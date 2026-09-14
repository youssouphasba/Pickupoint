import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/notifications/notification_alert_profile.dart';

void main() {
  test('message profile takes priority for a driver conversation', () {
    final profile = notificationAlertProfileFor(
      eventType: 'parcel_message',
      refType: 'mission',
      category: 'messages',
    );

    expect(profile.kind, NotificationAlertKind.message);
    expect(profile.channelId, 'denkma_messages_v2');
    expect(profile.vibrationPattern, [0, 70]);
  });

  test('available mission uses the urgent mission profile', () {
    final profile = notificationAlertProfileFor(
      eventType: 'mission_available',
      refType: 'mission',
      category: 'parcel_updates',
    );

    expect(profile.kind, NotificationAlertKind.mission);
    expect(profile.importance, Importance.max);
    expect(profile.iosSound, 'denkma_mission.wav');
  });

  test('parcel updates use the status profile', () {
    final profile = notificationAlertProfileFor(
      eventType: 'parcel_detail',
      refType: 'parcel',
      category: 'parcel_updates',
    );

    expect(profile.kind, NotificationAlertKind.status);
    expect(profile.channelId, 'denkma_updates_v2');
  });
}
