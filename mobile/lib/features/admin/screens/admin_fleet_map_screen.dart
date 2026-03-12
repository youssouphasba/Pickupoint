import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import '../providers/admin_provider.dart';

class AdminFleetMapScreen extends ConsumerStatefulWidget {
  const AdminFleetMapScreen({super.key});

  @override
  ConsumerState<AdminFleetMapScreen> createState() => _AdminFleetMapScreenState();
}

class _AdminFleetMapScreenState extends ConsumerState<AdminFleetMapScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.invalidate(adminFleetProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(adminFleetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi de la Flotte Live'),
      ),
      body: fleetAsync.when(
        data: (fleet) {
          final markers = fleet
              .where((m) => m['driver_location'] != null)
              .map((m) {
            final loc = m['driver_location'] as Map<String, dynamic>;
            final status = m['status'] as String? ?? '';
            final parcelId = m['parcel_id'] as String?;

            // Couleur selon le statut
            double hue = BitmapDescriptor.hueAzure;
            if (status == 'in_progress') hue = BitmapDescriptor.hueGreen;
            if (status == 'assigned') hue = BitmapDescriptor.hueOrange;

            return Marker(
              markerId: MarkerId(m['mission_id'] as String),
              position: LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()),
              infoWindow: InfoWindow(
                title: m['driver_name'] as String? ?? 'Livreur',
                snippet: 'Mission: ${(m['mission_id'] as String).substring(0, 8)}… — $status',
                onTap: parcelId != null
                    ? () => context.push('/admin/parcels/$parcelId/audit')
                    : null,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(hue),
            );
          }).toSet();

          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.7167, -17.4677), // Dakar default
              zoom: 12,
            ),
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
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }
}
