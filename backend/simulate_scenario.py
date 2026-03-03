"""
simulate_scenario.py — Crée (si besoin) 2 relais distincts + 2 agents + 1 expéditeur + 1 client,
puis insère UN colis de test RELAY_TO_RELAY avec tous les codes nécessaires.

Usage :
    cd pickupoint/backend
    python simulate_scenario.py

OTP universel en DEBUG : 123456
"""
import asyncio
import os
import sys
import random
import uuid

from datetime import datetime, timezone, timedelta

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus, DeliveryMode
from services.parcel_service import _parcel_id, _event_id


# ── Comptes de test fixes ────────────────────────────────────────────────────
ACCOUNTS = {
    "sender":   {"phone": "+221770000003", "name": "Fatou Diallo (Expéditrice)", "role": "client"},
    "recipient":{"phone": "+221770000004", "name": "Ibrahima Sow (Destinataire)", "role": "client"},
    "driver":   {"phone": "+221770000001", "name": "Moussa (Livreur)",            "role": "driver"},
    "agent_a":  {"phone": "+221770000002", "name": "Boutique Relais Médina",      "role": "relay_agent"},
    "agent_b":  {"phone": "+221770000005", "name": "Boutique Relais Plateau",     "role": "relay_agent"},
}

RELAY_A = {
    "name": "Relais Médina (Origine)",
    "address": {
        "label":    "Médina, Rue 11x12",
        "city":     "Dakar",
        "district": "Médina",
        "geopin":   {"lat": 14.6789, "lng": -17.4456},
    },
}

RELAY_B = {
    "name": "Relais Plateau (Destination)",
    "address": {
        "label":    "Plateau, Avenue Pompidou",
        "city":     "Dakar",
        "district": "Plateau",
        "geopin":   {"lat": 14.6930, "lng": -17.4380},
    },
}


def _user_id() -> str:
    return f"usr_{uuid.uuid4().hex[:12]}"

def _relay_id() -> str:
    return f"rly_{uuid.uuid4().hex[:12]}"


async def _ensure_user(phone: str, name: str, role: str) -> dict:
    """Retourne l'utilisateur existant ou en crée un nouveau."""
    user = await db.users.find_one({"phone": phone})
    if user:
        # Met à jour le rôle et le nom si nécessaire
        await db.users.update_one(
            {"phone": phone},
            {"$set": {"role": role, "name": name, "updated_at": datetime.now(timezone.utc)}},
        )
        return await db.users.find_one({"phone": phone})

    now     = datetime.now(timezone.utc)
    user_id = _user_id()
    doc     = {
        "user_id":           user_id,
        "phone":             phone,
        "name":              name,
        "role":              role,
        "is_active":         True,
        "is_phone_verified": True,
        "relay_point_id":    None,
        "created_at":        now,
        "updated_at":        now,
    }
    await db.users.insert_one(doc)
    print(f"    ✅ Créé  {role:<12} {phone}  ({name})")
    return doc


async def _ensure_relay(owner_user_id: str, relay_info: dict) -> dict:
    """Retourne le relais lié à cet owner ou en crée un."""
    relay = await db.relay_points.find_one({"owner_user_id": owner_user_id})
    if relay:
        # Met à jour l'adresse au format correct si besoin
        await db.relay_points.update_one(
            {"relay_id": relay["relay_id"]},
            {"$set": {
                "name":       relay_info["name"],
                "address":    relay_info["address"],
                "updated_at": datetime.now(timezone.utc),
            }},
        )
        return await db.relay_points.find_one({"owner_user_id": owner_user_id})

    now      = datetime.now(timezone.utc)
    relay_id = _relay_id()
    doc      = {
        "relay_id":           relay_id,
        "owner_user_id":      owner_user_id,
        "agent_user_ids":     [],
        "name":               relay_info["name"],
        "address":            relay_info["address"],
        "phone":              "",
        "max_capacity":       20,
        "current_load":       0,
        "opening_hours":      "08h-20h",
        "zone_ids":           [],
        "coverage_radius_km": 5.0,
        "is_active":          True,
        "is_verified":        True,
        "score":              5.0,
        "created_at":         now,
        "updated_at":         now,
    }
    await db.relay_points.insert_one(doc)
    print(f"    ✅ Relais créé : {relay_info['name']}")
    return doc


