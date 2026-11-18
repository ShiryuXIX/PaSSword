import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CredentialEditor extends StatefulWidget {
  const CredentialEditor({
    required this.onSave,
    this.site = '',
    this.email = '',
    this.password = '',
    super.key,
  });

  final Future<void> Function(String site, String email, String password)
  onSave;
  final String site;
  final String email;
  final String password;

  @override
  State<CredentialEditor> createState() => _CredentialEditorState();
}

class _CredentialEditorState extends State<CredentialEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _site = TextEditingController(text: widget.site);
  late final _email = TextEditingController(text: widget.email);
  late final _password = TextEditingController(text: widget.password);
  final _random = Random.secure();
  bool _saving = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _site.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  int _secureIndex(int length) {
    final limit = 256 - (256 % length);
    int value;
    do {
      value = _random.nextInt(256);
    } while (value >= limit);
    return value % length;
  }

  String _generatePassword() {
    const groups = [
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      'abcdefghijklmnopqrstuvwxyz',
      '0123456789',
      '!@#\$%^&*()-_=+[]{}:,.?',
    ];
    final allCharacters = groups.join();
    final password = groups
        .map((group) => group[_secureIndex(group.length)])
        .toList();
    while (password.length < 12) {
      password.add(allCharacters[_secureIndex(allCharacters.length)]);
    }
    for (var index = password.length - 1; index > 0; index--) {
      final swap = _secureIndex(index + 1);
      final current = password[index];
      password[index] = password[swap];
      password[swap] = current;
    }
    return password.join();
  }

  Future<void> _copyPassword() async {
    if (_password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe una contraseña antes de copiarla.'),
        ),
      );
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: _password.text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Contraseña copiada.')));
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo copiar la contraseña.')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El portapapeles no está disponible.')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        _site.text.trim(),
        _email.text.trim(),
        _password.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outline,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.site.isEmpty ? 'Añadir acceso' : 'Editar acceso',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _site,
                  autofocus: true,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: 'Sitio web o servicio',
                    prefixIcon: Icon(Icons.language),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Escribe el nombre del sitio.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email o usuario',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Escribe el email o usuario.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Escribe una contraseña.'
                      : null,
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      label: Text(_showPassword ? 'Ocultar' : 'Ver'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _password.text = _generatePassword();
                          _showPassword = true;
                        });
                      },
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Generar'),
                    ),
                    TextButton.icon(
                      onPressed: _copyPassword,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copiar'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Guardando…' : 'Guardar acceso'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
