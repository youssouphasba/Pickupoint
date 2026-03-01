# Plan d'implémentation — Tracking temps réel, Codes de validation, Anti-contournement

> Document autonome. Un développeur peut l'implémenter sans autre contexte.
> Ordre d'implémentation à respecter : Backend → Modèles Flutter → Écrans Flutter.

---

## Contexte technique

- **Backend** : FastAPI + MongoDB (Motor async) + Pydantic V2
- **Frontend** : Flutter (Riverpod + go_router)
- **Répertoire** : `/mnt/c/Users/Utilisateur/pickupoint/`
- **Backend prod** : `https://pickupoint-production.up.railway.app`
- **Packages Flutter disponibles** : `geolocator`, `mobile_scanner`, `qr_flutter`, `flutter_riverpod`
- **À ajouter dans `pubspec.yaml`** : `flutter_map: ^6.1.0` + `latlong2: ^0.9.0`

---

## Vue d'ensemble de ce qui est implémenté

Ce plan couvre **4 blocs** :

| Bloc | Description |
|---|---|
| **A** | Codes de validation 6 chiffres (pickup + delivery) obligatoires |
| **B** | Carte temps réel avec position du livreur (style Uber) |
| **C** | Géofence + GPS Trail pour audit anti-détournement |
| **D** | Anti-contournement paiement (numéros masqués, paiement bloqué sans QR) |

---

## BLOC A — Codes de validation (QR + 6 chiffres)

### Principe

```
Expéditeur/Relais voit pickup_code → le lit au livreur ou lui montre l'écran
Livreur entre le code dans son app → pickup confirmé
----
Destinataire voit delivery_code → le lit au livreur ou lui montre l'écran
Livreur entre le code dans son app → livraison validée, wallet crédité
```

Les codes sont dans le colis, pas dans la mission.
Le QR code scannable encode `{parcel_id}:{code}` — même format pour les deux.

---

### A1 — Backend : génération des codes

**Fichier** : `backend/models/parcel.py`

Ajouter dans la classe `Parcel` (après `payment_ref`) :
```python
pickup_code:   str  = ""   # 6 chiffres — montré à l'expéditeur/relais
delivery_code: str  = ""   # 6 chiffres — montré au destinataire
```

Ajouter dans `ParcelCreate` : rien (les codes sont générés côté service).

---

**Fichier** : `backend/services/parcel_service.py`

Ajouter en haut du fichier :
```python
import random
```

Ajouter la fonction helper :
```python
def _generate_code() -> str:
    """Génère un code numérique à 6 chiffres."""
    return f"{random.randint(100000, 999999)}"
```

Dans `create_parcel()`, ajouter les deux codes dans `parcel_doc` (après `"quoted_price"`) :
```python
"pickup_code":   _generate_code(),
"delivery_code": _generate_code(),
```

---

### A2 — Backend : endpoint confirm-pickup (driver)

**Fichier** : `backend/routers/deliveries.py`

Ajouter ce modèle Pydantic en haut (après les imports) :
```python
from pydantic import BaseModel

class CodeConfirm(BaseModel):
    code: str
```

Ajouter cet endpoint après `accept_mission` :
```python
@router.post("/{mission_id}/confirm-pickup", summary="Confirmer la prise en charge (code 6 chiffres)")
async def confirm_pickup(
    mission_id: str,
    body: CodeConfirm,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    """
    Le livreur saisit le code vu chez l'expéditeur ou au relais.
    Valide la prise en charge physique du colis.
    Passe la mission en 'in_progress' et démarre l'enregistrement du trail GPS.
    """
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0})
    if not mission:
        raise not_found_exception("Mission")
    if mission["status"] != MissionStatus.ASSIGNED.value:
        raise bad_request_exception("La mission doit être en statut 'assigned'")

    parcel = await db.parcels.find_one({"parcel_id": mission["parcel_id"]}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    if parcel.get("pickup_code", "") != body.code.strip():
        raise bad_request_exception("Code de collecte invalide")

    now = datetime.now(timezone.utc)
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "status":      MissionStatus.IN_PROGRESS.value,
            "started_at":  now,
            "updated_at":  now,
            "gps_trail":   [],   # initialiser le trail
        }},
    )
    return {"message": "Prise en charge confirmée", "mission_id": mission_id}
```

