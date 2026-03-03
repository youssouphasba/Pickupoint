import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/admin_provider.dart';
import '../../../core/auth/auth_provider.dart';

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
            final r = relays[index];
            return Card(
              child: ListTile(
                leading: Icon(Icons.store, color: r.isVerified ? Colors.green : Colors.grey),
                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r.city} - ${r.addressLabel}'),
                trailing: r.isVerified 
                  ? const Icon(Icons.verified, color: Colors.blue)
                  : ElevatedButton(
                      onPressed: () => _verifyRelay(context, ref, r.id),
                      child: const Text('Vérifier'),
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

  Future<void> _verifyRelay(BuildContext context, WidgetRef ref, String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.verifyRelay(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relais vérifié avec succès !')));
      ref.invalidate(adminRelaysProvider);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }
}
