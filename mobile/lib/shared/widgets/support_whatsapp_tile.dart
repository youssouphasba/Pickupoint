import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../utils/error_utils.dart';

final supportWhatsAppProvider =
    FutureProvider<Map<String, String?>>((ref) async {
  final res = await ref.watch(apiClientProvider).getPublicAppSettings();
  final data = Map<String, dynamic>.from(
    res.data as Map<String, dynamic>? ?? const {},
  );
  return {
    'phone': data['support_whatsapp_phone']?.toString(),
    'url': data['support_whatsapp_url']?.toString(),
  };
});

class SupportWhatsAppTile extends ConsumerWidget {
  const SupportWhatsAppTile(
      {super.key, this.contentPadding, this.trackingCode});

  final EdgeInsetsGeometry? contentPadding;
  final String? trackingCode;

  Future<void> _openSupport(BuildContext context, String url) async {
    var uri = Uri.tryParse(url);
    if (uri == null) return;
    if (trackingCode?.trim().isNotEmpty == true) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'text':
            'Bonjour, j’ai besoin d’aide pour le colis ${trackingCode!.trim()}.'
      });
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supportAsync = ref.watch(supportWhatsAppProvider);
    return supportAsync.when(
      data: (support) {
        final url = (support['url'] ?? '').trim();
        final phone = (support['phone'] ?? '').trim();
        if (url.isEmpty) return const SizedBox.shrink();
        return ListTile(
          contentPadding: contentPadding,
          leading: const Icon(Icons.support_agent_outlined),
          title: const Text('Contacter le support WhatsApp'),
          subtitle: Text(phone.isEmpty ? 'Écrire au support Denkma' : phone),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openSupport(context, url),
        );
      },
      loading: () => ListTile(
        contentPadding: contentPadding,
        leading: const Icon(Icons.support_agent_outlined),
        title: const Text('Support WhatsApp'),
        subtitle: const Text('Chargement du contact support...'),
      ),
      error: (error, _) => ListTile(
        contentPadding: contentPadding,
        leading: const Icon(Icons.support_agent_outlined),
        title: const Text('Support WhatsApp indisponible'),
        subtitle: Text(friendlyError(error)),
      ),
    );
  }
}
