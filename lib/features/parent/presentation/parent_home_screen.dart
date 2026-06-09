import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/models/configuration_model.dart';
import '../../subscription/revenue_cat_service.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final currentUserProvider =
    FutureProvider<AppUser?>((ref) => getCurrentUser());

final _trialDaysLeftProvider =
    FutureProvider<int>((ref) => trialDaysLeft());

final childrenProvider = FutureProvider<List<AppUser>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  return getChildren(user.familyId);
});

final childWeeklySummaryProvider =
    FutureProvider.family<_WeeklySummary, String>((ref, childId) async {
  final config = await getConfiguration(childId);
  final weekStats = await getWeeklyStats(childId);
  final bonus = weekStats.fold<int>(0, (sum, d) => sum + d.earnedCents);
  final base  = config?.baseWeeklyCents ?? 0;
  final alreadyPaid = await getWeeklyPaidOut(childId);
  final remaining = (base + bonus - alreadyPaid).clamp(0, 999999);
  return _WeeklySummary(
    baseCents:  base,
    bonusCents: bonus,
    totalCents: remaining,
    config:     config,
  );
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync     = ref.watch(currentUserProvider);
    final childrenAsync = ref.watch(childrenProvider);
    final fmt = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

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
        body: SafeArea(
          child: CustomScrollView(
            slivers: [

              // ── HEADER ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            userAsync.when(
                              data: (u) => Text(
                                'Bonjour, ${u?.name ?? ''} 👋',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textLight,
                                ),
                              ).animate().fadeIn(duration: 400.ms),
                              loading: () => const SizedBox(height: 32),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 4),
                            childrenAsync.when(
                              data: (children) {
                                if (children.isEmpty) {
                                  return const Text(
                                    'Ajoutez votre premier enfant',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13),
                                  );
                                }
                                return _TotalThisWeek(
                                    children: children, ref: ref, fmt: fmt);
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_outlined,
                            color: AppColors.textMuted),
                        onPressed: () async {
                          await signOut();
                          if (context.mounted) context.go('/login');
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ── BANNIÈRE TRIAL ──────────────────────────────────
              SliverToBoxAdapter(
                child: ref.watch(_trialDaysLeftProvider).maybeWhen(
                  data: (days) {
                    if (days <= 0) return const SizedBox.shrink();
                    final isUrgent = days <= 2;
                    return GestureDetector(
                      onTap: () => context.push('/paywall'),
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUrgent
                              ? const Color(0xFF7B1F1F)
                              : const Color(0xFF1B3A2B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isUrgent
                                ? const Color(0xFFEF5350)
                                : AppColors.emerald,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(isUrgent ? '⚠️' : '🎁',
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                days == 1
                                    ? 'Dernier jour d\'essai — abonnez-vous pour continuer'
                                    : 'Essai gratuit — $days jours restants',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isUrgent
                                      ? const Color(0xFFEF9A9A)
                                      : AppColors.textLight,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios,
                                size: 13,
                                color: isUrgent
                                    ? const Color(0xFFEF9A9A)
                                    : AppColors.textMuted),
                          ],
                        ),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ),

              // ── SECTION TITRE ───────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                sliver: SliverToBoxAdapter(
                  child: childrenAsync.when(
                    data: (children) => Text(
                      children.isEmpty ? 'Commencer' : 'Mes enfants',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
              ),

              // ── LISTE ENFANTS ────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                sliver: childrenAsync.when(
                  data: (children) => children.isEmpty
                      ? SliverToBoxAdapter(child: _EmptyState())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _ChildCard(
                              child: children[i],
                              fmt: fmt,
                              index: i,
                              ref: ref,
                            ),
                            childCount: children.length,
                          ),
                        ),
                  loading: () => const SliverToBoxAdapter(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.emerald)),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Center(
                        child: Text('Erreur : $e',
                            style:
                                const TextStyle(color: AppColors.textMuted))),
                  ),
                ),
              ),
            ],
          ),
        ),

        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddChildDialog(context, ref),
          backgroundColor: AppColors.emerald,
          icon: const Icon(Icons.person_add, color: Colors.white),
          label: const Text(
            'Ajouter un enfant',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void _showAddChildDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _AddChildDialog(onAdded: () {
        ref.invalidate(childrenProvider);
      }),
    );
  }
}

// ── TOTAL BANNER ──────────────────────────────────────────────────────────────

class _TotalThisWeek extends ConsumerWidget {
  final List<AppUser> children;
  final WidgetRef ref;
  final NumberFormat fmt;

