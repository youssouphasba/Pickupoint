import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/denkma_rounding_offer.dart';
import '../../../shared/utils/phone_utils.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../../../core/models/delivery_mission.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/notifications/notifications_bell_button.dart';
import '../../../shared/notifications/notification_permission_banner.dart';
import '../../../shared/promotions/campaign_banner.dart';
import '../../../core/location/driver_location_consent.dart';
import '../../../core/location/driver_presence_service.dart';
import '../../../core/location/fresh_position_helper.dart';
import '../../../core/notifications/notification_navigation.dart';
import '../../../shared/feedback/action_feedback.dart';
import '../widgets/completed_mission_card.dart';

class _MissionPreview {
  const _MissionPreview({
    this.pickupDistanceText,
    this.pickupEtaText,
    this.deliveryDistanceText,
    this.deliveryEtaText,
    this.totalDistanceText,
    this.totalEtaText,
    this.pickupEncodedPolyline,
    this.deliveryEncodedPolyline,
  });

  final String? pickupDistanceText;
  final String? pickupEtaText;
  final String? deliveryDistanceText;
  final String? deliveryEtaText;
  final String? totalDistanceText;
  final String? totalEtaText;
  final String? pickupEncodedPolyline;
  final String? deliveryEncodedPolyline;

  factory _MissionPreview.fromJson(Map<String, dynamic> json) {
    return _MissionPreview(
      pickupDistanceText: json['pickup_distance_text']?.toString(),
      pickupEtaText: json['pickup_eta_text']?.toString(),
      deliveryDistanceText: json['delivery_distance_text']?.toString(),
      deliveryEtaText: json['delivery_eta_text']?.toString(),
      totalDistanceText: json['total_distance_text']?.toString(),
      totalEtaText: json['total_eta_text']?.toString(),
      pickupEncodedPolyline: json['pickup_encoded_polyline']?.toString(),
      deliveryEncodedPolyline: json['delivery_encoded_polyline']?.toString(),
    );
  }
}

class DriverHome extends ConsumerStatefulWidget {
  const DriverHome({
    super.key,
    this.initialPreviewMissionId,
    this.unavailableMissionId,
    this.openAvailableMissions = false,
    this.notificationRequest,
  });

  final String? initialPreviewMissionId;
  final String? unavailableMissionId;
  final bool openAvailableMissions;
  final DriverMissionNotificationRequest? notificationRequest;

