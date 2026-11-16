import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/github_release_updater.dart';

void main() {
  group('GitHubReleaseUpdater.parseRelease', () {
    test('returns a newer APK version from the expected GitHub repository', () {
      final update = GitHubReleaseUpdater.parseRelease(
        release: _release,
        manifest: _manifest,
        currentBuildNumber: 3,
      );

      expect(update, isNotNull);
      expect(update!.displayVersion, '1.1.2');
      expect(update.buildNumber, 4);
      expect(update.releaseNotes, 'Cambios y correcciones.');
      expect(update.downloadUrl.host, 'github.com');
    });

    test('ignores a release that is not newer than the installed build', () {
      final update = GitHubReleaseUpdater.parseRelease(
        release: _release,
        manifest: _manifest,
        currentBuildNumber: 4,
      );

      expect(update, isNull);
    });

    test('rejects APK download URLs outside the configured repository', () {
      final release = {
        'assets': [
          {
            'name': 'PaSSword-Android.apk',
            'browser_download_url': 'https://github.com/attacker/PaSSword/releases/download/v1/PaSSword-Android.apk',
          },
        ],
      };

      expect(
        () => GitHubReleaseUpdater.parseRelease(
          release: release,
          manifest: _manifest,
          currentBuildNumber: 3,
        ),
        throwsA(isA<GitHubUpdateException>()),
      );
    });

    test('rejects an Android build without a matching APK asset', () {
      expect(
        () => GitHubReleaseUpdater.parseRelease(
          release: {'assets': []},
          manifest: _manifest,
          currentBuildNumber: 3,
        ),
        throwsA(isA<GitHubUpdateException>()),
      );
    });
  });
}

const _release = {
  'assets': [
    {
      'name': 'PaSSword-Android.apk',
      'browser_download_url': 'https://github.com/ShiryuXIX/PaSSword/releases/download/v1/PaSSword-Android.apk',
    },
  ],
};

const _manifest = {
  'version': '1.1.2',
  'buildNumber': 4,
  'releaseNotes': 'Cambios y correcciones.',
};
