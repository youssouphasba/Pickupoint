import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../../shared/widgets/authenticated_avatar.dart';
import '../providers/admin_provider.dart';
import 'admin_user_detail_screen.dart';
import 'admin_user_history_screen.dart';
import '../../../shared/utils/error_utils.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _statusFilter = 'all';

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
        title: const Text('Utilisateurs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminUsersProvider),
          ),
        ],
      ),
      body: usersAsync.when(
        data: (users) {
          final filtered = users.where(_matchesFilters).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Nom, telephone, e-mail ou ID',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _UserSummaryRow(users: users),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _buildRoleChip('Tous', 'all'),
                    _buildRoleChip('Clients', 'client'),
                    _buildRoleChip('Relais', 'relay_agent'),
                    _buildRoleChip('Livreurs', 'driver'),
                    _buildRoleChip('Admins', 'admin'),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildStatusChip('Tous', 'all'),
                    _buildStatusChip('Actifs', 'active'),
                    _buildStatusChip('Suspendus', 'banned'),
                    _buildStatusChip('KYC ok', 'kyc_verified'),
                    _buildStatusChip(
                        'Telephone non verifie', 'phone_unverified'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun utilisateur ne correspond aux filtres.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) =>
                            _UserCard(user: filtered[index]),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  Widget _buildRoleChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _roleFilter == value,
        onSelected: (_) => setState(() => _roleFilter = value),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _statusFilter == value,
        onSelected: (_) => setState(() => _statusFilter = value),
      ),
    );
  }

  bool _matchesFilters(User user) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final matchesRole = _roleFilter == 'all' || user.role == _roleFilter;
    final matchesStatus = switch (_statusFilter) {
      'all' => true,
      'active' => user.isActive && !user.isBanned,
      'banned' => user.isBanned,
      'kyc_verified' => user.kycStatus == 'verified',
      'phone_unverified' => !user.isPhoneVerified,
      _ => true,
    };

    if (!matchesRole || !matchesStatus) {
      return false;
    }

    if (query.isEmpty) {
      return true;
    }

    return user.name.toLowerCase().contains(query) ||
        user.phone.toLowerCase().contains(query) ||
        (user.email ?? '').toLowerCase().contains(query) ||
        user.id.toLowerCase().contains(query);
  }
}

class _UserSummaryRow extends StatelessWidget {
  const _UserSummaryRow({required this.users});

  final List<User> users;

  @override
  Widget build(BuildContext context) {
    final drivers = users.where((user) => user.isDriver).length;
    final relayAgents = users.where((user) => user.isRelayAgent).length;
    final banned = users.where((user) => user.isBanned).length;
    final kycVerified =
        users.where((user) => user.kycStatus == 'verified').length;

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Livreurs',
            value: '$drivers',
            color: Colors.blue,
            icon: Icons.delivery_dining_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Relais',
            value: '$relayAgents',
            color: Colors.orange,
            icon: Icons.storefront,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'Suspendus',
            value: '$banned',
            color: Colors.red,
            icon: Icons.block_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryTile(
            label: 'KYC ok',
            value: '$kycVerified',
            color: Colors.green,
            icon: Icons.verified_user_outlined,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});

  final User user;

  static const _roleLabels = {
    'client': 'Client',
    'relay_agent': 'Agent relais',
    'driver': 'Livreur',
    'admin': 'Admin',
    'superadmin': 'Super admin',
  };

  static const _roleColors = {
    'client': Colors.grey,
    'relay_agent': Colors.orange,
    'driver': Colors.blue,
    'admin': Colors.purple,
    'superadmin': Colors.red,
  };

