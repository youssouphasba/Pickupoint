import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/providers/user_stats_provider.dart';
import '../../../shared/widgets/account_switcher.dart';

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    _buildActionsList(context, ref),
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
                   const Icon(Icons.verified, color: Colors.blueAccent, size: 20),
                   const SizedBox(width: 4),
                   Text(
                    user.phone,
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (user.kycStatus == 'verified') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.verified, color: Colors.white, size: 10),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
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
          backgroundColor: Colors.white.withOpacity(0.3),
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
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
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
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _buildLoyaltyProgress(dynamic user, AsyncValue<Map<String, dynamic>> statsAsync) {
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Statut $tier'.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('$points / $nextTierPoints PTS', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
            Text('Plus que ${nextTierPoints - points} points pour devenir $nextTier !', 
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _buildActionsList(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _buildActionCard([
          ListTile(
            leading: const Icon(Icons.switch_account_outlined),
            title: const Text('Changer de rôle (Debug)'),
            trailing: const AccountSwitcherButton(),
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
        const Text('PRÉFÉRENCES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
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
            onTap: () => _showEditBio(context, ref, user),
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
            leading: const Icon(Icons.share_outlined),
            title: const Text('Partager mon code parrainage'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Copy to clipboard or share
            },
          ),
        ]),
        const SizedBox(height: 20),
        _buildActionCard([
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Confidentialité'),
            onTap: () => context.push('/legal/privacy_policy'),
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
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      try {
        final response = await ref.read(apiClientProvider).uploadAvatar(File(image.path));
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo mise à jour !')));
           // Re-fetch user profile to update avatar everywhere
           ref.read(authProvider.notifier).fetchMe();
        }
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  void _showDigitalID(BuildContext context, dynamic user) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ID Digital PickuPoint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Présentez ce code QR à un agent relais pour identification.', 
                       textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            QrImageView(
              data: user.id,
              version: QrVersions.auto,
              size: 200.0,
            ),
            const SizedBox(height: 12),
            Text(user.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
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
              decoration: const InputDecoration(labelText: 'Nom (non modifiable)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(authProvider.notifier).updateProfile(email: emailCtrl.text);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                 if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(authProvider.notifier).updateProfile(bio: bioCtrl.text);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
