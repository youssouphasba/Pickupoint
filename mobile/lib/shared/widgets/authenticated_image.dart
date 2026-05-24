import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';

final _authenticatedImageBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, url) async {
  final api = ref.watch(apiClientProvider);
  return api.downloadBytes(url);
});

class AuthenticatedImage extends ConsumerWidget {
  const AuthenticatedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.backgroundColor,
    this.fallback,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final Color? backgroundColor;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _fallback();
    }

    final bytes = ref.watch(_authenticatedImageBytesProvider(url));
    return bytes.when(
      data: (data) => ClipRRect(
        borderRadius: borderRadius,
        child: Image.memory(
          data,
          width: width,
          height: height,
          fit: fit,
        ),
      ),
      loading: () => _container(
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => _fallback(),
    );
  }

  Widget _fallback() => _container(
        fallback ??
            const Icon(
              Icons.image_not_supported_outlined,
              color: Colors.blueGrey,
            ),
      );

  Widget _container(Widget child) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: width,
        height: height,
        color: backgroundColor ?? Colors.blueGrey.shade50,
        child: child,
      ),
    );
  }
}
