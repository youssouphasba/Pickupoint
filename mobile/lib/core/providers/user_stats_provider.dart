import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';

final userStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.getUserStats();
  return res.data as Map<String, dynamic>;
});
