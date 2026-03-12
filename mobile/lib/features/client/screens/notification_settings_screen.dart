import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    if (user == null) return const Scaffold(body: Center(child: Text('Non connecté')));
    
    final prefs = user.notificationPrefs;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionTitle('Canaux de réception'),
              _buildToggle(
                label: 'Notifications Push',
                subtitle: 'Alertes en temps réel sur votre mobile',
                value: prefs.pushEnabled,
                onChanged: (v) => _updatePrefs(push: v),
                icon: Icons.notifications_active_outlined,
              ),
              const Divider(),
              _buildToggle(
                label: 'E-mail',
                subtitle: 'Factures et récapitulatifs hebdomadaires',
                value: prefs.emailEnabled,
                onChanged: (v) => _updatePrefs(email: v),
                icon: Icons.email_outlined,
              ),
              const Divider(),
              _buildToggle(
                label: 'WhatsApp',
                subtitle: 'Mises à jour de livraison par WhatsApp',
                value: prefs.whatsappEnabled,
                onChanged: (v) => _updatePrefs(whatsapp: v),
                icon: Icons.message_outlined,
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('Événements'),
              _buildToggle(
                label: 'Statut des colis',
                subtitle: 'Chaque étape de la livraison de vos colis',
                value: true,
                onChanged: null, // Toujours activé pour l'instant
                icon: Icons.local_shipping_outlined,
              ),
              const Divider(),
              _buildToggle(
                label: 'Promotions',
                subtitle: 'Offres spéciales et codes promos',
                value: true,
                onChanged: null,
                icon: Icons.sell_outlined,
              ),
            ],
          ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildToggle({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required IconData icon,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(icon, color: Colors.blueGrey, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 32),
        child: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.blue,
    );
  }

  Future<void> _updatePrefs({bool? push, bool? email, bool? whatsapp}) async {
    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).valueOrNull?.user;
      if (user == null) return;

      final newPrefs = {
        'push': push ?? user.notificationPrefs.pushEnabled,
        'email': email ?? user.notificationPrefs.emailEnabled,
        'whatsapp': whatsapp ?? user.notificationPrefs.whatsappEnabled,
      };

      await ref.read(authProvider.notifier).updateProfile(
        notificationPrefs: newPrefs,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
