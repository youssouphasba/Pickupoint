import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/notifications/notification_navigation.dart';

void main() {
  group('notificationRouteFor', () {
    test('opens an available mission preview in the driver view', () {
      expect(
        notificationRouteFor(
          refType: 'mission',
          refId: 'msn_123',
          role: 'client',
          eventType: 'mission_available',
          targetView: 'driver',
        ),
        '/driver?preview=msn_123',
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
}
