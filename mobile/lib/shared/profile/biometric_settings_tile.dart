import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/biometric_auth_service.dart';
import '../utils/error_utils.dart';

class BiometricSettingsTile extends ConsumerStatefulWidget {
  const BiometricSettingsTile({super.key});

  @override
  ConsumerState<BiometricSettingsTile> createState() =>
      _BiometricSettingsTileState();
}

class _BiometricSettingsTileState extends ConsumerState<BiometricSettingsTile> {
  bool _busy = true;
  bool _supported = false;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _busy = true);
    try {
      final service = ref.read(biometricAuthServiceProvider);
      final phone = ref.read(authProvider).valueOrNull?.user?.phone ?? '';
      final supported = await service.isSupported();
      final enabled = supported && await service.canUseForPhone(phone);
      if (mounted) {
        setState(() {
          _supported = supported;
          _enabled = enabled;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    if (_busy) return;
    final enabled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _EnableBiometricsDialog(),
    );
    if (enabled == true && mounted) await _load();
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await ref.read(biometricAuthServiceProvider).disable();
      if (mounted) setState(() => _enabled = false);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(biometricAuthServiceProvider, (_, __) => _load());
    final subtitle = _error ??
        (_busy
            ? 'Vérification…'
            : !_supported
                ? 'Aucune biométrie disponible sur cet appareil.'
                : _enabled
                    ? 'Activée sur cet appareil uniquement.'
                    : 'Activez la connexion biométrique avec votre PIN. Ce réglage concerne uniquement cet appareil.');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.fingerprint),
      title: const Text('Empreinte ou Face ID'),
      subtitle: Text(subtitle),
      trailing: _supported && _error == null
          ? Switch.adaptive(
              value: _enabled,
              onChanged:
                  _busy ? null : (value) => value ? _enable() : _disable())
          : _error != null
              ? IconButton(
                  tooltip: 'Réessayer',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh))
              : null,
    );
  }
}

class _EnableBiometricsDialog extends ConsumerStatefulWidget {
  const _EnableBiometricsDialog();

  @override
  ConsumerState<_EnableBiometricsDialog> createState() =>
      _EnableBiometricsDialogState();
}

class _EnableBiometricsDialogState
    extends ConsumerState<_EnableBiometricsDialog> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      setState(() => _error = 'Saisissez votre PIN actuel.');
      return;
    }
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await ref.read(apiClientProvider).verifyPin(pin);
      final service = ref.read(biometricAuthServiceProvider);
      if (!await service.authenticateForSetup()) {
        if (mounted) {
          setState(() => _error =
              'Confirmation biométrique annulée. Rien n’a été activé.');
        }
        return;
      }
      await service.saveCredentials(phone: user.phone, pin: pin);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('Activer l’empreinte ou Face ID'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Confirmez votre PIN, puis votre empreinte ou Face ID. Vous pourrez désactiver cette connexion ici à tout moment.'),
            const SizedBox(height: 16),
            TextField(
              controller: _pin,
              enabled: !_busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12)
              ],
              decoration: const InputDecoration(
                  labelText: 'PIN actuel', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
          ]),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: _busy ? null : _activate,
                child: Text(_busy ? 'Vérification…' : 'Activer')),
          ],
        ),
      );
}
