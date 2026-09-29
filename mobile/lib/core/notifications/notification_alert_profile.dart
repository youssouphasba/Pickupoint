import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationAlertKind {
  mission,
  message,
  status,
}

class NotificationAlertProfile {
  const NotificationAlertProfile({
    required this.kind,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    required this.soundResource,
    required this.iosSound,
    required this.importance,
    required this.priority,
    required this.vibrationPattern,
    required this.interruptionLevel,
  });

  final NotificationAlertKind kind;
  final String channelId;
  final String channelName;
  final String channelDescription;
  final String soundResource;
  final String iosSound;
  final Importance importance;
  final Priority priority;
  final List<int> vibrationPattern;
  final InterruptionLevel interruptionLevel;

  Int64List get androidVibrationPattern => Int64List.fromList(vibrationPattern);

  AndroidNotificationChannel toAndroidChannel() {
    return AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: importance,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundResource),
      enableVibration: true,
      vibrationPattern: androidVibrationPattern,
      showBadge: true,
    );
  }

  AndroidNotificationDetails toAndroidDetails() {
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      icon: 'ic_notification_logo',
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundResource),
      enableVibration: true,
      vibrationPattern: androidVibrationPattern,
      category: kind == NotificationAlertKind.mission
          ? AndroidNotificationCategory.event
          : AndroidNotificationCategory.message,
    );
  }

  DarwinNotificationDetails toDarwinDetails() {
    return DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: iosSound,
      interruptionLevel: interruptionLevel,
    );
  }
}

const missionAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.mission,
  channelId: 'denkma_missions_v3',
  channelName: 'Courses et missions',
  channelDescription: 'Nouvelles courses et actions urgentes sur une mission',
  soundResource: 'denkma_mission',
  iosSound: 'denkma_mission.wav',
  importance: Importance.max,
  priority: Priority.max,
  vibrationPattern: [0, 700, 180, 700, 180, 1100],
  interruptionLevel: InterruptionLevel.timeSensitive,
);

const messageAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.message,
  channelId: 'denkma_messages_v3',
  channelName: 'Messages',
  channelDescription: 'Nouveaux messages reçus dans Denkma',
  soundResource: 'denkma_message',
  iosSound: 'denkma_message.wav',
  importance: Importance.high,
  priority: Priority.high,
  vibrationPattern: [0, 500, 160, 700],
  interruptionLevel: InterruptionLevel.active,
);

const statusAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.status,
  channelId: 'denkma_updates_v3',
  channelName: 'Suivi des colis',
  channelDescription: 'Étapes de livraison et informations de compte',
  soundResource: 'denkma_status',
  iosSound: 'denkma_status.wav',
  importance: Importance.high,
  priority: Priority.high,
  vibrationPattern: [0, 450, 160, 600],
  interruptionLevel: InterruptionLevel.active,
);

const notificationAlertProfiles = [
  missionAlertProfile,
  messageAlertProfile,
  statusAlertProfile,
];

NotificationAlertProfile notificationAlertProfileFor({
  String? eventType,
  String? refType,
  String? category,
}) {
  final normalizedEvent = eventType?.trim().toLowerCase();
  final normalizedRef = refType?.trim().toLowerCase();
  final normalizedCategory = category?.trim().toLowerCase();

  if (normalizedCategory == 'messages' || normalizedEvent == 'parcel_message') {
    return messageAlertProfile;
  }
  if (normalizedRef == 'mission' ||
      normalizedEvent == 'mission_available' ||
      normalizedEvent == 'mission_detail' ||
      normalizedEvent == 'mission_unavailable') {
    return missionAlertProfile;
  }
  return statusAlertProfile;
}
