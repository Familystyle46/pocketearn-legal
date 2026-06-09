import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.childBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textMuted),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Vous êtes...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ).animate().fadeIn(duration: 400.ms),

              const SizedBox(height: 8),
              const Text(
                'Choisissez votre profil pour commencer.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 40),

              _RoleCard(
                emoji: '👨‍👩‍👧',
                title: 'Parent',
                subtitle: 'Je configure les règles et valide les virements chaque semaine',
                accentColor: AppColors.emerald,
                onTap: () => context.push('/signup'),
                index: 0,
              ),

              const SizedBox(height: 16),

              _RoleCard(
                emoji: '🧒',
                title: 'Enfant',
                subtitle: 'J\'ai un code donné par mon parent pour rejoindre la famille',
                accentColor: AppColors.violet,
                onTap: () => context.push('/join'),
                index: 1,
              ),

              const Spacer(),

              Center(
                child: TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text(
                    'Déjà un compte ? Se connecter',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
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

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final int index;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.childCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.childBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_ios,
                color: accentColor, size: 16),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 150 + index * 100))
        .fadeIn(duration: 400.ms)
        .slideX(begin: 0.1, end: 0);
  }
}
