import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/phone_utils.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../core/models/delivery_mission.dart';

class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});

  @override
  ConsumerState<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<DriverHome> {
  double? _driverLat;
  double? _driverLng;
  bool    _gpsLoading = true;
  bool    _toggling   = false;

  @override
  void initState() {
    super.initState();
    _fetchDriverLocation();
  }

  /// Capture la position du livreur pour filtrer les missions par proximité.
  Future<void> _fetchDriverLocation() async {
    setState(() => _gpsLoading = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // GPS refusé → on affiche quand même toutes les missions (sans filtre)
        if (mounted) setState(() => _gpsLoading = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _driverLat = pos.latitude;
          _driverLng = pos.longitude;
          _gpsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _toggleAvailability() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.toggleAvailability();
      final newVal = res.data['is_available'] as bool? ?? false;
      ref.read(authProvider.notifier).updateUserAvailability(newVal);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  DriverLocation get _driverLoc => (lat: _driverLat, lng: _driverLng);

  @override
  Widget build(BuildContext context) {
    final isAvailable     = ref.watch(authProvider).value?.user?.isAvailable ?? false;
    final availableAsync  = ref.watch(availableMissionsProvider(_driverLoc));
    final myMissionsAsync = ref.watch(myMissionsProvider);
    final hasGps          = _driverLat != null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Espace Livreur'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Column(
              children: [
                // Barre GPS status
                if (!_gpsLoading)
                  Container(
                    color: hasGps ? Colors.green.shade700 : Colors.orange.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
                    width: double.infinity,
                    child: Row(children: [
                      Icon(
                        hasGps ? Icons.my_location : Icons.location_off,
                        size: 13, color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasGps
                            ? 'Missions dans un rayon de 5 km'
                            : 'GPS indisponible — toutes les missions affichées',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      if (hasGps) ...[
                        const Spacer(),
                        InkWell(
                          onTap: _fetchDriverLocation,
                          child: const Icon(Icons.refresh, size: 14, color: Colors.white70),
                        ),
                      ],
                    ]),
                  ),
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.inbox),          text: 'Disponibles'),
                    Tab(icon: Icon(Icons.local_shipping),  text: 'Mes missions'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            // Toggle disponibilité
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: isAvailable ? Colors.green : Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                _toggling
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Switch(
                        value: isAvailable,
                        onChanged: (_) => _toggleAvailability(),
                        activeColor: Colors.green,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
              ]),
            ),
            const AccountSwitcherButton(),
            // Badge Niveau (Phase 8)
            if (ref.watch(authProvider).value?.user != null)
              GestureDetector(
                onTap: () => context.push('/driver/performance'),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars, color: Colors.amber, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Lvl ${ref.watch(authProvider).value!.user!.level}',
                        style: const TextStyle(
                          color: Colors.amber, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 12
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        body: _gpsLoading
            ? const Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Localisation en cours…', style: TextStyle(color: Colors.grey)),
                ]),
              )
            : TabBarView(
                children: [
                  _MissionsList(
                    asyncValue:  availableAsync,
                    isAvailable: true,
                    driverLoc:   _driverLoc,
                  ),
                  _MissionsList(
                    asyncValue:  myMissionsAsync,
                    isAvailable: false,
                    driverLoc:   _driverLoc,
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Liste missions ────────────────────────────────────────────────────────────
class _MissionsList extends ConsumerWidget {
  const _MissionsList({
    required this.asyncValue,
    required this.isAvailable,
    required this.driverLoc,
  });
  final AsyncValue<List<DeliveryMission>> asyncValue;
  final bool isAvailable;
  final DriverLocation driverLoc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(availableMissionsProvider);
        ref.refresh(myMissionsProvider);
      },
      child: asyncValue.when(
        data: (missions) {
          // Pour "Mes missions" : séparer actives et terminées
          if (!isAvailable) {
            final active    = missions.where((m) => m.status == 'assigned' || m.status == 'in_progress').toList();
            final completed = missions.where((m) => m.status == 'completed' || m.status == 'failed').toList();

            if (active.isEmpty && completed.isEmpty) {
              return _buildEmpty('Vous n\'avez pas encore de mission');
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ── Missions actives ──────────────────────────────────
                if (active.isNotEmpty) ...[
                  ...active.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MissionCard(mission: m, isAvailable: false, driverLoc: driverLoc),
                  )),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.blue.shade50,
                    child: Row(children: [
                      Icon(Icons.check_circle, color: Colors.blue.shade300, size: 18),
                      const SizedBox(width: 10),
                      Text('Aucune mission en cours',
                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Historique gains ──────────────────────────────────
                if (completed.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.grey.shade100,
                    child: Row(children: [
                      Icon(Icons.history, color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 10),
                      Text('${completed.length} mission(s) terminée(s)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  ...completed.map((m) => _buildCompletedCard(context, m)),
                ],
                const SizedBox(height: 80),
              ],
            );
          }

          // Pour "Disponibles" : comportement inchangé
          if (missions.isEmpty) {
            return _buildEmpty(driverLoc.lat != null
                ? 'Aucune course dans votre rayon (5 km)'
                : 'Aucune course disponible pour le moment');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: missions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MissionCard(
              mission:     missions[i],
              isAvailable: true,
              driverLoc:   driverLoc,
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  Widget _buildEmpty(String msg) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text(msg, style: const TextStyle(fontSize: 15, color: Colors.grey), textAlign: TextAlign.center),
    ]),
  );

  Widget _buildCompletedCard(BuildContext context, DeliveryMission m) {
    final isFailed  = m.status == 'failed';
    final color     = isFailed ? Colors.red : Colors.green;
    final icon      = isFailed ? Icons.cancel_outlined : Icons.check_circle_outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          m.trackingCode ?? m.id.substring(0, 10),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'monospace'),
        ),
        subtitle: Text(
          '${m.pickupLabel} → ${m.deliveryLabel}',
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatXof(m.earnAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isFailed ? Colors.grey : Colors.green.shade700,
                fontSize: 14,
              ),
            ),
            Text(
              isFailed ? 'Échouée' : 'Encaissé',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Carte mission ─────────────────────────────────────────────────────────────
class _MissionCard extends ConsumerWidget {
  const _MissionCard({
    required this.mission,
    required this.isAvailable,
    required this.driverLoc,
  });
  final DeliveryMission mission;
  final bool isAvailable;
  final DriverLocation driverLoc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // En-tête : tracking code + distance + gain
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                mission.trackingCode ?? mission.id.substring(0, 10),
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                    fontSize: 12),
              ),
            ),
            // Badge distance
            if (mission.distanceKm != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _distanceColor(mission.distanceKm!).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.near_me, size: 11, color: _distanceColor(mission.distanceKm!)),
                  const SizedBox(width: 3),
                  Text(
                    '${mission.distanceKm!.toStringAsFixed(1)} km',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _distanceColor(mission.distanceKm!)),
                  ),
                ]),
              ),
            ],
            const Spacer(),
            Text(
              formatXof(mission.earnAmount),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
            ),
          ]),
          const SizedBox(height: 14),
          // Pickup
          _locationRow(
            icon: mission.pickupIsRelay ? Icons.store : Icons.radio_button_checked,
            color: mission.pickupIsRelay ? Colors.orange : Colors.blue,
            label: mission.pickupIsRelay
                ? 'Récupérer au relais'
                : 'Récupérer chez l\'expéditeur',
            address: mission.pickupLabel,
            city: mission.pickupCity,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Icon(Icons.arrow_downward, size: 18, color: Colors.grey.shade400),
          ),
          // Livraison
          _locationRow(
            icon: Icons.location_on,
            color: Colors.red,
            label: 'Livrer à',
            address: mission.deliveryLabel,
            city: mission.deliveryCity,
          ),
          // Destinataire
          if (mission.recipientName != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.person_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(mission.recipientName!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (mission.recipientPhone != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.phone, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(maskPhone(mission.recipientPhone!),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ]),
          ],
          const SizedBox(height: 12),
          // Bouton
          SizedBox(
            width: double.infinity,
            child: isAvailable
                ? ElevatedButton.icon(
                    onPressed: () => _accept(context, ref),
                    icon: const Icon(Icons.check),
                    label: const Text('Accepter la course'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  )
                : OutlinedButton.icon(
                    onPressed: () => context.push('/driver/mission/${mission.id}'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Voir les détails'),
                  ),
          ),
        ]),
      ),
    );
  }

  Color _distanceColor(double km) {
    if (km <= 2) return Colors.green.shade700;
    if (km <= 4) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Widget _locationRow({
    required IconData icon,
    required Color color,
    required String label,
    required String address,
    required String city,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text(address, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Text(city, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    ]);
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.acceptMission(mission.id);
      ref.invalidate(availableMissionsProvider);
      ref.refresh(myMissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Course acceptée ! Bonne livraison 🛵'),
          backgroundColor: Colors.green,
        ));
        context.push('/driver/mission/${mission.id}');
      }
    } catch (e) {
      if (context.mounted) {
        String msg = 'Erreur lors de l\'acceptation';
        if (e is DioException) {
          final data = e.response?.data;
          if (data is Map) msg = data['detail']?.toString() ?? msg;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }
}
