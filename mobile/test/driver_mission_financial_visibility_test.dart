import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/models/delivery_mission.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';
import 'package:pickupoint/features/driver/screens/mission_detail_screen.dart';
import 'package:pickupoint/shared/utils/currency_format.dart';
import 'package:pickupoint/shared/widgets/parcel_chat_widget.dart';
import 'package:pickupoint/shared/widgets/recipient_collection_card.dart';

class DisabledMissionGps extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
}

class MissionFinancialAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.authenticated, activeView: 'driver');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalGps = GeolocatorPlatform.instance;
  setUp(() => GeolocatorPlatform.instance = DisabledMissionGps());
  tearDown(() => GeolocatorPlatform.instance = originalGps);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final status in [
      'pending',
      'assigned',
      'in_progress',
      'completed',
      'failed'
    ]) {
      testWidgets('mission $status on $platform only shows driver gain',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final container = ProviderContainer(overrides: [
          authProvider.overrideWith(MissionFinancialAuth.new),
          parcelMessagesProvider.overrideWith((ref, id) async => []),
          missionProvider
              .overrideWith((ref, id) async => DeliveryMission.fromJson({
                    'mission_id': id,
                    'parcel_id': 'parcel',
                    'status': status,
                    'created_at': '2026-10-07T10:00:00Z',
                    'pickup_type': 'gps',
                    'delivery_type': 'relay',
                    'quoted_price': 2300,
                    'paid_price': 2300,
                    'earn_amount': 1650,
                    'recipient_collection_plan': {
                      'collector': 'relay',
                      'status': 'collection_required',
                      'amount_due_xof': 2300,
                    },
                    'financial_rounding': {
                      'rounding': {
                        'version': 'customer_down_driver_up_v1',
                        'driver_bonus_xof': 14.1,
                      },
                    },
                  })),
        ]);
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MissionDetailScreen(id: 'mission')),
        ));
        await tester.pumpAndSettle();
        expect(find.text('PRIX DE LA COURSE'), findsNothing);
        expect(find.text(formatXof(2300)), findsNothing);
        expect(find.textContaining(formatXof(2300)), findsNothing);
        expect(find.text(formatXof(1650)), findsOneWidget);
        expect(find.textContaining('offerts par Denkma'), findsOneWidget);
        expect(find.textContaining('Règlement en attente'), findsOneWidget);
        expect(find.textContaining('Reste à régler'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, variant: TargetPlatformVariant.only(platform));
    }
  }

  for (final collector in ['driver', 'relay', 'denkma', null]) {
    testWidgets('driver payment status hides amounts for collector $collector',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RecipientCollectionCard(
            showAmount: false,
            plan: {
              'status':
                  collector == null ? 'admin_review' : 'collection_required',
              'collector': collector,
              'amount_due_xof': 2300,
              'amount_received_xof': 500,
            },
          ),
        ),
      ));
      expect(find.textContaining('FCFA'), findsNothing);
      expect(find.textContaining('Règlement en attente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('driver confirmed payment never requests a second collection',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecipientCollectionCard(
          showAmount: false,
          isPaid: true,
          plan: {'collector': 'driver', 'amount_due_xof': 2300},
        ),
      ),
    ));
    expect(find.textContaining('Aucun nouvel encaissement'), findsOneWidget);
    expect(find.textContaining('FCFA'), findsNothing);
    expect(find.textContaining('Règlement en attente'), findsNothing);
  });
}
