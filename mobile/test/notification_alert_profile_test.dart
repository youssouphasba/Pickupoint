import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/notifications/notification_alert_profile.dart';
import 'package:pickupoint/core/models/user.dart';

void main() {
  test('Android preference defaults to enabled and survives serialization', () {
    expect(NotificationPrefs.fromJson({}).androidVibrationEnabled, isTrue);
    final preferences =
        NotificationPrefs.fromJson({'android_vibration': false});
    expect(preferences.toJson()['android_vibration'], isFalse);
    expect(preferences.pushEnabled, isTrue);
  });

  for (final profile in notificationAlertProfiles) {
    test(
        '${profile.kind.name} no-vibration variant keeps sounds and importance',
        () {
      final channel = profile.toAndroidChannel(vibrationEnabled: false);
      final details = profile.toAndroidDetails(vibrationEnabled: false);
      expect(channel.id, '${profile.channelId}_no_vibration');
      expect(details.channelId, channel.id);
      expect(channel.enableVibration, isFalse);
      expect(details.enableVibration, isFalse);
      expect(channel.vibrationPattern, isNull);
      expect(details.vibrationPattern, isNull);
      expect(channel.playSound, isTrue);
      expect(details.playSound, isTrue);
      expect(channel.sound, isA<RawResourceAndroidNotificationSound>());
      expect((channel.sound as RawResourceAndroidNotificationSound).sound,
          profile.soundResource);
      expect(channel.importance, profile.importance);
      expect(details.priority, profile.priority);
      expect(profile.toAndroidChannel().id, profile.channelId);
      expect(profile.toAndroidChannel().enableVibration, isTrue);
    });
  }
  test('message profile takes priority for a driver conversation', () {
    final profile = notificationAlertProfileFor(
      eventType: 'parcel_message',
      refType: 'mission',
      category: 'messages',
    );

    expect(profile.kind, NotificationAlertKind.message);
    expect(profile.channelId, 'denkma_messages_v4');
    expect(profile.vibrationPattern, [0, 150]);
  });

  test('available mission uses the urgent mission profile', () {
    final profile = notificationAlertProfileFor(
      eventType: 'mission_available',
      refType: 'mission',
      category: 'parcel_updates',
    );

    expect(profile.kind, NotificationAlertKind.mission);
    expect(profile.importance, Importance.max);
    expect(profile.priority, Priority.max);
    expect(profile.vibrationPattern, [0, 700, 180, 700, 180, 1100]);
    expect(profile.iosSound, 'denkma_mission.wav');
  });

  test('parcel updates use the status profile', () {
    final profile = notificationAlertProfileFor(
      eventType: 'parcel_detail',
      refType: 'parcel',
      category: 'parcel_updates',
      targetView: 'client',
      parcelStatus: 'delivered',
    );

    expect(profile.kind, NotificationAlertKind.status);
    expect(profile.channelId, 'denkma_updates_v3');
    expect(profile.importance, Importance.high);
    expect(profile.vibrationPattern, [0, 450, 160, 600]);
  });

  test('long vibration is limited to driver offers and client delivery steps',
      () {
    for (final event in ['mission_detail', 'mission_unavailable']) {
      expect(
          notificationAlertProfileFor(
              eventType: event, refType: 'mission', targetView: 'driver'),
          missionUpdateAlertProfile);
    }
    for (final view in ['driver', 'relay_agent', 'admin']) {
      expect(
          notificationAlertProfileFor(
              eventType: 'parcel_detail',
              refType: 'parcel',
              targetView: view,
              parcelStatus: 'delivered'),
          otherAlertProfile);
    }
    expect(
        notificationAlertProfileFor(eventType: 'wallet', targetView: 'driver'),
        otherAlertProfile);
    expect(
        notificationAlertProfileFor(
            eventType: 'parcel_detail',
            refType: 'parcel',
            targetView: 'client'),
        otherAlertProfile);
    expect(
        notificationAlertProfileFor(
            eventType: 'parcel_detail',
            refType: 'parcel',
            targetView: 'client',
            alertKind: 'delivery_step'),
        statusAlertProfile);
    expect(
        notificationAlertProfileFor(
            eventType: 'parcel_message',
            refType: 'parcel',
            targetView: 'client',
            parcelStatus: 'delivered'),
        messageAlertProfile);
  });
}
