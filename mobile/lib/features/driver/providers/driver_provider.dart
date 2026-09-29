import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/delivery_mission.dart';
import '../../../core/models/wallet.dart';

/// Paramètre GPS pour le filtrage par proximité.
/// Utiliser `(lat: null, lng: null)` si GPS indisponible (fallback = toutes les missions).
typedef DriverLocation = ({double? lat, double? lng});

final foregroundMissionNotificationProvider = StateProvider<int>((ref) => 0);

const activeDriverMissionStatuses = {
  'assigned',
  'in_progress',
  'incident_reported',
};

bool hasActiveDriverMission(List<DeliveryMission> missions) {
  return missions.any(
    (mission) => activeDriverMissionStatuses.contains(mission.status),
  );
}

Future<bool> canLeaveDriverAccount(WidgetRef ref) async {
  final missions = await ref.refresh(myMissionsProvider.future);
  return !hasActiveDriverMission(missions);
}

/// Provider pour les missions disponibles, filtrées par proximité GPS actuelle.
final availableMissionsProvider =
    FutureProvider.family<List<DeliveryMission>, DriverLocation>(
        (ref, loc) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAvailableMissions(lat: loc.lat, lng: loc.lng);
  final data = res.data as Map<String, dynamic>;
  if (data['profile_photo_required'] == true) {
    throw Exception(
      'Votre photo de profil doit être ajoutée et approuvée avant de recevoir des missions.',
    );
  }
  return (data['missions'] as List? ?? [])
      .map((e) => DeliveryMission.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour les missions acceptées par le livreur connecté.
final myMissionsProvider = FutureProvider<List<DeliveryMission>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final responses = await Future.wait([
    api.getMyMissions(),
    api.getMyMissions(limit: 10, finishedOnly: true),
  ]);
  final missionsById = <String, DeliveryMission>{};
  for (final response in responses) {
    final data = response.data as Map<String, dynamic>;
    for (final entry in data['missions'] as List? ?? const []) {
      final mission = DeliveryMission.fromJson(entry as Map<String, dynamic>);
      missionsById[mission.id] = mission;
    }
  }
  return missionsById.values.toList();
});

final completedDriverMissionsProvider =
    FutureProvider<List<DeliveryMission>>((ref) async {
  final api = ref.watch(apiClientProvider);
  const pageSize = 100;
  final missions = <DeliveryMission>[];
  var offset = 0;
  var total = pageSize;

  while (offset < total) {
    final response = await api.getMyMissions(
      limit: pageSize,
      skip: offset,
      finishedOnly: true,
    );
    final data = response.data as Map<String, dynamic>;
    final page = (data['missions'] as List? ?? const [])
        .map((entry) => DeliveryMission.fromJson(entry as Map<String, dynamic>))
        .toList();
    missions.addAll(page);
    total = (data['total'] as num?)?.toInt() ?? missions.length;
    if (page.isEmpty) break;
    offset += page.length;
  }

  missions
      .sort((a, b) => _missionHistoryDate(b).compareTo(_missionHistoryDate(a)));
  return missions;
});

DateTime _missionHistoryDate(DeliveryMission mission) {
  return mission.completedAt ??
      mission.startedAt ??
      mission.assignedAt ??
      mission.createdAt;
}

/// Provider pour une mission spécifique.
final missionProvider =
    FutureProvider.family<DeliveryMission, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getMission(id);
  return DeliveryMission.fromJson(res.data as Map<String, dynamic>);
});

/// Provider pour le portefeuille du livreur.
final driverWalletProvider = FutureProvider<Wallet>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getWallet();
  return Wallet.fromJson(res.data as Map<String, dynamic>);
});
