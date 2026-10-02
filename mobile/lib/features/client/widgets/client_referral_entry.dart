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

class ReferralRewardButton extends StatefulWidget {
  const ReferralRewardButton(
      {super.key, required this.offer, required this.onPressed});

  final Map<String, dynamic> offer;
  final VoidCallback onPressed;

  @override
  State<ReferralRewardButton> createState() => _ReferralRewardButtonState();
}

class _ReferralRewardButtonState extends State<ReferralRewardButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !TickerMode.of(context)) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        formatXof((widget.offer['sponsor_bonus_xof'] as num).toDouble());
    return Tooltip(
      message: 'Parrainage · $label selon les conditions du programme',
      child: AnimatedBuilder(
        animation: _shine,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment(-3 + _shine.value * 6, -1),
              end: Alignment(-1 + _shine.value * 6, 1),
              colors: const [
                Color(0xFFFFD66B),
                Color(0xFFFFF5CB),
                Color(0xFFFFC94A)
              ],
            ),
          ),
          child: child,
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: const Color(0xFF6D3900),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(48, 48),
            shape: const StadiumBorder(),
          ),
          onPressed: widget.onPressed,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.card_giftcard_outlined,
                size: 22, color: Color(0xFF863F94)),
            const SizedBox(width: 6),
            Flexible(
                child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
            )),
          ]),
        ),
      ),
    );
  }
}

class ClientHeaderLogo extends StatelessWidget {
  const ClientHeaderLogo({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Denkma',
        image: true,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: 40,
            child: Image.asset(
              'assets/logo_header.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
}

class ClientReferralToolbar extends StatelessWidget {
  const ClientReferralToolbar(
      {super.key,
      required this.offer,
      required this.actions,
      required this.onPressed});

  final Map<String, dynamic>? offer;
  final List<Widget> actions;
  final VoidCallback onPressed;

  static double _minimumRowWidth(bool hasReferral, int actionCount) =>
      40 + 8 + (hasReferral ? 128 : 0) + actionCount * 48;

  static double height(BuildContext context,
      {required bool hasReferral, required int actionCount}) {
    final spacing = Theme.of(context).appBarTheme.titleSpacing ??
        NavigationToolbar.kMiddleSpacing;
    final availableWidth = MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal -
        spacing * 2;
    return availableWidth >= _minimumRowWidth(hasReferral, actionCount)
        ? 64
        : 112;
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compactRowWidth = _minimumRowWidth(offer != null, actions.length);
        final actionRow = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: actions);
        if (constraints.maxWidth >= compactRowWidth) {
          return Row(children: [
            const ClientHeaderLogo(),
            const SizedBox(width: 8),
            if (offer != null)
              SizedBox(
                  width: 128,
                  child: ReferralRewardButton(
                      offer: offer!, onPressed: onPressed)),
            Expanded(child: actionRow),
          ]);
        }
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const ClientHeaderLogo(),
            if (offer != null)
              SizedBox(
                  width: 156,
                  child: ReferralRewardButton(
                      offer: offer!, onPressed: onPressed)),
          ]),
          actionRow,
        ]);
      });
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
