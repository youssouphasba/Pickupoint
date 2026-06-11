import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/in_app_campaign.dart';

final activeCampaignsProvider =
    FutureProvider.family<List<InAppCampaign>, String>((ref, role) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.getActiveCampaigns(role: role);
  final data = response.data as Map<String, dynamic>;
  return (data['campaigns'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => InAppCampaign.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ))
      .where((campaign) => campaign.id.isNotEmpty)
      .toList();
});

class CampaignBanner extends ConsumerStatefulWidget {
  const CampaignBanner({super.key, required this.role});

  final String role;

  @override
  ConsumerState<CampaignBanner> createState() => _CampaignBannerState();
}

class _CampaignBannerState extends ConsumerState<CampaignBanner> {
  final Set<String> _seen = {};

  @override
  Widget build(BuildContext context) {
    final campaignsAsync = ref.watch(activeCampaignsProvider(widget.role));
    return campaignsAsync.maybeWhen(
      data: (campaigns) {
        if (campaigns.isEmpty) {
          return const SizedBox.shrink();
        }
        final campaign = campaigns.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _markImpression(campaign.id);
        });
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openCampaign(context, campaign),
            child: Container(
              constraints: const BoxConstraints(minHeight: 86),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (campaign.imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        campaign.imageUrl!,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _CampaignIcon(),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    _CampaignIcon(),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          campaign.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          campaign.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: () => _openCampaign(context, campaign),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(campaign.ctaLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Future<void> _markImpression(String campaignId) async {
    if (_seen.contains(campaignId)) {
      return;
    }
    _seen.add(campaignId);
    try {
      await ref
          .read(apiClientProvider)
          .markCampaignImpression(campaignId, role: widget.role);
    } catch (_) {}
  }

  Future<void> _openCampaign(
    BuildContext context,
    InAppCampaign campaign,
  ) async {
    try {
      await ref
          .read(apiClientProvider)
          .markCampaignClick(campaign.id, role: widget.role);
    } catch (_) {}
    if (!context.mounted) {
      return;
    }
    if (campaign.actionType == 'external_url') {
      final uri = Uri.tryParse(campaign.actionValue);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    try {
      context.push(campaign.actionValue);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette offre est momentanement indisponible.')),
      );
    }
  }
}

class _CampaignIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.campaign_outlined, color: Colors.white),
    );
  }
}
