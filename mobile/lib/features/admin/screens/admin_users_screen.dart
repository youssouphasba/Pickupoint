import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../../core/models/relay_point.dart';
import 'admin_user_history_screen.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // 'all' | 'client' | 'relay_agent' | 'driver' | 'admin'

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion Utilisateurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminUsersProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Barre de recherche ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Rechercher par téléphone ou nom…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // ── Filtre par rôle ─────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _filterChip('Tous',     'all'),
                _filterChip('Clients',  'client'),
                _filterChip('Relais',   'relay_agent'),
                _filterChip('Livreurs', 'driver'),
                _filterChip('Admins',   'admin'),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Liste ───────────────────────────────────────────────────────
          Expanded(
            child: usersAsync.when(
              data: (users) {
                final query = _searchCtrl.text.toLowerCase();
                final filtered = users.where((u) {
                  final matchRole = _filter == 'all' || u.role == _filter;
                  final matchSearch = query.isEmpty ||
                      u.phone.contains(query) ||
                      (u.fullName?.toLowerCase().contains(query) ?? false);
                  return matchRole && matchSearch;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('Aucun utilisateur trouvé'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) => _UserTile(user: filtered[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Center(child: Text('Erreur: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      ),
    );
  }
}

// ── Tuile utilisateur avec actions ──────────────────────────────────────────
class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user});
  final User user;

  static const _roleLabels = {
    'client':      'Client',
    'relay_agent': 'Agent Relais',
    'driver':      'Livreur',
    'admin':       'Admin',
    'superadmin':  'Super Admin',
  };

  static const _roleColors = {
    'client':      Colors.grey,
    'relay_agent': Colors.orange,
    'driver':      Colors.blue,
    'admin':       Colors.purple,
    'superadmin':  Colors.red,
  };

  static const _roleIcons = {
    'client':      Icons.person,
    'relay_agent': Icons.store,
    'driver':      Icons.delivery_dining,
    'admin':       Icons.admin_panel_settings,
    'superadmin':  Icons.security,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _roleColors[user.role] ?? Colors.grey;
    final icon  = _roleIcons[user.role]  ?? Icons.person;
    final label = _roleLabels[user.role] ?? user.role;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        user.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.phone, style: const TextStyle(fontSize: 12)),
          if (user.relayPointId != null)
            Text('Relais: ${user.relayPointId}',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      onTap: () => _showUserActions(context, ref),
    );
  }

  void _showUserActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _UserActionsSheet(user: user, ref: ref),
    );
  }
}

// ── Bottom sheet d'actions ───────────────────────────────────────────────────
class _UserActionsSheet extends ConsumerStatefulWidget {
  const _UserActionsSheet({required this.user, required this.ref});
  final User user;
  final WidgetRef ref;

  @override
  ConsumerState<_UserActionsSheet> createState() => _UserActionsSheetState();
}

class _UserActionsSheetState extends ConsumerState<_UserActionsSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(children: [
            const Icon(Icons.manage_accounts, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.user.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(widget.user.phone, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          const Text('Changer le rôle',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 10),
          // Boutons de changement de rôle
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _roleButton(context, 'Client',      'client',      Icons.person,           Colors.grey),
                _roleButton(context, 'Livreur',     'driver',      Icons.delivery_dining,  Colors.blue),
                _roleButton(context, 'Agent Relais','relay_agent', Icons.store,            Colors.orange),
                _roleButton(context, 'Admin',       'admin',       Icons.admin_panel_settings, Colors.purple),
              ],
            ),
          // Si relay_agent : lier un point relais
          if (widget.user.role == 'relay_agent' || true) ...[
            const SizedBox(height: 20),
            const Text('Lier un point relais',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            _LinkRelayButton(user: widget.user),
          ],
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: const Text('Voir l\'historique d\'activité',
                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminUserHistoryScreen(
                    userId: widget.user.id,
                    userName: widget.user.name,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _roleButton(BuildContext context, String label, String role,
      IconData icon, Color color) {
    final isCurrent = widget.user.role == role;
    return OutlinedButton.icon(
      onPressed: isCurrent ? null : () => _changeRole(context, role),
      icon: Icon(icon, size: 16, color: isCurrent ? Colors.grey : color),
      label: Text(label,
          style: TextStyle(color: isCurrent ? Colors.grey : color, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: isCurrent ? Colors.grey.shade300 : color.withOpacity(0.5)),
        backgroundColor: isCurrent ? Colors.grey.shade100 : color.withOpacity(0.05),
      ),
    );
  }

  Future<void> _changeRole(BuildContext context, String role) async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.changeUserRole(widget.user.id, role);
      ref.invalidate(adminUsersProvider);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rôle de ${widget.user.name} changé en "$role" ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ── Widget pour lier un point relais ────────────────────────────────────────
class _LinkRelayButton extends ConsumerStatefulWidget {
  const _LinkRelayButton({required this.user});
  final User user;

  @override
  ConsumerState<_LinkRelayButton> createState() => _LinkRelayButtonState();
}

class _LinkRelayButtonState extends ConsumerState<_LinkRelayButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final relaysAsync = ref.watch(adminRelaysProvider);

    return relaysAsync.when(
      data: (relays) {
        if (relays.isEmpty) {
          return const Text('Aucun point relais disponible',
              style: TextStyle(color: Colors.grey, fontSize: 13));
        }
        return DropdownButtonFormField<String>(
          value: widget.user.relayPointId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: 'Sélectionner un relais…',
          ),
          items: relays.map((r) => DropdownMenuItem(
            value: r.id,
            child: Text('${r.name} — ${r.city}', style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: _loading ? null : (relayId) {
            if (relayId != null) _assignRelay(context, relayId);
          },
        );
      },
      loading: () => const SizedBox(height: 20, width: 20,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, __) => Text('Erreur relais: $e',
          style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }

  Future<void> _assignRelay(BuildContext context, String relayId) async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.assignRelayPoint(widget.user.id, relayId);
      ref.invalidate(adminUsersProvider);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Point relais lié avec succès ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