---

### A3 — Backend : modifier deliver pour exiger delivery_code + géofence

**Fichier** : `backend/routers/parcels.py`

Remplacer le modèle `ProofOfDelivery` importé par un nouveau modèle local avec `delivery_code`.

Modifier l'import au début du fichier :
```python
from models.delivery import ProofOfDelivery, CodeDelivery
```

**Fichier** : `backend/models/delivery.py`

Ajouter après `ProofOfDelivery` :
```python
class CodeDelivery(BaseModel):
    delivery_code: str
    driver_lat:    Optional[float] = None   # pour géofence
    driver_lng:    Optional[float] = None
```

**Fichier** : `backend/routers/parcels.py`

Remplacer l'endpoint `deliver_parcel` :
```python
@router.post("/{parcel_id}/deliver", summary="Marquer livré — code 6 chiffres obligatoire")
async def deliver_parcel(
    parcel_id: str,
    body: CodeDelivery,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    # ── Validation du code ─────────────────────────────────────────────
    if parcel.get("delivery_code", "") != body.delivery_code.strip():
        raise bad_request_exception("Code de livraison invalide")

    # ── Géofence : livreur doit être à moins de 500 m du destinataire ──
    if body.driver_lat is not None and body.driver_lng is not None:
        delivery_addr = parcel.get("delivery_address") or {}
        geopin = delivery_addr.get("geopin") or {}
        dest_lat = geopin.get("lat")
        dest_lng = geopin.get("lng")
        if dest_lat is not None and dest_lng is not None:
            from services.pricing_service import _haversine_km
            dist_m = _haversine_km(body.driver_lat, body.driver_lng, dest_lat, dest_lng) * 1000
            if dist_m > 500:
                raise bad_request_exception(
                    f"Vous êtes trop loin de l'adresse de livraison ({int(dist_m)} m). "
                    f"Rapprochez-vous (< 500 m)."
                )

    updated = await transition_status(
        parcel_id, ParcelStatus.DELIVERED,
        actor_id=current_user["user_id"], actor_role=current_user["role"],
        notes=f"Livré — code validé",
        metadata={"delivery_code_used": True},
    )
    return updated
```

> Note : `_haversine_km` existe dans `pricing_service.py`. L'importer directement.

---

### A4 — Backend : endpoint pour afficher les codes (client + relais)

**Fichier** : `backend/routers/parcels.py`

Ajouter cet endpoint (accès client + relay_agent + admin) :
```python
@router.get("/{parcel_id}/codes", summary="Codes de validation du colis")
async def get_parcel_codes(
    parcel_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Retourne les codes de collecte et de livraison.
    - Expéditeur/Relais : voit pickup_code (pour donner au livreur)
    - Destinataire : voit delivery_code (pour donner au livreur à la livraison)
    - Admin : voit les deux
    """
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")

    role    = current_user["role"]
    user_id = current_user["user_id"]
    is_admin = role in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]

    # L'expéditeur ou le relais origine voient le pickup_code
    can_see_pickup = (
        is_admin
        or parcel.get("sender_user_id") == user_id
        or (role == UserRole.RELAY_AGENT.value
            and current_user.get("relay_point_id") == parcel.get("origin_relay_id"))
    )

    # Le destinataire : pas de compte → le code est envoyé par SMS.
    # L'admin peut voir les deux.
    return {
        "pickup_code":   parcel.get("pickup_code")   if can_see_pickup or is_admin else None,
        "delivery_code": parcel.get("delivery_code") if is_admin else parcel.get("delivery_code"),
        # delivery_code visible par tous les ayants-droit (client destinataire = sender si flux inverse, ou voir note ci-dessous)
    }
```

> **Note métier** : Le `delivery_code` doit être visible par le destinataire final.
> Dans le flux actuel, le destinataire n'a pas de compte → recevoir le code par SMS à la création.
> Pour Phase 1, le sender voit aussi le delivery_code (il peut le transmettre au destinataire).

---

### A5 — Backend : envoyer delivery_code par SMS au destinataire

