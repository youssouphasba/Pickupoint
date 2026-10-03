import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/models/parcel.dart';
import 'package:pickupoint/shared/widgets/recipient_collection_card.dart';

void main() {
  test('redirection uses the actual relay and coordinates, not the old home',
      () {
    final parcel = Parcel.fromJson({
      'parcel_id': 'parcel',
      'delivery_mode': 'home_to_home',
      'redirect_relay_id': 'new-relay',
      'delivery_address': {
        'label': 'Ancien domicile',
        'geopin': {'lat': 14.72, 'lng': -17.46}
      },
      'delivery_destination': {
        'type': 'relay',
        'relay_id': 'new-relay',
        'address': {
          'label': 'Relais de retrait',
          'geopin': {'lat': 14.79, 'lng': -16.92}
        }
      }
    });
    expect(parcel.deliveryMode, 'home_to_relay');
    expect(parcel.destinationRelayId, 'new-relay');
    expect(parcel.destinationAddress, 'Relais de retrait');
    expect(parcel.destinationLat, 14.79);
    expect(parcel.destinationLng, -16.92);
    expect(parcel.deliveryLocation?['label'], 'Relais de retrait');
  });

  test('a later home GPS confirmation overrides an old destination snapshot',
      () {
    final parcel = Parcel.fromJson({
      'delivery_mode': 'relay_to_home',
      'delivery_destination': {
        'type': 'home',
        'address': {
          'label': 'Ancienne adresse',
          'geopin': {'lat': 14.72, 'lng': -17.46}
        }
      },
      'delivery_address': {
        'label': 'Adresse confirmée',
        'geopin': {'lat': 14.79, 'lng': -16.92}
      }
    });
    expect(parcel.destinationAddress, 'Adresse confirmée');
    expect(parcel.destinationLat, 14.79);
    expect(parcel.deliveryLocation?['label'], 'Adresse confirmée');
  });

  testWidgets('partial payment shows only the remaining amount and collector',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecipientCollectionCard(plan: {
          'status': 'collection_required',
          'collector': 'relay',
          'amount_received_xof': 500,
          'amount_due_xof': 1500,
        }),
      ),
    ));
    expect(find.textContaining('Reste à régler'), findsOneWidget);
    expect(find.textContaining('au relais de retrait'), findsOneWidget);
    expect(find.textContaining('avant la remise'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed payment never asks the recipient to pay again',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecipientCollectionCard(
          isPaid: true,
          plan: {'status': 'admin_review', 'amount_due_xof': 2000},
        ),
      ),
    ));
    expect(find.textContaining('Aucun nouvel encaissement'), findsOneWidget);
    expect(find.textContaining('Reste à régler'), findsNothing);
  });

  testWidgets('unknown collector directs the recipient to admin review',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecipientCollectionCard(
          plan: {'status': 'admin_review', 'amount_due_xof': 2000},
        ),
      ),
    ));
    expect(find.textContaining('Denkma doit préciser'), findsOneWidget);
    expect(find.textContaining('au livreur affecté'), findsNothing);
  });
}
