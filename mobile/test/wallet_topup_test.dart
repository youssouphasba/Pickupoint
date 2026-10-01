import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pickupoint/core/api/api_client.dart';
import 'package:pickupoint/core/auth/auth_provider.dart';
import 'package:pickupoint/core/models/user.dart';
import 'package:pickupoint/core/models/wallet.dart';
import 'package:pickupoint/core/router/wallet_return_navigation.dart';
import 'package:pickupoint/core/router/app_router.dart';
import 'package:pickupoint/features/driver/providers/driver_provider.dart';
import 'package:pickupoint/features/driver/screens/driver_wallet_screen.dart';
import 'package:pickupoint/features/driver/widgets/wallet_topup_dialog.dart';
import 'package:pickupoint/shared/utils/error_utils.dart';
import 'package:pickupoint/shared/utils/currency_format.dart';

class WalletAuth extends AuthNotifier {
  WalletAuth({this.activeView});
  final String? activeView;
  @override
  Future<AuthState> build() async => AuthState(
        status: AuthStatus.authenticated,
        user: const User(id: 'driver', phone: '+221700000000', role: 'driver'),
        activeView: activeView,
      );
}

class LoadingWalletAuth extends WalletAuth {
  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.unknown);

  void authenticate() => state = const AsyncData(AuthState(
        status: AuthStatus.authenticated,
        user: User(id: 'driver', phone: '+221700000000', role: 'driver'),
      ));
}

class WalletApi extends ApiClient {
  String status = 'pending';
  bool confirmOnCheck = true;
  bool failCheck = false;
  bool failRefresh = false;
  bool failTransactions = false;
  int refreshes = 0;
  int checks = 0;
  int creations = 0;
  int transactionLoads = 0;
  int retryAttempts = 0;
  int confirmAfterChecks = 1;
  Response response(Object data) =>
      Response(data: data, requestOptions: RequestOptions(path: '/synthetic'));
  Map<String, dynamic> topup() => {
        'topup_id': 'top_synthetic',
        'amount': 500,
        'currency': 'XOF',
        'status': status,
        'created_at': '2026-10-01T07:00:00Z',
      };

  @override
  Future<Response> getWallet() async {
    refreshes++;
    if (failRefresh) throw Exception('Actualisation indisponible');
    return response({
      'wallet_id': 'wallet',
      'owner_id': 'driver',
      'balance': status == 'paid' ? 6806 : 6306,
      'currency': 'XOF',
      'topups': [topup()],
      'topup_options': {
        'enabled': true,
        'minimum_amount': 500,
        'maximum_amount': 500000,
        'verification_retry_seconds': 1,
        'verification_retry_attempts': retryAttempts,
      },
    });
  }

  @override
  Future<Response> getStripeWalletTopup(String id) async {
    checks++;
    if (failCheck) throw Exception('Vérification indisponible');
    if (id != 'top_synthetic') throw Exception('Recharge introuvable');
    if (confirmOnCheck && checks >= confirmAfterChecks) status = 'paid';
    return response(topup());
  }

  @override
  Future<Response> getTransactions({String? period}) async {
    transactionLoads++;
    if (failTransactions) throw Exception('Historique indisponible');
    return response({
      'transactions': status != 'paid'
          ? []
          : [
              {
                'tx_id': 'wtx_synthetic',
                'wallet_id': 'wallet',
                'tx_type': 'credit',
                'amount': 500,
                'created_at': '2026-10-01T07:00:00Z',
                'description': 'Recharge du solde par carte',
              }
            ]
    });
  }

  @override
  Future<Response> getMyPayouts() async => response({'payouts': []});

  @override
  Future<Response> getWalletActivity(
      {String? period, String category = 'balance', int skip = 0}) async {
    final transactions = ((await getTransactions(period: period)).data
        as Map)['transactions'] as List;
    return response({
      'items': transactions
          .map((row) => {
                ...row as Map,
                'kind': 'transaction',
                'effect': row['amount'],
                'status': 'recorded'
              })
          .toList(),
      'total': transactions.length,
      'earnings': {'amount': 0, 'courses_count': 0},
      'pending_payouts': [],
      'pending_topups': status == 'pending' ? [topup()] : [],
    });
  }