**Fichier** : `backend/services/parcel_service.py`

Dans `create_parcel()`, après `await db.parcels.insert_one(parcel_doc)`, ajouter :
```python
# Envoyer le code de livraison au destinataire par SMS/WhatsApp
from services.notification_service import notify_delivery_code
await notify_delivery_code(
    phone=data.recipient_phone,
    recipient_name=data.recipient_name,
    tracking_code=tracking_code,
    delivery_code=parcel_doc["delivery_code"],
)
```

**Fichier** : `backend/services/notification_service.py`

Ajouter cette fonction (si elle n'existe pas déjà) :
```python
async def notify_delivery_code(
    phone: str,
    recipient_name: str,
    tracking_code: str,
    delivery_code: str,
) -> None:
    """Envoie le code de livraison au destinataire par WhatsApp/SMS."""
    msg = (
        f"Bonjour {recipient_name},\n"
        f"Un colis vous est destiné (réf. {tracking_code}).\n"
        f"Votre code de réception : *{delivery_code}*\n"
        f"Donnez ce code au livreur pour valider la remise. Ne le partagez pas."
    )
    try:
        await _send_via_twilio(phone, msg)
    except Exception as e:
        logger.warning("Impossible d'envoyer le code livraison: %s", e)
```

---

## BLOC B — Carte temps réel (style Uber)

### B1 — Ajouter les packages carte

**Fichier** : `mobile/pubspec.yaml`

Ajouter dans `dependencies:` :
```yaml
  # Carte OpenStreetMap (gratuit, pas d'API key)
  flutter_map: ^6.1.0
  latlong2: ^0.9.0
```

---

### B2 — Backend : endpoint position livreur (client peut interroger)

**Fichier** : `backend/routers/parcels.py`

Ajouter cet endpoint public (client voit la position du livreur de SON colis) :
```python
@router.get("/{parcel_id}/driver-location", summary="Position GPS du livreur (temps réel)")
async def get_driver_location(
    parcel_id: str,
    current_user: dict = Depends(get_current_user),
):
    """Retourne la dernière position connue du livreur. Polling toutes les 5s côté Flutter."""
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
    if parcel.get("sender_user_id") != current_user["user_id"] and \
       current_user["role"] not in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]:
        raise forbidden_exception()

    mission = await db.delivery_missions.find_one(
        {"parcel_id": parcel_id, "status": {"$in": ["assigned", "in_progress"]}},
        {"_id": 0, "driver_location": 1, "location_updated_at": 1},
    )
    if not mission or not mission.get("driver_location"):
        return {"available": False, "location": None}

    return {
        "available": True,
        "location":  mission["driver_location"],
        "updated_at": mission.get("location_updated_at"),
    }
```

---

### B3 — Backend : GPS Trail (anti-détournement audit)

**Fichier** : `backend/routers/deliveries.py`

Modifier `update_location` pour stocker aussi le trail (max 300 points) :
```python
@router.put("/{mission_id}/location", summary="Mettre à jour position GPS")
async def update_location(
    mission_id: str,
    body: LocationUpdate,
    current_user: dict = Depends(require_role(
        UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN
    )),
):
    now = datetime.now(timezone.utc)
    trail_point = {"lat": body.lat, "lng": body.lng, "ts": now.isoformat()}

    await db.delivery_missions.update_one(
        {"mission_id": mission_id, "driver_id": current_user["user_id"]},
        {
            "$set": {
                "driver_location":    {"lat": body.lat, "lng": body.lng, "accuracy": body.accuracy},
                "location_updated_at": now,
                "updated_at":          now,
            },
            # Ajouter au trail et limiter à 300 points
            "$push": {
                "gps_trail": {
                    "$each":  [trail_point],
                    "$slice": -300,
                }
            },
        },
    )
    return {"message": "Position mise à jour"}
```

---

### B4 — Flutter : `parcel_detail_screen.dart` — Mini carte avec position livreur

Réécrire complètement `parcel_detail_screen.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import '../../../core/auth/auth_provider.dart';
import '../providers/client_provider.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/timeline_widget.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';

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
  final   _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
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
        data: (parcel) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, parcel),
              const SizedBox(height: 16),

              // ── Carte temps réel (uniquement si livraison en cours) ──────
              if (parcel.status == 'out_for_delivery') ...[
                _buildLiveMap(parcel),
                const SizedBox(height: 16),
              ],

              // ── Code de livraison (delivery_code) ───────────────────────
              if (_shouldShowDeliveryCode(parcel))
                _buildDeliveryCodeCard(parcel),

              // ── QR tracking (pour relais) ────────────────────────────────
              const SizedBox(height: 16),
              _buildQrSection(context, parcel.trackingCode),

              const SizedBox(height: 20),
              _buildInfoSection(parcel),
              const SizedBox(height: 28),

              const Text('Historique',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TimelineWidget(events: parcel.events),
              const SizedBox(height: 28),

              if (parcel.canBeCancelled)
                LoadingButton(
                  label: "Annuler l'envoi",
                  color: Colors.red.shade700,
                  onPressed: () => _showCancelDialog(context, ref),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  // ── Afficher le code de livraison si statut pertinent ─────────────────────
  bool _shouldShowDeliveryCode(dynamic parcel) {
    return ['out_for_delivery', 'created', 'in_transit', 'at_destination_relay',
            'available_at_relay'].contains(parcel.status as String);
  }

  Widget _buildDeliveryCodeCard(dynamic parcel) {
    // Le code est dans parcel.deliveryCode (voir modèle Dart section B5)
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lock, color: Colors.white70, size: 16),
            SizedBox(width: 6),
            Text('Code de réception',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          // Affichage grand du code
          Center(
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Donnez ce code au livreur à sa arrivée.\nNe le partagez pas avant.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          // QR du code de livraison (scannable par livreur)
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
        ],
      ),
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

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom:   14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pickupoint.app',
              ),
              MarkerLayer(markers: [
                // Marker livreur (moto)
                if (_driverLat != null)
                  Marker(
                    point: LatLng(_driverLat!, _driverLng!),
                    width: 48, height: 48,
                    child: const Icon(Icons.motorcycle, color: Colors.blue, size: 36),
                  ),
                // Marker destination
                if (destLat != null)
                  Marker(
                    point: LatLng(destLat, destLng!),
                    width: 40, height: 40,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                  ),
              ]),
            ],
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
                  _driverOnline ? 'Livreur en route' : 'Position indisponible',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, dynamic parcel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${parcel.trackingCode}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ParcelStatusBadge(status: parcel.status),
          ],
        ),
        const SizedBox(height: 8),
        Text('Créé le ${formatDate(parcel.createdAt)}',
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ]),
    );
  }

  Widget _buildQrSection(BuildContext context, String trackingCode) {
    return InkWell(
      onTap: () => _showFullScreenQr(context, trackingCode),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Column(children: [
          QrImageView(data: trackingCode, version: QrVersions.auto, size: 130, backgroundColor: Colors.white),
          const SizedBox(height: 6),
          Text(trackingCode,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text('Appuyez pour agrandir — QR pour le relais',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
      ),
    );
  }

  void _showFullScreenQr(BuildContext context, String trackingCode) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('QR du colis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            QrImageView(data: trackingCode, version: QrVersions.auto, size: 240, backgroundColor: Colors.white),
            const SizedBox(height: 12),
            Text(trackingCode,
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ]),
        ),
      ),
    );
  }

  Widget _buildInfoSection(dynamic parcel) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _infoRow(Icons.person, 'Destinataire', parcel.recipientName ?? 'N/A'),
      // MASQUAGE DU NUMÉRO — voir Bloc D
      _infoRow(Icons.phone, 'Téléphone', _maskPhone(parcel.recipientPhone ?? '')),
      _infoRow(Icons.monitor_weight, 'Poids', '${parcel.weightKg ?? 1.0} kg'),
      _infoRow(Icons.payments, 'Prix', formatXof(parcel.totalPrice ?? 0.0)),
    ]);
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ])),
      ]),
    );
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Annuler l'envoi ?"),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).cancelParcel(widget.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ref.invalidate(parcelProvider(widget.id));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              }
            },
            child: const Text("Confirmer l'annulation", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
```

---

### B5 — Flutter : modèle Parcel — ajouter `deliveryCode`, `deliveryLat`, `deliveryLng`

**Fichier** : `mobile/lib/core/models/parcel.dart`

Dans la classe `Parcel`, ajouter les champs :
```dart
final String? deliveryCode;   // code 6 chiffres affiché au destinataire
final double? deliveryLat;    // lat de delivery_address.geopin
final double? deliveryLng;
```

Dans `fromJson`, ajouter :
```dart
deliveryCode: json['delivery_code'] as String?,
deliveryLat:  (json['delivery_address'] as Map<String,dynamic>?)?['geopin'] != null
    ? ((json['delivery_address']['geopin']['lat']) as num?)?.toDouble()
    : null,
deliveryLng:  (json['delivery_address'] as Map<String,dynamic>?)?['geopin'] != null
    ? ((json['delivery_address']['geopin']['lng']) as num?)?.toDouble()
    : null,
```

---

### B6 — Flutter : `api_client.dart` — ajouter `getDriverLocation`

```dart
Future<Response> getDriverLocation(String parcelId) =>
    _dio.get('${ApiEndpoints.parcel(parcelId)}/driver-location');
```

---

### B7 — Flutter : `mission_detail_screen.dart` — carte + scan QR pickup

Réécrire `mission_detail_screen.dart` avec :

1. **Carte** : markers pickup (orange) + delivery (rouge) + ligne pointillée entre les deux
2. **Bouton "Confirmer la collecte"** : ouvre un dialog avec scan QR OU saisie 6 chiffres
3. **Bouton "Valider la livraison"** : ouvre dialog avec scan QR OU saisie 6 chiffres du destinataire
4. **Bouton "Impossible de livrer"** : inchangé

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/driver_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/delivery_mission.dart';
import '../../../shared/utils/currency_format.dart';
import 'dart:async';

class MissionDetailScreen extends ConsumerStatefulWidget {
  const MissionDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<MissionDetailScreen> createState() => _MissionDetailScreenState();
}

class _MissionDetailScreenState extends ConsumerState<MissionDetailScreen> {
  bool   _isProcessing   = false;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  // ── GPS upload toutes les 30s ─────────────────────────────────────────────
  Future<void> _startLocationUpdates() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) return;

    _locationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.balanced);
        await ref.read(apiClientProvider).updateLocation(
          widget.id, {'lat': pos.latitude, 'lng': pos.longitude},
        );
      } catch (_) {}
    });
  }

  // ── Scan QR ou saisie manuelle → retourne le code saisi ──────────────────
  Future<String?> _showCodeDialog({required String title, required String hint}) async {
    String? scannedCode;
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
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
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
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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

  // ── Confirmer la collecte (pickup_code) ───────────────────────────────────
  Future<void> _confirmPickup() async {
    final code = await _showCodeDialog(
      title: 'Code de collecte',
      hint: '• • • • • •',
    );
    if (code == null || code.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.confirmPickup(widget.id, code);
      if (mounted) {
        ref.refresh(missionProvider(widget.id));
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Valider la livraison (delivery_code + géofence) ───────────────────────
  Future<void> _confirmDelivery(String parcelId) async {
    final code = await _showCodeDialog(
      title: 'Code du destinataire',
      hint: '• • • • • •',
    );
    if (code == null || code.isEmpty) return;

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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Échec livraison (inchangé) ────────────────────────────────────────────
  Future<void> _showFailDialog(String parcelId) async {
    String? reason;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signaler un problème'),
        content: StatefulBuilder(builder: (ctx, setLocal) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Le colis sera redirigé vers le relais le plus proche.'),
            const SizedBox(height: 12),
            ...['Destinataire absent', 'Adresse introuvable', 'Colis refusé'].map((r) =>
              RadioListTile<String>(
                title: Text(r),
                value: r.toLowerCase().replaceAll(' ', '_'),
                groupValue: reason,
                onChanged: (v) => setLocal(() => reason = v),
              ),
            ),
          ]);
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: reason == null ? null : () { Navigator.pop(ctx); _failDelivery(parcelId, reason!); },
            child: const Text('Confirmer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _failDelivery(String parcelId, String reason) async {
    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.failDelivery(parcelId, {'failure_reason': reason});
      final redirectRelayId = res.data['redirect_relay_id'] as String?;
      if (mounted && redirectRelayId != null) {
        await _confirmRedirect(parcelId, redirectRelayId);
      } else if (mounted) {
        ref.invalidate(myMissionsProvider);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmRedirect(String parcelId, String relayId) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Relais de repli trouvé'),
        content: Text('Déposer le colis au relais $relayId ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        await ref.read(apiClientProvider).redirectToRelay(parcelId, {'redirect_relay_id': relayId});
        ref.invalidate(myMissionsProvider);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('VOTRE GAIN',
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    Text(formatXof(mission.earnAmount),
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ]),
                  const Icon(Icons.local_shipping, size: 40, color: Colors.blue),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Carte itinéraire ───────────────────────────────────────
            _buildRouteMap(mission),
            const SizedBox(height: 20),

            // ── Destinataire (numéro masqué) ──────────────────────────
            if (mission.recipientName != null) ...[
              const Text('Destinataire',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(mission.recipientName!),
                subtitle: Text(_maskPhone(mission.recipientPhone ?? '')),
                // Numéro masqué — pas de bouton appel direct (anti-contournement)
              ),
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
    final hasPickup   = mission.pickupLat != null;
    final hasDelivery = mission.deliveryLat != null;

    if (!hasPickup && !hasDelivery) return const SizedBox.shrink();

    final center = hasPickup
        ? LatLng(mission.pickupLat!, mission.pickupLng!)
        : LatLng(mission.deliveryLat!, mission.deliveryLng!);

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.hardEdge,
      child: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 13),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.pickupoint.app',
          ),
          if (hasPickup && hasDelivery)
            PolylineLayer(polylines: [
              Polyline(
                points: [
                  LatLng(mission.pickupLat!, mission.pickupLng!),
                  LatLng(mission.deliveryLat!, mission.deliveryLng!),
                ],
                color: Colors.blue.withOpacity(0.6),
                strokeWidth: 3,
                isDotted: true,
              ),
            ]),
          MarkerLayer(markers: [
            if (hasPickup)
              Marker(
                point: LatLng(mission.pickupLat!, mission.pickupLng!),
                width: 40, height: 40,
                child: const Icon(Icons.store, color: Colors.orange, size: 32),
              ),
            if (hasDelivery)
              Marker(
                point: LatLng(mission.deliveryLat!, mission.deliveryLng!),
                width: 40, height: 40,
                child: const Icon(Icons.location_on, color: Colors.red, size: 32),
              ),
          ]),
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
      ]);
    }

    // Statut "in_progress" → livraison en cours → valider ou signaler
    if (status == 'in_progress') {
      return Column(children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : () => _confirmDelivery(mission.parcelId),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Valider la livraison (QR / code)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _isProcessing ? null : () => _showFailDialog(mission.parcelId),
            icon: const Icon(Icons.report_problem, color: Colors.red),
            label: const Text('Impossible de livrer', style: TextStyle(color: Colors.red)),
          ),
        ),
      ]);
    }

    return const SizedBox.shrink();
  }
}
```

---

### B8 — Flutter : `api_client.dart` — ajouter `confirmPickup`

```dart
Future<Response> confirmPickup(String missionId, String code) =>
    _dio.post(
      '${ApiEndpoints.base}/api/deliveries/$missionId/confirm-pickup',
      data: {'code': code},
    );
