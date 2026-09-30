import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_provider.dart';
import '../models/delivery_mission.dart';
import '../../features/driver/providers/driver_provider.dart';
import 'driver_location_consent.dart';
import 'driver_trace_buffer.dart';
import 'fresh_position_helper.dart';
import 'location_policy.dart';

class DriverLocationHealth {
  const DriverLocationHealth(
      {this.tracking = false, this.lastSuccess, this.error});
  final bool tracking;
  final DateTime? lastSuccess;
  final String? error;
}

final driverLocationHealthProvider =
    StateProvider<DriverLocationHealth>((ref) => const DriverLocationHealth());

class DriverGpsPlatform {
  Future<bool> hasConsent() => DriverLocationConsent.hasAccepted();
  Future<bool> isEnabled() => Geolocator.isLocationServiceEnabled();
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  Stream<ServiceStatus> get serviceStatus =>
      Geolocator.getServiceStatusStream();
  Stream<Position> positions(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);
  Future<Position> freshPosition() =>
      FreshPositionHelper.getDriverPresencePosition();
  Future<void> refreshPolicy() => LocationPolicy.refresh();
}

final driverGpsPlatformProvider = Provider((ref) => DriverGpsPlatform());
final driverTraceBufferProvider = Provider((ref) => DriverTraceBuffer());