async def setup_accounts() -> dict:
    """Crée ou récupère tous les comptes et relais nécessaires. Retourne les objets."""
    print("\n🔧  Vérification / création des comptes de test…")

    sender    = await _ensure_user(**ACCOUNTS["sender"])
    recipient = await _ensure_user(**ACCOUNTS["recipient"])
    driver    = await _ensure_user(**ACCOUNTS["driver"])
    agent_a   = await _ensure_user(**ACCOUNTS["agent_a"])
    agent_b   = await _ensure_user(**ACCOUNTS["agent_b"])

    # Relais A lié à agent_a
    relay_a = await _ensure_relay(agent_a["user_id"], RELAY_A)
    await db.users.update_one(
        {"user_id": agent_a["user_id"]},
        {"$set": {"relay_point_id": relay_a["relay_id"]}},
    )

    # Relais B lié à agent_b
    relay_b = await _ensure_relay(agent_b["user_id"], RELAY_B)
    await db.users.update_one(
        {"user_id": agent_b["user_id"]},
        {"$set": {"relay_point_id": relay_b["relay_id"]}},
    )

    # Re-fetch après update pour avoir relay_point_id à jour
    agent_a = await db.users.find_one({"user_id": agent_a["user_id"]})
    agent_b = await db.users.find_one({"user_id": agent_b["user_id"]})

    return {
        "sender": sender, "recipient": recipient, "driver": driver,
        "agent_a": agent_a, "agent_b": agent_b,
        "relay_a": relay_a, "relay_b": relay_b,
    }


