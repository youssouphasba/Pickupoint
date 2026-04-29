import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/notifications/notifications_bell_button.dart';
import '../../../shared/notifications/notification_permission_banner.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/state_feedback.dart';
import '../providers/client_provider.dart';

class ClientHome extends ConsumerWidget {
  const ClientHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parcelsAsync = ref.watch(parcelsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes colis'),
          actions: [
            const AccountSwitcherButton(),
            const NotificationsBellButton(route: '/client/notifications'),
            IconButton(
              icon: const Icon(Icons.handshake_outlined),
              tooltip: 'Devenir partenaire',
              onPressed: () => context.push('/client/partnership'),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: parcelsAsync.maybeWhen(
              data: (parcels) {
                final active = parcels.where((p) => !_isTerminal(p.status)).length;
                final done = parcels.where((p) => _isTerminal(p.status)).length;
                return TabBar(
                  tabs: [
                    Tab(text: 'En cours${active > 0 ? ' ($active)' : ''}'),
                    Tab(text: 'Terminés${done > 0 ? ' ($done)' : ''}'),
                  ],
                );
              },
              orElse: () => const TabBar(
                tabs: [Tab(text: 'En cours'), Tab(text: 'Terminés')],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            const NotificationPermissionBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(parcelsProvider.future),
                child: parcelsAsync.when(
                  data: (parcels) {
                    final active = parcels.where((p) => !_isTerminal(p.status)).toList();
                    final done = parcels.where((p) => _isTerminal(p.status)).toList();
                    return TabBarView(
                      children: [
                        _ParcelList(
                          parcels: active,
                          emptyTitle: 'Aucun colis en cours',
                          emptySubtitle: 'Vos envois et réceptions actifs apparaîtront ici.',
                        ),
                        _ParcelList(
                          parcels: done,
                          emptyTitle: 'Aucun colis terminé',
                          emptySubtitle: 'L\'historique de vos livraisons s\'affichera ici.',
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => ErrorStateView(
                    message: err.toString(),
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

}

class _ParcelList extends StatelessWidget {
  const _ParcelList({
    required this.parcels,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<Parcel> parcels;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (parcels.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
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
      itemCount: parcels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _ParcelCard(parcel: parcels[index]),
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
                        ? 'De ${parcel.senderName ?? 'Expediteur'}'
                        : 'Pour ${parcel.recipientName ?? 'Destinataire'}',
                  ),
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: formatDate(parcel.createdAt),
                  ),
                  if (parcel.totalPrice != null)
                    _MetaChip(
                      icon: Icons.payments_outlined,
                      label: formatXof(parcel.totalPrice!),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (parcel.paymentStatus != null || parcel.etaText != null)
                Row(
                  children: [
                    if (parcel.paymentStatus != null)
                      Expanded(
                        child: Text(
                          'Paiement: ${_paymentLabel(parcel)}',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: const Text(
                    'Remise finale actuellement bloquee par le paiement.',
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
    final status = parcel.paymentStatus ?? '-';
    if (parcel.whoPays == 'recipient' && status != 'paid') {
      return 'contre-remboursement';
    }
    return status;
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

