import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class VaultKeyStore {
  static const _regularStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'password_vault_regular_key',
    ),
  );
  static const _biometricStorage = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.biometricOrDeviceCredential,
      biometricPromptTitle: 'Desbloquear PaSSword',
      biometricPromptSubtitle: 'Confirma tu identidad para abrir la bóveda',
      storageNamespace: 'password_vault_biometric_key',
    ),
  );

  String _storageKey(String userId) => 'vault-key:$userId';

  Future<bool> hasBiometricKey(String userId) {
    return _biometricStorage.containsKey(key: _storageKey(userId));
  }

  Future<Uint8List?> readKey(String userId, {required bool biometric}) async {
    final storage = biometric ? _biometricStorage : _regularStorage;
    final value = await storage.read(key: _storageKey(userId));
    if (value == null) {
      return null;
    }
    final bytes = Uint8List.fromList(base64.decode(value));
    if (bytes.length != 32) {
      bytes.fillRange(0, bytes.length, 0);
      await storage.delete(key: _storageKey(userId));
      throw const FormatException(
        'La llave local de esta bóveda está dañada. Desbloquéala con la contraseña maestra.',
      );
    }
    return bytes;
  }

  Future<void> saveKey(
    String userId,
    Uint8List key, {
    required bool biometric,
  }) async {
    if (key.length != 32) {
      throw ArgumentError('La llave de la bóveda no tiene un formato válido.');
    }
    final selected = biometric ? _biometricStorage : _regularStorage;
    final other = biometric ? _regularStorage : _biometricStorage;
    await selected.write(key: _storageKey(userId), value: base64.encode(key));
    await other.delete(key: _storageKey(userId));
  }

  Future<void> forgetBiometricKey(String userId) {
    return _biometricStorage.delete(key: _storageKey(userId));
  }

  Future<void> forgetLegacyKey(String userId) {
    return _regularStorage.delete(key: _storageKey(userId));
  }

  Future<void> forgetKey(String userId) async {
    await Future.wait([
      _regularStorage.delete(key: _storageKey(userId)),
      _biometricStorage.delete(key: _storageKey(userId)),
    ]);
  }
}
