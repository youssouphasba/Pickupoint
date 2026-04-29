import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapPickerResult {
  final LatLng position;
  final String? address;

  const MapPickerResult({required this.position, this.address});
}

class MapPickerModal extends StatefulWidget {
  final String title;
  final LatLng? initialPosition;

  const MapPickerModal({
    super.key,
    this.title = 'Choisir une position',
    this.initialPosition,
  });

  @override
  State<MapPickerModal> createState() => _MapPickerModalState();
}

class _MapPickerModalState extends State<MapPickerModal> {
  LatLng? _selectedPosition;
  bool _loading = true;
  GoogleMapController? _mapController;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
  Timer? _debounce;
  List<_PlaceSuggestion> _suggestions = [];
  bool _searching = false;
  CancelToken? _searchCancel;

  String? _selectedAddress;
  LatLng? _selectedAddressForPosition;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCancel?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    if (widget.initialPosition != null) {
      _selectedPosition = widget.initialPosition;
      setState(() => _loading = false);
      return;
    }

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition();
        _selectedPosition = LatLng(pos.latitude, pos.longitude);
      } else {
        _selectedPosition = const LatLng(14.6928, -17.4467);
      }
    } catch (_) {
      _selectedPosition = const LatLng(14.6928, -17.4467);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    _searchCancel?.cancel();
    _searchCancel = CancelToken();
    setState(() => _searching = true);
    try {
      final biasLat = _selectedPosition?.latitude ?? 14.6928;
      final biasLon = _selectedPosition?.longitude ?? -17.4467;
      final res = await _dio.get(
        'https://photon.komoot.io/api/',
        queryParameters: {
          'q': query,
          'limit': 6,
          'lang': 'fr',
          'lat': biasLat,
          'lon': biasLon,
        },
        cancelToken: _searchCancel,
      );
      final features = (res.data['features'] as List?) ?? [];
      final list = features
          .map<_PlaceSuggestion?>((f) => _PlaceSuggestion.tryParse(f as Map<String, dynamic>))
          .whereType<_PlaceSuggestion>()
          .toList();
      if (!mounted) return;
      setState(() {
        _suggestions = list;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _searching = false;
      });
    }
  }

  void _selectSuggestion(_PlaceSuggestion s) {
    _searchCtrl.text = s.label;
    _searchFocus.unfocus();
    final pos = LatLng(s.lat, s.lng);
    final fullAddress = s.subtitle == null || s.subtitle!.isEmpty
        ? s.label
        : '${s.label}, ${s.subtitle!}';
    setState(() {
      _suggestions = [];
      _selectedPosition = pos;
      _selectedAddress = fullAddress;
      _selectedAddressForPosition = pos;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      final res = await _dio.get(
        'https://photon.komoot.io/reverse',
        queryParameters: {'lat': pos.latitude, 'lon': pos.longitude, 'lang': 'fr'},
      );
      final features = (res.data['features'] as List?) ?? [];
      if (features.isEmpty) return null;
      final s = _PlaceSuggestion.tryParse(features.first as Map<String, dynamic>);
      if (s == null) return null;
      return s.subtitle == null || s.subtitle!.isEmpty
          ? s.label
          : '${s.label}, ${s.subtitle!}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _onConfirm() async {
    final pos = _selectedPosition;
    if (pos == null) return;
    String? address = _selectedAddress;
    final samePos = _selectedAddressForPosition != null &&
        (_selectedAddressForPosition!.latitude - pos.latitude).abs() < 1e-5 &&
        (_selectedAddressForPosition!.longitude - pos.longitude).abs() < 1e-5;
    if (address == null || !samePos) {
      setState(() => _confirming = true);
      address = await _reverseGeocode(pos);
      if (!mounted) return;
      setState(() => _confirming = false);
    }
    if (!mounted) return;
    Navigator.pop(context, MapPickerResult(position: pos, address: address));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Rechercher une adresse, un lieu…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (_searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _suggestions = []);
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _selectedPosition!,
                          zoom: 15,
                        ),
                        onMapCreated: (c) => _mapController = c,
                        onCameraMove: (position) {
                          _selectedPosition = position.target;
                          // L'adresse mise en cache n'est plus valide après un déplacement manuel.
                          if (_selectedAddressForPosition != null) {
                            _selectedAddress = null;
                            _selectedAddressForPosition = null;
                          }
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        mapToolbarEnabled: false,
                        zoomControlsEnabled: false,
                        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 35),
                            child: Icon(
                              Icons.location_on,
                              size: 45,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ),
                      if (_suggestions.isNotEmpty)
                        Positioned(
                          left: 12,
                          right: 12,
                          top: 0,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = _suggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.place_outlined, size: 20),
                                    title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: s.subtitle != null
                                        ? Text(s.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                                        : null,
                                    onTap: () => _selectSuggestion(s),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirming ? null : _onConfirm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _confirming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Confirmer cette position'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PlaceSuggestion {
  final String label;
  final String? subtitle;
  final double lat;
  final double lng;

  _PlaceSuggestion({required this.label, this.subtitle, required this.lat, required this.lng});

  static _PlaceSuggestion? tryParse(Map<String, dynamic> feature) {
    final geom = feature['geometry'] as Map<String, dynamic>?;
    final coords = geom?['coordinates'] as List?;
    if (coords == null || coords.length < 2) return null;
    final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
    final name = props['name'] as String?;
    final street = props['street'] as String?;
    final houseNumber = props['housenumber'] as String?;
    final city = props['city'] as String?;
    final district = props['district'] as String?;
    final country = props['country'] as String?;
    final state = props['state'] as String?;

    final mainParts = <String>[
      if (name != null && name.isNotEmpty) name,
      if (houseNumber != null && houseNumber.isNotEmpty) houseNumber,
      if (street != null && street.isNotEmpty) street,
    ];
    final subtitleParts = <String>[
      if (district != null && district.isNotEmpty) district,
      if (city != null && city.isNotEmpty) city,
      if (state != null && state.isNotEmpty && state != city) state,
      if (country != null && country.isNotEmpty) country,
    ];
    final label = mainParts.isNotEmpty
        ? mainParts.join(' ')
        : (subtitleParts.isNotEmpty ? subtitleParts.first : 'Sans nom');

    return _PlaceSuggestion(
      label: label,
      subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(', ') : null,
      lat: (coords[1] as num).toDouble(),
      lng: (coords[0] as num).toDouble(),
    );
  }
}
