import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/notifications/notifications_bell_button.dart';
import '../../../shared/notifications/notification_permission_banner.dart';
import '../../../shared/promotions/campaign_banner.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/state_feedback.dart';
import '../../driver/providers/driver_provider.dart';
import '../providers/client_provider.dart';

class ClientHome extends ConsumerStatefulWidget {
  const ClientHome({super.key});

  @override
  ConsumerState<ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends ConsumerState<ClientHome>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        ref.invalidate(parcelsProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(parcelsProvider);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(foregroundNotificationRefreshProvider, (_, __) {
      ref.invalidate(parcelsProvider);
    });
    final parcelsAsync = ref.watch(parcelsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Denkma'),
          actions: [
            const AccountSwitcherButton(),
            const NotificationsBellButton(route: '/client/notifications'),
            IconButton(
              tooltip: 'Devenir partenaire',
              icon: const Icon(Icons.handshake_outlined),
              onPressed: () => context.push('/client/partnership'),
            ),
            IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
              onPressed: () => _logout(context, ref),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: parcelsAsync.maybeWhen(
              data: (parcels) {
                final active =
                    parcels.where((p) => !_isTerminal(p.status)).length;
                final done = parcels.where((p) => _isTerminal(p.status)).length;
                return TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  tabs: [
                    Tab(text: 'En cours${active > 0 ? ' ($active)' : ''}'),
                    Tab(text: 'Terminés${done > 0 ? ' ($done)' : ''}'),
                  ],
                );
              },
              orElse: () => const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'En cours'),
                  Tab(text: 'Terminés'),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(parcelsProvider.future),
                child: parcelsAsync.when(
                  data: (parcels) {
                    final active =
                        parcels.where((p) => !_isTerminal(p.status)).toList();
                    final done =
                        parcels.where((p) => _isTerminal(p.status)).toList();
                    return TabBarView(
                      children: [
                        _ParcelList(
                          parcels: active,
                          emptyTitle: 'Aucun colis en cours',
                          emptySubtitle:
                              'Vos envois et réceptions actifs apparaîtront ici.',
                          header: _ClientHomeHeader(
                            activeCount: active.length,
                            onSend: () => context.push('/client/create'),
                            onStats: () => context.push('/client/statistics'),
                            onRelay: () => context.push('/client/relays'),
                          ),
                        ),
                        _ParcelList(
                          parcels: done,
                          emptyTitle: 'Aucun colis terminé',
                          emptySubtitle:
                              'L\'historique de vos livraisons s\'affichera ici.',
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) => ErrorStateView(
                    message: friendlyError(err),
                    onRetry: () => ref.invalidate(parcelsProvider),
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/client/create'),
          label: const Text('Envoyer un colis'),
          icon: const Icon(Icons.add),
        ),
      ),
    );
  }

  static bool _isTerminal(String status) {
    return const {
      'delivered',
      'cancelled',
      'expired',
      'disputed',
      'returned',
    }.contains(status);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (!await _canLogout(context, ref) || !context.mounted) return;
    await ref.read(authProvider.notifier).logout();
  }

  Future<bool> _canLogout(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user?.role != 'driver') return true;

    try {
      final canLeave = await canLeaveDriverAccount(ref);
      if (canLeave) return true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terminez ou libérez votre course active avant de quitter votre compte.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de vérifier vos courses en cours. Réessayez dans un instant.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
}

class _ClientWelcomeSection extends StatelessWidget {
  const _ClientWelcomeSection({
    required this.activeCount,
    required this.onSend,
    required this.onStats,
    required this.onRelay,
  });

  final int activeCount;
  final VoidCallback onSend;
  final VoidCallback onStats;
  final VoidCallback onRelay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primary,
                  colors.primary.withValues(alpha: 0.82)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Envoyez. Suivez. Recevez.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        activeCount == 0
                            ? 'Votre prochaine livraison commence ici.'
                            : '$activeCount livraison${activeCount > 1 ? 's' : ''} en cours',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.add_box_outlined,
                  label: 'Envoyer',
                  color: colors.primary,
                  onTap: onSend,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.insights_outlined,
                  label: 'Stats',
                  color: Colors.teal.shade700,
                  onTap: onStats,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.storefront_outlined,
                  label: 'Relais',
                  color: Colors.deepOrange.shade700,
                  onTap: onRelay,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryModesGuide extends StatelessWidget {
  const _DeliveryModesGuide();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        scrollDirection: Axis.horizontal,
        children: [
          _ModeCard(
            icon: Icons.home_outlined,
            title: 'Domicile → domicile',
            subtitle: 'Simple et direct',
            color: Color(0xFF1A73E8),
            steps: [
              'Choisissez le mode domicile → domicile.',
              'Capturez la position de départ.',
              'Indiquez le nom et le numéro du destinataire.',
              'Le destinataire peut confirmer sa position dans l’application ou via le lien WhatsApp.',
              'Vérifiez le récapitulatif puis confirmez l’envoi.',
            ],
          ),
          _ModeCard(
            icon: Icons.home_work_outlined,
            title: 'Domicile → relais',
            subtitle: 'Retrait flexible',
            color: Color(0xFF00897B),
            steps: [
              'Choisissez le mode domicile → relais.',
              'Capturez la position de départ.',
              'Recherchez et choisissez le relais de retrait.',
              'Indiquez les informations du destinataire.',
              'Vérifiez le récapitulatif puis confirmez l’envoi.',
            ],
          ),
          _ModeCard(
            icon: Icons.storefront_outlined,
            title: 'Relais → domicile',
            subtitle: 'Livraison à la porte',
            color: Color(0xFFE65100),
            steps: [
              'Choisissez le relais de départ.',
              'Indiquez le nom et le numéro du destinataire.',
              'Le destinataire peut confirmer sa position dans l’application ou via le lien WhatsApp.',
              'Vérifiez le récapitulatif puis confirmez l’envoi.',
            ],
          ),
          _ModeCard(
            icon: Icons.swap_horiz,
            title: 'Relais → relais',
            subtitle: 'Pratique et économique',
            color: Color(0xFF6A1B9A),
            steps: [
              'Choisissez le relais de départ.',
              'Choisissez le relais de retrait.',
              'Indiquez les informations du destinataire.',
              'Vérifiez le récapitulatif puis confirmez l’envoi.',
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.steps,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _showModeExplanation(context, title, subtitle, steps),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 190,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientHomeHeader extends StatelessWidget {
  const _ClientHomeHeader({
    required this.activeCount,
    required this.onSend,
    required this.onStats,
    required this.onRelay,
  });

  final int activeCount;
  final VoidCallback onSend;
  final VoidCallback onStats;
  final VoidCallback onRelay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const NotificationPermissionBanner(),
        _ClientWelcomeSection(
          activeCount: activeCount,
          onSend: onSend,
          onStats: onStats,
          onRelay: onRelay,
        ),
        const CampaignBanner(role: 'client'),
        const _DeliveryModesGuide(),
      ],
    );
  }
}

void _showModeExplanation(
  BuildContext context,
  String title,
  String subtitle,
  List<String> steps,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 18),
              ...steps.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                              radius: 12,
                              child: Text('${entry.key + 1}',
                                  style: const TextStyle(fontSize: 12))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(entry.value)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ParcelList extends StatelessWidget {
  const _ParcelList({
    required this.parcels,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.header,
  });

  final List<Parcel> parcels;
  final String emptyTitle;
  final String emptySubtitle;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (parcels.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (header != null) header!,
          const SizedBox(height: 80),
          EmptyStateView(
            icon: Icons.inventory_2_outlined,
            title: emptyTitle,
            subtitle: emptySubtitle,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: parcels.length + (header == null ? 0 : 1),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        if (header != null && index == 0) return header!;
        final parcelIndex = header == null ? index : index - 1;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration:
              Duration(milliseconds: 260 + (parcelIndex.clamp(0, 5) * 35)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - value)),
              child: child,
            ),
          ),
          child: _ParcelCard(parcel: parcels[parcelIndex]),
        );
      },
    );
  }
}

class _ParcelCard extends StatelessWidget {
  const _ParcelCard({required this.parcel});