```

Modifier `deliverParcel` pour envoyer `delivery_code` + GPS :
```dart
Future<Response> deliverParcel(String parcelId, Map<String, dynamic> body) =>
    _dio.post('${ApiEndpoints.parcel(parcelId)}/deliver', data: body);
```

---

## BLOC C — Anti-détournement géofence (récapitulatif)

Déjà traité dans **A3** (endpoint `deliver` avec géofence 500m).

### C1 — Vérification optionnelle au pickup

Optionnel pour Phase 1 : si le livreur confirme le pickup avec un code valide, c'est suffisant comme preuve.

### C2 — Consultation du trail GPS (admin)

**Fichier** : `backend/routers/deliveries.py`

Ajouter :
```python
@router.get("/{mission_id}/trail", summary="Trail GPS complet (admin)")
async def get_gps_trail(
    mission_id: str,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    mission = await db.delivery_missions.find_one({"mission_id": mission_id}, {"_id": 0, "gps_trail": 1})
    if not mission:
        raise not_found_exception("Mission")
    return {"trail": mission.get("gps_trail", []), "count": len(mission.get("gps_trail", []))}
```

---

## BLOC D — Anti-contournement paiement

### D1 — Masquage du numéro de téléphone (Flutter)

Ajouter cette fonction utilitaire dans `mobile/lib/shared/utils/phone_utils.dart` (créer le fichier) :

```dart
/// Masque le milieu du numéro : +221 77 XXX XX 45
String maskPhone(String phone) {
  if (phone.length < 8) return phone;
  final visible = 3;
  final start = phone.substring(0, visible);
  final end   = phone.substring(phone.length - 2);
  final hidden = 'X' * (phone.length - visible - 2);
  return '$start$hidden$end';
}
```

Utiliser `maskPhone(mission.recipientPhone ?? '')` partout où le numéro du destinataire/expéditeur est affiché côté **livreur**.

Utiliser `maskPhone(parcel.recipientPhone ?? '')` côté **client** aussi (pour ne pas afficher le vrai numéro livreur à rebours).

**Règle** : le numéro complet n'est jamais visible dans l'app. Uniquement masqué.

---

### D2 — Pas de bouton "Appeler directement"

Dans `mission_detail_screen.dart` et `driver_home.dart` : **supprimer** tout `IconButton` avec `Icons.phone` qui lance un appel direct.

Remplacer par : un bouton "Contacter via PickuPoint" qui ouvre un dialog d'information (Phase 1 = pas encore de chat, mais on pose la base).

```dart
// À la place du bouton appel direct :
IconButton(
  icon: const Icon(Icons.phone_in_talk, color: Colors.grey),
  tooltip: 'Contact via PickuPoint (prochainement)',
  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Chat in-app disponible prochainement.')),
  ),
),
```

---

### D3 — Paiement bloqué sans code de livraison validé

La logique est déjà dans **A3** : `distribute_delivery_revenue` n'est appelé que dans `transition_status(DELIVERED)`, qui ne peut être déclenché que si le `delivery_code` est validé dans l'endpoint `/deliver`.

**Donc** : pas de paiement livreur sans validation du code. Le wallet n'est jamais crédité si le livreur marque "livré" sans code.

---

### D4 — COD (paiement à la réception) — Phase 1 contrôlé

Pour `who_pays = "recipient"` :

**Fichier** : `backend/services/wallet_service.py`

Dans `distribute_delivery_revenue`, ajouter en début de fonction :
```python
# COD : paiement à la livraison — le client paye en cash au livreur
# Le livreur reverse la plateforme et les relais via son wallet (Phase 2)
# Phase 1 : log seulement, on ne crédite pas le wallet automatiquement
if parcel.get("who_pays") == "recipient":
    logger.info(
        "COD livraison %s — montant %s XOF — à réconcilier manuellement",
        parcel.get("parcel_id"), price
    )
    # TODO Phase 2 : intégration paiement à la remise (Wave/OM via API)
    return
