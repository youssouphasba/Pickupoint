import 'package:flutter/material.dart';
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
      final price = _numNullable(quote['price']);
      if (price == null) {
        throw Exception('Prix indisponible');
      }
      final mode = breakdown['delivery_mode']?.toString() ??
          formData['delivery_mode']?.toString() ??
          'relay_to_relay';

      final res =
          await ref.read(apiClientProvider).checkPromoCode(code, price, mode);
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
      final formData = Map<String, dynamic>.from(
        widget.data['formData'] as Map? ?? const {},
      );
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
      if (!mounted) return;
      ref.invalidate(parcelsProvider);
      if (parcelId != null && parcelId.isNotEmpty) {
        context.go('/client/parcel/$parcelId');
      } else {
        context.go('/client');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande confirmée. Le colis a été créé avec succès.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _asMap(widget.data['quote']);
    final breakdown = _asMap(quote['breakdown']);
    final total = _numNullable(quote['price']);
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
    final estHours = breakdown['estimated_hours']?.toString();
    final coeffFactors = _asMap(breakdown['coeff_factors']);
    final awaitingRecipientConfirmation =
        breakdown['awaiting_recipient_confirmation'] == true;
    final awaitingSenderConfirmation =
        breakdown['awaiting_sender_confirmation'] == true;
    final priceAvailable =
        breakdown['price_available'] == true && total != null;
    final durationAvailable = breakdown['duration_available'] == true &&
        estHours != null &&
        estHours.isNotEmpty;
    final finalAmount = _promoResult != null
        ? (_promoResult!['final_price'] as num?)?.toDouble() ?? total
        : total;

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
              child: priceAvailable
                  ? Column(
                      children: [
                        const Text(
                          'MONTANT ESTIMÉ',
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
                          formatXof(finalAmount ?? 0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (durationAvailable)
                          Text(
                            isExpress
                                ? estHours
                                : 'Durée approximative : $estHours',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        const Icon(
                          Icons.pending_actions,
                          color: Colors.white,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Devis en attente',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          awaitingRecipientConfirmation
                              ? 'En attente de la confirmation de la position du destinataire pour calculer le prix et la durée. Vous recevrez une notification.'
                              : awaitingSenderConfirmation
                                  ? 'En attente de la confirmation de la position de collecte pour calculer le prix et la durée. Vous recevrez une notification.'
                                  : 'En attente des informations nécessaires pour calculer le prix et la durée. Vous recevrez une notification.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Résumé de l’envoi'),
            const SizedBox(height: 8),
            _buildOrderSummary(),
            if (priceAvailable) ...[
              const SizedBox(height: 20),
              _sectionTitle('Détail du prix'),
              const SizedBox(height: 8),
              _row('Prix de base', base),
              _row('Distance (${distKm.toStringAsFixed(1)} km)', distCost),
              if (extraKg > 0)
                _row(
                  'Supplément poids (${extraKg.toStringAsFixed(1)} kg)',
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
                  'Supplément express (+30 %)',
                  expressCost,
                  color: const Color(0xFFFF6B00),
                ),
              ],
              const SizedBox(height: 20),
              _buildPromoSection(),
              const Divider(height: 20),
              _row('TOTAL', finalAmount ?? 0, bold: true, large: true),
            ],
            const SizedBox(height: 20),
            _sectionTitle('Informations pratiques'),
            const SizedBox(height: 8),
            _infoCard([
              _infoRow(
                Icons.schedule,
                'Durée approximative',
                durationAvailable
                    ? estHours
                    : 'Disponible après validation du destinataire',
              ),
              _infoRow(
                Icons.payment,
                'Paiement',
                whoPays == 'sender'
                    ? 'Réglé par l’expéditeur'
                    : 'Réglé par le destinataire',
              ),
              if (isExpress)
                _infoRow(
                  Icons.bolt,
                  'Mode',
                  'Express - priorité maximale',
                  color: const Color(0xFFFF6B00),
                ),
            ]),
            const SizedBox(height: 24),
            const Text(
              'En confirmant, vous acceptez nos conditions générales de transport.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            LoadingButton(
              label: 'Confirmer la demande',
              isLoading: _isConfirming,
              onPressed: _confirmAndPay,
            ),
            if (!priceAvailable) ...[
              const SizedBox(height: 12),
              const Text(
                'Le paiement apparaîtra dans le détail du colis dès que le montant final sera disponible.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
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
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, dynamic>{};
  }

  double? _numNullable(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
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
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade700,
                  size: 20,
                ),
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
                    hintText: 'Ex. : DENKMA20',
                    prefixIcon: const Icon(
                      Icons.local_offer_outlined,
                      size: 20,
                    ),
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
    final weight = _num(formData['weight_kg']);
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
      _infoRow(Icons.phone_outlined, 'Téléphone', recipientPhone),
      _infoRow(
        Icons.scale_outlined,
        'Poids',
        '${weight.toStringAsFixed(1)} kg',
      ),
      _infoRow(
        Icons.shield_outlined,
        'Valeur déclarée',
        formatXof(declaredValue),
      ),
      _infoRow(
        Icons.payments_outlined,
        'Paiement',
        whoPays == 'recipient'
            ? 'Pris en charge par le destinataire'
            : 'Pris en charge par l’expéditeur',
      ),
      _infoRow(
        Icons.swap_horiz,
        'Initiative',
        initiatedBy == 'recipient'
            ? 'Le destinataire initie la demande'
            : 'L’expéditeur initie la demande',
      ),
      if (isExpress) _infoRow(Icons.bolt_outlined, 'Express', 'Oui'),
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
        : 'Remise heure creuse ($sign$pct %)';

    final reasons = factors.entries
        .where((entry) => !entry.key.startsWith('_'))
        .map((entry) {
          final key = entry.key;
          final value = entry.value;
          switch (key) {
            case 'rush_hour':
              return 'Heure de pointe';
            case 'lunch_rush':
              return 'Heure du déjeuner';
            case 'night':
              return 'Tarif nuit';
            case 'sunday':
              return 'Tarif dimanche';
            case 'surge_high':
              return 'Forte demande';
            case 'surge_medium':
              return 'Demande elevee';
            case 'low_demand':
              return 'Faible activité';
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
