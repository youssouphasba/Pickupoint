import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/api/api_endpoints.dart';
import '../../core/models/user.dart';
import '../../core/location/fresh_position_helper.dart';

class MapPickerResult {
  final LatLng position;
  final String? address;
  final String source;
  final double? accuracy;

  const MapPickerResult(
      {required this.position,
      this.address,
      this.source = 'manual',
      this.accuracy});
}

class MapPickerModal extends StatefulWidget {
  final String title;
  final LatLng? initialPosition;
  final List<FavoriteAddress> favoriteAddresses;
  final double? initialAccuracy;
  final String initialSource;

  const MapPickerModal({
    super.key,
    this.title = 'Choisir une position',
    this.initialPosition,
    this.favoriteAddresses = const [],
    this.initialAccuracy,
    this.initialSource = 'manual',
  });

  @override
  State<MapPickerModal> createState() => _MapPickerModalState();
}

class _MapPickerModalState extends State<MapPickerModal> {
  LatLng? _selectedPosition;
  LatLng _mapCenter = const LatLng(14.6928, -17.4467);
  bool _userMoving = false;
  bool _gpsLoading = false;
  bool _hasGpsAccess = false;
  String? _locationError;
  String _source = 'manual';
  double? _accuracy;
  int _searchGeneration = 0;
  bool _loading = true;
  GoogleMapController? _mapController;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5)));
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
    _dio.close();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    if (widget.initialPosition != null) {
      _selectedPosition = widget.initialPosition;
      _mapCenter = widget.initialPosition!;
      _source = widget.initialSource;
      _accuracy = widget.initialAccuracy;
      setState(() => _loading = false);
      return;
    }

    await _useMyPosition();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _useMyPosition() async {
    if (_gpsLoading) return;
    setState(() {
      _gpsLoading = true;
      _locationError = null;
    });
    try {
      final position = await FreshPositionHelper.getStrictFreshPosition(
          context: 'la sélection de votre position');
      if (!mounted) return;
      final selected = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedPosition = selected;
        _mapCenter = selected;
        _source = 'gps';
        _accuracy = position.accuracy;
        _hasGpsAccess = true;
        _selectedAddress = null;
        _selectedAddressForPosition = null;
        _userMoving = false;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(selected, 16));
    } catch (_) {
      if (mounted) {
        setState(() => _locationError =
            'Position GPS indisponible. Recherchez une adresse, choisissez un favori ou déplacez la carte pour sélectionner le lieu.');
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _searchGeneration++;
    _searchCancel?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(
        const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    final generation = _searchGeneration;
    _searchCancel?.cancel();
    _searchCancel = CancelToken();
    setState(() => _searching = true);
    final biasLat = _selectedPosition?.latitude ?? 14.6928;
    final biasLon = _selectedPosition?.longitude ?? -17.4467;
    try {
      final res = await _dio.get(
        ApiEndpoints.addressSuggestions,
        queryParameters: {
          'q': query,
          'limit': 6,
          'lat': biasLat,
          'lng': biasLon,
        },
        cancelToken: _searchCancel,
      );
      final suggestions = (res.data['suggestions'] as List?) ?? [];
      final list = suggestions
          .map<_PlaceSuggestion?>(
              (s) => _PlaceSuggestion.tryParse(s as Map<String, dynamic>))
          .whereType<_PlaceSuggestion>()
          .toList();
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _suggestions = list;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _suggestions = [];
        _searching = false;
        _locationError =
            'Recherche d’adresse indisponible. Réessayez ou sélectionnez le lieu sur la carte.';
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
      _mapCenter = pos;
      _source = 'manual';
      _accuracy = null;
      _locationError = null;
      _userMoving = false;
      _selectedAddress = fullAddress;
      _selectedAddressForPosition = pos;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  void _selectFavorite(FavoriteAddress favorite) {
    final pos = LatLng(favorite.lat, favorite.lng);
    _searchCtrl.text = favorite.address;
    _searchFocus.unfocus();
    setState(() {
      _suggestions = [];
      _selectedPosition = pos;
      _mapCenter = pos;
      _source = 'manual';
      _accuracy = null;
      _locationError = null;
      _userMoving = false;
      _selectedAddress = favorite.address;
      _selectedAddressForPosition = pos;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.reverseAddress,
        queryParameters: {
          'lat': pos.latitude,
          'lng': pos.longitude,
        },
      );
      final data = res.data;
      final address = data is Map ? data['address'] : null;
      final formatted = address is Map
          ? address['formatted_address']?.toString().trim()
          : null;
      if (formatted != null && formatted.isNotEmpty) return formatted;
    } catch (_) {}

    return null;
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
    Navigator.pop(
        context,
        MapPickerResult(
            position: pos,
            address: address,
            source: _source,
            accuracy: _accuracy));
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
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                    ),
                  ),
                ),
                if (widget.favoriteAddresses.isNotEmpty)
                  SizedBox(
                    height: 94,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 2),
                          child: Text(
                            'Mes adresses favorites',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.favoriteAddresses.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final favorite = widget.favoriteAddresses[index];
                              return ActionChip(
                                avatar: const Icon(
                                  Icons.bookmark_outline,
                                  size: 18,
                                ),
                                label: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 170),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        favorite.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        favorite.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                onPressed: () => _selectFavorite(favorite),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_locationError != null || _selectedPosition == null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                        _locationError ??
                            'Choisissez explicitement le lieu sur la carte ou recherchez une adresse.',
                        style: const TextStyle(
                            color: Colors.deepOrange, fontSize: 13)),
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Listener(
                          onPointerDown: (_) => _userMoving = true,
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _mapCenter,
                              zoom: 15,
                            ),
                            onMapCreated: (c) => _mapController = c,
                            onCameraMove: (position) {
                              _mapCenter = position.target;
                              if (!_userMoving) return;
                              setState(() {
                                _selectedPosition = position.target;
                                _source = 'manual';
                                _accuracy = null;
                                _locationError = null;
                              });
                            },
                            onCameraIdle: () {
                              _userMoving = false;
                              final addressPosition =
                                  _selectedAddressForPosition;
                              final selectedPosition = _selectedPosition;
                              if (addressPosition != null &&
                                  selectedPosition != null &&
                                  Geolocator.distanceBetween(
                                        addressPosition.latitude,
                                        addressPosition.longitude,
                                        selectedPosition.latitude,
                                        selectedPosition.longitude,
                                      ) >
                                      25) {
                                _selectedAddress = null;
                                _selectedAddressForPosition = null;
                              }
                            },
                            myLocationEnabled: _hasGpsAccess,
                            myLocationButtonEnabled: false,
                            mapToolbarEnabled: false,
                            zoomControlsEnabled: false,
                            gestureRecognizers: <Factory<
                                OneSequenceGestureRecognizer>>{
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                          )),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: null,
                          tooltip: 'Ma position GPS',
                          onPressed: _gpsLoading ? null : _useMyPosition,
                          child: _gpsLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location),
                        ),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: _suggestions.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = _suggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.place_outlined,
                                        size: 20),
                                    title: Text(s.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: s.subtitle != null
                                        ? Text(s.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 12))
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
                      onPressed: _confirming ||
                              _selectedPosition == null ||
                              _gpsLoading
                          ? null
                          : _onConfirm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _confirming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
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

  _PlaceSuggestion(
      {required this.label,
      this.subtitle,
      required this.lat,
      required this.lng});

  static _PlaceSuggestion? tryParse(Map<String, dynamic> feature) {
    final directLat = feature['lat'];
    final directLng = feature['lng'];
    final directLabel = feature['label'];
    if (directLat is num &&
        directLng is num &&
        directLabel is String &&
        directLabel.trim().isNotEmpty) {
      final subtitle = feature['subtitle'];
      return _PlaceSuggestion(
        label: directLabel.trim(),
        subtitle: subtitle is String && subtitle.trim().isNotEmpty
            ? subtitle.trim()
            : null,
        lat: directLat.toDouble(),
        lng: directLng.toDouble(),
      );
    }

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
