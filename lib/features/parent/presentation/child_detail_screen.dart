import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/models/configuration_model.dart';
import '../../../shared/providers/config_provider.dart';
import 'parent_home_screen.dart' show childWeeklySummaryProvider;
import '../../../core/notifications/notification_service.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _childDetailUserProvider =
    FutureProvider.family<AppUser?, String>((ref, childId) async {
  final data = await supabase
      .from('users')
      .select()
      .eq('id', childId)
      .maybeSingle();
  if (data == null) return null;
  return AppUser.fromJson(data);
});

final _weeklyStatsProvider =
    FutureProvider.family<List<DayStat>, String>((ref, childId) {
  return getWeeklyStats(childId);
});

final _streakProvider =
    FutureProvider.family<int, String>((ref, childId) {
  return getStreak(childId);
});

final _weeklyPaidOutProvider =
    FutureProvider.family<int, String>((ref, childId) {
  return getWeeklyPaidOut(childId);
});

final _screenTimeProvider =
    FutureProvider.family<Map<DateTime, int>, String>((ref, childId) {
  return getWeeklyScreenTime(childId);
});


// ── Screen ────────────────────────────────────────────────────────────────────

class ChildDetailScreen extends ConsumerWidget {
  final String childId;

  const ChildDetailScreen({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt            = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final childAsync     = ref.watch(_childDetailUserProvider(childId));
    final statsAsync     = ref.watch(_weeklyStatsProvider(childId));
    final streakAsync    = ref.watch(_streakProvider(childId));
    final configAsync    = ref.watch(configProvider(childId));
    final paidOutAsync   = ref.watch(_weeklyPaidOutProvider(childId));

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.parentDarkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.emerald,
          surface: AppColors.parentDarkSurface,
        ),
      ),
      child: Scaffold(
        backgroundColor: AppColors.parentDarkBg,
        body: childAsync.when(
          data: (child) {
            if (child == null) {
              return const Center(
                  child: Text('Enfant introuvable',
                      style: TextStyle(color: AppColors.textMuted)));
            }
            return CustomScrollView(
              slivers: [
                _Header(child: child, childId: childId),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Code de connexion : visible tant qu'il existe, pour que
                      // le parent puisse toujours le retrouver/partager.
                      if ((child.inviteCode ?? '').isNotEmpty) ...[
                        _ConnectionCodeCard(code: child.inviteCode!),
                        const SizedBox(height: 16),
                      ],
                      _WeeklyBalanceCard(
                          configAsync: configAsync,
                          statsAsync: statsAsync,
                          paidOutAsync: paidOutAsync,
                          fmt: fmt),
                      const SizedBox(height: 16),
                      _WeekChartCard(
                          statsAsync: statsAsync,
                          configAsync: configAsync),
                      const SizedBox(height: 16),
                      _DigitalWellbeingCard(
                          childName: child.name,
                          screenTimeAsync:
                              ref.watch(_screenTimeProvider(childId))),
                      const SizedBox(height: 16),
                      _StatsRow(
                          streakAsync: streakAsync,
                          statsAsync: statsAsync,
                          configAsync: configAsync),
                      const SizedBox(height: 20),
                      _ActionButtons(
                          childId: childId,
                          configAsync: configAsync,
                          statsAsync: statsAsync,
                          paidOutAsync: paidOutAsync,
                          fmt: fmt,
                          ref: ref),
                    ]),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.emerald)),
          error: (e, _) => Center(
              child: Text('Erreur : $e',
                  style: const TextStyle(color: AppColors.textMuted))),
        ),
      ),
    );
  }
}

// ── CODE DE CONNEXION ─────────────────────────────────────────────────────────

/// Affiche le code de liaison de l'enfant pour que le parent puisse le
/// retrouver et le copier à tout moment (connexion du téléphone de l'enfant).
class _ConnectionCodeCard extends StatelessWidget {
  final String code;
  const _ConnectionCodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.parentDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('🔗', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Code de connexion',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                const Text(
                  'À saisir sur le téléphone de ton enfant pour le connecter.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded,
                color: AppColors.emerald, size: 20),
            tooltip: 'Copier',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copié ✓')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── HEADER ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AppUser child;
  final String childId;

