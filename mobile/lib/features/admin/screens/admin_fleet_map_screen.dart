import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/admin_provider.dart';
import '../../../shared/utils/error_utils.dart';

class AdminFleetMapScreen extends ConsumerStatefulWidget {
  const AdminFleetMapScreen({super.key});

  @override
  ConsumerState<AdminFleetMapScreen> createState() =>
      _AdminFleetMapScreenState();
}

class _AdminFleetMapScreenState extends ConsumerState<AdminFleetMapScreen> {
  Timer? _refreshTimer;
  GoogleMapController? _mapController;
  String? _selectedMissionId;
  String? _lastCameraKey;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.invalidate(adminFleetProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(adminFleetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi de la flotte live'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _lastCameraKey = null;
              ref.invalidate(adminFleetProvider);
            },
          ),
        ],
      ),
      body: fleetAsync.when(
        data: (payload) {
          final fleet = List<Map<String, dynamic>>.from(
            payload['fleet'] as List? ?? const [],
          );
          final idleDrivers = List<Map<String, dynamic>>.from(
            payload['idle_drivers'] as List? ?? const [],
          );
          final summary = Map<String, dynamic>.from(
            payload['summary'] as Map? ?? const {},
          );
          final selectedMission = _resolveSelectedMission(fleet);
          final visiblePoints =
              _cameraSeedPoints(fleet, idleDrivers, selectedMission);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitBoundsIfNeeded(visiblePoints);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _FleetSummary(summary: summary),
              ),
              Expanded(
                child: (fleet.isEmpty && idleDrivers.isEmpty)
                    ? _buildGlobalEmptyState()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildSelectionHeader(selectedMission),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 290,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildMap(
                                fleet,
                                idleDrivers,
                                selectedMission,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: fleet.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final mission = fleet[index];
                                return _MissionCard(
                                  mission: mission,
                                  isSelected: mission['mission_id'] ==
                                      _selectedMissionId,
                                  onSelect: () {
                                    setState(() {
                                      _selectedMissionId =
                                          mission['mission_id'] as String?;
                                      _lastCameraKey = null;
                                    });
                                  },
                                  onAudit: () {
                                    final parcelId =
                                        mission['parcel_id'] as String?;
                                    if (parcelId == null || parcelId.isEmpty) {
                                      return;
                                    }
                                    context
                                        .push('/admin/parcels/$parcelId/audit');
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  Widget _buildGlobalEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 44, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Aucune mission active avec flotte à suivre.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'La carte s’alimentera dès qu’un livreur assigné enverra sa position ou qu’une mission active existera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionHeader(Map<String, dynamic>? selectedMission) {
    if (selectedMission == null) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Aucune mission sélectionnée',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }
    final tracking = selectedMission['tracking_code'] as String?;
    final eta = selectedMission['eta_text'] as String?;
    final distance = selectedMission['distance_text'] as String?;
    final pickup = _locationLabel(selectedMission['pickup']);
    final delivery = _locationLabel(selectedMission['delivery']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tracking == null || tracking.isEmpty
                      ? 'Mission ${selectedMission['mission_id']}'
                      : 'Colis $tracking',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              _StatusChip(status: selectedMission['status'] as String? ?? ''),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Trajet: ${pickup ?? "Point de départ"} → ${delivery ?? "Point d’arrivée"}',
            style: const TextStyle(fontSize: 13),
          ),
          if (eta != null || distance != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (eta != null && eta.isNotEmpty) 'ETA $eta',
                  if (distance != null && distance.isNotEmpty) distance,
                ].join(' • '),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(
    List<Map<String, dynamic>> fleet,
    List<Map<String, dynamic>> idleDrivers,
    Map<String, dynamic>? selectedMission,
  ) {
    final markers = <Marker>{};
    for (final mission in fleet) {
      final location = _latLngFromMap(mission['driver_location']);
      if (location == null) continue;
      final status = mission['status'] as String? ?? '';
      final isStale = mission['is_stale'] as bool? ?? false;
      markers.add(
        Marker(
          markerId: MarkerId('mission:${mission['mission_id']}'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isStale ? BitmapDescriptor.hueOrange : _statusHue(status),
          ),
          infoWindow: InfoWindow(
            title: mission['driver_name'] as String? ?? 'Livreur',
            snippet: [
              if ((mission['tracking_code'] as String?)?.isNotEmpty ?? false)
                mission['tracking_code'] as String,
              isStale ? 'Signal perdu' : status,
            ].where((value) => value.isNotEmpty).join(' • '),
            onTap: () => _openDriverSheet(mission: mission, isIdle: false),
          ),
          onTap: () {
            setState(() {
              _selectedMissionId = mission['mission_id'] as String?;
              _lastCameraKey = null;
            });
          },
        ),
      );
    }

    for (final driver in idleDrivers) {
      final location = _latLngFromMap(driver['driver_location']);
      if (location == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('idle:${driver['driver_id']}'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
          infoWindow: InfoWindow(
            title: driver['driver_name'] as String? ?? 'Livreur',
            snippet: 'Hors course',
            onTap: () => _openDriverSheet(mission: driver, isIdle: true),
          ),
        ),
      );
    }

    final polylines = <Polyline>{};
    if (selectedMission != null) {
      final pickup = _latLngFromLocation(selectedMission['pickup']);
      final delivery = _latLngFromLocation(selectedMission['delivery']);
      final driver = _latLngFromMap(selectedMission['driver_location']);

      if (pickup != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('selected_pickup'),
            position: pickup,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: 'Départ',
              snippet: _locationLabel(selectedMission['pickup']),
            ),
          ),
        );
      }
      if (delivery != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('selected_delivery'),
            position: delivery,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(
              title: 'Arrivée',
              snippet: _locationLabel(selectedMission['delivery']),
            ),
          ),
        );
      }
      if (driver != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('selected_driver'),
            position: driver,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: InfoWindow(
              title:
                  selectedMission['driver_name'] as String? ?? 'Livreur actif',
              snippet:
                  (selectedMission['eta_text'] as String?) ?? 'Position live',
            ),
          ),
        );
      }

      final plannedPoints =
          _decodePolyline(selectedMission['encoded_polyline'] as String?);
      final trailPoints = _trailPoints(selectedMission);
      if (plannedPoints.length >= 2) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('planned_route'),
            points: plannedPoints,
            color: Colors.blue.shade500,
            width: 5,
          ),
        );
      }
      if (trailPoints.length >= 2) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('actual_route'),
            points: trailPoints,
            color: Colors.green.shade600,
            width: 6,
          ),
        );
      } else if (plannedPoints.length < 2 &&
          pickup != null &&
          delivery != null) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('fallback_route'),
            points: [pickup, delivery],
            color: Colors.orange.shade600,
            width: 4,
          ),
        );
      }
    }

    final seedPoints = _cameraSeedPoints(fleet, idleDrivers, selectedMission);
    final cameraTarget = seedPoints.isNotEmpty
        ? seedPoints.first
        : const LatLng(14.7167, -17.4677);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: cameraTarget, zoom: 12),
            onMapCreated: (controller) {
              _mapController = controller;
              _fitBoundsIfNeeded(seedPoints);
            },
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: true,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
          if (markers.isEmpty)
            Container(
              color: Colors.black.withValues(alpha: 0.05),
              alignment: Alignment.center,
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun point GPS exploitable pour cette mission.\nLa liste ci-dessous reste consultable.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: FloatingActionButton.small(
              heroTag: 'fleet_recenter',
              backgroundColor: Colors.white,
              onPressed: () {
                _lastCameraKey = null;
                _fitBoundsIfNeeded(seedPoints);
              },
              child: const Icon(Icons.center_focus_strong, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _resolveSelectedMission(
    List<Map<String, dynamic>> fleet,
  ) {
    if (fleet.isEmpty) {
      return null;
    }
    final selected = fleet.firstWhere(
      (mission) => mission['mission_id'] == _selectedMissionId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isNotEmpty) {
      return selected;
    }
    final withLocation = fleet.firstWhere(
      (mission) => mission['driver_location'] != null,
      orElse: () => fleet.first,
    );
    _selectedMissionId = withLocation['mission_id'] as String?;
    return withLocation;
  }

  List<LatLng> _cameraSeedPoints(
    List<Map<String, dynamic>> fleet,
    List<Map<String, dynamic>> idleDrivers,
    Map<String, dynamic>? selectedMission,
  ) {
    if (selectedMission != null) {
      final points = <LatLng>[
        ..._trailPoints(selectedMission),
        ..._decodePolyline(selectedMission['encoded_polyline'] as String?),
      ];
      final pickup = _latLngFromLocation(selectedMission['pickup']);
      final delivery = _latLngFromLocation(selectedMission['delivery']);
      final driver = _latLngFromMap(selectedMission['driver_location']);
      if (pickup != null) points.add(pickup);
      if (delivery != null) points.add(delivery);
      if (driver != null) points.add(driver);
      if (points.isNotEmpty) {
        return points;
      }
    }

    return [
      ...fleet.map((mission) => _latLngFromMap(mission['driver_location'])),
      ...idleDrivers.map((driver) => _latLngFromMap(driver['driver_location'])),
    ].whereType<LatLng>().toList();
  }

  Future<void> _fitBoundsIfNeeded(List<LatLng> points) async {
    if (_mapController == null || points.isEmpty) {
      return;
    }
    final key = points
        .map((point) =>
            '${point.latitude.toStringAsFixed(4)}:${point.longitude.toStringAsFixed(4)}')
        .join('|');
    if (_lastCameraKey == key) {
      return;
    }
    _lastCameraKey = key;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted || _mapController == null) {
      return;
    }
    final bounds = _boundsFromPoints(points);
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 64),
    );
  }

  void _openDriverSheet({
    required Map<String, dynamic> mission,
    required bool isIdle,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _DriverDetailsSheet(
          data: mission,
          isIdle: isIdle,
          onCenter: () {
            Navigator.of(sheetContext).pop();
            if (!isIdle) {
              setState(() {
                _selectedMissionId = mission['mission_id'] as String?;
                _lastCameraKey = null;
              });
            } else {
              final point = _latLngFromMap(mission['driver_location']);
              if (point != null) {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(point, 15),
                );
              }
            }
          },
          onOpenAudit: isIdle
              ? null
              : () {
                  final parcelId = mission['parcel_id'] as String?;
                  if (parcelId == null || parcelId.isEmpty) return;
                  Navigator.of(sheetContext).pop();
                  context.push('/admin/parcels/$parcelId/audit');
                },
        );
      },
    );
  }
}