  @override
  ConsumerState<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends ConsumerState<DriverHome>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _tabController;
  double? _driverLat;
  double? _driverLng;
  bool _gpsLoading = false;
  bool _locationAccessLoading = false;
  bool _backgroundLocationAllowed = true;
  String? _locationError;
  Future<void>? _locationRequest;
  Future<bool>? _locationPreparationRequest;
  StreamSubscription<Position>? _presencePositionSubscription;
  Timer? _gpsRetryTimer;
  bool _toggling = false;
  bool _notificationActionHandled = false;
  bool _notificationActionLoading = false;
  String? _missionActionId;
  int _notificationActionGeneration = 0;
  ModalRoute<dynamic>? _notificationPreviewRoute;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _refreshBackgroundPermission();
    _presencePositionSubscription =
        ref.read(driverPresenceServiceProvider).positions.listen((position) {
      if (!mounted) return;
      setState(() {
        _driverLat = position.latitude;
        _driverLng = position.longitude;
        _locationAccessLoading = false;
        _gpsLoading = false;
        _locationError = null;
      });
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      ref.invalidate(availableMissionsProvider);
      ref.invalidate(myMissionsProvider);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareLocationAccess();
    });
  }

  @override
  void didUpdateWidget(covariant DriverHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPreviewMissionId != widget.initialPreviewMissionId ||
        oldWidget.unavailableMissionId != widget.unavailableMissionId ||
        oldWidget.openAvailableMissions != widget.openAvailableMissions ||
        oldWidget.notificationRequest != widget.notificationRequest) {
      _notificationActionGeneration++;
      _notificationActionHandled = false;
      _notificationActionLoading = false;
      final previewRoute = _notificationPreviewRoute;
      _notificationPreviewRoute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previewRoute?.isActive == true) {
          previewRoute!.navigator?.removeRoute(previewRoute);
        }
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _gpsRetryTimer?.cancel();
    _presencePositionSubscription?.cancel();
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBackgroundPermission();
      ref.invalidate(availableMissionsProvider);
      ref.invalidate(myMissionsProvider);
      _prepareLocationAccess();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final missions = ref.read(myMissionsProvider).valueOrNull ??
            const <DeliveryMission>[];
        if (hasActiveDriverMission(missions) && _tabController.index != 1) {
          _tabController.animateTo(1);
        }
      });
    }
  }

  Future<void> _refreshBackgroundPermission() async {
    if (!DriverLocationConsent.requiresAlwaysPermission) return;
    final permission = await Geolocator.checkPermission();
    if (mounted) {
      setState(() {
        _backgroundLocationAllowed = permission == LocationPermission.always;
      });
    }
  }

  Future<bool> _prepareLocationAccess({bool userInitiated = false}) async {
    final pending = _locationPreparationRequest;
    if (pending != null) return pending;

    late final Future<bool> request;
    request = _prepareLocationAccessOnce(userInitiated: userInitiated)
        .whenComplete(() {
      if (identical(_locationPreparationRequest, request)) {
        _locationPreparationRequest = null;
      }
    });
    _locationPreparationRequest = request;
    return request;
  }

  Future<bool> _prepareLocationAccessOnce({
    required bool userInitiated,
  }) async {
    if (mounted) {
      setState(() {
        _locationAccessLoading = true;
        _gpsLoading = false;
        _locationError = null;
        _driverLat = null;
        _driverLng = null;
      });
    }

    bool allowed;
    try {
      allowed = await DriverLocationConsent.ensure(
        context,
        userInitiated: userInitiated,
      );
    } catch (_) {
      allowed = false;
    }
    if (!mounted) return false;
    await _refreshBackgroundPermission();
    if (!allowed) {
      setState(() {
        _locationAccessLoading = false;
        _gpsLoading = false;
        _locationError =
            'Autorisez la localisation pour voir les courses disponibles.';
      });
      return false;
    }

    setState(() {
      _locationAccessLoading = false;
      _gpsLoading = true;
    });
    await _fetchDriverLocation();
    if (!mounted) return false;
    unawaited(ref.read(driverPresenceServiceProvider).reconcile(
          ref.read(authProvider).valueOrNull,
          forceUpload: true,
        ));
    return _driverLat != null && _driverLng != null;
  }

  /// Capture la position du livreur pour filtrer les missions par proximité.
  Future<void> _fetchDriverLocation() async {
    final pending = _locationRequest;
    if (pending != null) return pending;
    final request = _resolveDriverLocation();
    _locationRequest = request;
    try {
      await request;
    } finally {
      if (identical(_locationRequest, request)) _locationRequest = null;
    }
  }

  Future<void> _resolveDriverLocation() async {
    if (!mounted) return;
    setState(() {
      _gpsLoading = true;
      _locationError = null;
      _driverLat = null;
      _driverLng = null;
    });
    try {
      final pos = await ref
          .read(driverPresenceServiceProvider)
          .requestFreshPosition()
          .timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() {
          _driverLat = pos.latitude;
          _driverLng = pos.longitude;
          _gpsLoading = false;
          _locationError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _driverLat = null;
          _driverLng = null;
          _gpsLoading = false;
          _locationError = 'Localisation indisponible. Vérifiez le GPS.';
        });
        _scheduleGpsRetry();
      }
    }
  }

  void _scheduleGpsRetry() {
    if (_gpsRetryTimer != null) return;
    _gpsRetryTimer = Timer(const Duration(seconds: 15), () {
      _gpsRetryTimer = null;
      if (mounted) _prepareLocationAccess();
    });
  }

  Future<void> _toggleAvailability() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final currentlyAvailable =
          ref.read(authProvider).valueOrNull?.user?.isAvailable ?? false;
      if (!currentlyAvailable &&
          !await DriverLocationConsent.ensureForWork(context)) {
        return;
      }
      if (!mounted) return;
      final api = ref.read(apiClientProvider);
      final res = await api.toggleAvailability();
      final newVal = res.data['is_available'] as bool? ?? false;
      ref.read(authProvider.notifier).updateUserAvailability(newVal);
      if (newVal) {
        unawaited(ref.read(driverPresenceServiceProvider).reconcile(
              ref.read(authProvider).valueOrNull,
              forceUpload: true,
            ));
      }
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

  Future<void> _acceptMission(DeliveryMission mission) async {
    if (!mounted || _missionActionId != null) return;
    setState(() => _missionActionId = mission.id);
    final router = GoRouter.of(context);
    try {
      if (!await DriverLocationConsent.ensureForWork(context)) return;
      if (!context.mounted) return;
      final requiredBalance = mission.walletBalanceRequiredXof > 0
          ? mission.walletBalanceRequiredXof
          : mission.totalCommissionXof;
      if (requiredBalance > 0) {
        final wallet = await ref.refresh(driverWalletProvider.future);
        if (!mounted) return;
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
      final api = ref.read(apiClientProvider);
      final position = await FreshPositionHelper.getDriverSearchPosition();
      if (!mounted) return;
      await api.acceptMission(
        mission.id,
        location: {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'captured_at': position.timestamp.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      ref.invalidate(missionProvider(mission.id));
      ref.invalidate(availableMissionsProvider);
      ref.invalidate(myMissionsProvider);
      ref.invalidate(driverWalletProvider);
      _tabController.animateTo(1);
      unawaited(ActionFeedback.mission());
      router.push('/driver/mission/${mission.id}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course acceptée')),
      );
    } catch (e) {
      if (context.mounted) {
        final msg = friendlyError(e);
        if (msg.toLowerCase().contains('solde insuffisant')) {
          await _showRechargeRequiredDialog(context);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _missionActionId = null);
    }
  }

  Future<void> _declineMission(DeliveryMission mission) async {
    if (!mounted || _missionActionId != null) return;
    setState(() => _missionActionId = mission.id);
    try {
      await ref.read(apiClientProvider).declineMission(mission.id);
      if (!mounted) return;
      ref.invalidate(availableMissionsProvider);
      unawaited(ActionFeedback.confirm());
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
    } finally {
      if (mounted) setState(() => _missionActionId = null);
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

  Future<bool> _ensureGpsReady() async {
    return DriverLocationConsent.ensure(context, userInitiated: true);
  }

  DriverLocation get _driverLoc => (lat: _driverLat, lng: _driverLng);

  void _handleNotificationAction() {
    if (_notificationActionHandled || _notificationActionLoading) return;
    final unavailable = (widget.unavailableMissionId ?? '').isNotEmpty;
    final requested = unavailable ||
        widget.openAvailableMissions ||
        (widget.initialPreviewMissionId ?? '').isNotEmpty;
    if (!requested) return;
    if (!unavailable &&
        (_gpsLoading ||
            _locationAccessLoading ||
            _driverLat == null ||
            _driverLng == null)) {
      return;
    }
    _notificationActionLoading = true;
    final generation = _notificationActionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentNotificationAction(generation)) {
        if (mounted && generation == _notificationActionGeneration) {
          _notificationActionLoading = false;
        }
        return;
      }
      _notificationActionHandled = true;
      unawaited(_openNotificationAction(generation, unavailable: unavailable));
    });
  }

  bool _isCurrentNotificationAction(int generation) {
    return mounted &&
        generation == _notificationActionGeneration &&
        ModalRoute.of(context)?.isCurrent == true;
  }

  Future<void> _openNotificationAction(
    int generation, {
    required bool unavailable,
  }) async {
    setState(() => _notificationActionLoading = true);
    try {
      final myMissions = await ref.refresh(myMissionsProvider.future);
      if (!mounted || !_isCurrentNotificationAction(generation)) return;
      if (hasActiveDriverMission(myMissions)) {
        _tabController.animateTo(1);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terminez votre mission en cours avant d’accepter une autre course.',
            ),
          ),
        );
        return;
      }
      _tabController.animateTo(0);
      if (unavailable) {
        ref.invalidate(availableMissionsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cette course a déjà été acceptée par un autre livreur.'),
          ),
        );
        return;
      }
      final location = _driverLoc;
      if (location.lat == null || location.lng == null) {
        _notificationActionHandled = false;
        return;
      }
      final missions =
          await ref.refresh(availableMissionsProvider(location).future);
      if (!mounted || !_isCurrentNotificationAction(generation)) return;
      if (missions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Il n’y a plus de course disponible dans votre rayon.'),
          ),
        );
        return;
      }
      if (missions.length != 1) return;
      final card = _MissionCard(
        mission: missions.single,
        isAvailable: true,
        driverLoc: location,
        ensureGpsReady: _ensureGpsReady,
        onAccept: _acceptMission,
        onDecline: _declineMission,
      );
      setState(() => _notificationActionLoading = false);
      await card._showPreviewSheet(
        context,
        ref,
        onOpened: (route) => _notificationPreviewRoute = route,
      );
      if (mounted && generation == _notificationActionGeneration) {
        _notificationPreviewRoute = null;
      }
    } catch (error) {
      if (!mounted || !_isCurrentNotificationAction(generation)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          action: SnackBarAction(
            label: 'Réessayer',
            onPressed: () {
              if (!mounted || generation != _notificationActionGeneration) {
                return;
              }
              setState(() => _notificationActionHandled = false);
            },
          ),
        ),
      );
    } finally {
      if (mounted && generation == _notificationActionGeneration) {
        setState(() => _notificationActionLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(foregroundMissionNotificationProvider, (_, __) {
      ref.invalidate(availableMissionsProvider);
    });
    final isAvailable =
        ref.watch(authProvider).value?.user?.isAvailable ?? false;
    final hasGps = _driverLat != null && _driverLng != null;
    final availableAsync = hasGps
        ? ref.watch(availableMissionsProvider(_driverLoc))
        : const AsyncValue.data(<DeliveryMission>[]);
    final myMissionsAsync = ref.watch(myMissionsProvider);
    final myMissions = myMissionsAsync.valueOrNull ?? const <DeliveryMission>[];
    final hasLockedMission = hasActiveDriverMission(myMissions);
    if (hasLockedMission && _tabController.index != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _tabController.index == 1) return;
        _tabController.animateTo(1);
      });
    }
    _handleNotificationAction();

    final locationMessage = !_backgroundLocationAllowed &&
            !_locationAccessLoading &&
            !_gpsLoading
        ? 'Position en arrière-plan requise pour recevoir des courses à proximité.'
        : _locationAccessLoading
            ? 'Autorisation de localisation requise'
            : _gpsLoading
                ? 'Recherche de votre position…'
                : _locationError ??
                    (hasGps
                        ? 'Missions autour de vous'
                        : 'Choisissez « ${DriverLocationConsent.permissionOptionLabel} » '
                            'pour voir les missions');
    final locationActionVisible =
        !_backgroundLocationAllowed && !_locationAccessLoading && !_gpsLoading;

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Column(
            children: [
              Container(
                color: hasGps ? Colors.green.shade700 : Colors.orange.shade700,
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
                      locationMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (locationActionVisible)
                    TextButton(
                      onPressed: () => _prepareLocationAccess(
                        userInitiated: true,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 30),
                      ),
                      child: Text('Activer '
                          '« ${DriverLocationConsent.permissionOptionLabel} »'),
                    ),
                ]),
              ),
              TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                tabs: const [
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
          IconButton(
            icon: _gpsLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location),
            tooltip: 'Actualiser ma position',
            onPressed: _gpsLoading
                ? null
                : () => _prepareLocationAccess(userInitiated: true),
          ),
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
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
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
          const SupportWhatsAppButton(),
        ],
      ),
      body: Column(
        children: [
          const NotificationPermissionBanner(),
          const CampaignBanner(role: 'driver'),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _MissionsList(
                      asyncValue: availableAsync,
                      isAvailable: true,
                      driverLoc: _driverLoc,
                      ensureGpsReady: _ensureGpsReady,
                      backgroundLocationAllowed: _backgroundLocationAllowed,
                      onEnableBackgroundLocation: () =>
                          _prepareLocationAccess(userInitiated: true),
                      onAccept: _acceptMission,
                      onDecline: _declineMission,
                    ),
                    _MissionsList(
                      asyncValue: myMissionsAsync,
                      isAvailable: false,
                      driverLoc: _driverLoc,
                      ensureGpsReady: _ensureGpsReady,
                    ),
                  ],
                ),
                if (_gpsLoading ||
                    _notificationActionLoading ||
                    _missionActionId != null)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
        ],
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
    this.backgroundLocationAllowed = true,
    this.onEnableBackgroundLocation,
    this.onAccept,
    this.onDecline,
  });
  final AsyncValue<List<DeliveryMission>> asyncValue;
  final bool isAvailable;
  final DriverLocation driverLoc;
  final Future<bool> Function() ensureGpsReady;
  final bool backgroundLocationAllowed;
  final VoidCallback? onEnableBackgroundLocation;
  final Future<void> Function(DeliveryMission)? onAccept;
  final Future<void> Function(DeliveryMission)? onDecline;

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
            active.sort(
              (a, b) => _driverMissionDate(b).compareTo(_driverMissionDate(a)),
            );
            completed.sort(
              (a, b) => _driverMissionDate(b).compareTo(_driverMissionDate(a)),
            );
            final recentCompleted = completed.take(10).toList();

            if (active.isEmpty && completed.isEmpty) {
              return _buildEmpty('Vous n\'avez pas encore de mission');
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                      Text('Missions terminées',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700)),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  ...recentCompleted.asMap().entries.map(
                        (entry) => _MissionEntrance(
                          index: entry.key,
                          child: CompletedMissionCard(mission: entry.value),
                        ),
                      ),
                  Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          context.push('/driver/missions/completed'),
                      icon: const Icon(Icons.history),
                      label: const Text('Voir plus'),
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            );
          }

          // Pour "Disponibles" : comportement inchangé
          if (missions.isEmpty) {
            if (!backgroundLocationAllowed) {
              return _buildEmpty(
                DriverLocationConsent.settingsInstructions,
                actionLabel: 'Activer '
                    '« ${DriverLocationConsent.permissionOptionLabel} »',
                onAction: onEnableBackgroundLocation,
              );
            }
            return _buildEmpty(driverLoc.lat != null
                ? 'Aucune course dans votre rayon'
                : 'Activez la localisation pour voir les courses');
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: missions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MissionEntrance(
              index: i,
              child: _MissionCard(
                mission: missions[i],
                isAvailable: true,
                driverLoc: driverLoc,
                ensureGpsReady: ensureGpsReady,
                onAccept: onAccept,
                onDecline: onDecline,
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => _buildEmpty(friendlyError(e)),
      ),
    );
  }

  Widget _buildEmpty(
    String msg, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_shipping_outlined,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Text(
                        msg,
                        style:
                            const TextStyle(fontSize: 15, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(actionLabel),
                      ),
                    ],
                  ]),
            ),
          )
        ],
      );
}