  final Parcel parcel;

  @override
  Widget build(BuildContext context) {
    final isRecipient = parcel.isRecipientView ?? false;
    final statusColor = parcel.deliveryBlockedByPayment
        ? Colors.red.shade700
        : Colors.blueGrey.shade700;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/client/parcel/${parcel.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: isRecipient
                        ? Colors.green.shade50
                        : Colors.blue.shade50,
                    child: Icon(
                      isRecipient ? Icons.download : Icons.upload,
                      color: isRecipient
                          ? Colors.green.shade700
                          : Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parcel.trackingCode,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _modeLabel(parcel.deliveryMode),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ParcelStatusBadge(status: parcel.status),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: isRecipient
                        ? Icons.person_outline
                        : Icons.outbox_outlined,
                    label: isRecipient
                        ? 'De ${parcel.senderName ?? 'Expéditeur'}'
                        : 'Pour ${parcel.recipientName ?? 'Destinataire'}',
                  ),
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: formatDate(parcel.createdAt),
                  ),
                  _MetaChip(
                    icon: Icons.payments_outlined,
                    label: parcel.totalPrice != null
                        ? formatXof(parcel.totalPrice!)
                        : 'Prix en attente',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (parcel.whoPays != null || parcel.etaText != null)
                Row(
                  children: [
                    if (parcel.whoPays != null)
                      Expanded(
                        child: Text(
                          'Règlement : ${_paymentLabel(parcel)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (parcel.etaText != null)
                      Expanded(
                        child: Text(
                          parcel.etaText!,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              if (parcel.deliveryBlockedByPayment) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: const Text(
                    'Remise finale actuellement bloquée par le règlement.',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case 'relay_to_relay':
        return 'Relais vers relais';
      case 'relay_to_home':
        return 'Relais vers domicile';
      case 'home_to_relay':
        return 'Domicile vers relais';
      case 'home_to_home':
        return 'Domicile vers domicile';
      default:
        return mode;
    }
  }

  static String _paymentLabel(Parcel parcel) {
    if (parcel.whoPays == 'recipient') {
      return 'au livreur par le destinataire';
    }
    return 'au livreur par l’expéditeur';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }
}
