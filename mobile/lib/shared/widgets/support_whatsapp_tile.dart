import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../utils/error_utils.dart';

Uri? supportWhatsAppUri(String url, {String? message, String? trackingCode}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !const ['https', 'http', 'whatsapp'].contains(uri.scheme)) {
    return null;
  }
  final text = message?.trim().isNotEmpty == true
      ? message!.trim()
      : trackingCode?.trim().isNotEmpty == true
          ? 'Bonjour, j’ai besoin d’aide pour le colis ${trackingCode!.trim()}.'
          : null;
  return text == null
      ? uri
      : uri.replace(queryParameters: {...uri.queryParameters, 'text': text});
}

Future<void> openSupportWhatsApp(BuildContext context, String url,
    {String? message, String? trackingCode}) async {
  final uri =
      supportWhatsAppUri(url, message: message, trackingCode: trackingCode);
  try {
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Impossible d’ouvrir WhatsApp. Vérifiez que l’application est installée.')),
    );
  }
}

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
      {super.key, this.contentPadding, this.trackingCode, this.message});

  final EdgeInsetsGeometry? contentPadding;
  final String? trackingCode;
  final String? message;

  Future<void> _openSupport(BuildContext context, String url) async {
    await openSupportWhatsApp(context, url,
        message: message, trackingCode: trackingCode);
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
        trailing: const Icon(Icons.refresh),
        onTap: () => ref.invalidate(supportWhatsAppProvider),
      ),
    );
  }
}

class SupportWhatsAppButton extends ConsumerWidget {
  const SupportWhatsAppButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(supportWhatsAppProvider);
    if (support.hasValue &&
        (support.valueOrNull?['url'] ?? '').trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Support WhatsApp',
      icon: const Icon(Icons.support_agent_outlined),
      onPressed: support.isLoading
          ? null
          : () {
              final url = support.valueOrNull?['url'];
              if (url != null && url.isNotEmpty) {
                openSupportWhatsApp(context, url);
              } else {
                ref.invalidate(supportWhatsAppProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Le contact support est momentanément indisponible. Nouvelle tentative…')),
                );
              }
            },
    );
  }
}
