import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/utils/error_utils.dart';

class AdminUserHistoryScreen extends ConsumerWidget {
  final String userId;
  final String userName;

  const AdminUserHistoryScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(adminUserHistoryProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Historique : $userName'),
      ),
      body: historyAsync.when(
        data: (data) {
          final sent = data['parcels_sent'] as List;
          final received = data['parcels_received'] as List;
          final missions = data['missions'] as List;
          final timeline = data['timeline'] as List? ?? const [];

          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Activit\u00e9'),
                    Tab(text: 'Envoy\u00e9s'),
                    Tab(text: 'Re\u00e7us'),
                    Tab(text: 'Missions'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTimelineList(timeline),
                      _buildParcelList(sent, 'Aucun colis envoy\u00e9'),
                      _buildParcelList(received, 'Aucun colis re\u00e7u'),
                      _buildMissionList(missions),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  Widget _buildParcelList(List items, String emptyMsg) {
    if (items.isEmpty) return Center(child: Text(emptyMsg));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          leading: const Icon(Icons.inventory_2),
          title: Text('Code : ${item['tracking_code']}'),
          subtitle: Text(
            'Statut : ${item['status']}\\nDate : ${item['created_at'] != null ? formatDate(DateTime.parse(item['created_at'])) : "---"}',
          ),
          isThreeLine: true,
        );
      },
    );
  }

  Widget _buildMissionList(List items) {
    if (items.isEmpty) {
      return const Center(child: Text('Aucune mission effectu\u00e9e'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          leading: const Icon(Icons.delivery_dining),
          title: Text('Mission : ${item['mission_id']}'),
          subtitle: Text(
            'Statut : ${item['status']}\\nType : ${item['delivery_type']}',
          ),
        );
      },
    );
  }

  Widget _buildTimelineList(List items) {
    if (items.isEmpty) {
      return const Center(child: Text('Aucune activit\u00e9 enregistr\u00e9e'));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = Map<String, dynamic>.from(items[i] as Map);
        final subtitle = item['subtitle']?.toString();
        final referenceId = item['reference_id']?.toString();
        final occurredAt = item['occurred_at']?.toString();
        final dateLabel = occurredAt != null && occurredAt.isNotEmpty
            ? formatDate(DateTime.parse(occurredAt))
            : '---';

        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(item['title']?.toString() ?? 'Activit\u00e9'),
          subtitle: Text(
            [
              if (subtitle != null && subtitle.isNotEmpty) subtitle,
              if (referenceId != null && referenceId.isNotEmpty)
                'R\u00e9f\u00e9rence : $referenceId',
              'Date : $dateLabel',
            ].join('\\n'),
          ),
          isThreeLine: true,
        );
      },
    );
  }
}
