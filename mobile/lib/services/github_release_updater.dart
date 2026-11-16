import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class GitHubUpdateException implements Exception {
  const GitHubUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GitHubReleaseUpdate {
  const GitHubReleaseUpdate({
    required this.displayVersion,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  final String displayVersion;
  final int buildNumber;
  final String releaseNotes;
  final Uri downloadUrl;
}

class GitHubReleaseUpdater {
  GitHubReleaseUpdater({http.Client? client})
    : _client = client ?? http.Client();

  static const _owner = 'ShiryuXIX';
  static const _repository = 'PaSSword';
  static const _apkName = 'PaSSword-Android.apk';
  static const _manifestName = 'android-update.json';
  static final _latestReleaseUri = Uri.https(
    'api.github.com',
    '/repos/$_owner/$_repository/releases/latest',
  );

  final http.Client _client;

  Future<GitHubReleaseUpdate?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuildNumber = int.tryParse(packageInfo.buildNumber);
    if (currentBuildNumber == null) {
      throw const GitHubUpdateException(
        'No se pudo leer el número de versión instalado.',
      );
    }

    final response = await _client
        .get(
          _latestReleaseUri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'PaSSword-Android',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw GitHubUpdateException(
        'GitHub respondió con el estado ${response.statusCode}.',
      );
    }

    final release = _decodeObject(response.body);
    final manifestUrl = _findAssetUrl(release['assets'], _manifestName);
    final manifestResponse = await _client
        .get(manifestUrl, headers: const {'User-Agent': 'PaSSword-Android'})
        .timeout(const Duration(seconds: 15));
    if (manifestResponse.statusCode != 200) {
      throw GitHubUpdateException(
        'No se pudo leer la información de la versión (estado '
        '${manifestResponse.statusCode}).',
      );
    }

    final manifest = _decodeObject(manifestResponse.body);
    return parseRelease(
      release: release,
      manifest: manifest,
      currentBuildNumber: currentBuildNumber,
    );
  }

  static GitHubReleaseUpdate? parseRelease({
    required Map<String, dynamic> release,
    required Map<String, dynamic> manifest,
    required int currentBuildNumber,
  }) {
    final version = manifest['version'];
    final buildNumber = manifest['buildNumber'];
    if (version is! String || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw const GitHubUpdateException(
        'La release no contiene una versión Android válida.',
      );
    }
    if (buildNumber is! int || buildNumber < 1) {
      throw const GitHubUpdateException(
        'La release no contiene un código Android válido.',
      );
    }
    if (buildNumber <= currentBuildNumber) return null;

    final notes = manifest['releaseNotes'];
    return GitHubReleaseUpdate(
      displayVersion: version,
      buildNumber: buildNumber,
      releaseNotes: notes is String ? notes.trim() : '',
      downloadUrl: _findAssetUrl(release['assets'], _apkName),
    );
  }

  Future<File> downloadUpdate(GitHubReleaseUpdate update) async {
    final request = http.Request('GET', update.downloadUrl)
      ..headers['User-Agent'] = 'PaSSword-Android';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw GitHubUpdateException(
        'GitHub no pudo descargar la APK (estado ${response.statusCode}).',
      );
    }

    final directory = await getTemporaryDirectory();
    final apk = File(
      '${directory.path}${Platform.pathSeparator}PaSSword-update.apk',
    );
    if (await apk.exists()) await apk.delete();

    var validDownload = false;
    try {
      await response.stream.pipe(apk.openWrite());
      final downloadedBytes = await apk.length();
      if (downloadedBytes == 0 ||
          (response.contentLength != null &&
              downloadedBytes != response.contentLength)) {
        throw const GitHubUpdateException('La APK descargada está incompleta.');
      }
      validDownload = true;
      return apk;
    } finally {
      if (!validDownload && await apk.exists()) await apk.delete();
    }
  }

  Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const GitHubUpdateException(
        'La respuesta de GitHub no tiene un formato válido.',
      );
    }
    return decoded;
  }

  static Uri _findAssetUrl(dynamic assetsValue, String assetName) {
    if (assetsValue is! List) {
      throw GitHubUpdateException('La release no contiene $assetName.');
    }
    final matches = assetsValue.where(
      (asset) => asset is Map && asset['name'] == assetName,
    );
    if (matches.length != 1) {
      throw GitHubUpdateException(
        'La release debe incluir exactamente un archivo $assetName.',
      );
    }

    final asset = matches.single as Map;
    final rawUrl = asset['browser_download_url'];
    final url = Uri.tryParse(rawUrl is String ? rawUrl : '');
    final expectedPath = '/$_owner/$_repository/releases/download/';
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith(expectedPath)) {
      throw GitHubUpdateException(
        'El enlace de descarga de $assetName no es válido.',
      );
    }
    return url;
  }

  void close() => _client.close();
}
