import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/parcel.dart';
import '../providers/client_provider.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/timeline_widget.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/utils/phone_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_endpoints.dart';
import 'package:geolocator/geolocator.dart';

class ParcelDetailScreen extends ConsumerStatefulWidget {
  const ParcelDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ParcelDetailScreen> createState() => _ParcelDetailScreenState();
}

class _ParcelDetailScreenState extends ConsumerState<ParcelDetailScreen> {
  Timer?  _locationTimer;
  double? _driverLat;
  double? _driverLng;
  bool    _driverOnline = false;
  GoogleMapController? _mapController;
  bool    _isConfirmingLocation = false;
  final   _voiceNoteController  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _voiceNoteController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final parcel = ref.read(parcelProvider(widget.id)).value;
      if (parcel == null) return;
      // Seulement quand le colis est en cours de livraison
      if (parcel.status != 'out_for_delivery') return;
      await _fetchDriverLocation();
    });
  }

  Future<void> _fetchDriverLocation() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getDriverLocation(widget.id);
      final data = res.data as Map<String, dynamic>;
      if (data['available'] == true && data['location'] != null) {
        final loc = data['location'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _driverLat   = (loc['lat'] as num).toDouble();
            _driverLng   = (loc['lng'] as num).toDouble();
            _driverOnline = true;
          });
          
          if (_mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(LatLng(_driverLat!, _driverLng!))
            );
          }
        }
      } else {
        if (mounted) setState(() => _driverOnline = false);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final parcelAsync = ref.watch(parcelProvider(widget.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Détail du colis')),
      body: parcelAsync.when(
        data: (parcel) {
          final isRecipient = parcel.isRecipientView ?? false;
          return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, parcel, isRecipient: isRecipient),
              const SizedBox(height: 16),

              if (parcel.status == 'out_for_delivery') ...[
                _buildLiveMap(parcel),
                const SizedBox(height: 16),
              ],

              // ── Bloc Confirmation Position (Destinataire Home) ──────────
              if (_shouldShowConfirmLocation(parcel, isRecipient)) ...[
                _buildConfirmLocationCard(parcel),
                const SizedBox(height: 16),
              ],

              // ── Code collecte (expéditeur donne au livreur — H2R / H2H) ──
              if (_shouldShowPickupCode(parcel, isRecipient)) ...[
                _buildPickupCodeCard(parcel),
                const SizedBox(height: 16),
              ],

              // ── Code PIN retrait relais (destinataire) ───────────────────
              if (_shouldShowPinCode(parcel, isRecipient)) ...[
                _buildPinCodeCard(parcel),
                const SizedBox(height: 16),
              ],

              // ── Code livraison domicile (destinataire donne au livreur)
              if (_shouldShowDeliveryCode(parcel, isRecipient)) ...[
                _buildDeliveryCodeCard(parcel),
                const SizedBox(height: 16),
              ],

              // ── Bloc Notation & Pourboire (si livré et non noté) ─────────
              if (parcel.status == 'delivered' && parcel.rating == null && !isRecipient) ...[
                _buildRatingCard(parcel),
                const SizedBox(height: 16),
              ],

              // ── QR tracking (pour relais) ────────────────────────────────
              _buildQrSection(context, parcel, isRecipient: isRecipient),

              const SizedBox(height: 20),
              _buildInfoSection(parcel, isRecipient: isRecipient),
              const SizedBox(height: 28),

              const Text('Historique',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TimelineWidget(events: parcel.events),
              const SizedBox(height: 28),

              if (parcel.canBeCancelled && !isRecipient)
                LoadingButton(
                  label: "Annuler l'envoi",
                  color: Colors.red.shade700,
                  onPressed: () => _showCancelDialog(context, ref),
                ),
              const SizedBox(height: 40),
            ],
          ),
        );},
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  // ── Confirmation de position In-App ─────────────────────────────────────
  bool _shouldShowConfirmLocation(Parcel parcel, bool isRecipient) {
    if (!isRecipient) return false;
    final isHomeDel = parcel.deliveryMode.endsWith('_to_home');
    return isHomeDel &&
        !['delivered', 'cancelled', 'returned'].contains(parcel.status);
  }

  Widget _buildConfirmLocationCard(Parcel parcel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Text(
                'Action requise : Confirmer votre adresse',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Pour que le livreur puisse vous trouver, confirmez votre position GPS actuelle.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _voiceNoteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instruction vocale (optionnel)',
              hintText: 'Ex: Sonner 2 fois, 2e étage à gauche…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.mic_none),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: LoadingButton(
              label: 'Confirmer / Mettre à jour ma position',
              isLoading: _isConfirmingLocation,
              onPressed: _confirmLocation,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLocation() async {
    setState(() => _isConfirmingLocation = true);
    try {
      // 1. Déclenchement permission & capture GPS
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
           throw 'Permission GPS refusée';
        }
      }
      
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      // 2. Appel API
      final api = ref.read(apiClientProvider);
      final body = <String, dynamic>{
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
      };
      final note = _voiceNoteController.text.trim();
      if (note.isNotEmpty) body['voice_note'] = note;
      await api.updateDeliveryAddress(widget.id, body);

      // 3. Succès
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position confirmée avec succès !')),
        );
        // Rafraîchir le colis
        ref.invalidate(parcelProvider(widget.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirmingLocation = false);
    }
  }

  // ── Code collecte (pickup_code) — l'expéditeur le donne au livreur ──────────
  bool _shouldShowPickupCode(dynamic parcel, bool isRecipient) {
    if (isRecipient) return false;
    final mode = parcel.deliveryMode as String;
    final isHomePickup = mode == 'home_to_relay' || mode == 'home_to_home';
    final code = parcel.pickupCode as String?;
    return isHomePickup &&
        ['created', 'assigned'].contains(parcel.status as String) &&
        code != null;
  }

  Widget _buildPickupCodeCard(dynamic parcel) {
    final code = parcel.pickupCode as String? ?? '';
    if (code.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade700, Colors.orange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.local_shipping, color: Colors.white70, size: 16),
          SizedBox(width: 6),
          Text('Code de collecte — Livreur',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Donnez ce code au livreur quand il arrive chez vous.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              )),
        ),
      ]),
    );
  }

  // ── Code livraison domicile (delivery_code) — donné au livreur ────────────
  bool _shouldShowDeliveryCode(dynamic parcel, bool isRecipient) {
    if (!isRecipient) return false;
    final mode = parcel.deliveryMode as String;
    // Uniquement livraison à domicile (R2H ou H2H) — pas H2R (retrait relais)
    final isHomeDel = mode == 'relay_to_home' || mode == 'home_to_home';
    return isHomeDel &&
        ['created', 'in_transit', 'out_for_delivery'].contains(parcel.status as String) &&
        (parcel.deliveryCode as String?) != null;
  }

  // ── Code retrait relais (pin_code / delivery_code) — donné à l'agent relais ──
  bool _shouldShowPinCode(dynamic parcel, bool isRecipient) {
    if (!isRecipient) return false;
    final isRelayDest = (parcel.deliveryMode as String) == 'relay_to_relay' || (parcel.deliveryMode as String) == 'home_to_relay';
    final code = (parcel.pinCode as String?) ?? (parcel.deliveryCode as String?);
    return isRelayDest &&
        ['at_destination_relay', 'available_at_relay']
            .contains(parcel.status as String) &&
        code != null;
  }

  Widget _buildDeliveryCodeCard(dynamic parcel) {
    final code = parcel.deliveryCode as String? ?? '';
    if (code.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lock, color: Colors.white70, size: 16),
          SizedBox(width: 6),
          Text('Code de réception — Livraison domicile',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Center(
          child: Text(code,
              style: const TextStyle(
                color: Colors.white, fontSize: 38,
                fontWeight: FontWeight.bold, letterSpacing: 8,
              )),
        ),
        const SizedBox(height: 10),
        const SizedBox(width: double.infinity,
          child: Text(
            'Donnez ce code au livreur à son arrivée.\nNe le partagez pas avant.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: QrImageView(
              data: '${parcel.id}:$code',
              version: QrVersions.auto,
              size: 120,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildPinCodeCard(dynamic parcel) {
    final pin = (parcel.pinCode as String?) ?? (parcel.deliveryCode as String?) ?? '';
    if (pin.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.store, color: Colors.white70, size: 16),
          SizedBox(width: 6),
          Text('Code de retrait — Point relais',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Votre colis est disponible au relais. Présentez ce code à l\'agent.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(pin,
              style: const TextStyle(
                color: Colors.white, fontSize: 38,
                fontWeight: FontWeight.bold, letterSpacing: 10,
              )),
        ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: QrImageView(
              data: pin,
              version: QrVersions.auto,
              size: 130,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const SizedBox(width: double.infinity,
          child: Text(
            'Le QR code ou le code à 4 chiffres — montrez-en un seul.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }

  Widget _buildLiveMap(dynamic parcel) {
    // Coordonnées destination depuis le colis
    final destLat = parcel.deliveryLat as double?;
    final destLng = parcel.deliveryLng as double?;

    // Centrer sur le livreur si disponible, sinon sur la destination
    final center = _driverLat != null
        ? LatLng(_driverLat!, _driverLng!)
        : (destLat != null ? LatLng(destLat, destLng!) : const LatLng(14.693, -17.447)); // Dakar fallback

    final Set<Marker> markers = {};

    // Marker livreur (moto)
    if (_driverLat != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_pos'),
          position: LatLng(_driverLat!, _driverLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Livreur en route'),
        ),
      );
    }
    
    // Marker destination
    if (destLat != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dest_pos'),
          position: LatLng(destLat, destLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: center,
              zoom: 14.0,
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: markers,
            zoomControlsEnabled: true,
            mapToolbarEnabled: true,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
          // Badge statut GPS
          Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _driverOnline ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _driverOnline ? Icons.circle : Icons.circle_outlined,
                  size: 8, color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _driverOnline 
                    ? (parcel.etaText != null ? 'En route • ${parcel.etaText}' : 'En route')
                    : 'Signal GPS faible',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // RESTE DE L'UI: Header, QrTracking, Infos
  Widget _buildHeader(BuildContext context, dynamic parcel, {bool isRecipient = false}) {
    final otherPartyPhoto = isRecipient ? parcel.senderPhotoUrl : parcel.recipientPhotoUrl;
    final otherPartyName  = isRecipient ? (parcel.senderName ?? 'Expéditeur') : (parcel.recipientName ?? 'Destinataire');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: otherPartyPhoto != null ? NetworkImage(otherPartyPhoto) : null,
              child: otherPartyPhoto == null ? const Icon(Icons.person, size: 20, color: Colors.blue) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRecipient ? 'Expéditeur : $otherPartyName' : 'Destinataire : $otherPartyName',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Text('Colis ${parcel.trackingCode}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            ParcelStatusBadge(status: parcel.status),
          ],
        ),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isRecipient ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRecipient ? Colors.green.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                isRecipient ? Icons.download : Icons.upload,
                size: 12,
                color: isRecipient ? Colors.green.shade700 : Colors.blue.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                isRecipient ? 'Colis reçu' : 'Colis envoyé',
                style: TextStyle(
                  fontSize: 11,
                  color: isRecipient ? Colors.green.shade700 : Colors.blue.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text(formatDate(parcel.createdAt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),

        if (parcel.driverPhotoUrl != null && (parcel.status == 'assigned' || parcel.status == 'picked_up' || parcel.status == 'out_for_delivery')) ...[
          const SizedBox(height: 16),
          _buildDriverInfo(parcel),
        ],
      ],
    );
  }

  Widget _buildDriverInfo(dynamic parcel) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(parcel.driverPhotoUrl!),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Livreur en charge', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text('Votre livreur est en route', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_in_talk, color: Colors.green),
            onPressed: () {
              // Appeler le livreur si nécessaire
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection(BuildContext context, Parcel parcel, {bool isRecipient = false}) {
    // Choix du code affiché dans le QR selon le rôle et le mode de livraison
    final isRelayPickup = parcel.deliveryMode == 'relay_to_relay' ||
                          parcel.deliveryMode == 'home_to_relay';
    final String? qrCode;
    final String qrLabel;
    if (!isRecipient) {
      // Expéditeur : code collecte (H2R/H2H) ou code suivi
      qrCode  = parcel.pickupCode ?? parcel.trackingCode;
      qrLabel = parcel.pickupCode != null ? 'Code Collecte (Livreur)' : 'Code Suivi';
    } else if (isRelayPickup) {
      // Destinataire retrait relais : relay_pin
      qrCode  = parcel.pinCode ?? parcel.trackingCode;
      qrLabel = 'Code retrait relais';
    } else {
      // Destinataire livraison domicile (R2H/H2H) : delivery_code
      qrCode  = parcel.deliveryCode ?? parcel.trackingCode;
      qrLabel = 'Code de réception (Livreur)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              QrImageView(
                data: qrCode ?? parcel.trackingCode,
                size: 64,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qrLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(qrCode ?? parcel.trackingCode,
                        style: const TextStyle(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _shareOnWhatsApp(parcel),
              icon: const Icon(Icons.share, size: 18, color: Colors.green),
              label: const Text('Partager sur WhatsApp', style: TextStyle(color: Colors.green)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.green),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOnWhatsApp(Parcel parcel) async {
    final senderName = ref.read(authProvider).valueOrNull?.user?.name ?? "L'expéditeur";
    final url = ApiEndpoints.trackingView(parcel.trackingCode);
    
    // "[Sender Name] veut vous envoyer [tel colis]. Veuillez confirmer votre position via ce lien pour recevoir le colis."
    String text = '$senderName veut vous envoyer un colis (${parcel.trackingCode}).';
    
    if (parcel.recipientConfirmUrl != null && !parcel.deliveryConfirmed) {
      text += '\n\nVeuillez confirmer votre position via ce lien pour recevoir le colis : ${parcel.recipientConfirmUrl}';
    } else {
      text += '\n\nVous pouvez suivre l\'avancement ici : $url';
    }

    final whatsappUrl = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    
    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp n\'est pas installé')),
        );
      }
    }
  }

  Widget _buildInfoSection(dynamic parcel, {bool isRecipient = false}) {
    return Column(
      children: [
        _buildInfoRow(Icons.person, 'Destinataire', parcel.recipientName ?? 'N/A'),
        _buildInfoRow(Icons.phone, 'Téléphone', maskPhone(parcel.recipientPhone ?? '')),
        _buildInfoRow(
          Icons.location_on,
          parcel.isRelayToHome ? 'Adresse' : 'Point Relais',
          parcel.isRelayToHome ? (parcel.destinationAddress ?? 'N/A') : (parcel.destinationRelayId ?? 'N/A'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingCard(Parcel parcel) {
    return _RatingCard(parcelId: parcel.id);
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler l\'envoi ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
          TextButton(
            onPressed: () async {
              try {
                final api = ref.read(apiClientProvider);
                await api.cancelParcel(widget.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ref.invalidate(parcelProvider(widget.id));
                  ref.invalidate(parcelsProvider);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              }
            },
            child: const Text('Confirmer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends ConsumerStatefulWidget {
  const _RatingCard({required this.parcelId});
  final String parcelId;

  @override
  ConsumerState<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends ConsumerState<_RatingCard> {
  int _rating = 0;
  final _commentController = TextEditingController();
  final _tipController     = TextEditingController();
  bool _submitting         = false;

  void _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner au moins une étoile')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final tip = double.tryParse(_tipController.text) ?? 0.0;
      await ref.read(apiClientProvider).rateParcel(
        widget.parcelId, 
        _rating, 
        comment: _commentController.text,
        tip: tip,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci pour votre avis !')),
        );
        ref.invalidate(parcelProvider(widget.parcelId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comment s\'est passée la livraison ?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                icon: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 36,
                ),
                onPressed: () => setState(() => _rating = index + 1),
              );
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              hintText: 'Un commentaire ? (Optionnel)',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          const Text('Ajouter un pourboire au livreur ?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _tipController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Montant en XOF (ex: 500)',
              prefixIcon: Icon(Icons.account_balance_wallet, size: 20),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 20),
          LoadingButton(
            label: 'Envoyer ma note',
            onPressed: _submit,
            isLoading: _submitting,
          ),
        ],
      ),
    );
  }
}
