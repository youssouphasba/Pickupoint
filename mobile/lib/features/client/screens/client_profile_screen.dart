import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/providers/user_stats_provider.dart';
import '../../../shared/profile/profile_widgets.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../widgets/client_loyalty_card.dart';

class ClientProfileScreen extends ConsumerStatefulWidget {
  const ClientProfileScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  ConsumerState<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState extends ConsumerState<ClientProfileScreen> {
  final _scrollController = ScrollController();
  final _activityKey = GlobalKey();
  final _advantagesKey = GlobalKey();
  final _settingsKey = GlobalKey();
  final _supportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollToSection();
  }

  @override
  void didUpdateWidget(covariant ClientProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) _scrollToSection();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = switch (widget.initialSection?.toLowerCase()) {
        'stats' || 'kpis' => _activityKey,
        'loyalty' || 'fidelity' || 'referral' || 'parrainage' => _advantagesKey,
        'settings' || 'preferences' || 'security' => _settingsKey,
        'support' => _supportKey,
        _ => null,
      };
      final target = key?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.05);
    });
  }

  Future<void> _refresh() async {
    await ref.read(authProvider.notifier).fetchMe();
    ref.invalidate(clientLoyaltyProvider);
    ref.invalidate(userStatsProvider);
    await ref.read(userStatsProvider.future);
  }

  void _showQr(String id, String name) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Mon code d’identification',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          QrImageView(data: id, size: 200, backgroundColor: Colors.white),
          Text(name),
          const SizedBox(height: 12),
          const Text(
              'Présentez ce code à un agent relais pour vous identifier.'),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).valueOrNull;
    final user = auth?.user;
    final stats = ref.watch(userStatsProvider);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Mon profil'),
          actions: const [ProfileAppBarActions()]),
      body: user == null
          ? const Center(
              child: Text('Connectez-vous pour accéder à votre profil.'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  ProfileHeader(user: user, role: auth!.effectiveRole),
                  const ProfileSection(
                      title: 'Mes adresses',
                      child: ProfileAction(
                        title: 'Adresses favorites',
                        subtitle:
                            'Retrouvez-les lorsque vous choisissez une position.',
                        icon: Icons.place_outlined,
                        route: '/client/favorites',
                      )),
                  ProfileSection(
                      key: _activityKey,
                      title: 'Mon activité',
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            stats.when(
                              data: (data) =>
                                  Wrap(spacing: 12, runSpacing: 10, children: [
                                Chip(
                                    label: Text(
                                        '${data['parcels_sent'] ?? 0} envoyés')),
                                Chip(
                                    label: Text(
                                        '${data['parcels_received'] ?? 0} reçus')),
                                Chip(
                                    label: Text(
                                        '${data['parcels_active'] ?? 0} en cours')),
                                Chip(
                                    label: Text(
                                        '${data['parcels_delivered'] ?? 0} livrés')),
                                Chip(
                                    label: Text(
                                        '${data['parcels_cancelled'] ?? 0} annulés')),
                                Chip(
                                    label: Text(
                                        '${formatXof((data['client_monthly_spent_xof'] as num?)?.toDouble() ?? 0)} ce mois')),
                              ]),
                              loading: () => const LinearProgressIndicator(),
                              error: (_, __) => ProfileNotice(
                                  message:
                                      'Votre activité est momentanément indisponible.',
                                  onRetry: () =>
                                      ref.invalidate(userStatsProvider)),
                            ),
                            const ProfileAction(
                                title: 'Mes colis',
                                subtitle: 'Envois, réceptions et historique',
                                icon: Icons.inventory_2_outlined,
                                route: '/client'),
                            const ProfileAction(
                                title: 'Mes statistiques',
                                subtitle: 'Activité, délais et dépenses',
                                icon: Icons.insights_outlined,
                                route: '/client/statistics'),
                            ProfileAction(
                                title: 'Mon code d’identification',
                                icon: Icons.qr_code,
                                onTap: () => _showQr(user.id, user.name)),
                          ])),
                  ProfileSection(
                      key: _advantagesKey,
                      title: 'Mes avantages',
                      child: const Column(children: [
                        ClientLoyaltyCard(),
                        ProfileAction(
                            title: 'Historique de fidélité',
                            icon: Icons.history,
                            route: '/client/loyalty-history'),
                        ProfileAction(
                            title: 'Mon parrainage',
                            subtitle: 'Invitations, conditions et primes',
                            icon: Icons.card_giftcard_outlined,
                            route: '/client/referral'),
                      ])),
                  if (!auth.canSwitchToClient)
                    const ProfileSection(
                        title: 'Devenir partenaire',
                        child: ProfileAction(
                            title: 'Livreur ou point relais',
                            subtitle:
                                'Consulter les conditions et déposer une candidature',
                            icon: Icons.handshake_outlined,
                            route: '/client/partnership')),
                  ProfileSection(
                      key: _supportKey,
                      title: 'Besoin d’aide ?',
                      child: const SupportWhatsAppTile(
                          contentPadding: EdgeInsets.zero)),
                  ProfileSection(
                      key: _settingsKey,
                      title: 'Mon compte et mes préférences',
                      child: const Column(children: [
                        ProfileAction(
                            title: 'Mes données',
                            subtitle: 'Consulter ou télécharger mes données',
                            icon: Icons.folder_shared_outlined,
                            route: '/my-data'),
                        ProfileAction(
                            title: 'Paramètres',
                            subtitle:
                                'Notifications, sécurité et confidentialité',
                            icon: Icons.settings_outlined,
                            route: '/settings'),
                      ])),
                ],
              ),
            ),
    );
  }
}
