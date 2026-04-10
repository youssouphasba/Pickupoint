import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/error_utils.dart';

class RelaySelectorModal extends ConsumerStatefulWidget {
  const RelaySelectorModal({super.key});

  @override
  ConsumerState<RelaySelectorModal> createState() => _RelaySelectorModalState();
}

class _RelaySelectorModalState extends ConsumerState<RelaySelectorModal> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  
  List<RelayPoint> _allRelays = [];
  List<RelayPoint> _filteredRelays = [];
  bool _isLoading = true;
  String? _error;
  Position? _currentPosition;
  
  // Dakar centroid (Utilisé par défaut si on n'a pas la position)
  static const LatLng _dakarCenter = LatLng(14.6928, -17.4467);

  @override
  void initState() {
    super.initState();
    _initLocationAndFetch();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocationAndFetch() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          _currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);
        }
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
    
    await _fetchRelays();
  }

  Future<void> _fetchRelays() async {
    try {
      setState(() { _isLoading = true; _error = null; });
      final api = ref.read(apiClientProvider);
      
      final res = _currentPosition != null 
          ? await api.getNearbyRelays(_currentPosition!.latitude, _currentPosition!.longitude)
          : await api.getRelayPoints(params: {'limit': 200}); // Fallback to all, avec une limite plus large
          
      final data = res.data as Map<String, dynamic>;
      final list = (data['relay_points'] as List? ?? [])
          .map((e) => RelayPoint.fromJson(e as Map<String, dynamic>))
          .toList();
          
      if (mounted) {
        setState(() {
          _allRelays = list;
          _filteredRelays = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _isLoading = false; });
    }
  }

  void _filterRelays(String query) {
    if (query.isEmpty) {
      setState(() => _filteredRelays = _allRelays);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredRelays = _allRelays.where((r) => 
        r.name.toLowerCase().contains(q) || 
        (r.district?.toLowerCase() ?? '').contains(q) ||
        r.city.toLowerCase().contains(q)
      ).toList();
    });
  }

  void _selectRelay(RelayPoint relay) {
    Navigator.of(context).pop(relay); // Renvoie le relais sélectionné
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Poignée drag
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40, height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Choisir un relais', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher par nom, quartier...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: _filterRelays,
            ),
          ),
          
          // MAP ou Loading
          Expanded(
            flex: 2,
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _error != null 
                ? Center(child: Text('Erreur: $_error', style: const TextStyle(color: Colors.red)))
                : _buildMapInfo(),
          ),
          
          // LISTE
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.grey.shade50,
              child: _isLoading 
                  ? const SizedBox() // géré en haut
                  : _filteredRelays.isEmpty
                    ? const Center(child: Text('Aucun relais trouvé'))
                    : ListView.separated(
                        itemCount: _filteredRelays.length,
                        separatorBuilder: (_,__) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = _filteredRelays[i];
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                              child: const Icon(Icons.storefront, color: Colors.blue),
                            ),
                            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r.district}, ${r.city}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                if (r.openingHours?['general'] != null && r.openingHours!['general'].toString().isNotEmpty)
                                  Text(
                                    '🕒 ${r.openingHours!["general"]}', 
                                    style: const TextStyle(fontSize: 12, color: Colors.green),
                                  ),
                                if (r.description != null && r.description!.isNotEmpty)
                                  Text(
                                    'ℹ️ ${r.description}', 
                                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.indigo),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            onTap: () => _selectRelay(r),
                            trailing: IconButton(
                              icon: const Icon(Icons.map_outlined, color: Colors.grey),
                              onPressed: () {
                                if (r.lat != null && r.lng != null && _mapController != null) {
                                  _mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(r.lat!, r.lng!), 15.0));
                                }
                              },
                            ),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapInfo() {
    final center = _currentPosition != null 
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : _dakarCenter;

    final Set<Marker> markers = {};

    // User position
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_pos'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    // Relays
    for (final r in _filteredRelays) {
      if (r.lat != null && r.lng != null) {
        markers.add(
          Marker(
            markerId: MarkerId(r.id),
            position: LatLng(r.lat!, r.lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            onTap: () => _selectRelay(r),
          ),
        );
      }
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: 13.0,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        if (_currentPosition == null && _filteredRelays.isNotEmpty) {
          final first = _filteredRelays.first;
          if (first.lat != null && first.lng != null) {
            controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(first.lat!, first.lng!), 13.0));
          }
        }
      },
      markers: markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      mapToolbarEnabled: true,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(
          () => EagerGestureRecognizer(),
        ),
      },
    );
  }
}
