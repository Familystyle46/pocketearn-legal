import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/models/user_model.dart';
import '../../subscription/revenue_cat_service.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rgpdConsent = false; // Item 41 — consentement RGPD
  String? _error;

  Future<void> _signup() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Tous les champs sont obligatoires');
      return;
    }
    if (!_rgpdConsent) {
      setState(() => _error = 'Veuillez accepter la politique de confidentialité');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final name  = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final response = await signUp(
        email: email,
        password: _passwordCtrl.text,
        name: name,
        role: UserRole.parent,
      );
      // Enregistre le consentement RGPD
      if (response.user != null) {
        await supabase.from('users').update({
          'rgpd_consent_at': DateTime.now().toIso8601String(),
        }).eq('id', response.user!.id);
        // Initialise RevenueCat dès l'inscription (évite le crash iOS si
        // Purchases est appelé avant le prochain démarrage).
        try {
          await initRevenueCat(response.user!.id);
        } catch (_) {}
      }
      // Item 1 — email de bienvenue (non bloquant)
      supabase.functions.invoke('send-welcome-email', body: {
        'name': name,
        'email': email,
      }).catchError((_) {});
      if (!mounted) return;
      context.go('/parent');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.childBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textMuted),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Créer un\ncompte parent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

              const SizedBox(height: 6),
              const Text(
                '7 jours gratuits — sans carte bancaire',
                style: TextStyle(color: AppColors.emerald, fontSize: 14),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 32),

              _DarkField(
                controller: _nameCtrl,
                label: 'Votre prénom',
                icon: Icons.person_outline,
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 14),

              _DarkField(
                controller: _emailCtrl,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 14),

              _DarkField(
                controller: _passwordCtrl,
                label: 'Mot de passe (8 car. min.)',
                icon: Icons.lock_outline,
                obscureText: _obscure,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ).animate().fadeIn(delay: 250.ms),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.rose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.rose.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.rose, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(color: AppColors.rose, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Item 41 — Consentement RGPD explicite
              GestureDetector(
                onTap: () => setState(() => _rgpdConsent = !_rgpdConsent),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24, height: 24,
                      child: Checkbox(
                        value: _rgpdConsent,
                        onChanged: (v) => setState(() => _rgpdConsent = v ?? false),
                        activeColor: AppColors.emerald,
                        side: const BorderSide(color: AppColors.textMuted),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'J\'accepte la politique de confidentialité et les CGU de Tiipee. '
                        'Mes données sont traitées conformément au RGPD.',
                        style: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.8),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              GestureDetector(
                onTap: _loading ? null : _signup,
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: _loading ? null : AppColors.gradientEmerald,
                    color: _loading ? AppColors.childCard : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _loading ? [] : [
                      BoxShadow(
                        color: AppColors.emerald.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.emerald),
                          )
                        : const Text(
                            'Démarrer gratuitement',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Consentement horodaté et stocké de façon sécurisée.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const _DarkField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textLight, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.childCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.childBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.childBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