final driverPresenceServiceProvider = Provider<DriverPresenceService>((ref) {
  final service = DriverPresenceService(ref);
  ref.listen(authProvider,
      (_, next) => unawaited(service.reconcile(next.valueOrNull)));
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

class DriverPresenceService {
  DriverPresenceService(this._ref);
  final Ref _ref;
  final _positionController = StreamController<Position>.broadcast();
  StreamSubscription<Position>? _subscription;
  StreamSubscription<ServiceStatus>? _serviceSubscription;
  ProviderSubscription<AsyncValue<List<DeliveryMission>>>? _missionSubscription;
  Future<Position>? _freshPositionRequest;
  Future<void> _reconcileTail = Future.value();
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  DateTime? _lastUpload;
  DateTime? _lastBufferedAt;
  Position? _latestPosition;
  String? _owner;
  String? _streamMission;
  DeliveryMission? _mission;
  String? _confirmedCollectionMission;
  DateTime? _confirmedCollectionAt;
  List<DriverTracePoint> _pendingTrace = [];
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  bool _uploading = false;
  bool _flushing = false;
  bool _inForeground = true;

  Stream<Position> get positions => _positionController.stream;
  bool _owns(String? owner, int generation) =>
      !_disposed &&
      generation == _generation &&
      owner != null &&
      _ref.read(authProvider).valueOrNull?.isAuthenticated == true &&
      _ref.read(authProvider).valueOrNull?.user?.role == 'driver' &&
      _ref.read(authProvider).valueOrNull?.user?.id == owner;

  Future<Position> requestFreshPosition() {
    final pending = _freshPositionRequest;
    if (pending != null) return pending;
    final owner = _ref.read(authProvider).valueOrNull?.user?.id;
    final generation = _generation;
    final request =
        _ref.read(driverGpsPlatformProvider).freshPosition().then((position) {
      if (!_owns(owner, generation)) {
        throw StateError('Le compte livreur a changé.');
      }
      if (!LocationPolicy.current.accepts(position)) {
        throw StateError('Position GPS trop ancienne ou imprécise.');
      }
      unawaited(_receive(position, owner, generation));
      return position;
    });
    _freshPositionRequest = request;
    void clear() {
      if (identical(_freshPositionRequest, request)) {
        _freshPositionRequest = null;
      }
    }

    unawaited(request.then<void>((_) => clear(),
        onError: (Object _, StackTrace __) => clear()));
    return request;
  }

  Future<void> start() async {
    if (_disposed) return;
    _started = true;
    await reconcile(_ref.read(authProvider).valueOrNull);
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    _inForeground = state == AppLifecycleState.resumed;
    if (_inForeground && !_disposed) {
      await reconcile(_ref.read(authProvider).valueOrNull, forceUpload: true);
    }
  }

  Future<void> reconcile(AuthState? auth, {bool forceUpload = false}) {
    if (!_started || _disposed) return Future.value();
    final next = _reconcileTail.then((_) => _reconcile(forceUpload));
    _reconcileTail = next.catchError((Object _) {
      _health(
          error: 'Le suivi GPS n’a pas pu démarrer. Vérifiez la localisation.');
      _scheduleRetry();
    });
    return _reconcileTail;
  }

  Future<void> _reconcile(bool forceUpload) async {
    if (_disposed) return;
    final auth = _ref.read(authProvider).valueOrNull;
    final driver = auth?.isAuthenticated == true &&
        auth?.user?.role == 'driver' &&
        auth?.user?.isActive != false &&
        auth?.user?.isBanned != true;
    final owner = driver ? auth!.user!.id : null;
    if (_owner != owner) {
      await _stopStream();
      _missionSubscription?.close();
      _missionSubscription = null;
      _mission = null;
      _confirmedCollectionMission = null;
      _confirmedCollectionAt = null;
      _owner = owner;
      _pendingTrace = owner == null
          ? []
          : await _ref.read(driverTraceBufferProvider).load(owner);
      if (owner == null) {
        await _ref.read(driverTraceBufferProvider).save(null, []);
      }
      if (owner != null && !_disposed) {
        _missionSubscription = _ref.listen(myMissionsProvider, (_, next) {
          if (_disposed || next.isLoading || next.hasError) return;
          final active = (next.valueOrNull ?? [])
              .where((m) => activeDriverMissionStatuses.contains(m.status));
          _mission = active.isEmpty ? null : active.first;
          unawaited(reconcile(_ref.read(authProvider).valueOrNull,
              forceUpload: true));
        }, fireImmediately: true);
      }
    }
    if (_disposed) return;
    if (owner == null ||
        (auth?.user?.isAvailable != true && _mission == null)) {
      await _stopStream();
      _ref.read(driverLocationHealthProvider.notifier).state =
          const DriverLocationHealth();
      if (owner != null && _pendingTrace.isNotEmpty) {
        unawaited(_flushTrace(owner, _generation));
      }
      return;
    }
    final platform = _ref.read(driverGpsPlatformProvider);
    await platform.refreshPolicy();
    if (_disposed || _ref.read(authProvider).valueOrNull?.user?.id != owner) {
      return;
    }
    final policy = LocationPolicy.current;
    _heartbeatTimer ??= Timer.periodic(
        policy.heartbeatInterval, (_) => unawaited(_heartbeat()));
    _serviceSubscription ??= platform.serviceStatus.listen(
        (_) => unawaited(_restart()),
        onError: (Object _) => _scheduleRetry());
    if (!await platform.hasConsent() || !await platform.isEnabled()) {
      await _stopStream(keepRecovery: true);
      _health(
          error:
              'Activez la localisation et autorisez le suivi pour travailler.');
      _scheduleRetry();
      return;
    }
    final permission = await platform.permission();
    final allowed = defaultTargetPlatform == TargetPlatform.android
        ? permission == LocationPermission.always
        : permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
    if (!allowed) {
      await _stopStream(keepRecovery: true);
      _health(
          error: 'Autorisez la localisation dans les réglages du téléphone.');
      _scheduleRetry();
      return;
    }
    if (_subscription != null && _streamMission != _mission?.id) {
      await _stopStream(keepRecovery: true);
    }
    if (_disposed || _ref.read(authProvider).valueOrNull?.user?.id != owner) {
      return;
    }
    if (_subscription == null && _inForeground) {
      final generation = _generation;
      _streamMission = _mission?.id;
      _subscription = platform.positions(_settings(policy)).listen((position) {
        unawaited(_receive(position, owner, generation));
      }, onError: (Object _) {
        if (_owns(owner, generation)) unawaited(_streamFailed());
      }, onDone: () {
        if (_owns(owner, generation)) unawaited(_streamFailed());
      });
      _health(tracking: true);
      _retryTimer?.cancel();
      _retryTimer = null;
      forceUpload = true;
    }
    if (forceUpload && _subscription != null) unawaited(_heartbeat());
  }

  LocationSettings _settings(LocationPolicy policy) {
    final distance = _mission == null ? 25 : 10;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distance,
          intervalDuration: policy.uploadInterval,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Localisation Denkma active',
              notificationText:
                  'Position actualisée pour les courses proches et le suivi de votre livraison par Denkma.',
              notificationIcon: AndroidResource(
                  name: 'ic_notification_logo', defType: 'drawable'),
              enableWakeLock: true));
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: distance,
          activityType: ActivityType.otherNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true);
    }
    return LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: distance);
  }

  Future<void> _receive(
      Position position, String? owner, int generation) async {
    if (!_owns(owner, generation)) return;
    if (!LocationPolicy.current.accepts(position)) {
      _health(
          tracking: _subscription != null,
          error: 'Position GPS trop ancienne ou imprécise.');
      return;
    }
    if (_latestPosition != null &&
        !position.timestamp.isAfter(_latestPosition!.timestamp)) {
      return;
    }
    _latestPosition = position;
    if (!_positionController.isClosed) _positionController.add(position);
    final policy = LocationPolicy.current;
    final mission = _mission;
    final startedAt = mission?.startedAt ??
        (mission?.id == _confirmedCollectionMission
            ? _confirmedCollectionAt
            : null);
    if (mission != null &&
        startedAt != null &&
        !position.timestamp.isBefore(startedAt) &&
        (_lastBufferedAt == null ||
            position.timestamp.difference(_lastBufferedAt!) >=
                policy.uploadInterval)) {
      _lastBufferedAt = position.timestamp;
      _pendingTrace.add(DriverTracePoint(mission.id, _body(position)));
      _trimTrace();
      await _ref.read(driverTraceBufferProvider).save(owner, _pendingTrace);
      if (!_owns(owner, generation)) return;
    }
    await _transmit(owner!, generation);
  }

  Map<String, dynamic> _body(Position position) => {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'captured_at': position.timestamp.toUtc().toIso8601String(),
      };

  void registerCollection(String missionId, DateTime startedAt) {
    if (_disposed || _mission?.id != missionId) return;
    _confirmedCollectionMission = missionId;
    _confirmedCollectionAt = startedAt;
  }

  Future<void> _heartbeat() async {
    if (_disposed) return;
    if (_subscription == null) {
      await reconcile(_ref.read(authProvider).valueOrNull);
      return;
    }
    final owner = _owner;
    final generation = _generation;
    if (_latestPosition != null &&
        LocationPolicy.current.accepts(_latestPosition!)) {
      await _transmit(owner!, generation);
      return;
    }
    try {
      await requestFreshPosition();
    } catch (_) {
      if (_owns(owner, generation)) {
        _health(
            tracking: _subscription != null,
            error: 'Impossible d’obtenir une position récente.');
      }
    }
  }

  Future<void> _transmit(String owner, int generation) async {
    if (!_owns(owner, generation) || _uploading || _latestPosition == null) {
      return;
    }
    final now = DateTime.now();
    if (_lastUpload != null &&
        now.difference(_lastUpload!) < LocationPolicy.current.uploadInterval) {
      return;
    }
    final position = _latestPosition!;
    if (!LocationPolicy.current.accepts(position)) return;
    _uploading = true;
    _lastUpload = now;
    final missionId = _mission?.id;
    try {
      final api = _ref.read(apiClientProvider);
      var traceRecorded = false;
      if (missionId != null) {
        final response = await api.updateLocation(missionId, _body(position));
        traceRecorded =
            response.data is Map && response.data['trace_recorded'] != false;
      } else {
        await api.updateMyDriverLocation(_body(position));
      }
      if (!_owns(owner, generation)) return;
      _health(tracking: _subscription != null, lastSuccess: position.timestamp);
      if (missionId != null && traceRecorded) {
        _pendingTrace.removeWhere((p) =>
            p.missionId == missionId &&
            p.body['captured_at'] == _body(position)['captured_at']);
        await _ref.read(driverTraceBufferProvider).save(owner, _pendingTrace);
      }
      await _flushTrace(owner, generation);
    } catch (error) {
      if (!_owns(owner, generation)) return;
      if (error is DioException &&
          error.response?.statusCode == 400 &&
          missionId != null) {
        _ref.invalidate(myMissionsProvider);
      }
      _health(
          tracking: _subscription != null,
          error:
              'Dernière position non transmise. Vérifiez la connexion. Le parcours sera renvoyé dès son retour.');
    } finally {
      _uploading = false;
    }
  }

  void _trimTrace() {
    final policy = LocationPolicy.current;
    final cutoff = DateTime.now().subtract(policy.offlineRetention);
    _pendingTrace.removeWhere(
        (p) => p.capturedAt == null || p.capturedAt!.isBefore(cutoff));
    final maxPoints =
        (policy.offlineRetention.inSeconds / policy.uploadInterval.inSeconds)
            .ceil();
    if (_pendingTrace.length > maxPoints) {
      _pendingTrace.removeRange(0, _pendingTrace.length - maxPoints);
    }
  }

  Future<void> _flushTrace(String owner, int generation) async {
    if (_flushing || !_owns(owner, generation)) return;
    _flushing = true;
    try {
      _trimTrace();
      while (_pendingTrace.isNotEmpty && _owns(owner, generation)) {
        final missionId = _pendingTrace.first.missionId;
        final batch = _pendingTrace
            .where((p) => p.missionId == missionId)
            .take(300)
            .toList();
        try {
          await _ref
              .read(apiClientProvider)
              .uploadDriverTrace(missionId, batch.map((p) => p.body).toList());
        } on DioException catch (error) {
          if (![400, 403, 404, 410].contains(error.response?.statusCode)) {
            rethrow;
          }
        }
        if (!_owns(owner, generation)) return;
        _pendingTrace.removeWhere(batch.contains);
        await _ref.read(driverTraceBufferProvider).save(owner, _pendingTrace);
      }
    } catch (_) {
    } finally {
      _flushing = false;
    }
  }

  void _health({bool tracking = false, DateTime? lastSuccess, String? error}) {
    if (_disposed) return;
    _ref.read(driverLocationHealthProvider.notifier).state =
        DriverLocationHealth(
            tracking: tracking,
            lastSuccess: lastSuccess ??
                _ref.read(driverLocationHealthProvider).lastSuccess,
            error: error);
  }

  Future<void> _streamFailed() async {
    await _stopStream(keepRecovery: true);
    _health(
        error:
            'Suivi GPS interrompu. Une reprise sera tentée automatiquement.');
    _scheduleRetry();
  }

  Future<void> _restart() async {
    await _stopStream(keepRecovery: true);
    if (!_disposed) {
      await reconcile(_ref.read(authProvider).valueOrNull, forceUpload: true);
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    _retryTimer = Timer(LocationPolicy.current.heartbeatInterval, () {
      _retryTimer = null;
      unawaited(
          reconcile(_ref.read(authProvider).valueOrNull, forceUpload: true));
    });
  }

  Future<void> _stopStream({bool keepRecovery = false}) async {
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    _streamMission = null;
    _latestPosition = null;
    _freshPositionRequest = null;
    _lastUpload = null;
    _lastBufferedAt = null;
    await subscription?.cancel();
    if (!keepRecovery) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      final status = _serviceSubscription;
      _serviceSubscription = null;
      await status?.cancel();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _missionSubscription?.close();
    await _stopStream();
    await _positionController.close();
  }
}
