import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../features/driver/providers/driver_provider.dart';

class AccountSwitcherButton extends ConsumerWidget {
  const AccountSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).valueOrNull;
    if (auth == null || !auth.isAuthenticated) return const SizedBox.shrink();

    final user = auth.user!;
    final effectiveRole = auth.effectiveRole;

    if (user.role == 'client' ||
        user.role == 'admin' ||
        user.role == 'superadmin') {
      return const SizedBox.shrink();
    }

    final isPro = effectiveRole == user.role;

    return PopupMenuButton<String>(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isPro ? Colors.white24 : Colors.white,
            child: Icon(
              effectiveRole == 'client'
                  ? Icons.person
                  : effectiveRole == 'driver'
                      ? Icons.delivery_dining
                      : Icons.store,
              size: 18,
              color: isPro ? Colors.white : Theme.of(context).primaryColor,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      tooltip: 'Changer de compte',
      onSelected: (value) {
        _onSwitch(context, ref, value);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          height: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                user.phone,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        _menuItem(
          value: 'client',
          icon: Icons.person,
          label: 'Mode Client',
          subtitle: 'Envoyer & recevoir des colis',
          isActive: effectiveRole == 'client',
          color: Colors.indigo,
        ),
        _menuItem(
          value: user.role,
          icon: user.role == 'driver' ? Icons.delivery_dining : Icons.store,
          label: user.role == 'driver' ? 'Mode Livreur' : 'Mode Point Relais',
          subtitle: user.role == 'driver'
              ? 'Voir mes missions & gains'
              : 'Gérer mon stock & scanner',
          isActive: effectiveRole == user.role,
          color: user.role == 'driver' ? Colors.blue : Colors.orange,
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isActive,
    required Color color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isActive ? color : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: isActive ? Colors.white : color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isActive ? color : null,
                        fontSize: 13,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Actif',
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSwitch(
    BuildContext context,
    WidgetRef ref,
    String newView,
  ) async {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth == null || auth.effectiveRole == newView) return;

    if (!await _canSwitch(context, ref, auth.user?.role, newView)) return;
    if (!context.mounted) return;

    ref.read(authProvider.notifier).switchView(newView);

    final route = switch (newView) {
      'driver' => '/driver',
      'relay_agent' => '/relay',
      'admin' => '/admin',
      _ => '/client',
    };
    context.go(route);

    final label = switch (newView) {
      'driver' => 'Mode Livreur activé',
      'relay_agent' => 'Mode Point Relais activé',
      _ => 'Mode Client activé',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _canSwitch(
    BuildContext context,
    WidgetRef ref,
    String? role,
    String newView,
  ) async {
    if (role != 'driver' || newView != 'client') return true;

    try {
      final canLeave = await canLeaveDriverAccount(ref);
      if (canLeave) return true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terminez ou libérez votre course active avant de passer en vue client.',
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
}
