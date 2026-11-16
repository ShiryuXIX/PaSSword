plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStoreFile = System.getenv("BOVEDA_ANDROID_KEYSTORE")
val releaseStorePassword = System.getenv("BOVEDA_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("BOVEDA_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("BOVEDA_ANDROID_KEY_PASSWORD")
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.substringAfterLast(":").contains("release", ignoreCase = true)
}

if (releaseBuildRequested) {
    require(!releaseStoreFile.isNullOrBlank()) {
        "Set BOVEDA_ANDROID_KEYSTORE to the production signing keystore path."
    }
    require(!releaseStorePassword.isNullOrBlank()) {
        "Set BOVEDA_ANDROID_KEYSTORE_PASSWORD before building a release."
    }
    require(!releaseKeyAlias.isNullOrBlank()) {
        "Set BOVEDA_ANDROID_KEY_ALIAS before building a release."
    }
    require(!releaseKeyPassword.isNullOrBlank()) {
        "Set BOVEDA_ANDROID_KEY_PASSWORD before building a release."
    }
}

android {
    namespace = "password.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "password.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("production") {
            if (!releaseStoreFile.isNullOrBlank()) {
                storeFile = file(releaseStoreFile)
            }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".dev"
        }
        getByName("release") {
            applicationIdSuffix = ".flutter"
            signingConfig = signingConfigs.getByName("production")
        }
    }

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