class _FleetSummary extends StatelessWidget {
  const _FleetSummary({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Actives', '${summary['total_active'] ?? 0}', Colors.blue),
      ('Avec GPS', '${summary['with_live_location'] ?? 0}', Colors.green),
      ('Signal faible', '${summary['stale_locations'] ?? 0}', Colors.orange),
      ('Sans position', '${summary['missing_locations'] ?? 0}', Colors.red),
      ('Hors course', '${summary['idle_drivers'] ?? 0}', Colors.purple),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Container(
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: item.$3.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: item.$3.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$1,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.$3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.isSelected,
    required this.onSelect,
    required this.onAudit,
  });

  final Map<String, dynamic> mission;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onAudit;

  @override
  Widget build(BuildContext context) {
    final tracking = mission['tracking_code'] as String?;
    final routeSummary = Map<String, dynamic>.from(
      mission['route_summary'] as Map? ?? const {},
    );
    final durationSummary = Map<String, dynamic>.from(
      mission['duration_summary'] as Map? ?? const {},
    );
    final themeColor = isSelected ? Colors.blue : Colors.grey.shade300;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: themeColor, width: isSelected ? 1.5 : 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tracking == null || tracking.isEmpty
                        ? 'Mission ${mission['mission_id']}'
                        : tracking,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                _StatusChip(status: mission['status'] as String? ?? ''),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              mission['driver_name'] as String? ?? 'Livreur non identifié',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TinyInfoChip(
                  icon: Icons.route,
                  label: _locationLabel(mission['pickup']) ?? 'Départ inconnu',
                ),
                _TinyInfoChip(
                  icon: Icons.flag,
                  label:
                      _locationLabel(mission['delivery']) ?? 'Arrivée inconnue',
                ),
                if ((mission['eta_text'] as String?)?.isNotEmpty ?? false)
                  _TinyInfoChip(
                    icon: Icons.schedule,
                    label: mission['eta_text'] as String,
                  ),
                if ((mission['distance_text'] as String?)?.isNotEmpty ?? false)
                  _TinyInfoChip(
                    icon: Icons.straighten,
                    label: mission['distance_text'] as String,
                  ),
                if ((routeSummary['gps_points_count'] as int? ?? 0) > 0)
                  _TinyInfoChip(
                    icon: Icons.my_location,
                    label: '${routeSummary['gps_points_count']} points GPS',
                  ),
                if ((durationSummary['active_elapsed_seconds'] as int?) != null)
                  _TinyInfoChip(
                    icon: Icons.timer,
                    label: _formatDuration(
                      durationSummary['active_elapsed_seconds'] as int?,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fleetLocationLabel(mission),
                    style: TextStyle(
                      color: (mission['is_stale'] as bool? ?? false)
                          ? Colors.orange.shade700
                          : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onAudit,
                  icon: const Icon(Icons.visibility_outlined),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: _statusColor(status),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TinyInfoChip extends StatelessWidget {
  const _TinyInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black54),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

String _fleetLocationLabel(Map<String, dynamic> mission) {
  final isStale = mission['is_stale'] as bool? ?? false;
  final lastSeen = _formatDateTime(mission['location_updated_at']);
  if (mission['driver_location'] == null) {
    return 'Aucune position live disponible pour ce livreur.';
  }
  if (isStale) {
    return lastSeen == null
        ? 'Signal GPS ancien'
        : 'Dernier point connu: $lastSeen';
  }
  return lastSeen == null
      ? 'Position en direct'
      : 'Dernière mise à jour: $lastSeen';
}

String? _locationLabel(Object? location) {
  if (location is! Map) {
    return null;
  }
  final label = location['label'] as String?;
  if (label != null && label.isNotEmpty) {
    return label;
  }
  final relay = location['relay'];
  if (relay is Map) {
    return relay['label'] as String? ?? relay['name'] as String?;
  }
  return null;
}

LatLng? _latLngFromMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final lat = value['lat'];
  final lng = value['lng'];
  if (lat is! num || lng is! num) {
    return null;
  }
  return LatLng(lat.toDouble(), lng.toDouble());
}

LatLng? _latLngFromLocation(Object? location) {
  if (location is! Map) {
    return null;
  }
  return _latLngFromMap(location['geopin']);
}

List<LatLng> _trailPoints(Map<String, dynamic> mission) {
  return List<Map<String, dynamic>>.from(
    mission['gps_trail'] as List? ?? const [],
  ).map<LatLng?>((point) => _latLngFromMap(point)).whereType<LatLng>().toList();
}

List<LatLng> _decodePolyline(String? encodedPolyline) {
  if (encodedPolyline == null || encodedPolyline.isEmpty) {
    return const [];
  }
  return PolylinePoints()
      .decodePolyline(encodedPolyline)
      .map((point) => LatLng(point.latitude, point.longitude))
      .toList();
}

LatLngBounds _boundsFromPoints(List<LatLng> points) {
  if (points.length == 1) {
    final point = points.first;
    return LatLngBounds(
      southwest: LatLng(point.latitude - 0.01, point.longitude - 0.01),
      northeast: LatLng(point.latitude + 0.01, point.longitude + 0.01),
    );
  }
  double minLat = points.first.latitude;
  double maxLat = points.first.latitude;
  double minLng = points.first.longitude;
  double maxLng = points.first.longitude;
  for (final point in points.skip(1)) {
    minLat = point.latitude < minLat ? point.latitude : minLat;
    maxLat = point.latitude > maxLat ? point.latitude : maxLat;
    minLng = point.longitude < minLng ? point.longitude : minLng;
    maxLng = point.longitude > maxLng ? point.longitude : maxLng;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

double _statusHue(String status) {
  switch (status) {
    case 'in_progress':
      return BitmapDescriptor.hueGreen;
    case 'assigned':
      return BitmapDescriptor.hueOrange;
    case 'incident_reported':
      return BitmapDescriptor.hueRed;
    default:
      return BitmapDescriptor.hueAzure;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'in_progress':
      return Colors.green.shade700;
    case 'assigned':
      return Colors.orange.shade700;
    case 'incident_reported':
      return Colors.red.shade700;
    default:
      return Colors.blueGrey.shade700;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'in_progress':
      return 'En cours';
    case 'assigned':
      return 'Assignée';
    case 'incident_reported':
      return 'Incident';
    default:
      return status.isEmpty ? 'Inconnue' : status;
  }
}

String _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '0 min';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}';
  }
  return '$minutes min';
}

String? _formatDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) {
    return value.toString();
  }
  final local = parsed.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} à $hh:$mm';
}

class _DriverDetailsSheet extends StatelessWidget {
  const _DriverDetailsSheet({
    required this.data,
    required this.isIdle,
    required this.onCenter,
    this.onOpenAudit,
  });

