import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/error_utils.dart';

final adminParcelAuditProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getParcelAudit(id);
  return res.data as Map<String, dynamic>;
});

class AdminParcelAuditScreen extends ConsumerStatefulWidget {
  const AdminParcelAuditScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AdminParcelAuditScreen> createState() =>
      _AdminParcelAuditScreenState();
}

class _AdminParcelAuditScreenState
    extends ConsumerState<AdminParcelAuditScreen> {
  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(adminParcelAuditProvider(widget.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Audit trail du colis')),
      body: auditAsync.when(
        data: (data) {
          final parcel = Map<String, dynamic>.from(
            data['parcel'] as Map? ?? const {},
          );
          final parcelSummary = Map<String, dynamic>.from(
            data['parcel_summary'] as Map? ?? const {},
          );
          final financial = Map<String, dynamic>.from(
            data['financial_summary'] as Map? ?? const {},
          );
          final timeline = List<Map<String, dynamic>>.from(
            data['timeline'] as List? ?? const [],
          );
          final missions = List<Map<String, dynamic>>.from(
            data['missions'] as List? ?? const [],
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Synthèse colis'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MetricCard(
                      title: 'Code',
                      value: parcel['tracking_code'] as String? ??
                          'Non disponible',
                      icon: Icons.qr_code_2,
                      color: Colors.blue,
                    ),
                    _MetricCard(
                      title: 'Statut',
                      value: _statusLabel(parcel['status'] as String? ?? ''),
                      icon: Icons.local_shipping,
                      color: Colors.green,
                    ),
                    _MetricCard(
                      title: 'Mode',
                      value: _deliveryModeLabel(
                        parcelSummary['delivery_mode'] as String?,
                      ),
                      icon: Icons.route,
                      color: Colors.orange,
                    ),
                    _MetricCard(
                      title: 'Durée totale',
                      value: _formatDuration(
                        parcelSummary['total_delivery_seconds'] as int?,
                      ),
                      icon: Icons.timer,
                      color: Colors.deepPurple,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _InfoPanel(
                  children: [
                    _InfoLine(
                      label: 'Expéditeur',
                      value: parcel['sender_name'] as String? ??
                          parcel['sender_user_id'] as String? ??
                          'Inconnu',
                    ),
                    _InfoLine(
                      label: 'Destinataire',
                      value:
                          '${parcel['recipient_name'] ?? "Inconnu"} (${parcel['recipient_phone'] ?? "-"})',
                    ),
                    if (_locationLabel(parcel['origin_relay']) != null)
                      _InfoLine(
                        label: 'Relais origine',
                        value: _locationLabel(parcel['origin_relay'])!,
                      ),
                    if (_locationLabel(parcel['destination_relay']) != null)
                      _InfoLine(
                        label: 'Relais destination',
                        value: _locationLabel(parcel['destination_relay'])!,
                      ),
                    if (_locationLabel(parcel['redirect_relay']) != null)
                      _InfoLine(
                        label: 'Relais de repli',
                        value: _locationLabel(parcel['redirect_relay'])!,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionTitle('Paiement et repricing'),
                _InfoPanel(
                  children: [
                    _InfoLine(
                      label: 'Statut paiement',
                      value:
                          financial['payment_status'] as String? ?? 'Inconnu',
                    ),
                    if ((financial['payment_method'] as String?)?.isNotEmpty ??
                        false)
                      _InfoLine(
                        label: 'Méthode',
                        value: financial['payment_method'] as String,
                      ),
                    if ((financial['who_pays'] as String?)?.isNotEmpty ?? false)
                      _InfoLine(
                        label: 'Payeur',
                        value: financial['who_pays'] as String,
                      ),
                    if (financial['payment_override'] == true)
                      _InfoLine(
                        label: 'Override',
                        value:
                            financial['payment_override_reason'] as String? ??
                                'Oui',
                      ),
                    if ((financial['address_change_surcharge_xof'] as num?) !=
                            null &&
                        (financial['address_change_surcharge_xof'] as num) > 0)
                      _InfoLine(
                        label: 'Surcoût adresse',
                        value:
                            '${financial['address_change_surcharge_xof']} XOF',
                      ),
                    if ((financial['driver_bonus_xof'] as num?) != null &&
                        (financial['driver_bonus_xof'] as num) > 0)
                      _InfoLine(
                        label: 'Bonus livreur',
                        value: '${financial['driver_bonus_xof']} XOF',
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionTitle('Missions et trace réelle'),
                if (missions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Aucune mission trouvée pour ce colis.'),
                  )
                else
                  ...missions.map(
                    (mission) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _MissionAuditCard(
                        mission: mission,
                        onReassign: _canReassign(mission)
                            ? () => _showReassignDialog(
                                  context,
                                  mission['mission_id'] as String,
                                )
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                const _SectionTitle('Timeline des événements'),
                if (timeline.isEmpty)
                  const Text('Aucun événement journalisé.')
                else
                  ...timeline.map(
                    (event) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title:
                            Text(event['event_type'] as String? ?? 'Événement'),
                        subtitle: Text(
                          [
                            _formatDateTime(event['timestamp']) ??
                                event['timestamp']?.toString() ??
                                '-',
                            'Acteur: ${event['actor_name'] ?? event['actor_id'] ?? event['actor_role'] ?? "Système"}',
                            if ((event['notes'] as String?)?.isNotEmpty ??
                                false)
                              'Notes: ${event['notes']}',
                          ].join('\n'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  bool _canReassign(Map<String, dynamic> mission) {
    const allowedStatuses = {'pending', 'assigned', 'incident_reported'};
    return allowedStatuses.contains(mission['status']);
  }

  void _showReassignDialog(BuildContext context, String missionId) {
    final driverController = TextEditingController();
    final reasonController = TextEditingController(
      text: 'Réassignation manuelle depuis l’audit colis',
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Réassigner la mission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: driverController,
              decoration: const InputDecoration(
                labelText: 'ID du nouveau livreur',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Motif'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (driverController.text.trim().isEmpty ||
                  reasonController.text.trim().isEmpty) {
                return;
              }
              try {
                await ref.read(apiClientProvider).reassignMission(
                      missionId,
                      driverController.text.trim(),
                      reason: reasonController.text.trim(),
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ref.invalidate(adminParcelAuditProvider(widget.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mission réassignée.')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyError(e))),
                );
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }
}

class _MissionAuditCard extends StatelessWidget {
  const _MissionAuditCard({
    required this.mission,
    required this.onReassign,
  });

  final Map<String, dynamic> mission;
  final VoidCallback? onReassign;

  @override
  Widget build(BuildContext context) {
    final routeSummary = Map<String, dynamic>.from(
      mission['route_summary'] as Map? ?? const {},
    );
    final durations = Map<String, dynamic>.from(
      mission['duration_summary'] as Map? ?? const {},
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          'Mission ${mission['mission_id']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
                'Livreur: ${mission['driver_name'] ?? mission['driver_id'] ?? "Inconnu"}'),
            Text('Statut: ${_statusLabel(mission['status'] as String? ?? "")}'),
          ],
        ),
        trailing: onReassign == null
            ? null
            : IconButton(
                icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                tooltip: 'Réassigner',
                onPressed: onReassign,
              ),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricCard(
                title: 'Trace GPS',
                value:
                    '${routeSummary['gps_points_count'] as int? ?? 0} points',
                icon: Icons.my_location,
                color: Colors.green,
              ),
              _MetricCard(
                title: 'ETA',
                value: (routeSummary['eta_text'] as String?) ?? 'Non calculée',
                icon: Icons.schedule,
                color: Colors.orange,
              ),
              _MetricCard(
                title: 'Distance',
                value: (routeSummary['distance_text'] as String?) ??
                    'Non calculée',
                icon: Icons.straighten,
                color: Colors.blue,
              ),
              _MetricCard(
                title: 'Durée active',
                value: _formatDuration(
                  durations['active_elapsed_seconds'] as int?,
                ),
                icon: Icons.timer,
                color: Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AuditMissionMap(mission: mission),
          const SizedBox(height: 14),
          _InfoPanel(
            children: [
              _InfoLine(
                label: 'Départ',
                value: _locationLabel(mission['pickup']) ?? 'Inconnu',
              ),
              _InfoLine(
                label: 'Arrivée',
                value: _locationLabel(mission['delivery']) ?? 'Inconnue',
              ),
              if ((mission['driver_phone'] as String?)?.isNotEmpty ?? false)
                _InfoLine(
                  label: 'Téléphone livreur',
                  value: mission['driver_phone'] as String,
                ),
              if (_formatDateTime(routeSummary['last_seen_at']) != null)
                _InfoLine(
                  label: 'Dernier point live',
                  value: _formatDateTime(routeSummary['last_seen_at'])!,
                ),
              if ((durations['assigned_to_pickup_seconds'] as int?) != null)
                _InfoLine(
                  label: 'Assignation -> prise en charge',
                  value: _formatDuration(
                    durations['assigned_to_pickup_seconds'] as int?,
                  ),
                ),
              if ((durations['pickup_to_completion_seconds'] as int?) != null)
                _InfoLine(
                  label: 'Prise en charge -> fin',
                  value: _formatDuration(
                    durations['pickup_to_completion_seconds'] as int?,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuditMissionMap extends StatefulWidget {
  const _AuditMissionMap({required this.mission});

  final Map<String, dynamic> mission;

  @override
  State<_AuditMissionMap> createState() => _AuditMissionMapState();
}

class _AuditMissionMapState extends State<_AuditMissionMap> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _latLngFromLocation(widget.mission['pickup']);
    final delivery = _latLngFromLocation(widget.mission['delivery']);
    final driver = _latLngFromMap(widget.mission['driver_location']);
    final trail = _trailPoints(widget.mission);
    final planned = _decodePolyline(
      widget.mission['encoded_polyline'] as String?,
    );
    final visiblePoints = <LatLng>[
      if (pickup != null) pickup,
      if (delivery != null) delivery,
      if (driver != null) driver,
      ...trail,
      ...planned,
    ];

    if (visiblePoints.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Aucune géolocalisation exploitable pour cette mission.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final markers = <Marker>{
      if (pickup != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Départ',
            snippet: _locationLabel(widget.mission['pickup']),
          ),
        ),
      if (delivery != null)
        Marker(
          markerId: const MarkerId('delivery'),
          position: delivery,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: 'Arrivée',
            snippet: _locationLabel(widget.mission['delivery']),
          ),
        ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: widget.mission['driver_name'] as String? ?? 'Livreur',
            snippet:
                widget.mission['eta_text'] as String? ?? 'Position courante',
          ),
        ),
    };

    final polylines = <Polyline>{};
    if (planned.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('planned_route'),
          points: planned,
          color: Colors.blue.shade500,
          width: 5,
        ),
      );
    }
    if (trail.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('actual_route'),
          points: trail,
          color: Colors.green.shade600,
          width: 6,
        ),
      );
    } else if (planned.length < 2 && pickup != null && delivery != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('fallback_route'),
          points: [pickup, delivery],
          color: Colors.orange.shade700,
          width: 4,
        ),
      );
    }

    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: visiblePoints.first,
            zoom: 13,
          ),
          onMapCreated: (controller) async {
            _mapController = controller;
            await Future<void>.delayed(const Duration(milliseconds: 120));
            if (!mounted || _mapController == null) return;
            await _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                  _boundsFromPoints(visiblePoints), 60),
            );
          },
          markers: markers,
          polylines: polylines,
          myLocationEnabled: false,
          zoomControlsEnabled: true,
          mapToolbarEnabled: true,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer()),
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

LatLng? _latLngFromMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final lat = value['lat'];
  final lng = value['lng'];
  if (lat is! num || lng is! num) {
    return null;
  }
  return LatLng(lat.toDouble(), lng.toDouble());
}

LatLng? _latLngFromLocation(Object? location) {
  if (location is! Map) {
    return null;
  }
  return _latLngFromMap(location['geopin']);
}

String? _locationLabel(Object? location) {
  if (location is! Map) {
    return null;
  }
  final label = location['label'] as String?;
  if (label != null && label.isNotEmpty) {
    return label;
  }
  final relay = location['relay'];
  if (relay is Map) {
    return relay['label'] as String? ?? relay['name'] as String?;
  }
  return null;
}

List<LatLng> _trailPoints(Map<String, dynamic> mission) {
  return List<Map<String, dynamic>>.from(
    mission['gps_trail'] as List? ?? const [],
  ).map<LatLng?>((point) => _latLngFromMap(point)).whereType<LatLng>().toList();
}

List<LatLng> _decodePolyline(String? encodedPolyline) {
  if (encodedPolyline == null || encodedPolyline.isEmpty) {
    return const [];
  }
  return PolylinePoints()
      .decodePolyline(encodedPolyline)
      .map((point) => LatLng(point.latitude, point.longitude))
      .toList();
}

LatLngBounds _boundsFromPoints(List<LatLng> points) {
  if (points.length == 1) {
    final point = points.first;
    return LatLngBounds(
      southwest: LatLng(point.latitude - 0.01, point.longitude - 0.01),
      northeast: LatLng(point.latitude + 0.01, point.longitude + 0.01),
    );
  }
  double minLat = points.first.latitude;
  double maxLat = points.first.latitude;
  double minLng = points.first.longitude;
  double maxLng = points.first.longitude;
  for (final point in points.skip(1)) {
    minLat = point.latitude < minLat ? point.latitude : minLat;
    maxLat = point.latitude > maxLat ? point.latitude : maxLat;
    minLng = point.longitude < minLng ? point.longitude : minLng;
    maxLng = point.longitude > maxLng ? point.longitude : maxLng;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

String _statusLabel(String status) {
  switch (status) {
    case 'created':
      return 'Créé';
    case 'assigned':
      return 'Assignée';
    case 'in_progress':
      return 'En cours';
    case 'incident_reported':
      return 'Incident';
    case 'delivered':
      return 'Livré';
    case 'available_at_relay':
      return 'Disponible au relais';
    default:
      return status.isEmpty ? 'Inconnu' : status;
  }
}

String _deliveryModeLabel(String? mode) {
  switch (mode) {
    case 'relay_to_relay':
      return 'Relais → relais';
    case 'relay_to_home':
      return 'Relais → domicile';
    case 'home_to_relay':
      return 'Domicile → relais';
    case 'home_to_home':
      return 'Domicile → domicile';
    default:
      return mode ?? 'Inconnu';
  }
}

String _formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '0 min';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}';
  }
  return '$minutes min';
}

String? _formatDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) {
    return value.toString();
  }
  final local = parsed.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} à $hh:$mm';
}
