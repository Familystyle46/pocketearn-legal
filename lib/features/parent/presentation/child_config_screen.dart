import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/models/configuration_model.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/providers/config_provider.dart';

class ChildConfigScreen extends ConsumerStatefulWidget {
  final String childId;
  const ChildConfigScreen({super.key, required this.childId});

  @override
  ConsumerState<ChildConfigScreen> createState() => _ChildConfigScreenState();
}

class _ChildConfigScreenState extends ConsumerState<ChildConfigScreen> {
  // ── 2 paramètres exposés au parent ──────────────────────────
  double _baseWeekly  = 10.0;   // récompense garantie (€/sem)
  double _bonusWeekMax = 5.0;   // bonus maximum (€/sem)

  // ── Paramètres avancés (masqués par défaut) ──────────────────
  bool   _advancedOpen    = false;
  double _startHour       = 16;
  double _endHour         = 22;
  double _dailyTargetHours = 2;
  int    _paymentDay      = 7; // dimanche par défaut (réglage masqué en V1)

  bool _loading     = false;
  bool _initialized = false;

  final _fmt = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

  // Taux horaire calculé automatiquement : bonusWeekMax / heures cibles/semaine
  int get _derivedHourlyRateCents {
    final targetHoursPerWeek = _dailyTargetHours * 7;
    if (targetHoursPerWeek <= 0) return 50;
    return (_bonusWeekMax * 100 / targetHoursPerWeek).round().clamp(1, 99999);
  }

  int get _derivedDailyMaxCents => (_bonusWeekMax * 100 / 7).round();

