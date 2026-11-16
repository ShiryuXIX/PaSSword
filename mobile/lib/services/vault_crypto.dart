import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../models/vault_metadata.dart';

class VaultCrypto {
  static final _pbkdf2 = Pbkdf2.hmacSha256(
    iterations: vaultPbkdf2Iterations,
    bits: 256,
  );
  static final _aes = AesGcm.with256bits();
  static final _secureRandom = Random.secure();

  static Uint8List createSalt() => _randomBytes(16);

  static String normalizeMasterPassword(String password) =>
      unorm.nfkc(password);

  static Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    if (password.isEmpty || password.length > 1024 || salt.length != 16) {
      throw ArgumentError('La contraseña maestra o la sal no es válida.');
    }

    final key = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(normalizeMasterPassword(password))),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<Map<String, String>> wrapKeyWithPin(
    Uint8List vaultKey,
    String pin,
    String ownerId,
  ) async {
    _validateKey(vaultKey);
    _validatePin(pin);
    _validateIdentifier(ownerId);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final wrappingKey = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    final box = await _aes.encrypt(
      vaultKey,
      secretKey: wrappingKey,
      nonce: nonce,
      aad: utf8.encode('boveda:pin:v1:$ownerId'),
    );
    return {
      'version': '1',
      'salt': base64.encode(salt),
      'iv': base64.encode(nonce),
      'ciphertext': base64.encode(_combine(box)),
    };
  }

  static Future<Uint8List> unwrapKeyWithPin(
    Map<String, String> record,
    String pin,
    String ownerId,
  ) async {
    _validatePin(pin);
    _validateIdentifier(ownerId);
    if (record['version'] != '1') {
      throw const FormatException('El PIN guardado no es compatible.');
    }

    final salt = _decodeCiphertext(record['salt'] ?? '');
    final nonce = _decodeCiphertext(record['iv'] ?? '');
    final ciphertext = _decodeCiphertext(record['ciphertext'] ?? '');
    if (salt.length != 16 || nonce.length != 12 || ciphertext.length != 48) {
      throw const FormatException('El PIN guardado está dañado.');
    }
    final wrappingKey = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    try {
      final plaintext = await _aes.decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - 16),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
        ),
        secretKey: wrappingKey,
        aad: utf8.encode('boveda:pin:v1:$ownerId'),
      );
      try {
        final key = Uint8List.fromList(plaintext);
        _validateKey(key);
        return key;
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
    } on SecretBoxAuthenticationError {
      throw StateError('El PIN no es correcto.');
    }
  }

  static Future<Map<String, String>> createVerifier(
    Uint8List key,
    String ownerId,
  ) async {
    _validateKey(key);
    _validateIdentifier(ownerId);
    final nonce = _randomBytes(12);
    final box = await _aes.encrypt(
      utf8.encode('boveda-vault-verifier-v1'),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode('boveda:verifier:v1:$ownerId'),
    );
    return {
      'iv': base64.encode(nonce),
      'ciphertext': base64.encode(_combine(box)),
    };
  }

  static Future<bool> verifyKey(
    Uint8List key,
    String ownerId,
    VaultMetadata metadata,
  ) async {
    try {
      _validateKey(key);
      _validateIdentifier(ownerId);
      final box = SecretBox(
        metadata.verifierCiphertext.sublist(
          0,
          metadata.verifierCiphertext.length - 16,
        ),
        nonce: metadata.verifierIv,
        mac: Mac(
          metadata.verifierCiphertext.sublist(
            metadata.verifierCiphertext.length - 16,
          ),
        ),
      );
      final plaintext = await _aes.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: utf8.encode('boveda:verifier:v1:$ownerId'),
      );
      return utf8.decode(plaintext) == 'boveda-vault-verifier-v1';
    } on Object {
      return false;
    }
  }

  static Future<Map<String, Object?>> encryptCredential(
    Uint8List key,
    String ownerId,
    String credentialId,
    Map<String, String> credential, {
    int keyGeneration = 1,
  }) async {
    _validateContext(ownerId, credentialId);
    _validateKey(key);
    _validateCredential(credential);
    _validateGeneration(keyGeneration);

    final nonce = _randomBytes(12);
    final plaintext = utf8.encode(jsonEncode(credential));
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _credentialAad(ownerId, credentialId, keyGeneration),
    );
    return {
      'version': 1,
      'keyGeneration': keyGeneration,
      'iv': base64.encode(nonce),
      'ciphertext': base64.encode(_combine(box)),
    };
  }

  static Future<Map<String, String>> decryptCredential(
    Uint8List key,
    String ownerId,
    String credentialId,
    Map<String, Object?> document,
  ) async {
    _validateContext(ownerId, credentialId);
    _validateKey(key);

    try {
      if (document['version'] != 1 ||
          document['iv'] is! String ||
          document['ciphertext'] is! String) {
        throw const FormatException();
      }

      final generationValue = document['keyGeneration'];
      if (generationValue != null &&
          (generationValue is! int ||
              generationValue < 1 ||
              generationValue > 2147483647)) {
        throw const FormatException();
      }

      final nonce = _decodeCiphertext(document['iv']! as String);
      final ciphertext = _decodeCiphertext(document['ciphertext']! as String);
      if (nonce.length != 12 || ciphertext.length <= 16) {
        throw const FormatException();
      }

      final generation = generationValue as int?;
      final box = SecretBox(
        ciphertext.sublist(0, ciphertext.length - 16),
        nonce: nonce,
        mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
      );
      final plaintext = await _aes.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: generation == null
            ? utf8.encode('boveda:credential:v1:$ownerId:$credentialId')
            : _credentialAad(ownerId, credentialId, generation),
      );
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final credential = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.value is! String) {
          throw const FormatException();
        }
        credential[entry.key] = entry.value as String;
      }
      _validateCredential(credential);
      return credential;
    } on Object {
      throw StateError(
        'No se pudo descifrar el acceso. La contraseña maestra puede ser incorrecta o el documento estar dañado.',
      );
    }
  }

  static Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _secureRandom.nextInt(256)),
    );
  }

  static List<int> _combine(SecretBox box) => [
    ...box.cipherText,
    ...box.mac.bytes,
  ];

  static Uint8List _decodeCiphertext(String value) {
    if (!RegExp(
      r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
    ).hasMatch(value)) {
      throw const FormatException();
    }
    return Uint8List.fromList(base64.decode(value));
  }

  static List<int> _credentialAad(
    String ownerId,
    String credentialId,
    int generation,
  ) => utf8.encode('boveda:credential:v2:$ownerId:$credentialId:$generation');

  static void _validateKey(Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('La llave de la bóveda no tiene un formato válido.');
    }
  }

  static void _validateIdentifier(String value) {
    if (value.isEmpty || value.length > 128) {
      throw ArgumentError('El identificador no tiene un formato válido.');
    }
  }

  static void _validatePin(String pin) {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('El PIN de PaSSword debe tener 4 cifras.');
    }
  }

  static void _validateContext(String ownerId, String credentialId) {
    _validateIdentifier(ownerId);
    _validateIdentifier(credentialId);
  }

  static void _validateGeneration(int generation) {
    if (generation < 1 || generation > 2147483647) {
      throw ArgumentError('La generación de llave no es válida.');
    }
  }

  static void _validateCredential(Map<String, String> credential) {
    final keys = credential.keys.toList()..sort();
    if (keys.length != 3 ||
        keys[0] != 'email' ||
        keys[1] != 'password' ||
        keys[2] != 'site' ||
        credential.values.any((value) => value.length > 10000)) {
      throw ArgumentError(
        'Cada acceso debe contener sitio, email y contraseña válidos.',
      );
    }
  }
}
