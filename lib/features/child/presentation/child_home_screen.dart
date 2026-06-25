import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/models/configuration_model.dart';
import '../../../shared/providers/config_provider.dart';
import '../../screen_time/platform/screen_time_service.dart';
import '../../../core/notifications/notification_service.dart';
import 'streak_badge_widget.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _childUserProvider = FutureProvider<AppUser?>((ref) => getCurrentUser());


final _weeklyBonusProvider =
    FutureProvider.family<int, String>((ref, childId) => getWeeklyBonus(childId));

final _weeklyPaidOutChildProvider =
    FutureProvider.family<int, String>((ref, childId) => getWeeklyPaidOut(childId));

final _hasPendingPayoutProvider =
    FutureProvider.family<bool, String>((ref, childId) async {
  final data = await supabase
      .from('payouts')
      .select('id')
      .eq('child_id', childId)
      .eq('status', 'pending')
      .limit(1);
  return (data as List).isNotEmpty;
});

final _todayBonusProvider =
    FutureProvider.family<int, String>((ref, childId) => getTodayBalance(childId));

final _streakChildProvider =
    FutureProvider.family<int, String>((ref, childId) => getStreak(childId));

final _totalSessionsProvider =
    FutureProvider.family<int, String>((ref, childId) async {
  final data = await supabase
      .from('screen_sessions')
      .select('id')
      .eq('child_id', childId);
  return (data as List).length;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ChildHomeScreen extends ConsumerStatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  ConsumerState<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends ConsumerState<ChildHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  RealtimeChannel? _realtimeChannel;
  Timer? _ticker;
  StreamSubscription<Map<String, dynamic>>? _screenSubscription;

  int _sessionSeconds = 0;
  bool _sessionActive = false;
  DateTime? _sessionStartAt;

  // Utilisé pour sauvegarder la session au bon moment
  String? _userId;

  // Suivi du temps d'écran (bien-être numérique) — optionnel, non bloquant.
  bool _usageGranted = false;

  // Exemption d'optimisation batterie (fiabilité du suivi en arrière-plan).
  bool _batteryOk = true;

  // Évite deux synchros simultanées de la file de sessions (anti double-comptage).
  bool _flushing = false;

  // iOS Screen Time (Family Controls) : suivi réel du temps d'écran via
  // l'extension DeviceActivityMonitor. Indépendant du flux argent.
  bool _iosTrackingActive = false;

  late AnimationController _pulseController;
  late AnimationController _ringController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sessionActive) setState(() => _sessionSeconds++);
    });

    WidgetsBinding.instance.addObserver(this);

    // Pré-charge l'userId et souscrit au realtime
    getCurrentUser().then((user) {
      if (!mounted || user == null) return;
      _userId = user.id;
      _realtimeChannel = subscribeToChildBalance(user.id, (balanceCents) {
        if (mounted) {
          ref.invalidate(_weeklyBonusProvider(user.id));
          ref.invalidate(_todayBonusProvider(user.id));
        }
      });
      // Suivi temps d'écran : vérifie la permission et remonte les données.
      _refreshScreenTime();
      _refreshScreenTimeIOS();
      // Synchronise les sessions enregistrées en arrière-plan (app fermée).
      _flushPendingSessions();
    });

    // Détection automatique sur Android
    if (ScreenTimeService.supportsAutoDetection) {
      _screenSubscription =
          ScreenTimeService.screenEventStream.listen(_onScreenEvent);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _ringController.dispose();
    _ticker?.cancel();
    _screenSubscription?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour dans l'app (ex. après avoir accordé la permission dans les
    // réglages), on re-vérifie et on re-synchronise le temps d'écran.
    if (state == AppLifecycleState.resumed) {
      _refreshScreenTime();
      _refreshScreenTimeIOS();
      _flushPendingSessions();
    }
  }

  /// Vérifie la permission "Accès à l'usage" et, si accordée, remonte le
  /// temps d'écran des 7 derniers jours vers Supabase.
  /// Entièrement non bloquant : la moindre erreur est ignorée silencieusement
  /// et n'affecte aucun autre flux de l'app.
  Future<void> _refreshScreenTime() async {
    if (!ScreenTimeService.supportsAutoDetection) return;
    try {
      // État de l'exemption batterie (indépendant de la permission d'usage).
      final batteryOk =
          await ScreenTimeService.isIgnoringBatteryOptimizations();
      if (mounted && batteryOk != _batteryOk) {
        setState(() => _batteryOk = batteryOk);
      }

      final granted = await ScreenTimeService.hasPermission();
      if (mounted && granted != _usageGranted) {
        setState(() => _usageGranted = granted);
      }
      if (!granted || _userId == null) return;
      final days = await ScreenTimeService.getDailyScreenOnMinutes(days: 7);
      await upsertScreenTime(_userId!, days);
    } catch (_) {
      // Silencieux : le suivi du temps d'écran ne doit jamais perturber l'app.
    }
  }

  /// iOS uniquement : si l'autorisation Family Controls est accordée et qu'une
  /// sélection d'apps existe, (re)démarre le monitoring et remonte les minutes
  /// réelles d'usage vers Supabase (même format qu'Android, table screen_time_daily).
  /// Entièrement non bloquant et découplé du flux argent.
  Future<void> _refreshScreenTimeIOS() async {
    if (!Platform.isIOS) return;
    try {
      final granted = await ScreenTimeService.hasPermission();
      final hasSelection = await ScreenTimeService.hasAppSelection();
      final active = granted && hasSelection;
      if (mounted && active != _iosTrackingActive) {
        setState(() => _iosTrackingActive = active);
      }
      if (!active || _userId == null) return;
      // Idempotent : garantit que le monitoring tourne (relancé au démarrage).
      await ScreenTimeService.startScreenTimeMonitoring();
      final days = await ScreenTimeService.getDailyScreenOnMinutes(days: 7);
      if (days.isEmpty) return;
      // Carte « temps d'écran » du parent (usage journalier complet).
      await upsertScreenTime(_userId!, days);

      // Règlement des gains iOS pour aujourd'hui et hier (idempotent côté RPC).
      // La RPC clampe l'usage à la plage active → comparable à Android.
      final df = DateFormat('yyyy-MM-dd');
      final todayKey = df.format(DateTime.now());
      final yesterdayKey =
          df.format(DateTime.now().subtract(const Duration(days: 1)));
      var settled = false;
      for (final d in days) {
        final key = d['day'] as String?;
        if (key == todayKey || key == yesterdayKey) {
          await settleIosScreenTime(_userId!, key!, (d['minutes'] as int?) ?? 0);
          settled = true;
        }
      }
      if (settled && mounted) {
        final id = _userId!;
        ref.invalidate(_weeklyBonusProvider(id));
        ref.invalidate(_todayBonusProvider(id));
        ref.invalidate(_weeklyPaidOutChildProvider(id));
      }
    } catch (_) {
      // Silencieux : ne doit jamais perturber l'app.
    }
  }

  /// iOS : lance le flux d'activation du suivi du temps d'écran
  /// (autorisation Screen Time → choix des apps → démarrage du monitoring).
  Future<void> _activateIOSTracking() async {
    if (!Platform.isIOS) return;
    try {
      await ScreenTimeService.requestPermission();
      final granted = await ScreenTimeService.hasPermission();
      if (!granted) return;
      final count = await ScreenTimeService.presentAppPicker();
      if (count <= 0) return; // annulé ou rien sélectionné
      await ScreenTimeService.startScreenTimeMonitoring();
      await _refreshScreenTimeIOS();
    } catch (_) {
      // Silencieux.
    }
  }

  // ── Gestion des événements écran (Android auto-détection) ────

  void _onScreenEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'screen_off' && !_sessionActive) {
      _startSession();
    } else if (type == 'screen_on' && _sessionActive) {
      _endSession();
    }
  }

  void _startSession() {
    _ringController.forward();
    setState(() {
      _sessionActive = true;
      _sessionStartAt = DateTime.now();
      _sessionSeconds = 0;
    });
  }

  void _endSession() {
    final endAt   = DateTime.now();
    final startAt = _sessionStartAt;
    _ringController.reverse();
    setState(() {
      _sessionActive = false;
      _sessionSeconds = 0;
      _sessionStartAt = null;
    });

    if (ScreenTimeService.supportsAutoDetection) {
      // Android : la session a déjà été enregistrée par le service natif
      // (résistant à la fermeture de l'app) → on synchronise la file.
      _flushPendingSessions();
    } else {
      // iOS (mode manuel) : pas de service natif, on sauvegarde directement.
      if (startAt == null || _userId == null) return;
      saveSession(childId: _userId!, startAt: startAt, endAt: endAt).then((_) {
        final id = _userId!;
        ref.invalidate(_weeklyBonusProvider(id));
        ref.invalidate(_weeklyPaidOutChildProvider(id));
        ref.invalidate(_todayBonusProvider(id));
        ref.invalidate(_streakChildProvider(id));
        ref.invalidate(_totalSessionsProvider(id));
      });
    }
  }

  /// Récupère les sessions enregistrées par le service natif (y compris quand
  /// l'app était fermée) et les synchronise vers Supabase. Android uniquement.
  /// Non bloquant : toute erreur est ignorée.
  Future<void> _flushPendingSessions() async {
    if (!ScreenTimeService.supportsAutoDetection) return;
    final id = _userId;
    if (id == null || _flushing) return;
    _flushing = true;
    try {
      final sessions = await ScreenTimeService.getAndClearPendingSessions();
      if (sessions.isEmpty) return;
      for (final s in sessions) {
        final start = DateTime.fromMillisecondsSinceEpoch(s['start'] as int);
        final end = DateTime.fromMillisecondsSinceEpoch(s['end'] as int);
        await saveSession(childId: id, startAt: start, endAt: end);
      }
      if (!mounted) return;
      ref.invalidate(_weeklyBonusProvider(id));
      ref.invalidate(_weeklyPaidOutChildProvider(id));
      ref.invalidate(_todayBonusProvider(id));
      ref.invalidate(_streakChildProvider(id));
      ref.invalidate(_totalSessionsProvider(id));
    } catch (_) {
      // Silencieux : ne jamais perturber l'app.
    } finally {
      _flushing = false;
    }
  }

  // Toggle manuel pour iOS (ou override Android si besoin)
  void _toggleSession(String childId, ChildConfiguration? _) {
    if (_sessionActive) {
      _userId = childId;
      _endSession();
    } else {
      _startSession();
    }
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  int _sessionBonusCents(ChildConfiguration? config) {
    if (config == null) return 0;
    return (_sessionSeconds / 3600 * config.bonusHourlyRateCents).round();
  }

  @override
  Widget build(BuildContext context) {
    final fmt       = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
    final userAsync = ref.watch(_childUserProvider);

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const Scaffold(
            backgroundColor: AppColors.childBg,
            body: Center(child: CircularProgressIndicator(color: AppColors.emerald)),
          );
        }

        // Cache user.id pour les callbacks
        _userId = user.id;

        final configAsync           = ref.watch(configProvider(user.id));
        final weeklyBonusAsync      = ref.watch(_weeklyBonusProvider(user.id));
        final todayBonusAsync       = ref.watch(_todayBonusProvider(user.id));
        final streakAsync           = ref.watch(_streakChildProvider(user.id));
        final totalSessionsAsync    = ref.watch(_totalSessionsProvider(user.id));
        final paidOutAsync          = ref.watch(_weeklyPaidOutChildProvider(user.id));
        final hasPendingAsync       = ref.watch(_hasPendingPayoutProvider(user.id));
        final config                = configAsync.value;
        // Hors plage horaire : on n'affiche aucun gain en direct (le serveur
        // ne crédite rien non plus). Par défaut "true" si la config charge encore.
        final inHours               = config?.isWithinActiveHours ?? true;
        return Theme(
          data: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: AppColors.childBg,
            colorScheme: const ColorScheme.dark(
              primary: AppColors.emerald,
              surface: AppColors.childSurface,
            ),
          ),
          child: Scaffold(
            backgroundColor: AppColors.childBg,
            body: RefreshIndicator(
              color: AppColors.emerald,
              backgroundColor: AppColors.childSurface,
              onRefresh: () async {
                // Balayer vers le bas → recharge gains, config et versements.
                ref.invalidate(_weeklyBonusProvider(user.id));
                ref.invalidate(_todayBonusProvider(user.id));
                ref.invalidate(_streakChildProvider(user.id));
                ref.invalidate(_totalSessionsProvider(user.id));
                ref.invalidate(_weeklyPaidOutChildProvider(user.id));
                ref.invalidate(_hasPendingPayoutProvider(user.id));
                ref.invalidate(configProvider(user.id));
                await ref.read(_weeklyBonusProvider(user.id).future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                  backgroundColor: AppColors.childBg,
                  expandedHeight: 0,
                  floating: true,
                  pinned: false,
                  leading: const SizedBox.shrink(),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout, color: AppColors.textMuted, size: 20),
                      onPressed: () async {
                        await signOut();
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ],
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([

                      _Greeting(name: user.name, streakAsync: streakAsync),
                      const SizedBox(height: 28),

                      _BalanceHero(
                        weeklyBonusAsync: weeklyBonusAsync,
                        configAsync: configAsync,
                        sessionBonusCents: _sessionBonusCents(config),
                        isActive: _sessionActive && inHours,
                        fmt: fmt,
                      ),
                      const SizedBox(height: 28),

                      _TimerCircle(
                        isActive: _sessionActive,
                        seconds: _sessionSeconds,
                        bonusCents:
                            inHours ? _sessionBonusCents(config) : 0,
                        pulseController: _pulseController,
                        fmt: fmt,
                        formatDuration: _formatDuration,
                        isAutoMode: ScreenTimeService.supportsAutoDetection,
                        onManualToggle: () => _toggleSession(user.id, config),
                        onManualStop: _sessionActive
                            ? () {
                                _userId = user.id;
                                _endSession();
                              }
                            : null,
                      ),
                      if (!inHours && config != null) ...[
                        const SizedBox(height: 16),
                        _OutOfHoursBanner(config: config),
                      ],
                      const SizedBox(height: 24),

                      _DailyChallenge(
                        todayBonusAsync: todayBonusAsync,
                        config: config,
                        fmt: fmt,
                      ),
                      const SizedBox(height: 16),

                      _WeekStrip(config: config),
                      const SizedBox(height: 16),

                      // Guide d'activation du suivi (Android) : étapes claires
                      // avec statut ✅/⚠️ + rassurance vie privée. Visible tant
                      // qu'une des autorisations manque. Non bloquant.
                      if (ScreenTimeService.supportsAutoDetection &&
                          (!_usageGranted || !_batteryOk)) ...[
                        _ScreenTimeGuide(
                          usageGranted: _usageGranted,
                          batteryOk: _batteryOk,
                          onActivateUsage: () async {
                            await ScreenTimeService.requestPermission();
                            // Re-vérifié au retour via didChangeAppLifecycleState.
                          },
                          onActivateBattery: () async {
                            await ScreenTimeService
                                .requestIgnoreBatteryOptimizations();
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // iOS : activation du suivi Screen Time (Family Controls).
                      if (Platform.isIOS && !_iosTrackingActive) ...[
                        _ScreenTimeOptIn(onActivate: _activateIOSTracking),
                        const SizedBox(height: 16),
                      ],

                      streakAsync.when(
                        data: (streak) => todayBonusAsync.when(
                          data: (todayCents) => StreakBadgeWidget(
                            streak: streak,
                            todayMinutes: config != null && config.bonusHourlyRateCents > 0
                                ? (todayCents / (config.bonusHourlyRateCents / 60)).round()
                                : 0,
                            targetMinutes: config?.dailyTargetMinutes ?? 120,
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),

                      streakAsync.when(
                        data: (streak) => totalSessionsAsync.when(
                          data: (total) => BadgesRow(
                            streak: streak,
                            totalSessions: total,
                            totalMinutes: weeklyBonusAsync.when(
                              data: (cents) => config != null && config.bonusHourlyRateCents > 0
                                  ? (cents / (config.bonusHourlyRateCents / 60)).round()
                                  : 0,
                              loading: () => 0,
                              error: (_, __) => 0,
                            ),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 16),

                      weeklyBonusAsync.when(
                        data: (bonus) {
                          final alreadyPaid = paidOutAsync.value ?? 0;
                          final hasPending  = hasPendingAsync.value ?? false;
                          final total = ((config?.baseWeeklyCents ?? 0) + bonus - alreadyPaid).clamp(0, 999999);
                          final paymentDayReached = config?.isPaymentDayReached ?? false;

                          // Solde nul ou déjà versé → rien
                          if (total == 0) return const SizedBox.shrink();

                          // Pas encore le jour de paiement → message discret
                          if (!paymentDayReached) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.childCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.childBorder),
                              ),
                              child: Row(
                                children: [
                                  const Text('📅', style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Tu pourras demander ton versement ${config?.paymentDayLabel != null ? "à partir du ${config!.paymentDayLabel}" : "bientôt"} 😊',
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // Demande déjà en attente → bouton désactivé
                          if (hasPending) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.childCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.hourglass_top, color: AppColors.emerald, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Demande envoyée — en attente du parent',
                                    style: TextStyle(color: AppColors.emerald, fontSize: 14),
                                  ),
                                ],
                              ),
                            );
                          }

                          return _PayoutButton(
                            childId: user.id,
                            totalCents: total,
                            fmt: fmt,
                            onRequested: () {
                              ref.invalidate(_hasPendingPayoutProvider(user.id));
                            },
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        backgroundColor: AppColors.childBg,
        body: Center(child: CircularProgressIndicator(color: AppColors.emerald)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.childBg,
        body: Center(child: Text('Erreur : $e',
            style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

// ── GREETING ──────────────────────────────────────────────────────────────────

class _Greeting extends StatelessWidget {
  final String name;
  final AsyncValue<int> streakAsync;

  const _Greeting({required this.name, required this.streakAsync});

  String get _timeGreeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_timeGreeting, $name 👋',
              style: const TextStyle(
                color: AppColors.textLight,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
            const SizedBox(height: 2),
            Text(
              ScreenTimeService.supportsAutoDetection
                  ? 'Éteins l\'écran pour gagner 💰'
                  : 'Pose ton téléphone et gagne 💰',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
          ],
        ),
        streakAsync.when(
          data: (streak) => streak > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.childCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.childBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '$streak',
                        style: const TextStyle(
                          color: AppColors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms)
              : const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── BALANCE HERO ──────────────────────────────────────────────────────────────

class _BalanceHero extends StatelessWidget {
  final AsyncValue<int> weeklyBonusAsync;
  final AsyncValue<ChildConfiguration?> configAsync;
  final int sessionBonusCents;
  final bool isActive;
  final NumberFormat fmt;

  const _BalanceHero({
    required this.weeklyBonusAsync,
    required this.configAsync,
    required this.sessionBonusCents,
    required this.isActive,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final baseWeekly  = configAsync.when(
        data: (c) => c?.baseWeeklyCents ?? 0, loading: () => 0, error: (_, __) => 0);
    final bonusMax    = configAsync.when(
        data: (c) => c?.bonusWeeklyMaxCents ?? 0, loading: () => 0, error: (_, __) => 0);
    final bonusEarned = weeklyBonusAsync.when(
        data: (c) => c, loading: () => 0, error: (_, __) => 0);
    final total = baseWeekly + bonusEarned + (isActive ? sessionBonusCents : 0);
    final cap   = baseWeekly + bonusMax;
    final progress = cap > 0 ? (total / cap).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.gradientParentCard,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.emeraldDark.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 210,
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(210, 210),
                  painter: _GaugePainter(progress: progress),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Cette semaine',
                        style: TextStyle(color: Colors.white60, fontSize: 13)),
                    Text(
                      fmt.format(total / 100),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ).animate(key: ValueKey(total)).scale(
                          duration: 300.ms,
                          curve: Curves.elasticOut,
                          begin: const Offset(0.95, 0.95),
                          end: const Offset(1, 1),
                        ),
                    Text('sur ${fmt.format(cap / 100)}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                    if (isActive && sessionBonusCents > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '+${fmt.format(sessionBonusCents / 100)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BalancePill(label: '🛡️ Socle', value: fmt.format(baseWeekly / 100)),
              const SizedBox(width: 10),
              _BalancePill(
                label: '📵 Bonus',
                value: '+${fmt.format(bonusEarned / 100)}',
                highlight: bonusEarned > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalancePill extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _BalancePill({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label  $value',
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}

/// Jauge circulaire du compteur d'euros (présentation pure) : remplit l'arc
/// selon `progress` (gains de la semaine / plafond « semaine parfaite »).
class _GaugePainter extends CustomPainter {
  final double progress;
  const _GaugePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 9;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final prog = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      prog,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress;
}

// ── TIMER CIRCLE ──────────────────────────────────────────────────────────────

class _TimerCircle extends StatelessWidget {
  final bool isActive;
  final int seconds;
  final int bonusCents;
  final AnimationController pulseController;
  final NumberFormat fmt;
  final String Function(int) formatDuration;
  final bool isAutoMode;
  final VoidCallback onManualToggle;
  final VoidCallback? onManualStop;

  const _TimerCircle({
    required this.isActive,
    required this.seconds,
    required this.bonusCents,
    required this.pulseController,
    required this.fmt,
    required this.formatDuration,
    required this.isAutoMode,
    required this.onManualToggle,
    this.onManualStop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Cercle principal
        Center(
          child: GestureDetector(
            // Mode iOS : tap pour démarrer/arrêter
            onTap: isAutoMode ? null : onManualToggle,
            child: AnimatedBuilder(
              animation: pulseController,
              builder: (context, child) {
                final pulse = isActive ? 1.0 + pulseController.value * 0.04 : 1.0;
                return Transform.scale(scale: pulse, child: child);
              },
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Halo vert pulsant
                    if (isActive)
                      AnimatedBuilder(
                        animation: pulseController,
                        builder: (_, __) => Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.emerald.withValues(
                                    alpha: 0.15 + pulseController.value * 0.15),
                                blurRadius: 40 + pulseController.value * 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Ring de progression
                    CustomPaint(
                      size: const Size(200, 200),
                      painter: _RingPainter(
                        progress: isActive && seconds > 0
                            ? (seconds % 3600) / 3600.0
                            : 0,
                        color: isActive ? AppColors.emerald : AppColors.childCard,
                        bgColor: AppColors.childBorder,
                      ),
                    ),

                    // Contenu central
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.childCard,
                        border: Border.all(
                          color: isActive
                              ? AppColors.emerald
                              : AppColors.childBorder,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!isActive) ...[
                            Icon(
                              isAutoMode
                                  ? Icons.nightlight_round
                                  : Icons.phone_android,
                              color: AppColors.textMuted,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isAutoMode
                                  ? 'Éteins\nl\'écran'
                                  : 'Poser mon\ntéléphone',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textLight,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isAutoMode
                                  ? 'automatique'
                                  : 'Appuie pour démarrer',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 10),
                            ),
                          ] else ...[
                            Text(
                              formatDuration(seconds),
                              style: const TextStyle(
                                color: AppColors.emerald,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (bonusCents > 0)
                              Text(
                                '+${fmt.format(bonusCents / 100)}',
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ).animate(onPlay: (c) => c.repeat())
                                  .shimmer(
                                      duration: 1500.ms,
                                      color: AppColors.amber),
                            const SizedBox(height: 6),
                            if (!isAutoMode)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.rose.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.rose
                                          .withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  'Arrêter',
                                  style: TextStyle(
                                    color: AppColors.rose,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bouton d'arrêt manuel (Android, session active)
        if (isAutoMode && isActive && onManualStop != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton(
              onPressed: onManualStop,
              child: const Text(
                'Arrêter la session',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bgColor;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    const strokeWidth = 6.0;

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = bgColor
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    if (progress > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          2 * math.pi * progress,
          false,
          Paint()
            ..color = color
            ..strokeWidth = strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── DAILY CHALLENGE ───────────────────────────────────────────────────────────

class _DailyChallenge extends StatelessWidget {
  final AsyncValue<int> todayBonusAsync;
  final ChildConfiguration? config;
  final NumberFormat fmt;

  const _DailyChallenge({
    required this.todayBonusAsync,
    required this.config,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final dailyMax  = config?.dailyMaxCents ?? 300;
    final todayBonus = todayBonusAsync.value ?? 0;
    final progress  = dailyMax > 0 ? (todayBonus / dailyMax).clamp(0.0, 1.0) : 0.0;
    final reached   = progress >= 1.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.childCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: reached
              ? AppColors.emerald.withValues(alpha: 0.5)
              : AppColors.childBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: reached
                      ? AppColors.emerald.withValues(alpha: 0.2)
                      : AppColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  reached ? '✅ OBJECTIF ATTEINT' : '🎯 DÉFI DU JOUR',
                  style: TextStyle(
                    color: reached ? AppColors.emerald : AppColors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                '${fmt.format(todayBonus / 100)} / ${fmt.format(dailyMax / 100)}',
                style: const TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.childBorder,
              valueColor: AlwaysStoppedAnimation(
                  reached ? AppColors.emerald : AppColors.amber),
            ),
          ),
          if (!reached) ...[
            const SizedBox(height: 8),
            Text(
              'Encore ${fmt.format((dailyMax - todayBonus) / 100)} à gagner aujourd\'hui',
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ── WEEK STRIP ────────────────────────────────────────────────────────────────

class _WeekStrip extends StatelessWidget {
  final ChildConfiguration? config;

  const _WeekStrip({required this.config});

  @override
  Widget build(BuildContext context) {
    final now    = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final days   = List.generate(7, (i) => monday.add(Duration(days: i)));
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.childCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.childBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          final day     = days[i];
          final isToday = day.day == now.day &&
              day.month == now.month &&
              day.year == now.year;
          final isPast = day.isBefore(DateTime(now.year, now.month, now.day));

          return Column(
            children: [
              Text(
                labels[i],
                style: TextStyle(
                  color: isToday ? AppColors.emerald : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday
                      ? AppColors.emerald
                      : isPast
                          ? AppColors.childBorder
                          : AppColors.childSurface,
                  border: Border.all(
                    color: isToday ? AppColors.emerald : AppColors.childBorder,
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: isToday ? Colors.white : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── BANDEAU HORS PLAGE HORAIRE ────────────────────────────────────────────────

class _OutOfHoursBanner extends StatelessWidget {
  final ChildConfiguration config;

  const _OutOfHoursBanner({required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('⏰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'En dehors des heures qui rapportent',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tu gagnes de l\'argent entre ${config.activeHoursLabel}. Reviens pendant ce créneau ! 😊',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── OPT-IN TEMPS D'ÉCRAN ──────────────────────────────────────────────────────

/// Guide d'activation du suivi (Android) : explique le pourquoi, rassure sur la
/// vie privée, et liste les étapes avec leur statut (✅ fait / ⚠️ à activer).
/// Purement UI : réutilise les callbacks existants, ne change aucune logique.
class _ScreenTimeGuide extends StatelessWidget {
  final bool usageGranted;
  final bool batteryOk;
  final Future<void> Function() onActivateUsage;
  final Future<void> Function() onActivateBattery;

  const _ScreenTimeGuide({
    required this.usageGranted,
    required this.batteryOk,
    required this.onActivateUsage,
    required this.onActivateBattery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.childCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Active le suivi du temps d\'écran',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Indispensable pour que tes gains comptent. 2 étapes rapides :',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),

          // Étape 1 — accès à l'usage
          _GuideStep(
            done: usageGranted,
            title: 'Accès à l\'usage',
            subtitle: 'Pour mesurer ton temps d\'écran total.',
            onActivate: onActivateUsage,
          ),
          const SizedBox(height: 10),
          // Étape 2 — exemption batterie
          _GuideStep(
            done: batteryOk,
            title: 'Suivi en arrière-plan',
            subtitle: 'Pour que ça compte même app fermée.',
            onActivate: onActivateBattery,
          ),

          const SizedBox(height: 14),
          // Rassurance vie privée
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.childBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Text('🔒', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tes parents voient seulement ton temps d\'écran total — jamais le détail de tes apps.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Une étape du guide : pastille de statut + texte + bouton « Activer » si à faire.
class _GuideStep extends StatelessWidget {
  final bool done;
  final String title;
  final String subtitle;
  final Future<void> Function() onActivate;

  const _GuideStep({
    required this.done,
    required this.title,
    required this.subtitle,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Pastille statut
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppColors.emerald.withValues(alpha: 0.15)
                : AppColors.amber.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Icon(
              done ? Icons.check_rounded : Icons.priority_high_rounded,
              size: 16,
              color: done ? AppColors.emerald : AppColors.amber,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.textMuted,
                ),
              ),
              Text(subtitle,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
          ),
        ),
        if (!done) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: onActivate,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.emerald,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
            ),
            child: const Text('Activer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Text('Fait ✓',
                style: TextStyle(color: AppColors.emerald, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _ScreenTimeOptIn extends StatelessWidget {
  final Future<void> Function() onActivate;

  const _ScreenTimeOptIn({required this.onActivate});

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
          const Text('📊', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suivi du temps d\'écran',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Active-le pour partager ton temps d\'écran avec tes parents.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onActivate,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.emerald,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Activer',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── PAYOUT BUTTON ─────────────────────────────────────────────────────────────

class _PayoutButton extends ConsumerWidget {
  final String childId;
  final int totalCents;
  final NumberFormat fmt;
  final VoidCallback? onRequested;

  const _PayoutButton({
    required this.childId,
    required this.totalCents,
    required this.fmt,
    this.onRequested,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientEmerald,
        borderRadius: BorderRadius.circular(16),
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
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _requestPayout(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.payments_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  'Demander ${fmt.format(totalCents / 100)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestPayout(BuildContext context, WidgetRef ref) async {
    try {
      final user = await getCurrentUser();
      if (user == null) return;
      final data = await supabase
          .from('users')
          .select('id')
          .eq('family_id', user.familyId)
          .eq('role', 'parent')
          .limit(1);
      if ((data as List).isEmpty) return;
      final parentData = data.first;
      final parentId = parentData['id'] as String;
      await requestPayout(
        childId: childId,
        parentId: parentId,
        amountCents: totalCents,
      );
      // Notifie le parent par push + email (non bloquant)
      final currentUser = await getCurrentUser();
      notifyParentPayout(
        childId: childId,
        childName: currentUser?.name ?? 'Votre enfant',
        amountCents: totalCents,
        parentId: parentId,
      );
      onRequested?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande envoyée à tes parents ! 🎉'),
            backgroundColor: AppColors.emerald,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }
}
