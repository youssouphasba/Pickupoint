import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/phone_utils.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../core/models/delivery_mission.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/notifications/notifications_bell_button.dart';
import '../../../shared/notifications/notification_permission_banner.dart';
import '../../../shared/promotions/campaign_banner.dart';
import '../../../core/location/fresh_position_helper.dart';
import '../../../core/location/location_tracking_service.dart';

class _MissionPreview {
  const _MissionPreview({
    this.pickupDistanceText,
    this.pickupEtaText,
    this.deliveryDistanceText,
    this.deliveryEtaText,
    this.totalDistanceText,
    this.totalEtaText,
  });

  final String? pickupDistanceText;
  final String? pickupEtaText;
  final String? deliveryDistanceText;
  final String? deliveryEtaText;
  final String? totalDistanceText;
  final String? totalEtaText;

  factory _MissionPreview.fromJson(Map<String, dynamic> json) {
    return _MissionPreview(
      pickupDistanceText: json['pickup_distance_text']?.toString(),
      pickupEtaText: json['pickup_eta_text']?.toString(),
      deliveryDistanceText: json['delivery_distance_text']?.toString(),
      deliveryEtaText: json['delivery_eta_text']?.toString(),
      totalDistanceText: json['total_distance_text']?.toString(),
      totalEtaText: json['total_eta_text']?.toString(),
    );
  }
}

