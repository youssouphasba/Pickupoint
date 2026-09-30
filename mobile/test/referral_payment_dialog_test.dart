import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/features/admin/widgets/referral_payment_dialog.dart';

class FakeReferralApi extends ApiClient {
  final payments = <Map<String, dynamic>>[];
  Completer<Response>? pending;
  bool fail = false;

  @override
  Future<Response> confirmReferralPayment(
    String referralId, {
    required String beneficiary,
    required int amountXof,
    required DateTime paidAt,
    String reference = '',
    String note = '',
  }) async {
    payments.add({
      'referral_id': referralId,
      'beneficiary': beneficiary,
      'amount_xof': amountXof,
      'paid_at': paidAt,
      'reference': reference,
      'note': note
    });
    if (fail) throw Exception('offline');
    if (pending != null) return await pending!.future;
    return Response(
        data: {'message': 'OK'}, requestOptions: RequestOptions(path: 'test'));
  }
}

void main() {
  final record = <String, dynamic>{
    'referral_id': 'ref_1',
    'sponsor_name': 'Parrain',
    'referred_name': 'Filleul',
    'created_at': '2026-09-01T00:00:00Z',
    'payments': {
      'sponsor': {'amount_xof': 750, 'status': 'pending'},
      'referred': {'amount_xof': 450, 'status': 'pending'},
    },
  };

  Future<void> show(
      WidgetTester tester, FakeReferralApi api, String beneficiary) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => ReferralPaymentDialog(
                            record: record, beneficiary: beneficiary)),
                    child: const Text('Paiement'),
                  )))),
    ));
    await tester.tap(find.text('Paiement'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'confirmation explicite avec bénéficiaire montant date et référence',
      (tester) async {
    final api = FakeReferralApi();
    await show(tester, api, 'referred');
    expect(find.textContaining('450'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmer'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField).first, 'REF-PAYEE');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(api.payments, hasLength(1));
    expect(api.payments.single['beneficiary'], 'referred');
    expect(api.payments.single['amount_xof'], 450);
    expect(api.payments.single['reference'], 'REF-PAYEE');
    expect(api.payments.single['paid_at'], isA<DateTime>());
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('envoi en cours bloque une deuxième confirmation et la fermeture',
      (tester) async {
    final api = FakeReferralApi()..pending = Completer<Response>();
    await show(tester, api, 'sponsor');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Confirmer'));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmation…'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Annuler'))
            .onPressed,
        isNull);
    expect(api.payments, hasLength(1));
    api.pending!.complete(
        Response(data: {}, requestOptions: RequestOptions(path: 'test')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('erreur garde le formulaire et permet de réessayer',
      (tester) async {
    final api = FakeReferralApi()..fail = true;
    await show(tester, api, 'sponsor');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmer'))
            .onPressed,
        isNotNull);
    api.fail = false;
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('formulaire utilisable sur écran étroit avec grandes polices',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester, FakeReferralApi(), 'sponsor');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
