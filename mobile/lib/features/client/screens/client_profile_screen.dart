import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/providers/user_stats_provider.dart';
import '../../driver/providers/driver_provider.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../../../shared/widgets/authenticated_avatar.dart';
import '../../../shared/widgets/change_pin_tile.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/utils/currency_format.dart';
import '../widgets/client_loyalty_card.dart';

class ClientProfileScreen extends ConsumerStatefulWidget {
  const ClientProfileScreen({super.key, this.initialSection});

  final String? initialSection;

  @override
  ConsumerState<ClientProfileScreen> createState() =>
      _ClientProfileScreenState();
}

class _ClientProfileScreenState extends ConsumerState<ClientProfileScreen> {
  final _scrollController = ScrollController();
  final _statsKey = GlobalKey();
  final _loyaltyKey = GlobalKey();
  final _settingsKey = GlobalKey();
  final _referralKey = GlobalKey();
  final _supportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollToInitialSection();
  }

  @override
  void didUpdateWidget(covariant ClientProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _scrollToInitialSection();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToInitialSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _sectionContext(widget.initialSection);
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    });
  }

  BuildContext? _sectionContext(String? section) {
    final key = switch ((section ?? '').trim().toLowerCase()) {
      'stats' || 'kpis' => _statsKey,
      'loyalty' || 'fidelity' => _loyaltyKey,
      'settings' || 'preferences' || 'security' => _settingsKey,
      'referral' || 'parrainage' => _referralKey,
      'support' => _supportKey,
      _ => null,
    };
    return key?.currentContext;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider).valueOrNull;
    final statsAsync = ref.watch(userStatsProvider);
    final user = authState?.user;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Non connecté')));
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(userStatsProvider.future),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            _buildSliverAppBar(context, ref, user),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyedSubtree(
                      key: _statsKey,
                      child: _buildStatsRow(context, statsAsync),
                    ),
                    const SizedBox(height: 24),
                    KeyedSubtree(
                      key: _loyaltyKey,
                      child: const ClientLoyaltyCard(),
                    ),
                    const SizedBox(height: 24),
                    _buildActionsList(context, ref, user),
                    const SizedBox(height: 40),
                    _buildLogoutButton(context, ref),
                    const SizedBox(height: 12),
                    _buildDeleteAccountButton(context, ref),
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
          child: AuthenticatedAvatar(
            imageUrl: user.profilePictureUrl ?? user.avatarUrl,
            radius: 50,
            backgroundColor: Colors.white,
            fallback: const Icon(Icons.person, size: 50, color: Colors.grey),
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

  Widget _buildStatsRow(
    BuildContext context,
    AsyncValue<Map<String, dynamic>> statsAsync,
  ) {
    return statsAsync.when(
      data: (stats) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.25,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          _buildStatItem(
            context,
            'Colis envoyés',
            '${stats['parcels_sent'] ?? 0}',
            Icons.outbox_outlined,
            Colors.blue,
            'Nombre total de colis que vous avez créés.',
          ),
          _buildStatItem(
            context,
            'Colis reçus',
            '${stats['parcels_received'] ?? 0}',
            Icons.move_to_inbox_outlined,
            Colors.teal,
            'Nombre total de colis envoyés à votre numéro.',
          ),
          _buildStatItem(
            context,
            'En cours',
            '${stats['parcels_active'] ?? 0}',
            Icons.local_shipping_outlined,
            Colors.orange,
            'Colis envoyés ou reçus qui ne sont pas encore terminés.',
          ),
          _buildStatItem(
            context,
            'Colis livrés',
            '${stats['parcels_delivered'] ?? 0}',
            Icons.verified_outlined,
            Colors.green,
            'Nombre de colis envoyés ou reçus qui ont été livrés.',
          ),
          _buildStatItem(
            context,
            'Colis annulés',
            '${stats['parcels_cancelled'] ?? 0}',
            Icons.cancel_outlined,
            Colors.red,
            'Nombre de colis envoyés ou reçus qui ont été annulés.',
          ),
          _buildStatItem(
            context,
            'Dépenses ce mois',
            formatXof(
              (stats['client_monthly_spent_xof'] as num?)?.toDouble() ?? 0,
            ),
            Icons.payments_outlined,
            Colors.indigo,
            'Montant des livraisons que vous avez payées ce mois-ci.',
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => const Text('Erreur stats'),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
    String explanation,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showKpiInfo(context, label, explanation),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const Spacer(),
                Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _showKpiInfo(BuildContext context, String title, String message) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontSize: 14, height: 1.35)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsList(
    BuildContext context,
    WidgetRef ref,
    dynamic user,
  ) {
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
        const Text(
          'PRÉFÉRENCES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: _settingsKey,
          child: _buildActionCard([
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
            const ChangePinTile(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Ma Bio professionnelle'),
              trailing: const Icon(Icons.edit, size: 18, color: Colors.blue),
              onTap: () => _showEditBio(
                  context, ref, ref.read(authProvider).valueOrNull?.user),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        KeyedSubtree(
          key: _referralKey,
          child: _buildActionCard([
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Mes statistiques'),
              subtitle: const Text('Activité, délais et dépenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/client/statistics'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historique de fidélité'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/client/loyalty-history'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.card_giftcard_outlined),
              title: const Text('Mon parrainage'),
              subtitle: const Text('Invitations, objectifs et paiements'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/client/referral'),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        KeyedSubtree(
          key: _supportKey,
          child: _buildActionCard([
            const SupportWhatsAppTile(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_shared_outlined),
              title: const Text('Mes données'),
              subtitle: const Text('Consulter ou télécharger mes données'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/my-data'),
            ),
            const Divider(height: 1),
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
        ),
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

  Future<bool> _canLeaveClientAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user?.role != 'driver') return true;

    try {
      final canLeave = await canLeaveDriverAccount(ref);
      if (canLeave) return true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terminez ou libérez votre course active avant de quitter votre compte.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de vérifier vos courses en cours. Réessayez dans un instant.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: Colors.red),
      onPressed: () async {
        if (!await _canLeaveClientAccount(context, ref)) return;
        if (!context.mounted) return;
        await ref.read(authProvider.notifier).logout();
      },
      icon: const Icon(Icons.logout),
      label: const Text('Se déconnecter'),
    );
  }

  Widget _buildDeleteAccountButton(BuildContext context, WidgetRef ref) {
    return Center(
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
        onPressed: () => _confirmDeleteAccount(context, ref),
        icon: const Icon(Icons.delete_forever_outlined),
        label: const Text('Supprimer mon compte'),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    if (!await _canLeaveClientAccount(context, ref)) return;
    if (!context.mounted) return;

    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: const Text(
          'Cette action supprimera votre accès, effacera vos sessions et anonymisera vos informations personnelles. Elle ne peut pas être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !context.mounted) return;

    final controller = TextEditingController();
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmation finale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tapez SUPPRIMER pour confirmer la suppression.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'SUPPRIMER',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext)
                .pop(controller.text.trim().toUpperCase() == 'SUPPRIMER'),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (secondConfirm != true || !context.mounted) return;

    try {
      await ref.read(authProvider.notifier).deleteAccount();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte supprimé.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null) {
      try {
        await ref.read(apiClientProvider).uploadAvatar(File(image.path));
        await ref.read(authProvider.notifier).fetchMe();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Photo mise à jour !')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
                      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
                      .showSnackBar(SnackBar(content: Text(friendlyError(e))));
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
