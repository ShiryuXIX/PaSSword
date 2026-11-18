import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/firebase_service.dart';
import 'package:app/models/vault_metadata.dart';

void main() {
  test('decodes a versioned 256-bit recovery key', () {
    final expected = List<int>.generate(32, (index) => index);
    final key = FirebaseService.decodeRecoveryKey({
      'version': 1,
      'key': base64Encode(expected),
    });

    expect(key, expected);
  });

  test('rejects malformed, unsupported, or extra recovery-key fields', () {
    expect(
      () => FirebaseService.decodeRecoveryKey({'version': 2, 'key': 'AA=='}),
      throwsFormatException,
    );
    expect(
      () => FirebaseService.decodeRecoveryKey({'version': 1, 'key': 'AA=='}),
      throwsFormatException,
    );
    expect(
      () => FirebaseService.decodeRecoveryKey({
        'version': 1,
        'key': base64Encode(List<int>.filled(32, 0)),
        'extra': true,
      }),
      throwsFormatException,
    );
  });

  test('accepts both random recovery keys and legacy PBKDF2 metadata', () {
    final metadataBase = <String, Object?>{
      'version': 1,
      'keyGeneration': 1,
      'salt': base64Encode(List<int>.filled(16, 1)),
      'verifier': {
        'iv': base64Encode(List<int>.filled(12, 2)),
        'ciphertext': base64Encode(List<int>.filled(32, 3)),
      },
    };

    expect(
      VaultMetadata.fromMap({
        ...metadataBase,
        'kdf': vaultRecoveryKeyMode,
        'iterations': 0,
      }).keyGeneration,
      1,
    );
    expect(
      VaultMetadata.fromMap({
        ...metadataBase,
        'kdf': vaultKdfName,
        'iterations': vaultPbkdf2Iterations,
      }).keyGeneration,
      1,
    );
    expect(
      () => VaultMetadata.fromMap({
        ...metadataBase,
        'kdf': vaultRecoveryKeyMode,
        'iterations': vaultPbkdf2Iterations,
      }),
      throwsFormatException,
    );
  });
}
