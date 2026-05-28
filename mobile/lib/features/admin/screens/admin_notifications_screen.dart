import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../../shared/utils/error_utils.dart';
import '../providers/admin_provider.dart';

class AdminNotificationsScreen extends ConsumerStatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  ConsumerState<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState
    extends ConsumerState<AdminNotificationsScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final Set<String> _selectedUserIds = {};
  String _category = 'admin';
  String _targetMode = 'role';
  String _role = 'client';
  bool _includeInactive = false;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Envoyer'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SendNotificationTab(
              titleCtrl: _titleCtrl,
              bodyCtrl: _bodyCtrl,
              searchCtrl: _searchCtrl,
              selectedUserIds: _selectedUserIds,
              category: _category,
              targetMode: _targetMode,
              role: _role,
              includeInactive: _includeInactive,
              sending: _sending,
              onCategoryChanged: (value) => setState(() => _category = value),
              onTargetModeChanged: (value) =>
                  setState(() => _targetMode = value),
              onRoleChanged: (value) => setState(() => _role = value),
              onIncludeInactiveChanged: (value) =>
                  setState(() => _includeInactive = value),
              onToggleUser: _toggleUser,
              onSend: _send,
            ),
            const _NotificationHistoryTab(),
          ],
        ),
      ),
    );
  }

  void _toggleUser(String userId, bool selected) {
    setState(() {
      if (selected) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
    });
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.length < 2 || body.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titre et message obligatoires.')),
      );
      return;
    }
    if (_targetMode == 'users' && _selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez au moins un utilisateur.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final payload = {
        'title': title,
        'body': body,
        'category': _category,
        'include_inactive': _includeInactive,
        'user_ids': _targetMode == 'users' ? _selectedUserIds.toList() : [],
        if (_targetMode == 'role') 'role': _role,
      };
      final res =
          await ref.read(apiClientProvider).sendAdminNotification(payload);
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _selectedUserIds.clear();
      ref.invalidate(adminNotificationBroadcastsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Notification envoyée à ${data['sent'] ?? 0}/${data['matched'] ?? 0} utilisateur(s).',
          ),
        ),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}

class _SendNotificationTab extends ConsumerWidget {
  const _SendNotificationTab({
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.searchCtrl,
    required this.selectedUserIds,
    required this.category,
    required this.targetMode,
    required this.role,
    required this.includeInactive,
    required this.sending,
    required this.onCategoryChanged,
    required this.onTargetModeChanged,
    required this.onRoleChanged,
    required this.onIncludeInactiveChanged,
    required this.onToggleUser,
    required this.onSend,
  });

  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final TextEditingController searchCtrl;
  final Set<String> selectedUserIds;
  final String category;
  final String targetMode;
  final String role;
  final bool includeInactive;
  final bool sending;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onTargetModeChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final void Function(String userId, bool selected) onToggleUser;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Titre',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 90,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 600,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'messages', child: Text('Message')),
                    DropdownMenuItem(
                        value: 'promotions', child: Text('Promotion')),
                    DropdownMenuItem(
                        value: 'parcel_updates', child: Text('Colis')),
                  ],
                  onChanged: (value) {
                    if (value != null) onCategoryChanged(value);
                  },
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'role', label: Text('Par rôle')),
                    ButtonSegment(
                        value: 'users', label: Text('Sélection multiple')),
                  ],
                  selected: {targetMode},
                  onSelectionChanged: (values) =>
                      onTargetModeChanged(values.first),
                ),
                const SizedBox(height: 16),
                if (targetMode == 'role') ...[
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(
                      labelText: 'Rôle cible',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'client', child: Text('Clients')),
                      DropdownMenuItem(
                          value: 'driver', child: Text('Livreurs')),
                      DropdownMenuItem(
                          value: 'relay_agent', child: Text('Relais')),
                      DropdownMenuItem(value: 'admin', child: Text('Admins')),
                    ],
                    onChanged: (value) {
                      if (value != null) onRoleChanged(value);
                    },
                  ),
                ] else ...[
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Rechercher un utilisateur',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  usersAsync.when(
                    data: (users) => ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchCtrl,
                      builder: (context, value, _) => _UserSelectionList(
                        users: _filterUsers(users, value.text),
                        selectedUserIds: selectedUserIds,
                        onToggleUser: onToggleUser,
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Text(friendlyError(error)),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeInactive,
                  onChanged: onIncludeInactiveChanged,
                  title: const Text('Inclure les comptes inactifs ou bannis'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: sending ? null : onSend,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(sending ? 'Envoi...' : 'Envoyer'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<User> _filterUsers(List<User> users, String search) {
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users.where((user) {
      final haystack = '${user.name} ${user.phone} ${user.role}'.toLowerCase();
      return haystack.contains(query);
    }).toList();
  }
}

class _UserSelectionList extends StatelessWidget {
  const _UserSelectionList({
    required this.users,
    required this.selectedUserIds,
    required this.onToggleUser,
  });

  final List<User> users;
  final Set<String> selectedUserIds;
  final void Function(String userId, bool selected) onToggleUser;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Aucun utilisateur trouvé.'),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = users[index];
          final checked = selectedUserIds.contains(user.id);
          return CheckboxListTile(
            value: checked,
            onChanged: (value) => onToggleUser(user.id, value ?? false),
            title: Text(user.name),
            subtitle: Text('${user.phone} · ${_roleLabel(user.role)}'),
          );
        },
      ),
    );
  }
}

