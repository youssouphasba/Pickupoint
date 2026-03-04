import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

class AdminLegalNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Rien à initialiser spécifiquement
  }

  Future<void> updateDocument(String docType, String title, String content) async {
    state = const AsyncLoading();
    try {
      final client = ref.read(apiClientProvider);
      await client.updateLegal(docType, {
        'title': title,
        'content': content,
      });
      state = const AsyncData(null);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      rethrow;
    }
  }
}

final adminLegalProvider = AsyncNotifierProvider<AdminLegalNotifier, void>(AdminLegalNotifier.new);