  const _TotalThisWeek({
    required this.children,
    required this.ref,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int total = 0;
    for (final child in children) {
      final summary = ref.watch(childWeeklySummaryProvider(child.id));
      total += summary.value?.totalCents ?? 0;
    }
    return Text(
      '${fmt.format(total / 100)} à verser cette semaine',
      style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w500),
    ).animate().fadeIn(duration: 400.ms, delay: 150.ms);
  }
}

// ── CHILD CARD ────────────────────────────────────────────────────────────────

class _ChildCard extends ConsumerWidget {
  final AppUser child;
  final NumberFormat fmt;
  final int index;
  final WidgetRef ref;

  const _ChildCard({
    required this.child,
    required this.fmt,
    required this.index,
    required this.ref,
  });

  static const _avatarColors = [
    AppColors.emerald,
    Color(0xFF7C3AED),
    Color(0xFFFF6B35),
    Color(0xFF0090FF),
    Color(0xFFFF4D6D),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(childWeeklySummaryProvider(child.id));
    final avatarColor  = _avatarColors[index % _avatarColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.parentDarkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.parentDarkBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/parent/child/${child.id}'),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    // Avatar
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: avatarColor.withValues(alpha: 0.3),
                            width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          child.name.isNotEmpty
                              ? child.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: avatarColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Nom + solde
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            child.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          summaryAsync.when(
                            data: (s) => Text(
                              'Cette semaine · ${fmt.format(s.totalCents / 100)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.emerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            loading: () => const Text('Calcul...',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted)),
                            error: (_, __) => const Text('—'),
                          ),
                        ],
                      ),
                    ),

                    // Chevron
                    const Icon(Icons.chevron_right,
                        color: AppColors.textMuted, size: 20),
                  ],
                ),

                // Barre de progression du bonus
                summaryAsync.when(
                  data: (s) {
                    final max = s.config?.bonusWeeklyMaxCents ?? 0;
                    if (max == 0) return const SizedBox.shrink();
                    final prog =
                        (s.bonusCents / max).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🛡️ ${fmt.format(s.baseCents / 100)}',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11),
                              ),
                              Text(
                                '📵 +${fmt.format(s.bonusCents / 100)} / ${fmt.format(max / 100)}',
                                style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: prog,
                              minHeight: 4,
                              backgroundColor: AppColors.parentDarkBorder,
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.emerald),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                // Bouton Valider inline si solde > 0
                summaryAsync.when(
                  data: (s) {
                    if (s.totalCents == 0) return const SizedBox.shrink();
                    if (!(s.config?.isPaymentDayReached ?? false)) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () =>
                              context.push('/parent/child/${child.id}'),
                          child: Text(
                            'Voir · Valider ${fmt.format(s.totalCents / 100)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: index * 80))
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0);
  }
}

// ── EMPTY STATE ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.emerald.withValues(alpha: 0.2)),
            ),
            child: const Center(
              child: Text('👨‍👩‍👧', style: TextStyle(fontSize: 44)),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ajoutez votre premier enfant',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Un code unique sera généré pour\nque votre enfant rejoigne la famille.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── ADD CHILD DIALOG ──────────────────────────────────────────────────────────

class _AddChildDialog extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddChildDialog({required this.onAdded});

  @override
  ConsumerState<_AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends ConsumerState<_AddChildDialog> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  String? _generatedCode;

  Future<void> _add() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final code = await createChild(_nameCtrl.text.trim());
      setState(() => _generatedCode = code);
      widget.onAdded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.parentDarkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Ajouter un enfant',
          style: TextStyle(
              fontWeight: FontWeight.bold, color: AppColors.textLight)),
      content: _generatedCode == null
          ? TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.textLight),
              decoration: InputDecoration(
                labelText: 'Prénom',
                labelStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.parentDarkBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Donne ce code à ton enfant pour rejoindre la famille :',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _generatedCode!,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _generatedCode == null ? 'Annuler' : 'Fermer',
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        if (_generatedCode == null)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _loading ? null : _add,
            child: _loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Créer',
                    style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}

// ── DATA CLASS ────────────────────────────────────────────────────────────────

class _WeeklySummary {
  final int baseCents;
  final int bonusCents;
  final int totalCents;
  final ChildConfiguration? config;

  const _WeeklySummary({
    required this.baseCents,
    required this.bonusCents,
    required this.totalCents,
    required this.config,
  });
}
