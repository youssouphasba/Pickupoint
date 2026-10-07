import 'package:flutter/material.dart';
import '../utils/currency_format.dart';

class RecipientCollectionCard extends StatelessWidget {
  const RecipientCollectionCard(
      {super.key,
      required this.plan,
      this.isPaid = false,
      this.showAmount = true});

  final Map<String, dynamic> plan;
  final bool isPaid;
  final bool showAmount;

  @override
  Widget build(BuildContext context) {
    final due = (plan['amount_due_xof'] as num?)?.toDouble() ?? 0;
    final paid = isPaid || plan['status'] == 'paid';
    final collector = switch (plan['collector']) {
      'relay' => 'au relais de retrait',
      'driver' => 'au livreur affecté',
      'denkma' => 'à Denkma',
      _ => null,
    };
    final paymentLabel = showAmount
        ? 'Reste à régler : ${formatXof(due)}'
        : 'Règlement en attente';
    final text = paid
        ? 'Paiement déjà confirmé. Aucun nouvel encaissement.'
        : plan['status'] == 'admin_review' || collector == null
            ? '$paymentLabel. Denkma doit préciser qui encaisse avant la remise. '
                '${showAmount ? 'Ne payez pas une deuxième fois un montant déjà réglé.' : 'N’effectuez aucun nouvel encaissement sans confirmation de Denkma.'}'
            : '$paymentLabel, $collector. La confirmation du règlement est nécessaire avant la remise.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(paid ? Icons.check_circle_outline : Icons.payments_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      ),
    );
  }
}