DateTime _driverMissionDate(DeliveryMission mission) {
  return mission.completedAt ??
      mission.startedAt ??
      mission.assignedAt ??
      mission.createdAt;
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

class _MissionEntrance extends StatelessWidget {
  const _MissionEntrance({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = index.clamp(0, 5).toInt() * 35;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: animatedChild,
        ),
      ),
      child: child,
    );
  }
}

enum _MissionPreviewAction { accept, decline }

class _MissionCard extends ConsumerWidget {
  const _MissionCard({
    required this.mission,
    required this.isAvailable,
    required this.driverLoc,
    required this.ensureGpsReady,
    this.onAccept,
    this.onDecline,
  });
  final DeliveryMission mission;
  final bool isAvailable;
  final DriverLocation driverLoc;
  final Future<bool> Function() ensureGpsReady;
  final Future<void> Function(DeliveryMission)? onAccept;
  final Future<void> Function(DeliveryMission)? onDecline;

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
          DenkmaRoundingOffer(
            amount: mission.rounding.driverBonus,
            includedInGain: true,
          ),
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
            city: _pickupZoneLabel(),
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
            city: _deliveryZoneLabel(),
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

  Future<void> _showPreviewSheet(
    BuildContext context,
    WidgetRef ref, {
    void Function(ModalRoute<dynamic> route)? onOpened,
  }) async {
    final previewFuture = _loadPreview(ref);
    final action = await showModalBottomSheet<_MissionPreviewAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final route = ModalRoute.of(sheetContext);
        if (route != null) onOpened?.call(route);
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
                future: previewFuture,
                builder: (builderContext, snapshot) {
                  final preview = snapshot.data;
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;
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
                                'Aperçu de la course',
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
                              _buildPreviewMap(preview),
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
                                        ? 'Relais de départ'
                                        : 'Collecte',
                                  ),
                                  _MapLegendChip(
                                    color: Colors.red,
                                    icon: mission.deliveryIsRelay
                                        ? Icons.inventory_2_outlined
                                        : Icons.flag_outlined,
                                    label: mission.deliveryIsRelay
                                        ? "Relais d'arrivée"
                                        : 'Livraison',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              DenkmaRoundingOffer(
                                amount: mission.rounding.driverBonus,
                                includedInGain: true,
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _PreviewMetricCard(
                                      label: 'Gain estimé',
                                      value: formatXof(mission.earnAmount),
                                      icon: Icons.payments_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _PreviewMetricCard(
                                      label: 'Solde requis',
                                      value: formatXof(_requiredBalance()),
                                      icon:
                                          Icons.account_balance_wallet_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: onDecline == null
                                          ? null
                                          : () => Navigator.of(sheetContext)
                                              .pop(_MissionPreviewAction
                                                  .decline),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(52),
                                        side: BorderSide(
                                            color: Colors.grey.shade900),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
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
                                      onPressed: onAccept == null
                                          ? null
                                          : () => Navigator.of(sheetContext)
                                              .pop(
                                                  _MissionPreviewAction.accept),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(52),
                                        backgroundColor:
                                            const Color(0xFFF4FF5A),
                                        foregroundColor: Colors.black87,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
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
                                title: 'Résumé',
                                children: [
                                  _PreviewLine(
                                    icon: Icons.near_me_outlined,
                                    label: 'Vers la collecte',
                                    value: preview?.pickupDistanceText ??
                                        _fallbackPickupDistance(),
                                    trailing: preview?.pickupEtaText,
                                    loading: isLoading,
                                  ),
                                  _PreviewLine(
                                    icon: Icons.route_outlined,
                                    label: 'Collecte → livraison',
                                    value: preview?.deliveryDistanceText ??
                                        'Non disponible',
                                    trailing: preview?.deliveryEtaText,
                                    loading: isLoading,
                                  ),
                                  _PreviewLine(
                                    icon: Icons.alt_route_outlined,
                                    label: 'Trajet total',
                                    value: preview?.totalDistanceText ??
                                        'Non disponible',
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
                                title: 'Détails',
                                children: [
                                  _PreviewLine(
                                    icon: mission.pickupIsRelay
                                        ? Icons.storefront_outlined
                                        : Icons.my_location_outlined,
                                    label: 'Zone de collecte',
                                    value: _pickupZoneLabel(),
                                  ),
                                  if ((mission.senderName ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    _PreviewLine(
                                      icon: Icons.person_outline,
                                      label: 'Nom expéditeur',
                                      value: mission.senderName!.trim(),
                                    ),
                                  _PreviewLine(
                                    icon: mission.deliveryIsRelay
                                        ? Icons.inventory_2_outlined
                                        : Icons.flag_outlined,
                                    label: 'Zone de livraison',
                                    value: _deliveryZoneLabel(),
                                  ),
                                  if ((mission.recipientName ?? '')
                                      .trim()
                                      .isNotEmpty)
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
                                  friendlyError(
                                      snapshot.error ?? Exception('Erreur')),
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
    if (action == _MissionPreviewAction.accept) {
      await onAccept?.call(mission);
    } else if (action == _MissionPreviewAction.decline) {
      await onDecline?.call(mission);
    }
  }

  Widget _buildPreviewMap(_MissionPreview? preview) {
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
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Vous'),
        ),
      if (pickupPoint != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickupPoint,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow:
              InfoWindow(title: 'Expéditeur', snippet: _pickupZoneLabel()),
        ),
      if (deliveryPoint != null)
        Marker(
          markerId: const MarkerId('delivery'),
          position: deliveryPoint,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow:
              InfoWindow(title: 'Destinataire', snippet: _deliveryZoneLabel()),
        ),
    };

    final pickupRoute = _decodeRoute(preview?.pickupEncodedPolyline);
    final deliveryRoute = _decodeRoute(preview?.deliveryEncodedPolyline);
    final polylines = <Polyline>{
      if (pickupRoute.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('driver_to_pickup'),
          points: pickupRoute,
          color: Colors.blue.shade600,
          width: 5,
        ),
      if (deliveryRoute.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('pickup_to_delivery'),
          points: deliveryRoute,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                      Icon(Icons.navigation_outlined,
                          size: 14, color: Colors.blue),
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

  List<LatLng> _decodeRoute(String? encodedPolyline) {
    if (encodedPolyline == null || encodedPolyline.trim().isEmpty) {
      return const [];
    }
    return PolylinePoints()
        .decodePolyline(encodedPolyline)
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();
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
    return '${mission.distanceKm!.toStringAsFixed(1)} km à vol d’oiseau';
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
      return 'Payé par le destinataire';
    }
    return "Payé par l'expéditeur";
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
