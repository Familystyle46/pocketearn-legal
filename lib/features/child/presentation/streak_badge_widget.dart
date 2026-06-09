import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';

class StreakBadgeWidget extends StatelessWidget {
  final int streak;
  final int todayMinutes;
  final int targetMinutes;

  const StreakBadgeWidget({
    super.key,
    required this.streak,
    required this.todayMinutes,
    required this.targetMinutes,
  });

  String get _streakEmoji {
    if (streak == 0) return '😴';
    if (streak < 3) return '🔥';
    if (streak < 7) return '⚡';
    if (streak < 14) return '💎';
    return '🏆';
  }

  String get _streakMessage {
    if (streak == 0) return 'Lance ta première série aujourd\'hui !';
    if (streak == 1) return '1 jour — c\'est parti !';
    if (streak < 7) return '$streak jours d\'affilée 🔥';
    if (streak < 14) return '$streak jours — tu es en feu ! ⚡';
    if (streak < 30) return '$streak jours — incroyable ! 💎';
    return '$streak jours — légende ! 🏆';
  }

  bool get _todayDone => todayMinutes >= targetMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.childCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.childBorder),
      ),
      child: Row(
        children: [
          // Streak circle
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: streak > 0
                  ? const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFFF9500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: streak == 0 ? Colors.grey[100] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_streakEmoji,
                    style: const TextStyle(fontSize: 20))
                    .animate(onPlay: (c) => c.repeat(period: 3.seconds))
                    .shimmer(duration: 1200.ms, delay: 2.seconds),
                Text(
                  '$streak',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: streak > 0 ? Colors.white : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Message + today status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _streakMessage,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      _todayDone ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 14,
                      color: _todayDone
                          ? const Color(0xFF2E7D32)
                          : Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _todayDone
                          ? 'Objectif du jour atteint !'
                          : 'Encore ${targetMinutes - todayMinutes} min aujourd\'hui',
                      style: TextStyle(
                        fontSize: 12,
                        color: _todayDone
                            ? const Color(0xFF2E7D32)
                            : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Badges débloqués ──────────────────────────────────────────────────────────

class BadgesRow extends StatelessWidget {
  final int streak;
  final int totalSessions;
  final int totalMinutes;

  const BadgesRow({
    super.key,
    required this.streak,
    required this.totalSessions,
    required this.totalMinutes,
  });

  List<_Badge> get _badges => [
    _Badge('🌱', 'Premier pas', 'Première session', totalSessions >= 1),
    _Badge('📵', '10 sessions', 'Régularité', totalSessions >= 10),
    _Badge('🔥', '3j d\'affilée', '3 jours consécutifs', streak >= 3),
    _Badge('⚡', 'Une semaine', '7 jours consécutifs', streak >= 7),
    _Badge('⏰', '10h posé', '10h cumulées', totalMinutes >= 600),
    _Badge('💎', 'Deux semaines', '14 jours consécutifs', streak >= 14),
  ];

  @override
  Widget build(BuildContext context) {
    final unlocked = _badges.where((b) => b.unlocked).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.childCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.childBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Badges',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textLight),
              ),
              Text(
                '$unlocked/${_badges.length}',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 5 * 8) / 6;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _badges
                    .map((b) => SizedBox(width: itemWidth, child: _BadgeTile(badge: b)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Badge {
  final String emoji;
  final String name;
  final String description;
  final bool unlocked;

  const _Badge(this.emoji, this.name, this.description, this.unlocked);
}

class _BadgeTile extends StatelessWidget {
  final _Badge badge;

  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: badge.description,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badge.unlocked
                  ? const Color(0xFFFFF9C4)
                  : Colors.grey[100],
            ),
            child: Center(
              child: Text(
                badge.emoji,
                style: TextStyle(
                  fontSize: 20,
                  color: badge.unlocked
                      ? null
                      : const Color(0xFFFFFFFF).withValues(alpha: 0.15),
                ),
              ).animate(
                target: badge.unlocked ? 1 : 0,
              ).scale(duration: 300.ms),
            ),
          ),
          ), // ferme AspectRatio
          const SizedBox(height: 4),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: badge.unlocked ? Colors.black87 : Colors.grey[400],
              fontWeight: badge.unlocked ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
