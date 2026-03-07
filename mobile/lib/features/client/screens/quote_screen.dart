import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/client_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/currency_format.dart';

class QuoteScreen extends ConsumerStatefulWidget {
  const QuoteScreen({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  ConsumerState<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends ConsumerState<QuoteScreen> {
  bool _isConfirming = false;

  Future<void> _confirmAndPay() async {
    setState(() => _isConfirming = true);
    try {
      final api = ref.read(apiClientProvider);

      final formData = Map<String, dynamic>.from(widget.data['formData'] as Map);
      final payload = {
        ...formData,
        'recipient_name':  widget.data['recipient_name'],
        'recipient_phone': widget.data['recipient_phone'],
      };

      final res = await api.createParcel(payload);
      final paymentUrl = res.data['payment_url'] as String?;

      if (!mounted) return;

      if (paymentUrl != null) {
        _showPaymentWebView(paymentUrl);
      } else {
        context.go('/client');
        ref.invalidate(parcelsProvider);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la création : $e')),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  void _showPaymentWebView(String url) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            AppBar(
              title: const Text('Paiement sécurisé'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(url)),
                onLoadStop: (controller, url) {
                  if (url.toString().contains('callback') ||
                      url.toString().contains('status=successful')) {
                    Navigator.pop(context);
                    this.context.go('/client');
                    ref.invalidate(parcelsProvider);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Paiement réussi ! Colis créé.')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote     = widget.data['quote'] as Map<String, dynamic>;
    final total     = (quote['price'] as num).toDouble();
    final breakdown = (quote['breakdown'] as Map<String, dynamic>?) ?? {};

    final base         = _num(breakdown['base']);
    final distKm       = _num(breakdown['distance_km']);
    final distCost     = _num(breakdown['distance_cost']);
    final extraKg      = _num(breakdown['weight_extra_kg']);
    final weightCost   = _num(breakdown['weight_cost']);
    final sousTotal    = _num(breakdown['sous_total']);
    final coeff        = _num(breakdown['coefficient'], def: 1.0);
    final expressCost  = _num(breakdown['express_cost']);
    final isExpress    = breakdown['is_express'] as bool? ?? false;
    final whoPays      = breakdown['who_pays'] as String? ?? 'sender';
    final estHours     = breakdown['estimated_hours'] as String? ?? '—';
    final coeffFactors = (breakdown['coeff_factors'] as Map<String, dynamic>?) ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Votre devis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Prix total mis en avant ─────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                const Text('TOTAL À PAYER',
                    style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(
                  formatXof(total),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  isExpress ? estHours : 'Estimation livraison : $estHours',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            // ── Détail du calcul ─────────────────────────────────────────
            _sectionTitle('Détail du prix'),
            const SizedBox(height: 8),
            _row('Prix de base', base),
            _row('Distance (${distKm.toStringAsFixed(1)} km)', distCost),
            if (extraKg > 0) _row('Supplément poids (${extraKg.toStringAsFixed(1)} kg)', weightCost),
            const Divider(height: 20),
            _row('Sous-total', sousTotal, bold: true),

            // Coefficient dynamique
            if (coeff != 1.0) ...[
              const SizedBox(height: 4),
              _coeffRow(coeff, coeffFactors),
            ],

            // Express
            if (isExpress && expressCost > 0) ...[
              const SizedBox(height: 4),
              _row('Supplément express (+40 %)', expressCost,
                  color: const Color(0xFFFF6B00)),
            ],

            const Divider(height: 20),
            _row('TOTAL', total, bold: true, large: true),

            const SizedBox(height: 20),

            // ── Infos pratiques ──────────────────────────────────────────
            _sectionTitle('Informations pratiques'),
            const SizedBox(height: 8),
            _infoCard([
              _infoRow(Icons.schedule, 'Délai estimé', estHours),
              _infoRow(
                Icons.payment,
                'Paiement',
                whoPays == 'sender' ? 'Réglé par l\'expéditeur' : 'Réglé par le destinataire (contre-remboursement)',
              ),
              if (isExpress)
                _infoRow(Icons.bolt, 'Mode', 'Express — priorité maximale',
                    color: const Color(0xFFFF6B00)),
            ]),

            const SizedBox(height: 24),

            // Conditions + bouton
            const Text(
              'En confirmant, vous acceptez nos conditions générales de transport.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            LoadingButton(
              label: whoPays == 'recipient'
                  ? 'Confirmer la commande'
                  : 'Confirmer et payer',
              isLoading: _isConfirming,
              onPressed: _confirmAndPay,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  double _num(dynamic v, {double def = 0.0}) =>
      v == null ? def : (v as num).toDouble();

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      );

  Widget _row(String label, double amount,
      {bool bold = false, bool large = false, Color? color}) {
    final style = TextStyle(
      fontSize: large ? 18 : 14,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatXof(amount), style: style),
        ],
      ),
    );
  }

  Widget _coeffRow(double coeff, Map<String, dynamic> factors) {
    final isBoost   = coeff > 1.0;
    final color     = isBoost ? Colors.orange.shade700 : Colors.green.shade700;
    final pct       = ((coeff - 1.0).abs() * 100).toStringAsFixed(0);
    final sign      = isBoost ? '+' : '-';
    final label     = isBoost ? 'Coefficient demande ($sign$pct %)' : 'Remise creux ($sign$pct %)';

    final reasons = factors.entries
        .where((e) => !e.key.startsWith('_'))
        .map((e) {
          final k = e.key;
          final v = e.value;
          return switch (k) {
            'rush_hour'    => 'Heure de pointe',
            'lunch_rush'   => 'Heure du déjeuner',
            'night'        => 'Tarif nuit',
            'sunday'       => 'Tarif dimanche',
            'surge_high'   => 'Forte demande',
            'surge_medium' => 'Demande élevée',
            'low_demand'   => 'Faible activité',
            'loyalty_tier' => 'Avantage membre ${v.toString().toUpperCase()}',
            'is_frequent'  => v == true ? 'Bonus Fidèle (+10 livraisons)' : null,
            _              => k,
          };
        })
        .whereType<String>()
        .join(', ');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(isBoost ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            if (reasons.isNotEmpty)
              Text(reasons, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
          ]),
        ),
      ]),
    );
  }

  Widget _infoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: children),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: color ?? Colors.grey),
        const SizedBox(width: 8),
        Text('$label : ', style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
            textAlign: TextAlign.right,
          ),
        ),
      ]),
    );
  }
}
