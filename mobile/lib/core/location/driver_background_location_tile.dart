import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../auth/auth_provider.dart';
import 'driver_location_consent.dart';
import 'driver_presence_service.dart';

class DriverBackgroundLocationTile extends ConsumerStatefulWidget {
  const DriverBackgroundLocationTile({super.key});

  @override
  ConsumerState<DriverBackgroundLocationTile> createState() =>
      _DriverBackgroundLocationTileState();
}

class _DriverBackgroundLocationTileState
    extends ConsumerState<DriverBackgroundLocationTile>
    with WidgetsBindingObserver {
  LocationPermission? _permission;
  LocationAccuracyStatus? _accuracy;
  bool? _serviceEnabled;
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
    if (kIsWeb) return;
    final check = ++_check;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      LocationAccuracyStatus? accuracy;
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        try {
          accuracy = await Geolocator.getLocationAccuracy();
        } catch (_) {}
      }
      if (!mounted || check != _check) return;
      setState(() {
        _serviceEnabled = enabled;
        _permission = permission;
        _accuracy = accuracy;
        _failed = false;
      });
    } catch (_) {
      if (mounted && check == _check) setState(() => _failed = true);
    }
  }

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (await DriverLocationConsent.ensure(context, userInitiated: true)) {
        if (!mounted) return;
        await ref
            .read(driverPresenceServiceProvider)
            .reconcile(ref.read(authProvider).valueOrNull, forceUpload: true);
      }
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Impossible de vérifier la localisation. Réessayez.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final health = ref.watch(driverLocationHealthProvider);
    final android = defaultTargetPlatform == TargetPlatform.android;
    final permissionLabel = switch (_permission) {
      LocationPermission.always => 'Position autorisée en permanence',
      LocationPermission.whileInUse => android
          ? 'Position autorisée pendant l’utilisation · choisissez « Toujours autoriser » pour les courses.'
          : 'Position autorisée pendant l’utilisation',
      LocationPermission.denied ||
      LocationPermission.deniedForever =>
        'Accès à la position non autorisé',
      _ => 'Vérification de l’autorisation…',
    };
    final lastSuccess = health.lastSuccess;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.location_on_outlined),
        title: const Text('État de la localisation'),
        subtitle: Text(_failed
            ? 'Vérification momentanément indisponible.'
            : '${_serviceEnabled == false ? 'Localisation du téléphone désactivée.\n' : ''}$permissionLabel${_accuracy == LocationAccuracyStatus.reduced ? '\nPosition approximative : activez la position précise dans les réglages du téléphone.' : ''}'),
      ),
      Text(lastSuccess == null
          ? 'Aucune transmission confirmée depuis l’ouverture de l’application.'
          : 'Dernière position transmise : ${DateFormat('dd/MM à HH:mm:ss').format(lastSuccess.toLocal())}'),
      if (health.error != null)
        Text(health.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (!health.tracking && lastSuccess == null)
        const Text('Le suivi de position n’est pas actif actuellement.'),
      Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: _busy ? null : _activate,
              icon: const Icon(Icons.refresh),
              label: Text(_busy ? 'Vérification…' : 'Vérifier et actualiser'))),
    ]);
  }
}
