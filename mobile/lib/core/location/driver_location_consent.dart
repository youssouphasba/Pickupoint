import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

class DriverLocationConsent {
  static Future<bool> ensureForWork(BuildContext context) async {
    final allowed = await ensure(context, userInitiated: true);
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
      'Denkma collecte et transmet votre position à ses serveurs pour vous '
      'proposer les courses proches et permettre le suivi de vos livraisons '
      'par l’expéditeur, le destinataire et l’équipe Denkma, même lorsque '
      'l’application est fermée ou non utilisée. Appuyez sur « Continuer » '
      'pour donner votre accord avant la demande d’autorisation Android.';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _storageKey = 'driver_location_consent_v1';
  static const _accepted = 'accepted';
  static const _declined = 'declined';
  static const _backgroundPromptKey = 'driver_background_location_prompt_v1';
  static Future<bool>? _pendingRequest;

  static Future<void> _openSettings(Future<bool> Function() open) async {
    final resumed = Completer<void>();
    var leftApp = false;
    final listener = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused) {
        leftApp = true;
      }
      if (state == AppLifecycleState.resumed &&
          leftApp &&
          !resumed.isCompleted) {
        resumed.complete();
      }
    });
    try {
      if (await open()) await resumed.future;
    } finally {
      listener.dispose();
    }
  }

  static Future<bool> _offerSettings(
    BuildContext context, {
    required String title,
    required String message,
    required Future<bool> Function() open,
  }) async {
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    if (accepted != true) return false;
    await _openSettings(open);
    return context.mounted;
  }

  static Future<bool> hasAccepted() async {
    return await _read(_storageKey) == _accepted;
  }

  static Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
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
    final isAndroid =
        context.mounted && Theme.of(context).platform == TargetPlatform.android;
    final savedChoice = await _read(_storageKey);
    if (savedChoice == _declined && !userInitiated) {
      return false;
    }

    final currentPermission = await Geolocator.checkPermission();
    final disclosureRequired = currentPermission == LocationPermission.denied ||
        currentPermission == LocationPermission.deniedForever ||
        (isAndroid && currentPermission != LocationPermission.always);
    if (disclosureRequired || savedChoice != _accepted) {
      if (!context.mounted) return false;
      final accepted = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Autorisation de localisation du livreur'),
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
      if (!context.mounted) return false;
      final returned = await _offerSettings(
        context,
        title: 'Activer la localisation',
        message:
            'Activez la localisation du téléphone pour voir les courses proches.',
        open: Geolocator.openLocationSettings,
      );
      if (!returned || !await Geolocator.isLocationServiceEnabled()) {
        return false;
      }
    }

    var permission = currentPermission;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (!context.mounted) return false;
      final returned = await _offerSettings(
        context,
        title: 'Autoriser la position',
        message:
            'Ouvrez Autorisations, puis Localisation, et autorisez l’accès à votre position.',
        open: Geolocator.openAppSettings,
      );
      if (!returned) return false;
      permission = await Geolocator.checkPermission();
    }

    final backgroundPromptShown =
        isAndroid ? await _read(_backgroundPromptKey) != null : true;
    if (permission == LocationPermission.whileInUse &&
        context.mounted &&
        isAndroid &&
        (userInitiated || !backgroundPromptShown)) {
      final returned = await _offerSettings(
        context,
        title: 'Position en arrière-plan',
        message: 'Pour recevoir les courses proches en arrière-plan, ouvrez '
            'Autorisations > Localisation et choisissez Toujours autoriser.',
        open: Geolocator.openAppSettings,
      );
      if (returned) permission = await Geolocator.checkPermission();
      await _storage.write(key: _backgroundPromptKey, value: 'shown');
    }

    if (isAndroid) return permission == LocationPermission.always;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }
}
