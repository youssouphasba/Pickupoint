import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../../shared/widgets/map_picker_modal.dart';

class FavoriteAddressesScreen extends ConsumerStatefulWidget {
  const FavoriteAddressesScreen({super.key});

  @override
  ConsumerState<FavoriteAddressesScreen> createState() =>
      _FavoriteAddressesScreenState();
}

class _FavoriteAddressesScreenState
    extends ConsumerState<FavoriteAddressesScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    final favorites = user?.favoriteAddresses ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Mes adresses favorites')),
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
        onPressed: favorites.length >= 10 ? null : () => _openAddressDialog(),
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
          Icon(
            Icons.location_off_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucune adresse enregistree',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gardez vos adresses frequentes pour gagner du temps a la creation.',
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
        title: Text(
          addr.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(addr.address, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              '${addr.lat.toStringAsFixed(5)}, ${addr.lng.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              _openAddressDialog(existing: addr);
            } else if (value == 'delete') {
              _confirmDelete(addr);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Modifier')),
            PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ],
        ),
      ),
    );
  }

  void _openAddressDialog({FavoriteAddress? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final addrCtrl = TextEditingController(text: existing?.address ?? '');
    LatLng? selectedLatLng = existing == null
        ? null
        : LatLng(existing.lat, existing.lng);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle adresse' : 'Modifier l adresse'),
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
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Adresse complete',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final result = await showModalBottomSheet<MapPickerResult>(
                      context: dialogContext,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const MapPickerModal(
                        title: 'Localiser l adresse',
                      ),
                    );
                    if (result != null) {
                      setDialogState(() {
                        selectedLatLng = result.position;
                        if (result.address != null && result.address!.isNotEmpty) {
                          addrCtrl.text = result.address!;
                        }
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selectedLatLng != null ? Colors.green : Colors.grey,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: selectedLatLng != null ? Colors.green.shade50 : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedLatLng != null
                              ? Icons.location_on
                              : Icons.map_outlined,
                          color:
                              selectedLatLng != null ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            selectedLatLng != null
                                ? 'Position selectionnee'
                                : 'Selectionner sur la carte',
                            style: TextStyle(
                              color: selectedLatLng != null
                                  ? Colors.green.shade700
                                  : Colors.grey.shade700,
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
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty ||
                    addrCtrl.text.trim().isEmpty ||
                    selectedLatLng == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Veuillez remplir tous les champs et choisir la position.',
                      ),
                    ),
                  );
                  return;
                }

                final name = nameCtrl.text.trim();
                final address = addrCtrl.text.trim();
                Navigator.pop(dialogContext);
                if (existing == null) {
                  _addAddress(name, address, selectedLatLng!);
                } else {
                  _updateAddress(existing.name, name, address, selectedLatLng!);
                }
              },
              child: Text(existing == null ? 'Enregistrer' : 'Mettre a jour'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      addrCtrl.dispose();
    });
  }

  Future<void> _addAddress(String name, String address, LatLng coords) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.addFavoriteAddress({
        'name': name,
        'address': address,
        'lat': coords.latitude,
        'lng': coords.longitude,
      });
      await ref.read(authProvider.notifier).fetchMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adresse "$name" ajoutee')),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _updateAddress(
    String currentName,
    String name,
    String address,
    LatLng coords,
  ) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.updateFavoriteAddress(currentName, {
        'name': name,
        'address': address,
        'lat': coords.latitude,
        'lng': coords.longitude,
      });
      await ref.read(authProvider.notifier).fetchMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adresse "$name" mise a jour')),
      );
    } catch (e) {
      _showError(e);
    }
  }

  void _confirmDelete(FavoriteAddress addr) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer l adresse ?'),
        content: Text('Voulez-vous vraiment supprimer "${addr.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteAddress(addr);
            },
            child: const Text(
              'Supprimer',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAddress(FavoriteAddress addr) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteFavoriteAddress(addr.name);
      await ref.read(authProvider.notifier).fetchMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Adresse "${addr.name}" supprimee')),
      );
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur: $error'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
