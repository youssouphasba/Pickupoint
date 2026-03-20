import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/admin_provider.dart';

class AdminHeatmapScreen extends ConsumerStatefulWidget {
  const AdminHeatmapScreen({super.key});

  @override
  ConsumerState<AdminHeatmapScreen> createState() => _AdminHeatmapScreenState();
}

class _AdminHeatmapScreenState extends ConsumerState<AdminHeatmapScreen> {
  GoogleMapController? _mapController;
  String _selectedFilter = 'all';
  String? _lastCameraKey;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heatmapAsync = ref.watch(adminHeatmapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte des demandes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminHeatmapProvider),
          ),
        ],
      ),
      body: heatmapAsync.when(
        data: (payload) {
          final points = List<Map<String, dynamic>>.from(
            payload['points'] as List? ?? const [],
          );
          final summary = Map<String, dynamic>.from(
            payload['summary'] as Map? ?? const {},
          );
          final rawHotspots = List<Map<String, dynamic>>.from(
            payload['top_hotspots'] as List? ?? const [],
          );
          final hotspots = rawHotspots.isNotEmpty
              ? rawHotspots
              : _buildLegacyHotspots(points);
          final filteredHotspots = _filterHotspots(hotspots, _selectedFilter);
          final hotspotPoints = filteredHotspots
              .map((hotspot) => _latLngFromHotspot(hotspot))
              .whereType<LatLng>()
              .toList();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _fitBoundsIfNeeded(hotspotPoints);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _HeatmapSummary(summary: summary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildFilters(),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: points.isEmpty
                    ? _buildEmptyState()
                    : Column(
                        children: [
                          SizedBox(
                            height: 300,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildMap(filteredHotspots),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: filteredHotspots.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Aucun point ne correspond à ce filtre.',
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    itemCount: filteredHotspots.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final hotspot = filteredHotspots[index];
                                      return _HotspotCard(hotspot: hotspot);
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

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 44, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Aucune demande géolocalisée récente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'La heatmap se nourrit des points de collecte domicile, livraison domicile et relais utilisés sur les 30 derniers jours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    const filters = [
      ('all', 'Tout'),
      ('home', 'Domicile'),
      ('relay', 'Relais'),
      ('redirect', 'Redirections'),
      ('transit', 'Transit'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.$2),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedFilter = filter.$1;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> hotspots) {
    final circles = <Circle>{};
    final markers = <Marker>{};
    for (final hotspot in hotspots) {
      final center = _latLngFromHotspot(hotspot);
      if (center == null) {
        continue;
      }
      final count = hotspot['count'] as int? ?? 1;
      final pointType = hotspot['point_type'] as String? ?? 'relay_points';
      final color = _pointTypeColor(pointType);
      circles.add(
        Circle(
          circleId: CircleId(
            '${center.latitude}_${center.longitude}_$pointType',
          ),
          center: center,
          radius: (120 + (count * 45)).clamp(120, 900).toDouble(),
          fillColor: color.withValues(alpha: 0.22),
          strokeColor: color.withValues(alpha: 0.32),
          strokeWidth: 1,
        ),
      );
      markers.add(
        Marker(
          markerId: MarkerId(
            '${center.latitude}_${center.longitude}_${pointType}_marker',
          ),
          position: center,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _pointTypeHue(pointType),
          ),
          infoWindow: InfoWindow(
            title: hotspot['label'] as String? ?? 'Zone de demande',
            snippet: '$count demandes • ${_pointTypeLabel(pointType)}',
          ),
        ),
      );
    }

    final cameraTarget = hotspots.isNotEmpty
        ? _latLngFromHotspot(hotspots.first) ?? const LatLng(14.7167, -17.4677)
        : const LatLng(14.7167, -17.4677);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: cameraTarget, zoom: 12),
        onMapCreated: (controller) {
          _mapController = controller;
          final points = hotspots
              .map((hotspot) => _latLngFromHotspot(hotspot))
              .whereType<LatLng>()
              .toList();
          _fitBoundsIfNeeded(points);
        },
        circles: circles,
        markers: markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }

  List<Map<String, dynamic>> _filterHotspots(
    List<Map<String, dynamic>> hotspots,
    String filter,
  ) {
    if (filter == 'all') {
      return hotspots;
    }
    return hotspots.where((hotspot) {
      final type = hotspot['point_type'] as String? ?? '';
      switch (filter) {
        case 'home':
          return type == 'home_pickups' || type == 'home_deliveries';
        case 'relay':
          return type == 'relay_points';
        case 'redirect':
          return type == 'redirect_points';
        case 'transit':
          return type == 'transit_points';
        default:
          return true;
      }
    }).toList();
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
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _mapController == null) {
      return;
    }
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(_boundsFromPoints(points), 64),
    );
  }
}

