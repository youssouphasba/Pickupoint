import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../providers/admin_provider.dart';
import 'admin_relay_detail_screen.dart';

class AdminRelaysScreen extends ConsumerWidget {
  const AdminRelaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relaysAsync = ref.watch(adminRelaysProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Points Relais')),
      body: relaysAsync.when(
        data: (relays) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: relays.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final relay = relays[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: relay.isVerified
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.store,
                    color: relay.isVerified ? Colors.green : Colors.orange,
                  ),
                ),
                title: Text(
                  relay.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${relay.city} - ${relay.addressLabel}\n${relay.phone}',
                ),
                isThreeLine: true,
                trailing: relay.isVerified
                    ? const Icon(Icons.verified, color: Colors.blue)
                    : ElevatedButton(
                        onPressed: () => _verifyRelay(context, ref, relay.id),
                        child: const Text('Verifier'),
                      ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AdminRelayDetailScreen(relayId: relay.id),
                  ),
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  Future<void> _verifyRelay(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.verifyRelay(id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relais verifie avec succes !')),
      );
      ref.invalidate(adminRelaysProvider);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }
}