class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});

  @override
  ConsumerState<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<DriverHome> with WidgetsBindingObserver {
  double? _driverLat;
  double? _driverLng;
  bool _gpsLoading = true;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchDriverLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationTrackingServiceProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchDriverLocation();
    }
  }

  Future<void> _syncDriverPresenceLocation(Position pos) async {
    try {
      await ref.read(apiClientProvider).updateMyDriverLocation({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
      });
    } catch (_) {}
  }

  /// Capture la position du livreur pour filtrer les missions par proximité.
  Future<void> _fetchDriverLocation() async {
    setState(() => _gpsLoading = true);
    try {
      final pos = await FreshPositionHelper.getDriverSearchPosition();
      await _syncDriverPresenceLocation(pos);
      if (mounted) {
        setState(() {
          _driverLat = pos.latitude;
          _driverLng = pos.longitude;
          _gpsLoading = false;
        });
      }
    } catch (_) {
      try {
        final pos = await FreshPositionHelper.getDriverPresencePosition();
        await _syncDriverPresenceLocation(pos);
        if (mounted) {
          setState(() {
            _driverLat = pos.latitude;
            _driverLng = pos.longitude;
            _gpsLoading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _driverLat = null;
            _driverLng = null;
            _gpsLoading = false;
          });
        }
      }
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
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<bool> _ensureGpsReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Activez le GPS pour accepter une course et rester traçable.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await Geolocator.openLocationSettings();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Autorisez la localisation pour accepter une course.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
    return true;
  }

  DriverLocation get _driverLoc => (lat: _driverLat, lng: _driverLng);

  @override
  Widget build(BuildContext context) {
    final isAvailable =
        ref.watch(authProvider).value?.user?.isAvailable ?? false;
    final availableAsync = ref.watch(availableMissionsProvider(_driverLoc));
    final myMissionsAsync = ref.watch(myMissionsProvider);
    final myMissions = myMissionsAsync.valueOrNull ?? const <DeliveryMission>[];
    final hasLockedMission = hasActiveDriverMission(myMissions);
    final hasGps = _driverLat != null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const SizedBox.shrink(),
          titleSpacing: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(68),
            child: Column(
              children: [
                if (!_gpsLoading)
                  Container(
                    color:
                        hasGps ? Colors.green.shade700 : Colors.orange.shade700,
                    padding:
                        const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
                    width: double.infinity,
                    child: Row(children: [
                      Icon(
                        hasGps ? Icons.my_location : Icons.location_off,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hasGps
                              ? 'Missions à 5 km'
                              : 'GPS requis pour voir les missions',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _fetchDriverLocation,
                        child: const Icon(Icons.refresh,
                            size: 18, color: Colors.white70),
                      ),
                    ]),
                  ),
                const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelPadding: EdgeInsets.symmetric(horizontal: 4),
                  labelStyle:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(
                      height: 46,
                      child: _CompactTab(
                        icon: Icons.inbox,
                        label: 'Disponibles',
                      ),
                    ),
                    Tab(
                      height: 46,
                      child: _CompactTab(
                        icon: Icons.local_shipping,
                        label: 'Mes missions',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            // Toggle disponibilité
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Tooltip(
                message: hasLockedMission
                    ? "Disponibilité verrouillée pendant une course active ou un retour expéditeur."
                    : 'Activer ou désactiver les nouvelles missions',
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: isAvailable ? Colors.green : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 4),
                  _toggling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Transform.scale(
                          scale: 0.78,
                          child: Switch(
                            value: isAvailable,
                            onChanged: hasLockedMission
                                ? null
                                : (_) => _toggleAvailability(),
                            activeThumbColor: Colors.green,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                ]),
              ),
            ),
            if (!hasLockedMission) const AccountSwitcherButton(),
            const NotificationsBellButton(route: '/driver/notifications'),
            // Badge Niveau (Phase 8)
            if (ref.watch(authProvider).value?.user != null)
              GestureDetector(
                onTap: () => context.push('/driver/performance'),
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
                        '${ref.watch(authProvider).value!.user!.level}',
                        style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                hasLockedMission ? Icons.lock_outline : Icons.logout,
              ),
              tooltip: hasLockedMission
                  ? 'Déconnexion bloquée pendant une course active'
                  : 'Se déconnecter',
              onPressed: hasLockedMission
                  ? null
                  : () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        body: Column(
          children: [
            const NotificationPermissionBanner(),
            const CampaignBanner(role: 'driver'),
            Expanded(
              child: _gpsLoading
                  ? const Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Localisation en cours…',
                                style: TextStyle(color: Colors.grey)),
                          ]),
                    )
                  : TabBarView(
                      children: [
                        _MissionsList(
                          asyncValue: availableAsync,
                          isAvailable: true,
                          driverLoc: _driverLoc,
                          ensureGpsReady: _ensureGpsReady,
                        ),
                        _MissionsList(
                          asyncValue: myMissionsAsync,
                          isAvailable: false,
                          driverLoc: _driverLoc,
                          ensureGpsReady: _ensureGpsReady,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionsList extends ConsumerWidget {
  const _MissionsList({
    required this.asyncValue,
    required this.isAvailable,
    required this.driverLoc,
    required this.ensureGpsReady,
  });
  final AsyncValue<List<DeliveryMission>> asyncValue;
  final bool isAvailable;
  final DriverLocation driverLoc;
  final Future<bool> Function() ensureGpsReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => Future.wait([
        ref.refresh(availableMissionsProvider(driverLoc).future),
        ref.refresh(myMissionsProvider.future),
      ]),
      child: asyncValue.when(
        data: (missions) {
          // Pour "Mes missions" : séparer actives et terminées
          if (!isAvailable) {
            final active = missions
                .where((m) =>
                    m.status == 'assigned' ||
                    m.status == 'in_progress' ||
                    m.status == 'incident_reported')
                .toList();
            final completed = missions
                .where((m) => m.status == 'completed' || m.status == 'failed')
                .toList();

            if (active.isEmpty && completed.isEmpty) {
              return _buildEmpty('Vous n\'avez pas encore de mission');
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (active.isNotEmpty) ...[
                  ...active.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MissionCard(
                            mission: m,
                            isAvailable: false,
                            driverLoc: driverLoc,
                            ensureGpsReady: ensureGpsReady),
                      )),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: Colors.blue.shade50,
                    child: Row(children: [
                      Icon(Icons.check_circle,
                          color: Colors.blue.shade300, size: 18),
                      const SizedBox(width: 10),
                      Text('Aucune mission en cours',
                          style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],

                if (completed.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    color: Colors.grey.shade100,
                    child: Row(children: [
                      Icon(Icons.history,
                          color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 10),
                      Text('${completed.length} mission(s) terminée(s)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700)),
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
              mission: missions[i],
              isAvailable: true,
              driverLoc: driverLoc,
              ensureGpsReady: ensureGpsReady,
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  Widget _buildEmpty(String msg) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.local_shipping_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(msg,
              style: const TextStyle(fontSize: 15, color: Colors.grey),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _buildCompletedCard(BuildContext context, DeliveryMission m) {
    final isFailed = m.status == 'failed';
    final color = isFailed ? Colors.red : Colors.green;
    final icon = isFailed ? Icons.cancel_outlined : Icons.check_circle_outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          m.trackingCode ?? m.id.substring(0, 10),
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              fontFamily: 'monospace'),
        ),
        subtitle: Text(
          '${m.pickupLabel} -> ${m.deliveryLabel}',
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

class _CompactTab extends StatelessWidget {
  const _CompactTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MissionCard extends ConsumerWidget {
  const _MissionCard({
    required this.mission,
    required this.isAvailable,
    required this.driverLoc,
    required this.ensureGpsReady,
  });
  final DeliveryMission mission;
  final bool isAvailable;
  final DriverLocation driverLoc;
  final Future<bool> Function() ensureGpsReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // En-tête : tracking code + distance + gain
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 170),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mission.trackingCode ?? mission.id.substring(0, 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                          fontSize: 12),
                    ),
                  ),
                  if (mission.distanceKm != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _distanceColor(mission.distanceKm!)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.near_me,
                            size: 11,
                            color: _distanceColor(mission.distanceKm!)),
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
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatXof(mission.earnAmount),
                  maxLines: 1,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          // Pickup
          _locationRow(
            icon: mission.pickupIsRelay
                ? Icons.store
                : Icons.radio_button_checked,
            color: mission.pickupIsRelay ? Colors.orange : Colors.blue,
            label: mission.pickupIsRelay
                ? 'Récupérer au relais'
                : 'Récupérer chez l\'expéditeur',
            address: mission.pickupLabel,
            city: mission.pickupCity,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Icon(Icons.arrow_downward,
                size: 18, color: Colors.grey.shade400),
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
              Expanded(
                child: Text(
                  mission.recipientName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (mission.recipientPhone != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.phone, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    maskPhone(mission.recipientPhone!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ]),
          ],
          const SizedBox(height: 12),
          // Bouton
          SizedBox(
            width: double.infinity,
            child: isAvailable
                ? ElevatedButton.icon(
                    onPressed: () => _showPreviewSheet(context, ref),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Voir course'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  )
                : OutlinedButton.icon(
                    onPressed: () =>
                        context.push('/driver/mission/${mission.id}'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Voir les détails'),
                  ),
          ),
        ]),
      ),
    );
  }

  Future<_MissionPreview> _loadPreview(WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    final response = await api.getMissionPreview(
      mission.id,
      lat: driverLoc.lat,
      lng: driverLoc.lng,
    );
    final data = response.data as Map<String, dynamic>;
    final previewJson = data['preview'] as Map<String, dynamic>? ?? const {};
    return _MissionPreview.fromJson(previewJson);
  }
  Future<void> _showPreviewSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: FutureBuilder<_MissionPreview>(
                future: _loadPreview(ref),
                builder: (context, snapshot) {
                  final preview = snapshot.data;
                  final isLoading = snapshot.connectionState == ConnectionState.waiting;
                  final loadError = snapshot.hasError;
                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Apercu de la course',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              formatXof(mission.earnAmount),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPreviewMap(),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  const _MapLegendChip(
                                    color: Colors.blue,
                                    icon: Icons.navigation_outlined,
                                    label: 'Vous',
                                  ),
                                  _MapLegendChip(
                                    color: Colors.green,
                                    icon: mission.pickupIsRelay
                                        ? Icons.storefront_outlined
                                        : Icons.my_location_outlined,
                                    label: mission.pickupIsRelay
                                        ? 'Relais de depart'
                                        : 'Collecte',
                                  ),
                                  _MapLegendChip(
                                    color: Colors.red,
                                    icon: mission.deliveryIsRelay
                                        ? Icons.inventory_2_outlined
                                        : Icons.flag_outlined,
                                    label: mission.deliveryIsRelay
                                        ? "Relais d'arrivee"
                                        : 'Livraison',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _PreviewMetricCard(
                                      label: 'Gain estime',
                                      value: formatXof(mission.earnAmount),
                                      icon: Icons.payments_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _PreviewMetricCard(
                                      label: 'Solde requis',
                                      value: formatXof(_requiredBalance()),
                                      icon: Icons.account_balance_wallet_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        Navigator.of(sheetContext).pop();
                                        await _decline(context, ref);
                                      },
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(52),
                                        side: BorderSide(color: Colors.grey.shade900),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                      ),
                                      child: const Text(
                                        'Refuser',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () async {
                                        Navigator.of(sheetContext).pop();
                                        await _accept(context, ref);
                                      },
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(52),
                                        backgroundColor: const Color(0xFFF4FF5A),
                                        foregroundColor: Colors.black87,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(18),
                                        ),
                                      ),
                                      child: const Text(
                                        'Accepter',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _PreviewSection(
                                title: 'Resume',
                                children: [
                                  _PreviewLine(
                                    icon: Icons.near_me_outlined,
                                    label: "Vers l'expediteur",
                                    value: preview?.pickupDistanceText ?? _fallbackPickupDistance(),
                                    trailing: preview?.pickupEtaText,
                                    loading: isLoading,
                                  ),
                                  _PreviewLine(
                                    icon: Icons.route_outlined,
                                    label: 'Course',
                                    value: preview?.deliveryDistanceText ?? 'Non disponible',
                                    trailing: preview?.deliveryEtaText,
                                    loading: isLoading,
                                  ),
                                  _PreviewLine(
                                    icon: Icons.alt_route_outlined,
                                    label: 'Total pour vous',
                                    value: preview?.totalDistanceText ?? _fallbackTotalDistance(preview),
                                    trailing: preview?.totalEtaText,
                                    loading: isLoading,
                                  ),
                                  _PreviewLine(
                                    icon: Icons.local_shipping_outlined,
                                    label: 'Type de course',
                                    value: _deliveryModeLabel(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _PreviewSection(
                                title: 'Details',
                                children: [
                                  _PreviewLine(
                                    icon: mission.pickupIsRelay
                                        ? Icons.storefront_outlined
                                        : Icons.my_location_outlined,
                                    label: 'Zone de collecte',
                                    value: _pickupZoneLabel(),
                                  ),
                                  if ((mission.senderName ?? '').trim().isNotEmpty)
                                    _PreviewLine(
                                      icon: Icons.person_outline,
                                      label: 'Nom expediteur',
                                      value: mission.senderName!.trim(),
                                    ),
                                  _PreviewLine(
                                    icon: mission.deliveryIsRelay
                                        ? Icons.inventory_2_outlined
                                        : Icons.flag_outlined,
                                    label: 'Zone de livraison',
                                    value: _deliveryZoneLabel(),
                                  ),
                                  if ((mission.recipientName ?? '').trim().isNotEmpty)
                                    _PreviewLine(
                                      icon: Icons.person_outline,
                                      label: 'Nom destinataire',
                                      value: mission.recipientName!.trim(),
                                    ),
                                  _PreviewLine(
                                    icon: Icons.wallet_outlined,
                                    label: 'Paiement',
                                    value: _payerLabel(),
                                  ),
                                ],
                              ),
                              if (loadError) ...[
                                const SizedBox(height: 14),
                                Text(
                                  friendlyError(snapshot.error ?? Exception('Erreur')),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewMap() {
    final driverPoint = _driverPoint();
    final pickupPoint = _pickupPoint();
    final deliveryPoint = _deliveryPoint();
    final points = [
      if (driverPoint != null) driverPoint,
      if (pickupPoint != null) pickupPoint,
      if (deliveryPoint != null) deliveryPoint,
    ];

    if (points.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: const Text('Carte indisponible'),
      );
    }

    final markers = <Marker>{
      if (driverPoint != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driverPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Vous'),
        ),
      if (pickupPoint != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickupPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Expediteur', snippet: _pickupZoneLabel()),
        ),
      if (deliveryPoint != null)
        Marker(
          markerId: const MarkerId('delivery'),
          position: deliveryPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: 'Destinataire', snippet: _deliveryZoneLabel()),
        ),
    };

    final polylines = <Polyline>{
      if (driverPoint != null && pickupPoint != null)
        Polyline(
          polylineId: const PolylineId('driver_to_pickup'),
          points: [driverPoint, pickupPoint],
          color: Colors.blue.shade600,
          width: 5,
        ),
      if (pickupPoint != null && deliveryPoint != null)
        Polyline(
          polylineId: const PolylineId('pickup_to_delivery'),
          points: [pickupPoint, deliveryPoint],
          color: Colors.green.shade600,
          width: 5,
        ),
    };

    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            GoogleMap(
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              initialCameraPosition: CameraPosition(
                target: points.first,
                zoom: points.length == 1 ? 14 : 11,
              ),
              rotateGesturesEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: markers,
              polylines: polylines,
              onMapCreated: (controller) {
                final bounds = _boundsFromPoints(points);
                if (bounds != null) {
                  Future.delayed(const Duration(milliseconds: 120), () {
                    controller.animateCamera(
                      CameraUpdate.newLatLngBounds(bounds, 64),
                    );
                  });
                }
              },
            ),
            if (driverPoint != null)
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.navigation_outlined, size: 14, color: Colors.blue),
                      SizedBox(width: 5),
                      Text(
                        'Vous',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LatLng? _driverPoint() {
    final lat = driverLoc.lat;
    final lng = driverLoc.lng;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _pickupPoint() {
    if (mission.pickupLat == null || mission.pickupLng == null) return null;
    return LatLng(mission.pickupLat!, mission.pickupLng!);
  }

  LatLng? _deliveryPoint() {
    if (mission.deliveryLat == null || mission.deliveryLng == null) return null;
    return LatLng(mission.deliveryLat!, mission.deliveryLng!);
  }

  LatLngBounds? _boundsFromPoints(List<LatLng> points) {
    if (points.isEmpty) return null;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    if (minLat == maxLat) {
      minLat -= 0.01;
      maxLat += 0.01;
    }
    if (minLng == maxLng) {
      minLng -= 0.01;
      maxLng += 0.01;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  double _requiredBalance() {
    return mission.walletBalanceRequiredXof > 0
        ? mission.walletBalanceRequiredXof
        : mission.totalCommissionXof;
  }

  String _fallbackPickupDistance() {
    if (mission.distanceKm == null) return 'Non disponible';
    return '${mission.distanceKm!.toStringAsFixed(1)} km';
  }

  String _fallbackTotalDistance(_MissionPreview? preview) {
    return preview?.deliveryDistanceText ?? _fallbackPickupDistance();
  }

  String _pickupZoneLabel() {
    if (mission.pickupAreaLabel.trim().isNotEmpty) {
      return mission.pickupAreaLabel.trim();
    }
    return mission.pickupLabel;
  }

  String _deliveryZoneLabel() {
    if (mission.deliveryAreaLabel.trim().isNotEmpty) {
      return mission.deliveryAreaLabel.trim();
    }
    return mission.deliveryLabel;
  }

  String _deliveryModeLabel() {
    if (mission.pickupIsRelay && mission.deliveryIsRelay) {
      return 'Relais -> Relais';
    }
    if (mission.pickupIsRelay && !mission.deliveryIsRelay) {
      return 'Relais -> Domicile';
    }
    if (!mission.pickupIsRelay && mission.deliveryIsRelay) {
      return 'Domicile -> Relais';
    }
    return 'Domicile -> Domicile';
  }

  String _payerLabel() {
    if (mission.whoPays == 'recipient') {
      return 'Paye par le destinataire';
    }
    return "Paye par l'expediteur";
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
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text(address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          Text(city,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    ]);
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    try {
      final requiredBalance = mission.walletBalanceRequiredXof > 0
          ? mission.walletBalanceRequiredXof
          : mission.totalCommissionXof;
      if (requiredBalance > 0) {
        final wallet = await ref.read(driverWalletProvider.future);
        if (wallet.balance < requiredBalance) {
          if (context.mounted) {
            await _showRechargeRequiredDialog(
              context,
              requiredBalance: requiredBalance,
              currentBalance: wallet.balance,
            );
          }
          return;
        }
      }
      final gpsReady = await ensureGpsReady();
      if (!gpsReady) {
        return;
      }
      final api = ref.read(apiClientProvider);
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 10));
      } catch (_) {}
      await api.acceptMission(
        mission.id,
        location: position == null
            ? null
            : {
                'lat': position.latitude,
                'lng': position.longitude,
                'accuracy': position.accuracy,
              },
      );
      ref.invalidate(availableMissionsProvider);
      ref.invalidate(myMissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Course acceptée ! Bonne livraison'),
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
        if (msg.toLowerCase().contains('solde insuffisant')) {
          await _showRechargeRequiredDialog(context);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _decline(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiClientProvider).declineMission(mission.id);
      ref.invalidate(availableMissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mission refusée.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showRechargeRequiredDialog(
    BuildContext context, {
    double? requiredBalance,
    double? currentBalance,
  }) async {
    final details = requiredBalance == null
        ? 'Rechargez votre wallet pour accepter cette course.'
        : 'Solde requis : ${formatXof(requiredBalance)}. Solde actuel : ${formatXof(currentBalance ?? 0)}.';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recharge nécessaire'),
        content: Text(details),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go('/driver/wallet');
            },
            child: const Text('Recharger'),
          ),
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.blueGrey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? trailing;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading && value == 'Non disponible' ? 'Chargement…' : value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if ((trailing ?? '').isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trailing!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewMetricCard extends StatelessWidget {
  const _PreviewMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey.shade600),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey.shade500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLegendChip extends StatelessWidget {
  const _MapLegendChip({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