  @override
  Future<Response> createStripeWalletTopup(Map<String, dynamic> body) async {
    creations++;
    throw Exception('No real checkout allowed in tests');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  const options = WalletTopupOptions(
      enabled: true, minimumAmount: 1200, maximumAmount: 4000);

  test(
      'wallet return supports current Android and iOS links without new native paths',
      () {
    for (final base in [
      'https://denkma.com/app/',
      'https://www.denkma.com/app/',
      'denkma://app/parcel'
    ]) {
      expect(
          walletReturnParameters(
              Uri.parse('$base?wallet_return=success&topup_id=top_synthetic')),
          {'wallet_return': 'success', 'topup_id': 'top_synthetic'});
    }
    expect(
        walletReturnParameters(
            Uri.parse('https://denkma.com/wallet/stripe/cancel')),
        {'wallet_return': 'cancel'});
    expect(
        walletReturnParameters(
            Uri.parse('/app/?wallet_return=cancel&topup_id=top_synthetic')),
        {'wallet_return': 'cancel', 'topup_id': 'top_synthetic'});
  });

  test('invalid payment links do not create a wallet return', () {
    for (final link in [
      'https://outside.example/app/?wallet_return=success',
      'https://denkma.com.outside.example/app/?wallet_return=success',
      'https://denkma.com/app/?wallet_return=paid',
      '/client?wallet_return=success',
      'http://denkma.com/app/?wallet_return=success'
    ]) {
      expect(walletReturnParameters(Uri.parse(link)), isNull);
    }
    expect(
        walletReturnParameters(
            Uri.parse('/app/?wallet_return=success&topup_id=../../other')),
        {'wallet_return': 'success'});
  });

  test('backend validation details never appear as technical dumps', () {
    final request = RequestOptions(path: '/synthetic');
    final error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 422, data: {
          'detail': [
            {
              'type': 'greater_than_equal',
              'input': 300,
              'ctx': {'ge': 500}
            }
          ]
        }));
    expect(friendlyError(error),
        'Vérifiez les informations saisies puis réessayez.');
    expect(
        friendlyError(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 400, data: {
              'detail': 'Le montant minimum de recharge est de 500 FCFA'
            }))),
        'Le montant minimum de recharge est de 500 FCFA');
  });

  Future<void> showDialogScreen(
      WidgetTester tester, Future<void> Function(int) submit) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showDialog(
                          context: context,
                          builder: (_) => WalletTopupDialog(
                              options: options, onSubmit: submit)),
                      child: const Text('Ouvrir'),
                    )))));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'recharge validates server limits and rejects fractions before any request',
      (tester) async {
    var calls = 0;
    await showDialogScreen(tester, (_) async {
      calls++;
    });
    for (final value in ['300', '1199', '4001', '1500.5', '0', '']) {
      await tester.enterText(find.byType(TextFormField), value);
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    }
    await tester.enterText(find.byType(TextFormField), '1 200');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(WalletTopupDialog), findsNothing);
  });

  testWidgets(
      'double click cannot create two checkouts and error stays readable',
      (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    await showDialogScreen(tester, (_) {
      calls++;
      return gate.future;
    });
    await tester.enterText(find.byType(TextFormField), '1500');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(calls, 1);
    gate.completeError(Exception('Paiement indisponible'));
    await tester.pumpAndSettle();
    expect(find.text('Paiement indisponible'), findsOneWidget);
    expect(find.byType(WalletTopupDialog), findsOneWidget);
  });

  Future<void> showWallet(WidgetTester tester, WalletApi api,
      {String? returnResult, String? topupId}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(WalletAuth.new),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
            home: DriverWalletScreen(
                initialTopupId: topupId, returnResult: returnResult))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'paid return verifies server, refreshes balance, then reloads transactions',
      (tester) async {
    final api = WalletApi();
    await showWallet(tester, api,
        topupId: 'top_synthetic', returnResult: 'success');
    expect(api.checks, 1);
    expect(find.textContaining('créditée sur votre solde'), findsOneWidget);
    expect(find.text('Recharge du solde par carte'), findsOneWidget);
    expect(api.creations, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('success URL alone never shows credited payment', (tester) async {
    final api = WalletApi()..confirmOnCheck = false;
    await showWallet(tester, api,
        topupId: 'top_synthetic', returnResult: 'success');
    expect(find.text('Non confirmée'), findsOneWidget);
    expect(find.text('Créditée'), findsNothing);
    expect(find.textContaining('Paiement non confirmé'), findsOneWidget);
  });

  testWidgets('unknown recharge reference does not block balance refresh',
      (tester) async {
    final api = WalletApi()..status = 'paid';
    await showWallet(tester, api,
        topupId: 'top_unknown', returnResult: 'success');
    expect(api.refreshes, greaterThan(1));
    expect(find.text(formatXof(6806)), findsOneWidget);
    expect(find.text('Recharge du solde par carte'), findsOneWidget);
    expect(find.textContaining('Solde actualisé. Recharge introuvable'),
        findsOneWidget);
    expect(api.creations, 0);
  });

  testWidgets('history error does not hide a confirmed recharge',
      (tester) async {
    final api = WalletApi()..failTransactions = true;
    await showWallet(tester, api,
        topupId: 'top_synthetic', returnResult: 'success');
    expect(find.textContaining('créditée sur votre solde'), findsOneWidget);
    expect(find.text('Historique indisponible'), findsOneWidget);
    expect(api.creations, 0);
  });

  testWidgets('cancel return does not credit unpaid checkout', (tester) async {
    final api = WalletApi()..confirmOnCheck = false;
    await showWallet(tester, api,
        topupId: 'top_synthetic', returnResult: 'cancel');
    expect(find.text('Non confirmée'), findsOneWidget);
    expect(api.creations, 0);
  });

  testWidgets(
      'manual verification credits existing payment without creating checkout',
      (tester) async {
    final api = WalletApi();
    await showWallet(tester, api);
    await tester.ensureVisible(find.text('Vérifier le paiement'));
    await tester.tap(find.text('Vérifier le paiement'));
    await tester.pumpAndSettle();
    expect(api.checks, 1);
    expect(find.textContaining('créditée sur votre solde'), findsOneWidget);
    expect(api.creations, 0);
  });

  testWidgets('pull refresh really reloads wallet and movements',
      (tester) async {
    final api = WalletApi();
    await showWallet(tester, api);
    final before = api.refreshes;
    final movementsBefore = api.transactionLoads;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(api.refreshes, greaterThan(before));
    expect(api.transactionLoads, greaterThan(movementsBefore));
  });

  testWidgets('return from browser refreshes automatically', (tester) async {
    final api = WalletApi();
    await showWallet(tester, api);
    final before = api.refreshes;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.refreshes, greaterThan(before));
  });

  testWidgets(
      'delayed confirmation is checked automatically with bounded retries',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final api = WalletApi()
      ..retryAttempts = 2
      ..confirmAfterChecks = 3;
    await showWallet(tester, api,
        topupId: 'top_synthetic', returnResult: 'success');
    expect(api.checks, 1);
    expect(find.text('Non confirmée'), findsOneWidget);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    expect(api.checks, 3);
    expect(find.textContaining('créditée sur votre solde'), findsOneWidget);
    expect(api.creations, 0);
  });

  testWidgets(
      'pending checks stop at configured limit and while app is backgrounded',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final api = WalletApi()
      ..retryAttempts = 2
      ..confirmOnCheck = false;
    await showWallet(tester, api,
        topupId: 'top_synthetic', returnResult: 'success');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(api.checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    final checks = api.checks;
    await tester.pump(const Duration(seconds: 10));
    expect(api.checks, checks);
    expect(api.creations, 0);
  });

  testWidgets(
      'actual application router opens wallet rather than parcel for payment links',
      (tester) async {
    final api = WalletApi();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => WalletAuth(activeView: 'client')),
      apiClientProvider.overrideWithValue(api),
      myMissionsProvider.overrideWith((ref) async => []),
    ]);
    await container.read(authProvider.future);
    final router = container.read(appRouterProvider);
    router.go(
        'https://denkma.com/app/?wallet_return=success&topup_id=top_synthetic');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.byType(DriverWalletScreen), findsOneWidget);
    expect(api.checks, 1);
    expect(find.textContaining('créditée sur votre solde'), findsOneWidget);
    router
        .go('denkma://app/parcel?wallet_return=success&topup_id=top_synthetic');
    await tester.pumpAndSettle();
    expect(find.byType(DriverWalletScreen), findsOneWidget);
    expect(container.read(authProvider).valueOrNull?.effectiveRole, 'driver');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
  });

  testWidgets('cold payment return survives authentication loading',
      (tester) async {
    final api = WalletApi();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(LoadingWalletAuth.new),
      apiClientProvider.overrideWithValue(api),
      myMissionsProvider.overrideWith((ref) async => []),
    ]);
    await container.read(authProvider.future);
    final router = container.read(appRouterProvider);
    router.go(
        'https://denkma.com/app/?wallet_return=success&topup_id=top_synthetic');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    (container.read(authProvider.notifier) as LoadingWalletAuth).authenticate();
    await tester.pumpAndSettle();
    expect(find.byType(DriverWalletScreen), findsOneWidget);
    expect(find.textContaining('créditée sur votre solde'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
  });
}
