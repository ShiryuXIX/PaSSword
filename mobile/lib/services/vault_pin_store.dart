import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'vault_crypto.dart';

class VaultPinStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'password_vault_pin_key',
    ),
  );

  String _storageKey(String userId) => 'vault-pin-key:$userId';

  Future<bool> hasPin(String userId) {
    return _storage.containsKey(key: _storageKey(userId));
  }

  Future<void> saveKey(String userId, Uint8List key, String pin) async {
    final record = await VaultCrypto.wrapKeyWithPin(key, pin, userId);
    await _storage.write(key: _storageKey(userId), value: jsonEncode(record));
  }

  Future<Uint8List?> readKey(String userId, String pin) async {
    final value = await _storage.read(key: _storageKey(userId));
    if (value == null) {
      return null;
    }

    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((item) => item is! String)) {
      throw const FormatException('El PIN guardado está dañado.');
    }
    return VaultCrypto.unwrapKeyWithPin(
      decoded.cast<String, String>(),
      pin,
      userId,
    );
  }

  Future<void> forgetPin(String userId) {
    return _storage.delete(key: _storageKey(userId));
  }
}
