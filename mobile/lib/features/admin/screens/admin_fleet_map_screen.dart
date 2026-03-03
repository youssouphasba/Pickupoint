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
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final fleetAsync = ref.watch(adminFleetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi de la Flotte Live'),
      ),
      body: fleetAsync.when(
        data: (fleet) {
          final markers = fleet.map((m) {
            final loc = m['driver_location'];
            final status = m['status'] as String;
            
            // Couleur selon le statut
            double hue = BitmapDescriptor.hueAzure;
            if (status == 'in_progress') hue = BitmapDescriptor.hueGreen;
            if (status == 'assigned') hue = BitmapDescriptor.hueOrange;
            
            return Marker(
              markerId: MarkerId(m['mission_id']),
              position: LatLng(loc['lat'], loc['lng']),
              infoWindow: InfoWindow(
                title: m['driver_name'] ?? 'Livreur',
                snippet: 'Mission: ${m['mission_id'].toString().substring(0, 8)}... — $status',
                onTap: () => context.push('/admin/parcels/${m['mission_id']}/audit'),
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
            onMapCreated: (controller) => _mapController = controller,
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
