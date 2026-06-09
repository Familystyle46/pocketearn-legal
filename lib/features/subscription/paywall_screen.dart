import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'revenue_cat_service.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  final bool isDismissible;
  const PaywallScreen({super.key, this.isDismissible = true});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _yearlySelected = true;
  bool _loading = false;

  static const _monthlyPrice = '4,99 €';
  static const _yearlyPrice = '39,99 €';
  static const _yearlyMonthly = '3,33 €';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.isDismissible
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.black54),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HERO ──────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    const Text('💰', style: TextStyle(fontSize: 56))
                        .animate()
                        .scale(duration: 600.ms, curve: Curves.elasticOut),
                    const SizedBox(height: 16),
                    const Text(
                      'Tiipee Premium',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tout ce qu\'il faut pour motiver\nvos enfants à poser leur téléphone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── FEATURES ──────────────────────────────────────
              ..._features.map((f) => _FeatureRow(
                    icon: f.$1,
                    title: f.$2,
                    subtitle: f.$3,
                  )),

              const SizedBox(height: 32),

              // ── PLANS ─────────────────────────────────────────
              const Text(
                'Choisissez votre formule',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              _PlanCard(
                title: 'Annuel',
                price: _yearlyPrice,
                subtitle: '$_yearlyMonthly / mois — économisez 33%',
                badge: 'Meilleure offre',
                selected: _yearlySelected,
                onTap: () => setState(() => _yearlySelected = true),
              ),
              const SizedBox(height: 10),
              _PlanCard(
                title: 'Mensuel',
                price: '$_monthlyPrice / mois',
                subtitle: 'Sans engagement',
                selected: !_yearlySelected,
                onTap: () => setState(() => _yearlySelected = false),
              ),

              const SizedBox(height: 24),

              // ── TRIAL BADGE ───────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Text('🎁', style: TextStyle(fontSize: 24)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '7 jours gratuits',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          Text(
                            'Aucun débit avant la fin de l\'essai.\nAnnulez à tout moment.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF388E3C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── CTA ───────────────────────────────────────────
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  backgroundColor: const Color(0xFF2E7D32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _loading ? null : _subscribe,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Commencer l\'essai gratuit',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),

              const SizedBox(height: 12),

              // Restore
              Center(
                child: TextButton(
                  onPressed: _restorePurchases,
                  child: Text(
                    'Restaurer mes achats',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ),
              ),

              // Legal
              Center(
                child: Text(
                  'Abonnement auto-renouvelable. Annulable avant renouvellement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    setState(() => _loading = true);
    final success =
        _yearlySelected ? await purchaseYearly() : await purchaseMonthly();
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        ref.invalidate(subscriptionProvider);
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Achat annulé ou échoué.')),
        );
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _loading = true);
    await restorePurchases();
    if (mounted) {
      setState(() => _loading = false);
      ref.invalidate(subscriptionProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Achats restaurés ✓')),
      );
    }
  }

  static const _features = [
    ('🧒', 'Profils enfants illimités', 'Configurez les règles pour chaque enfant'),
    ('📊', 'Tableau de bord hebdomadaire', 'Suivez les progrès jour par jour'),
    ('💌', 'Email récap automatique', 'Rappel chaque dimanche soir'),
    ('⚙️', 'Règles personnalisables', 'Socle garanti + bonus screen-free'),
    ('📵', 'Mesure automatique Android', 'Via UsageStats — sans triche'),
  ];
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle,
              color: Color(0xFF2E7D32), size: 18),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final String subtitle;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.subtitle,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F5E9) : Colors.grey[50],
          border: Border.all(
            color: selected ? const Color(0xFF2E7D32) : Colors.grey[200]!,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFF2E7D32)
                      : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Center(
                      child: Icon(Icons.circle,
                          size: 12, color: Color(0xFF2E7D32)),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: selected ? const Color(0xFF2E7D32) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
