import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/in_app_campaign.dart';

class CampaignDetailScreen extends ConsumerStatefulWidget {
  const CampaignDetailScreen({
    super.key,
    required this.campaign,
    required this.role,
  });

  final InAppCampaign campaign;
  final String role;

  @override
  ConsumerState<CampaignDetailScreen> createState() =>
      _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends ConsumerState<CampaignDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(apiClientProvider).markCampaignImpression(
            widget.campaign.id,
            role: widget.role,
          );
    });
  }

  Future<void> _openAction() async {
    try {
      await ref.read(apiClientProvider).markCampaignClick(
            widget.campaign.id,
            role: widget.role,
          );
    } catch (_) {}
    if (!mounted) return;

    if (widget.campaign.actionType == 'external_url') {
      final uri = Uri.tryParse(widget.campaign.actionValue);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    context.push(widget.campaign.actionValue);
  }

  @override
  Widget build(BuildContext context) {
    final campaign = widget.campaign;
    return Scaffold(
      appBar: AppBar(title: const Text('Campagne')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (campaign.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    campaign.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (campaign.imageUrl != null) const SizedBox(height: 20),
            Text(
              campaign.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              campaign.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _openAction,
                child: Text(campaign.ctaLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
