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
          final events = data['events'] as List;

          return DefaultTabController(
            length: 4,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Envoyés'),
                    Tab(text: 'Reçus'),
                    Tab(text: 'Missions'),
                    Tab(text: 'Audit'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildParcelList(sent, 'Aucun colis envoyé'),
                      _buildParcelList(received, 'Aucun colis reçu'),
                      _buildMissionList(missions),
                      _buildEventList(events),
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
          title: Text('Code: ${item['tracking_code']}'),
          subtitle: Text('Status: ${item['status']}\nDate: ${item['created_at'] != null ? formatDate(DateTime.parse(item['created_at'])) : "---"}'),
          isThreeLine: true,
        );
      },
    );
  }

  Widget _buildMissionList(List items) {
    if (items.isEmpty) return const Center(child: Text('Aucune mission effectuée'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          leading: const Icon(Icons.delivery_dining),
          title: Text('Mission: ${item['mission_id']}'),
          subtitle: Text('Status: ${item['status']}\nType: ${item['delivery_type']}'),
        );
      },
    );
  }

  Widget _buildEventList(List items) {
    if (items.isEmpty) return const Center(child: Text('Aucun événement enregistré'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return ListTile(
          leading: const Icon(Icons.history),
          title: Text(item['event_type']),
          subtitle: Text('Colis: ${item['parcel_id']}\nDate: ${item['created_at'] != null ? formatDate(DateTime.parse(item['created_at'])) : "---"}'),
        );
      },
    );
  }
}