  final Map<String, dynamic> data;
  final bool isIdle;
  final VoidCallback onCenter;
  final VoidCallback? onOpenAudit;

  @override
  Widget build(BuildContext context) {
    final name = data['driver_name'] as String? ?? 'Livreur';
    final phone = data['driver_phone'] as String?;
    final tracking = data['tracking_code'] as String?;
    final status = data['status'] as String? ?? '';
    final isStale = data['is_stale'] as bool? ?? false;
    final eta = data['eta_text'] as String?;
    final distance = data['distance_text'] as String?;
    final recipientName = data['recipient_name'] as String?;
    final recipientPhone = data['recipient_phone'] as String?;
    final updatedAt = _formatDateTime(data['location_updated_at']);
    final photoUrl = data['driver_photo_url'] as String?;

    final statusLabel = isIdle
        ? 'Hors course'
        : isStale
            ? 'Signal perdu'
            : _statusLabel(status);
    final statusColor = isIdle
        ? Colors.purple
        : isStale
            ? Colors.orange
            : _statusColor(status);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage:
                        (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (phone != null && phone.isNotEmpty)
                _SheetRow(
                  icon: Icons.phone,
                  label: phone,
                  trailing: TextButton.icon(
                    onPressed: () => _callNumber(phone),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Appeler'),
                  ),
                ),
              if (!isIdle && tracking != null && tracking.isNotEmpty)
                _SheetRow(icon: Icons.qr_code, label: 'Colis $tracking'),
              if (!isIdle && recipientName != null && recipientName.isNotEmpty)
                _SheetRow(
                  icon: Icons.person,
                  label: 'Destinataire : $recipientName',
                  trailing: (recipientPhone != null &&
                          recipientPhone.isNotEmpty)
                      ? IconButton(
                          onPressed: () => _callNumber(recipientPhone),
                          icon: const Icon(Icons.call, size: 18),
                          tooltip: 'Appeler le destinataire',
                        )
                      : null,
                ),
              if (!isIdle && (eta != null || distance != null))
                _SheetRow(
                  icon: Icons.schedule,
                  label: [
                    if (eta != null && eta.isNotEmpty) 'ETA $eta',
                    if (distance != null && distance.isNotEmpty) distance,
                  ].join(' • '),
                ),
              if (updatedAt != null)
                _SheetRow(
                  icon: Icons.update,
                  label: 'Dernière position : $updatedAt',
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCenter,
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('Centrer'),
                    ),
                  ),
                  if (onOpenAudit != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onOpenAudit,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Voir audit'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
