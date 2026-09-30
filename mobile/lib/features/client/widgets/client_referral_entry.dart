import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/providers/user_stats_provider.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/error_utils.dart';

final clientReferralProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final response = await ref.watch(apiClientProvider).getReferralInfo();
  return Map<String, dynamic>.from(response.data as Map);
});

Map<String, dynamic>? referralRewardOffer(Map<String, dynamic>? data) {
  if (data?['enabled'] != true ||
      data?['can_sponsor'] != true ||
      (data?['referral_code']?.toString().trim() ?? '').isEmpty) {
    return null;
  }
  final offers = (data?['invitation_offers'] as List? ?? [])
      .whereType<Map>()
      .map((offer) => Map<String, dynamic>.from(offer))
      .where((offer) {
    final amount = offer['sponsor_bonus_xof'];
    return amount is num && amount.isFinite && amount > 0;
  }).toList();
  return offers
          .where((offer) => offer['referred_role'] == 'client')
          .firstOrNull ??
      offers.firstOrNull;
}

class ReferralRewardButton extends StatelessWidget {
  const ReferralRewardButton(
      {super.key, required this.offer, required this.onPressed});

  final Map<String, dynamic> offer;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label =
        'Gagnez ${formatXof((offer['sponsor_bonus_xof'] as num).toDouble())}';
    return Tooltip(
      message: '$label · Parrainage',
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Theme.of(context).primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: const StadiumBorder(),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.card_giftcard_outlined, size: 20),
        label: Text(label, maxLines: 2, textAlign: TextAlign.center),
      ),
    );
  }
}

class ClientReferralToolbar extends StatelessWidget {
  const ClientReferralToolbar(
      {super.key,
      required this.offer,
      required this.actions,
      required this.onPressed});

  final Map<String, dynamic> offer;
  final List<Widget> actions;
  final VoidCallback onPressed;

  static double height(BuildContext context) =>
      kToolbarHeight * MediaQuery.textScalerOf(context).scale(14) / 14 + 48;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Flexible(
                flex: 2,
                child:
                    ReferralRewardButton(offer: offer, onPressed: onPressed)),
            const SizedBox(width: 12),
            const Expanded(
                child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('Denkma'),
            )),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      );
}

class ReferralCodeEntry extends ConsumerWidget {
  const ReferralCodeEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(clientReferralProvider).asData?.value;
    if (data?['can_apply_now'] != true || data?['can_be_referred'] != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.card_giftcard_outlined),
            label: const Text('Vous avez un code parrainage ?'),
            onPressed: () => showReferralCodeDialog(context),
          )),
    );
  }
}

Future<void> showReferralCodeDialog(BuildContext context,
        {String? initialCode}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReferralCodeDialog(initialCode: initialCode),
    );

class _ReferralCodeDialog extends ConsumerStatefulWidget {
  const _ReferralCodeDialog({this.initialCode});
  final String? initialCode;
  @override
  ConsumerState<_ReferralCodeDialog> createState() =>
      _ReferralCodeDialogState();
}

class _ReferralCodeDialogState extends ConsumerState<_ReferralCodeDialog> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialCode?.trim().toUpperCase() ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .applyReferralCode(_controller.text.trim().toUpperCase());
      await ref.read(authProvider.notifier).fetchMe();
      ref.invalidate(clientReferralProvider);
      ref.invalidate(userStatsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(clientReferralProvider).asData?.value;
    return PopScope(
        canPop: !_sending,
        child: AlertDialog(
          title: const Text('Ajouter un code parrainage'),
          scrollable: true,
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data != null) ...[
                  Text(data['apply_rule']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  Text(data['reward_rule']?.toString() ?? ''),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _controller,
                  enabled: !_sending,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'Code parrainage',
                      border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]),
          actions: [
            TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: const Text('Annuler')),
            FilledButton(
                onPressed:
                    _sending || _controller.text.trim().isEmpty ? null : _apply,
                child: Text(_sending ? 'Vérification…' : 'Appliquer')),
          ],
        ));
  }
}

class ReferralInviteCard extends ConsumerWidget {
  const ReferralInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(clientReferralProvider).asData?.value;
    if (data?['can_sponsor'] != true ||
        data?['enabled'] != true ||
        (data?['referral_code']?.toString() ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    final sponsor =
        (data!['referral_sponsor_bonus_xof'] as num?)?.toDouble() ?? 0;
    final offers = (data['invitation_offers'] as List? ?? []).whereType<Map>();
    final offer =
        offers.where((offer) => offer['referred_role'] == 'client').firstOrNull;
    if (data.containsKey('invitation_offers') && offer == null) {
      return const SizedBox.shrink();
    }
    final referred = ((offer?['referred_bonus_xof'] ??
                data['referral_referred_bonus_xof']) as num?)
            ?.toDouble() ??
        0;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Votre colis est livré. Invitez un proche !',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (sponsor > 0)
          Text('Pour vous : ${formatXof(sponsor)} par parrainage validé.'),
        if (referred > 0)
          Text(
              'Pour votre proche : ${formatXof(referred)} selon les conditions du programme.'),
        const SizedBox(height: 8),
        Text((offer?['reward_rule'] ?? data['reward_rule'])?.toString() ?? ''),
        const Text('Primes payées par Denkma hors de l’application.'),
        TextButton.icon(
            icon: const Icon(Icons.share_outlined),
            label: const Text('Inviter un proche'),
            onPressed: () => showReferralShareDialog(context, data)),
      ]),
    ));
  }
}

Future<void> showReferralShareDialog(
        BuildContext context, Map<String, dynamic> data) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Inviter un proche'),
        scrollable: true,
        content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText('Votre code : ${data['referral_code']}'),
              const SizedBox(height: 12),
              SelectableText(data['share_message']?.toString() ?? ''),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer')),
          TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(
                    text: data['share_message']?.toString() ??
                        data['referral_url']?.toString() ??
                        ''));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Invitation copiée')));
                }
              },
              child: const Text('Copier')),
          FilledButton(
              onPressed: () async {
                final message = data['share_message']?.toString() ?? '';
                var opened = false;
                try {
                  opened = await launchUrl(
                      Uri.https('wa.me', '/', {'text': message}),
                      mode: LaunchMode.externalApplication);
                } catch (_) {}
                if (!opened && dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(
                      content: Text(
                          'Impossible d’ouvrir WhatsApp. Vous pouvez copier l’invitation.')));
                }
              },
              child: const Text('WhatsApp')),
        ],
      ),
    );
