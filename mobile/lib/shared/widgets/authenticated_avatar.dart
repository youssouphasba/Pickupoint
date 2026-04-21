import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';

final _avatarBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, url) async {
  final api = ref.watch(apiClientProvider);
  return api.downloadBytes(url);
});

class AuthenticatedAvatar extends ConsumerWidget {
  const AuthenticatedAvatar({
    super.key,
    required this.imageUrl,
    required this.radius,
    this.backgroundColor,
    this.fallback,
    this.loadingColor,
  });

  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final Widget? fallback;
  final Color? loadingColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _fallbackAvatar();
    }

    final bytes = ref.watch(_avatarBytesProvider(url));
    return bytes.when(
      data: (data) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: MemoryImage(data),
      ),
      loading: () => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: SizedBox(
          width: radius * 0.55,
          height: radius * 0.55,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: loadingColor,
          ),
        ),
      ),
      error: (_, __) => _fallbackAvatar(),
    );
  }

  CircleAvatar _fallbackAvatar() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: fallback,
    );
  }
}
