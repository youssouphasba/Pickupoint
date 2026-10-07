import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriverMissionActivityIssue {
  const DriverMissionActivityIssue(this.message,
      {this.openSettings = false, this.canRetry = true});

  final String message;
  final bool openSettings;
  final bool canRetry;
}

final driverMissionActivityIssueProvider =
    StateProvider<DriverMissionActivityIssue?>((ref) => null);

class DriverMissionActivity {
  const DriverMissionActivity({
    required this.missionId,
    required this.trackingCode,
    required this.assignedAt,
    required this.startedAt,
    required this.pickupDeadline,
  });

  final String missionId;
  final String? trackingCode;
  final DateTime assignedAt;
  final DateTime? startedAt;
  final DateTime? pickupDeadline;

  String get phase => startedAt == null ? 'pickup' : 'delivery';
  DateTime? get deadline => startedAt == null ? pickupDeadline : null;

  String _date(DateTime value) => value.toUtc().toIso8601String();

  Map<String, Object?> get arguments => {
        'missionId': missionId,
        'trackingCode': trackingCode ?? '',
        'phase': phase,
        'assignedAt': _date(assignedAt),
        'deadline': deadline == null ? null : _date(deadline!),
      };

  String get signature =>
      '$missionId|${trackingCode ?? ''}|$phase|${_date(assignedAt)}|'
      '${deadline == null ? '' : _date(deadline!)}';

  Map<String, String> get notificationData => {
        'event_type': 'mission_detail',
        'ref_type': 'mission',
        'ref_id': missionId,
        'target_view': 'driver',
      };
}
