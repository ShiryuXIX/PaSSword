$ErrorActionPreference = 'Stop'

$firebaseProject = 'gestor-pass-b60d6'
$firebaseAndroidAppId = '1:899324045825:android:ebd3680a4801d2b32fae00'
$googleServerClientId = '899324045825-s28q0rrt4nlfjoptja33boggf0a1etfb.apps.googleusercontent.com'
$keyAlias = 'passwordappflutter'
$keystorePath = Join-Path $env:USERPROFILE '.bubblewrap\password-app-flutter.jks'
$apkPath = Join-Path $PSScriptRoot 'PaSSword-app.apk'
$certificatePath = Join-Path ([IO.Path]::GetTempPath()) (
    'password-app-flutter-{0}.cer' -f [Guid]::NewGuid().ToString('N')
)

function Invoke-FirebaseCli {
    param([string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $commandOutput = & firebase @Arguments 2>&1
        $commandExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    [PSCustomObject]@{
        ExitCode = $commandExitCode
        Output = @($commandOutput)
    }
}

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCommand -or [string]::IsNullOrWhiteSpace($flutterCommand.Source)) {
    throw 'Flutter was not found on PATH.'
}
$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytoolCommand) {
    throw 'keytool was not found on PATH. Install or configure a JDK first.'
}
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    throw 'Firebase CLI was not found on PATH.'
}

