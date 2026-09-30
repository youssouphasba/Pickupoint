import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/biometric_auth_service.dart';
import '../utils/error_utils.dart';

class ChangePinTile extends ConsumerWidget {
  const ChangePinTile({super.key, this.contentPadding});

  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authenticated =
        ref.watch(authProvider).valueOrNull?.isAuthenticated == true;
    return ListTile(
      contentPadding: contentPadding,
      leading: const Icon(Icons.password_outlined),
      title: const Text('Modifier mon PIN'),
      trailing: const Icon(Icons.chevron_right),
      onTap: !authenticated
          ? null
          : () async {
              final changed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const _ChangePinDialog(),
              );
              if (changed == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN modifié.')),
                );
              }
            },
    );
  }
}

class _ChangePinDialog extends ConsumerStatefulWidget {
  const _ChangePinDialog();

  @override
  ConsumerState<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends ConsumerState<_ChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final currentPin = _current.text.trim();
    final newPin = _next.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(currentPin) ||
        !RegExp(r'^\d{4}$').hasMatch(newPin)) {
      setState(() => _error = 'Le PIN doit contenir 4 chiffres.');
      return;
    }
    if (newPin != _confirmation.text.trim()) {
      setState(() => _error = 'Les deux nouveaux PIN diffèrent.');
      return;
    }
    final phone = ref.read(authProvider).valueOrNull?.user?.phone;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await ref.read(apiClientProvider).updatePin({
        'current_pin': currentPin,
        'new_pin': newPin,
      });
      if (!mounted) return;
      if (phone != null) {
        final biometrics = ref.read(biometricAuthServiceProvider);
        try {
          await biometrics.updatePinIfEnabled(phone, newPin);
        } catch (_) {
          try {
            await biometrics.disable();
          } catch (_) {}
        }
        if (!mounted) return;
        ref.invalidate(biometricAuthServiceProvider);
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Modifier mon PIN'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _PinField(
                  controller: _current, label: 'PIN actuel', enabled: !_busy),
              const SizedBox(height: 12),
              _PinField(
                  controller: _next, label: 'Nouveau PIN', enabled: !_busy),
              const SizedBox(height: 12),
              _PinField(
                  controller: _confirmation,
                  label: 'Confirmer',
                  enabled: !_busy),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Valider'),
            ),
          ],
        ),
      );
}

class _PinField extends StatelessWidget {
  const _PinField(
      {required this.controller, required this.label, required this.enabled});

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
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
