import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

final userStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.getUserStats();
  return res.data as Map<String, dynamic>;
});
