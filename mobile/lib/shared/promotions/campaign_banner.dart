import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/in_app_campaign.dart';

final activeCampaignsProvider =
    FutureProvider.family<List<InAppCampaign>,
        ({String role, String placement})>((ref, key) async {
  final api = ref.watch(apiClientProvider);
  final response = await api.getActiveCampaigns(
    role: key.role,
    placement: key.placement,
  );
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
  const CampaignBanner({
    super.key,
    required this.role,
    this.placement = 'home',
  });

  final String role;
  final String placement;

  @override
  ConsumerState<CampaignBanner> createState() => _CampaignBannerState();
}

class _CampaignBannerState extends ConsumerState<CampaignBanner> {
  final Set<String> _seen = {};
  final Set<String> _expanded = {};
  final PageController _pageController = PageController();
  Timer? _autoTimer;
  int _index = 0;
  String _campaignSignature = '';

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final campaignsAsync = ref.watch(
      activeCampaignsProvider((
        role: widget.role,
        placement: widget.placement,
      )),
    );
    return campaignsAsync.maybeWhen(
      data: (campaigns) {
        if (campaigns.isEmpty) {
          return const SizedBox.shrink();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncCampaigns(campaigns);
        });
        final safeIndex = _index.clamp(0, campaigns.length - 1);
        final campaign = campaigns[safeIndex];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _markImpression(campaign.id);
        });
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: _expanded.contains(campaign.id) ? 258 : 126,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: campaigns.length,
                  onPageChanged: (page) {
                    setState(() => _index = page);
                    _markImpression(campaigns[page].id);
                  },
                  itemBuilder: (context, page) {
                    final item = campaigns[page];
                    return _CampaignCard(
                      campaign: item,
                      expanded: _expanded.contains(item.id),
                      onToggle: () {
                        setState(() {
                          if (_expanded.contains(item.id)) {
                            _expanded.remove(item.id);
                          } else {
                            _expanded.add(item.id);
                          }
                        });
                      },
                      onOpen: () => _openCampaign(context, item),
                    );
                  },
                ),
              ),
              if (campaigns.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < campaigns.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: i == safeIndex ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == safeIndex
                              ? Colors.blue.shade700
                              : Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  void _syncCampaigns(List<InAppCampaign> campaigns) {
    if (!mounted) return;
    final signature = campaigns.map((campaign) => campaign.id).join('|');
    if (_campaignSignature != signature) {
      _campaignSignature = signature;
      _expanded.clear();
      _index = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
    _autoTimer?.cancel();
    if (campaigns.length < 2) {
      return;
    }
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients || _expanded.isNotEmpty) {
        return;
      }
      final next = (_index + 1) % campaigns.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
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
        const SnackBar(
          content: Text("Cette offre n'est pas disponible pour le moment."),
        ),
      );
    }
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final InAppCampaign campaign;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    maxLines: expanded ? 3 : 1,
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
                    maxLines: expanded ? 8 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(0, 38),
                        ),
                        onPressed: onOpen,
                        child: Text(
                          campaign.ctaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: expanded ? 'Réduire' : 'Lire la suite',
                  onPressed: onToggle,
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ),
                if (!expanded)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 82),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 36),
                      ),
                      onPressed: onOpen,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(campaign.ctaLabel),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
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
