import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'campaign_dismiss_store.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/in_app_campaign.dart';

final activeCampaignsProvider = FutureProvider.family<List<InAppCampaign>,
    ({String role, String placement})>((ref, key) async {
  final userId = ref.watch(authProvider).valueOrNull?.user?.id;
  if (userId == null) return [];
  final api = ref.watch(apiClientProvider);
  final response = await api.getActiveCampaigns(
    role: key.role,
    placement: key.placement,
  );
  final data = response.data as Map<String, dynamic>;
  Set<String> dismissed;
  try {
    dismissed = await CampaignDismissStore.read(userId);
  } catch (_) {
    dismissed = {};
  }
  final rawCampaigns =
      (data['campaigns'] as List? ?? const []).whereType<Map>().toList();
  for (final item in rawCampaigns) {
    final id = item['campaign_id']?.toString();
    if (id != null && dismissed.contains(id)) {
      try {
        await api.dismissCampaign(id);
      } catch (_) {}
    }
  }
  return rawCampaigns
      .map((item) => InAppCampaign.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ))
      .where((campaign) =>
          campaign.id.isNotEmpty && !dismissed.contains(campaign.id))
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

class _CampaignBannerState extends ConsumerState<CampaignBanner>
    with WidgetsBindingObserver {
  final Set<String> _seen = {};
  final Set<String> _expanded = {};
  final Set<String> _dismissed = {};
  final PageController _pageController = PageController();
  Timer? _autoTimer;
  int _index = 0;
  String _campaignSignature = '';
  String? _userId;
  ScrollPosition? _scrollPosition;
  List<InAppCampaign> _visibleCampaigns = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _seen.clear();
      _dismissed.clear();
      ref.invalidate(activeCampaignsProvider(
          (role: widget.role, placement: widget.placement)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _scrollPosition?.removeListener(_markVisibleCampaign);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authProvider).valueOrNull?.user?.id;
    if (uid != _userId) {
      _userId = uid;
      _seen.clear();
      _dismissed.clear();
      _expanded.clear();
      _campaignSignature = '';
    }
    final campaignsAsync = ref.watch(
      activeCampaignsProvider((
        role: widget.role,
        placement: widget.placement,
      )),
    );
    return campaignsAsync.maybeWhen(
      data: (campaigns) {
        final visibleCampaigns = campaigns
            .where((campaign) => !_dismissed.contains(campaign.id))
            .toList();
        if (visibleCampaigns.isEmpty) {
          _visibleCampaigns = [];
          _autoTimer?.cancel();
          return const SizedBox.shrink();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncCampaigns(visibleCampaigns);
        });
        final safeIndex = _index.clamp(0, visibleCampaigns.length - 1);
        final campaign = visibleCampaigns[safeIndex];
        final expanded = _expanded.contains(campaign.id);
        final titleHeight =
            _textHeight(context, _CampaignCard.titleStyle, expanded ? 3 : 1);
        final bodyHeight =
            _textHeight(context, _CampaignCard.bodyStyle, expanded ? 8 : 2);
        final cardHeight = max(expanded ? 232.0 : 124.0,
            titleHeight + bodyHeight + (expanded ? 90 : 32));
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
                height: cardHeight,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: visibleCampaigns.length,
                  onPageChanged: (page) {
                    setState(() => _index = page);
                    _markImpression(visibleCampaigns[page].id);
                  },
                  itemBuilder: (context, page) {
                    final item = visibleCampaigns[page];
                    return _CampaignCard(
                      campaign: item,
                      expanded: _expanded.contains(item.id),
                      onDismiss: () => _dismissCampaign(item.id),
                      onToggle: () {
                        setState(() {
                          if (_expanded.contains(item.id)) {
                            _expanded.remove(item.id);
                          } else {
                            _expanded.add(item.id);
                          }
                        });
                      },
                      onOpenDetails: () => _openCampaignDetails(context, item),
                      onOpen: () => _openCampaign(context, item),
                    );
                  },
                ),
              ),
              if (visibleCampaigns.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < visibleCampaigns.length; i++)
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

  double _textHeight(BuildContext context, TextStyle style, int lines) {
    final painter = TextPainter(
      text: TextSpan(
          text: List.filled(lines, 'M').join('\n'),
          style: DefaultTextStyle.of(context).style.merge(style)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      locale: Localizations.localeOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  void _syncCampaigns(List<InAppCampaign> campaigns) {
    if (!mounted) return;
    _visibleCampaigns = campaigns;
    final position = Scrollable.maybeOf(context)?.position;
    if (_scrollPosition != position) {
      _scrollPosition?.removeListener(_markVisibleCampaign);
      _scrollPosition = position;
      _scrollPosition?.addListener(_markVisibleCampaign);
    }
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
      if (!mounted ||
          !_pageController.hasClients ||
          _expanded.isNotEmpty ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          ModalRoute.of(context)?.isCurrent != true) {
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

  void _markVisibleCampaign() {
    if (mounted && _visibleCampaigns.isNotEmpty) {
      _markImpression(
          _visibleCampaigns[_index.clamp(0, _visibleCampaigns.length - 1)].id);
    }
  }

  Future<void> _markImpression(String campaignId) async {
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      if (top >= MediaQuery.sizeOf(context).height ||
          top + box.size.height <= 0) {
        return;
      }
    }
    if (_seen.contains(campaignId)) {
      return;
    }
    _seen.add(campaignId);
    try {
      final response = await ref.read(apiClientProvider).markCampaignImpression(
          campaignId,
          role: widget.role,
          viewId:
              '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}');
      if (response.data['allowed'] == false && mounted) {
        setState(() => _dismissed.add(campaignId));
      }
    } catch (_) {}
  }

  Future<void> _dismissCampaign(String id) async {
    final userId = _userId;
    final api = ref.read(apiClientProvider);
    setState(() {
      _dismissed.add(id);
      _expanded.remove(id);
      _index = 0;
    });
    if (userId == null) return;
    var stored = false;
    try {
      await CampaignDismissStore.dismiss(userId, id);
      stored = true;
    } catch (_) {}
    try {
      await api.dismissCampaign(id);
      stored = true;
    } catch (_) {}
    if (!stored && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'La fermeture n’a pas pu être mémorisée. Vérifiez votre connexion et réessayez.')));
    }
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

  void _openCampaignDetails(BuildContext context, InAppCampaign campaign) {
    final route = switch (widget.role) {
      'driver' => '/driver/campaign',
      'relay_agent' => '/relay/campaign',
      _ => '/client/campaign',
    };
    context.push(route, extra: campaign);
  }
}

class _CampaignCard extends StatelessWidget {
  static const titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );
  static const bodyStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    height: 1.2,
  );
  const _CampaignCard({
    required this.campaign,
    required this.expanded,
    required this.onToggle,
    required this.onOpenDetails,
    required this.onOpen,
    required this.onDismiss,
  });

  final InAppCampaign campaign;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

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
            if (campaign.videoUrl != null) ...[
              CampaignVideoPreview(url: campaign.videoUrl!),
              const SizedBox(width: 12),
            ] else if (campaign.imageUrl != null) ...[
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
                    style: titleStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    campaign.body,
                    maxLines: expanded ? 8 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Masquer cette campagne',
                      onPressed: onDismiss,
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: expanded ? 'Réduire' : 'Lire la suite',
                      onPressed: onOpenDetails,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                      ),
                    ),
                  ],
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

class CampaignVideoPreview extends StatefulWidget {
  const CampaignVideoPreview({super.key, required this.url});

  final String url;

  @override
  State<CampaignVideoPreview> createState() => _CampaignVideoPreviewState();
}

class _CampaignVideoPreviewState extends State<CampaignVideoPreview> {
  Future<void> _play() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      return;
    }
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (_, value, __) => IconButton.filled(
                  onPressed: () =>
                      value.isPlaying ? controller.pause() : controller.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 58,
        height: 58,
        child: Material(
          color: Colors.white.withValues(alpha: 0.18),
          child: InkWell(
            onTap: _play,
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 30),
          ),
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
