import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../providers/admin_provider.dart';

class AdminParcelsScreen extends ConsumerStatefulWidget {
  const AdminParcelsScreen({super.key});

  @override
  ConsumerState<AdminParcelsScreen> createState() => _AdminParcelsScreenState();
}

class _AdminParcelsScreenState extends ConsumerState<AdminParcelsScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parcelsAsync = ref.watch(adminParcelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion colis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminParcelsProvider),
          ),
        ],
      ),
      body: parcelsAsync.when(
        data: (parcels) {
          final filtered = parcels.where(_matchesFilters).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText:
                        'Code, expediteur, destinataire ou livreur en charge',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SummaryRow(parcels: parcels),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _buildFilterChip('Tous', 'all'),
                    _buildFilterChip('Actifs', 'active'),
                    _buildFilterChip('Bloques paiement', 'blocked_payment'),
                    _buildFilterChip('Litiges', 'disputed'),
                    _buildFilterChip('Livres', 'delivered'),
                    _buildFilterChip('Annules', 'cancelled'),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun colis ne correspond aux filtres en cours.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final parcel = filtered[index];
                          return _ParcelCard(
                            parcel: parcel,
                            onOpenAudit: () => context
                                .push('/admin/parcels/${parcel.id}/audit'),
                            onOpenActions: () =>
                                _showStatusActionSheet(context, ref, parcel),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _statusFilter == value,
        onSelected: (_) => setState(() => _statusFilter = value),
      ),
    );
  }

  bool _matchesFilters(Parcel parcel) {
    final query = _searchCtrl.text.trim().toLowerCase();

    final matchesStatus = switch (_statusFilter) {
      'all' => true,
      'active' => !const {
          'delivered',
          'cancelled',
          'returned',
        }.contains(parcel.status),
      'blocked_payment' => parcel.deliveryBlockedByPayment,
      _ => parcel.status == _statusFilter,
    };

    if (!matchesStatus) {
      return false;
    }

    if (query.isEmpty) {
      return true;
    }

    return parcel.trackingCode.toLowerCase().contains(query) ||
        (parcel.senderName ?? '').toLowerCase().contains(query) ||
        (parcel.recipientName ?? '').toLowerCase().contains(query) ||
        (parcel.driverName ?? '').toLowerCase().contains(query) ||
        (parcel.recipientPhone ?? '').toLowerCase().contains(query);
  }

  void _showStatusActionSheet(
    BuildContext context,
    WidgetRef ref,
    Parcel parcel,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parcel.trackingCode,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(_modeLabel(parcel.deliveryMode)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, color: Colors.blue),
              title: const Text('Voir audit complet'),
              subtitle: const Text('Timeline, preuve, paiement, acteurs'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/admin/parcels/${parcel.id}/audit');
              },
            ),
            const Divider(),
            const Text(
              'Forcer le statut',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                    context, ref, parcel.id, 'cancelled', Colors.red),
                _buildStatusChip(
                    context, ref, parcel.id, 'returned', Colors.grey),
                _buildStatusChip(
                  context,
                  ref,
                  parcel.id,
                  'disputed',
                  Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    WidgetRef ref,
    String id,
    String status,
    Color color,
  ) {
    return ActionChip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      backgroundColor: color,
      onPressed: () => _showForceStatusDialog(context, ref, id, status),
    );
  }

  void _showForceStatusDialog(
    BuildContext context,
    WidgetRef ref,
    String id,
    String status,
  ) {
    final notesController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Forcer le statut ${status.toUpperCase()}'),
        content: TextField(
          controller: notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motif obligatoire',
            hintText: 'Explique la raison de cette intervention admin',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final notes = notesController.text.trim();
              if (notes.isEmpty) {
                return;
              }
              try {
                await ref
                    .read(apiClientProvider)
                    .forceParcelStatus(id, status, notes: notes);
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.pop(dialogContext);
                ref.invalidate(adminParcelsProvider);
                ref.invalidate(adminDashboardProvider);
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Statut $status force.')),
                );
              } catch (e) {
                if (!dialogContext.mounted) {
                  return;
                }
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Erreur: $e')),
                );
              }
            },
            child: const Text('Confirmer'),
          ),
        ],
      ),
    ).whenComplete(notesController.dispose);
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
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.parcels});

  final List<Parcel> parcels;

  @override
  Widget build(BuildContext context) {
    final active = parcels
        .where((parcel) => !const {
              'delivered',
              'cancelled',
              'returned',
            }.contains(parcel.status))
        .length;
    final blocked =
        parcels.where((parcel) => parcel.deliveryBlockedByPayment).length;
    final disputed =
        parcels.where((parcel) => parcel.status == 'disputed').length;
    final delivered =
        parcels.where((parcel) => parcel.status == 'delivered').length;

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Actifs',
            value: '$active',
            color: Colors.blue,
            icon: Icons.local_shipping_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Paiement',
            value: '$blocked',
            color: Colors.red,
            icon: Icons.lock_clock_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Litiges',
            value: '$disputed',
            color: Colors.orange,
            icon: Icons.report_problem_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Livres',
            value: '$delivered',
            color: Colors.green,
            icon: Icons.check_circle_outline,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ParcelCard extends StatelessWidget {
  const _ParcelCard({
    required this.parcel,
    required this.onOpenAudit,
    required this.onOpenActions,
  });

  final Parcel parcel;
  final VoidCallback onOpenAudit;
  final VoidCallback onOpenActions;

  @override
  Widget build(BuildContext context) {
    final paymentColor =
        parcel.deliveryBlockedByPayment ? Colors.red : Colors.blueGrey;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parcel.trackingCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _AdminParcelsScreenState._modeLabel(
                            parcel.deliveryMode),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                ParcelStatusBadge(status: parcel.status),
                IconButton(
                  onPressed: onOpenActions,
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.person_outline,
                  label: 'Expediteur: ${parcel.senderName ?? parcel.senderId}',
                ),
                _InfoPill(
                  icon: Icons.inbox_outlined,
                  label: 'Destinataire: ${parcel.recipientName ?? "-"}',
                ),
                if ((parcel.driverName ?? '').isNotEmpty)
                  _InfoPill(
                    icon: Icons.delivery_dining_outlined,
                    label: 'Livreur: ${parcel.driverName}',
                  ),
                if ((parcel.recipientPhone ?? '').isNotEmpty)
                  _InfoPill(
                    icon: Icons.phone_outlined,
                    label: parcel.recipientPhone!,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetaLine(
                    icon: Icons.schedule_outlined,
                    label: 'Cree le',
                    value: formatDate(parcel.createdAt),
                  ),
                ),
                Expanded(
                  child: _MetaLine(
                    icon: Icons.payments_outlined,
                    label: 'Montant',
                    value: parcel.totalPrice == null
                        ? '-'
                        : formatXof(parcel.totalPrice!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetaLine(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Paiement',
                    value: parcel.paymentStatus ?? 'non renseigne',
                    valueColor: paymentColor,
                  ),
                ),
                Expanded(
                  child: _MetaLine(
                    icon: Icons.swap_horiz_outlined,
                    label: 'Qui paie',
                    value: parcel.whoPays ?? '-',
                  ),
                ),
              ],
            ),
            if (parcel.deliveryBlockedByPayment) ...[
              const SizedBox(height: 12),
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
                  'Remise finale bloquee par le paiement.',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if ((parcel.destinationAddress ?? '').isNotEmpty)
                  Expanded(
                    child: Text(
                      parcel.destinationAddress!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                else
                  const Spacer(),
                TextButton.icon(
                  onPressed: onOpenAudit,
                  icon: const Icon(Icons.history_edu_outlined, size: 18),
                  label: const Text('Audit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

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
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
