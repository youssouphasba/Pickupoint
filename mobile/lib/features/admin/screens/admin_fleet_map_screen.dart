import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/admin_provider.dart';

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
          final summary = Map<String, dynamic>.from(
            payload['summary'] as Map? ?? const {},
          );
          final selectedMission = _resolveSelectedMission(fleet);
          final visiblePoints = _cameraSeedPoints(fleet, selectedMission);
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
                child: fleet.isEmpty
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
                              child: _buildMap(fleet, selectedMission),
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
        error: (e, __) => Center(child: Text('Erreur: $e')),
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
    Map<String, dynamic>? selectedMission,
  ) {
    final markers = <Marker>{};
    for (final mission in fleet) {
      final location = _latLngFromMap(mission['driver_location']);
      if (location == null) continue;
      final status = mission['status'] as String? ?? '';
      markers.add(
        Marker(
          markerId: MarkerId(mission['mission_id'] as String),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _statusHue(status),
          ),
          infoWindow: InfoWindow(
            title: mission['driver_name'] as String? ?? 'Livreur',
            snippet: [
              if ((mission['tracking_code'] as String?)?.isNotEmpty ?? false)
                mission['tracking_code'] as String,
              status,
            ].where((value) => value.isNotEmpty).join(' • '),
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

    final cameraTarget = _cameraSeedPoints(fleet, selectedMission).isNotEmpty
        ? _cameraSeedPoints(fleet, selectedMission).first
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
              _fitBoundsIfNeeded(_cameraSeedPoints(fleet, selectedMission));
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
                _fitBoundsIfNeeded(_cameraSeedPoints(fleet, selectedMission));
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

    return fleet
        .map((mission) => _latLngFromMap(mission['driver_location']))
        .whereType<LatLng>()
        .toList();
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
