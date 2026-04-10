import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/error_utils.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Non connecte')));
    }

    final prefs = user.notificationPrefs;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildSectionTitle('Canaux de reception'),
                _buildToggle(
                  label: 'Notifications Push',
                  subtitle: 'Alertes en temps reel sur votre mobile',
                  value: prefs.pushEnabled,
                  onChanged: (v) => _updatePrefs(push: v),
                  icon: Icons.notifications_active_outlined,
                ),
                const Divider(),
                _buildToggle(
                  label: 'E-mail',
                  subtitle: 'Factures et recapitulatifs hebdomadaires',
                  value: prefs.emailEnabled,
                  onChanged: (v) => _updatePrefs(email: v),
                  icon: Icons.email_outlined,
                ),
                const Divider(),
                _buildToggle(
                  label: 'WhatsApp',
                  subtitle: 'Mises a jour de livraison par WhatsApp',
                  value: prefs.whatsappEnabled,
                  onChanged: (v) => _updatePrefs(whatsapp: v),
                  icon: Icons.message_outlined,
                ),
                const SizedBox(height: 32),
                _buildSectionTitle('Evenements'),
                _buildToggle(
                  label: 'Statut des colis',
                  subtitle: 'Chaque etape de la livraison de vos colis',
                  value: prefs.parcelUpdatesEnabled,
                  onChanged: (v) => _updatePrefs(parcelUpdates: v),
                  icon: Icons.local_shipping_outlined,
                ),
                const Divider(),
                _buildToggle(
                  label: 'Promotions',
                  subtitle: 'Offres speciales et codes promo',
                  value: prefs.promotionsEnabled,
                  onChanged: (v) => _updatePrefs(promotions: v),
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
        child: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.blue,
    );
  }

  Future<void> _updatePrefs({
    bool? push,
    bool? email,
    bool? whatsapp,
    bool? parcelUpdates,
    bool? promotions,
  }) async {
    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).valueOrNull?.user;
      if (user == null) {
        return;
      }

      final newPrefs = {
        'push': push ?? user.notificationPrefs.pushEnabled,
        'email': email ?? user.notificationPrefs.emailEnabled,
        'whatsapp': whatsapp ?? user.notificationPrefs.whatsappEnabled,
        'parcel_updates':
            parcelUpdates ?? user.notificationPrefs.parcelUpdatesEnabled,
        'promotions': promotions ?? user.notificationPrefs.promotionsEnabled,
      };

      await ref.read(authProvider.notifier).updateProfile(
            notificationPrefs: newPrefs,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