List<Map<String, dynamic>> _buildLegacyHotspots(
  List<Map<String, dynamic>> points,
) {
  final grouped = <String, Map<String, dynamic>>{};
  for (final point in points) {
    final lat = point['lat'];
    final lng = point['lng'];
    if (lat is! num || lng is! num) {
      continue;
    }
    final key =
        '${lat.toDouble().toStringAsFixed(3)}:${lng.toDouble().toStringAsFixed(3)}';
    final hotspot = grouped.putIfAbsent(
      key,
      () => {
        'lat': lat.toDouble(),
        'lng': lng.toDouble(),
        'label': point['label'] as String? ?? 'Zone de demande',
        'point_type': point['point_type'] as String? ?? 'relay_points',
        'count': 0,
      },
    );
    hotspot['count'] = (hotspot['count'] as int? ?? 0) + 1;
  }
  final hotspots = grouped.values.toList();
  hotspots.sort(
    (left, right) =>
        (right['count'] as int? ?? 0).compareTo(left['count'] as int? ?? 0),
  );
  return hotspots;
}

class _HeatmapSummary extends StatelessWidget {
  const _HeatmapSummary({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Colis', '${summary['parcels_considered'] ?? 0}', Colors.blue),
      ('Points', '${summary['total_points'] ?? 0}', Colors.deepPurple),
      ('Domicile', _homeCount(summary).toString(), Colors.green),
      ('Relais', '${summary['relay_points'] ?? 0}', Colors.orange),
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

class _HotspotCard extends StatelessWidget {
  const _HotspotCard({required this.hotspot});

  final Map<String, dynamic> hotspot;

  @override
  Widget build(BuildContext context) {
    final pointType = hotspot['point_type'] as String? ?? '';
    final color = _pointTypeColor(pointType);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.place, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hotspot['label'] as String? ?? 'Zone de demande',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${hotspot['count'] ?? 0} demandes • ${_pointTypeLabel(pointType)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

LatLng? _latLngFromHotspot(Map<String, dynamic> hotspot) {
  final lat = hotspot['lat'];
  final lng = hotspot['lng'];
  if (lat is! num || lng is! num) {
    return null;
  }
  return LatLng(lat.toDouble(), lng.toDouble());
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

int _homeCount(Map<String, dynamic> summary) {
  return (summary['home_pickups'] as int? ?? 0) +
      (summary['home_deliveries'] as int? ?? 0);
}

Color _pointTypeColor(String pointType) {
  switch (pointType) {
    case 'home_pickups':
      return Colors.green.shade700;
    case 'home_deliveries':
      return Colors.blue.shade700;
    case 'redirect_points':
      return Colors.red.shade700;
    case 'transit_points':
      return Colors.deepPurple.shade700;
    case 'relay_points':
    default:
      return Colors.orange.shade700;
  }
}

double _pointTypeHue(String pointType) {
  switch (pointType) {
    case 'home_pickups':
      return BitmapDescriptor.hueGreen;
    case 'home_deliveries':
      return BitmapDescriptor.hueAzure;
    case 'redirect_points':
      return BitmapDescriptor.hueRed;
    case 'transit_points':
      return BitmapDescriptor.hueViolet;
    case 'relay_points':
    default:
      return BitmapDescriptor.hueOrange;
  }
}

String _pointTypeLabel(String pointType) {
  switch (pointType) {
    case 'home_pickups':
      return 'Collectes domicile';
    case 'home_deliveries':
      return 'Livraisons domicile';
    case 'redirect_points':
      return 'Redirections';
    case 'transit_points':
      return 'Transit';
    case 'relay_points':
    default:
      return 'Relais';
  }
}
