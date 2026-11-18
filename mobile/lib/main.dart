import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';
import 'app_theme.dart';
import 'services/github_release_updater.dart';
import 'screens/credential_editor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaSSwordApp());
}

class PaSSwordApp extends StatefulWidget {
  const PaSSwordApp({super.key});

  @override
  State<PaSSwordApp> createState() => _PaSSwordAppState();
}

class _PaSSwordAppState extends State<PaSSwordApp> {
  final _controller = AppController();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _releaseUpdater = GitHubReleaseUpdater();
  bool _updateProgressVisible = false;

  @override
  void initState() {
    super.initState();
    _controller.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForAppUpdate());
    });
  }

  @override
  void dispose() {
    _releaseUpdater.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaSSword',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      home: Listener(
        onPointerDown: (_) => _controller.registerActivity(),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _buildHome(),
        ),
      ),
    );
  }

  Future<void> _checkForAppUpdate() async {
    if (!kReleaseMode || !Platform.isAndroid) return;
    try {
      final update = await _releaseUpdater.checkForUpdate();
      if (!mounted || update == null) return;

      final context = _navigatorKey.currentContext;
      if (context == null || !context.mounted) {
        _showUpdateError('No se pudo abrir el aviso de actualización.');
        return;
      }

      final notes = update.releaseNotes.isEmpty
          ? ''
          : '\n\n${update.releaseNotes}';
      final shouldUpdate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Actualización disponible'),
          content: Text(
            'Está disponible PaSSword ${update.displayVersion}.$notes\n\n'
            '¿Quieres descargarla e instalarla ahora?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Más tarde'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      );
      if (!mounted || shouldUpdate != true) return;
      await _downloadAndInstallUpdate(update);
    } on GitHubUpdateException catch (error) {
      _showUpdateError(error.message);
    } on http.ClientException catch (error) {
      _showUpdateError(error.message);
    } on SocketException catch (error) {
      _showUpdateError(error.message);
    } on TimeoutException catch (error) {
      _showUpdateError(error.message ?? 'Tiempo de espera agotado.');
    } on FormatException catch (error) {
      _showUpdateError(error.message);
    } on PlatformException catch (error) {
      _showUpdateError(error.message ?? 'No se pudo comprobar la versión.');
    }
  }

  Future<void> _downloadAndInstallUpdate(GitHubReleaseUpdate update) async {
    try {
      final context = _navigatorKey.currentContext;
      if (context == null) {
        _showUpdateError('No se pudo abrir la descarga de la actualización.');
        return;
      }
      _updateProgressVisible = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const PopScope<void>(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 18),
                  Expanded(child: Text('Descargando actualización…')),
                ],
              ),
            ),
          ),
        ),
      );

      final apk = await _releaseUpdater.downloadUpdate(update);
      if (!mounted) return;
      _closeUpdateProgress();
      final result = await OpenFilex.open(
        apk.path,
        type: "application/vnd.android.package-archive",
      );
      if (result.type != ResultType.done) {
        _showUpdateError(
          'Android no pudo abrir el instalador: ${result.message}',
        );
      }
    } on GitHubUpdateException catch (error) {
      _closeUpdateProgress();
      _showUpdateError(error.message);
    } on http.ClientException catch (error) {
      _closeUpdateProgress();
      _showUpdateError(error.message);
    } on SocketException catch (error) {
      _closeUpdateProgress();
      _showUpdateError(error.message);
    } on TimeoutException catch (error) {
      _closeUpdateProgress();
      _showUpdateError(error.message ?? 'Tiempo de espera agotado.');
    } on FileSystemException catch (error) {
      _closeUpdateProgress();
      _showUpdateError(error.message);
    } on PlatformException catch (error) {
      _closeUpdateProgress();
      _showUpdateError(error.message ?? 'Android no pudo abrir el instalador.');
    }
  }

  void _closeUpdateProgress() {
    if (!_updateProgressVisible) return;
    _updateProgressVisible = false;
    _navigatorKey.currentState?.pop();
  }

  void _showUpdateError(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('No se pudo completar la actualización: $message'),
      ),
    );
  }

  Widget _buildHome() {
    switch (_controller.stage) {
      case AppStage.starting:
      case AppStage.loadingVault:
        return const _LoadingScreen();
      case AppStage.configuration:
        return _ConfigurationScreen(
          message:
              _controller.configurationMessage ?? 'Configuración incompleta.',
        );
      case AppStage.signedOut:
        return _SignInScreen(controller: _controller);
      case AppStage.createVault:
        return _VaultAccessScreen(controller: _controller, create: true);
      case AppStage.configureUnlock:
        return _UnlockSetupScreen(controller: _controller);
      case AppStage.unlockVault:
        return _VaultAccessScreen(controller: _controller, create: false);
      case AppStage.unlocked:
        return _VaultScreen(controller: _controller);
    }
  }
}

