import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../providers/admin_provider.dart';

class AdminHeatmapScreen extends ConsumerStatefulWidget {
  const AdminHeatmapScreen({super.key});

  @override
  ConsumerState<AdminHeatmapScreen> createState() => _AdminHeatmapScreenState();
}

class _AdminHeatmapScreenState extends ConsumerState<AdminHeatmapScreen> {
  @override
  Widget build(BuildContext context) {
    final heatmapAsync = ref.watch(adminHeatmapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte des Demandes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(adminHeatmapProvider),
          ),
        ],
      ),
      body: heatmapAsync.when(
        data: (points) {
          if (points.isEmpty) {
            return const Center(child: Text('Aucune donnée de demande récente.'));
          }

          final circles = <Circle>{};
          for (int i = 0; i < points.length; i++) {
            final p = points[i];
            circles.add(
              Circle(
                circleId: CircleId('point_$i'),
                center: LatLng(p['lat'], p['lng']),
                radius: 150, // 150 mètres de rayon pour l'effet "chaleur"
                fillColor: Colors.red.withOpacity(0.2),
                strokeColor: Colors.red.withOpacity(0.1),
                strokeWidth: 1,
              ),
            );
          }

          return GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.7167, -17.4677), // Dakar
              zoom: 12,
            ),
            circles: circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }
}
