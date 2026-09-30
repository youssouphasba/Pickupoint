import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../../../shared/profile/profile_widgets.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/relay_public_details.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../providers/relay_provider.dart';

class RelayProfileScreen extends ConsumerStatefulWidget {
  const RelayProfileScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  ConsumerState<RelayProfileScreen> createState() => _RelayProfileScreenState();
}

class _RelayProfileScreenState extends ConsumerState<RelayProfileScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _relayKey = GlobalKey();
  final _activityKey = GlobalKey();
  final _moneyKey = GlobalKey();
  final _settingsKey = GlobalKey();
  final _supportKey = GlobalKey();
  Timer? _refreshTimer;
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        ref.invalidate(relayPointProfileProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(relayPointProfileProvider);
    }
  }

  @override
  void didUpdateWidget(covariant RelayProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _initialScrollDone = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialScrollDone) return;
      final key = switch (widget.initialSection?.toLowerCase()) {
        'info' => _relayKey,
        'operations' => _activityKey,
        'wallet' => _moneyKey,
        'support' => _supportKey,
        'security' || 'identity' => _settingsKey,
        _ => null,
      };
      final target = key?.currentContext;
      if (target != null) {
        _initialScrollDone = true;
        Scrollable.ensureVisible(target, alignment: 0.05);
      }
    });
  }

  void _preview(RelayPoint relay) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
          child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: RelayPublicDetails(relay: relay)),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).valueOrNull;
    final user = auth?.user;
    final relay = ref.watch(relayPointProfileProvider);
    final wallet = ref.watch(relayWalletProvider);
    _scrollToSection();
    return Scaffold(
      appBar: AppBar(
          title: const Text('Mon profil'),
          actions: const [ProfileAppBarActions()]),
      body: user == null
          ? const Center(
              child: Text('Connectez-vous pour accéder à votre profil.'))
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(authProvider.notifier).fetchMe();
                ref.invalidate(relayPointProfileProvider);
                ref.invalidate(relayPerformanceProvider);
                ref.invalidate(relayWalletProvider);
              },
              child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    ProfileHeader(user: user, role: auth!.effectiveRole),
                    ProfileSection(
                        key: _relayKey,
                        title: 'Mon point relais',
                        child: relay.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => ProfileNotice(
                              message:
                                  'Impossible de charger la fiche du relais. Votre compte et le support restent accessibles.',
                              onRetry: () =>
                                  ref.invalidate(relayPointProfileProvider)),
                          data: (point) => point == null
                              ? const Text(
                                  'Aucun point relais n’est encore rattaché à votre compte. Contactez le support pour vérifier le rattachement.')
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                      Text(point.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      Text(point.addressLabel),
                                      Text(point.city),
                                      const SizedBox(height: 8),
                                      Text(relayOpeningLabel(point),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text(point.isVerified
                                          ? 'Relais validé par Denkma'
                                          : 'Validation du relais en attente'),
                                      Text(point.isActive
                                          ? 'Relais activé dans Denkma'
                                          : 'Relais désactivé dans Denkma'),
                                      const SizedBox(height: 12),
                                      const ProfileAction(
                                          title: 'Modifier ma fiche publique',
                                          subtitle:
                                              'Adresse, position, contact, jours et horaires',
                                          icon:
                                              Icons.edit_location_alt_outlined,
                                          route: '/relay/profile/edit'),
                                      ProfileAction(
                                          title:
                                              'Voir ma fiche comme un client',
                                          subtitle:
                                              'Aperçu des informations actuellement enregistrées',
                                          icon: Icons.visibility_outlined,
                                          onTap: () => _preview(point)),
                                    ]),
                        )),
                    ProfileSection(
                        key: _activityKey,
                        title: 'Mon activité et mon stock',
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (relay.valueOrNull != null)
                                Text(
                                    '${relay.valueOrNull!.currentStock} colis en stock · ${relay.valueOrNull!.availableSlots.clamp(0, relay.valueOrNull!.capacity)} places disponibles'),
                              const ProfileAction(
                                  title: 'Stock et historique des remises',
                                  icon: Icons.inventory_2_outlined,
                                  route: '/relay'),
                              const ProfileAction(
                                  title: 'Réceptionner un colis',
                                  icon: Icons.qr_code_scanner,
                                  route: '/relay/scan-in'),
                            ])),
                    ProfileSection(
                        key: _moneyKey,
                        title: 'Mes gains et règlements',
                        subtitle:
                            'Les règlements avec Denkma sont effectués hors plateforme. Leur validation est distincte de votre solde.',
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              wallet.when(
                                  data: (value) => Text(
                                      'Solde enregistré : ${formatXof(value.balance)}'),
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (_, __) => ProfileNotice(
                                      message:
                                          'Solde momentanément indisponible.',
                                      onRetry: () =>
                                          ref.invalidate(relayWalletProvider))),
                              const ProfileAction(
                                  title: 'Gains et transactions',
                                  icon: Icons.payments_outlined,
                                  route: '/relay/wallet'),
                              const ProfileAction(
                                  title: 'Actions de paiement par colis',
                                  subtitle:
                                      'Ouvrez un colis dans le stock pour consulter les montants et actions.',
                                  icon: Icons.receipt_long_outlined,
                                  route: '/relay'),
                            ])),
                    ProfileSection(
                        key: _supportKey,
                        title: 'Besoin d’aide ?',
                        child: const SupportWhatsAppTile(
                            contentPadding: EdgeInsets.zero)),
                    ProfileSection(
                        key: _settingsKey,
                        title: 'Mon compte personnel',
                        subtitle:
                            'Ces informations concernent le responsable, pas la fiche publique du relais.',
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
                  ]),
            ),
    );
  }
}
