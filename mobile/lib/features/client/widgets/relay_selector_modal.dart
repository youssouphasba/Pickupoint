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
  const RelaySelectorModal({super.key, this.consultative = false});

  final bool consultative;

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
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          _currentPosition = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high)
              .timeout(const Duration(seconds: 10));
        }
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }

    await _fetchRelays();
  }

  Future<void> _fetchRelays() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final api = ref.read(apiClientProvider);

      var res = _currentPosition != null
          ? await api.getNearbyRelays(
              _currentPosition!.latitude, _currentPosition!.longitude)
          : await api.getRelayPoints(params: {'limit': 200});

      var data = res.data as Map<String, dynamic>;
      final nearbyRelays = data['relay_points'] as List? ?? const [];
      if (_currentPosition != null && nearbyRelays.isEmpty) {
        res = await api.getRelayPoints(params: {'limit': 200});
        data = res.data as Map<String, dynamic>;
      }
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
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _isLoading = false;
        });
      }
    }
  }

  void _filterRelays(String query) {
    if (query.isEmpty) {
      setState(() => _filteredRelays = _allRelays);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filteredRelays = _allRelays
          .where((r) =>
              r.name.toLowerCase().contains(q) ||
              r.addressLabel.toLowerCase().contains(q) ||
              (r.description?.toLowerCase().contains(q) ?? false) ||
              r.phone.toLowerCase().contains(q) ||
              (r.district?.toLowerCase() ?? '').contains(q) ||
              r.city.toLowerCase().contains(q))
          .toList();
    });
  }

  void _selectRelay(RelayPoint relay) {
    if (!widget.consultative) {
      Navigator.of(context).pop(relay);
      return;
    }

    final area = _relayArea(relay);
    final hours = _relayOpeningHours(relay);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(relay.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              if (relay.addressLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(relay.addressLabel.trim()),
              ],
              if (area.isNotEmpty)
                Text(area, style: const TextStyle(color: Colors.blueGrey)),
              if (relay.phone.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(relay.phone.trim()),
              ],
              if (hours != null) ...[
                const SizedBox(height: 8),
                Text('Horaires : $hours',
                    style: const TextStyle(color: Colors.green)),
              ],
              if (relay.description?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(relay.description!.trim()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _relayArea(RelayPoint relay) {
    final parts = <String>[];
    for (final value in [relay.district, relay.city]) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty &&
          !parts
              .any((part) => part.toLowerCase() == normalized.toLowerCase())) {
        parts.add(normalized);
      }
    }
    return parts.join(', ');
  }

  String? _relayOpeningHours(RelayPoint relay) {
    final hours = relay.openingHours;
    if (hours == null || hours.isEmpty) return null;
    final general = hours['general']?.toString().trim();
    if (general != null && general.isNotEmpty) return general;
    final entries = hours.entries
        .map((entry) =>
            MapEntry(entry.key.trim(), entry.value.toString().trim()))
        .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty)
        .map((entry) => '${entry.key}: ${entry.value}')
        .toList();
    return entries.isEmpty ? null : entries.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.consultative
          ? double.infinity
          : MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: widget.consultative
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Poignée drag
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 5,
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
                Text(
                  widget.consultative ? 'Points relais' : 'Choisir un relais',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
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
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    ? Center(
                        child: Text('Erreur: $_error',
                            style: const TextStyle(color: Colors.red)))
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
                      ? _buildEmptyState()
                      : ListView.separated(
                          itemCount: _filteredRelays.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = _filteredRelays[i];
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.storefront,
                                    color: Colors.blue),
                              ),
                              title: Text(r.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Builder(builder: (context) {
                                final area = _relayArea(r);
                                final address = r.addressLabel.trim();
                                final hours = _relayOpeningHours(r);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (address.isNotEmpty &&
                                        address.toLowerCase() !=
                                            area.toLowerCase())
                                      Text(
                                        address,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (area.isNotEmpty)
                                      Text(
                                        area,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blueGrey),
                                      ),
                                    if (r.phone.trim().isNotEmpty)
                                      Text(
                                        r.phone,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    if (hours != null)
                                      Text(
                                        'Horaires : $hours',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.green),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (r.description?.trim().isNotEmpty ==
                                        true)
                                      Text(
                                        r.description!.trim(),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.indigo),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                );
                              }),
                              onTap: () => _selectRelay(r),
                              trailing: IconButton(
                                icon: const Icon(Icons.map_outlined,
                                    color: Colors.grey),
                                onPressed: () {
                                  if (r.lat != null &&
                                      r.lng != null &&
                                      _mapController != null) {
                                    _mapController!.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                            LatLng(r.lat!, r.lng!), 15.0));
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_mall_directory_outlined,
                size: 44, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text(
              'Aucun relais ne correspond à votre recherche.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _fetchRelays,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
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
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
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
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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
            controller.animateCamera(CameraUpdate.newLatLngZoom(
                LatLng(first.lat!, first.lng!), 13.0));
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
