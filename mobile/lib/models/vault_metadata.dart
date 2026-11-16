import 'dart:convert';
import 'dart:typed_data';

const vaultKdfName = 'PBKDF2-SHA-256';
const vaultPbkdf2Iterations = 600000;

class VaultMetadata {
  const VaultMetadata({
    required this.salt,
    required this.verifierIv,
    required this.verifierCiphertext,
    required this.keyGeneration,
    required this.raw,
  });

  final Uint8List salt;
  final Uint8List verifierIv;
  final Uint8List verifierCiphertext;
  final int keyGeneration;
  final Map<String, Object?> raw;

  factory VaultMetadata.fromMap(Map<String, Object?> data) {
    if (data['version'] != 1 ||
        data['kdf'] != vaultKdfName ||
        data['iterations'] != vaultPbkdf2Iterations) {
      throw const FormatException(
        'La configuración de esta bóveda no es compatible.',
      );
    }

    final salt = _decodeBase64(data['salt'], 'sal');
    final verifier = data['verifier'];
    if (salt.length != 16 ||
        verifier is! Map ||
        verifier['iv'] is! String ||
        verifier['ciphertext'] is! String) {
      throw const FormatException(
        'La configuración de esta bóveda está dañada.',
      );
    }

    final verifierIv = _decodeBase64(verifier['iv'], 'nonce del verificador');
    final verifierCiphertext = _decodeBase64(
      verifier['ciphertext'],
      'verificador',
    );
    final generation = data['keyGeneration'] ?? 1;
    if (verifierIv.length != 12 ||
        verifierCiphertext.length <= 16 ||
        generation is! int ||
        generation < 1 ||
        generation > 2147483647) {
      throw const FormatException(
        'La configuración de esta bóveda está dañada.',
      );
    }

    return VaultMetadata(
      salt: salt,
      verifierIv: verifierIv,
      verifierCiphertext: verifierCiphertext,
      keyGeneration: generation,
      raw: Map<String, Object?>.unmodifiable(data),
    );
  }

  bool get rotationInProgress => raw['rotationInProgress'] == true;
}

Uint8List _decodeBase64(Object? value, String field) {
  if (value is! String ||
      !RegExp(
        r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
      ).hasMatch(value)) {
    throw FormatException('El campo $field no tiene un formato válido.');
  }

  try {
    return Uint8List.fromList(base64.decode(value));
  } on FormatException {
    throw FormatException('El campo $field no tiene un formato válido.');
  }
}