class _UnlockSetupScreen extends StatefulWidget {
  const _UnlockSetupScreen({required this.controller});

  final AppController controller;

  @override
  State<_UnlockSetupScreen> createState() => _UnlockSetupScreenState();
}

class _UnlockSetupScreenState extends State<_UnlockSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.controller.completeUnlockSetup(_pin.text);
    if (mounted && widget.controller.isUnlocked) {
      _pin.clear();
      _confirmation.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandMark(size: 58),
                    const SizedBox(height: 24),
                    Text(
                      'Protege PaSSword',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      controller.biometricAvailable
                          ? 'Crea un PIN de respaldo y confirma tu huella o el desbloqueo del teléfono. Necesitarás Google y este método para volver a abrir PaSSword.'
                          : 'Crea un PIN para abrir PaSSword después de iniciar sesión con Google.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'PIN de PaSSword (4 a 6 cifras)',
                        counterText: '',
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                      validator: (value) =>
                          value == null || !RegExp(r'^\d{4,6}$').hasMatch(value)
                          ? 'El PIN debe tener entre 4 y 6 cifras.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmation,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Repite el PIN',
                        counterText: '',
                      ),
                      validator: (value) =>
                          value != _pin.text ? 'Los PIN no coinciden.' : null,
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _MessageBanner(message: controller.errorMessage!),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: controller.isBusy ? null : _submit,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(
                        controller.isBusy
                            ? 'Configurando…'
                            : controller.biometricAvailable
                            ? 'Guardar PIN y huella'
                            : 'Guardar PIN',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: controller.isBusy ? null : controller.signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar sesión de Google'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'PaSSword',
    );
  }
}

