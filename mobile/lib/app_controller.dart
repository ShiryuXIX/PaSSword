import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';

import 'firebase_setup.dart';
import 'models/vault_metadata.dart';
import 'services/firebase_service.dart';
import 'services/vault_crypto.dart';
import 'services/vault_key_store.dart';
import 'services/vault_pin_store.dart';

enum AppStage {
  starting,
  configuration,
  signedOut,
  loadingVault,
  createVault,
  unlockVault,
  unlocked,
}

class VaultCredential {
  const VaultCredential({
    required this.id,
    required this.site,
    required this.email,
    required this.password,
    required this.hasPendingWrites,
  });

  final String id;
  final String site;
  final String email;
  final String password;
  final bool hasPendingWrites;
}

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final VaultKeyStore _keyStore = VaultKeyStore();
  final VaultPinStore _pinStore = VaultPinStore();
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  FirebaseService? _service;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<CredentialSnapshot>? _credentialSubscription;
  Timer? _idleTimer;
  DateTime? _backgroundedAt;
  User? user;
  VaultMetadata? metadata;
  Uint8List? _vaultKey;
  List<VaultCredential> credentials = const [];
  AppStage stage = AppStage.starting;
  String? errorMessage;
  String? configurationMessage;
  bool biometricAvailable = false;
  bool hasBiometricKey = false;
  bool hasPinKey = false;
  bool snapshotsFromCache = false;
  bool hasPendingWrites = false;
  bool syncError = false;
  bool isBusy = false;

  bool get isUnlocked => stage == AppStage.unlocked && _vaultKey != null;

  void clearErrorMessage() {
    if (errorMessage == null) {
      return;
    }
    errorMessage = null;
    notifyListeners();
  }

  String get syncStatus {
    if (!isUnlocked) {
      return 'Bóveda bloqueada';
    }
    if (syncError) {
      return 'Error de sincronización';
    }
    if (hasPendingWrites || snapshotsFromCache) {
      return 'Cambios pendientes de sincronizar';
    }
    return 'Sincronizado';
  }

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await FirebaseSetup.initialize();
      _service = FirebaseService();
      stage = AppStage.signedOut;
      _authSubscription = _service!.authChanges.listen(
        (nextUser) => unawaited(_handleAuthChange(nextUser)),
        onError: (Object error, StackTrace stack) {
          errorMessage = 'No se pudo comprobar la sesión de Google.';
          notifyListeners();
        },
      );
    } on StateError catch (error) {
      configurationMessage = error.message.toString();
      stage = AppStage.configuration;
    } on FirebaseException catch (error) {
      configurationMessage =
          'No se pudo iniciar Firebase. Código: ${error.code}.';
      stage = AppStage.configuration;
    } on PlatformException catch (error) {
      configurationMessage =
          'No se pudo preparar el inicio de sesión. Código: ${error.code}.';
      stage = AppStage.configuration;
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    errorMessage = null;
    notifyListeners();
    try {
      await _service!.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      errorMessage =
          'No se pudo iniciar sesión con Google. Código: ${error.code}.';
      notifyListeners();
    } on GoogleSignInException catch (error) {
      errorMessage = _googleErrorMessage(error.code.name, error.description);
      notifyListeners();
    } on PlatformException catch (error) {
      errorMessage = _googleErrorMessage(error.code);
      notifyListeners();
    } on StateError catch (error) {
      errorMessage = error.message.toString();
      notifyListeners();
    }
  }

  Future<void> _handleAuthChange(User? nextUser, {bool force = false}) async {
    if (!force && nextUser?.uid == user?.uid && nextUser != null) {
      return;
    }
    await _credentialSubscription?.cancel();
    _credentialSubscription = null;
    _clearActiveVault();
    user = nextUser;
    metadata = null;
    credentials = const [];
    hasBiometricKey = false;
    hasPinKey = false;
    syncError = false;
    snapshotsFromCache = false;
    hasPendingWrites = false;
    errorMessage = null;

    if (nextUser == null) {
      stage = AppStage.signedOut;
      notifyListeners();
      return;
    }

    stage = AppStage.loadingVault;
    notifyListeners();
    try {
      final rawMetadata = await _service!.readMetadata(nextUser.uid);
      if (user?.uid != nextUser.uid) {
        return;
      }
      if (rawMetadata == null) {
        stage = AppStage.createVault;
        biometricAvailable = await _isBiometricAvailable();
        notifyListeners();
        return;
      }

      metadata = VaultMetadata.fromMap(rawMetadata);
      if (metadata!.rotationInProgress) {
        stage = AppStage.unlockVault;
        errorMessage = 'La bóveda se está actualizando desde otro dispositivo. Vuelve a comprobarlo en unos segundos.';
        notifyListeners();
        return;
      }

      hasBiometricKey = await _keyStore.hasBiometricKey(nextUser.uid);
      hasPinKey = await _pinStore.hasPin(nextUser.uid);
      await _keyStore.forgetLegacyKey(nextUser.uid);
      if (hasBiometricKey || hasPinKey) {
        stage = AppStage.unlockVault;
        biometricAvailable = await _isBiometricAvailable();
        notifyListeners();
        return;
      }

      stage = AppStage.unlockVault;
      biometricAvailable = await _isBiometricAvailable();
    } on FirebaseException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = 'No se pudo leer la bóveda. Código: ${error.code}.';
    } on FormatException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = error.message;
    } on PlatformException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage =
          'No se pudo leer la llave guardada. Usa la contraseña maestra. Código: ${error.code}.';
      biometricAvailable = await _isBiometricAvailable();
    } on StateError catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = error.message.toString();
    }
    notifyListeners();
  }

  Future<void> refreshVault() async {
    final activeUser = user;
    if (activeUser == null) {
      return;
    }
    stage = AppStage.loadingVault;
    errorMessage = null;
    notifyListeners();
    await _handleAuthChange(activeUser, force: true);
  }

  Future<void> createVault({
    required String password,
    required String confirmation,
    required bool enableBiometrics,
    required String? pin,
  }) async {
    if (password.length < 12) {
      errorMessage = 'Usa una contraseña maestra de al menos 12 caracteres.';
      notifyListeners();
      return;
    }
    if (password != confirmation) {
      errorMessage = 'Las contraseñas maestras no coinciden.';
      notifyListeners();
      return;
    }

    await _unlockOrCreate(
      password: password,
      create: true,
      enableBiometrics: enableBiometrics,
      pin: pin,
    );
  }

  Future<void> unlockWithPassword({
    required String password,
    required bool enableBiometrics,
    required String? pin,
  }) async {
    if (password.length < 12) {
      errorMessage = 'La contraseña maestra debe tener al menos 12 caracteres.';
      notifyListeners();
      return;
    }
    await _unlockOrCreate(
      password: password,
      create: false,
      enableBiometrics: enableBiometrics,
      pin: pin,
    );
  }

  Future<void> _unlockOrCreate({
    required String password,
    required bool create,
    required bool enableBiometrics,
    required String? pin,
  }) async {
    final activeUser = user;
    if (activeUser == null) {
      errorMessage = 'Inicia sesión con Google antes de abrir la bóveda.';
      notifyListeners();
      return;
    }

    errorMessage = null;
    stage = AppStage.loadingVault;
    notifyListeners();
    Uint8List? key;
    var metadataCreated = false;
    try {
      if (create) {
        final salt = VaultCrypto.createSalt();
        key = await VaultCrypto.deriveKey(password, salt);
        final verifier = await VaultCrypto.createVerifier(key, activeUser.uid);
        await _service!.createMetadata(
          uid: activeUser.uid,
          salt: salt,
          verifier: verifier,
        );
        metadataCreated = true;
        metadata = VaultMetadata.fromMap({
          'version': 1,
          'kdf': vaultKdfName,
          'iterations': vaultPbkdf2Iterations,
          'keyGeneration': 1,
          'salt': base64Encode(salt),
          'verifier': verifier,
        });
      } else {
        final activeMetadata = metadata;
        if (activeMetadata == null) {
          throw StateError('No se encontró la configuración de la bóveda.');
        }
        key = await VaultCrypto.deriveKey(password, activeMetadata.salt);
        if (!await VaultCrypto.verifyKey(key, activeUser.uid, activeMetadata)) {
          throw StateError('La contraseña maestra no es correcta.');
        }
      }

      if (enableBiometrics) {
        if (!biometricAvailable) {
          throw StateError(
            'Configura huella, rostro o bloqueo de pantalla en Android para activar el desbloqueo biométrico.',
          );
        }
        await _keyStore.saveKey(activeUser.uid, key, biometric: true);
        hasBiometricKey = true;
      }
      if (pin != null) {
        await _pinStore.saveKey(activeUser.uid, key, pin);
        hasPinKey = true;
      }
      _activateVault(key);
      key = null;
    } on FirebaseException catch (error) {
      stage = create && !metadataCreated
          ? AppStage.createVault
          : AppStage.unlockVault;
      errorMessage = metadataCreated
          ? 'La bóveda se creó, pero no se pudo guardar la llave local. Introdúcela para continuar. Código: ${error.code}.'
          : 'No se pudo guardar la configuración. Código: ${error.code}.';
    } on PlatformException catch (error) {
      stage = create && !metadataCreated
          ? AppStage.createVault
          : AppStage.unlockVault;
      errorMessage = metadataCreated
          ? 'La bóveda se creó, pero no se pudo guardar la llave local. Introdúcela para continuar. Código: ${error.code}.'
          : 'No se pudo guardar la llave en este dispositivo. Código: ${error.code}.';
    } on ArgumentError catch (error) {
      stage = create && !metadataCreated
          ? AppStage.createVault
          : AppStage.unlockVault;
      errorMessage = error.message.toString();
    } on StateError catch (error) {
      stage = create && !metadataCreated
          ? AppStage.createVault
          : AppStage.unlockVault;
      errorMessage = error.message.toString();
    } finally {
      key?.fillRange(0, key.length, 0);
    }
    notifyListeners();
  }

  Future<void> unlockWithBiometrics() async {
    final activeUser = user;
    final activeMetadata = metadata;
    if (activeUser == null || activeMetadata == null || !hasBiometricKey) {
      return;
    }
    errorMessage = null;
    stage = AppStage.loadingVault;
    notifyListeners();
    Uint8List? key;
    try {
      key = await _keyStore.readKey(activeUser.uid, biometric: true);
      if (key == null ||
          !await VaultCrypto.verifyKey(key, activeUser.uid, activeMetadata)) {
        throw StateError(
          'La llave biométrica no coincide con esta bóveda. Usa la contraseña maestra.',
        );
      }
      _activateVault(key);
      key = null;
    } on PlatformException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage =
          'No se pudo confirmar la identidad en este dispositivo. Usa la contraseña maestra. Código: ${error.code}.';
    } on StateError catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = error.message.toString();
    } on FormatException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = error.message;
    } finally {
      key?.fillRange(0, key.length, 0);
    }
    notifyListeners();
  }

  Future<void> unlockWithPin(String pin) async {
    final activeUser = user;
    final activeMetadata = metadata;
    if (activeUser == null || activeMetadata == null || !hasPinKey) {
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      errorMessage = 'Escribe el PIN de PaSSword de 4 cifras.';
      notifyListeners();
      return;
    }
    errorMessage = null;
    stage = AppStage.loadingVault;
    notifyListeners();
    Uint8List? key;
    try {
      key = await _pinStore.readKey(activeUser.uid, pin);
      if (key == null ||
          !await VaultCrypto.verifyKey(key, activeUser.uid, activeMetadata)) {
        throw StateError(
          'El PIN guardado no coincide con esta bóveda. Usa la recuperación con contraseña maestra.',
        );
      }
      _activateVault(key);
      key = null;
    } on PlatformException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = 'No se pudo leer el PIN guardado. Código: ${error.code}.';
    } on StateError catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = error.message.toString();
    } on FormatException catch (error) {
      stage = AppStage.unlockVault;
      errorMessage = error.message;
    } finally {
      key?.fillRange(0, key.length, 0);
    }
    notifyListeners();
  }

  Future<void> enableBiometricUnlock() async {
    final activeUser = user;
    final key = _vaultKey;
    if (activeUser == null || key == null || !isUnlocked) {
      throw StateError('Desbloquea la bóveda antes de cambiar esta opción.');
    }
    if (!await _isBiometricAvailable()) {
      throw StateError(
        'Configura una huella o un PIN de pantalla en Android antes de activar esta opción.',
      );
    }
    await _keyStore.saveKey(activeUser.uid, key, biometric: true);
    hasBiometricKey = true;
    biometricAvailable = true;
    notifyListeners();
  }

  Future<void> disableBiometricUnlock() async {
    final activeUser = user;
    if (activeUser == null) {
      return;
    }
    await _keyStore.forgetBiometricKey(activeUser.uid);
    hasBiometricKey = false;
    notifyListeners();
  }

  Future<void> enablePinUnlock(String pin) async {
    final activeUser = user;
    final key = _vaultKey;
    if (activeUser == null || key == null || !isUnlocked) {
      throw StateError('Desbloquea la bóveda antes de cambiar esta opción.');
    }
    await _pinStore.saveKey(activeUser.uid, key, pin);
    hasPinKey = true;
    notifyListeners();
  }

  Future<void> disablePinUnlock() async {
    final activeUser = user;
    if (activeUser == null) {
      return;
    }
    await _pinStore.forgetPin(activeUser.uid);
    hasPinKey = false;
    notifyListeners();
  }

  Future<bool> _isBiometricAvailable() async {
    try {
      return await _localAuthentication.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  void _activateVault(Uint8List key) {
    _clearActiveVault();
    _vaultKey = key;
    stage = AppStage.unlocked;
    errorMessage = null;
    _startCredentialWatch();
    _resetIdleTimer();
    notifyListeners();
  }

  void _startCredentialWatch() {
    if (_credentialSubscription != null ||
        user == null ||
        _vaultKey == null ||
        _service == null) {
      return;
    }
    _credentialSubscription = _service!
        .watchCredentials(user!.uid)
        .listen(_handleCredentialSnapshot, onError: _handleSyncError);
  }

  Future<void> _handleCredentialSnapshot(CredentialSnapshot snapshot) async {
    final activeUser = user;
    final key = _vaultKey;
    final activeMetadata = metadata;
    if (activeUser == null || key == null || activeMetadata == null) {
      return;
    }

    try {
      final decrypted = <VaultCredential>[];
      for (final item in snapshot.items) {
        final fields = await VaultCrypto.decryptCredential(
          key,
          activeUser.uid,
          item.id,
          item.document,
        );
        decrypted.add(
          VaultCredential(
            id: item.id,
            site: fields['site']!,
            email: fields['email']!,
            password: fields['password']!,
            hasPendingWrites: item.hasPendingWrites,
          ),
        );
      }
      credentials = decrypted;
      snapshotsFromCache = snapshot.fromCache;
      hasPendingWrites = snapshot.hasPendingWrites;
      syncError = false;
      errorMessage = null;
    } on StateError catch (error) {
      syncError = true;
      errorMessage = error.message.toString();
    }
    notifyListeners();
  }

  void _handleSyncError(Object error, StackTrace stack) {
    syncError = true;
    errorMessage = error is FirebaseException
        ? 'No se pudo sincronizar la bóveda. Código: ${error.code}.'
        : 'No se pudo sincronizar la bóveda.';
    notifyListeners();
  }

  Future<void> saveCredential({
    String? id,
    required String site,
    required String email,
    required String password,
  }) async {
    final activeUser = user;
    final key = _vaultKey;
    final activeMetadata = metadata;
    if (activeUser == null || key == null || activeMetadata == null) {
      throw StateError('Desbloquea la bóveda antes de guardar un acceso.');
    }
    if (activeMetadata.rotationInProgress) {
      throw StateError(
        'La bóveda se está actualizando en otro dispositivo. Inténtalo más tarde.',
      );
    }

    final fields = {'site': site, 'email': email, 'password': password};
    final Future<void> write;
    if (id == null) {
      final created = _service!.createCredential(activeUser.uid, (newId) {
        return VaultCrypto.encryptCredential(
          key,
          activeUser.uid,
          newId,
          fields,
          keyGeneration: activeMetadata.keyGeneration,
        );
      });
      write = created.then((_) {});
    } else {
      write =
          VaultCrypto.encryptCredential(
            key,
            activeUser.uid,
            id,
            fields,
            keyGeneration: activeMetadata.keyGeneration,
          ).then(
            (encrypted) =>
                _service!.saveCredential(activeUser.uid, id, encrypted),
          );
    }
    _queueWrite(write);
  }

  Future<void> deleteCredential(String id) async {
    final activeUser = user;
    if (activeUser == null || !isUnlocked) {
      throw StateError('Desbloquea la bóveda antes de eliminar un acceso.');
    }
    _queueWrite(_service!.deleteCredential(activeUser.uid, id));
  }

  Future<void> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    final activeUser = user;
    final oldKey = _vaultKey;
    final activeMetadata = metadata;
    if (activeUser == null ||
        oldKey == null ||
        activeMetadata == null ||
        !isUnlocked) {
      throw StateError('Desbloquea la bóveda antes de cambiar la contraseña.');
    }
    if (snapshotsFromCache || hasPendingWrites || syncError) {
      throw StateError(
        'Conéctate y espera a que todos los cambios estén sincronizados antes de continuar.',
      );
    }
    if (newPassword.length < 12 || newPassword.length > 1024) {
      throw StateError(
        'La nueva contraseña maestra debe tener al menos 12 caracteres.',
      );
    }
    if (newPassword != confirmation) {
      throw StateError('Las nuevas contraseñas no coinciden.');
    }
    if (VaultCrypto.normalizeMasterPassword(currentPassword) ==
        VaultCrypto.normalizeMasterPassword(newPassword)) {
      throw StateError('La nueva contraseña debe ser distinta de la actual.');
    }

    isBusy = true;
    errorMessage = null;
    await _credentialSubscription?.cancel();
    _credentialSubscription = null;
    notifyListeners();
    Uint8List? verifiedOldKey;
    Uint8List? newKey;
    var rotationCommitted = false;
    try {
      verifiedOldKey = await VaultCrypto.deriveKey(
        currentPassword,
        activeMetadata.salt,
      );
      if (!await VaultCrypto.verifyKey(
        verifiedOldKey,
        activeUser.uid,
        activeMetadata,
      )) {
        throw StateError('La contraseña maestra actual no es correcta.');
      }
      if (!_keysMatch(verifiedOldKey, oldKey)) {
        throw StateError(
          'La llave activa no coincide con la contraseña maestra actual.',
        );
      }

      final newSalt = VaultCrypto.createSalt();
      newKey = await VaultCrypto.deriveKey(newPassword, newSalt);
      final newGeneration = activeMetadata.keyGeneration + 1;
      final newVerifier = await VaultCrypto.createVerifier(
        newKey,
        activeUser.uid,
      );
      final rotationId = _service!.createRotationId();
      final nextMetadata = <String, Object?>{
        'version': 1,
        'kdf': vaultKdfName,
        'iterations': vaultPbkdf2Iterations,
        'keyGeneration': newGeneration,
        'salt': base64Encode(newSalt),
        'verifier': newVerifier,
      };

      await _service!.reencryptVault(
        uid: activeUser.uid,
        expectedMetadata: activeMetadata.raw,
        nextMetadata: nextMetadata,
        rotationId: rotationId,
        encryptForNewId: (oldId, newId, oldDocument) async {
          final fields = await VaultCrypto.decryptCredential(
            oldKey,
            activeUser.uid,
            oldId,
            oldDocument,
          );
          return VaultCrypto.encryptCredential(
            newKey!,
            activeUser.uid,
            newId,
            fields,
            keyGeneration: newGeneration,
          );
        },
      );

      rotationCommitted = true;
      metadata = VaultMetadata.fromMap(nextMetadata);
      if (hasBiometricKey) {
        await _keyStore.saveKey(activeUser.uid, newKey, biometric: true);
      }
      if (hasPinKey) {
        await _pinStore.forgetPin(activeUser.uid);
        hasPinKey = false;
      }
      oldKey.fillRange(0, oldKey.length, 0);
      _activateVault(newKey);
      newKey = null;
      errorMessage = null;
    } on FirebaseException catch (error) {
      errorMessage = 'No se pudo cambiar la contraseña. Código: ${error.code}.';
    } on PlatformException catch (error) {
      if (rotationCommitted) {
        hasBiometricKey = false;
        hasPinKey = false;
        if (newKey != null) {
          oldKey.fillRange(0, oldKey.length, 0);
          _activateVault(newKey);
          newKey = null;
        }
        var keyStoreStatus = '';
        try {
          await Future.wait([
            _keyStore.forgetKey(activeUser.uid),
            _pinStore.forgetPin(activeUser.uid),
          ]);
        } on PlatformException catch (cleanupError) {
          keyStoreStatus =
              ' No se pudo borrar la llave local anterior. Código: ${cleanupError.code}.';
        }
        errorMessage =
            'La contraseña cambió, pero no se pudo actualizar la llave guardada. Usa la nueva contraseña al volver a entrar. Código: ${error.code}.$keyStoreStatus';
      } else {
        errorMessage =
            'No se pudo acceder al almacenamiento seguro. Código: ${error.code}.';
      }
    } on StateError catch (error) {
      errorMessage = error.message.toString();
    } on ArgumentError catch (error) {
      errorMessage = error.message.toString();
    } finally {
      verifiedOldKey?.fillRange(0, verifiedOldKey.length, 0);
      newKey?.fillRange(0, newKey.length, 0);
      if (user?.uid == activeUser.uid) {
        isBusy = false;
        _startCredentialWatch();
      }
    }
    notifyListeners();
  }

  bool _keysMatch(Uint8List first, Uint8List second) {
    if (first.length != second.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  Future<void> forgetThisDevice() async {
    final activeUser = user;
    if (activeUser == null) {
      return;
    }
    await Future.wait([
      _keyStore.forgetKey(activeUser.uid),
      _pinStore.forgetPin(activeUser.uid),
    ]);
    hasBiometricKey = false;
    hasPinKey = false;
    errorMessage = 'Se eliminó la llave guardada. La próxima vez tendrás que introducir la contraseña maestra.';
    notifyListeners();
  }

  Future<void> signOut() async {
    _clearActiveVault();
    await _service?.signOut();
    user = null;
    metadata = null;
    credentials = const [];
    stage = AppStage.signedOut;
    notifyListeners();
  }

  void _queueWrite(Future<void> write) {
    syncError = false;
    unawaited(
      write.catchError((Object error, StackTrace stack) {
        _handleSyncError(error, stack);
      }),
    );
  }

  Future<void> lockAndSignOut() => signOut();

  void _clearActiveVault() {
    _idleTimer?.cancel();
    final key = _vaultKey;
    key?.fillRange(0, key.length, 0);
    _vaultKey = null;
    credentials = const [];
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 5), () {
      unawaited(lockAndSignOut());
    });
  }

  void registerActivity() {
    if (isUnlocked) {
      _resetIdleTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >=
              const Duration(minutes: 5)) {
        unawaited(lockAndSignOut());
      } else {
        registerActivity();
      }
    }
  }

  String _googleErrorMessage(String code, [String? description]) {
    if (code == 'sign_in_canceled' || code == 'canceled') {
      return 'Se canceló el inicio de sesión con Google.';
    }
    final technicalDetail = description?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final visibleDetail = technicalDetail == null
        ? null
        : technicalDetail.length > 240
        ? technicalDetail.substring(0, 240)
        : technicalDetail;
    final detailSuffix = visibleDetail == null || visibleDetail.isEmpty
        ? ''
        : ' Detalle: $visibleDetail';
    return 'No se pudo completar el inicio de sesión con Google. Código: $code.$detailSuffix';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_credentialSubscription?.cancel());
    _clearActiveVault();
    super.dispose();
  }
}
