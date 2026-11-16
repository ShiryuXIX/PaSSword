import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/vault_metadata.dart';

class RemoteCredential {
  const RemoteCredential({
    required this.id,
    required this.document,
    required this.hasPendingWrites,
  });

  final String id;
  final Map<String, Object?> document;
  final bool hasPendingWrites;
}

class CredentialSnapshot {
  const CredentialSnapshot({
    required this.items,
    required this.fromCache,
    required this.hasPendingWrites,
  });

  final List<RemoteCredential> items;
  final bool fromCache;
  final bool hasPendingWrites;
}

class FirebaseService {
  FirebaseService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;
  static final _random = Random.secure();

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signInWithGoogle() async {
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google no devolvió un token de identidad válido.');
    }
    await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  DocumentReference<Map<String, dynamic>> _metadataRef(String uid) =>
      _firestore.doc('users/$uid/vault/meta');

  CollectionReference<Map<String, dynamic>> _credentialsRef(String uid) =>
      _firestore.collection('users/$uid/credentials');

  Future<Map<String, Object?>?> readMetadata(String uid) async {
    final reference = _metadataRef(uid);
    try {
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      return snapshot.exists ? snapshot.data() : null;
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable' && error.code != 'deadline-exceeded') {
        rethrow;
      }
      final snapshot = await reference.get(
        const GetOptions(source: Source.cache),
      );
      return snapshot.exists ? snapshot.data() : null;
    }
  }

  Future<void> createMetadata({
    required String uid,
    required Uint8List salt,
    required Map<String, String> verifier,
  }) async {
    final reference = _metadataRef(uid);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) {
        throw StateError(
          'La bóveda ya existe. Vuelve a cargarla e intenta desbloquearla.',
        );
      }
      transaction.set(reference, {
        'version': 1,
        'kdf': vaultKdfName,
        'iterations': vaultPbkdf2Iterations,
        'keyGeneration': 1,
        'salt': base64Encode(salt),
        'verifier': verifier,
      });
    });
  }

  Stream<CredentialSnapshot> watchCredentials(String uid) {
    return _credentialsRef(uid)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
          return CredentialSnapshot(
            items: snapshot.docs
                .map(
                  (document) => RemoteCredential(
                    id: document.id,
                    document: Map<String, Object?>.from(document.data()),
                    hasPendingWrites: document.metadata.hasPendingWrites,
                  ),
                )
                .toList(growable: false),
            fromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          );
        });
  }

  Future<String> createCredential(
    String uid,
    Future<Map<String, Object?>> Function(String id) encrypt,
  ) async {
    final reference = _credentialsRef(uid).doc();
    await reference.set(await encrypt(reference.id));
    return reference.id;
  }

  Future<void> saveCredential(
    String uid,
    String id,
    Map<String, Object?> document,
  ) {
    return _credentialsRef(uid).doc(id).set(document);
  }

  Future<void> deleteCredential(String uid, String id) {
    return _credentialsRef(uid).doc(id).delete();
  }

  Future<void> reencryptVault({
    required String uid,
    required Map<String, Object?> expectedMetadata,
    required Map<String, Object?> nextMetadata,
    required String rotationId,
    required Future<Map<String, Object?>> Function(
      String oldId,
      String newId,
      Map<String, Object?> oldDocument,
    )
    encryptForNewId,
  }) async {
    final metadataReference = _metadataRef(uid);
    final collection = _credentialsRef(uid);
    final expectedGeneration = expectedMetadata['keyGeneration'] ?? 1;
    if (expectedGeneration is! int || expectedGeneration >= 2147483647) {
      throw StateError(
        'Se alcanzó el límite de cambios de llave. No se cambió nada.',
      );
    }

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(metadataReference);
        final current = snapshot.data();
        if (current == null || !_matchesMetadata(current, expectedMetadata)) {
          throw StateError(
            'La bóveda cambió en otro dispositivo. Recarga antes de volver a intentarlo.',
          );
        }
        transaction.update(metadataReference, {
          'rotationInProgress': true,
          'rotationId': rotationId,
        });
      });

      final snapshot = await collection.get(
        const GetOptions(source: Source.server),
      );
      if (snapshot.docs.length > 249) {
        throw StateError(
          'La bóveda supera el límite de 249 accesos para el cambio de contraseña. No se cambió nada.',
        );
      }

      final replacements =
          <
            ({
              DocumentReference<Map<String, dynamic>> oldReference,
              DocumentReference<Map<String, dynamic>> newReference,
              Map<String, Object?> encrypted,
            })
          >[];
      for (final document in snapshot.docs) {
        final newReference = collection.doc();
        final encrypted = await encryptForNewId(
          document.id,
          newReference.id,
          Map<String, Object?>.from(document.data()),
        );
        replacements.add((
          oldReference: document.reference,
          newReference: newReference,
          encrypted: encrypted,
        ));
      }

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(metadataReference);
        final current = snapshot.data();
        if (current == null ||
            !_matchesMetadata(current, expectedMetadata) ||
            current['rotationInProgress'] != true ||
            current['rotationId'] != rotationId) {
          throw StateError(
            'La rotación de la bóveda fue sustituida en otro dispositivo. No se cambió la contraseña.',
          );
        }

        for (final replacement in replacements) {
          transaction.set(replacement.newReference, replacement.encrypted);
          transaction.delete(replacement.oldReference);
        }
        transaction.set(metadataReference, nextMetadata);
      });
    } on Object {
      try {
        await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(metadataReference);
          final current = snapshot.data();
          if (current != null &&
              current['rotationInProgress'] == true &&
              current['rotationId'] == rotationId) {
            transaction.update(metadataReference, {
              'rotationInProgress': FieldValue.delete(),
              'rotationId': FieldValue.delete(),
            });
          }
        });
      } on FirebaseException catch (cleanupError) {
        throw StateError(
          'Falló el cambio de contraseña y no se pudo liberar el bloqueo de la bóveda. Código: ${cleanupError.code}.',
        );
      }
      rethrow;
    }
  }

  bool _matchesMetadata(
    Map<String, dynamic> current,
    Map<String, Object?> expected,
  ) {
    const fields = ['version', 'kdf', 'iterations', 'keyGeneration', 'salt'];
    for (final field in fields) {
      if ((current[field] ?? (field == 'keyGeneration' ? 1 : null)) !=
          (expected[field] ?? (field == 'keyGeneration' ? 1 : null))) {
        return false;
      }
    }
    final currentVerifier = current['verifier'];
    final expectedVerifier = expected['verifier'];
    return currentVerifier is Map &&
        expectedVerifier is Map &&
        currentVerifier['iv'] == expectedVerifier['iv'] &&
        currentVerifier['ciphertext'] == expectedVerifier['ciphertext'];
  }

  String createRotationId() {
    return List<int>.generate(
      32,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
