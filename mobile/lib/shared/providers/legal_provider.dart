import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/legal_content.dart';

final legalContentProvider = FutureProvider.family<LegalContent, String>((ref, docType) async {
  final client = ref.read(apiClientProvider);
  final res = await client.getLegal(docType);
  return LegalContent.fromJson(res.data);
});
