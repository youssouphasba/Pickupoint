import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/models/wallet.dart';

/// Provider pour le stock actuel du point relais de l'agent connecté.
final relayStockProvider = FutureProvider<List<Parcel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull?.user;
  final relayId = user?.relayPointId;

  if (relayId == null) return [];

  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayStock(relayId);
  final data = res.data as Map<String, dynamic>;
  // Backend retourne {"parcels": [...]}
  return (data['parcels'] as List? ?? [])
      .map((e) => Parcel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour le portefeuille (wallet) de l'agent relais.
final relayWalletProvider = FutureProvider<Wallet>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getWallet();
  return Wallet.fromJson(res.data as Map<String, dynamic>);
});

/// Provider pour l'historique des colis remis (status=delivered).
final relayHistoryProvider = FutureProvider<List<Parcel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull?.user;
  final relayId = user?.relayPointId;
  if (relayId == null) return [];

  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayHistory(relayId);
  final data = res.data as Map<String, dynamic>;
  return (data['parcels'] as List? ?? [])
      .map((e) => Parcel.fromJson(e as Map<String, dynamic>))
      .toList();
});

final relayPerformanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull?.user;
  final relayId = user?.relayPointId;
  if (relayId == null) return {};

  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayPerformance(relayId);
  return Map<String, dynamic>.from(res.data as Map<String, dynamic>);
});

/// Provider pour les transactions du portefeuille.
final relayTransactionsProvider =
    FutureProvider.family<List<WalletTransaction>, String?>(
        (ref, period) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getTransactions(period: period);
  final data = res.data as Map<String, dynamic>;
  return (data['transactions'] as List? ?? [])
      .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour la fiche detaillee du point relais de l'agent connecte.
final relayPointProfileProvider = FutureProvider<RelayPoint?>((ref) async {
  final user = ref.watch(authProvider).valueOrNull?.user;
  final relayId = user?.relayPointId;
  if (relayId == null) {
    return null;
  }

  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayPoint(relayId);
  return RelayPoint.fromJson(res.data as Map<String, dynamic>);
});

final relayFinancialActionsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int skip, bool pendingOnly})>(
        (ref, page) async {
  final relayId = ref.watch(authProvider).valueOrNull?.user?.relayPointId;
  if (relayId == null) return {'actions': [], 'pending_count': 0, 'total': 0};
  final response = await ref.watch(apiClientProvider).getRelayFinancialActions(
      relayId,
      skip: page.skip,
      pendingOnly: page.pendingOnly);
  return Map<String, dynamic>.from(response.data as Map);
});

final relayFinancialActionCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final page = await ref.watch(
      relayFinancialActionsProvider((skip: 0, pendingOnly: true)).future);
  return (page['pending_count'] as num?)?.toInt() ?? 0;
});
