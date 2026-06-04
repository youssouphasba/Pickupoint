import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../utils/error_utils.dart';

class ChangePinTile extends ConsumerWidget {
  const ChangePinTile({super.key, this.contentPadding});

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: contentPadding,
      leading: const Icon(Icons.password_outlined),
      title: const Text('Modifier mon PIN'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showChangePinDialog(context, ref),
    );
  }

  Future<void> _showChangePinDialog(BuildContext context, WidgetRef ref) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? errorText;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Modifier mon PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PinField(controller: currentCtrl, label: 'PIN actuel'),
              const SizedBox(height: 12),
              _PinField(controller: newCtrl, label: 'Nouveau PIN'),
              const SizedBox(height: 12),
              _PinField(controller: confirmCtrl, label: 'Confirmer'),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final currentPin = currentCtrl.text.trim();
                      final newPin = newCtrl.text.trim();
                      final confirmPin = confirmCtrl.text.trim();
                      if (!_isValidPin(currentPin) || !_isValidPin(newPin)) {
                        setDialogState(
                          () => errorText = 'Le PIN doit contenir 4 chiffres.',
                        );
                        return;
                      }
                      if (newPin != confirmPin) {
                        setDialogState(
                          () => errorText = 'Les deux nouveaux PIN diffèrent.',
                        );
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        errorText = null;
                      });
                      try {
                        await ref.read(apiClientProvider).updatePin({
                          'current_pin': currentPin,
                          'new_pin': newPin,
                        });
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PIN modifié.')),
                        );
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          busy = false;
                          errorText = friendlyError(e);
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Valider'),
            ),
          ],
        ),
      ),
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  bool _isValidPin(String value) {
    return value.length == 4 && RegExp(r'^\d{4}$').hasMatch(value);
  }
}

class _PinField extends StatelessWidget {
  const _PinField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
