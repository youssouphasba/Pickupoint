import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/error_utils.dart';

class ReferralPaymentDialog extends ConsumerStatefulWidget {
  const ReferralPaymentDialog(
      {super.key, required this.record, required this.beneficiary});
  final Map<String, dynamic> record;
  final String beneficiary;

  @override
  ConsumerState<ReferralPaymentDialog> createState() =>
      _ReferralPaymentDialogState();
}

class _ReferralPaymentDialogState extends ConsumerState<ReferralPaymentDialog> {
  final _reference = TextEditingController();
  final _note = TextEditingController();
  DateTime _paidAt = DateTime.now();
  bool _checked = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final created =
        DateTime.tryParse(widget.record['created_at']?.toString() ?? '')
                ?.toLocal() ??
            _paidAt;
    final date = await showDatePicker(
        context: context,
        initialDate: _paidAt,
        firstDate: created.isAfter(_paidAt) ? _paidAt : created,
        lastDate: DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_paidAt));
    if (time != null && mounted) {
      setState(() => _paidAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute));
    }
  }

  Future<void> _confirm() async {
    if (_sending || !_checked) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final payment = Map<String, dynamic>.from(
          (widget.record['payments'] as Map)[widget.beneficiary] as Map);
      await ref.read(apiClientProvider).confirmReferralPayment(
          widget.record['referral_id'] as String,
          beneficiary: widget.beneficiary,
          amountXof: (payment['amount_xof'] as num).toInt(),
          paidAt: _paidAt,
          reference: _reference.text.trim(),
          note: _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = Map<String, dynamic>.from(
        (widget.record['payments'] as Map)[widget.beneficiary] as Map);
    final beneficiary = widget.beneficiary == 'sponsor' ? 'parrain' : 'filleul';
    final name = widget.record['${widget.beneficiary}_name']?.toString() ?? '';
    return PopScope(
        canPop: !_sending,
        child: AlertDialog(
          title: const Text('Paiement hors plateforme'),
          scrollable: true,
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Prime du $beneficiary : ${formatXof((payment['amount_xof'] as num).toDouble())}'),
                if (name.isNotEmpty) Text(name),
                const SizedBox(height: 12),
                const Text(
                    'Confirmez uniquement un paiement déjà effectué. Aucun argent n’est envoyé et aucun wallet n’est crédité.'),
                TextButton(
                    onPressed: _sending ? null : _chooseDate,
                    child: Text(
                        'Payé le ${DateFormat('dd/MM/yyyy à HH:mm').format(_paidAt)}')),
                TextField(
                    controller: _reference,
                    enabled: !_sending,
                    maxLength: 120,
                    decoration: const InputDecoration(
                        labelText: 'Référence (facultatif)')),
                TextField(
                    controller: _note,
                    enabled: !_sending,
                    maxLength: 300,
                    decoration: const InputDecoration(
                        labelText: 'Note interne (facultatif)')),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _checked,
                    title: const Text(
                        'Denkma a payé ce bénéficiaire hors plateforme.'),
                    onChanged: _sending
                        ? null
                        : (value) => setState(() => _checked = value ?? false)),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]),
          actions: [
            TextButton(
                onPressed:
                    _sending ? null : () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: !_sending && _checked ? _confirm : null,
                child: Text(_sending ? 'Confirmation…' : 'Confirmer')),
          ],
        ));
  }
}
