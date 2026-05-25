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
import '../../../shared/utils/error_utils.dart';
import '../../../shared/notifications/notifications_bell_button.dart';
import '../../../shared/notifications/notification_permission_banner.dart';
import '../../../core/location/location_tracking_service.dart';

class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({super.key});

  @override
  ConsumerState<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<DriverHome> {
  double? _driverLat;
  double? _driverLng;
  bool _gpsLoading = true;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _fetchDriverLocation();
    // Initialiser le tracking global pour les missions actives
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationTrackingServiceProvider);
    });
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
                    onPressed: () => _accept(context, ref),
                    icon: const Icon(Icons.check),
                    label: const Text('Accepter la course'),
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
          : mission.platformCommissionXof;
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
