import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/user.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/map_picker_modal.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FavoriteAddressesScreen extends ConsumerStatefulWidget {
  const FavoriteAddressesScreen({super.key});

  @override
  ConsumerState<FavoriteAddressesScreen> createState() => _FavoriteAddressesScreenState();
}

class _FavoriteAddressesScreenState extends ConsumerState<FavoriteAddressesScreen> {
  bool _loading = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    final favorites = user?.favoriteAddresses ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Mes Adresses Favorites')),
      body: favorites.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final addr = favorites[index];
                return _buildAddressCard(addr);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: favorites.length >= 10 ? null : _showAddAddressDialog,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
        backgroundColor: favorites.length >= 10 ? Colors.grey : Colors.blue,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Aucune adresse enregistrée',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enregistrez vos adresses fréquentes pour\ngagner du temps lors de vos envois.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(FavoriteAddress addr) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          child: const Icon(Icons.place, color: Colors.blue),
        ),
        title: Text(addr.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(addr.address, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(addr),
        ),
      ),
    );
  }

  void _showAddAddressDialog() {
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    LatLng? selectedLatLng;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle adresse'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom (ex: Maison, Bureau)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addrCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adresse complète',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final LatLng? result = await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const MapPickerModal(title: 'Localiser l\'adresse'),
                    );
                    if (result != null) {
                      setDialogState(() => selectedLatLng = result);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: selectedLatLng != null ? Colors.green : Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: selectedLatLng != null ? Colors.green.shade50 : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedLatLng != null ? Icons.location_on : Icons.map_outlined,
                          color: selectedLatLng != null ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedLatLng != null
                                ? 'Position sélectionnée ✅'
                                : 'Sélectionner sur la carte (GPS) *',
                            style: TextStyle(
                              color: selectedLatLng != null ? Colors.green.shade700 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isEmpty || addrCtrl.text.isEmpty || selectedLatLng == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Veuillez remplir tous les champs et choisir la position')),
                  );
                  return;
                }
                final name = nameCtrl.text.trim();
                final address = addrCtrl.text.trim();
                Navigator.pop(context);
                _addAddress(name, address, selectedLatLng!);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAddress(String name, String address, LatLng coords) async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.addFavoriteAddress({
        'name': name,
        'address': address,
        'lat': coords.latitude,
        'lng': coords.longitude,
      });
      await ref.read(authProvider.notifier).fetchMe();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Adresse "$name" ajoutée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirmDelete(FavoriteAddress addr) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l\'adresse ?'),
        content: Text('Voulez-vous vraiment supprimer "${addr.name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAddress(addr);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAddress(FavoriteAddress addr) async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteFavoriteAddress(addr.name);
      await ref.read(authProvider.notifier).fetchMe();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
