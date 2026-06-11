import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/notifications/notifications_bell_button.dart';
import '../../../shared/promotions/campaign_banner.dart';
import '../providers/relay_provider.dart';
import '../../../shared/utils/error_utils.dart';

class RelayHome extends ConsumerStatefulWidget {
  const RelayHome({super.key});

  @override
  ConsumerState<RelayHome> createState() => _RelayHomeState();
}

class _RelayHomeState extends ConsumerState<RelayHome> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    final stockAsync = ref.watch(relayStockProvider);
    final historyAsync = ref.watch(relayHistoryProvider);
    final relayAsync = ref.watch(relayPointProfileProvider);
    final performanceAsync = ref.watch(relayPerformanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.name ?? 'Mon relais'),
        actions: [
          const AccountSwitcherButton(),
          const NotificationsBellButton(route: '/relay/notifications'),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/relay/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(relayStockProvider);
          ref.invalidate(relayHistoryProvider);
          ref.invalidate(relayPointProfileProvider);
          ref.invalidate(relayPerformanceProvider);
        },
        child: stockAsync.when(
          data: (parcels) {
            final history = historyAsync.valueOrNull ?? [];
            final incoming = parcels
                .where((parcel) => parcel.status == 'in_transit')
                .toList();
            final pending = parcels
                .where((parcel) => parcel.status == 'redirected_to_relay')
                .toList();
            final inStock = parcels
                .where(
                  (parcel) =>
                      parcel.status != 'redirected_to_relay' &&
                      parcel.status != 'in_transit',
                )
                .toList();

            final filteredIncoming =
                incoming.where((parcel) => _matchesParcel(parcel)).toList();
            final filteredPending =
                pending.where((parcel) => _matchesParcel(parcel)).toList();
            final filteredInStock =
                inStock.where((parcel) => _matchesParcel(parcel)).toList();
            final filteredHistory =
                history.where((parcel) => _matchesParcel(parcel)).toList();

            if (parcels.isEmpty && history.isEmpty) {
              return const _EmptyState();
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                const CampaignBanner(role: 'relay_agent'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _OverviewCard(
                    relayAsync: relayAsync,
                    performanceAsync: performanceAsync,
                    incoming: incoming.length,
                    pending: pending.length,
                    inStock: inStock.length,
                    history: history.length,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Code, destinataire ou telephone',
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildFilterChip('Tous', 'all'),
                      _buildFilterChip('En route', 'incoming'),
                      _buildFilterChip('À réceptionner', 'pending'),
                      _buildFilterChip('En stock', 'stock'),
                      _buildFilterChip('Historique', 'history'),
                    ],
                  ),
                ),
                if (_showSection('incoming') &&
                    filteredIncoming.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.local_shipping,
                    label: '${filteredIncoming.length} colis en route',
                    color: Colors.indigo,
                    background: Colors.indigo.shade50,
                  ),
                  ...filteredIncoming
                      .map((parcel) => _IncomingCard(parcel: parcel)),
                  const SizedBox(height: 8),
                ],
                if (_showSection('pending') && filteredPending.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.reply,
                    label: '${filteredPending.length} colis à réceptionner',
                    color: Colors.orange,
                    background: Colors.orange.shade50,
                  ),
                  ...filteredPending
                      .map((parcel) => _PendingCard(parcel: parcel)),
                  const SizedBox(height: 8),
                ],
                if (_showSection('stock')) ...[
                  _SectionHeader(
                    icon: Icons.inventory,
                    label: '${filteredInStock.length} colis en stock',
                    color: Colors.blue,
                    background: Colors.blue.shade50,
                  ),
                  if (filteredInStock.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Aucun colis ne correspond a la recherche dans le stock.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...filteredInStock.map(
                      (parcel) => _StockCard(
                        parcel: parcel,
                        onTap: () => _showParcelDetail(context, parcel),
                      ),
                    ),
                ],
                if (_showSection('history') && filteredHistory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionHeader(
                    icon: Icons.history,
                    label: '${filteredHistory.length} colis remis',
                    color: Colors.grey.shade700,
                    background: Colors.grey.shade100,
                  ),
                  ...filteredHistory
                      .map((parcel) => _HistoryCard(parcel: parcel)),
                ],
                if (filteredIncoming.isEmpty &&
                    filteredPending.isEmpty &&
                    filteredInStock.isEmpty &&
                    filteredHistory.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Aucun colis ne correspond a la recherche en cours.',
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => Center(child: Text(friendlyError(e))),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scanIn',
            onPressed: () => context.push('/relay/scan-in'),
            label: const Text('Receptionner'),
            icon: const Icon(Icons.download),
            backgroundColor: Colors.green,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scanOut',
            onPressed: () => context.push('/relay/scan-out'),
            label: const Text('Remettre client'),
            icon: const Icon(Icons.upload),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  bool _showSection(String section) => _filter == 'all' || _filter == section;

  bool _matchesParcel(Parcel parcel) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return parcel.trackingCode.toLowerCase().contains(query) ||
        (parcel.recipientName ?? '').toLowerCase().contains(query) ||
        (parcel.recipientPhone ?? '').toLowerCase().contains(query);
  }

  void _showParcelDetail(BuildContext context, Parcel parcel) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RelayParcelDetailSheet(parcel: parcel),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.relayAsync,
    required this.performanceAsync,
    required this.incoming,
    required this.pending,
    required this.inStock,
    required this.history,
  });

  final AsyncValue<dynamic> relayAsync;
  final AsyncValue<Map<String, dynamic>> performanceAsync;
  final int incoming;
  final int pending;
  final int inStock;
  final int history;

  @override
  Widget build(BuildContext context) {
    return relayAsync.when(
      data: (relay) {
        final capacityText = relay == null
            ? '$inStock en stock'
            : '${relay.currentStock}/${relay.capacity} places utilisees';
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade800, Colors.orange.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                relay?.name ?? 'Point relais',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                capacityText,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OverviewChip(
                    label: '$incoming en route',
                    icon: Icons.local_shipping_outlined,
                    explanation:
                        'Colis déjà pris en charge et actuellement en route vers votre relais.',
                  ),
                  _OverviewChip(
                    label: '$pending à réceptionner',
                    icon: Icons.reply_outlined,
                    explanation:
                        'Colis redirigés vers votre relais après une tentative de livraison ou un changement de parcours.',
                  ),
                  _OverviewChip(
                    label: '$inStock en stock',
                    icon: Icons.inventory_2_outlined,
                    explanation:
                        'Colis physiquement disponibles dans votre relais et en attente de retrait ou de passage livreur.',
                  ),
                  _OverviewChip(
                    label: '$history remis',
                    icon: Icons.history,
                    explanation:
                        'Nombre de colis déjà remis au destinataire dans votre historique récent.',
                  ),
                ],
              ),
              performanceAsync.maybeWhen(
                data: (stats) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _OverviewChip(
                        label: '${stats['parcels_processed'] ?? 0} traités',
                        icon: Icons.task_alt_outlined,
                        explanation:
                            'Total des colis passés par votre relais pendant le mois en cours. Ce volume sert au suivi de performance.',
                      ),
                      _OverviewChip(
                        label: '${stats['parcels_delivered'] ?? 0} livrés',
                        icon: Icons.check_circle_outline,
                        explanation:
                            'Colis du mois qui ont été remis ou finalisés depuis votre relais.',
                      ),
                      _OverviewChip(
                        label:
                            '${NumberFormat.decimalPattern('fr_FR').format(stats['projected_bonus_xof'] ?? 0)} XOF bonus',
                        icon: Icons.emoji_events_outlined,
                        explanation:
                            'Bonus estimé selon les paliers configurés par Denkma. Il peut changer si le volume du mois évolue.',
                      ),
                      _OverviewChip(
                        label: stats['next_bonus_threshold'] == null
                            ? 'Palier max'
                            : 'Palier ${stats['next_bonus_threshold']}',
                        icon: Icons.flag_outlined,
                        explanation:
                            'Prochain volume de colis à atteindre pour débloquer ou augmenter le bonus mensuel.',
                      ),
                    ],
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          '$incoming en route, $pending à réceptionner, $inStock en stock.',
        ),
      ),
    );
  }
}

