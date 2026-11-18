import 'dart:typed_data';

import 'package:app/services/vault_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PINs must contain four to six digits', () async {
    final key = Uint8List(32);

    await expectLater(
      VaultCrypto.wrapKeyWithPin(key, '123', 'user-1'),
      throwsArgumentError,
    );
    await expectLater(
      VaultCrypto.wrapKeyWithPin(key, '1234567', 'user-1'),
      throwsArgumentError,
    );
    expect(await VaultCrypto.wrapKeyWithPin(key, '1234', 'user-1'), isNotEmpty);
    expect(
      await VaultCrypto.wrapKeyWithPin(key, '123456', 'user-1'),
      isNotEmpty,
    );
  });
}
