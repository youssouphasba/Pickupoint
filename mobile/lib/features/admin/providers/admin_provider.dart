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

final adminActionCenterProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminActionCenter();
  return Map<String, dynamic>.from(res.data as Map<String, dynamic>);
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

class AdminParcelsPageQuery {
  const AdminParcelsPageQuery({
    this.page = 1,
    this.search = '',
    this.status,
    this.period,
  });

  final int page;
  final String search;
  final String? status;
  final String? period;

  @override
  bool operator ==(Object other) =>
      other is AdminParcelsPageQuery &&
      other.page == page &&
      other.search == search &&
      other.status == status &&
      other.period == period;

  @override
  int get hashCode => Object.hash(page, search, status, period);
}

class AdminPageResult<T> {
  const AdminPageResult({required this.items, required this.total});

  final List<T> items;
  final int total;
}

final adminParcelsPageProvider =
    FutureProvider.family<AdminPageResult<Parcel>, AdminParcelsPageQuery>(
        (ref, query) async {
  final api = ref.watch(apiClientProvider);
  final params = <String, dynamic>{
    'skip': (query.page - 1) * 100,
    'limit': 100,
  };
  if (query.search.trim().isNotEmpty) params['search'] = query.search.trim();
  if (query.period != null) {
    params['from_date'] = '${query.period}-01';
  }
  if (query.status != null) {
    if (query.status == 'active') {
      params['scope'] = 'active';
    } else if (query.status == 'blocked_payment') {
      params['payment_blocked'] = true;
    } else if ({
      'delivered_paid',
      'delivered_unpaid',
      'commission_received',
      'commission_debt',
      'commission_offered',
    }.contains(query.status)) {
      params['finance_filter'] = query.status;
    } else if (query.status != 'all') {
      params['status'] = query.status;
    }
  }
  final res = await api.getAdminParcels(params: params);
  final data = res.data as Map<String, dynamic>;
  final parcels = (data['parcels'] as List? ?? [])
      .map((e) => Parcel.fromJson(e as Map<String, dynamic>))
      .toList();
  return AdminPageResult(
    items: parcels,
    total: (data['total'] as num?)?.toInt() ?? parcels.length,
  );
});

final adminParcelsOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminParcelsOverview();
  return res.data as Map<String, dynamic>;
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
  final users = (data['users'] as List? ?? [])
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .toList();
  users.sort((a, b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  });
  return users;
});

class AdminRelaysPageQuery {
  const AdminRelaysPageQuery({this.page = 1, this.search = ''});

  final int page;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is AdminRelaysPageQuery &&
      other.page == page &&
      other.search == search;

  @override
  int get hashCode => Object.hash(page, search);
}

final adminRelaysPageProvider =
    FutureProvider.family<AdminPageResult<RelayPoint>, AdminRelaysPageQuery>(
        (ref, query) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminRelays(
    skip: (query.page - 1) * 100,
    limit: 100,
    search: query.search,
  );
  final data = res.data as Map<String, dynamic>;
  final relays = (data['relay_points'] as List? ?? [])
      .map((e) => RelayPoint.fromJson(e as Map<String, dynamic>))
      .toList();
  return AdminPageResult(
    items: relays,
    total: (data['total'] as num?)?.toInt() ?? relays.length,
  );
});

class AdminUsersPageQuery {
  const AdminUsersPageQuery({this.page = 1, this.search = '', this.role});

  final int page;
  final String search;
  final String? role;

  @override
  bool operator ==(Object other) =>
      other is AdminUsersPageQuery &&
      other.page == page &&
      other.search == search &&
      other.role == role;

  @override
  int get hashCode => Object.hash(page, search, role);
}

final adminUsersPageProvider =
    FutureProvider.family<AdminPageResult<User>, AdminUsersPageQuery>(
        (ref, query) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminUsers(
    skip: (query.page - 1) * 100,
    limit: 100,
    search: query.search,
    role: query.role,
  );
  final data = res.data as Map<String, dynamic>;
  final users = (data['users'] as List? ?? [])
      .map((e) => User.fromJson(e as Map<String, dynamic>))
      .toList();
  return AdminPageResult(
    items: users,
    total: (data['total'] as num?)?.toInt() ?? users.length,
  );
});

final adminUsersOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminUsersOverview();
  return res.data as Map<String, dynamic>;
});

final adminNotificationBroadcastsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminNotificationBroadcasts();
  final data = res.data as Map<String, dynamic>;
  return List<Map<String, dynamic>>.from(data['broadcasts'] as List? ?? []);
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
final adminFinanceOverviewProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, period) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getFinanceOverview(period);
  return res.data as Map<String, dynamic>;
});

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
