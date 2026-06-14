import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/notifications/notification_service.dart';
import '../../subscription/revenue_cat_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      if (response.user != null) {
        // Initialise RevenueCat dès le login (sinon Purchases reste non
        // configuré jusqu'au prochain démarrage → crash iOS sur getCustomerInfo).
        try {
          await initRevenueCat(response.user!.id);
        } catch (_) {}
        saveFCMToken(response.user!.id);
        final user = await getCurrentUser();
        if (!mounted) return;
        context.go(user?.role.name == 'child' ? '/child' : '/parent');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.childBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── LOGO / HERO ───────────────────────────────────
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientEmerald,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emerald.withValues(alpha: 0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('💰', style: TextStyle(fontSize: 38)),
                      ),
                    ).animate().scale(
                          duration: 600.ms,
                          curve: Curves.elasticOut,
                        ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tiipee',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 4),
                    const Text(
                      'Plus tu décroches, plus tu gagnes',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // ── FORM ──────────────────────────────────────────
              const Text(
                'Connexion',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 24),

              // Email
              _DarkTextField(
                controller: _emailCtrl,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1),

              const SizedBox(height: 14),

              // Password
              _DarkTextField(
                controller: _passwordCtrl,
                label: 'Mot de passe',
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
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

              // Erreur
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.rose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.rose.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.rose, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: AppColors.rose, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // CTA
              GestureDetector(
                onTap: _loading ? null : _login,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: _loading ? null : AppColors.gradientEmerald,
                    color: _loading ? AppColors.childCard : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _loading
                        ? []
                        : [
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
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.emerald,
                            ),
                          )
                        : const Text(
                            'Se connecter',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ).animate().fadeIn(delay: 350.ms),

              const SizedBox(height: 20),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.childBorder)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'ou',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.childBorder)),
                ],
              ),

              const SizedBox(height: 20),

              // Sign up
              GestureDetector(
                onTap: () => context.go('/role'),
                child: Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.childCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.childBorder),
                  ),
                  child: const Center(
                    child: Text(
                      'Créer un compte',
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 32),

              // Legal
              Center(
                child: Text(
                  'En continuant, vous acceptez nos conditions d\'utilisation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.6),
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

// ── DARK TEXT FIELD ───────────────────────────────────────────────────────────

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const _DarkTextField({
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
