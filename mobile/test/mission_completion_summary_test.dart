import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';

void main() {
  test('completed mission parses its operational recap', () {
    final mission = DeliveryMission.fromJson({
      'mission_id': 'msn_test',
      'parcel_id': 'prc_test',
      'status': 'completed',
      'created_at': '2026-09-29T10:00:00Z',
      'completed_at': '2026-09-29T10:40:00Z',
      'earn_amount': 2200,
      'completion_summary': {
        'assigned_to_pickup_seconds': 720,
        'pickup_to_delivery_seconds': 1680,
        'total_duration_seconds': 2400,
        'recorded_distance_meters': 8350,
        'gps_points_count': 48,
        'completed_at': '2026-09-29T10:40:00Z',
      },
    });

    expect(mission.isCompleted, isTrue);
    expect(mission.completionSummary?.totalDurationSeconds, 2400);
    expect(mission.completionSummary?.recordedDistanceMeters, 8350);
    expect(mission.completionSummary?.gpsPointsCount, 48);
  });
}