class _NotificationHistoryTab extends ConsumerWidget {
  const _NotificationHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(adminNotificationBroadcastsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminNotificationBroadcastsProvider.future),
      child: historyAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                Center(child: Text('Aucune notification envoyée.')),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.notifications_active_outlined),
                  ),
                  title: Text((item['title'] ?? '').toString()),
                  subtitle: Text(
                    [
                      (item['body'] ?? '').toString(),
                      _targetLabel(item),
                      _pushLabel(item),
                      _dateLabel(item['created_at']),
                    ].where((value) => value.isNotEmpty).join('\n'),
                  ),
                  trailing: Text(
                    '${item['sent_count'] ?? 0}/${item['matched_count'] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [Text(friendlyError(error))],
        ),
      ),
    );
  }

  String _targetLabel(Map<String, dynamic> item) {
    final role = item['target_role']?.toString();
    final requested = item['requested_user_ids'];
    if (role != null && role.isNotEmpty) {
      return 'Cible : ${_roleLabel(role)}';
    }
    if (requested is List && requested.isNotEmpty) {
      return 'Cible : ${requested.length} utilisateur(s) sélectionné(s)';
    }
    return '';
  }

  String _pushLabel(Map<String, dynamic> item) {
    final sent = item['push_sent_count'] ?? 0;
    final failed = item['push_failed_count'] ?? 0;
    final skipped = item['push_skipped_count'] ?? 0;
    final reasons = item['push_reasons'];
    final reasonText = reasons is Map
        ? reasons.entries
            .map((entry) =>
                '${_pushReasonLabel(entry.key.toString())}: ${entry.value}')
            .join(' · ')
        : '';
    final summary = '$sent push envoyés · $failed échec · $skipped ignoré';
    return reasonText.isEmpty ? summary : '$summary\n$reasonText';
  }

  String _pushReasonLabel(String reason) {
    switch (reason) {
      case 'missing_fcm_token':
        return 'token absent';
      case 'push_disabled':
        return 'push désactivé';
      case 'firebase_not_configured':
        return 'Firebase non configuré';
      case 'category_disabled':
        return 'catégorie désactivée';
      case 'user_not_found':
        return 'utilisateur introuvable';
      default:
        return reason;
    }
  }

  String _dateLabel(dynamic value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return '';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} à $hour:$minute';
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'driver':
      return 'Livreur';
    case 'relay_agent':
      return 'Relais';
    case 'admin':
      return 'Admin';
    case 'superadmin':
      return 'Super admin';
    default:
      return 'Client';
  }
}