  void _initFromConfig(ChildConfiguration c) {
    if (_initialized) return;
    _initialized = true;
    _baseWeekly      = c.baseWeeklyCents / 100;
    _bonusWeekMax    = (c.bonusWeeklyMaxCents / 100).clamp(0.0, 50.0);
    _startHour       = c.activeHoursStart.toDouble();
    _endHour         = c.activeHoursEnd.toDouble();
    _dailyTargetHours = c.dailyTargetMinutes / 60;
    _paymentDay      = c.paymentDay;
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final existing = await getConfiguration(widget.childId);
      final config = ChildConfiguration(
        id:                   existing?.id ?? '',
        childId:              widget.childId,
        baseWeeklyCents:      (_baseWeekly * 100).round(),
        bonusHourlyRateCents: _derivedHourlyRateCents,
        bonusWeeklyMaxCents:  (_bonusWeekMax * 100).round(),
        dailyMaxCents:        _derivedDailyMaxCents,
        activeHoursStart:     _startHour.round(),
        activeHoursEnd:       _endHour.round(),
        dailyTargetMinutes:   (_dailyTargetHours * 60).round(),
        paymentDay:           _paymentDay,
      );
      await upsertConfiguration(config);
      ref.invalidate(configProvider(widget.childId));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(configProvider(widget.childId));
    configAsync.whenData((c) { if (c != null) _initFromConfig(c); });

    final totalIdeal = _baseWeekly + _bonusWeekMax;

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
        appBar: AppBar(
          backgroundColor: AppColors.parentDarkBg,
          foregroundColor: AppColors.textLight,
          elevation: 0,
          title: const Text(
            'Configurer les règles',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [

            // ── BLOC 1 : ARGENT DE POCHE GARANTI ───────────────
            _ConfigCard(
              color: AppColors.parentDarkCard,
              borderColor: AppColors.parentDarkBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('🛡️', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text(
                        'Récompense garantie',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Versé chaque semaine, quoi qu\'il arrive',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  _StepperControl(
                    value: _fmt.format(_baseWeekly),
                    caption: '/ semaine',
                    valueColor: AppColors.textLight,
                    onMinus: () => setState(() =>
                        _baseWeekly = (_baseWeekly - 1).clamp(0, 100).toDouble()),
                    onPlus: () => setState(() =>
                        _baseWeekly = (_baseWeekly + 1).clamp(0, 100).toDouble()),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── BLOC 2 : BONUS MAXIMUM ──────────────────────────
            _ConfigCard(
              color: AppColors.parentDarkCard,
              borderColor: AppColors.emerald.withValues(alpha: 0.25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('📵', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text(
                        'Bonus écran éteint',
                        style: TextStyle(
                          color: AppColors.textLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Gagné en plus du socle si l\'écran est éteint',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  _StepperControl(
                    value: _fmt.format(_bonusWeekMax),
                    caption: 'max / semaine',
                    valueColor: AppColors.emerald,
                    onMinus: () => setState(() =>
                        _bonusWeekMax = (_bonusWeekMax - 0.5).clamp(0, 50).toDouble()),
                    onPlus: () => setState(() =>
                        _bonusWeekMax = (_bonusWeekMax + 0.5).clamp(0, 50).toDouble()),
                  ),
                  // Taux automatique info
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.parentDarkBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '≈ ${_fmt.format(_derivedHourlyRateCents / 100)}/h · max ${_fmt.format(_derivedDailyMaxCents / 100)}/jour',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── RÉCAPITULATIF ───────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.gradientParentCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('🛡️ Garanti / semaine',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(_fmt.format(_baseWeekly),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('📵 Bonus max / semaine',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('+ ${_fmt.format(_bonusWeekMax)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Semaine parfaite',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text(
                        _fmt.format(totalIdeal),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── JOUR DE PAIEMENT : masqué en V1 pour simplifier l'onboarding.
            // Défaut = dimanche (aligné au récap hebdo). La logique est conservée
            // (_paymentDay toujours sauvegardé) ; réexposer ce réglage ici en v1.1.

            // ── PARAMÈTRES AVANCÉS (accordéon) ──────────────────
            _AdvancedSection(
              isOpen: _advancedOpen,
              startHour: _startHour,
              endHour: _endHour,
              dailyTargetHours: _dailyTargetHours,
              onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
              onRangeChanged: (start, end) => setState(() {
                _startHour = start;
                _endHour   = end;
              }),
              onTargetChanged: (v) =>
                  setState(() => _dailyTargetHours = v),
            ),

            const SizedBox(height: 24),

            AppButton(
              label: 'Enregistrer',
              onPressed: _save,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }
}

// ── ADVANCED SECTION ──────────────────────────────────────────────────────────

class _AdvancedSection extends StatelessWidget {
  final bool isOpen;
  final double startHour;
  final double endHour;
  final double dailyTargetHours;
  final VoidCallback onToggle;
  final void Function(double, double) onRangeChanged;
  final ValueChanged<double> onTargetChanged;

  const _AdvancedSection({
    required this.isOpen,
    required this.startHour,
    required this.endHour,
    required this.dailyTargetHours,
    required this.onToggle,
    required this.onRangeChanged,
    required this.onTargetChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.parentDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.parentDarkBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.tune,
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Paramètres avancés',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    isOpen ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            const Divider(color: AppColors.parentDarkBorder, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Plages horaires comptabilisées',
                    style: TextStyle(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${startHour.round()}h → ${endHour.round()}h',
                    style: const TextStyle(
                        color: AppColors.emerald,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.emerald,
                      thumbColor: AppColors.emerald,
                      inactiveTrackColor: AppColors.parentDarkBorder,
                    ),
                    child: RangeSlider(
                      values: RangeValues(startHour, endHour),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      labels: RangeLabels(
                        '${startHour.round()}h',
                        '${endHour.round()}h',
                      ),
                      onChanged: (v) => onRangeChanged(v.start, v.end),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Objectif quotidien',
                    style: TextStyle(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dailyTargetHours.round()}h de pause / jour',
                    style: const TextStyle(
                        color: AppColors.emerald,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.emerald,
                      thumbColor: AppColors.emerald,
                      inactiveTrackColor: AppColors.parentDarkBorder,
                    ),
                    child: Slider(
                      value: dailyTargetHours,
                      min: 0.5,
                      max: 6,
                      divisions: 11,
                      label: '${dailyTargetHours.round()}h',
                      onChanged: onTargetChanged,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────────────────────

/// Contrôle tactile − valeur + (remplace les sliders). Purement visuel : les
/// callbacks ajustent l'état exactement comme avant.
class _StepperControl extends StatelessWidget {
  final String value;
  final String caption;
  final Color valueColor;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _StepperControl({
    required this.value,
    required this.caption,
    required this.valueColor,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundStepBtn(icon: Icons.remove, onTap: onMinus),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              caption,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        _RoundStepBtn(icon: Icons.add, onTap: onPlus),
      ],
    );
  }
}

class _RoundStepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundStepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.parentDarkBg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.emerald, size: 24),
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final Widget child;

  const _ConfigCard({
    required this.color,
    required this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
