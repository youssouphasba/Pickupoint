import 'package:flutter/material.dart';
import '../../../core/models/wallet.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/error_utils.dart';

class WalletTopupDialog extends StatefulWidget {
  const WalletTopupDialog(
      {super.key, required this.options, required this.onSubmit});

  final WalletTopupOptions options;
  final Future<void> Function(int amount) onSubmit;

  @override
  State<WalletTopupDialog> createState() => _WalletTopupDialogState();
}

class _WalletTopupDialogState extends State<WalletTopupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _submitting = false;
  String? _error;

  int? _amount() => int.tryParse(
      _amountController.text.replaceAll(RegExp(r'\s|\u00a0|\u202f'), ''));

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_amount()!);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_submitting,
        child: AlertDialog(
          title: const Text('Recharger le solde'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _amountController,
                    enabled: !_submitting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Montant (FCFA)',
                        border: OutlineInputBorder()),
                    validator: (_) {
                      final amount = _amount();
                      if (amount == null || amount <= 0) {
                        return 'Saisissez un montant entier en FCFA.';
                      }
                      if (amount < widget.options.minimumAmount) {
                        return 'Minimum : ${formatXof(widget.options.minimumAmount)}';
                      }
                      if (amount > widget.options.maximumAmount) {
                        return 'Maximum : ${formatXof(widget.options.maximumAmount)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                      'De ${formatXof(widget.options.minimumAmount)} à ${formatXof(widget.options.maximumAmount)}.'),
                  const SizedBox(height: 12),
                  const Text(
                      'Paiement sécurisé par carte sur Stripe. Votre solde est crédité uniquement après confirmation du paiement.'),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Continuer'),
            ),
          ],
        ),
      );
}
