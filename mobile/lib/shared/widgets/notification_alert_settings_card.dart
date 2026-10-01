import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/notifications/notification_alert_profile.dart';
import '../profile/profile_widgets.dart';

class NotificationAlertSettingsCard extends StatefulWidget {
  const NotificationAlertSettingsCard({super.key, required this.openSettings});

  final Future<bool> Function() openSettings;

  @override
  State<NotificationAlertSettingsCard> createState() =>
      _NotificationAlertSettingsCardState();
}

class _NotificationAlertSettingsCardState
    extends State<NotificationAlertSettingsCard> {
  bool _opening = false;

  Future<void> _openSettings() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (!await widget.openSettings()) {
        throw StateError('Settings unavailable');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Impossible d’ouvrir les réglages. Ouvrez les paramètres du téléphone, puis recherchez Denkma.')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const SizedBox.shrink();
    }
    final android = defaultTargetPlatform == TargetPlatform.android;
    return ProfileSection(
      title: 'Sons et vibrations',
      subtitle: 'Ces réglages concernent ce téléphone, pas votre compte.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(android
              ? 'L’interrupteur « Vibrations des notifications » ci-dessous permet de faire votre choix dans Denkma. Pour régler les sons ou les alertes par catégorie, ouvrez les réglages du téléphone. Les réglages Android restent prioritaires.'
              : 'Dans les réglages Denkma, ouvrez Notifications pour modifier les alertes et les sons. Les vibrations de l’iPhone se règlent séparément dans Réglages → Sons et vibrations ; ce réglage peut affecter les autres applications.'),
          if (android)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: const Text('Quelles catégories régler ?'),
              children: [
                for (final profile in notificationAlertProfiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(profile.channelName),
                    subtitle: Text(profile.channelDescription),
                  ),
                const Text(
                    'Sur certains Samsung, activez d’abord « Gestion des catégories de notification pour chaque appli » dans Paramètres → Notifications → Paramètres avancés. Les intitulés peuvent varier selon le téléphone.'),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _opening ? null : _openSettings,
            icon: _opening
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings_outlined),
            label: Text(_opening ? 'Ouverture…' : 'Ouvrir les réglages Denkma'),
          ),
          const SizedBox(height: 8),
          const Text(
              'Pour continuer à recevoir vos alertes, laissez les notifications autorisées. Modifier la vibration ne change pas vos préférences ci-dessous.'),
        ],
      ),
    );
  }
}