class _OverviewChip extends StatelessWidget {
  const _OverviewChip({
    required this.label,
    required this.icon,
    required this.explanation,
  });

  final String label;
  final IconData icon;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showRelayKpiInfo(context, label, explanation),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52, minWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.info_outline, size: 13, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

void _showRelayKpiInfo(BuildContext context, String title, String message) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 14, height: 1.35)),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: background,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.parcel});

  final Parcel parcel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.reply, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Colis redirigé après échec de livraison',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ParcelStatusBadge(status: parcel.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Code: ${parcel.trackingCode}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              'Destinataire: ${parcel.recipientName ?? "-"}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/relay/scan-in'),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Scanner pour confirmer la reception'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({required this.parcel});

  final Parcel parcel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_shipping,
                  color: Colors.indigo.shade400,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'En route vers votre relais',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.indigo.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ParcelStatusBadge(status: parcel.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Code: ${parcel.trackingCode}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              'Destinataire: ${parcel.recipientName ?? "-"}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.parcel, required this.onTap});

  final Parcel parcel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined, color: Colors.blueGrey),
        title: Text(
          parcel.trackingCode,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(parcel.recipientName ?? '-'),
        trailing: ParcelStatusBadge(status: parcel.status),
        onTap: onTap,
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.parcel});

  final Parcel parcel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: Icon(
            Icons.check_circle_outline,
            color: Colors.green.shade600,
            size: 20,
          ),
        ),
        title: Text(
          parcel.trackingCode,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          parcel.recipientName ?? '-',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          formatDate(parcel.createdAt),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Aucun colis en stock',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text('Utilisez le bouton "Receptionner" pour scanner un colis.'),
        ],
      ),
    );
  }
}

