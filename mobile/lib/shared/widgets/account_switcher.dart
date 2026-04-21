import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_provider.dart';

/// Bouton de switch de compte dans l'AppBar.
/// À placer dans les `actions` de chaque home screen.
class AccountSwitcherButton extends ConsumerWidget {
  const AccountSwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider).valueOrNull;
    if (auth == null || !auth.isAuthenticated) return const SizedBox.shrink();

    final user         = auth.user!;
    final effectiveRole = auth.effectiveRole;

    // Un simple client sans rôle pro → pas de switcher
    if (user.role == 'client' ||
        user.role == 'admin' ||
        user.role == 'superadmin') {
      return const SizedBox.shrink();
    }

    // Rôle pro : driver ou relay_agent
    final isPro = effectiveRole == user.role; // vrai = on est en vue pro

    return PopupMenuButton<String>(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                isPro ? Colors.white24 : Colors.white,
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
            right: -2, bottom: -2,
            child: Container(
              width: 12, height: 12,
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
      onSelected: (value) => _onSwitch(context, ref, value),
      itemBuilder: (_) => [
        // En-tête informatif
        PopupMenuItem(
          enabled: false,
          height: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(user.phone,
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Vue Client
        _menuItem(
          value: 'client',
          icon: Icons.person,
          label: 'Mode Client',
          subtitle: 'Envoyer & recevoir des colis',
          isActive: effectiveRole == 'client',
          color: Colors.indigo,
        ),
        // Vue Pro (driver ou relay_agent)
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
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isActive ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18,
              color: isActive ? Colors.white : color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive ? color : null,
                      fontSize: 13)),
              if (isActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Actif',
                      style: TextStyle(color: color, fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            Text(subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  void _onSwitch(BuildContext context, WidgetRef ref, String newView) {
    final auth = ref.read(authProvider).valueOrNull;
    if (auth == null || auth.effectiveRole == newView) return;

    ref.read(authProvider.notifier).switchView(newView);

    // Naviguer vers le bon dashboard
    final route = switch (newView) {
      'driver'      => '/driver',
      'relay_agent' => '/relay',
      'admin'       => '/admin',
      _             => '/client',
    };
    context.go(route);

    // Feedback visuel
    final label = switch (newView) {
      'driver'      => 'Mode Livreur activé',
      'relay_agent' => 'Mode Point Relais activé',
      _             => 'Mode Client activé',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
