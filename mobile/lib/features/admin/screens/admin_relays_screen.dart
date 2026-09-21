import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../providers/admin_provider.dart';
import 'admin_relay_detail_screen.dart';
import '../../../shared/utils/error_utils.dart';

class AdminRelaysScreen extends ConsumerStatefulWidget {
  const AdminRelaysScreen({super.key});

  @override
  ConsumerState<AdminRelaysScreen> createState() => _AdminRelaysScreenState();
}

class _AdminRelaysScreenState extends ConsumerState<AdminRelaysScreen> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all';
  GoogleMapController? _mapController;
  String? _lastMapSignature;
  int _page = 1;
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relaysAsync = ref.watch(adminRelaysPageProvider(
      AdminRelaysPageQuery(page: _page, search: _searchCtrl.text),
    ));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Points relais'),
        actions: [
          IconButton(
            tooltip: 'Géocoder les relais incomplets',
            icon: const Icon(Icons.location_searching),
            onPressed: () => _geocodeMissingRelays(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminRelaysPageProvider),
          ),
        ],
      ),
      body: relaysAsync.when(
        data: (pageResult) {
          final relays = pageResult.items;
          final filtered = relays.where(_matchesFilter).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) {
                    _searchTimer?.cancel();
                    _searchTimer = Timer(const Duration(milliseconds: 350), () {
                      if (mounted) setState(() => _page = 1);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Nom, ville, quartier ou téléphone',
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
                child: _RelaySummaryRow(relays: relays),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildRelayMap(context, filtered),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _filterChip('Tous', 'all'),
                    _filterChip('À vérifier', 'pending'),
                    _filterChip('Vérifiés', 'verified'),
                    _filterChip('Actifs', 'active'),
                    _filterChip('Satures', 'full'),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun relais ne correspond aux filtres en cours.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final relay = filtered[index];
                          return _RelayCard(
                            relay: relay,
                            onVerify: relay.isVerified
                                ? null
                                : () => _verifyRelay(context, ref, relay.id),
                          );
                        },
                      ),
              ),
              if (pageResult.total > 100)
                _RelayPagination(
                  page: _page,
                  total: pageResult.total,
                  onPrevious: _page > 1
                      ? () => setState(() => _page--)
                      : null,
                  onNext: _page * 100 < pageResult.total
                      ? () => setState(() => _page++)
                      : null,
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  Widget _buildRelayMap(BuildContext context, List<RelayPoint> relays) {
    final locatedRelays = relays
        .where((relay) => relay.lat != null && relay.lng != null)
        .toList();
    if (locatedRelays.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Aucun relais géolocalisé dans cette sélection.'),
      );
    }

    final signature = locatedRelays.map((relay) => relay.id).join('|');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || signature == _lastMapSignature) return;
      _lastMapSignature = signature;
      _fitRelayBounds(locatedRelays);
    });

    final first = locatedRelays.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 300,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(first.lat!, first.lng!),
            zoom: locatedRelays.length == 1 ? 14 : 10,
          ),
          markers: locatedRelays.map((relay) {
            return Marker(
              markerId: MarkerId(relay.id),
              position: LatLng(relay.lat!, relay.lng!),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                relay.isActive
                    ? BitmapDescriptor.hueOrange
                    : BitmapDescriptor.hueAzure,
              ),
              infoWindow: InfoWindow(
                title: relay.name,
                snippet: relay.addressLabel.isNotEmpty
                    ? relay.addressLabel
                    : relay.city,
                onTap: () => _openRelayDetails(context, relay),
              ),
              onTap: () => _openRelayDetails(context, relay),
            );
          }).toSet(),
          onMapCreated: (controller) {
            _mapController = controller;
            _fitRelayBounds(locatedRelays);
          },
          mapToolbarEnabled: true,
          zoomControlsEnabled: true,
          myLocationButtonEnabled: false,
          compassEnabled: true,
        ),
      ),
    );
  }

  Future<void> _fitRelayBounds(List<RelayPoint> relays) async {
    if (_mapController == null || relays.isEmpty) return;
    final points =
        relays.map((relay) => LatLng(relay.lat!, relay.lng!)).toList();
    final latitudes = points.map((point) => point.latitude);
    final longitudes = points.map((point) => point.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(latitudes.reduce((a, b) => a < b ? a : b),
          longitudes.reduce((a, b) => a < b ? a : b)),
      northeast: LatLng(latitudes.reduce((a, b) => a > b ? a : b),
          longitudes.reduce((a, b) => a > b ? a : b)),
    );
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 48),
      );
    } catch (_) {}
  }

  void _openRelayDetails(BuildContext context, RelayPoint relay) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(relay.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(relay.addressLabel.isEmpty
                  ? relay.city
                  : '${relay.addressLabel}, ${relay.city}'),
              if (relay.phone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(relay.phone),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  _StatusChip(
                    label: relay.isActive ? 'Actif' : 'Inactif',
                    color: relay.isActive ? Colors.green : Colors.grey,
                  ),
                  _StatusChip(
                    label: relay.isVerified ? 'Vérifié' : 'À vérifier',
                    color: relay.isVerified ? Colors.blue : Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminRelayDetailScreen(relayId: relay.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ouvrir la fiche du relais'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() {
          _filter = value;
          _page = 1;
        }),
      ),
    );
  }

  bool _matchesFilter(RelayPoint relay) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final matchesFilter = switch (_filter) {
      'all' => true,
      'pending' => !relay.isVerified,
      'verified' => relay.isVerified,
      'active' => relay.isActive,
      'full' => relay.isFull,
      _ => true,
    };

    if (!matchesFilter) {
      return false;
    }

    if (query.isEmpty) {
      return true;
    }

    return relay.name.toLowerCase().contains(query) ||
        relay.city.toLowerCase().contains(query) ||
        (relay.district ?? '').toLowerCase().contains(query) ||
        relay.phone.toLowerCase().contains(query);
  }

  Future<void> _verifyRelay(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.verifyRelay(id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relais vérifié avec succès.')),
      );
      ref.invalidate(adminRelaysPageProvider);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  Future<void> _geocodeMissingRelays(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(apiClientProvider).geocodeMissingAdminRelays();
      if (!context.mounted) return;
      ref.invalidate(adminRelaysPageProvider);
      final data = Map<String, dynamic>.from(result.data as Map? ?? const {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${data['geocoded'] ?? 0} relais géocodé(s), ${data['remaining'] ?? 0} restant(s).',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }
}

class _RelayPagination extends StatelessWidget {
  const _RelayPagination({
    required this.page,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final first = ((page - 1) * 100) + 1;
    final last = (page * 100).clamp(0, total);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$first–$last sur $total'),
            Row(
              children: [
                IconButton(
                  tooltip: 'Page précédente',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$page'),
                IconButton(
                  tooltip: 'Page suivante',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RelaySummaryRow extends StatelessWidget {
  const _RelaySummaryRow({required this.relays});

  final List<RelayPoint> relays;

  @override
  Widget build(BuildContext context) {
    final pending = relays.where((relay) => !relay.isVerified).length;
    final active = relays.where((relay) => relay.isActive).length;
    final full = relays.where((relay) => relay.isFull).length;
    final stock = relays.fold<int>(0, (sum, relay) => sum + relay.currentStock);

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'À vérifier',
            value: '$pending',
            color: Colors.orange,
            icon: Icons.fact_check_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Actifs',
            value: '$active',
            color: Colors.green,
            icon: Icons.storefront,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Satures',
            value: '$full',
            color: Colors.red,
            icon: Icons.warning_amber_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Charge',
            value: '$stock',
            color: Colors.blue,
            icon: Icons.inventory_2_outlined,
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

class _RelayCard extends StatelessWidget {
  const _RelayCard({required this.relay, required this.onVerify});

  final RelayPoint relay;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final loadRatio =
        relay.capacity == 0 ? 0.0 : relay.currentStock / relay.capacity;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminRelayDetailScreen(relayId: relay.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: relay.isVerified
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    child: Icon(
                      Icons.store,
                      color: relay.isVerified ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          relay.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          relay.district == null || relay.district!.isEmpty
                              ? relay.city
                              : '${relay.district}, ${relay.city}',
                        ),
                        Text(
                          relay.phone,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  if (onVerify != null)
                    ElevatedButton(
                      onPressed: onVerify,
                      child: const Text('Verifier'),
                    )
                  else
                    const Icon(Icons.verified, color: Colors.blue),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: relay.isVerified ? 'Vérifié' : 'En attente',
                    color: relay.isVerified ? Colors.green : Colors.orange,
                  ),
                  _StatusChip(
                    label: relay.isActive ? 'Actif' : 'Inactif',
                    color: relay.isActive ? Colors.green : Colors.grey,
                  ),
                  _StatusChip(
                    label: relay.isFull ? 'Saturé' : 'Capacité disponible',
                    color: relay.isFull ? Colors.red : Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Charge ${relay.currentStock}/${relay.capacity}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${(loadRatio * 100).round()}%',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: loadRatio.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    relay.isFull ? Colors.red : Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
