import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/loyalty.dart';

final rankingProvider = FutureProvider.autoDispose<DriverRanking?>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.getMyRanking();
    if (res.data != null) {
      return DriverRanking.fromJson(res.data);
    }
  } catch (e) {
    // Handle error or return null
  }
  return null;
});