class _RelayParcelDetailSheet extends ConsumerStatefulWidget {
  const _RelayParcelDetailSheet({required this.parcel});

  final Parcel parcel;

  @override
  ConsumerState<_RelayParcelDetailSheet> createState() =>
      _RelayParcelDetailSheetState();
}

class _RelayParcelDetailSheetState
    extends ConsumerState<_RelayParcelDetailSheet> {
  bool _loadingCode = false;
  String? _pickupCode;

  String _modeLabel(String mode) => switch (mode) {
        'relay_to_relay' => 'Relais -> Relais',
        'relay_to_home' => 'Relais -> Domicile',
        'home_to_relay' => 'Domicile -> Relais',
        'home_to_home' => 'Domicile -> Domicile',
        _ => mode,
      };

  @override
  Widget build(BuildContext context) {
    final parcel = widget.parcel;
    final formatter = DateFormat('d MMM yyyy a HH:mm', 'fr_FR');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  parcel.trackingCode,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ParcelStatusBadge(status: parcel.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cree le ${formatter.format(parcel.createdAt.toLocal())}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const Divider(height: 28),
          _sectionTitle('Colis'),
          _infoRow(Icons.local_shipping_outlined, 'Mode',
              _modeLabel(parcel.deliveryMode)),
          if (parcel.weightKg != null)
            _infoRow(Icons.scale_outlined, 'Poids', '${parcel.weightKg} kg'),
          if (parcel.declaredValue != null)
            _infoRow(
              Icons.attach_money,
              'Valeur declaree',
              '${parcel.declaredValue!.toStringAsFixed(0)} XOF',
            ),
          if (parcel.totalPrice != null)
            _infoRow(
              Icons.receipt_outlined,
              'Frais de port',
              '${parcel.totalPrice!.toStringAsFixed(0)} XOF',
            ),
          const Divider(height: 28),
          _sectionTitle('Destinataire'),
          _infoRow(Icons.person_outline, 'Nom', parcel.recipientName ?? '-'),
          _infoRow(
              Icons.phone_outlined, 'Téléphone', parcel.recipientPhone ?? '-'),
          if (parcel.destinationAddress != null)
            _infoRow(
              Icons.location_on_outlined,
              'Adresse',
              parcel.destinationAddress!,
            ),
          const Divider(height: 28),
          if (parcel.status == 'dropped_at_origin_relay') ...[
            _sectionTitle('Code de collecte livreur'),
            const Text(
              'Le livreur vient recuperer ce colis. Donnez lui ce code ou montrez lui le QR.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_pickupCode == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingCode ? null : _fetchPickupCode,
                  icon: _loadingCode
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_open_outlined),
                  label: Text(
                    _loadingCode ? 'Chargement...' : 'Afficher le code livreur',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Le livreur scanne le QR ou saisit le code.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.white,
                      child: QrImageView(
                        data: _pickupCode!,
                        version: QrVersions.auto,
                        size: 160,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.indigo,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _pickupCode!,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _pickupCode!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copie.')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copier le code'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (parcel.status == 'available_at_relay') ...[
            const Divider(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(
                    '/relay/scan-out',
                    extra: {
                      'parcelId': parcel.id,
                      'trackingCode': parcel.trackingCode,
                      'recipientName': parcel.recipientName ?? '-',
                      'recipientPhone': parcel.recipientPhone ?? '-',
                    },
                  );
                },
                icon: const Icon(Icons.upload),
                label: const Text('Remettre au destinataire'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _fetchPickupCode() async {
    setState(() => _loadingCode = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getParcelCodes(widget.parcel.id);
      final data = res.data as Map<String, dynamic>;
      final code = data['pickup_code'] as String?;
      if (!mounted) {
        return;
      }
      if (code == null || code.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Code introuvable. Vérifiez que le colis est bien déposé au relais.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        setState(() => _pickupCode = code);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingCode = false);
      }
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
}
