import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const passwordExposureCheckInterval = Duration(days: 7);

class PasswordExposureCredential {
  const PasswordExposureCredential({
    required this.id,
    required this.password,
    required this.revision,
  });

  final String id;
  final String password;
  final String revision;
}

class PasswordExposureScanResult {
  const PasswordExposureScanResult({
    required this.counts,
    required this.newlyExposedIds,
    required this.nextFullCheckAt,
  });

  final Map<String, int> counts;
  final Set<String> newlyExposedIds;
  final DateTime nextFullCheckAt;
}

abstract interface class PasswordExposureChecker {
  Future<int> countOccurrences(String password);
}

class PwnedPasswordChecker implements PasswordExposureChecker {
  PwnedPasswordChecker({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<int> countOccurrences(String password) async {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    late final String hash;
    try {
      final digest = await Sha1().hash(passwordBytes);
      hash = digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
    }

    final prefix = hash.substring(0, 5);
    final suffix = hash.substring(5);
    final response = await _client
        .get(
          Uri.https('api.pwnedpasswords.com', '/range/$prefix'),
          headers: const {'Add-Padding': 'true', 'User-Agent': 'PaSSword'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError(
        'El servicio de comprobación respondió con HTTP ${response.statusCode}.',
      );
    }

    for (final line in const LineSplitter().convert(response.body)) {
      final parts = line.split(':');
      if (parts.length != 2 || parts.first.toUpperCase() != suffix) {
        continue;
      }
      final count = int.tryParse(parts.last);
      if (count == null || count < 0) {
        throw const FormatException(
          'El servicio de comprobación devolvió una respuesta no válida.',
        );
      }
      return count;
    }
    return 0;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

abstract interface class PasswordExposureStateStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String value);
}

class SecurePasswordExposureStateStore implements PasswordExposureStateStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'password_vault_exposure',
    ),
  );

  String _key(String userId) => 'password-exposure-v1:$userId';

  @override
  Future<String?> read(String userId) => _storage.read(key: _key(userId));

  @override
  Future<void> write(String userId, String value) =>
      _storage.write(key: _key(userId), value: value);
}

class PasswordExposureMonitor {
  PasswordExposureMonitor({required this.store, required this.checker});

  final PasswordExposureStateStore store;
  final PasswordExposureChecker checker;

  Future<PasswordExposureScanResult?> scan({
    required String userId,
    required List<PasswordExposureCredential> credentials,
    required bool Function() canCommit,
    DateTime? now,
  }) async {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final state = _decodeState(await store.read(userId));
    final lastFullCheck = state.lastFullCheck;
    final isDue =
        lastFullCheck == null ||
        currentTime.difference(lastFullCheck) >= passwordExposureCheckInterval;
    final previous = state.findings;
    final currentIds = credentials.map((item) => item.id).toSet();
    final hasDeletedFindings = previous.keys.any(
      (id) => !currentIds.contains(id),
    );
    final changed = isDue
        ? credentials
        : credentials
              .where((item) => previous[item.id]?.revision != item.revision)
              .toList(growable: false);

    final counts = <String, int>{};
    for (final credential in credentials) {
      final prior = previous[credential.id];
      if (!isDue && prior?.revision == credential.revision) {
        counts[credential.id] = prior!.count;
      }
    }
    if (!isDue && changed.isEmpty && !hasDeletedFindings) {
      return PasswordExposureScanResult(
        counts: counts,
        newlyExposedIds: const {},
        nextFullCheckAt: lastFullCheck.add(passwordExposureCheckInterval),
      );
    }

    final countsByPassword = <String, int>{};
    final newlyExposedIds = <String>{};
    for (final credential in changed) {
      final priorCount = countsByPassword[credential.password];
      final occurrenceCount =
          priorCount ?? await checker.countOccurrences(credential.password);
      countsByPassword[credential.password] = occurrenceCount;
      counts[credential.id] = occurrenceCount;
      final prior = previous[credential.id];
      if (occurrenceCount > 0 &&
          (prior == null ||
              prior.revision != credential.revision ||
              prior.count == 0)) {
        newlyExposedIds.add(credential.id);
      }
    }

    if (!canCommit()) {
      return null;
    }

    final findings = <String, _ExposureFinding>{};
    for (final credential in credentials) {
      final count = counts[credential.id];
      if (count != null) {
        findings[credential.id] = _ExposureFinding(
          revision: credential.revision,
          count: count,
        );
      }
    }
    final nextFullCheck = isDue ? currentTime : lastFullCheck;
    await store.write(
      userId,
      jsonEncode({
        'version': 1,
        'lastFullCheck': nextFullCheck.millisecondsSinceEpoch,
        'findings': {
          for (final entry in findings.entries)
            entry.key: {
              'revision': entry.value.revision,
              'count': entry.value.count,
            },
        },
      }),
    );

    return PasswordExposureScanResult(
      counts: counts,
      newlyExposedIds: newlyExposedIds,
      nextFullCheckAt: nextFullCheck.add(passwordExposureCheckInterval),
    );
  }

  _ExposureState _decodeState(String? value) {
    if (value == null) {
      return const _ExposureState(lastFullCheck: null, findings: {});
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['findings'] is! Map ||
        (decoded['lastFullCheck'] != null &&
            decoded['lastFullCheck'] is! int)) {
      throw const FormatException(
        'El estado local de comprobación está dañado.',
      );
    }

    final findings = <String, _ExposureFinding>{};
    for (final entry in (decoded['findings'] as Map).entries) {
      final finding = entry.value;
      if (entry.key is! String ||
          finding is! Map ||
          finding['revision'] is! String ||
          finding['count'] is! int ||
          finding['count'] < 0) {
        throw const FormatException(
          'El estado local de comprobación está dañado.',
        );
      }
      findings[entry.key as String] = _ExposureFinding(
        revision: finding['revision'] as String,
        count: finding['count'] as int,
      );
    }
    final timestamp = decoded['lastFullCheck'] as int?;
    return _ExposureState(
      lastFullCheck: timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      findings: findings,
    );
  }
}

class _ExposureState {
  const _ExposureState({required this.lastFullCheck, required this.findings});

  final DateTime? lastFullCheck;
  final Map<String, _ExposureFinding> findings;
}

class _ExposureFinding {
  const _ExposureFinding({required this.revision, required this.count});

  final String revision;
  final int count;
}
