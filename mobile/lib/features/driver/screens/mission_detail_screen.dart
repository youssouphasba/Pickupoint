import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/driver_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/parcel_chat_widget.dart';
import '../../../core/models/delivery_mission.dart';
import '../../../shared/utils/currency_format.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:convert';

class MissionDetailScreen extends ConsumerStatefulWidget {
  const MissionDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<MissionDetailScreen> createState() =>
      _MissionDetailScreenState();
}

class _MissionDetailScreenState extends ConsumerState<MissionDetailScreen> {
  bool _isProcessing = false;
  StreamSubscription<Position>? _positionStream;
  DateTime? _lastBackendUpdate;
  GoogleMapController? _mapController;
  String? _proofBase64;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // ── GPS streaming (Temps Réel) ──────────────────────────────────────────
  Future<void> _startLocationUpdates() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm != LocationPermission.whileInUse &&
        perm != LocationPermission.always) {
      return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((pos) async {
      // 1. Update backend (Throttled: every 30s)
      final now = DateTime.now();
      if (_lastBackendUpdate == null ||
          now.difference(_lastBackendUpdate!).inSeconds > 30) {
        _lastBackendUpdate = now;
        try {
          await ref.read(apiClientProvider).updateLocation(
            widget.id,
            {
              'lat': pos.latitude,
              'lng': pos.longitude,
              'accuracy': pos.accuracy,
            },
          );
          // Auto-refresh mission data to get new ETA from backend
          ref.invalidate(missionProvider(widget.id));
        } catch (_) {}
      }
    });
  }

  // ── Scan QR ou saisie manuelle → retourne le code saisi ──────────────────
  Future<String?> _showCodeDialog(
      {required String title, required String hint, int maxLength = 6}) async {
    final codeCtrl = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              // ── Scan QR ────────────────────────────────────────────
              Container(
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.black,
                ),
                clipBehavior: Clip.hardEdge,
                child: MobileScanner(
                  onDetect: (capture) {
                    final code = capture.barcodes.first.rawValue;
                    if (code != null) {
                      // Format attendu : "parcel_id:code" → extraire le code
                      final parts = code.split(':');
                      final extracted = parts.length >= 2 ? parts.last : code;
                      Navigator.of(ctx).pop(extracted);
                    }
                  },
                ),
              ),

              const SizedBox(height: 16),
              const Row(children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou', style: TextStyle(color: Colors.grey)),
                ),
                Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),

              // ── Saisie manuelle ────────────────────────────────────
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: maxLength,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(codeCtrl.text.trim()),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Valider le code'),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          );
        }),
      ),
    );
  }

  // ── Ouvrir navigation externe (Google Maps / Waze) ───────────────────────
  Future<void> _openNavigation(double lat, double lng, String label) async {
    final googleMapsUrl = Uri.parse(
      'google.navigation:q=$lat,$lng&mode=d',
    );
    final googleMapsWeb = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    final wazeUrl = Uri.parse(
      'waze://ul?ll=$lat,$lng&navigate=yes',
    );

    if (!mounted) {
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Naviguer vers $label',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$lat, $lng',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield, color: Colors.blueGrey, size: 24),
                      Text('Sécurisé',
                          style:
                              TextStyle(fontSize: 10, color: Colors.blueGrey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _navOption(
                ctx,
                icon: 'G',
                iconColor: Colors.blue,
                label: 'Google Maps',
                onTap: () async {
                  Navigator.pop(ctx);
                  // Essayer l'app native, sinon web (toujours disponible)
                  final launched = await launchUrl(googleMapsUrl,
                      mode: LaunchMode.externalApplication);
                  if (!launched) {
                    await launchUrl(googleMapsWeb,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 8),
              _navOption(
                ctx,
                icon: 'W',
                iconColor: const Color(0xFF00CFFF),
                label: 'Waze',
                onTap: () async {
                  Navigator.pop(ctx);
                  final launched = await launchUrl(wazeUrl,
                      mode: LaunchMode.externalApplication);
                  if (!launched) {
                    // Waze non installé → Google Maps web
                    await launchUrl(googleMapsWeb,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navOption(
    BuildContext ctx, {
    required String icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Text(icon,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                    fontSize: 16)),
          ),
          const SizedBox(width: 14),
          Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const Spacer(),
          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  // ── Confirmer la collecte (pickup_code) ───────────────────────────────────
  Future<void> _confirmPickup() async {
    final code = await _showCodeDialog(
      title: 'Code de collecte',
      hint: '• • • • • •',
    );
    if (code == null || code.isEmpty) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);
      double? lat, lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
      await api.confirmPickup(widget.id, code, lat: lat, lng: lng);
      if (mounted) {
        ref.invalidate(missionProvider(widget.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Collecte confirmée ! Bonne route.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ── Signaler l'arrivée à destination (R2H / H2H) — GPS vérifié < 500m ──────
  Future<void> _arriveAtDestination(String parcelId) async {
    setState(() => _isProcessing = true);
    try {
      // Capturer la position GPS du driver
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Permission GPS requise pour confirmer l\'arrivée';
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final api = ref.read(apiClientProvider);
      await api.arriveAtDestination(parcelId,
          lat: pos.latitude, lng: pos.longitude);
      if (mounted) {
        ref.invalidate(missionProvider(widget.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Arrivée confirmée ! Validez la livraison avec le code.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ── Prendre une photo (Preuve) + Compression WebP (Phase 7) ───────────────
  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (image == null) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final bytes = await image.readAsBytes();
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
        format: CompressFormat.webp,
      );

      setState(() {
        _proofBase64 = base64Encode(result);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Photo de preuve enregistrée !'),
          backgroundColor: Colors.teal,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur compression: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ── Valider la livraison (delivery_code + géofence) ───────────────────────
  Future<void> _confirmDelivery(String parcelId) async {
    final code = await _showCodeDialog(
      title: 'Code du destinataire',
      hint: '• • • • • •',
      maxLength: 6,
    );
    if (code == null || code.isEmpty) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      // Récupérer position GPS actuelle pour la géofence
      double? driverLat, driverLng;
      try {
        final pos = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 8));
        driverLat = pos.latitude;
        driverLng = pos.longitude;
      } catch (_) {}

      final api = ref.read(apiClientProvider);
      await api.deliverParcel(parcelId, {
        'delivery_code': code,
        'driver_lat': driverLat,
        'driver_lng': driverLng,
        'proof_type': _proofBase64 != null ? 'photo' : null,
        'proof_data': _proofBase64,
      });
      if (mounted) {
        ref.invalidate(myMissionsProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Livraison validée ! Merci.'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ── Libérer une mission (avant collecte) ─────────────────────────────────
  Future<void> _releaseMission(String missionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Libérer la mission ?'),
        content: const Text(
          'La mission redeviendra disponible pour d\'autres livreurs.\n'
          'Impossible après avoir confirmé la collecte.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await ref.read(apiClientProvider).releaseMission(missionId);
      if (mounted) {
        ref.invalidate(myMissionsProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mission libérée.'),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // ── Échec livraison ────────────────────────────────────────────────────────
  Future<void> _showFailDialog(String parcelId) async {
    String? reason;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Signaler un problème'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Le colis sera redirigé vers le relais le plus proche.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: reason,
              decoration: const InputDecoration(
                labelText: 'Motif',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'destinataire_absent',
                  child: Text('Destinataire absent'),
                ),
                DropdownMenuItem(
                  value: 'adresse_introuvable',
                  child: Text('Adresse introuvable'),
                ),
                DropdownMenuItem(
                  value: 'colis_refuse',
                  child: Text('Colis refusé'),
                ),
              ],
              onChanged: (value) => setLocal(() => reason = value),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            TextButton(
              onPressed: reason == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _failDelivery(parcelId, reason!);
                    },
              child:
                  const Text('Confirmer', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _failDelivery(String parcelId, String reason) async {
    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.failDelivery(parcelId, {'failure_reason': reason});
      final redirectRelayId = res.data['redirect_relay_id'] as String?;
      if (mounted) {
        ref.invalidate(myMissionsProvider);
        final msg = redirectRelayId != null
            ? 'Livraison échouée — colis redirigé vers le relais de repli'
            : 'Livraison échouée';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missionAsync = ref.watch(missionProvider(widget.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Ma mission')),
      body: missionAsync.when(
        data: (mission) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Gain ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('VOTRE GAIN',
                            style: TextStyle(
                                fontSize: 11, color: Colors.blueGrey)),
                        Text(formatXof(mission.earnAmount),
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                        if (mission.driverBonusXof > 0)
                          Text(
                            'Bonus adresse: +${formatXof(mission.driverBonusXof)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.green),
                          ),
                      ]),
                  if (mission.etaText != null)
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(mission.etaText!.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold)),
                          Text(mission.distanceText ?? '',
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.blueGrey)),
                        ]),
                  if (mission.etaText == null)
                    const Icon(Icons.local_shipping,
                        size: 40, color: Colors.blue),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Carte itinéraire ───────────────────────────────────────
            _buildRouteMap(mission),
            const SizedBox(height: 20),

            // ── Statut du paiement ─────────────────────────────────────
            _buildPaymentStatus(mission),
            const SizedBox(height: 20),
            if ((mission.driverName?.isNotEmpty ?? false) ||
                (mission.driverPhone?.isNotEmpty ?? false) ||
                (mission.driverPhotoUrl?.isNotEmpty ?? false) ||
                (mission.senderName?.isNotEmpty ?? false) ||
                (mission.senderPhotoUrl?.isNotEmpty ?? false)) ...[
              const Text(
                'Identites',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if ((mission.driverName?.isNotEmpty ?? false) ||
                  (mission.driverPhone?.isNotEmpty ?? false) ||
                  (mission.driverPhotoUrl?.isNotEmpty ?? false)) ...[
                _buildContactCard(
                  title: 'Livreur en charge',
                  name: mission.driverName ?? 'Livreur Denkma',
                  photo: mission.driverPhotoUrl,
                  phone: mission.driverPhone,
                ),
                const SizedBox(height: 12),
              ],
              if ((mission.senderName?.isNotEmpty ?? false) ||
                  (mission.senderPhotoUrl?.isNotEmpty ?? false)) ...[
                _buildContactCard(
                  title: 'Expediteur',
                  name: mission.senderName ?? 'Expediteur',
                  photo: mission.senderPhotoUrl,
                  phone: null,
                ),
                const SizedBox(height: 20),
              ],
            ],
            if ((mission.pickupVoiceNote?.isNotEmpty ?? false) ||
                (mission.deliveryVoiceNote?.isNotEmpty ?? false)) ...[
              _buildInstructionCards(mission),
              const SizedBox(height: 20),
            ],

            // ── Contacts (Expéditeur & Destinataire) ───────────────────────
            const Text('Contacts',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // Expéditeur (Point de Retrait)
            _buildContactCard(
              title: 'Expéditeur (Retrait)',
              name: mission
                  .pickupLabel, // Souvent le nom du relais ou de l'expéditeur
              photo: mission.senderPhotoUrl,
              phone: null, // On garde masqué selon politique
              showCall: mission.status == 'assigned',
            ),

            const SizedBox(height: 12),

            // Destinataire (Point de Livraison)
            if (mission.recipientName != null)
              _buildContactCard(
                title: 'Destinataire (Livraison)',
                name: mission.recipientName!,
                photo: mission.recipientPhotoUrl,
                phone: mission.recipientPhone ?? '',
                // Le backend masque le numéro jusqu'à ce que le driver soit à <500m
                showCall: true,
              ),

            const SizedBox(height: 20),

            // ── Code de suivi (visible livreur pour montrer au relais) ─
            if (mission.trackingCode != null) ...[
              _buildTrackingCodeCard(mission),
              const SizedBox(height: 20),
            ],

            // ── Messagerie colis ──────────────────────────────────────
            if (mission.status == 'assigned' ||
                mission.status == 'in_progress') ...[
              ParcelChatWidget(parcelId: mission.parcelId, isClosed: false),
              const SizedBox(height: 20),
            ],

            // ── Boutons action selon statut ───────────────────────────
            _buildActionButtons(mission),
            const SizedBox(height: 40),
          ]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  Widget _buildRouteMap(DeliveryMission mission) {
    final hasPickup = mission.pickupLat != null;
    final hasDelivery = mission.deliveryLat != null;

    if (!hasPickup && !hasDelivery) return const SizedBox.shrink();

    final center = hasPickup
        ? LatLng(mission.pickupLat!, mission.pickupLng!)
        : LatLng(mission.deliveryLat!, mission.deliveryLng!);

    // Destination de navigation selon le statut de la mission
    final navToDelivery = mission.status == 'in_progress' && hasDelivery;
    final navLat = navToDelivery
        ? mission.deliveryLat!
        : (hasPickup ? mission.pickupLat! : mission.deliveryLat!);
    final navLng = navToDelivery
        ? mission.deliveryLng!
        : (hasPickup ? mission.pickupLng! : mission.deliveryLng!);
    final navLabel =
        navToDelivery ? mission.deliveryLabel : mission.pickupLabel;

    final Set<Marker> markers = {};
    if (hasPickup) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup_pos'),
          position: LatLng(mission.pickupLat!, mission.pickupLng!),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'Point de retrait'),
        ),
      );
    }
    if (hasDelivery) {
      markers.add(
        Marker(
          markerId: const MarkerId('delivery_pos'),
          position: LatLng(mission.deliveryLat!, mission.deliveryLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Point de livraison'),
        ),
      );
    }

    final Set<Polyline> polylines = {};
    if (hasPickup && hasDelivery) {
      List<LatLng> routePoints;
      if (mission.encodedPolyline != null) {
        final decoded =
            PolylinePoints().decodePolyline(mission.encodedPolyline!);
        routePoints =
            decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();
      } else {
        routePoints = [
          LatLng(mission.pickupLat!, mission.pickupLng!),
          LatLng(mission.deliveryLat!, mission.deliveryLng!),
        ];
      }
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue.withValues(alpha: 0.8),
          width: 4,
        ),
      );
    }

    return Column(
      children: [
        // ── Carte interactive ────────────────────────────────────────
        Stack(
          children: [
            Container(
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              clipBehavior: Clip.hardEdge,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: center,
                  zoom: 13.0,
                ),
                onMapCreated: (controller) => _mapController = controller,
                markers: markers,
                polylines: polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
            ),

            // ── Recentrer sur ma position ─────────────────────────
            Positioned(
              top: 10,
              right: 10,
              child: FloatingActionButton.small(
                heroTag: 'recenter_me',
                onPressed: () async {
                  final pos = await Geolocator.getCurrentPosition();
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
                  );
                },
                backgroundColor: Colors.white,
                child:
                    const Icon(Icons.my_location, color: Colors.blue, size: 20),
              ),
            ),
          ],
        ),

        // ── Légende pickup → delivery ────────────────────────────────
        if (hasPickup && hasDelivery) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store, color: Colors.orange, size: 14),
              const SizedBox(width: 4),
              Flexible(
                  child: Text(mission.pickupLabel,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
              ),
              const Icon(Icons.location_on, color: Colors.red, size: 14),
              const SizedBox(width: 4),
              Flexible(
                  child: Text(mission.deliveryLabel,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],

        // ── Bouton "Naviguer" plein-largeur bien visible ──────────────────────────
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () => _openNavigation(navLat, navLng, navLabel),
            icon: const Icon(Icons.navigation_rounded, size: 28),
            label: Text(
              'NAVIGUER VERS $navLabel'.toUpperCase(),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentStatus(DeliveryMission mission) {
    final isPaid = mission.isPaid;
    final isBlocked = mission.paymentBlocksDelivery;
    final color =
        isPaid ? Colors.green : (isBlocked ? Colors.red : Colors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(isPaid ? Icons.check_circle : Icons.warning_amber_rounded,
            color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPaid
                    ? 'PAIEMENT CONFIRMÉ'
                    : (isBlocked
                        ? 'PAIEMENT BLOQUANT EN ATTENTE'
                        : 'PAIEMENT EN ATTENTE'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color.shade800,
                ),
              ),
              Text(
                isPaid
                    ? 'Le client a réglé la commande.'
                    : 'Payeur: ${mission.whoPays == 'recipient' ? 'destinataire' : 'expéditeur'}'
                        '${mission.paymentMethod != null ? ' • ${mission.paymentMethod}' : ''}'
                        '${mission.paymentOverride ? ' • override admin actif' : ''}',
                style: TextStyle(fontSize: 12, color: color.shade700),
              ),
            ],
          ),
        ),
        if (!isPaid)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(missionProvider(widget.id)),
            tooltip: 'Vérifier le statut',
          ),
      ]),
    );
  }

  // ── Carte code de suivi — livreur le montre au relais ────────────────────
  Widget _buildTrackingCodeCard(DeliveryMission mission) {
    final isInProgress = mission.status == 'in_progress';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isInProgress ? Colors.teal.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInProgress ? Colors.teal.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.qr_code_2,
                color: isInProgress ? Colors.teal : Colors.grey, size: 18),
            const SizedBox(width: 8),
            Text(
              isInProgress
                  ? 'Montrez ce code au relais destinataire'
                  : 'Code de suivi du colis',
              style: TextStyle(
                fontSize: 12,
                color: isInProgress ? Colors.teal.shade700 : Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Center(
            child: Text(
              mission.trackingCode!,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: isInProgress ? Colors.teal.shade800 : Colors.black87,
              ),
            ),
          ),
          if (isInProgress) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Le relais le saisit dans son app pour confirmer la réception',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.teal.shade600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(DeliveryMission mission) {
    final status = mission.status;

    // Statut "assigned" → livreur doit confirmer qu'il a le colis (pickup_code)
    if (status == 'assigned') {
      return Column(children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _confirmPickup,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Confirmer la collecte (QR / code)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _isProcessing ? null : () => _releaseMission(mission.id),
            icon: const Icon(Icons.undo, color: Colors.grey),
            label: const Text('Libérer la mission',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      ]);
    }

    // Statut "in_progress" → livraison en cours → valider ou signaler
    if (status == 'in_progress') {
      // Livraison relais → relais : le relais B confirme lui-même sur son app
      if (mission.deliveryIsRelay) {
        return Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Déposez le colis au relais destinataire.\nIl confirmera la réception sur son application.',
                  style: TextStyle(fontSize: 13, color: Colors.blue),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _showFailDialog(mission.parcelId),
              icon: const Icon(Icons.report_problem, color: Colors.red),
              label: const Text('Impossible de livrer',
                  style: TextStyle(color: Colors.red)),
            ),
          ),
        ]);
      }

      // Driver en transit vers le domicile → bouton "Je suis arrivé"
      if (mission.parcelStatus == 'in_transit') {
        return Column(children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _arriveAtDestination(mission.parcelId),
              icon: const Icon(Icons.location_on),
              label: const Text('Je suis arrivé à destination'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _showFailDialog(mission.parcelId),
              icon: const Icon(Icons.report_problem, color: Colors.red),
              label: const Text('Impossible de livrer',
                  style: TextStyle(color: Colors.red)),
            ),
          ),
        ]);
      }

      // Livraison domicile : livreur valide avec le code du destinataire
      return Column(children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isProcessing || mission.paymentBlocksDelivery
                ? null
                : () => _confirmDelivery(mission.parcelId),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(
              mission.paymentBlocksDelivery
                  ? 'Paiement requis avant remise'
                  : 'Valider la livraison (QR / code)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  mission.paymentBlocksDelivery ? Colors.grey : Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (mission.paymentBlocksDelivery) ...[
          const SizedBox(height: 8),
          const Text(
            'Actualisez le paiement ou contactez les ops avant la remise finale.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.redAccent),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isProcessing ? null : _takePhoto,
            icon: Icon(
                _proofBase64 != null ? Icons.check_circle : Icons.camera_alt,
                color: _proofBase64 != null ? Colors.green : Colors.blue),
            label: Text(_proofBase64 != null
                ? 'Photo enregistrée'
                : 'Prendre une photo (Preuve)'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                  color: _proofBase64 != null ? Colors.green : Colors.blue),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed:
                _isProcessing ? null : () => _showFailDialog(mission.parcelId),
            icon: const Icon(Icons.report_problem, color: Colors.red),
            label: const Text('Impossible de livrer',
                style: TextStyle(color: Colors.red)),
          ),
        ),
      ]);
    }

    return const SizedBox.shrink();
  }

  Widget _buildInstructionCards(DeliveryMission mission) {
    final cards = <Widget>[];
    if (mission.pickupVoiceNote?.isNotEmpty ?? false) {
      cards.add(
        _instructionCard(
          title: 'Instruction collecte',
          icon: Icons.mic_none_rounded,
          color: Colors.orange,
          text: mission.pickupVoiceNote!,
        ),
      );
    }
    if (mission.deliveryVoiceNote?.isNotEmpty ?? false) {
      cards.add(
        _instructionCard(
          title: 'Instruction livraison',
          icon: Icons.record_voice_over_outlined,
          color: Colors.teal,
          text: mission.deliveryVoiceNote!,
        ),
      );
    }
    return Column(children: cards);
  }

  Widget _instructionCard({
    required String title,
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required String title,
    required String name,
    required String? photo,
    required String? phone,
    bool showCall = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.blue.shade50,
            backgroundImage: photo != null ? NetworkImage(photo) : null,
            child: photo == null
                ? const Icon(Icons.person, color: Colors.blue)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                if (phone != null)
                  Text(phone,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.blueGrey)),
              ],
            ),
          ),
          if (showCall && phone != null && !phone.contains('•'))
            IconButton(
              icon: const Icon(Icons.phone_in_talk, color: Colors.green),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
            ),
        ],
      ),
    );
  }
}