  static const _roleIcons = {
    'client': Icons.person,
    'relay_agent': Icons.store,
    'driver': Icons.delivery_dining,
    'admin': Icons.admin_panel_settings,
    'superadmin': Icons.security,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _roleColors[user.role] ?? Colors.grey;
    final icon = _roleIcons[user.role] ?? Icons.person;
    final label = _roleLabels[user.role] ?? user.role;
    final profilePicture = user.profilePictureUrl;
    final hasProfilePicture =
        profilePicture != null && profilePicture.trim().isNotEmpty;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminUserDetailScreen(userId: user.id),
          ),
        ),
        onLongPress: () => _showUserActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AuthenticatedAvatar(
                    imageUrl: hasProfilePicture ? profilePicture : null,
                    radius: 26,
                    backgroundColor: color.withValues(alpha: 0.15),
                    fallback: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(user.phone),
                        if ((user.email ?? '').isNotEmpty)
                          Text(
                            user.email!,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () => _showUserActions(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(label: label, color: color),
                  _InfoChip(
                    label: user.isBanned
                        ? 'Suspendu'
                        : (user.isActive ? 'Actif' : 'Inactif'),
                    color: user.isBanned
                        ? Colors.red
                        : (user.isActive ? Colors.green : Colors.grey),
                  ),
                  _InfoChip(
                    label: user.isPhoneVerified
                        ? 'Telephone verifie'
                        : 'Telephone non verifie',
                    color: user.isPhoneVerified ? Colors.green : Colors.orange,
                  ),
                  _InfoChip(
                    label: _kycLabel(user.kycStatus),
                    color: _kycColor(user.kycStatus),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (user.isDriver)
                Row(
                  children: [
                    Expanded(
                      child: _MetricLine(
                        icon: Icons.local_shipping_outlined,
                        label: 'Livraisons',
                        value: '${user.deliveriesCompleted}',
                      ),
                    ),
                    Expanded(
                      child: _MetricLine(
                        icon: Icons.star_outline,
                        label: 'Note',
                        value: user.averageRating.toStringAsFixed(1),
                      ),
                    ),
                    Expanded(
                      child: _MetricLine(
                        icon: Icons.payments_outlined,
                        label: 'Gains',
                        value: user.totalEarned.toStringAsFixed(0),
                      ),
                    ),
                  ],
                )
              else if (user.isRelayAgent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MetricLine(
                      icon: Icons.storefront,
                      label: 'Relais lie',
                      value: user.relayPointId ?? 'Aucun relais lie',
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _MetricLine(
                        icon: Icons.emoji_events_outlined,
                        label: 'Points',
                        value: '${user.loyaltyPoints}',
                      ),
                    ),
                    Expanded(
                      child: _MetricLine(
                        icon: Icons.person_add_alt_1_outlined,
                        label: 'Parrainage',
                        value:
                            user.referralCode.isEmpty ? '-' : user.referralCode,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _UserActionsSheet(user: user, ref: ref),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
          Row(
            children: [
              const Icon(Icons.manage_accounts, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      widget.user.phone,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    if ((widget.user.email ?? '').isNotEmpty)
                      Text(
                        widget.user.email!,
                        style: const TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Changer le role',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _roleButton('Client', 'client', Icons.person, Colors.grey),
                _roleButton(
                  'Livreur',
                  'driver',
                  Icons.delivery_dining,
                  Colors.blue,
                ),
                _roleButton(
                  'Agent relais',
                  'relay_agent',
                  Icons.store,
                  Colors.orange,
                ),
                _roleButton(
                  'Admin',
                  'admin',
                  Icons.admin_panel_settings,
                  Colors.purple,
                ),
              ],
            ),
          if (widget.user.role == 'relay_agent') ...[
            const SizedBox(height: 20),
            const Text(
              'Lier un point relais',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            _LinkRelayButton(user: widget.user),
          ],
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: const Text(
              'Voir historique utilisateur',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          const Divider(),
          ListTile(
            leading: Icon(
              widget.user.isBanned ? Icons.check_circle_outline : Icons.block,
              color: widget.user.isBanned ? Colors.green : Colors.red,
            ),
            title: Text(
              widget.user.isBanned
                  ? 'Debannir utilisateur'
                  : 'Bannir utilisateur',
              style: TextStyle(
                color: widget.user.isBanned ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: _loading ? null : () => _toggleBan(context),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBan(BuildContext context) async {
    final reason = await _askAdminReason(
      context: context,
      title: widget.user.isBanned
          ? 'Confirmer le debannissement'
          : 'Confirmer le bannissement',
      helper: widget.user.isBanned
          ? 'Explique pourquoi tu leves la suspension de ${widget.user.name}.'
          : 'Explique pourquoi tu suspends le compte de ${widget.user.name}.',
      confirmLabel: widget.user.isBanned ? 'Debannir' : 'Bannir',
      confirmColor: widget.user.isBanned ? Colors.green : Colors.red,
    );

    if (reason == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      if (widget.user.isBanned) {
        await api.unbanUser(widget.user.id, reason: reason);
      } else {
        await api.banUser(widget.user.id, reason: reason);
      }

      ref.invalidate(adminUsersProvider);

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.user.isBanned
                  ? 'Utilisateur debanni avec succes.'
                  : 'Utilisateur banni avec succes.',
            ),
            backgroundColor: widget.user.isBanned ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _askAdminReason({
    required BuildContext context,
    required String title,
    required String helper,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(helper),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Motif',
                  hintText: 'Exemple: fraude, documents invalides, correction',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 3) {
                  setDialogState(
                    () =>
                        errorText = 'Saisis un motif d au moins 3 caracteres.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  Widget _roleButton(
    String label,
    String role,
    IconData icon,
    Color color,
  ) {
    final isCurrent = widget.user.role == role;
    return OutlinedButton.icon(
      onPressed: isCurrent ? null : () => _changeRole(context, role),
      icon: Icon(icon, size: 16, color: isCurrent ? Colors.grey : color),
      label: Text(
        label,
        style: TextStyle(
          color: isCurrent ? Colors.grey : color,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color:
              isCurrent ? Colors.grey.shade300 : color.withValues(alpha: 0.5),
        ),
        backgroundColor:
            isCurrent ? Colors.grey.shade100 : color.withValues(alpha: 0.05),
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
            content: Text('Role de ${widget.user.name} change en "$role".'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

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
          return const Text(
            'Aucun point relais disponible.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: widget.user.relayPointId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText: 'Selectionner un relais',
          ),
          items: relays
              .map(
                (relay) => DropdownMenuItem<String>(
                  value: relay.id,
                  child: Text(
                    '${relay.name} - ${relay.city}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: _loading
              ? null
              : (relayId) {
                  if (relayId != null) {
                    _assignRelay(context, relayId);
                  }
                },
        );
      },
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (e, __) => Text(
        friendlyError(e),
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
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
            content: Text('Point relais lie avec succes.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

String _kycLabel(String status) {
  switch (status) {
    case 'verified':
      return 'KYC verifie';
    case 'pending':
      return 'KYC en attente';
    case 'rejected':
      return 'KYC rejete';
    default:
      return 'KYC non renseigne';
  }
}

Color _kycColor(String status) {
  switch (status) {
    case 'verified':
      return Colors.green;
    case 'pending':
      return Colors.orange;
    case 'rejected':
      return Colors.red;
    default:
      return Colors.grey;
  }
}
