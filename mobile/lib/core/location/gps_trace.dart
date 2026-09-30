import 'package:google_maps_flutter/google_maps_flutter.dart';

List<List<LatLng>> recordedTraceSegments(Map<String, dynamic> data) {
  final raw = (data['trace_summary'] as Map?)?['segments'] as List? ?? const [];
  return raw
      .whereType<List>()
      .map((segment) => segment
          .whereType<Map>()
          .where((point) =>
              point['lat'] is num &&
              point['lng'] is num &&
              (point['lat'] as num).isFinite &&
              (point['lng'] as num).isFinite &&
              (point['lat'] as num).abs() <= 90 &&
              (point['lng'] as num).abs() <= 180)
          .map((point) => LatLng((point['lat'] as num).toDouble(),
              (point['lng'] as num).toDouble()))
          .toList())
      .toList();
}
