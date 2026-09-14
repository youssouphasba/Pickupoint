import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'driver_location_consent.dart';

class DriverBackgroundLocationTile extends StatefulWidget {
  const DriverBackgroundLocationTile({super.key});

  @override
  State<DriverBackgroundLocationTile> createState() =>
      _DriverBackgroundLocationTileState();
}

class _DriverBackgroundLocationTileState
    extends State<DriverBackgroundLocationTile> with WidgetsBindingObserver {
  LocationPermission? _permission;
  bool _busy = false;
  bool _failed = false;
  int _check = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final check = ++_check;
    try {
      final permission = await Geolocator.checkPermission();
      if (!mounted || check != _check) return;
      setState(() {
        _permission = permission;
        _failed = false;
      });
    } catch (_) {
      if (mounted && check == _check) setState(() => _failed = true);
    }
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    try {
      await DriverLocationConsent.ensure(context, userInitiated: true);
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de vérifier la position. Réessayez.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    final allowed = _permission == LocationPermission.always;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.location_on_outlined),
      title: const Text('Position en arrière-plan'),
      subtitle: Text(_failed
          ? 'Vérification indisponible'
          : _permission == null
              ? 'Vérification…'
              : allowed
                  ? 'Toujours autorisée'
                  : 'Autorisation à compléter'),
      trailing: allowed
          ? const Icon(Icons.check_circle_outline)
          : TextButton(
              onPressed: _busy ? null : _activate,
              child: Text(_busy ? 'Patientez…' : 'Activer'),
            ),
    );
  }
}
