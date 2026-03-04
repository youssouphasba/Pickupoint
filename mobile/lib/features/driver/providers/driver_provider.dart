import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/delivery_mission.dart';
import '../../../core/models/wallet.dart';

/// Paramètre GPS pour le filtrage par proximité.
/// Utiliser `(lat: null, lng: null)` si GPS indisponible (fallback = toutes les missions).
typedef DriverLocation = ({double? lat, double? lng});

/// Provider pour les missions disponibles, filtrées par proximité si GPS fourni.
final availableMissionsProvider =
    FutureProvider.family<List<DeliveryMission>, DriverLocation>((ref, loc) async {
  final api = ref.watch(apiClientProvider);
  final res  = await api.getAvailableMissions(lat: loc.lat, lng: loc.lng);
  final data = res.data as Map<String, dynamic>;
  return (data['missions'] as List? ?? [])
      .map((e) => DeliveryMission.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Provider pour les missions acceptées par le livreur connecté.
final myMissionsProvider = FutureProvider<List<DeliveryMission>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getMyMissions();
  final data = res.data as Map<String, dynamic>;
  return (data['missions'] as List? ?? []).map((e) => DeliveryMission.fromJson(e as Map<String, dynamic>)).toList();
});

/// Provider pour une mission spécifique.
final missionProvider = FutureProvider.family<DeliveryMission, String>((ref, id) async {
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
