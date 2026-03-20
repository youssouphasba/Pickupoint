import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/models/user.dart';
import '../../../core/models/wallet.dart';
import '../../../core/models/promotion.dart';

/// Provider pour les promotions (admin).
final adminPromotionsProvider = FutureProvider<List<Promotion>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminPromotions();
  final data = res.data as Map<String, dynamic>;
  return (data['promotions'] as List? ?? [])
      .map((e) => Promotion.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour les statistiques du dashboard admin.
final adminDashboardProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getDashboard();
  return res.data as Map<String, dynamic>;
});

/// Provider pour tous les colis (vue admin).
final adminParcelsProvider = FutureProvider<List<Parcel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminParcels();
  final data = res.data as Map<String, dynamic>;
  return (data['parcels'] as List? ?? [])
      .map((e) => Parcel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour tous les points relais.
final adminRelaysProvider = FutureProvider<List<RelayPoint>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminRelays();
  final data = res.data as Map<String, dynamic>;
  return (data['relay_points'] as List? ?? [])
      .map((e) => RelayPoint.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour les demandes de retrait en attente.
final adminPayoutsProvider = FutureProvider<List<PayoutRequest>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getPayouts();
  final data = res.data as Map<String, dynamic>;
  return (data['payouts'] as List? ?? [])
      .map((e) => PayoutRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour la liste des utilisateurs.
final adminUsersProvider = FutureProvider<List<User>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminUsers();
  final data = res.data as Map<String, dynamic>;
  return (data['users'] as List? ?? [])
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour le suivi de la flotte live.
final adminFleetProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getLiveFleet();
  return res.data as Map<String, dynamic>;
});

/// Provider pour les colis stagnants.
final adminStaleParcelsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getStaleParcels();
  final data = res.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['stale_parcels'] as List? ?? []);
});

/// Provider pour le suivi financier (COD).
final adminFinanceProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getCodMonitoring();
  final data = res.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['entities'] as List? ?? []);
});

/// Provider pour le rapport de reconciliation finance/operations.
final adminReconciliationProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getFinanceReconciliation();
  return res.data as Map<String, dynamic>;
});

/// Provider pour les données de heatmap.
final adminHeatmapProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getHeatmapData();
  return res.data as Map<String, dynamic>;
});

/// Provider pour les anomalies signalées.
final adminAnomalyProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAnomalies();
  final data = res.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['anomalies'] as List? ?? []);
});

/// Provider pour l'historique d'un utilisateur spécifique.
final adminUserHistoryProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getUserHistory(userId);
  return res.data as Map<String, dynamic>;
});

final adminUserDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, userId) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminUserDetail(userId);
  return res.data as Map<String, dynamic>;
});

final adminRelayDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, relayId) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminRelayDetail(relayId);
  return res.data as Map<String, dynamic>;
});