$flutterSdkPath = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
$projectRoot = Split-Path -Parent $PSScriptRoot
$localPropertiesPath = Join-Path $PSScriptRoot 'android\local.properties'
$localPropertiesContents = [IO.File]::ReadAllText($localPropertiesPath)
$androidSdkMatch = [regex]::Match(
    $localPropertiesContents,
    '(?m)^sdk\.dir=(.+)$'
)
$androidSdkPath = $null
foreach ($candidate in @(
    $env:ANDROID_SDK_ROOT,
    $env:ANDROID_HOME,
    $(if ($androidSdkMatch.Success) {
        $androidSdkMatch.Groups[1].Value.Replace('\\', '\')
    })
)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and
        (Test-Path -LiteralPath $candidate -PathType Container)) {
        $androidSdkPath = $candidate
        break
    }
}
if (-not $androidSdkPath) {
    throw 'Could not locate the Android SDK from ANDROID_SDK_ROOT, ANDROID_HOME, or local.properties.'
}
$buildToolsPath = Get-ChildItem -LiteralPath (Join-Path $androidSdkPath 'build-tools') `
    -Directory |
    Sort-Object Name -Descending |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat')) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe'))
    } |
    Select-Object -First 1
if (-not $buildToolsPath) {
    throw 'Android SDK build-tools with apksigner and aapt were not found.'
}
$apksignerPath = Join-Path $buildToolsPath.FullName 'apksigner.bat'
$aaptPath = Join-Path $buildToolsPath.FullName 'aapt.exe'
$storePassword = $null
$keyPassword = $null
$storeBstr = [IntPtr]::Zero
$keyBstr = [IntPtr]::Zero
$originalLocation = Get-Location
$originalGradleOpts = $env:GRADLE_OPTS
$createdDrives = @()
$localPropertiesChanged = $false
$flutterLauncherPath = $null

try {
    $keystoreDirectory = Split-Path -Parent $keystorePath
    if (-not (Test-Path -LiteralPath $keystoreDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $keystoreDirectory | Out-Null
    }

    if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
        Write-Output 'Creating a new Android signing key. Save its password securely; it cannot be recovered.'
        & $keytoolCommand.Source -genkeypair -v `
            -keystore $keystorePath `
            -alias $keyAlias `
            -keyalg RSA `
            -keysize 2048 `
            -validity 10000 `
            -dname 'CN=PaSSword Android, O=PaSSword, C=ES'
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the signing keystore (exit code $LASTEXITCODE)."
        }
    }

    Write-Output 'Exporting the public certificate to register its fingerprints with Firebase.'
    & $keytoolCommand.Source -exportcert `
        -keystore $keystorePath `
        -alias $keyAlias `
        -file $certificatePath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not export the signing certificate (exit code $LASTEXITCODE)."
    }

    $certificateBytes = [IO.File]::ReadAllBytes($certificatePath)
    $sha1 = [Security.Cryptography.SHA1]::Create()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $sha1Fingerprint = [BitConverter]::ToString(
            $sha1.ComputeHash($certificateBytes)
        ).Replace('-', ':')
        $sha256Fingerprint = [BitConverter]::ToString(
            $sha256.ComputeHash($certificateBytes)
        ).Replace('-', ':')
    }
    finally {
        $sha1.Dispose()
        $sha256.Dispose()
    }

    $shaListCall = Invoke-FirebaseCli -Arguments @(
        'apps:android:sha:list',
        $firebaseAndroidAppId,
        '--project',
        $firebaseProject,
        '--json'
    )
    if ($shaListCall.ExitCode -ne 0) {
        throw "Could not read the Firebase app fingerprints: $($shaListCall.Output -join ' ')"
    }
    $shaListText = $shaListCall.Output -join [Environment]::NewLine
    $jsonStart = $shaListText.IndexOf('{')
    $jsonEnd = $shaListText.LastIndexOf('}')
    if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
        throw 'Firebase CLI returned an unreadable fingerprint list.'
    }
    $shaList = $shaListText.Substring($jsonStart, $jsonEnd - $jsonStart + 1) |
        ConvertFrom-Json
    if ($shaList.status -ne 'success') {
        throw "Firebase could not list signing fingerprints: $($shaList.error)"
    }
    $registeredFingerprints = @($shaList.result | ForEach-Object { $_.shaHash })

    foreach ($fingerprint in @($sha1Fingerprint, $sha256Fingerprint)) {
        if ($registeredFingerprints -contains $fingerprint) {
            continue
        }
        $shaCreateCall = Invoke-FirebaseCli -Arguments @(
            'apps:android:sha:create',
            $firebaseAndroidAppId,
            $fingerprint,
            '--project',
            $firebaseProject
        )
        if ($shaCreateCall.ExitCode -ne 0) {
            throw "Could not register signing fingerprint $fingerprint with Firebase: $($shaCreateCall.Output -join ' ')"
        }
        $shaCreateCall.Output | ForEach-Object { Write-Output $_ }
    }

    $storePassword = Read-Host 'New keystore password' -AsSecureString
    $keyPassword = Read-Host 'New signing key password' -AsSecureString
    $storeBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($storePassword)
    $keyBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyPassword)

    $env:BOVEDA_ANDROID_KEYSTORE = $keystorePath
    $env:BOVEDA_ANDROID_KEYSTORE_PASSWORD =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($storeBstr)
    $env:BOVEDA_ANDROID_KEY_ALIAS = $keyAlias
    $env:BOVEDA_ANDROID_KEY_PASSWORD =
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyBstr)
    $env:GRADLE_OPTS = (
        "$originalGradleOpts " +
        '-Dorg.gradle.daemon=false ' +
        '-Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process ' +
        '-Dorg.gradle.project.kotlin.incremental=false'
    ).Trim()

    $occupiedDrives = (Get-PSDrive -PSProvider FileSystem).Name
    $availableDrives = @('Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S', 'R', 'Q') |
        Where-Object { $occupiedDrives -notcontains $_ } |
        Select-Object -First 2
    if (@($availableDrives).Count -lt 2) {
        throw 'Two free drive letters are required for temporary project and Flutter paths.'
    }

    $projectDrive = "$($availableDrives[0]):"
    $flutterDrive = "$($availableDrives[1]):"
    & subst.exe $projectDrive $projectRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create temporary project drive $projectDrive."
    }
    $createdDrives += $projectDrive

    & subst.exe $flutterDrive $flutterSdkPath
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create temporary Flutter drive $flutterDrive."
    }
    $createdDrives += $flutterDrive

    $escapedFlutterDrive = $flutterDrive.Replace('\', '\\') + '\\'
    if ([regex]::IsMatch($localPropertiesContents, '(?m)^flutter\.sdk=.*$')) {
        $temporaryLocalProperties = [regex]::Replace(
            $localPropertiesContents,
            '(?m)^flutter\.sdk=.*$',
            "flutter.sdk=$escapedFlutterDrive"
        )
    }
    else {
        $temporaryLocalProperties = "$localPropertiesContents`nflutter.sdk=$escapedFlutterDrive`n"
    }
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText(
        $localPropertiesPath,
        $temporaryLocalProperties,
        $utf8WithoutBom
    )
    $localPropertiesChanged = $true

    $mobileProjectPath = Join-Path $projectDrive 'mobile'
    Set-Location -LiteralPath $mobileProjectPath
    $flutterArgs = @(
        'build',
        'apk',
        '--release',
        '--no-pub',
        "--dart-define=FIREBASE_ANDROID_APP_ID=$firebaseAndroidAppId",
        "--dart-define=GOOGLE_SERVER_CLIENT_ID=$googleServerClientId"
    )
    $flutterPath = Join-Path $flutterDrive 'bin\flutter.bat'
    $flutterLauncherPath = Join-Path $projectDrive (
        '.flutter-release-{0}.cmd' -f [Guid]::NewGuid().ToString('N')
    )
    $flutterCommandLine = '"{0}" {1}' -f $flutterPath, ($flutterArgs -join ' ')
    $launcherContents = "@echo off`r`ncall $flutterCommandLine`r`nexit /b %errorlevel%`r`n"
    [IO.File]::WriteAllText($flutterLauncherPath, $launcherContents)

    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = $env:ComSpec
    $processInfo.Arguments = "/d /s /c `"`"$flutterLauncherPath`"`""
    $processInfo.WorkingDirectory = $mobileProjectPath
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $flutterProcess = New-Object Diagnostics.Process
    $flutterProcess.StartInfo = $processInfo
    if (-not $flutterProcess.Start()) {
        throw 'Could not start the Flutter release build process.'
    }
    $stdoutTask = $flutterProcess.StandardOutput.ReadToEndAsync()
    $stderrTask = $flutterProcess.StandardError.ReadToEndAsync()
    $flutterProcess.WaitForExit()
    $flutterExitCode = $flutterProcess.ExitCode
    $flutterOutput = $stdoutTask.Result
    $flutterError = $stderrTask.Result
    if (-not [string]::IsNullOrWhiteSpace($flutterOutput)) {
        Write-Host $flutterOutput
    }
    if (-not [string]::IsNullOrWhiteSpace($flutterError)) {
        Write-Host $flutterError
    }
    if ($flutterExitCode -ne 0) {
        throw "Flutter release build failed with exit code $flutterExitCode."
    }

    $apkShortPath = Join-Path $projectDrive 'mobile\build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $apkShortPath -PathType Leaf)) {
        throw "Flutter did not create the expected APK: $apkPath"
    }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $apkCertificateOutput = & $apksignerPath verify --print-certs $apkShortPath 2>&1
        $apkVerifyExitCode = $LASTEXITCODE
        $apkPackageOutput = & $aaptPath dump badging $apkShortPath 2>&1
        $apkPackageExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($apkVerifyExitCode -ne 0) {
        throw "APK signature verification failed: $($apkCertificateOutput -join ' ')"
    }
    if ($apkPackageExitCode -ne 0) {
        throw "Could not read the APK package id: $($apkPackageOutput -join ' ')"
    }
    $apkPackageLine = $apkPackageOutput | Select-Object -First 1
    if ($apkPackageLine -notmatch "package: name='password\.app\.flutter'") {
        throw "Unexpected APK package id: $apkPackageLine"
    }
    $apkCertificateText = $apkCertificateOutput -join [Environment]::NewLine
    $apkFingerprintMatch = [regex]::Match(
        $apkCertificateText,
        '(?im)^\s*Signer #\d+ certificate SHA-256 digest:\s*(?<fingerprint>[0-9A-F]{64})\s*$'
    )
    if (-not $apkFingerprintMatch.Success) {
        throw 'Could not find the APK SHA-256 signing fingerprint.'
    }
    $apkFingerprint = $apkFingerprintMatch.Groups['fingerprint'].Value.ToLowerInvariant()
    $expectedApkFingerprint = $sha256Fingerprint.Replace(':', '').ToLowerInvariant()
    if ($apkFingerprint -ne $expectedApkFingerprint) {
        throw "APK signing key mismatch. Expected $sha256Fingerprint; got $apkFingerprint."
    }

    Copy-Item -LiteralPath $apkShortPath -Destination $apkPath -Force
    Write-Output "Production APK verified for password.app.flutter: $apkPath"
    Write-Output "Signing fingerprint: $apkFingerprint"
    Write-Warning 'Back up the new keystore and its password securely. Losing either prevents future updates.'
}
finally {
    Set-Location -LiteralPath $originalLocation
    Remove-Item Env:BOVEDA_ANDROID_KEYSTORE -ErrorAction SilentlyContinue
    Remove-Item Env:BOVEDA_ANDROID_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:BOVEDA_ANDROID_KEY_ALIAS -ErrorAction SilentlyContinue
    Remove-Item Env:BOVEDA_ANDROID_KEY_PASSWORD -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($originalGradleOpts)) {
        Remove-Item Env:GRADLE_OPTS -ErrorAction SilentlyContinue
    }
    else {
        $env:GRADLE_OPTS = $originalGradleOpts
    }
    if ($storeBstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($storeBstr)
    }
    if ($keyBstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyBstr)
    }
    if ($localPropertiesChanged) {
        [IO.File]::WriteAllText(
            $localPropertiesPath,
            $localPropertiesContents,
            $utf8WithoutBom
        )
    }
    if (Test-Path -LiteralPath $certificatePath -PathType Leaf) {
        Remove-Item -LiteralPath $certificatePath
    }
    if ($flutterLauncherPath -and (Test-Path -LiteralPath $flutterLauncherPath)) {
        Remove-Item -LiteralPath $flutterLauncherPath
    }
    foreach ($drive in $createdDrives) {
        & subst.exe $drive /D
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not remove temporary Flutter drive $drive."
        }
    }
}
