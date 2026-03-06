import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../core/models/relay_point.dart';

/// Provider pour la liste des colis de l'utilisateur.
final parcelsProvider = FutureProvider<List<Parcel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getParcels(params: {'role_view': 'client'});
  final data = res.data as Map<String, dynamic>;
  // Backend retourne {"parcels": [...], "total": N}
  return (data['parcels'] as List? ?? []).map((e) => Parcel.fromJson(e as Map<String, dynamic>)).toList();
});

/// Provider pour un colis spécifique identifié par son ID.
final parcelProvider = FutureProvider.family<Parcel, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getParcel(id);
  // Backend retourne {"parcel": {...}, "timeline": [...]}
  final data = res.data as Map<String, dynamic>;
  final parcelData = data['parcel'] as Map<String, dynamic>;
  final timeline = data['timeline'] as List? ?? [];
  return Parcel.fromJson({...parcelData, 'events': timeline});
});

/// Provider pour la liste des points relais disponibles.
final relayPointsProvider = FutureProvider<List<RelayPoint>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayPoints();
  final data = res.data as Map<String, dynamic>;
  // Backend retourne {"relay_points": [...], "total": N}
  return (data['relay_points'] as List? ?? []).map((e) => RelayPoint.fromJson(e as Map<String, dynamic>)).toList();
});
