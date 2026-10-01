import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationAlertKind {
  mission,
  message,
  status,
  other,
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

  String androidChannelId({bool vibrationEnabled = true}) =>
      vibrationEnabled ? channelId : '${channelId}_no_vibration';

  String _androidChannelName(bool vibrationEnabled) =>
      vibrationEnabled ? channelName : '$channelName · sans vibration';

  AndroidNotificationChannel toAndroidChannel({bool vibrationEnabled = true}) {
    return AndroidNotificationChannel(
      androidChannelId(vibrationEnabled: vibrationEnabled),
      _androidChannelName(vibrationEnabled),
      description: channelDescription,
      importance: importance,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundResource),
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationEnabled ? androidVibrationPattern : null,
      showBadge: true,
    );
  }

  AndroidNotificationDetails toAndroidDetails({bool vibrationEnabled = true}) {
    return AndroidNotificationDetails(
      androidChannelId(vibrationEnabled: vibrationEnabled),
      _androidChannelName(vibrationEnabled),
      channelDescription: channelDescription,
      importance: importance,
      priority: priority,
      icon: 'ic_notification_logo',
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundResource),
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationEnabled ? androidVibrationPattern : null,
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
  channelName: 'Courses disponibles',
  channelDescription: 'Nouvelles courses proposées au livreur',
  soundResource: 'denkma_mission',
  iosSound: 'denkma_mission.wav',
  importance: Importance.max,
  priority: Priority.max,
  vibrationPattern: [0, 700, 180, 700, 180, 1100],
  interruptionLevel: InterruptionLevel.timeSensitive,
);

const messageAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.message,
  channelId: 'denkma_messages_v4',
  channelName: 'Messages',
  channelDescription: 'Nouveaux messages reçus dans Denkma',
  soundResource: 'denkma_message',
  iosSound: 'denkma_message.wav',
  importance: Importance.high,
  priority: Priority.high,
  vibrationPattern: [0, 150],
  interruptionLevel: InterruptionLevel.active,
);

const statusAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.status,
  channelId: 'denkma_updates_v3',
  channelName: 'Suivi des colis',
  channelDescription:
      'Étapes de livraison pour les expéditeurs et destinataires',
  soundResource: 'denkma_status',
  iosSound: 'denkma_status.wav',
  importance: Importance.high,
  priority: Priority.high,
  vibrationPattern: [0, 450, 160, 600],
  interruptionLevel: InterruptionLevel.active,
);

const missionUpdateAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.mission,
  channelId: 'denkma_mission_updates_v1',
  channelName: 'Mission en cours',
  channelDescription: 'Informations et rappels sur les missions du livreur',
  soundResource: 'denkma_mission',
  iosSound: 'denkma_mission.wav',
  importance: Importance.max,
  priority: Priority.max,
  vibrationPattern: [0, 150],
  interruptionLevel: InterruptionLevel.timeSensitive,
);

const otherAlertProfile = NotificationAlertProfile(
  kind: NotificationAlertKind.other,
  channelId: 'denkma_other_alerts_v1',
  channelName: 'Autres notifications',
  channelDescription: 'Informations de compte, offres et alertes du relais',
  soundResource: 'denkma_status',
  iosSound: 'denkma_status.wav',
  importance: Importance.high,
  priority: Priority.high,
  vibrationPattern: [0, 150],
  interruptionLevel: InterruptionLevel.active,
);

const notificationAlertProfiles = [
  missionAlertProfile,
  messageAlertProfile,
  statusAlertProfile,
  missionUpdateAlertProfile,
  otherAlertProfile,
];

NotificationAlertProfile notificationAlertProfileFor({
  String? eventType,
  String? refType,
  String? category,
  String? targetView,
  String? parcelStatus,
  String? alertKind,
}) {
  final normalizedEvent = eventType?.trim().toLowerCase();
  final normalizedRef = refType?.trim().toLowerCase();
  final normalizedCategory = category?.trim().toLowerCase();
  final normalizedView = targetView?.trim().toLowerCase();

  if (normalizedCategory == 'messages' || normalizedEvent == 'parcel_message') {
    return messageAlertProfile;
  }
  if (normalizedEvent == 'mission_available' &&
      (normalizedView == null ||
          normalizedView.isEmpty ||
          normalizedView == 'driver')) {
    return missionAlertProfile;
  }
  if (normalizedRef == 'mission' ||
      normalizedEvent == 'mission_detail' ||
      normalizedEvent == 'mission_unavailable') {
    return missionUpdateAlertProfile;
  }
  if (normalizedView == 'client' &&
      ((normalizedEvent == 'parcel_detail' &&
              (parcelStatus?.trim().isNotEmpty ?? false)) ||
          alertKind == 'delivery_step')) {
    return statusAlertProfile;
  }
  return otherAlertProfile;
}
