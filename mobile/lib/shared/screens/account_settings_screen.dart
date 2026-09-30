import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/auth/auth_provider.dart';
import '../profile/account_actions.dart';
import '../profile/biometric_settings_tile.dart';
import '../profile/profile_widgets.dart';
import '../widgets/change_pin_tile.dart';
import '../widgets/support_whatsapp_tile.dart';

final applicationInfoProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

String notificationsRouteForRole(String role) => switch (role) {
      'driver' => '/driver/notifications',
      'relay_agent' => '/relay/notifications',
      _ => '/client/notifications',
    };

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).valueOrNull;
    final user = auth?.user;
    final application = ref.watch(applicationInfoProvider);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Paramètres'),
          actions: const [SupportWhatsAppButton()]),
      body: user == null
          ? const Center(
              child: Text('Connectez-vous pour accéder à vos paramètres.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ProfileSection(
                    title: 'Besoin d’aide ?',
                    child:
                        SupportWhatsAppTile(contentPadding: EdgeInsets.zero)),
                const ProfileSection(
                    title: 'Mon compte',
                    child: ProfileAction(
                      title: 'Mes informations personnelles',
                      subtitle: 'Photo, coordonnées et informations du compte',
                      icon: Icons.person_outline,
                      route: '/settings/account',
                    )),
                const ProfileSection(
                    title: 'Sécurité',
                    child: Column(children: [
                      ChangePinTile(contentPadding: EdgeInsets.zero),
                      BiometricSettingsTile(),
                    ])),
                ProfileSection(
                    title: 'Notifications',
                    subtitle:
                        'Les préférences s’appliquent au même compte, y compris lorsque vous changez de mode.',
                    child: Column(children: [
                      const ProfileAction(
                          title: 'Préférences de notification',
                          subtitle:
                              'Alertes sur le téléphone, suivi et communications',
                          icon: Icons.tune,
                          route: '/settings/notifications'),
                      ProfileAction(
                          title: 'Historique des notifications',
                          icon: Icons.notifications_outlined,
                          route:
                              notificationsRouteForRole(auth!.effectiveRole)),
                    ])),
                const ProfileSection(
                    title: 'Mes données et confidentialité',
                    child: Column(children: [
                      ProfileAction(
                          title: 'Mes données',
                          subtitle:
                              'Consulter, télécharger ou faire une demande',
                          icon: Icons.folder_shared_outlined,
                          route: '/my-data'),
                      ProfileAction(
                          title: 'Politique de confidentialité',
                          icon: Icons.privacy_tip_outlined,
                          route: '/legal/privacy'),
                      ProfileAction(
                          title: 'Conditions d’utilisation',
                          icon: Icons.gavel_outlined,
                          route: '/legal/cgu'),
                    ])),
                ProfileSection(
                    title: 'À propos de l’application',
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          application.when(
                            data: (info) => Text(
                                '${info.appName} · Version ${info.version} · Build ${info.buildNumber}'),
                            loading: () => const Text('Lecture de la version…'),
                            error: (_, __) => ProfileNotice(
                                message: 'Version momentanément indisponible.',
                                onRetry: () =>
                                    ref.invalidate(applicationInfoProvider)),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.copy_outlined),
                            title:
                                const Text('Copier la référence de mon compte'),
                            subtitle: const Text(
                                'À communiquer au support si nécessaire.'),
                            onTap: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: user.id));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Référence copiée.')));
                              }
                            },
                          ),
                        ])),
                const ProfileSection(
                    title: 'Gestion du compte',
                    child: AccountManagementSection()),
              ],
            ),
    );
  }
}