class _ConfigurationScreen extends StatelessWidget {
  const _ConfigurationScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(size: 54),
                  const SizedBox(height: 28),
                  Text(
                    'Falta preparar\nPaSSword móvil.',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700, height: 1.08),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: AppTheme.muted, height: 1.55),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Registra password.app.flutter (y password.app.dev para pruebas) como aplicaciones Android en el proyecto Firebase gestor-pass-b60d6. Configura el inicio de sesión Google y los identificadores Android/OAuth antes de compilar. Esta aplicación no carga la web ni necesita Firebase Hosting.',
                    style: TextStyle(height: 1.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInScreen extends StatelessWidget {
  const _SignInScreen({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(size: 54),
                  const SizedBox(height: 28),
                  Text(
                    'Una llave para\ntu bóveda.',
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w700, height: 1.05),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Inicia sesión con Google. Tus accesos se descifran solo en este dispositivo.',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: AppTheme.muted, height: 1.55),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: controller.signIn,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continuar con Google'),
                    ),
                  ),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 20),
                    _MessageBanner(message: controller.errorMessage!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultAccessScreen extends StatefulWidget {
  const _VaultAccessScreen({required this.controller, required this.create});

  final AppController controller;
  final bool create;

  @override
  State<_VaultAccessScreen> createState() => _VaultAccessScreenState();
}

class _VaultAccessScreenState extends State<_VaultAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _unlockPin = TextEditingController();
  bool _showPassword = false;
  bool _showRecovery = false;
  bool _submitting = false;

  @override
  void dispose() {
    _password.dispose();
    _unlockPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.create && !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      if (widget.create) {
        await widget.controller.createVault();
      } else {
        await widget.controller.unlockWithPassword(password: _password.text);
      }
      _password.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _unlockWithPin() async {
    setState(() => _submitting = true);
    try {
      await widget.controller.unlockWithPin(_unlockPin.text);
      _unlockPin.clear();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _recoverWithGoogle() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar PaSSword con Google'),
        content: const Text(
          'Se cerrará la sesión y se borrarán los métodos de desbloqueo guardados en este teléfono. Al volver a entrar con Google podrás configurarlos de nuevo. Las bóvedas antiguas que aún no activaron la recuperación seguirán necesitando su clave anterior.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _submitting = true);
    try {
      await widget.controller.recoverWithGoogle();
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo preparar la recuperación. Código: ${error.code}.',
            ),
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No está disponible el almacenamiento seguro.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final showPasswordForm =
        !widget.create &&
        ((!controller.hasBiometricKey && !controller.hasPinKey) ||
            _showRecovery);
    final showBiometric =
        !widget.create &&
        controller.hasBiometricKey &&
        controller.biometricAvailable;
    final showPin = !widget.create && controller.hasPinKey;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Column(
                    children: [
                      _BrandMark(size: 58),
                      SizedBox(height: 12),
                      Text(
                        'PaSSword',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (widget.create)
                    Text(
                      'Crea tu bóveda',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    )
                  else if (showPasswordForm)
                    Text(
                      _showRecovery
                          ? 'Introduce la clave antigua una vez para activar la recuperación con Google.'
                          : 'Introduce la clave antigua de esta bóveda para continuar.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        height: 1.5,
                      ),
                    ),
                  if (widget.create) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Google identificó tu cuenta. La llave de la bóveda se guardará en Firebase para abrirla automáticamente al iniciar sesión. Esto permite recuperar tus datos, pero el administrador del proyecto Firebase también puede acceder a la llave.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted, height: 1.5),
                    ),
                  ],
                  if (showBiometric) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : controller.unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text(
                        'Desbloquear con huella o PIN del teléfono',
                      ),
                    ),
                  ],
                  if (showPin) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _unlockPin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _unlockWithPin(),
                      decoration: const InputDecoration(
                        labelText: 'PIN de PaSSword (4 a 6 cifras)',
                        counterText: '',
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _unlockWithPin,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Desbloquear con PIN'),
                    ),
                  ],
                  if ((controller.hasBiometricKey || controller.hasPinKey) &&
                      !_showRecovery) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _recoverWithGoogle,
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Recuperar PaSSword con Google'),
                    ),
                  ],
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 18),
                    _MessageBanner(message: controller.errorMessage!),
                  ],
                  if (widget.create) ...[
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting ? 'Creando…' : 'Crear bóveda con Google',
                      ),
                    ),
                  ],
                  if (showPasswordForm) ...[
                    if (showBiometric || showPin)
                      const SizedBox(height: 8)
                    else
                      const SizedBox(height: 24),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _password,
                            autofocus: !widget.create && _showRecovery,
                            obscureText: !_showPassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: widget.create
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted: widget.create
                                ? null
                                : (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Clave antigua de la bóveda',
                              suffixIcon: IconButton(
                                tooltip: _showPassword ? 'Ocultar' : 'Mostrar',
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.length < 12
                                ? 'Usa al menos 12 caracteres.'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Esta bóveda es anterior a la recuperación con Google. Al introducir la clave, se guardará su llave en Firebase para recuperarla al iniciar sesión.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.muted, height: 1.45),
                          ),
                          const SizedBox(height: 22),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: Text(
                              _submitting
                                  ? 'Comprobando…'
                                  : 'Abrir y activar recuperación',
                            ),
                          ),
                          if (_showRecovery) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                controller.clearErrorMessage();
                                setState(() => _showRecovery = false);
                              },
                              child: const Text('Volver a las opciones'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (!_showRecovery &&
                      (controller.hasBiometricKey || controller.hasPinKey))
                    const SizedBox(height: 4),
                  if (controller.errorMessage != null &&
                      !showPasswordForm &&
                      !showPin)
                    const SizedBox(height: 4),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: controller.signOut,
                      child: const Text('Cerrar sesión de Google'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultScreen extends StatefulWidget {
  const _VaultScreen({required this.controller});

  final AppController controller;

  @override
  State<_VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<_VaultScreen> {
  final _search = TextEditingController();
  String _filter = '';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = packageInfo.version);
      }
    } on PlatformException {
      if (mounted) {
        _showFeedback('No se pudo leer la versión de PaSSword.');
      }
    } on MissingPluginException {
      if (mounted) {
        _showFeedback('No está disponible la información de versión.');
      }
    }
  }

  List<VaultCredential> _filtered(List<VaultCredential> items) {
    final filter = _filter.trim().toLowerCase();
    if (filter.isEmpty) {
      return items;
    }
    return items
        .where(
          (item) =>
              item.site.toLowerCase().contains(filter) ||
              item.email.toLowerCase().contains(filter),
        )
        .toList(growable: false);
  }

  Future<void> _addCredential() => _openEditor();

  Future<void> _openEditor([VaultCredential? credential]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (context) => CredentialEditor(
        site: credential?.site ?? '',
        email: credential?.email ?? '',
        password: credential?.password ?? '',
        onSave: (site, email, password) async {
          await widget.controller.saveCredential(
            id: credential?.id,
            site: site,
            email: email,
            password: password,
          );
        },
      ),
    );
    if (mounted && saved == true) {
      _showFeedback(
        credential == null ? 'Acceso guardado.' : 'Acceso actualizado.',
      );
    }
  }

  Future<void> _showCredential(VaultCredential credential) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (context) => _CredentialDetails(
        credential: credential,
        exposureCount:
            widget.controller.passwordExposureCounts[credential.id] ?? 0,
        onEdit: () {
          Navigator.of(context).pop();
          _openEditor(credential);
        },
        onDelete: () => _deleteCredential(credential, context),
        onCheckEmail: _confirmManualEmailCheck,
        onCopy: (value, label) async {
          try {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              Navigator.of(context).pop();
              _showFeedback('$label copiado.');
            }
          } on PlatformException catch (error) {
            if (mounted) {
              _showFeedback(
                'No se pudo copiar $label. El portapapeles no está disponible. Código: ${error.code}.',
              );
            }
          } on MissingPluginException {
            if (mounted) {
              _showFeedback(
                'No se pudo copiar $label porque el portapapeles no está disponible.',
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteCredential(
    VaultCredential credential,
    BuildContext sheetContext,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar acceso'),
        content: Text('¿Quieres eliminar el acceso de ${credential.site}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      await widget.controller.deleteCredential(credential.id);
      if (mounted) {
        _showFeedback('Acceso eliminado.');
      }
    }
  }

  Future<void> _showAccountMenu(String action) async {
    if (action == 'unlockOptions') {
      await _showSecuritySettings();
    } else if (action == 'recover') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recuperar PaSSword con Google'),
          content: const Text(
            'Se cerrará la sesión y se borrarán los métodos de desbloqueo guardados en este teléfono. Al volver a entrar con Google podrás configurarlos de nuevo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await widget.controller.recoverWithGoogle();
      } on PlatformException catch (error) {
        if (mounted) {
          _showFeedback(
            'No se pudo preparar la recuperación. Código: ${error.code}.',
          );
        }
      } on MissingPluginException {
        if (mounted) {
          _showFeedback('No está disponible el almacenamiento seguro.');
        }
      }
    } else if (action == 'changePin') {
      final pin = await showDialog<String>(
        context: context,
        builder: (context) => const _ConfigurePinDialog(change: true),
      );
      if (pin == null) return;
      try {
        await widget.controller.enablePinUnlock(pin);
        if (mounted) {
          _showFeedback('PIN de PaSSword cambiado.');
        }
      } on PlatformException catch (error) {
        if (mounted) {
          _showFeedback('No se pudo guardar el PIN. Código: ${error.code}.');
        }
      } on StateError catch (error) {
        if (mounted) _showFeedback(error.message.toString());
      }
    } else if (action == 'signOut') {
      await widget.controller.lockAndSignOut();
    }
  }

  Future<void> _showSecuritySettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _SecuritySettingsDialog(controller: widget.controller),
    );
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmManualEmailCheck() async {
    final continueToSite = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Comprobar el correo'),
        content: const Text(
          'Se abrirá Have I Been Pwned. PaSSword no enviará tu correo; '
          'tendrás que escribirlo tú en esa página.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abrir Have I Been Pwned'),
          ),
        ],
      ),
    );
    if (continueToSite != true) {
      return;
    }

    try {
      final opened = await launchUrl(
        Uri.https('haveibeenpwned.com', '/'),
        mode: LaunchMode.externalApplication,
      );
      if (mounted) {
        _showFeedback(
          opened
              ? 'Se abrió Have I Been Pwned. PaSSword no envió tu correo.'
              : 'No se pudo abrir Have I Been Pwned en el navegador.',
        );
      }
    } on PlatformException {
      if (mounted) {
        _showFeedback('No se pudo abrir Have I Been Pwned en el navegador.');
      }
    } on MissingPluginException {
      if (mounted) {
        _showFeedback('No está disponible la apertura del navegador externo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final items = _filtered(controller.credentials);
    final exposedCredentialCount = controller.passwordExposureCounts.values
        .where((count) => count > 0)
        .length;
    final exposureError = controller.passwordExposureError;
    final exposureMessage = exposedCredentialCount > 0
        ? 'Se encontraron $exposedCredentialCount accesos con contraseñas que aparecen en filtraciones conocidas. Cámbialas cuanto antes.${exposureError == null ? '' : ' No se pudo actualizar la comprobación.'}'
        : exposureError;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 22,
        title: const Row(
          children: [
            _BrandMark(size: 28),
            SizedBox(width: 8),
            Text(
              'PaSSword',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones de cuenta',
            onSelected: _showAccountMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'unlockOptions',
                child: Row(
                  children: [
                    Icon(Icons.fingerprint, size: 20),
                    SizedBox(width: 12),
                    Text('Elegir desbloqueo: huella o PIN'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'recover',
                child: Row(
                  children: [
                    Icon(Icons.key_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Recuperar PaSSword con Google'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'signOut',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 12),
                    Text('Bloquear y cerrar sesión'),
                  ],
                ),
              ),
              if (controller.hasPinKey)
                const PopupMenuItem(
                  value: 'changePin',
                  child: Row(
                    children: [
                      Icon(Icons.pin_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Cambiar PIN'),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  _appVersion.isEmpty ? 'PaSSword' : 'PaSSword v$_appVersion',
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCredential,
        icon: const Icon(Icons.add),
        label: const Text('Añadir acceso'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tus accesos',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _SyncStatus(status: controller.syncStatus),
                  const SizedBox(height: 6),
                  Text(
                    'Huella digital: revisión semanal y tras editar un acceso, '
                    'con la bóveda abierta.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            if (controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: _MessageBanner(message: controller.errorMessage!),
              ),
            if (exposureMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: _MessageBanner(message: exposureMessage),
              ),
            if (exposureMessage == null &&
                controller.isCheckingPasswordExposure)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: LinearProgressIndicator(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _filter = value),
                decoration: InputDecoration(
                  hintText: 'Buscar sitio o usuario',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar búsqueda',
                          onPressed: () {
                            _search.clear();
                            setState(() => _filter = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? _EmptyState(hasSearch: _filter.isNotEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(indent: 58),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final exposureCount =
                            controller.passwordExposureCounts[item.id] ?? 0;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.surface,
                            foregroundColor: AppTheme.lime,
                            child: Icon(Icons.key_outlined),
                          ),
                          title: Text(
                            item.site,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            item.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (exposureCount > 0)
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppTheme.error,
                                  size: 20,
                                  semanticLabel: 'Contraseña expuesta en filtraciones conocidas',
                                ),
                              if (item.hasPendingWrites)
                                const Icon(
                                  Icons.cloud_upload_outlined,
                                  color: AppTheme.lime,
                                  size: 20,
                                  semanticLabel: 'Pendiente de sincronizar',
                                )
                              else
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppTheme.muted,
                                ),
                            ],
                          ),
                          onTap: () => _showCredential(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isSynced = status == 'Sincronizado';
    final isError = status == 'Error de sincronización';
    final color = isSynced
        ? AppTheme.green
        : isError
        ? AppTheme.error
        : AppTheme.lime;
    return Row(
      children: [
        Icon(
          isSynced
              ? Icons.cloud_done_outlined
              : isError
              ? Icons.cloud_off_outlined
              : Icons.cloud_sync_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(status, style: TextStyle(color: color)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch});

  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_off_outlined, color: AppTheme.muted, size: 34),
            const SizedBox(height: 14),
            Text(
              hasSearch ? 'No hay coincidencias.' : 'Tu bóveda está vacía.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!hasSearch) ...[
              const SizedBox(height: 7),
              const Text(
                'Añade tu primer acceso cuando quieras.',
                style: TextStyle(color: AppTheme.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CredentialDetails extends StatefulWidget {
  const _CredentialDetails({
    required this.credential,
    required this.exposureCount,
    required this.onEdit,
    required this.onDelete,
    required this.onCheckEmail,
    required this.onCopy,
  });

  final VaultCredential credential;
  final int exposureCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCheckEmail;
  final Future<void> Function(String value, String label) onCopy;

  @override
  State<_CredentialDetails> createState() => _CredentialDetailsState();
}

class _CredentialDetailsState extends State<_CredentialDetails> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.credential;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          28 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.site,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar acceso',
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Eliminar acceso',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Email o usuario',
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(child: SelectableText(item.email)),
                IconButton(
                  tooltip: 'Copiar email o usuario',
                  onPressed: () => widget.onCopy(item.email, 'Email o usuario'),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Contraseña', style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _showPassword ? item.password : '••••••••••••',
                  ),
                ),
                IconButton(
                  tooltip: _showPassword
                      ? 'Ocultar contraseña'
                      : 'Mostrar contraseña',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar contraseña',
                  onPressed: () => widget.onCopy(item.password, 'Contraseña'),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            if (widget.exposureCount > 0) ...[
              const SizedBox(height: 8),
              _MessageBanner(
                message:
                    'Esta contraseña aparece ${widget.exposureCount} veces en filtraciones conocidas. Cámbiala en ese servicio y no la reutilices.',
              ),
            ],
            if (RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(item.email)) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onCheckEmail,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Comprobar exposición del correo'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.error, height: 1.45),
      ),
    );
  }
}

class _SecuritySettingsDialog extends StatefulWidget {
  const _SecuritySettingsDialog({required this.controller});

  final AppController controller;

  @override
  State<_SecuritySettingsDialog> createState() =>
      _SecuritySettingsDialogState();
}

class _SecuritySettingsDialogState extends State<_SecuritySettingsDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _toggleBiometrics() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.controller.hasBiometricKey) {
        await widget.controller.disableBiometricUnlock();
      } else {
        await widget.controller.enableBiometricUnlock();
      }
      if (mounted) {
        setState(() {});
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = 'No se pudo cambiar esta opción. Código: ${error.code}.',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _error = error.message.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _configurePin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (context) =>
          _ConfigurePinDialog(change: widget.controller.hasPinKey),
    );
    if (pin == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.enablePinUnlock(pin);
      if (mounted) {
        setState(() {});
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo guardar el PIN. Código: ${error.code}.',
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _error = error.message.toString());
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _error = error.message.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AlertDialog(
      title: const Text('Opciones de desbloqueo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fingerprint),
            title: const Text('Huella o PIN del teléfono'),
            subtitle: Text(
              controller.hasBiometricKey
                  ? 'Activada en este dispositivo'
                  : controller.biometricAvailable
                  ? 'Usa la huella o el PIN de pantalla de Android'
                  : 'Configura una huella o un PIN en Android',
            ),
            trailing: Switch(
              value: controller.hasBiometricKey,
              onChanged:
                  _busy ||
                      (!controller.hasBiometricKey &&
                          !controller.biometricAvailable)
                  ? null
                  : (_) => _toggleBiometrics(),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.pin_outlined),
            title: const Text('PIN de PaSSword'),
            subtitle: Text(
              controller.hasPinKey
                  ? 'PIN propio activado'
                  : 'Necesario para recuperar el acceso en este teléfono',
            ),
            trailing: IconButton(
              tooltip: controller.hasPinKey ? 'Cambiar PIN' : 'Crear PIN',
              onPressed: _busy ? null : _configurePin,
              icon: Icon(
                controller.hasPinKey
                    ? Icons.edit_outlined
                    : Icons.add_circle_outline,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'El PIN es obligatorio como alternativa. Si olvidas el PIN, recupera PaSSword con Google.',
            style: TextStyle(color: AppTheme.muted, height: 1.4),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(message: _error!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ConfigurePinDialog extends StatefulWidget {
  const _ConfigurePinDialog({this.change = false});

  final bool change;

  @override
  State<_ConfigurePinDialog> createState() => _ConfigurePinDialogState();
}

class _ConfigurePinDialogState extends State<_ConfigurePinDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.change ? 'Cambiar PIN de PaSSword' : 'Crear PIN de PaSSword',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN de 4 a 6 cifras',
                counterText: '',
              ),
              validator: (value) =>
                  value == null || !RegExp(r'^\d{4,6}$').hasMatch(value)
                  ? 'Escribe entre 4 y 6 cifras.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Repite el PIN',
                counterText: '',
              ),
              validator: (value) => value == null || value != _pin.text
                  ? 'Los PIN no coinciden.'
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Si lo olvidas, recupera PaSSword con Google.',
              style: TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.pop(context, _pin.text);
          },
          child: const Text('Guardar PIN'),
        ),
      ],
    );
  }
}
