import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/providers/user_stats_provider.dart';
import '../../../shared/widgets/account_switcher.dart';

final _referralInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ref.watch(apiClientProvider).getReferralInfo();
  return Map<String, dynamic>.from(
    res.data as Map<String, dynamic>? ?? const {},
  );
});

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).valueOrNull;
    final statsAsync = ref.watch(userStatsProvider);
    final referralAsync = ref.watch(_referralInfoProvider);
    final user = authState?.user;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Non connecté')));
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(userStatsProvider.future),
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, ref, user),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsRow(statsAsync),
                    const SizedBox(height: 24),
                    _buildLoyaltyProgress(user, statsAsync),
                    const SizedBox(height: 24),
                    _buildActionsList(context, ref, user, referralAsync),
                    const SizedBox(height: 40),
                    _buildLogoutButton(ref),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, WidgetRef ref, dynamic user) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade900, Colors.blue.shade600],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              _buildAvatar(context, ref, user),
              const SizedBox(height: 12),
              Text(
                user.fullName ?? 'Utilisateur',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified,
                      color: Colors.blueAccent, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    user.phone,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14),
                  ),
                ],
              ),
              if (user.email != null && user.email!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  user.email!,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        user.role.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (user.kycStatus == 'verified') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.verified,
                            color: Colors.white, size: 10),
                      ),
                    ],
                  ],
                ),
              ),
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    user.bio!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.qr_code_2, color: Colors.white),
          onPressed: () => _showDigitalID(context, user),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Colors.white),
          onPressed: () => _showEditProfile(context, ref, user),
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context, WidgetRef ref, dynamic user) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 54,
          backgroundColor: Colors.white.withValues(alpha: 0.3),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white,
            backgroundImage: user.profilePictureUrl != null
                ? CachedNetworkImageProvider(user.profilePictureUrl!)
                : null,
            child: user.profilePictureUrl == null
                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                : null,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => _pickAndUploadImage(context, ref),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.camera_alt, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(AsyncValue<Map<String, dynamic>> statsAsync) {
    return statsAsync.when(
      data: (stats) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Envois', '${stats['parcels_sent']}'),
          _buildStatItem('Points', '${stats['loyalty_points']}'),
          _buildStatItem('Filleuls', '${stats['referrals_count']}'),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => const Text('Erreur stats'),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildLoyaltyProgress(
      dynamic user, AsyncValue<Map<String, dynamic>> statsAsync) {
    final points = user.loyaltyPoints ?? 0;
    final tier = user.loyaltyTier ?? 'bronze';

    int nextTierPoints = 200;
    String nextTier = "Silver";
    if (tier == 'silver') {
      nextTierPoints = 500;
      nextTier = "Gold";
    } else if (tier == 'gold') {
      nextTierPoints = points;
    }

    final progress = (points / nextTierPoints).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Statut $tier'.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('$points / $nextTierPoints PTS',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          if (tier != 'gold')
            Text(
                'Plus que ${nextTierPoints - points} points pour devenir $nextTier !',
                style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _buildActionsList(
    BuildContext context,
    WidgetRef ref,
    dynamic user,
    AsyncValue<Map<String, dynamic>> referralAsync,
  ) {
    final referralData = referralAsync.valueOrNull ?? const <String, dynamic>{};
    final hasSponsor = (user.referredBy ?? '').toString().trim().isNotEmpty;
    final referralCheckFailed = referralAsync.hasError;
    final canApplyReferral = !hasSponsor &&
        (referralCheckFailed ||
            (referralData['can_apply_now'] as bool? ?? false));
    final applyRule = referralData['apply_rule']?.toString() ??
        'Les conditions du programme seront verifiees au moment de la saisie.';

    return Column(
      children: [
        _buildActionCard([
          const ListTile(
            leading: Icon(Icons.switch_account_outlined),
            title: Text('Changer de rôle'),
            trailing: AccountSwitcherButton(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: const Text('Devenir partenaire'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/client/partnership'),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('PRÉFÉRENCES',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        _buildActionCard([
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Adresses favorites'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/client/favorites'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/client/notifications'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Ma Bio professionnelle'),
            trailing: const Icon(Icons.edit, size: 18, color: Colors.blue),
            onTap: () => _showEditBio(
                context, ref, ref.read(authProvider).valueOrNull?.user),
          ),
        ]),
        const SizedBox(height: 20),
        _buildActionCard([
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Historique de fidélité'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/client/loyalty-history'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              hasSponsor
                  ? Icons.verified_outlined
                  : Icons.card_giftcard_outlined,
            ),
            title: Text(
              hasSponsor
                  ? 'Parrainage déjà activé'
                  : 'J\'ai un code parrainage',
            ),
            subtitle: Text(
              hasSponsor
                  ? (user.referralCredited
                      ? 'Le bonus de parrainage a déjà été crédité.'
                      : 'Votre bonus sera crédite selon les regles du programme de parrainage.')
                  : referralAsync.isLoading
                      ? 'Verification des conditions du programme...'
                      : referralCheckFailed
                          ? 'Vous pouvez saisir un code. Le serveur verifiera les conditions.'
                          : canApplyReferral
                              ? applyRule
                              : 'Le code ne peut plus etre applique. $applyRule',
            ),
            trailing: hasSponsor
                ? const Icon(Icons.lock_outline)
                : const Icon(Icons.chevron_right),
            enabled: hasSponsor || canApplyReferral,
            onTap: hasSponsor || !canApplyReferral
                ? null
                : () => _applyReferralCode(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Partager mon code parrainage'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _shareReferral(context, ref),
          ),
        ]),
        const SizedBox(height: 20),
        _buildActionCard([
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Confidentialité'),
            onTap: () => context.push('/legal/privacy'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Conditions (CGU)'),
            onTap: () => context.push('/legal/cgu'),
          ),
        ]),
      ],
    );
  }

  Widget _buildActionCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(children: children),
    );
  }

  Future<void> _applyReferralCode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajouter un code parrainage'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Code parrainage',
            hintText: 'Ex: DENKMA-4F2K',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(controller.text.trim().toUpperCase()),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (code == null || code.trim().isEmpty || !context.mounted) {
      return;
    }

    try {
      await ref.read(apiClientProvider).applyReferralCode(code.trim());
      await ref.read(authProvider.notifier).fetchMe();
      ref.invalidate(_referralInfoProvider);
      ref.invalidate(userStatsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Code parrainage applique. Les primes seront debloquees selon les regles du programme.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareReferral(BuildContext context, WidgetRef ref) async {
    try {
      final response = await ref.read(apiClientProvider).getReferralInfo();
      final data = Map<String, dynamic>.from(
        response.data as Map<String, dynamic>? ?? const {},
      );
      final enabled = data['enabled'] as bool? ?? false;
      if (!enabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data['message']?.toString() ??
                    'Le parrainage n\'est pas actif pour ce compte.',
              ),
            ),
          );
        }
        return;
      }

      final shareMessage = data['share_message']?.toString().trim() ?? '';
      final referralCode =
          data['referral_code']?.toString().trim().toUpperCase() ?? '';
      final referralUrl = data['referral_url']?.toString().trim();
      if (!context.mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Parrainage Denkma',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  referralCode.isEmpty
                      ? 'Votre code sera disponible apres l’activation du parrainage.'
                      : 'Code: $referralCode',
                ),
                if (referralUrl != null && referralUrl.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    referralUrl,
                    style: const TextStyle(color: Colors.blueGrey),
                  ),
                ],
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copier le message'),
                  subtitle: const Text('Code et lien de parrainage'),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: shareMessage),
                    );
                    if (!sheetContext.mounted) {
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message de parrainage copie'),
                      ),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tag_outlined),
                  title: const Text('Copier seulement le code'),
                  onTap: referralCode.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: referralCode),
                          );
                          if (!sheetContext.mounted) {
                            return;
                          }
                          Navigator.of(sheetContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code parrainage copie'),
                            ),
                          );
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.message_outlined, color: Colors.green),
                  title: const Text('Partager sur WhatsApp'),
                  onTap: () async {
                    final whatsappUri = Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(shareMessage)}',
                    );
                    if (await canLaunchUrl(whatsappUri)) {
                      await launchUrl(
                        whatsappUri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                    if (!sheetContext.mounted) {
                      return;
                    }
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildLogoutButton(WidgetRef ref) {
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: Colors.red),
      onPressed: () => ref.read(authProvider.notifier).logout(),
      icon: const Icon(Icons.logout),
      label: const Text('Se déconnecter'),
    );
  }

  Future<void> _pickAndUploadImage(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      try {
        await ref.read(apiClientProvider).uploadAvatar(File(image.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Photo mise à jour !')));
          // Re-fetch user profile to update avatar everywhere
          ref.read(authProvider.notifier).fetchMe();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erreur: $e')));
        }
      }
    }
  }

  void _showDigitalID(BuildContext context, dynamic user) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ID Digital Denkma',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'Présentez ce code QR à un agent relais pour identification.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            QrImageView(
              data: user.id,
              version: QrVersions.auto,
              size: 200.0,
            ),
            const SizedBox(height: 12),
            Text(user.fullName ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showEditProfile(BuildContext context, WidgetRef ref, dynamic user) {
    final emailCtrl = TextEditingController(text: user.email);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: user.fullName,
              enabled: false,
              decoration: const InputDecoration(
                  labelText: 'Nom (non modifiable)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                  labelText: 'E-mail', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(authProvider.notifier)
                    .updateProfile(email: emailCtrl.text);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _showEditBio(BuildContext context, WidgetRef ref, dynamic user) {
    final bioCtrl = TextEditingController(text: user.bio);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bio professionnelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Parlez un peu de vous ou de votre boutique. Cela sera visible lors de vos courses.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: bioCtrl,
              maxLines: 4,
              maxLength: 150,
              decoration: const InputDecoration(
                hintText: 'Ex: Livreur expérimenté sur Dakar Plateau...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref
                    .read(authProvider.notifier)
                    .updateProfile(bio: bioCtrl.text);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
