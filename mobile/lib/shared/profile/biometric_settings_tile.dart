import 'package:flutter/material.dart';
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
                    : 'Pour l’activer, cochez « Activer l’empreinte ou Face ID » lors de votre prochaine connexion avec le PIN.');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.fingerprint),
      title: const Text('Empreinte ou Face ID'),
      subtitle: Text(subtitle),
      trailing: _enabled
          ? Switch.adaptive(
              value: true, onChanged: _busy ? null : (_) => _disable())
          : _error != null
              ? IconButton(
                  tooltip: 'Réessayer',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh))
              : null,
    );
  }
}
