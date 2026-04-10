import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/loading_button.dart';
import '../providers/client_provider.dart';
import '../../../shared/utils/error_utils.dart';

class QuoteScreen extends ConsumerStatefulWidget {
  const QuoteScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  ConsumerState<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends ConsumerState<QuoteScreen> {
  bool _isConfirming = false;
  final _promoController = TextEditingController();
  bool _promoLoading = false;
  Map<String, dynamic>? _promoResult;
  String? _promoError;

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _checkPromoCode() async {
    final code = _promoController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _promoLoading = true;
      _promoError = null;
      _promoResult = null;
    });

    try {
      final quote = _asMap(widget.data['quote']);
      final breakdown = _asMap(quote['breakdown']);
      final formData = _asMap(widget.data['formData']);
      final price = _num(quote['price']);
      final mode = breakdown['delivery_mode']?.toString() ??
          formData['delivery_mode']?.toString() ??
          'relay_to_relay';

      final res = await ref.read(apiClientProvider).checkPromoCode(code, price, mode);
      final data = _asMap(res.data);
      setState(() => _promoResult = data);
    } catch (e) {
      setState(() => _promoError = 'Code invalide ou non applicable');
    } finally {
      if (mounted) setState(() => _promoLoading = false);
    }
  }

  void _removePromo() {
    setState(() {
      _promoResult = null;
      _promoError = null;
      _promoController.clear();
    });
  }

  Future<void> _confirmAndPay() async {
    setState(() => _isConfirming = true);
    try {
      final api = ref.read(apiClientProvider);
      final formData =
          Map<String, dynamic>.from(widget.data['formData'] as Map? ?? const {});
      final pickupVoicePath = formData.remove('pickup_voice_path') as String?;
      final promoCode = _promoResult != null
          ? _promoController.text.trim().toUpperCase()
          : null;
      final payload = {
        ...formData,
        'recipient_name': widget.data['recipient_name'],
        'recipient_phone': widget.data['recipient_phone'],
        if (promoCode != null) 'promo_id': promoCode,
      };

      final res = await api.createParcel(payload);
      final parcelId = res.data['parcel_id'] as String?;
      if (pickupVoicePath != null && parcelId != null) {
        try {
          await api.sendParcelVoice(parcelId, pickupVoicePath);
        } catch (_) {}
      }
      final paymentUrl = res.data['payment_url'] as String?;

      if (!mounted) return;
      if (paymentUrl != null) {
        _showPaymentWebView(paymentUrl);
      } else {
        context.go('/client');
        ref.invalidate(parcelsProvider);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
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
              title: const Text('Paiement securise'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(url)),
                onLoadStop: (controller, uri) {
                  final current = uri.toString();
                  if (current.contains('callback') ||
                      current.contains('status=successful')) {
                    Navigator.pop(context);
                    this.context.go('/client');
                    ref.invalidate(parcelsProvider);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Paiement reussi. Colis cree.'),
                      ),
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
    final quote = _asMap(widget.data['quote']);
    final breakdown = _asMap(quote['breakdown']);
    final total = _num(quote['price']);
    final base = _num(breakdown['base']);
    final distKm = _num(breakdown['distance_km']);
    final distCost = _num(breakdown['distance_cost']);
    final extraKg = _num(breakdown['weight_extra_kg']);
    final weightCost = _num(breakdown['weight_cost']);
    final sousTotal = _num(breakdown['sous_total']);
    final coeff = _num(breakdown['coefficient'], def: 1.0);
    final expressCost = _num(breakdown['express_cost']);
    final isExpress = breakdown['is_express'] == true;
    final whoPays = breakdown['who_pays']?.toString() ?? 'sender';
    final estHours = breakdown['estimated_hours']?.toString() ?? '-';
    final coeffFactors = _asMap(breakdown['coeff_factors']);

    return Scaffold(
      appBar: AppBar(title: const Text('Votre devis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'TOTAL A PAYER',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_promoResult != null) ...[
                    Text(
                      formatXof(total),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    formatXof(_promoResult != null
                        ? (_promoResult!['final_price'] as num?)?.toDouble() ?? total
                        : total),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isExpress ? estHours : 'Estimation livraison : $estHours',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Resume de l envoi'),
            const SizedBox(height: 8),
            _buildOrderSummary(),
            const SizedBox(height: 20),
            _sectionTitle('Detail du prix'),
            const SizedBox(height: 8),
            _row('Prix de base', base),
            _row('Distance (${distKm.toStringAsFixed(1)} km)', distCost),
            if (extraKg > 0)
              _row(
                'Supplement poids (${extraKg.toStringAsFixed(1)} kg)',
                weightCost,
              ),
            const Divider(height: 20),
            _row('Sous-total', sousTotal, bold: true),
            if (coeff != 1.0) ...[
              const SizedBox(height: 4),
              _coeffRow(coeff, coeffFactors),
            ],
            if (isExpress && expressCost > 0) ...[
              const SizedBox(height: 4),
              _row(
                'Supplement express (+30 %)',
                expressCost,
                color: const Color(0xFFFF6B00),
              ),
            ],
            const SizedBox(height: 20),
            _buildPromoSection(),
            const Divider(height: 20),
            _row(
              'TOTAL',
              _promoResult != null
                  ? (_promoResult!['final_price'] as num?)?.toDouble() ?? total
                  : total,
              bold: true,
              large: true,
            ),
            const SizedBox(height: 20),
            _sectionTitle('Informations pratiques'),
            const SizedBox(height: 8),
            _infoCard([
              _infoRow(Icons.schedule, 'Delai estime', estHours),
              _infoRow(
                Icons.payment,
                'Paiement',
                whoPays == 'sender'
                    ? 'Regle par l expediteur'
                    : 'Regle par le destinataire',
              ),
              if (isExpress)
                _infoRow(
                  Icons.bolt,
                  'Mode',
                  'Express - priorite maximale',
                  color: const Color(0xFFFF6B00),
                ),
            ]),
            const SizedBox(height: 24),
            const Text(
              'En confirmant, vous acceptez nos conditions generales de transport.',
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

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    return const <String, dynamic>{};
  }

  Widget _buildPromoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Code promotionnel'),
        const SizedBox(height: 8),
        if (_promoResult != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _promoResult!['promo_title']?.toString() ?? 'Promotion',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                      Text(
                        '-${formatXof((_promoResult!['discount_xof'] as num?)?.toDouble() ?? 0)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _removePromo,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Retirer',
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Ex: DENKMA20',
                    prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    errorText: _promoError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _promoLoading
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : FilledButton(
                      onPressed: _checkPromoCode,
                      child: const Text('OK'),
                    ),
            ],
          ),
      ],
    );
  }

  Widget _buildOrderSummary() {
    final formData = _asMap(widget.data['formData']);
    final recipientName = widget.data['recipient_name']?.toString() ?? '-';
    final recipientPhone = widget.data['recipient_phone']?.toString() ?? '-';
    final weight =
        _num(formData['weight_kg']);
    final declaredValue = _num(formData['declared_value']);
    final whoPays = formData['who_pays']?.toString() ?? 'sender';
    final initiatedBy = formData['initiated_by']?.toString() ?? 'sender';
    final isExpress = formData['is_express'] == true;

    return _infoCard([
      _infoRow(
        Icons.alt_route_outlined,
        'Mode',
        _modeLabel(formData['delivery_mode']?.toString()),
      ),
      _infoRow(Icons.person_outline, 'Destinataire', recipientName),
      _infoRow(Icons.phone_outlined, 'Telephone', recipientPhone),
      _infoRow(Icons.scale_outlined, 'Poids', '${weight.toStringAsFixed(1)} kg'),
      _infoRow(
        Icons.shield_outlined,
        'Valeur declaree',
        formatXof(declaredValue),
      ),
      _infoRow(
        Icons.payments_outlined,
        'Paiement',
        whoPays == 'recipient'
            ? 'Pris en charge par le destinataire'
            : 'Pris en charge par l expediteur',
      ),
      _infoRow(
        Icons.swap_horiz,
        'Initiative',
        initiatedBy == 'recipient'
            ? 'Le destinataire initie la demande'
            : 'L expediteur initie la demande',
      ),
      if (isExpress)
        _infoRow(Icons.bolt_outlined, 'Express', 'Oui'),
    ]);
  }

  double _num(dynamic value, {double def = 0.0}) {
    if (value == null) return def;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? def;
  }

  String _modeLabel(String? mode) {
    switch (mode) {
      case 'relay_to_relay':
        return 'Relais vers relais';
      case 'relay_to_home':
        return 'Relais vers domicile';
      case 'home_to_relay':
        return 'Domicile vers relais';
      case 'home_to_home':
        return 'Domicile vers domicile';
      default:
        return mode ?? '-';
    }
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      );

  Widget _row(
    String label,
    double amount, {
    bool bold = false,
    bool large = false,
    Color? color,
  }) {
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
    final isBoost = coeff > 1.0;
    final color = isBoost ? Colors.orange.shade700 : Colors.green.shade700;
    final pct = ((coeff - 1.0).abs() * 100).toStringAsFixed(0);
    final sign = isBoost ? '+' : '-';
    final label = isBoost
        ? 'Coefficient demande ($sign$pct %)'
        : 'Remise creux ($sign$pct %)';

    final reasons = factors.entries
        .where((entry) => !entry.key.startsWith('_'))
        .map((entry) {
          final key = entry.key;
          final value = entry.value;
          switch (key) {
            case 'rush_hour':
              return 'Heure de pointe';
            case 'lunch_rush':
              return 'Heure du dejeuner';
            case 'night':
              return 'Tarif nuit';
            case 'sunday':
              return 'Tarif dimanche';
            case 'surge_high':
              return 'Forte demande';
            case 'surge_medium':
              return 'Demande elevee';
            case 'low_demand':
              return 'Faible activite';
            case 'loyalty_tier':
              return 'Avantage membre ${value.toString().toUpperCase()}';
            case 'is_frequent':
              return value == true ? 'Bonus fidele' : null;
            default:
              return key;
          }
        })
        .whereType<String>()
        .join(', ');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isBoost ? Icons.trending_up : Icons.trending_down,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (reasons.isNotEmpty)
                  Text(
                    reasons,
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Text(
            '$label : ',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