  const _Header({required this.child, required this.childId});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: AppColors.parentDarkBg,
      foregroundColor: AppColors.textLight,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textMuted),
          onPressed: () => context.push('/parent/config/$childId'),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: AppColors.parentDarkBg,
          padding: const EdgeInsets.fromLTRB(20, 80, 20, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.emerald.withValues(alpha: 0.3),
                      width: 1.5),
                ),
                child: Center(
                  child: Text(
                    child.name.isNotEmpty ? child.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(child.name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textLight)),
                  const Text('Cette semaine',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SOLDE SEMAINE ─────────────────────────────────────────────────────────────

class _WeeklyBalanceCard extends StatelessWidget {
  final AsyncValue<ChildConfiguration?> configAsync;
  final AsyncValue<List<DayStat>> statsAsync;
  final AsyncValue<int> paidOutAsync;
  final NumberFormat fmt;

  const _WeeklyBalanceCard({
    required this.configAsync,
    required this.statsAsync,
    required this.paidOutAsync,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final baseWeekly = configAsync.when(
        data: (c) => c?.baseWeeklyCents ?? 0, loading: () => 0, error: (_, __) => 0);
    final bonusEarned = statsAsync.when(
        data: (s) => s.fold(0, (sum, d) => sum + d.earnedCents),
        loading: () => 0,
        error: (_, __) => 0);
    final bonusMax = configAsync.when(
        data: (c) => c?.bonusWeeklyMaxCents ?? 0, loading: () => 0, error: (_, __) => 0);
    final alreadyPaid = paidOutAsync.when(
        data: (p) => p, loading: () => 0, error: (_, __) => 0);
    final total = (baseWeekly + bonusEarned - alreadyPaid).clamp(0, 999999);
    final progress = bonusMax > 0
        ? (bonusEarned / bonusMax).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.gradientParentCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('À verser cette semaine',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    fmt.format(total / 100),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ).animate().scale(
                        duration: 400.ms, curve: Curves.elasticOut),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(progress * 100).round()}% du bonus',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _MiniStat(
                  label: 'Garanti', value: fmt.format(baseWeekly / 100), icon: '🛡️'),
              const SizedBox(width: 16),
              _MiniStat(
                  label: 'Bonus gagné',
                  value: fmt.format(bonusEarned / 100),
                  icon: '📵'),
              const SizedBox(width: 16),
              _MiniStat(
                  label: 'Max bonus',
                  value: fmt.format(bonusMax / 100),
                  icon: '🎯'),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final String icon;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$icon $label',
              style: const TextStyle(color: Colors.white60, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

// ── GRAPHIQUE ─────────────────────────────────────────────────────────────────

class _WeekChartCard extends StatelessWidget {
  final AsyncValue<List<DayStat>> statsAsync;
  final AsyncValue<ChildConfiguration?> configAsync;

  const _WeekChartCard(
      {required this.statsAsync, required this.configAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.parentDarkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.parentDarkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pauses écran',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textLight)),
              configAsync.when(
                data: (c) => Text(
                  'Objectif ${c?.dailyTargetMinutes ?? 120} min/jour',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          statsAsync.when(
            data: (stats) => SizedBox(
              height: 140,
              child: _BarChart(stats: stats, configAsync: configAsync),
            ),
            loading: () => const SizedBox(
              height: 140,
              child: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.emerald)),
            ),
            error: (_, __) => const SizedBox(
              height: 140,
              child: Center(
                  child: Text('Données indisponibles',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12))),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<DayStat> stats;
  final AsyncValue<ChildConfiguration?> configAsync;

  const _BarChart({required this.stats, required this.configAsync});

  @override
  Widget build(BuildContext context) {
    final target = configAsync.when(
        data: (c) => (c?.dailyTargetMinutes ?? 120).toDouble(),
        loading: () => 120.0,
        error: (_, __) => 120.0);

    final maxY = stats.fold(
        0, (m, d) => d.durationMinutes > m ? d.durationMinutes : m);
    final chartMax =
        (maxY < target ? target : maxY.toDouble()) * 1.3;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMax,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.parentDarkSurface,
            getTooltipItem: (group, _, rod, __) {
              final stat = stats[group.x];
              final h    = stat.durationMinutes ~/ 60;
              final m    = stat.durationMinutes % 60;
              return BarTooltipItem(
                h > 0 ? '${h}h${m}m' : '${m}m',
                const TextStyle(
                    color: AppColors.textLight, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= stats.length) {
                  return const SizedBox.shrink();
                }
                final stat = stats[idx];
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    stat.dayLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: stat.isToday
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: stat.isToday
                          ? AppColors.emerald
                          : AppColors.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: target,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.emerald.withValues(alpha: 0.15),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: stats.asMap().entries.map((entry) {
          final idx     = entry.key;
          final stat    = entry.value;
          final reached = stat.durationMinutes >= target;
          final isToday = stat.isToday;
          return BarChartGroupData(
            x: idx,
            barRods: [
              BarChartRodData(
                toY: stat.durationMinutes.toDouble(),
                width: 28,
                borderRadius: BorderRadius.circular(6),
                color: reached
                    ? AppColors.emerald
                    : isToday
                        ? AppColors.emerald.withValues(alpha: 0.4)
                        : AppColors.parentDarkBorder,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── BIEN-ÊTRE NUMÉRIQUE (temps d'écran) ───────────────────────────────────────

class _DigitalWellbeingCard extends StatelessWidget {
  final String childName;
  final AsyncValue<Map<DateTime, int>> screenTimeAsync;

  const _DigitalWellbeingCard({
    required this.childName,
    required this.screenTimeAsync,
  });

  static String _fmtHm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
    return '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return screenTimeAsync.when(
      // Pas de données (iOS, ou suivi non activé par l'enfant) → carte masquée.
      data: (map) {
        if (map.isEmpty || map.values.every((v) => v == 0)) {
          return const SizedBox.shrink();
        }
        final entries = map.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        final now = DateTime.now();
        bool isToday(DateTime d) =>
            d.year == now.year && d.month == now.month && d.day == now.day;

        final todayMinutes = entries
            .firstWhere((e) => isToday(e.key),
                orElse: () => MapEntry(now, 0))
            .value;
        final daysWithData = entries.where((e) => e.value > 0).length;
        final totalMinutes = entries.fold(0, (s, e) => s + e.value);
        final avgMinutes =
            daysWithData > 0 ? (totalMinutes / daysWithData).round() : 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.parentDarkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.parentDarkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('📱 Temps d\'écran de $childName',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textLight)),
                  ),
                  Text('~${_fmtHm(avgMinutes)}/jour',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(_fmtHm(todayMinutes),
                      style: const TextStyle(
                          color: AppColors.violet,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          height: 1.1)),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text("aujourd'hui",
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 120,
                child: _ScreenTimeChart(entries: entries, isToday: isToday),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ScreenTimeChart extends StatelessWidget {
  final List<MapEntry<DateTime, int>> entries;
  final bool Function(DateTime) isToday;

  const _ScreenTimeChart({required this.entries, required this.isToday});

  static const _labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  @override
  Widget build(BuildContext context) {
    final maxY = entries.fold(0, (m, e) => e.value > m ? e.value : m);
    final chartMax = (maxY == 0 ? 60 : maxY).toDouble() * 1.3;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMax,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.parentDarkSurface,
            getTooltipItem: (group, _, rod, __) {
              final min = entries[group.x].value;
              final h = min ~/ 60;
              final m = min % 60;
              return BarTooltipItem(
                h > 0 ? '${h}h${m}m' : '${m}m',
                const TextStyle(
                    color: AppColors.textLight, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx < 0 || idx >= entries.length) {
                  return const SizedBox.shrink();
                }
                final today = isToday(entries[idx].key);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _labels[entries[idx].key.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          today ? FontWeight.bold : FontWeight.normal,
                      color:
                          today ? AppColors.violet : AppColors.textMuted,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: entries.asMap().entries.map((entry) {
          final idx = entry.key;
          final today = isToday(entry.value.key);
          return BarChartGroupData(
            x: idx,
            barRods: [
              BarChartRodData(
                toY: entry.value.value.toDouble(),
                width: 28,
                borderRadius: BorderRadius.circular(6),
                color: today
                    ? AppColors.violet
                    : AppColors.violet.withValues(alpha: 0.4),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── STATS RAPIDES ─────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final AsyncValue<int> streakAsync;
  final AsyncValue<List<DayStat>> statsAsync;
  final AsyncValue<ChildConfiguration?> configAsync;

  const _StatsRow({
    required this.streakAsync,
    required this.statsAsync,
    required this.configAsync,
  });

  @override
  Widget build(BuildContext context) {
    final totalMinutes = statsAsync.when(
        data: (s) => s.fold(0, (sum, d) => sum + d.durationMinutes),
        loading: () => 0,
        error: (_, __) => 0);
    final target = configAsync.when(
        data: (c) => (c?.dailyTargetMinutes ?? 120) * 7,
        loading: () => 840,
        error: (_, __) => 840);
    final daysReached = statsAsync.when(
      data: (stats) {
        final daily = configAsync.when(
            data: (c) => c?.dailyTargetMinutes ?? 120,
            loading: () => 120,
            error: (_, __) => 120);
        return stats.where((d) => d.durationMinutes >= daily).length;
      },
      loading: () => 0,
      error: (_, __) => 0,
    );
    final streak = streakAsync.when(
        data: (s) => s, loading: () => 0, error: (_, __) => 0);
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    return Row(
      children: [
        _StatTile(
          value: h > 0 ? '${h}h${m}m' : '${m}m',
          label: 'posé cette semaine',
          icon: '📵',
          sub: '/ ${target ~/ 60}h objectif',
        ),
        const SizedBox(width: 12),
        _StatTile(value: '$daysReached/7', label: 'jours objectif', icon: '🎯'),
        const SizedBox(width: 12),
        _StatTile(
          value: '$streak',
          label: streak == 1 ? 'jour consécutif' : 'jours consécutifs',
          icon: '🔥',
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final String icon;
  final String? sub;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.parentDarkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.parentDarkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textLight,
                )),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textMuted)),
            if (sub != null)
              Text(sub!,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ── BOUTONS D'ACTION ──────────────────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final String childId;
  final AsyncValue<ChildConfiguration?> configAsync;
  final AsyncValue<List<DayStat>> statsAsync;
  final AsyncValue<int> paidOutAsync;
  final NumberFormat fmt;
  final WidgetRef ref;

  const _ActionButtons({
    required this.childId,
    required this.configAsync,
    required this.statsAsync,
    required this.paidOutAsync,
    required this.fmt,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseWeekly  = configAsync.when(
        data: (c) => c?.baseWeeklyCents ?? 0, loading: () => 0, error: (_, __) => 0);
    final bonusEarned = statsAsync.when(
        data: (s) => s.fold(0, (sum, d) => sum + d.earnedCents),
        loading: () => 0,
        error: (_, __) => 0);
    final alreadyPaid = paidOutAsync.when(
        data: (p) => p, loading: () => 0, error: (_, __) => 0);
    final total = (baseWeekly + bonusEarned - alreadyPaid).clamp(0, 999999);

    final config = configAsync.value;
    final paymentDayReached = config?.isPaymentDayReached ?? false;

    return Column(
      children: [
        if (total > 0 && paymentDayReached)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.gradientEmerald,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emerald.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showValidateDialog(context, total),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payments_outlined,
                          color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        'Valider le versement · ${fmt.format(total / 100)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (total > 0 && !paymentDayReached && config != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.parentDarkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.parentDarkBorder),
              ),
              child: Row(
                children: [
                  const Text('📅', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Versement disponible à partir du ${config.paymentDayLabel}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(
                  color: AppColors.parentDarkBorder, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.tune,
                color: AppColors.textMuted, size: 18),
            label: const Text('Modifier les règles',
                style: TextStyle(color: AppColors.textMuted)),
            onPressed: () => context.push('/parent/config/$childId'),
          ),
        ),
      ],
    );
  }

  void _showValidateDialog(BuildContext context, int totalCents) {
    showDialog(
      context: context,
      builder: (_) => _ValidatePayoutDialog(
        childId: childId,
        totalCents: totalCents,
        onValidated: () {
          // Rafraîchit les stats après validation
          ref.invalidate(_weeklyStatsProvider(childId));
          ref.invalidate(configProvider(childId));
          ref.invalidate(_weeklyPaidOutProvider(childId));
          ref.invalidate(childWeeklySummaryProvider(childId));
        },
      ),
    );
  }
}

// ── DIALOG CONFIRMATION VIREMENT ──────────────────────────────────────────────

class _ValidatePayoutDialog extends ConsumerStatefulWidget {
  final String childId;
  final int totalCents;
  final VoidCallback onValidated;

  const _ValidatePayoutDialog({
    required this.childId,
    required this.totalCents,
    required this.onValidated,
  });

  @override
  ConsumerState<_ValidatePayoutDialog> createState() =>
      _ValidatePayoutDialogState();
}

class _ValidatePayoutDialogState extends ConsumerState<_ValidatePayoutDialog> {
  bool _loading = false;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      // Récupère le parent connecté
      final parent = await getCurrentUser();
      if (parent == null) throw Exception('Utilisateur introuvable');

      // Crée la demande de virement, puis la valide immédiatement
      await requestPayout(
        childId: widget.childId,
        parentId: parent.id,
        amountCents: widget.totalCents,
      );

      // Récupère le payout qu'on vient d'insérer pour le valider
      final payouts = await getPendingPayouts(parent.id);
      final payout = payouts.firstWhere(
        (p) => p.childId == widget.childId,
        orElse: () => payouts.first,
      );
      await validatePayout(payout.id);

      // Notifie l'enfant que son versement est validé (non bloquant)
      notifyChildPayoutValidated(
        childId: widget.childId,
        amountCents: widget.totalCents,
      );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onValidated();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Versement validé !'),
          backgroundColor: AppColors.emerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.parentDarkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Confirmer le versement',
          style: TextStyle(
              color: AppColors.textLight, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
            ),
            child: Text(
              NumberFormat.currency(locale: 'fr_FR', symbol: '€')
                  .format(widget.totalCents / 100),
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppColors.emerald,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'En validant, vous confirmez avoir effectué le virement par votre moyen habituel (Lydia, virement bancaire, espèces…)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child:
              const Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
          onPressed: _loading ? null : _confirm,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirmer', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
