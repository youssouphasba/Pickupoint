import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/notifications/notification_navigation.dart';

void main() {
  group('notificationRouteFor', () {
    test('ouvre le colis relais depuis une alerte opérationnelle', () {
      expect(
        notificationRouteFor(
          refType: 'parcel',
          refId: 'prc_123',
          role: 'relay_agent',
          eventType: 'relay_finance',
        ),
        '/relay?parcel=prc_123',
      );
    });

    test('ouvre les documents du livreur depuis une alerte de conformité', () {
      expect(
        notificationRouteFor(
          refType: 'profile',
          refId: null,
          role: 'driver',
          eventType: 'driver_document',
        ),
        '/driver/profile?section=documents',
      );
    });

    test('requests a fresh availability check in the driver view', () {
      expect(
        notificationRouteFor(
          refType: 'mission',
          refId: 'msn_123',
          role: 'client',
          eventType: 'mission_available',
          targetView: 'driver',
        ),
        '/driver?available=true',
      );
    });

    test('availability reminders without a reference still trigger the check',
        () {
      expect(
        notificationRouteFor(
          refType: 'mission',
          refId: null,
          role: 'driver',
          eventType: 'mission_available',
        ),
        '/driver?available=true',
      );
    });

    test('legacy mission notifications also request a fresh check', () {
      expect(
        notificationRouteFor(
          refType: 'mission',
          refId: 'old mission',
          role: 'driver',
        ),
        '/driver?available=true',
      );
    });

    test('opens an assigned mission detail', () {
      expect(
        notificationRouteFor(
          refType: 'mission',
          refId: 'msn_123',
          role: 'driver',
          eventType: 'mission_detail',
          targetView: 'driver',
        ),
        '/driver/mission/msn_123',
      );
    });

    test('opens the parcel for a client and an admin', () {
      expect(
        notificationRouteFor(
          refType: 'parcel',
          refId: 'prc_123',
          role: 'client',
          eventType: 'parcel_detail',
          targetView: 'client',
        ),
        '/client/parcel/prc_123',
      );
      expect(
        notificationRouteFor(
          refType: 'parcel',
          refId: 'prc_123',
          role: 'admin',
          eventType: 'parcel_detail',
          targetView: 'admin',
        ),
        '/admin/parcels/prc_123/audit',
      );
    });

    test('opens the exact parcel message for clients and drivers', () {
      expect(
        notificationRouteFor(
          refType: 'parcel',
          refId: 'prc_123',
          role: 'client',
          eventType: 'parcel_message',
          targetView: 'client',
          messageId: 'msg_456',
        ),
        '/client/parcel/prc_123?message=msg_456',
      );
      expect(
        notificationRouteFor(
          refType: 'mission',
          refId: 'msn_123',
          role: 'driver',
          eventType: 'parcel_message',
          targetView: 'driver',
          messageId: 'msg_456',
        ),
        '/driver/mission/msn_123?message=msg_456',
      );
    });

    test('routes wallet notifications by professional role', () {
      expect(
        notificationRouteFor(
          refType: 'payout',
          refId: null,
          role: 'relay_agent',
          eventType: 'wallet',
          targetView: 'relay_agent',
        ),
        '/relay/wallet',
      );
    });
  });

  test('each tap on the same availability route is a separate request', () {
    final first = driverMissionNotificationRequestFor('/driver?preview=old');
    final second = driverMissionNotificationRequestFor('/driver?preview=old');
    expect(first, isA<DriverMissionNotificationRequest>());
    expect(identical(first, second), isFalse);
    expect(driverMissionNotificationRequestFor('/driver?available=true'),
        isA<DriverMissionNotificationRequest>());
    expect(driverMissionNotificationRequestFor('/driver?unavailable=old'),
        isA<DriverMissionNotificationRequest>());
    expect(driverMissionNotificationRequestFor('/driver'), isNull);
    expect(
        driverMissionNotificationRequestFor('/driver/mission/current'), isNull);
    expect(
        driverMissionNotificationRequestFor('/client/parcel/parcel'), isNull);
  });

  group('legacy notifications', () {
    test('old pending mission details go through the fresh available list',
        () async {
      expect(
          await resolveLegacyDriverMissionRoute(
              '/driver/mission/old', (_) async => {'status': 'pending'}),
          '/driver?available=true');
    });
    test('expired or inaccessible references go through the fresh list',
        () async {
      expect(
          await resolveLegacyDriverMissionRoute('/driver/mission/old',
              (_) async => throw Exception('Unavailable')),
          '/driver?available=true');
    });
    test('assigned and finished mission notifications retain their detail',
        () async {
      for (final status in [
        'assigned',
        'in_progress',
        'completed',
        'incident_reported'
      ]) {
        expect(
            await resolveLegacyDriverMissionRoute(
                '/driver/mission/current?message=message',
                (_) async => {'status': status}),
            '/driver/mission/current?message=message');
      }
    });
  });

  test('notificationPlatformId is stable for the same mission', () {
    final first = notificationPlatformId({
      'dedupe_key': 'mission_available:msn_123',
      'event_type': 'mission_available',
    });
    final second = notificationPlatformId({
      'dedupe_key': 'mission_available:msn_123',
      'event_type': 'mission_unavailable',
    });
    expect(first, second);
  });

  group('notificationExternalUrl', () {
    test('opens the matching store for an app update', () {
      expect(
        notificationExternalUrl(
          eventType: 'app_update',
          storeUrl:
              'https://play.google.com/store/apps/details?id=com.denkma.app',
          currentPlatform: 'android',
          targetPlatform: 'android',
        ),
        'https://play.google.com/store/apps/details?id=com.denkma.app',
      );
    });

    test('rejects another platform and unsafe links', () {
      expect(
        notificationExternalUrl(
          eventType: 'app_update',
          storeUrl: 'https://apps.apple.com/app/denkma/id123',
          currentPlatform: 'android',
          targetPlatform: 'ios',
        ),
        isNull,
      );
      expect(
        notificationExternalUrl(
          eventType: 'app_update',
          storeUrl: 'javascript:alert(1)',
          currentPlatform: 'android',
          targetPlatform: 'android',
        ),
        isNull,
      );
    });
  });
}
