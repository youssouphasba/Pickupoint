import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/account_switcher.dart';

class ClientProfileScreen extends ConsumerWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon Profil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 50,
            child: Icon(Icons.person, size: 50),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              authState?.user?.phone ?? 'Non connecté',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Center(
            child: Text(
              'Rôle actif : ${authState?.effectiveRole ?? ''}',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 40),
          
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.switch_account),
                  title: const Text('Changer de rôle (Test)'),
                  trailing: const AccountSwitcherButton(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.handshake_outlined),
                  title: const Text('Devenir partenaire (Relais/Livreur)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/client/partnership'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // ── Section Fidélité & Parrainage ──────────────────────────
          if (authState?.user != null)
            _buildLoyaltyCard(context, authState!.user!),

          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Aide et Contact'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact support : +221 77 000 00 00')),
                );
              },
            ),
          ),
          const SizedBox(height: 30),
          
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red.shade700,
              minimumSize: const Size(double.infinity, 50),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyCard(BuildContext context, dynamic user) {
    final tierColor = user.loyaltyTier == 'gold' 
        ? Colors.amber.shade700 
        : user.loyaltyTier == 'silver' 
            ? Colors.blueGrey 
            : Colors.brown.shade400;

    return Card(
      elevation: 0,
      color: tierColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tierColor.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: tierColor, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Membre ${user.loyaltyTier.toUpperCase()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: tierColor,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${user.loyaltyPoints} points cumulés',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Votre code parrainage', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      user.referralCode.isNotEmpty ? user.referralCode : '---',
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: user.referralCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copié !')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copier'),
                ),
              ],
            ),
            const Divider(height: 16),
            TextButton.icon(
              onPressed: () => context.push('/client/loyalty-history'),
              icon: const Icon(Icons.history, size: 20),
              label: const Text('Voir l\'historique des gains et bonus'),
            ),
          ],
        ),
      ),
    );
  }
}
