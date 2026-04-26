import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';
import '../utils/error_utils.dart';

final unreadNotificationsCountProvider = StreamProvider.autoDispose<int>((
  ref,
) async* {
  final api = ref.watch(apiClientProvider);
  yield* Stream.periodic(const Duration(seconds: 60), (_) => null)
      .asyncMap((_) async {
    try {
      final res = await api.getUnreadNotificationsCount();
      return (res.data['unread_count'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }).startWith(await _initialUnread(api));
});

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}

Future<int> _initialUnread(ApiClient api) async {
  try {
    final res = await api.getUnreadNotificationsCount();
    return (res.data['unread_count'] as int?) ?? 0;
  } catch (_) {
    return 0;
  }
}

final notificationsListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, bool>((ref, unreadOnly) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getNotifications(unreadOnly: unreadOnly, limit: 50);
  final raw = (res.data['notifications'] as List? ?? const []);
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
});

class NotificationsInboxScreen extends ConsumerStatefulWidget {
  const NotificationsInboxScreen({
    super.key,
    this.settingsRoute,
    this.parcelDetailsRoutePrefix,
  });

  final String? settingsRoute;
  final String? parcelDetailsRoutePrefix;

  @override
  ConsumerState<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState
    extends ConsumerState<NotificationsInboxScreen> {
  bool _unreadOnly = false;

  Future<void> _refresh() async {
    ref.invalidate(notificationsListProvider(_unreadOnly));
    ref.invalidate(unreadNotificationsCountProvider);
  }

  Future<void> _markAllRead() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.markAllNotificationsRead();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _open(Map<String, dynamic> notif) async {
    final notifId = notif['notif_id'] as String?;
    final wasUnread = notif['read_at'] == null;
    final api = ref.read(apiClientProvider);
    if (notifId != null && wasUnread) {
      try {
        await api.markNotificationRead(notifId);
      } catch (_) {}
    }
    if (!mounted) return;
    final href = _hrefFor(notif);
    if (href != null) {
      context.push(href);
    }
    await _refresh();
  }

  String? _hrefFor(Map<String, dynamic> notif) {
    final refType = notif['ref_type'] as String?;
    final refId = notif['ref_id'] as String?;
    if (refType == 'parcel' &&
        refId != null &&
        refId.isNotEmpty &&
        widget.parcelDetailsRoutePrefix != null) {
      return '${widget.parcelDetailsRoutePrefix}/$refId';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(notificationsListProvider(_unreadOnly));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Tout marquer comme lu',
            icon: const Icon(Icons.done_all),
            onPressed: _markAllRead,
          ),
          if (widget.settingsRoute != null)
            IconButton(
              tooltip: 'Réglages',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push(widget.settingsRoute!),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Toutes'),
                  selected: !_unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Non lues'),
                  selected: _unreadOnly,
                  onSelected: (_) => setState(() => _unreadOnly = true),
                ),
              ],
            ),
          ),
        ),
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (items) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Aucune notification.',
                            style: TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = items[index];
                final unread = n['read_at'] == null;
                final title = n['title'] as String? ?? '—';
                final body = n['body'] as String? ?? '';
                final createdAt = _formatDate(n['created_at']);
                return ListTile(
                  onTap: () => _open(n),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          unread ? Colors.blue.shade50 : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(n),
                      color: unread ? Colors.blue : Colors.grey.shade600,
                    ),
                  ),
                  title: Text(
                    title,
                    style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        createdAt,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  trailing: unread
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

IconData _iconFor(Map<String, dynamic> n) {
  final ref = n['ref_type'] as String?;
  if (ref == 'parcel') return Icons.local_shipping_outlined;
  if (ref == 'wallet') return Icons.account_balance_wallet_outlined;
  if (ref == 'mission') return Icons.assignment_outlined;
  return Icons.notifications_outlined;
}

String _formatDate(Object? value) {
  if (value == null) return '';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return '';
  final local = parsed.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
