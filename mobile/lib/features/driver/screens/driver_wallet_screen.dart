import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../providers/driver_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/denkma_rounding_offer.dart';
import '../../../shared/utils/date_format.dart';
import '../../../core/models/wallet.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/error_utils.dart';
import '../widgets/wallet_topup_dialog.dart';

final driverTransactionsProvider =
    FutureProvider.family<List<WalletTransaction>, String?>(
        (ref, period) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getTransactions(period: period);
  final data = res.data as Map<String, dynamic>;
  return (data['transactions'] as List? ?? [])
      .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
      .toList();
});

final driverPayoutsProvider = FutureProvider<List<PayoutRequest>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getMyPayouts();
  final data = res.data as Map<String, dynamic>;
  return (data['payouts'] as List? ?? [])
      .map((e) => PayoutRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

typedef WalletActivityQuery = ({String? period, String category, int skip});

final driverWalletActivityProvider = FutureProvider.autoDispose
    .family<WalletActivity, WalletActivityQuery>((ref, query) async {
  final response = await ref.watch(apiClientProvider).getWalletActivity(
      period: query.period, category: query.category, skip: query.skip);
  return WalletActivity.fromJson(
      Map<String, dynamic>.from(response.data as Map));
});

class DriverWalletScreen extends ConsumerStatefulWidget {
  const DriverWalletScreen({super.key, this.initialTopupId, this.returnResult});

  final String? initialTopupId;
  final String? returnResult;

  @override
  ConsumerState<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends ConsumerState<DriverWalletScreen>
    with WidgetsBindingObserver {
  String? _period = _monthValue(DateTime.now());
  String? _pendingTopupId;
  Future<void>? _refreshInFlight;
  String? _paymentMessage;
  bool _paymentConfirmed = false;
  bool _refreshing = false;
  Timer? _paymentRetry;
  int? _remainingPaymentChecks;
  bool _followPendingPayment = false;
  String _historyCategory = 'balance';
  final List<int> _historyOffsets = [0];
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _historyKey = GlobalKey();
  static const _contentPadding = EdgeInsets.all(24);
  double _minimumContentHeight = 0;
  WalletActivity? _lastActivity;
  String? _lastActivityPeriod;
  List<AsyncValue<WalletActivity>> _lastActivityPages = [];

  WalletActivityQuery _activityQuery(int skip) =>
      (period: _period, category: _historyCategory, skip: skip);

  @override
  void initState() {
    super.initState();
    _pendingTopupId = widget.initialTopupId;
    _followPendingPayment = widget.returnResult == 'success';
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authProvider).valueOrNull;
      if (auth?.user?.role == 'driver' && auth?.effectiveRole != 'driver') {
        ref.read(authProvider.notifier).switchView('driver');
      }
      _refreshWallet(showFeedback: widget.returnResult != null);
    });
  }

  @override
  void didUpdateWidget(covariant DriverWalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTopupId != widget.initialTopupId ||
        oldWidget.returnResult != widget.returnResult) {
      _pendingTopupId = widget.initialTopupId;
      _followPendingPayment = widget.returnResult == 'success';
      _remainingPaymentChecks = null;
      _paymentRetry?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshWallet(showFeedback: true);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _paymentRetry?.cancel();
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshWallet(showFeedback: _pendingTopupId != null);
    }
  }

  @override
  void dispose() {
    _paymentRetry?.cancel();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshWallet({bool showFeedback = false}) async {
    if (_refreshInFlight != null) return _refreshInFlight;
    final refresh = _performRefresh(showFeedback: showFeedback);
    _refreshInFlight = refresh;
    try {
      await refresh;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _performRefresh({required bool showFeedback}) async {
    if (!mounted) return;
    _paymentRetry?.cancel();
    setState(() => _refreshing = true);
    try {
      WalletTopup? topup;
      Object? verificationError;
      final pendingId = _pendingTopupId;
      if (pendingId != null) {
        try {
          final response =
              await ref.read(apiClientProvider).getStripeWalletTopup(pendingId);
          topup = WalletTopup.fromJson(response.data as Map<String, dynamic>);
        } catch (error) {
          verificationError = error;
        }
      }
      if (!mounted) return;
      final wallet = await ref.refresh(driverWalletProvider.future);
      if (!mounted) return;
      for (final latest in wallet.topups) {
        if (latest.id == pendingId) topup = latest;
      }
      ref.invalidate(driverWalletActivityProvider);
      setState(() {
        _historyOffsets
          ..clear()
          ..add(0);
      });
      try {
        await ref.read(driverWalletActivityProvider(_activityQuery(0)).future);
      } catch (_) {}
      if (!mounted) return;
      final retryOptions = wallet.topupOptions;
      _remainingPaymentChecks ??= retryOptions?.verificationRetryAttempts ?? 0;
      if (_followPendingPayment &&
          retryOptions?.enabled == true &&
          topup?.isPending == true &&
          _remainingPaymentChecks! > 0 &&
          (retryOptions?.verificationRetrySeconds ?? 0) > 0 &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _paymentRetry = Timer(
            Duration(seconds: retryOptions!.verificationRetrySeconds), () {
          _remainingPaymentChecks = _remainingPaymentChecks! - 1;
          if (mounted) _refreshWallet(showFeedback: true);
        });
      }
      if (!showFeedback) return;
      setState(() {
        _paymentConfirmed = topup?.isPaid == true;
        _paymentMessage = topup?.isPaid == true
            ? 'Recharge de ${formatXof(topup!.amount)} créditée sur votre solde.'
            : topup?.isPending == true
                ? topup!.verificationMessage ??
                    'Paiement non confirmé. Vérifiez avant de payer une deuxième fois.'
                : topup != null
                    ? 'Cette recharge n’a pas été créditée. Consultez son état ci-dessous.'
                    : verificationError != null
                        ? 'Solde actualisé. ${friendlyError(verificationError)}'
                        : widget.returnResult != null
                            ? 'Solde actualisé. Consultez l’état de votre recharge ci-dessous.'
                            : 'Solde actualisé : ${formatXof(wallet.balance)}.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentConfirmed = false;
          _paymentMessage = friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(driverWalletProvider);
    final activityPages = _historyOffsets
        .map((offset) =>
            ref.watch(driverWalletActivityProvider(_activityQuery(offset))))
        .toList();
    final activityAsync = activityPages.first;
    if (activityAsync.hasValue &&
        !activityAsync.isLoading &&
        !activityAsync.hasError) {
      _lastActivity = activityAsync.valueOrNull;
      _lastActivityPeriod = _period;
      _lastActivityPages = activityPages;
    }
    final activity = activityAsync.valueOrNull ?? _lastActivity;
    final displayedPages =
        activityAsync.hasValue ? activityPages : _lastActivityPages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solde et revenus'),
        actions: [
          IconButton(
            tooltip: 'Actualiser le solde et vérifier les recharges',
            onPressed:
                _refreshing ? null : () => _refreshWallet(showFeedback: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshWallet(showFeedback: true),
        child: SingleChildScrollView(
          key: const PageStorageKey('driver-wallet-scroll'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: _contentPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: _minimumContentHeight),
            child: Column(
              children: [
                _buildBalanceCard(context, walletAsync),
                if (_paymentMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (_paymentConfirmed ? Colors.green : Colors.blue)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_paymentMessage!),
                  ),
                ],
                _buildPendingOperations(activity, walletAsync.valueOrNull),
                const SizedBox(height: 24),
                if (activity != null)
                  _buildActivity(activity, displayedPages,
                      loading: activityAsync.isLoading,
                      summaryCurrent: _lastActivityPeriod == _period,
                      error:
                          activityAsync.hasError ? activityAsync.error : null)
                else
                  activityAsync.when(
                    data: (activity) => _buildActivity(activity, activityPages),
                    loading: () => Column(children: [
                      _buildPeriodFilter(),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ]),
                    error: (error, _) => Column(children: [
                      _buildPeriodFilter(),
                      _activityError(error, 0),
                    ]),
                  ),
                const SizedBox(height: 16),
                const ExpansionTile(
                  title: Text('Comprendre les montants'),
                  childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Le solde Denkma sert à régler vos commissions. Vous pouvez le recharger ou demander un retrait du montant disponible.'),
                    SizedBox(height: 8),
                    Text(
                        'Les revenus des courses sont encaissés hors de l’application. Ils ne s’ajoutent pas au solde Denkma.'),
                    SizedBox(height: 8),
                    Text(
                        'Les opérations en attente restent visibles, quelle que soit la période choisie.'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    final options = <String?>[null, ..._monthOptions()];

    return DropdownButtonFormField<String?>(
      initialValue: _period,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Période',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: options
          .map(
            (value) => DropdownMenuItem<String?>(
              value: value,
              child: Text(value == null ? 'Tout' : _monthLabel(value)),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() {
        _preserveScrollPosition();
        _period = value;
        _historyOffsets
          ..clear()
          ..add(0);
      }),
    );
  }

  Widget _buildBalanceCard(BuildContext context, AsyncValue walletAsync) {
    return walletAsync.when(
      data: (wallet) => Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.blue.shade800, Colors.blue.shade500]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text('Solde Denkma disponible',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              formatXof(wallet.balance),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
            ),
            if (wallet.pendingBalance > 0) ...[
              const SizedBox(height: 4),
              Text('Réservé pour retrait : ${formatXof(wallet.pendingBalance)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            const Text('Pour régler vos commissions',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Retirer',
              color: Colors.white,
              onPressed: wallet.balance > 0 && wallet.payoutAvailable
                  ? () => _showPayoutDialog(context)
                  : null,
            ),
            if (!wallet.payoutAvailable &&
                (wallet.payoutBlockReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                wallet.payoutBlockReason!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: wallet.topupOptions?.enabled == true
                  ? () => _showTopupDialog(context, wallet.topupOptions!)
                  : null,
              icon: const Icon(Icons.add_card),
              label: const Text('Recharger'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
            ),
            if (wallet.topupOptions?.enabled != true) ...[
              const SizedBox(height: 8),
              const Text(
                  'La recharge par carte est momentanément indisponible.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70)),
            ],
          ],
        ),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (e, __) => Text(friendlyError(e)),
    );
  }

  void _showTopupDialog(BuildContext context, WalletTopupOptions options) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WalletTopupDialog(
          options: options,
          onSubmit: (amount) async {
            final response = await ref
                .read(apiClientProvider)
                .createStripeWalletTopup({'amount': amount});
            final data = response.data as Map<String, dynamic>;
            final checkout =
                Uri.tryParse(data['checkout_url']?.toString() ?? '');
            if (checkout == null ||
                checkout.scheme != 'https' ||
                checkout.host != 'checkout.stripe.com') {
              throw Exception(
                  'Lien de paiement Stripe indisponible. Contactez le support.');
            }
            if (!mounted) return;
            _pendingTopupId = data['topup_id'] as String;
            _remainingPaymentChecks = null;
            _followPendingPayment = true;
            setState(() {
              _paymentMessage = null;
              _paymentConfirmed = false;
            });
            if (!await launchUrl(checkout,
                mode: LaunchMode.externalApplication)) {
              throw Exception(
                  'Impossible d’ouvrir le paiement. Vérifiez votre navigateur.');
            }
          }),
    );
  }

  Widget _buildPendingOperations(WalletActivity? activity, Wallet? wallet) {
    final pendingTopups = {
      for (final topup in activity?.pendingTopups ?? <WalletTopup>[])
        if (topup.isPending) topup.id: topup,
    };
    for (final topup in wallet?.topups ?? <WalletTopup>[]) {
      if (topup.isPending) {
        pendingTopups[topup.id] = topup;
      } else {
        pendingTopups.remove(topup.id);
      }
    }
    final payouts = activity?.pendingPayouts ?? <PayoutRequest>[];
    final count = pendingTopups.length + payouts.length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Opérations en attente ($count)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildTopupsSection(pendingTopups.values.toList()),
          _buildPayoutsSection(payouts),
        ],
      ),
    );
  }

  Widget _buildTopupsSection(List<WalletTopup> pending) {
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...pending.map((topup) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        Text(formatXof(topup.amount),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const _StatusPill(
                          label: 'Non confirmée',
                          color: Colors.orange,
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                          'Recharge par carte · ${formatDate(topup.createdAt)}'),
                      if (topup.isPending) ...[
                        const SizedBox(height: 8),
                        Text(topup.verificationMessage ??
                            'Vérifiez le paiement avant de payer une deuxième fois.'),
                        TextButton.icon(
                          onPressed: _refreshing
                              ? null
                              : () {
                                  _pendingTopupId = topup.id;
                                  _remainingPaymentChecks = null;
                                  _followPendingPayment = true;
                                  _refreshWallet(showFeedback: true);
                                },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Vérifier le paiement'),
                        ),
                      ],
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _activityError(Object error, int skip) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: [
          Text(friendlyError(error)),
          TextButton.icon(
              onPressed: () => ref.invalidate(
                  driverWalletActivityProvider(_activityQuery(skip))),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer')),
        ]),
      );

  Widget _buildActivity(
      WalletActivity activity, List<AsyncValue<WalletActivity>> pages,
      {bool loading = false, bool summaryCurrent = true, Object? error}) {
    final rows = pages
        .expand((page) => page.valueOrNull?.items ?? <WalletActivityItem>[])
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revenus des courses',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              _buildPeriodFilter(),
              const SizedBox(height: 16),
              Text(summaryCurrent ? formatXof(activity.earnings) : '—',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold)),
              Text(summaryCurrent
                  ? '${activity.coursesCount} course${activity.coursesCount == 1 ? '' : 's'}'
                  : loading
                      ? 'Chargement…'
                      : 'Revenus indisponibles'),
              const SizedBox(height: 8),
              const Text('Encaissés hors application'),
              TextButton.icon(
                onPressed: _showRevenueHistory,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Voir les courses concernées'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text('Historique',
          key: _historyKey,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final entry in {'balance': 'Solde', 'revenues': 'Courses'}.entries)
          ChoiceChip(
              label: Text(entry.value),
              selected: _historyCategory == entry.key,
              onSelected: (_) => _selectHistoryCategory(entry.key)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
          height: 4, child: loading ? const LinearProgressIndicator() : null),
      if (error != null) _activityError(error, 0),
      if (!loading &&
          error == null &&
          rows.isEmpty &&
          pages.every((page) => page.hasValue))
        const Text('Aucune opération pour cette période.'),
      IgnorePointer(
        ignoring: loading || error != null,
        child: Opacity(
          opacity: loading || error != null ? 0.45 : 1,
          child: Column(
              children: [for (final row in rows) _buildActivityRow(row)]),
        ),
      ),
      if (!loading && error == null)
        for (var index = 1; index < pages.length; index++)
          pages[index].when(
              data: (_) => const SizedBox.shrink(),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  _activityError(error, _historyOffsets[index])),
      if (!loading &&
          error == null &&
          pages.every((page) => page.hasValue) &&
          rows.length < activity.total)
        TextButton.icon(
            onPressed: () => setState(() => _historyOffsets.add(rows.length)),
            icon: const Icon(Icons.expand_more),
            label: Text('Voir plus (${rows.length} sur ${activity.total})')),
    ]);
  }

  void _showRevenueHistory() {
    _selectHistoryCategory('revenues');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final historyContext = _historyKey.currentContext;
      if (!mounted || historyContext == null) return;
      Scrollable.ensureVisible(historyContext,
          alignment: 0.1, duration: const Duration(milliseconds: 300));
    });
  }

  void _preserveScrollPosition() {
    if (!_scrollController.hasClients) return;
    _minimumContentHeight = max(
        0.0,
        _scrollController.offset +
            _scrollController.position.viewportDimension -
            _contentPadding.vertical);
  }

  void _selectHistoryCategory(String category) {
    if (_historyCategory == category) return;
    setState(() {
      _preserveScrollPosition();
      _historyCategory = category;
      _historyOffsets
        ..clear()
        ..add(0);
    });
  }

  Widget _buildActivityRow(WalletActivityItem item) {
    final revenue = item.kind == 'revenue';
    final color = revenue
        ? Colors.blue
        : item.effect < 0
            ? Colors.red
            : item.effect > 0
                ? Colors.green
                : Colors.grey;
    final status = item.kind == 'payout'
        ? _payoutStatusLabel(item.status)
        : item.status == 'expired'
            ? 'Expirée'
            : item.status == 'failed'
                ? 'Échec'
                : null;
    final effectLabel = item.kind == 'payout' && item.status == 'rejected'
        ? 'Montant restitué · solde inchangé'
        : !revenue && item.effect == 0
            ? 'Solde inchangé'
            : null;
    return Card(
        child: InkWell(
      onTap: item.missionId == null
          ? null
          : () => context
              .push('/driver/mission/${Uri.encodeComponent(item.missionId!)}'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                  revenue
                      ? Icons.payments_outlined
                      : item.effect < 0
                          ? Icons.remove_circle
                          : item.effect > 0
                              ? Icons.add_circle
                              : Icons.payments_outlined,
                  color: color),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(item.description,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (item.missionId != null) const Icon(Icons.chevron_right),
            ]),
            const SizedBox(height: 8),
            Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                      '${!revenue && item.effect != 0 ? item.effect > 0 ? '+ ' : '− ' : ''}${formatXof(item.amount)}',
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.bold)),
                  if (status != null) _StatusPill(label: status, color: color),
                ]),
            if (effectLabel != null)
              Text(effectLabel, style: Theme.of(context).textTheme.bodySmall),
            if (revenue)
              DenkmaRoundingOffer(
                amount: item.rounding.driverBonus,
                includedInGain: true,
              ),
            Text(formatDate(item.createdAt),
                style: Theme.of(context).textTheme.bodySmall),
            if (item.rejectionReason != null) Text(item.rejectionReason!),
          ])),
    ));
  }

  void _showPayoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayoutDialog(onSubmitted: () {
        if (!mounted) return;
        _refreshWallet();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Demande envoyée, montant réservé en attente de validation.')));
      }),
    );
  }

  Widget _buildPayoutsSection(List<PayoutRequest> payouts) {
    final recent =
        payouts.where((payout) => payout.status == 'pending').toList();
    if (recent.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...recent.map(
          (payout) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: Icon(
                _payoutStatusIcon(payout.status),
                color: _payoutStatusColor(payout.status),
              ),
              title: Text(formatXof(payout.amount)),
              subtitle: Text(
                'Retrait · ${_payoutMethodLabel(payout.method)} · ${formatDate(payout.updatedAt ?? payout.createdAt)}',
              ),
              trailing: _StatusPill(
                label: _payoutStatusLabel(payout.status),
                color: _payoutStatusColor(payout.status),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PayoutDialog extends ConsumerStatefulWidget {
  const _PayoutDialog({required this.onSubmitted});
  final VoidCallback onSubmitted;
  @override
  ConsumerState<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends ConsumerState<_PayoutDialog> {
  final _amountController = TextEditingController();
  final _random = Random.secure();
  late final _requestKey = base64Url
      .encode(List.generate(24, (_) => _random.nextInt(256)))
      .replaceAll('=', '');
  String _method = 'wave';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = double.tryParse(_amountController.text.trim());
    final wallet = ref.read(driverWalletProvider).valueOrNull;
    if (amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        amount != amount.roundToDouble()) {
      setState(() => _error = 'Saisissez un montant entier en FCFA.');
      return;
    }
    if (wallet == null || amount > wallet.balance) {
      setState(() => _error = 'Le montant dépasse votre solde disponible.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = ref.read(authProvider).valueOrNull?.user;
      await ref.read(apiClientProvider).requestPayout({
        'amount': amount,
        'method': _method,
        'phone': user?.phone ?? '',
        'request_key': _requestKey
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSubmitted();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_submitting,
        child: AlertDialog(
          title: const Text('Retirer de mon solde'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Le montant sera réservé jusqu’à la validation du versement par l’administration.'),
            const SizedBox(height: 16),
            TextField(
                controller: _amountController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Montant (FCFA)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
                initialValue: _method,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Méthode', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'wave', child: Text('Wave')),
                  DropdownMenuItem(
                      value: 'orange_money', child: Text('Orange Money')),
                  DropdownMenuItem(
                      value: 'free_money', child: Text('Free Money')),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _method = value!)),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
          ])),
          actions: [
            TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Annuler')),
            SizedBox(
                width: 180,
                child: LoadingButton(
                    label: 'Envoyer',
                    isLoading: _submitting,
                    onPressed: _submit)),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _payoutMethodLabel(String method) {
  switch (method) {
    case 'orange_money':
      return 'Orange Money';
    case 'free_money':
      return 'Free Money';
    case 'wave':
      return 'Wave';
    default:
      return method.isEmpty ? '-' : method;
  }
}

String _payoutStatusLabel(String status) {
  switch (status) {
    case 'approved':
      return 'Validé';
    case 'rejected':
      return 'Rejeté';
    default:
      return 'En attente';
  }
}

Color _payoutStatusColor(String status) {
  switch (status) {
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Colors.red;
    default:
      return Colors.orange;
  }
}

IconData _payoutStatusIcon(String status) {
  switch (status) {
    case 'approved':
      return Icons.check_circle;
    case 'rejected':
      return Icons.cancel;
    default:
      return Icons.hourglass_top;
  }
}

List<String> _monthOptions() {
  final now = DateTime.now();
  return List.generate(18, (index) {
    final date = DateTime(now.year, now.month - index);
    return _monthValue(date);
  });
}

String _monthValue(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String _monthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) {
    return value;
  }
  final month = int.tryParse(parts[1]);
  final year = parts[0];
  const names = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];
  if (month == null || month < 1 || month > 12) {
    return value;
  }
  return '${names[month - 1]} $year';
}