async def create_test_parcel():
    await connect_db()

    ctx = await setup_accounts()

    sender  = ctx["sender"]
    relay_a = ctx["relay_a"]
    relay_b = ctx["relay_b"]

    # ── Codes ────────────────────────────────────────────────────────────────
    now           = datetime.now(timezone.utc)
    parcel_id     = _parcel_id()
    tracking_code = f"PKP-{random.randint(100, 999)}-{random.randint(1000, 9999)}"
    pickup_code   = str(random.randint(100000, 999999))
    delivery_code = str(random.randint(100000, 999999))
    pin_code      = str(random.randint(1000, 9999))

    # ── Colis ────────────────────────────────────────────────────────────────
    parcel_doc = {
        "parcel_id":            parcel_id,
        "tracking_code":        tracking_code,
        "sender_user_id":       sender["user_id"],
        "sender_name":          sender["name"],
        "recipient_name":       ctx["recipient"]["name"],
        "recipient_phone":      ctx["recipient"]["phone"],
        "recipient_user_id":    ctx["recipient"]["user_id"],
        "delivery_mode":        DeliveryMode.RELAY_TO_RELAY.value,
        "origin_relay_id":      relay_a["relay_id"],
        "destination_relay_id": relay_b["relay_id"],
        "delivery_address":     None,
        "weight_kg":            1.5,
        "declared_value":       5000,
        "quoted_price":         1500,
        "payment_status":       "paid",
        "payment_method":       None,
        "payment_ref":          None,
        "is_insured":           False,
        "is_express":           False,
        "who_pays":             "sender",
        "pickup_code":          pickup_code,   # 6 chiffres — livreur donne au relais A
        "delivery_code":        delivery_code, # 6 chiffres — livreur domicile (non utilisé ici)
        "relay_pin":            pin_code,      # 4 chiffres — destinataire donne au relais B
        "assigned_driver_id":   None,
        "redirect_relay_id":    None,
        "status":               ParcelStatus.CREATED.value,
        "created_at":           now,
        "updated_at":           now,
        "expires_at":           now + timedelta(days=7),
    }
    await db.parcels.insert_one(parcel_doc)
    await db.parcel_events.insert_one({
        "event_id":    _event_id(),
        "parcel_id":   parcel_id,
        "event_type":  "STATUS_CHANGED",
        "from_status": None,
        "to_status":   ParcelStatus.CREATED.value,
        "actor_id":    sender["user_id"],
        "actor_role":  "client",
        "notes":       "Colis créé — simulation test",
        "created_at":  now,
    })

    # ── Affichage ─────────────────────────────────────────────────────────────
    sep  = "═" * 64
    dash = "─" * 64

    print(f"""
{sep}
  ✅  COLIS DE TEST CRÉÉ
{sep}
  📦  Code de suivi     :  {tracking_code}
  🔑  Code livreur      :  {pickup_code}     (relais A → livreur)
  🔒  PIN destinataire  :  {pin_code}         (relais B → destinataire)
  🔑  OTP universel     :  123456  (DEBUG)
{sep}
  📍  Relais A (Origine)      :  {relay_a["name"]}
  📍  Relais B (Destination)  :  {relay_b["name"]}
{sep}

{dash}
 ÉTAPE 1 — CLIENT expéditeur voit son colis  [CREATED]
{dash}
  Compte : +221770000003  /  OTP : 123456  (Fatou Diallo)
  → Liste : le colis {tracking_code} s'affiche
  → Tape dessus → timeline : "Créé"

{dash}
 ÉTAPE 2 — RELAIS A réceptionne  [→ DROPPED_AT_ORIGIN_RELAY]
{dash}
  Compte : +221770000002  /  OTP : 123456  ({relay_a["name"]})
  → "Réceptionner" → saisir : {tracking_code} → Confirmer
  → La carte du colis apparaît dans le stock
  → Tape dessus → bottom sheet → "Afficher le code livreur"
  → Code livreur : {pickup_code}  ← donne-le au livreur

{dash}
 ÉTAPE 3 — LIVREUR accepte + confirme la collecte  [mission in_progress]
{dash}
  Compte : +221770000001  /  OTP : 123456  (Moussa)
  → Active le toggle disponible (en haut)
  → Onglet Missions → mission {tracking_code} visible
  → "Accepter la course"
  → Dans la mission → "Confirmer la collecte (QR / code)"
  → Saisir : {pickup_code}
  → ✅ "Collecte confirmée ! Bonne route."

{dash}
 ÉTAPE 4 — RELAIS B réceptionne le colis arrivé  [→ AVAILABLE_AT_RELAY]
{dash}
  Compte : +221770000005  /  OTP : 123456  ({relay_b["name"]})
  (Le livreur a physiquement apporté le colis ici)
  → "Réceptionner" → saisir : {tracking_code} → Confirmer
  → L'app appelle arrive-relay :
    DROPPED → IN_TRANSIT → AT_DESTINATION → AVAILABLE ✅
  → Badge "DISPONIBLE AU RELAIS" sur la carte

{dash}
 ÉTAPE 5 — RELAIS B remet au destinataire  [→ DELIVERED]
{dash}
  Compte : +221770000005  /  OTP : 123456
  → Tape sur la carte → "Remettre au destinataire"
     OU bouton FAB "Remettre Client"
  → Saisir : {tracking_code}
  → Dialog PIN → saisir : {pin_code}
  → ✅ "Colis remis au destinataire !"

{dash}
 ÉTAPE 6 — CLIENT expéditeur voit la timeline complète  [DELIVERED]
{dash}
  Compte : +221770000003  /  OTP : 123456
  → Tape sur {tracking_code} → timeline avec tous les événements
  → Badge vert "LIVRÉ"

{sep}
 RÉCAPITULATIF — à garder sous la main
{sep}
  Code de suivi    →  {tracking_code}
  Code livreur     →  {pickup_code}     (étape 3)
  PIN remise       →  {pin_code}         (étape 5)

  Relais A  →  +221770000002  (réceptionne à l'étape 2)
  Relais B  →  +221770000005  (réceptionne + remet aux étapes 4-5)
  Livreur   →  +221770000001  (étape 3)
  Client    →  +221770000003  (étapes 1 et 6)
{sep}
""")


async def main():
    await create_test_parcel()


if __name__ == "__main__":
    asyncio.run(main())