```

---

### D5 — Alerte comportementale (bonus/malus livreurs)

**Fichier** : `backend/services/dynamic_pricing.py`

Ajouter dans `log_delivery_data()` un calcul du taux de scan :
```python
# Dans le document inséré dans delivery_logs, ajouter :
"validated_by_code": True,   # toujours True si on arrive ici (code obligatoire)
```

**Fichier** : `backend/routers/users.py` (ou admin router)

Ajouter un endpoint stats livreur (admin) :
```python
@router.get("/{user_id}/driver-stats", summary="Statistiques livreur (admin)")
async def driver_stats(
    user_id: str,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    total      = await db.delivery_missions.count_documents({"driver_id": user_id})
    completed  = await db.delivery_missions.count_documents({"driver_id": user_id, "status": "completed"})
    failed     = await db.delivery_missions.count_documents({"driver_id": user_id, "status": "failed"})
    scan_rate  = round(completed / max(total, 1) * 100, 1)
    return {
        "total_missions": total,
        "completed":      completed,
        "failed":         failed,
        "scan_rate_pct":  scan_rate,   # 100% = toutes les livraisons validées par code
    }
```

---

## RÉCAPITULATIF DES FICHIERS À MODIFIER / CRÉER

### Backend

| Fichier | Action |
|---|---|
| `models/parcel.py` | Ajouter `pickup_code`, `delivery_code` dans `Parcel` |
| `models/delivery.py` | Ajouter `CodeDelivery` model |
| `services/parcel_service.py` | `_generate_code()`, générer codes à création, notif SMS destinataire |
| `services/notification_service.py` | Ajouter `notify_delivery_code()` |
| `services/wallet_service.py` | Bloquer distribution si `who_pays=recipient` (COD) |
| `services/dynamic_pricing.py` | Ajouter `validated_by_code` dans delivery_logs |
| `routers/deliveries.py` | Ajouter `confirm-pickup`, modifier `update_location` (trail), ajouter `trail` endpoint |
| `routers/parcels.py` | Modifier `deliver` (code + géofence), ajouter `/codes`, ajouter `/driver-location` |
| `routers/users.py` | Ajouter `driver-stats` |

### Flutter

| Fichier | Action |
|---|---|
| `pubspec.yaml` | Ajouter `flutter_map: ^6.1.0`, `latlong2: ^0.9.0` |
| `core/models/parcel.dart` | Ajouter `deliveryCode`, `deliveryLat`, `deliveryLng` |
| `core/api/api_endpoints.dart` | Ajouter endpoints codes + driver-location + confirm-pickup |
| `core/api/api_client.dart` | Ajouter `confirmPickup()`, `getDriverLocation()`, modifier `deliverParcel()` |
| `shared/utils/phone_utils.dart` | **Créer** — fonction `maskPhone()` |
| `features/client/screens/parcel_detail_screen.dart` | Réécrire — carte temps réel + delivery_code |
| `features/driver/screens/mission_detail_screen.dart` | Réécrire — carte itinéraire + scan QR/code pickup + delivery |

---

## ORDRE D'IMPLÉMENTATION RECOMMANDÉ

```
1. pubspec.yaml → flutter pub get
2. models/parcel.py (pickup_code, delivery_code)
3. models/delivery.py (CodeDelivery)
4. services/parcel_service.py (_generate_code, codes dans create_parcel)
5. services/notification_service.py (notify_delivery_code)
6. routers/parcels.py (modifier deliver, ajouter /codes, /driver-location)
7. routers/deliveries.py (confirm-pickup, trail dans update_location, endpoint trail)
8. routers/users.py (driver-stats)
9. services/wallet_service.py (bloquer COD)
10. ── Tests backend avec curl / Swagger ──
11. shared/utils/phone_utils.dart (maskPhone)
12. core/models/parcel.dart (deliveryCode, deliveryLat/Lng)
13. core/api/api_client.dart + api_endpoints.dart
14. features/client/screens/parcel_detail_screen.dart (carte + code)
15. features/driver/screens/mission_detail_screen.dart (carte + scan + codes)
16. ── Test Flutter sur émulateur ──
```

---

## NOTES IMPORTANTES

- **OpenStreetMap** : gratuit, pas d'API key, tiles `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
- **Géofence 500m** : valeur par défaut raisonnable pour Dakar. Rendre configurable via `config.py` (`DELIVERY_GEOFENCE_METERS: float = 500.0`) si nécessaire
- **Numéros masqués** : masquage côté Flutter uniquement pour Phase 1. Phase 2 = Twilio Proxy (numéro relais PickuPoint pour les appels)
- **COD Phase 1** : juste un log + retour sans créditer wallets. Le livreur et la plateforme se réconcilieront manuellement. Phase 2 = Wave API pour reversement automatique
- **GPS Trail** : limité à 300 points par mission via `$slice: -300` MongoDB. Chaque point = position toutes les 30s = environ 2h30 de trail stocké
- **`_haversine_km`** est dans `pricing_service.py` — l'importer directement dans `parcels.py` avec `from services.pricing_service import _haversine_km`
