import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/supabase/supabase_service.dart'
    show joinFamilyByCode, activateChild;
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';

class JoinFamilyScreen extends ConsumerStatefulWidget {
  const JoinFamilyScreen({super.key});

  @override
  ConsumerState<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends ConsumerState<JoinFamilyScreen> {
  final _codeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _codeVerified = false;
  String? _childName;

  Future<void> _verifyCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await joinFamilyByCode(_codeCtrl.text.trim().toUpperCase());
      if (user == null) {
        setState(() => _error = 'Code invalide. Demande à ton parent.');
      } else {
        setState(() {
          _codeVerified = true;
          _childName = user.name;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createAccount() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email et mot de passe obligatoires');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Le mot de passe doit faire au moins 8 caractères');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await activateChild(
        inviteCode: _codeCtrl.text.trim().toUpperCase(),
        email: email,
        password: password,
      );
      if (!mounted) return;
      context.go('/child');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre ma famille')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_codeVerified) ...[
                Text(
                  'Entre le code de ton parent',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ton parent trouve ce code dans son app → Ajouter un enfant',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),
                AppTextField(
                  controller: _codeCtrl,
                  label: 'Code famille (6 lettres)',
                  textCapitalization: TextCapitalization.characters,
                ),
              ] else ...[
                Text(
                  'Bonjour $_childName !',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                const Text('Crée ton mot de passe pour accéder à ton compte.'),
                const SizedBox(height: 32),
                AppTextField(
                  controller: _emailCtrl,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _passwordCtrl,
                  label: 'Mot de passe',
                  obscureText: true,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              AppButton(
                label: _codeVerified ? 'Créer mon compte' : 'Vérifier le code',
                onPressed: _codeVerified ? _createAccount : _verifyCode,
                loading: _loading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
