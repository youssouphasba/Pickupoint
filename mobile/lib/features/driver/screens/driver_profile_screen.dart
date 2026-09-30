import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/location/driver_background_location_tile.dart';
import '../../../core/location/driver_location_consent.dart';
import '../../../core/location/driver_presence_service.dart';
import '../../../shared/profile/profile_widgets.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../providers/driver_provider.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key, this.initialSection});
  final String? initialSection;

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  final _scrollController = ScrollController();
  final _availabilityKey = GlobalKey();
  final _documentsKey = GlobalKey();
  final _activityKey = GlobalKey();
  final _moneyKey = GlobalKey();
  final _settingsKey = GlobalKey();
  final _supportKey = GlobalKey();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scrollToSection();
  }

  @override
  void didUpdateWidget(covariant DriverProfileScreen oldWidget) {
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
        'performance' => _activityKey,
        'availability' => _availabilityKey,
        'kyc' || 'documents' => _documentsKey,
        'wallet' || 'referral' || 'parrainage' => _moneyKey,
        'support' => _supportKey,
        'identity' || 'notifications' || 'security' => _settingsKey,
        _ => null,
      };
      final target = key?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.05);
    });
  }

  Future<void> _refresh() async {
    await ref.read(authProvider.notifier).fetchMe();
    ref.invalidate(driverWalletProvider);
    await ref.read(driverWalletProvider.future);
  }

  Future<void> _toggleAvailability() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = ref.read(authProvider).valueOrNull?.user;
      if (user == null) return;
      if (!await canLeaveDriverAccount(ref)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Terminez ou libérez votre course active avant de modifier votre disponibilité.')));
        }
        return;
      }
      if (!mounted) return;
      if (!user.isAvailable &&
          !await DriverLocationConsent.ensureForWork(context)) {
        return;
      }
      if (!mounted) return;
      final response = await ref.read(apiClientProvider).toggleAvailability();
      final available = response.data['is_available'] as bool? ?? false;
      ref.read(authProvider.notifier).updateUserAvailability(available);
      unawaited(ref.read(driverPresenceServiceProvider).reconcile(
          ref.read(authProvider).valueOrNull,
          forceUpload: available));
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
    final auth = ref.watch(authProvider).valueOrNull;
    final user = auth?.user;
    final wallet = ref.watch(driverWalletProvider);
    final missions = ref.watch(myMissionsProvider);
    final hasLockedMission = hasActiveDriverMission(missions.valueOrNull ?? []);
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
                  ProfileSection(
                      key: _availabilityKey,
                      title: 'Ma disponibilité',
                      subtitle:
                          'Votre disponibilité pour les nouvelles courses est distincte de votre connexion et du suivi GPS.',
                      child: Column(children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(user.isAvailable
                              ? 'Disponible pour les nouvelles courses'
                              : 'Non disponible pour les nouvelles courses'),
                          subtitle: Text(hasLockedMission
                              ? 'Une course est en cours. Terminez-la ou libérez-la avant de modifier votre disponibilité.'
                              : 'Une course déjà acceptée reste à effectuer et à suivre.'),
                          value: user.isAvailable,
                          onChanged: _busy ||
                                  user.isBanned ||
                                  !user.isActive ||
                                  hasLockedMission ||
                                  missions.isLoading ||
                                  missions.hasError
                              ? null
                              : (_) => _toggleAvailability(),
                        ),
                        if (missions.hasError)
                          ProfileNotice(
                              message:
                                  'Impossible de vérifier vos courses en cours. Actualisez avant de modifier votre disponibilité.',
                              onRetry: () =>
                                  ref.invalidate(myMissionsProvider)),
                        if (!user.isActive || user.isBanned)
                          const ProfileNotice(
                              message:
                                  'Votre compte ne permet pas de vous rendre disponible. Contactez le support.'),
                        if (user.profilePictureStatus != 'approved')
                          ProfileAction(
                              title: profilePhotoLabel(user),
                              subtitle:
                                  'Une photo approuvée est nécessaire pour recevoir les missions.',
                              icon: Icons.account_circle_outlined,
                              route: '/settings/account'),
                        const DriverBackgroundLocationTile(),
                      ])),
                  ProfileSection(
                      key: _documentsKey,
                      title: 'Mes documents',
                      child: ProfileAction(
                        title: identityVerificationLabel(user.kycStatus),
                        subtitle:
                            'Pièce d’identité, justificatif livreur et dates d’expiration',
                        icon: Icons.verified_user_outlined,
                        route: '/driver/documents',
                      )),
                  ProfileSection(
                      key: _activityKey,
                      title: 'Mes missions et performances',
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                '${user.deliveriesCompleted} livraisons terminées · Niveau ${user.level}'),
                            const SizedBox(height: 6),
                            Text(user.totalRatingsCount == 0
                                ? 'Aucun avis pour le moment'
                                : '${user.averageRating.toStringAsFixed(1)} / 5 · ${user.totalRatingsCount} avis'),
                            const ProfileAction(
                                title: 'Mes missions',
                                icon: Icons.two_wheeler,
                                route: '/driver'),
                            const ProfileAction(
                                title: 'Missions terminées',
                                subtitle:
                                    'Ouvrir le récapitulatif d’une livraison',
                                icon: Icons.task_alt,
                                route: '/driver/missions/completed'),
                            const ProfileAction(
                                title: 'Mes performances',
                                icon: Icons.insights_outlined,
                                route: '/driver/performance'),
                          ])),
                  ProfileSection(
                      key: _moneyKey,
                      title: 'Mes gains et commissions',
                      subtitle:
                          'Les paiements des clients et le solde destiné aux commissions sont distincts.',
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            wallet.when(
                              data: (value) => Text(
                                  'Solde pour les commissions : ${formatXof(value.balance)}'),
                              loading: () => const LinearProgressIndicator(),
                              error: (_, __) => ProfileNotice(
                                  message: 'Solde momentanément indisponible.',
                                  onRetry: () =>
                                      ref.invalidate(driverWalletProvider)),
                            ),
                            const ProfileAction(
                                title: 'Solde et transactions',
                                subtitle:
                                    'Rechargements et commissions des courses',
                                icon: Icons.account_balance_wallet_outlined,
                                route: '/driver/wallet'),
                            const ProfileAction(
                                title: 'Mon parrainage',
                                subtitle:
                                    'Conditions, objectifs et primes réglées hors plateforme',
                                icon: Icons.card_giftcard_outlined,
                                route: '/driver/referral'),
                          ])),
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
