import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/in_app_campaign.dart';
import 'campaign_detail_screen.dart';

class CampaignDetailByIdScreen extends ConsumerWidget {
  const CampaignDetailByIdScreen(
      {super.key, required this.campaignId, required this.role});

  final String campaignId;
  final String role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(apiClientProvider).getCampaign(campaignId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
              appBar: AppBar(title: const Text('Campagne')),
              body: const Center(
                  child: Text('Cette campagne n’est plus disponible.')));
        }
        final data = Map<String, dynamic>.from(snapshot.data!.data as Map);
        return CampaignDetailScreen(
            campaign: InAppCampaign.fromJson(
                Map<String, dynamic>.from(data['campaign'] as Map)),
            role: role);
      },
    );
  }
}
