import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../../core/models/relay_point.dart';
import '../../../shared/widgets/relay_opening_hours_editor.dart';
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
  Timer? _searchTimer;

  List<RelayPoint> _allRelays = [];
  List<RelayPoint> _filteredRelays = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _error;
  Position? _currentPosition;
  BitmapDescriptor? _relayMarkerIcon;

  // Dakar centroid (Utilisé par défaut si on n'a pas la position)
  static const LatLng _dakarCenter = LatLng(14.6928, -17.4467);

  @override
  void initState() {
    super.initState();
    _initLocationAndFetch();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocationAndFetch() async {
    try {
      _relayMarkerIcon = await _buildRelayMarkerIcon();
    } catch (e) {
      debugPrint('Relay marker error: $e');
    }
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
      debugPrint('Location error: $e');
    }

    await _fetchRelays();
  }

  Future<BitmapDescriptor> _buildRelayMarkerIcon() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final background = ui.Paint()..color = const Color(0xFF1976D2);
    final foreground = ui.Paint()
      ..color = Colors.white
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const ui.Offset(size / 2, size / 2), 44, background);
    final storefront = ui.Path()
      ..moveTo(25, 43)
      ..lineTo(71, 43)
      ..lineTo(66, 30)
      ..lineTo(30, 30)
      ..close();
    canvas.drawPath(storefront, foreground);
    canvas.drawRect(const ui.Rect.fromLTWH(30, 43, 36, 27), foreground);
    final door = ui.Paint()..color = const Color(0xFF1976D2);
    canvas.drawRect(const ui.Rect.fromLTWH(44, 53, 12, 17), door);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    return BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: 48,
      height: 48,
    );
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
    _searchTimer?.cancel();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      setState(() => _filteredRelays = _allRelays);
      return;
    }
    final q = normalizedQuery.toLowerCase();
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
    if (normalizedQuery.length < 2) return;
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      _searchRelays(normalizedQuery);
    });
  }

  Future<void> _searchRelays(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final response = await ref.read(apiClientProvider).getRelayPoints(
        params: {'search': query, 'limit': 200},
      );
      final data = response.data as Map<String, dynamic>;
      final results = (data['relay_points'] as List? ?? [])
          .map((item) => RelayPoint.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() => _filteredRelays = results);
      final first = results.firstWhere(
        (relay) => relay.lat != null && relay.lng != null,
        orElse: () => results.isEmpty
            ? const RelayPoint(
                id: '',
                name: '',
                phone: '',
                addressLabel: '',
                city: '',
                agentId: '',
              )
            : results.first,
      );
      if (first.id.isNotEmpty && first.lat != null && first.lng != null) {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(first.lat!, first.lng!), 13),
        );
      }
    } catch (_) {
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _filteredRelays = []);
      }
    } finally {
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectRelay(RelayPoint relay) {
    if (!widget.consultative) {
      if (relay.isFull) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${relay.name} est complet. Choisissez un autre relais.',
            ),
          ),
        );
        return;
      }
      if (!relay.isOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${relay.name} est fermé. ${relay.openingStatusLabel ?? 'Choisissez un autre relais.'}')),
        );
        return;
      }
      Navigator.of(context).pop(relay);
      return;
    }

    final area = _relayArea(relay);
    final hours = _relayOpeningHours(relay);
    final distance = _relayDistance(relay);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
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
                if (distance != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.near_me_outlined,
                          size: 18, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Text('Depuis ma position : $distance'),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Places disponibles : ${relay.availableSlots.clamp(0, relay.capacity)}',
                  style: const TextStyle(color: Colors.blueGrey),
                ),
                if (hours != null) ...[
                  const SizedBox(height: 8),
                  const Text('Horaires d’ouverture',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...relayOpeningHoursLines(relay.openingHours).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(line),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  relay.openingStatusLabel ??
                      (relay.isOpen ? 'Ouvert maintenant' : 'Fermé maintenant'),
                  style: TextStyle(
                    color: _relayStatusColor(relay),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (relay.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(relay.description!.trim()),
                ],
              ],
            ),
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
    return relayOpeningHoursSummary(hours);
  }

  String? _relayDistance(RelayPoint relay) {
    final position = _currentPosition;
    if (position == null || relay.lat == null || relay.lng == null) return null;
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      relay.lat!,
      relay.lng!,
    );
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  Color _relayStatusColor(RelayPoint relay) {
    if (!relay.openingStatusKnown) return Colors.orange.shade800;
    return relay.isOpen ? Colors.green : Colors.red;
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
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
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
                            final distance = _relayDistance(r);
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
                                    if (distance != null)
                                      Text(
                                        'À $distance de ma position',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue,
                                        ),
                                      ),
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
                                    Text(
                                      'Places disponibles : ${r.availableSlots.clamp(0, r.capacity)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    if (hours != null)
                                      Text(
                                        'Horaires : $hours',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.green),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      r.openingStatusLabel ??
                                          (r.isOpen
                                              ? 'Ouvert maintenant'
                                              : 'Fermé maintenant'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _relayStatusColor(r),
                                        fontWeight: FontWeight.w600,
                                      ),
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
            icon: _relayMarkerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
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
      myLocationEnabled: _currentPosition != null,
      myLocationButtonEnabled: _currentPosition != null,
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
