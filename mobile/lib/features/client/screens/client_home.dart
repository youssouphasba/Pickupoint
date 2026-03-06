import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../shared/widgets/state_feedback.dart';
import '../providers/client_provider.dart';
import '../../../core/models/parcel.dart';

class ClientHome extends ConsumerWidget {
  const ClientHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parcelsAsync = ref.watch(parcelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes colis'),
        actions: [
          const AccountSwitcherButton(),
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
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(parcelsProvider.future),
        child: parcelsAsync.when(
          data: (parcels) {
            if (parcels.isEmpty) {
              return _buildEmptyState(context);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: parcels.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final parcel = parcels[index];
                return _buildParcelCard(context, ref, parcel);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ErrorStateView(
            message: err.toString(),
            onRetry: () => ref.invalidate(parcelsProvider),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/client/create'),
        label: const Text('Envoyer un colis'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return EmptyStateView(
      icon: Icons.inventory_2_outlined,
      title: 'Aucun colis trouvé',
      subtitle: 'Envoyez votre premier colis dès maintenant !',
      actionLabel: 'Créer un colis',
      onAction: () => context.push('/client/create'),
    );
  }

  Widget _buildParcelCard(BuildContext context, WidgetRef ref, Parcel parcel) {
    final isRecipient = parcel.isRecipientView ?? false;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        onTap: () => context.push('/client/parcel/${parcel.id}'),
        leading: CircleAvatar(
          backgroundColor: isRecipient ? Colors.green.shade50 : Colors.blue.shade50,
          child: Icon(
            isRecipient ? Icons.download : Icons.upload,
            color: isRecipient ? Colors.green.shade600 : Colors.blue.shade600,
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                parcel.trackingCode,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ParcelStatusBadge(status: parcel.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              isRecipient
                  ? 'De : ${parcel.senderName ?? 'Expéditeur'}'
                  : 'Pour : ${parcel.recipientName ?? 'Non défini'}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              parcel.isRelayToHome ? 'Livraison domicile' : 'Retrait en relais',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
