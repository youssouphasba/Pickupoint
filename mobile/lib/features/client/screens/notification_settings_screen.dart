import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../shared/profile/profile_widgets.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool _saving = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationSettingsProvider);
    }
  }

  Future<void> _update(String key, bool value) async {
    if (_saving) return;
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user == null) return;
    final preferences = {...user.notificationPrefs.toJson(), key: value};
    setState(() => _saving = true);
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile(notificationPrefs: preferences);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _authorize() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final settings = ref.read(notificationSettingsProvider).valueOrNull;
      if (settings?.authorizationStatus == AuthorizationStatus.denied) {
        if (!await Geolocator.openAppSettings()) {
          throw Exception('Impossible d’ouvrir les réglages du téléphone.');
        }
      } else {
        await ref.read(notificationServiceProvider).requestPermission();
      }
      ref.invalidate(notificationSettingsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Widget _toggle(String label, String subtitle, String key, bool value) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(subtitle),
        value: value,
        onChanged: _saving ? null : (value) => _update(key, value),
      );

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).valueOrNull;
    final user = auth?.user;
    final authorization = ref.watch(notificationSettingsProvider);
    final followUp = switch (auth?.effectiveRole) {
      'driver' =>
        'Alertes liées aux missions et aux étapes de remise des colis.',
      'relay_agent' =>
        'Arrivées, remises et changements de statut des colis du relais.',
      _ => 'Changements de statut des colis que vous envoyez ou recevez.',
    };
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Préférences de notification'),
            actions: const [SupportWhatsAppButton()]),
        body: user == null
            ? const Center(
                child: Text('Connectez-vous pour modifier vos préférences.'))
            : ListView(padding: const EdgeInsets.all(16), children: [
                ProfileSection(
                    title: 'Autorisation du téléphone',
                    subtitle:
                        'Les préférences ci-dessous ne remplacent pas l’autorisation donnée dans les réglages du téléphone.',
                    child: authorization.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => ProfileNotice(
                          message:
                              'Impossible de vérifier l’autorisation du téléphone.',
                          onRetry: () =>
                              ref.invalidate(notificationSettingsProvider)),
                      data: (settings) {
                        final status = settings.authorizationStatus;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(switch (status) {
                                AuthorizationStatus.authorized =>
                                  'Notifications autorisées sur ce téléphone',
                                AuthorizationStatus.provisional =>
                                  'Notifications autorisées en mode discret',
                                AuthorizationStatus.denied =>
                                  'Notifications bloquées dans les réglages du téléphone',
                                _ => 'Autorisation pas encore demandée',
                              }),
                              TextButton.icon(
                                  onPressed: _requesting ? null : _authorize,
                                  icon: const Icon(Icons.settings_outlined),
                                  label: Text(_requesting
                                      ? 'Vérification…'
                                      : status == AuthorizationStatus.denied
                                          ? 'Ouvrir les réglages du téléphone'
                                          : 'Vérifier l’autorisation')),
                            ]);
                      },
                    )),
                ProfileSection(
                    title: 'Comment recevoir les alertes',
                    child: Column(children: [
                      _toggle(
                          'Alertes sur mon téléphone',
                          'Recevoir les notifications Denkma sur cet appareil lorsque le téléphone les autorise.',
                          'push',
                          user.notificationPrefs.pushEnabled),
                      _toggle(
                          'Suivi par WhatsApp',
                          'Canal de secours pour le suivi des colis lorsque les notifications de l’application ne peuvent pas être utilisées.',
                          'whatsapp',
                          user.notificationPrefs.whatsappEnabled),
                    ])),
                ProfileSection(
                    title: 'Quelles informations recevoir',
                    child: Column(children: [
                      _toggle(
                          'Suivi des colis et missions',
                          followUp,
                          'parcel_updates',
                          user.notificationPrefs.parcelUpdatesEnabled),
                      _toggle(
                          'Offres et communications',
                          'Communications promotionnelles et offres Denkma, selon votre éligibilité.',
                          'promotions',
                          user.notificationPrefs.promotionsEnabled),
                    ])),
                if (_saving) const LinearProgressIndicator(),
                const Text(
                    'Les changements sont enregistrés automatiquement et s’appliquent au même compte dans tous ses modes.'),
                const SizedBox(height: 16),
                const SupportWhatsAppTile(),
              ]),
      ),
    );
  }
}
