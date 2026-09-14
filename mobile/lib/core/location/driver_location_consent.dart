import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

class DriverLocationConsent {
  static Future<bool> ensureForWork(BuildContext context) async {
    final allowed = await ensure(context, userInitiated: true)
        .timeout(const Duration(seconds: 15));
    if (!allowed || !context.mounted) return false;
    if (Theme.of(context).platform != TargetPlatform.android) return true;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Choisissez Toujours autoriser pour vous rendre disponible '
          'ou accepter une course.',
        ),
      ));
    }
    return false;
  }

  static const disclosureText =
      'Denkma collecte votre position pour vous proposer les courses proches '
      'et actualiser la flotte, même lorsque l’application est fermée ou non utilisée.';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _storageKey = 'driver_location_consent_v1';
  static const _accepted = 'accepted';
  static const _declined = 'declined';
  static const _backgroundPromptKey = 'driver_background_location_prompt_v1';
  static Future<bool>? _pendingRequest;

  static Future<bool> hasAccepted() async {
    return await _storage.read(key: _storageKey) == _accepted;
  }

  static Future<bool> ensure(
    BuildContext context, {
    bool userInitiated = false,
  }) async {
    final pendingRequest = _pendingRequest;
    if (pendingRequest != null) return await pendingRequest;
    final request = _ensure(context, userInitiated: userInitiated);
    _pendingRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_pendingRequest, request)) {
        _pendingRequest = null;
      }
    }
  }

  static Future<bool> _ensure(
    BuildContext context, {
    required bool userInitiated,
  }) async {
    final savedChoice = await _storage.read(key: _storageKey);
    if (savedChoice == _declined && !userInitiated) {
      return false;
    }

    if (savedChoice != _accepted) {
      if (!context.mounted) return false;
      final accepted = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Position du livreur'),
              content: const Text(disclosureText),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Pas maintenant'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Continuer'),
                ),
              ],
            ),
          ) ??
          false;
      await _storage.write(
        key: _storageKey,
        value: accepted ? _accepted : _declined,
      );
      if (!accepted) return false;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Activez la localisation du téléphone.')),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Autorisez la localisation dans les réglages du téléphone.',
            ),
            action: SnackBarAction(
              label: 'Réglages',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
      }
      return false;
    }

    if (permission == LocationPermission.whileInUse &&
        context.mounted &&
        Theme.of(context).platform == TargetPlatform.android &&
        (userInitiated ||
            await _storage.read(key: _backgroundPromptKey) == null)) {
      if (!context.mounted) return false;
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Position en arrière-plan'),
          content: const Text(
            'Pour actualiser votre position et recevoir les courses proches '
            'lorsque Denkma est en arrière-plan, ouvrez Autorisations, '
            'puis Localisation et choisissez Toujours autoriser.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        ),
      );
      await _storage.write(key: _backgroundPromptKey, value: 'shown');
      if (openSettings == true) await Geolocator.openAppSettings();
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }
}
