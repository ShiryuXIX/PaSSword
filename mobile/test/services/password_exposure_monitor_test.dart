import 'package:app/services/password_exposure_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('PwnedPasswordChecker', () {
    test('sends only the SHA-1 prefix and matches the local suffix', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.pwnedpasswords.com');
        expect(request.url.path, '/range/5BAA6');
        expect(request.url.path, isNot(contains('1E4')));
        expect(request.headers['Add-Padding'], 'true');
        return http.Response(
          'OTHER:8\r\n1E4C9B93F3F0682250B6CF8331B7EE68FD8:7\r\n',
          200,
        );
      });

      final count = await PwnedPasswordChecker(client: client)
          .countOccurrences('password');

      expect(count, 7);
    });

    test('returns zero when no suffix matches', () async {
      final checker = PwnedPasswordChecker(
        client: MockClient((_) async => http.Response('OTHER:1\r\n', 200)),
      );

      expect(await checker.countOccurrences('password'), 0);
    });
  });

  group('PasswordExposureMonitor', () {
    test(
      'checks changed passwords immediately and notifies only new findings',
      () async {
        final store = _MemoryStateStore();
        final checker = _FakeChecker({'exposed': 12, 'safe': 0});
        final monitor = PasswordExposureMonitor(store: store, checker: checker);
        final firstTime = DateTime.utc(2026, 1, 1);

        final first = await monitor.scan(
          userId: 'user',
          credentials: const [
            PasswordExposureCredential(
              id: 'one',
              password: 'exposed',
              revision: 'cipher-1',
            ),
          ],
          canCommit: () => true,
          now: firstTime,
        );
        expect(first!.newlyExposedIds, {'one'});

        final unchanged = await monitor.scan(
          userId: 'user',
          credentials: const [
            PasswordExposureCredential(
              id: 'one',
              password: 'exposed',
              revision: 'cipher-1',
            ),
          ],
          canCommit: () => true,
          now: firstTime.add(const Duration(days: 1)),
        );
        expect(unchanged!.counts, {'one': 12});
        expect(unchanged.newlyExposedIds, isEmpty);
        expect(checker.checkedPasswords, ['exposed']);

        final changed = await monitor.scan(
          userId: 'user',
          credentials: const [
            PasswordExposureCredential(
              id: 'one',
              password: 'safe',
              revision: 'cipher-2',
            ),
          ],
          canCommit: () => true,
          now: firstTime.add(const Duration(days: 2)),
        );
        expect(changed!.counts, {'one': 0});
        expect(changed.newlyExposedIds, isEmpty);
        expect(checker.checkedPasswords, ['exposed', 'safe']);
      },
    );

    test('rechecks all credentials after seven days', () async {
      final store = _MemoryStateStore();
      final checker = _FakeChecker({'safe': 0});
      final monitor = PasswordExposureMonitor(store: store, checker: checker);
      final firstTime = DateTime.utc(2026, 1, 1);
      const credential = PasswordExposureCredential(
        id: 'one',
        password: 'safe',
        revision: 'cipher-1',
      );

      await monitor.scan(
        userId: 'user',
        credentials: const [credential],
        canCommit: () => true,
        now: firstTime,
      );
      await monitor.scan(
        userId: 'user',
        credentials: const [credential],
        canCommit: () => true,
        now: firstTime.add(const Duration(days: 7)),
      );

      expect(checker.checkedPasswords, ['safe', 'safe']);
    });

    test('records an empty vault check without an API request', () async {
      final store = _MemoryStateStore();
      final checker = _FakeChecker({});
      final monitor = PasswordExposureMonitor(store: store, checker: checker);
      final now = DateTime.utc(2026, 1, 1);

      final result = await monitor.scan(
        userId: 'user',
        credentials: const [],
        canCommit: () => true,
        now: now,
      );

      expect(result!.nextFullCheckAt, now.add(const Duration(days: 7)));
      expect(checker.checkedPasswords, isEmpty);
    });
  });
}

class _MemoryStateStore implements PasswordExposureStateStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String userId) async => values[userId];

  @override
  Future<void> write(String userId, String value) async {
    values[userId] = value;
  }
}

class _FakeChecker implements PasswordExposureChecker {
  _FakeChecker(this.counts);

  final Map<String, int> counts;
  final List<String> checkedPasswords = [];

  @override
  Future<int> countOccurrences(String password) async {
    checkedPasswords.add(password);
    return counts[password] ?? 0;
  }
}
