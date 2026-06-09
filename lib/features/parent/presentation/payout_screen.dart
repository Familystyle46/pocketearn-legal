import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../shared/models/earning_model.dart';
import 'package:intl/intl.dart';

final _payoutsProvider =
    FutureProvider.family<List<Payout>, String>((ref, childId) async {
  final user = await getCurrentUser();
  if (user == null) return [];
  final all = await getPendingPayouts(user.id);
  // Filtre uniquement les payouts de cet enfant
  return all.where((p) => p.childId == childId).toList();
});

final _balanceProvider =
    FutureProvider.family<int, String>((ref, childId) => getMonthlyBalance(childId));

class PayoutScreen extends ConsumerWidget {
  final String childId;
  final _fmt = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
  final _dateFmt = DateFormat('d MMM', 'fr_FR');

  PayoutScreen({super.key, required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payoutsAsync = ref.watch(_payoutsProvider(childId));
    final balanceAsync = ref.watch(_balanceProvider(childId));

    return Scaffold(
      appBar: AppBar(title: const Text('Valider le paiement')),
      body: Column(
        children: [
          balanceAsync.when(
            data: (cents) => _BalanceBanner(amountCents: cents, fmt: _fmt),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Expanded(
            child: payoutsAsync.when(
              data: (payouts) => payouts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('✅', style: TextStyle(fontSize: 48)),
                          SizedBox(height: 12),
                          Text('Aucun paiement en attente'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: payouts.length,
                      itemBuilder: (_, i) => _PayoutCard(
                        payout: payouts[i],
                        fmt: _fmt,
                        dateFmt: _dateFmt,
                        onValidate: () async {
                          await validatePayout(payouts[i].id);
                          ref.invalidate(_payoutsProvider(childId));
                          ref.invalidate(_balanceProvider(childId));
                        },
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceBanner extends StatelessWidget {
  final int amountCents;
  final NumberFormat fmt;

  const _BalanceBanner({required this.amountCents, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Solde accumulé ce mois',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            fmt.format(amountCents / 100),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
          ),
        ],
      ),
    );
  }
}

class _PayoutCard extends StatelessWidget {
  final Payout payout;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final VoidCallback onValidate;

  const _PayoutCard({
    required this.payout,
    required this.fmt,
    required this.dateFmt,
    required this.onValidate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.euro)),
        title: Text(
          fmt.format(payout.amountCents / 100),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Demandé le ${dateFmt.format(payout.createdAt)}'),
        trailing: FilledButton(
          onPressed: onValidate,
          child: const Text('Valider'),
        ),
      ),
    );
  }
}
