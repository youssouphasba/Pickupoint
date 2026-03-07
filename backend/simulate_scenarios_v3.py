"""
simulate_scenarios_v3.py — Scenarios de test complets (v3)

Couvre tous les changements recents :
  - Flux auth complet : OTP + PIN login + accepted_legal
  - Notes vocales (pickup_voice_note, delivery_voice_note)
  - Mise a jour adresse GPS (PUT /delivery-address)
  - Flux payout livreur (demande en attente pour test admin)
  - 4 modes de livraison a etapes variees (debut / milieu / fin)
  - Redirection (DELIVERY_FAILED -> REDIRECTED_TO_RELAY)
  - is_express, who_pays
  - Wallet avec solde pour tester les retraits

Usage :
    cd pickupoint/backend
    python simulate_scenarios_v3.py          # cree tout
    python simulate_scenarios_v3.py --wipe   # purge d'abord, puis recrée

Comptes de test (OTP fixe 123456, PIN 1234) :
  +221770000000  admin          Ibou Admin
  +221770000001  driver         Moussa Livreur
  +221770000002  relay_agent    Aminata (Relais Medina - Dakar)
  +221770000003  client         Fatou Diallo (expeditrice)
  +221770000004  client         Ibrahima Sow (destinataire)
  +221770000005  relay_agent    Cheikh (Relais Plateau - Dakar)
  +221770000006  relay_agent    Marème (Relais Escale - Thies)
"""
import asyncio
import os
import random
import sys
import uuid
from datetime import datetime, timezone, timedelta

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import db, connect_db
from models.common import ParcelStatus, DeliveryMode
from core.security import hash_password
from services.parcel_service import _parcel_id, _event_id, _create_delivery_mission

# ─── Comptes ────────────────────────────────────────────────────────────────

PIN_HASH = hash_password("1234")

ACCOUNTS = [
    {"phone": "+221770000000", "name": "Ibou Admin",                 "role": "admin"},
    {"phone": "+221770000001", "name": "Moussa Livreur",             "role": "driver"},
    {"phone": "+221770000002", "name": "Aminata (Relais Medina)",    "role": "relay_agent"},
    {"phone": "+221770000003", "name": "Fatou Diallo (Expeditrice)", "role": "client"},
    {"phone": "+221770000004", "name": "Ibrahima Sow (Destinataire)","role": "client"},
    {"phone": "+221770000005", "name": "Cheikh (Relais Plateau)",    "role": "relay_agent"},
    {"phone": "+221770000006", "name": "Mareme (Relais Escale)",     "role": "relay_agent"},
]

RELAYS_DEF = [
    {
        "owner_phone": "+221770000002",
        "name": "Relais Medina (Dakar)",
        "phone": "+221338001001",
        "address": {"label": "Medina, Rue 11", "city": "Dakar",
                    "geopin": {"lat": 14.6789, "lng": -17.4456}},
        "max_capacity": 50,
    },
    {
        "owner_phone": "+221770000005",
        "name": "Relais Plateau (Dakar)",
        "phone": "+221338002002",
        "address": {"label": "Plateau, Av. Pompidou", "city": "Dakar",
                    "geopin": {"lat": 14.6930, "lng": -17.4380}},
        "max_capacity": 40,
    },
    {
        "owner_phone": "+221770000006",
        "name": "Relais Escale (Thies)",
        "phone": "+221338003003",
        "address": {"label": "Escale, Rue de France", "city": "Thies",
                    "geopin": {"lat": 14.7910, "lng": -16.9350}},
        "max_capacity": 30,
    },
]

# ─── Helpers ─────────────────────────────────────────────────────────────────

def _tracking_code():
    return f"PKP-{random.randint(100,999)}-{random.randint(1000,9999)}"

def _pin6():
    return str(random.randint(100000, 999999))

def _pin4():
    return str(random.randint(1000, 9999))

def _event(parcel_id, status, actor_id, actor_role, note="", ts=None):
    return {
        "event_id":   _event_id(),
        "parcel_id":  parcel_id,
        "status":     status,
        "actor_id":   actor_id,
        "actor_role": actor_role,
        "note":       note,
        "timestamp":  ts or datetime.now(timezone.utc),
    }


async def _ensure_user(phone, name, role):
    now = datetime.now(timezone.utc)
    from services.user_service import generate_referral_code
    user = await db.users.find_one({"phone": phone})
    base = {
        "name":              name,
        "role":              role,
        "is_active":         True,
        "is_banned":         False,
        "is_phone_verified": True,
        "accepted_legal":    True,
        "accepted_legal_at": now,
        "pin_hash":          PIN_HASH,
        "email":             None,
        "user_type":         "individual",
        "language":          "fr",
        "currency":          "XOF",
        "country_code":      "SN",
        "loyalty_points":    0,
        "loyalty_tier":      "bronze",
        "referral_code":     generate_referral_code(phone),
        "referred_by":       None,
        "referral_credited": False,
        "xp":                0,
        "level":             1,
        "badges":            [],
        "deliveries_completed": 0,
        "on_time_deliveries":   0,
        "total_rating_sum":     0.0,
        "total_ratings_count":  0,
        "average_rating":       0.0,
        "cod_balance":          0.0,
        "total_earned":         0.0,
        "notification_prefs":   {"push": True, "email": True, "whatsapp": True},
        "kyc_status":           "none",
        "relay_point_id":       None,
        "profile_picture_url":  None,
        "updated_at":           now,
    }
    if user:
        await db.users.update_one({"phone": phone}, {"$set": base})
        user.update(base)
        return user
    doc = {"user_id": f"usr_{uuid.uuid4().hex[:12]}", "phone": phone,
           "created_at": now, **base}
    await db.users.insert_one(doc)
    return doc


async def _ensure_relay(owner_id, defn):
    relay = await db.relay_points.find_one({"owner_user_id": owner_id})
    now = datetime.now(timezone.utc)
    base = {
        "name":         defn["name"],
        "phone":        defn["phone"],
        "address":      defn["address"],
        "is_active":    True,
        "is_verified":  True,
        "max_capacity": defn["max_capacity"],
        "current_load": 0,
        "updated_at":   now,
    }
    if relay:
        await db.relay_points.update_one({"relay_id": relay["relay_id"]}, {"$set": base})
        relay.update(base)
        return relay
    doc = {"relay_id": f"rly_{uuid.uuid4().hex[:12]}", "owner_user_id": owner_id,
           "created_at": now, **base}
    await db.relay_points.insert_one(doc)
    return doc


async def _ensure_wallet(user_id, balance=0.0, pending=0.0):
    w = await db.wallets.find_one({"owner_id": user_id})
    if w:
        await db.wallets.update_one({"owner_id": user_id},
                                    {"$set": {"balance": balance, "pending_balance": pending}})
        return w
    doc = {
        "wallet_id":       f"wlt_{uuid.uuid4().hex[:12]}",
        "owner_id":        user_id,
        "owner_type":      "user",
        "balance":         balance,
        "pending_balance": pending,
        "currency":        "XOF",
        "created_at":      datetime.now(timezone.utc),
    }
    await db.wallets.insert_one(doc)
    return doc


async def _make_parcel(label, mode, sender, recipient,
                       origin_relay_id=None, dest_relay_id=None,
                       origin_loc=None, dest_addr=None,
                       status=ParcelStatus.CREATED,
                       assigned_driver_id=None,
                       redirect_relay_id=None,
                       is_express=False, who_pays="sender",
                       pickup_voice_note=None, delivery_voice_note=None,
                       events=None, quoted_price=None):
    now = datetime.now(timezone.utc)
    p_id = _parcel_id()
    t_code = _tracking_code()
    pickup_code = _pin6()

    home_delivery  = mode.value.endswith("_to_home")
    relay_delivery = mode.value.endswith("_to_relay")
    delivery_code  = _pin4() if home_delivery  else ""
    relay_pin      = _pin4() if relay_delivery else ""

    base_price = {"relay_to_relay": 700, "relay_to_home": 1100,
                  "home_to_relay": 900, "home_to_home": 1300}[mode.value]
    if quoted_price is None:
        quoted_price = int(base_price * (1.40 if is_express else 1.0))

    doc = {
        "parcel_id":       p_id,
        "tracking_code":   t_code,
        "status":          status.value,
        "delivery_mode":   mode.value,
        "sender_user_id":  sender["user_id"],
        "sender_name":     sender["name"],
        "recipient_name":  recipient["name"],
        "recipient_phone": recipient["phone"],
        "recipient_user_id": recipient["user_id"],
        "origin_relay_id":      origin_relay_id,
        "destination_relay_id": dest_relay_id,
        "origin_location":  origin_loc,
        "delivery_address": dest_addr,
        "quoted_price":    quoted_price,
        "payment_status":  "paid",
        "payment_method":  "wave",
        "payment_ref":     f"PAY-{uuid.uuid4().hex[:8].upper()}",
        "is_express":      is_express,
        "who_pays":        who_pays,
        "pickup_code":     pickup_code,
        "delivery_code":   delivery_code,
        "relay_pin":       relay_pin,
        "assigned_driver_id":  assigned_driver_id,
        "redirect_relay_id":   redirect_relay_id,
        "pickup_voice_note":   pickup_voice_note,
        "delivery_voice_note": delivery_voice_note,
        "pickup_confirmed":    status not in (ParcelStatus.CREATED,),
        "delivery_confirmed":  relay_delivery,
        "is_simulation":   True,
        "weight_kg":       1.5,
        "dimensions":      None,
        "created_at":      now,
        "updated_at":      now,
        "expires_at":      now + timedelta(days=7),
    }
    await db.parcels.insert_one(doc)

    # Événements timeline
    evts = events or []
    if evts:
        await db.parcel_events.insert_many([_event(p_id, **e) for e in evts])

    print(f"  [{status.value:30s}] {label}")
    print(f"    tracking={t_code}  pickup_code={pickup_code}", end="")
    if relay_pin:     print(f"  relay_pin={relay_pin}", end="")
    if delivery_code: print(f"  delivery_code={delivery_code}", end="")
    if is_express:    print("  🚀EXPRESS", end="")
    if who_pays == "recipient": print("  💳RECIPIENT_PAYS", end="")
    print()
    return doc


# ─── Main ────────────────────────────────────────────────────────────────────

async def main(wipe=False):
    await connect_db()

    if wipe:
        print("\n--- PURGE ---")
        r1 = await db.parcels.delete_many({"is_simulation": True})
        r2 = await db.parcel_events.delete_many({})
        r3 = await db.delivery_missions.delete_many({})
        await db.relay_points.update_many({}, {"$set": {"current_load": 0}})
        print(f"  {r1.deleted_count} colis  |  {r2.deleted_count} evts  |  {r3.deleted_count} missions  supprimés")

    # ── 1. Comptes ──────────────────────────────────────────────────────────
    print("\n--- COMPTES ---")
    users = {}
    for acc in ACCOUNTS:
        u = await _ensure_user(**acc)
        users[acc["phone"]] = u
        print(f"  [{acc['role']:12s}] {acc['name']} ({acc['phone']})  user_id={u['user_id']}")

    admin   = users["+221770000000"]
    driver  = users["+221770000001"]
    fatou   = users["+221770000003"]
    ibra    = users["+221770000004"]

    # ── 2. Relais ───────────────────────────────────────────────────────────
    print("\n--- RELAIS ---")
    relays = {}
    for defn in RELAYS_DEF:
        owner = users[defn["owner_phone"]]
        r = await _ensure_relay(owner["user_id"], defn)
        relays[defn["owner_phone"]] = r
        # lier l'agent à son relais
        await db.users.update_one({"user_id": owner["user_id"]},
                                  {"$set": {"relay_point_id": r["relay_id"]}})
        print(f"  {defn['name']}  relay_id={r['relay_id']}")

    medina  = relays["+221770000002"]
    plateau = relays["+221770000005"]
    escale  = relays["+221770000006"]

    # ── 3. Wallets ──────────────────────────────────────────────────────────
    print("\n--- WALLETS ---")
    await _ensure_wallet(driver["user_id"],  balance=12500, pending=3500)
    await _ensure_wallet(admin["user_id"],   balance=0)
    await _ensure_wallet(fatou["user_id"],   balance=500)
    await _ensure_wallet(ibra["user_id"],    balance=0)
    for phone in ["+221770000002", "+221770000005", "+221770000006"]:
        await _ensure_wallet(users[phone]["user_id"], balance=4200)
    print("  Wallets initialisés (driver=12500 XOF + 3500 pending, relais=4200 XOF chacun)")

    # Payout en attente pour test admin
    payout_w = await db.wallets.find_one({"owner_id": driver["user_id"]})
    existing_payout = await db.wallet_transactions.find_one(
        {"owner_id": driver["user_id"], "tx_type": "payout_request", "status": "pending"}
    )
    if not existing_payout:
        await db.wallet_transactions.insert_one({
            "tx_id":       f"txn_{uuid.uuid4().hex[:12]}",
            "wallet_id":   payout_w["wallet_id"],
            "owner_id":    driver["user_id"],
            "tx_type":     "payout_request",
            "amount":      5000,
            "currency":    "XOF",
            "status":      "pending",
            "description": "Retrait Wave — simulation test",
            "payout_method": "wave",
            "payout_phone":  driver["phone"],
            "created_at":  datetime.now(timezone.utc),
        })
        print("  Demande de retrait PENDING créée pour Moussa (5000 XOF)")

    # ── 4. Scénarios ────────────────────────────────────────────────────────
    print("\n--- SCENARIOS DE LIVRAISON ---")

    loc_fatou  = {"label": "Chez Fatou, Medina",  "city": "Dakar",  "geopin": {"lat": 14.680, "lng": -17.443}}
    loc_ibra   = {"label": "Bureau Ibrahima, Plateau", "city": "Dakar",  "geopin": {"lat": 14.710, "lng": -17.430}}
    loc_ibra2  = {"label": "Domicile Ibrahima, Thies", "city": "Thies", "geopin": {"lat": 14.795, "lng": -16.940}}

    # ══════════════ RELAY-TO-RELAY ══════════════

    await _make_parcel(
        "R2R-1 | CREATED — en attente dépôt relais origine",
        DeliveryMode.RELAY_TO_RELAY, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_relay_id=escale["relay_id"],
        status=ParcelStatus.CREATED,
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Colis créé"}],
    )

    await _make_parcel(
        "R2R-2 | DROPPED_AT_ORIGIN_RELAY — au relais Medina, livreur pas encore assigné",
        DeliveryMode.RELAY_TO_RELAY, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_relay_id=escale["relay_id"],
        status=ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        events=[
            {"status": ParcelStatus.CREATED.value,              "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value, "actor_id": users["+221770000002"]["user_id"], "actor_role": "relay_agent", "note": "Reçu au relais Medina"},
        ],
    )

    p_r2r_transit = await _make_parcel(
        "R2R-3 | IN_TRANSIT — livreur en route Dakar→Thiès",
        DeliveryMode.RELAY_TO_RELAY, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_relay_id=escale["relay_id"],
        status=ParcelStatus.IN_TRANSIT,
        assigned_driver_id=driver["user_id"],
        events=[
            {"status": ParcelStatus.CREATED.value,              "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value, "actor_id": users["+221770000002"]["user_id"], "actor_role": "relay_agent"},
            {"status": ParcelStatus.IN_TRANSIT.value,           "actor_id": driver["user_id"], "actor_role": "driver", "note": "Collecté au relais Medina"},
        ],
        is_express=True,
    )
    # Mission livreur pour ce colis
    await db.delivery_missions.insert_one({
        "mission_id":  f"msn_{uuid.uuid4().hex[:12]}",
        "parcel_id":   p_r2r_transit["parcel_id"],
        "driver_id":   driver["user_id"],
        "status":      "in_progress",
        "pickup_relay_id": medina["relay_id"],
        "dropoff_relay_id": escale["relay_id"],
        "earn_amount": int(p_r2r_transit["quoted_price"] * 0.70),
        "assigned_at": datetime.now(timezone.utc) - timedelta(minutes=20),
        "started_at":  datetime.now(timezone.utc) - timedelta(minutes=15),
        "created_at":  datetime.now(timezone.utc) - timedelta(minutes=25),
    })

    await _make_parcel(
        "R2R-4 | AT_DESTINATION_RELAY — arrivé à Thiès, en attente destinataire",
        DeliveryMode.RELAY_TO_RELAY, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_relay_id=escale["relay_id"],
        status=ParcelStatus.AT_DESTINATION_RELAY,
        events=[
            {"status": ParcelStatus.CREATED.value,              "actor_id": fatou["user_id"],   "actor_role": "client"},
            {"status": ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value, "actor_id": users["+221770000002"]["user_id"], "actor_role": "relay_agent"},
            {"status": ParcelStatus.IN_TRANSIT.value,           "actor_id": driver["user_id"],  "actor_role": "driver"},
            {"status": ParcelStatus.AT_DESTINATION_RELAY.value, "actor_id": users["+221770000006"]["user_id"], "actor_role": "relay_agent", "note": "Scan entrée Escale Thiès"},
        ],
    )

    # ══════════════ HOME-TO-RELAY ══════════════

    p_h2r = await _make_parcel(
        "H2R-1 | CREATED — livreur doit collecter chez Fatou",
        DeliveryMode.HOME_TO_RELAY, fatou, ibra,
        origin_loc=loc_fatou, dest_relay_id=plateau["relay_id"],
        status=ParcelStatus.CREATED,
        pickup_voice_note="uploads/voice/note_test.m4a",  # simule URL fichier
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Note vocale laissée pour le livreur"}],
    )
    await _create_delivery_mission(p_h2r, ParcelStatus.CREATED)

    await _make_parcel(
        "H2R-2 | OUT_FOR_DELIVERY — livreur collecté, en route vers Relais Plateau",
        DeliveryMode.HOME_TO_RELAY, fatou, ibra,
        origin_loc=loc_fatou, dest_relay_id=plateau["relay_id"],
        status=ParcelStatus.OUT_FOR_DELIVERY,
        assigned_driver_id=driver["user_id"],
        who_pays="recipient",
        events=[
            {"status": ParcelStatus.CREATED.value,        "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value, "actor_id": driver["user_id"], "actor_role": "driver", "note": "Collecté chez l'expéditeur"},
        ],
    )

    await _make_parcel(
        "H2R-3 | AT_DESTINATION_RELAY — livré au Relais Plateau, PIN dispo",
        DeliveryMode.HOME_TO_RELAY, fatou, ibra,
        origin_loc=loc_fatou, dest_relay_id=plateau["relay_id"],
        status=ParcelStatus.AT_DESTINATION_RELAY,
        events=[
            {"status": ParcelStatus.CREATED.value,            "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value,   "actor_id": driver["user_id"], "actor_role": "driver"},
            {"status": ParcelStatus.AT_DESTINATION_RELAY.value, "actor_id": driver["user_id"], "actor_role": "driver", "note": "Déposé au Relais Plateau"},
        ],
    )

    # ══════════════ RELAY-TO-HOME ══════════════

    await _make_parcel(
        "R2H-1 | CREATED — livreur doit collecter au Relais Medina",
        DeliveryMode.RELAY_TO_HOME, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_addr=loc_ibra,
        status=ParcelStatus.CREATED,
        delivery_voice_note="uploads/voice/livraison_test.m4a",
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Instruction vocale pour la livraison"}],
    )

    p_r2h_out = await _make_parcel(
        "R2H-2 | OUT_FOR_DELIVERY — livreur en route vers domicile, adresse GPS confirmée",
        DeliveryMode.RELAY_TO_HOME, fatou, ibra,
        origin_relay_id=medina["relay_id"],
        dest_addr={"label": "Domicile Ibrahima (GPS confirmé)", "city": "Dakar",
                   "geopin": {"lat": 14.7123, "lng": -17.4290}},
        status=ParcelStatus.OUT_FOR_DELIVERY,
        assigned_driver_id=driver["user_id"],
        events=[
            {"status": ParcelStatus.CREATED.value,          "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value, "actor_id": driver["user_id"], "actor_role": "driver", "note": "Collecté au Relais Medina"},
        ],
        quoted_price=1650,  # 1100 * 1.50 (coeff dynamique)
    )

    await _make_parcel(
        "R2H-3 | DELIVERED — livré au domicile avec code confirmé",
        DeliveryMode.RELAY_TO_HOME, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_addr=loc_ibra,
        status=ParcelStatus.DELIVERED,
        events=[
            {"status": ParcelStatus.CREATED.value,          "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value, "actor_id": driver["user_id"], "actor_role": "driver"},
            {"status": ParcelStatus.DELIVERED.value,        "actor_id": driver["user_id"], "actor_role": "driver", "note": "Livré à domicile, code confirmé par le destinataire"},
        ],
    )

    # ══════════════ HOME-TO-HOME ══════════════

    p_h2h = await _make_parcel(
        "H2H-1 | CREATED — collecte domicile + livraison domicile, EXPRESS",
        DeliveryMode.HOME_TO_HOME, fatou, ibra,
        origin_loc=loc_fatou, dest_addr=loc_ibra2,
        status=ParcelStatus.CREATED,
        is_express=True,
        pickup_voice_note="uploads/voice/h2h_pickup.m4a",
        delivery_voice_note="uploads/voice/h2h_livraison.m4a",
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "2 notes vocales enregistrées"}],
    )
    await _create_delivery_mission(p_h2h, ParcelStatus.CREATED)

    await _make_parcel(
        "H2H-2 | OUT_FOR_DELIVERY — livreur en route domicile→domicile",
        DeliveryMode.HOME_TO_HOME, fatou, ibra,
        origin_loc=loc_fatou, dest_addr=loc_ibra,
        status=ParcelStatus.OUT_FOR_DELIVERY,
        assigned_driver_id=driver["user_id"],
        is_express=True,
        events=[
            {"status": ParcelStatus.CREATED.value,          "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value, "actor_id": driver["user_id"], "actor_role": "driver"},
        ],
    )

    await _make_parcel(
        "H2H-3 | DELIVERED — livré domicile à domicile",
        DeliveryMode.HOME_TO_HOME, fatou, ibra,
        origin_loc=loc_fatou, dest_addr=loc_ibra,
        status=ParcelStatus.DELIVERED,
        events=[
            {"status": ParcelStatus.CREATED.value,          "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value, "actor_id": driver["user_id"], "actor_role": "driver"},
            {"status": ParcelStatus.DELIVERED.value,        "actor_id": driver["user_id"], "actor_role": "driver", "note": "Code de livraison confirmé"},
        ],
    )

    # ══════════════ CAS SPÉCIAUX ══════════════

    await _make_parcel(
        "REDIRECT-1 | REDIRECTED_TO_RELAY — echec livraison domicile → redirigé Plateau",
        DeliveryMode.RELAY_TO_HOME, fatou, ibra,
        origin_relay_id=medina["relay_id"],
        dest_addr=loc_ibra,
        redirect_relay_id=plateau["relay_id"],
        status=ParcelStatus.REDIRECTED_TO_RELAY,
        events=[
            {"status": ParcelStatus.CREATED.value,              "actor_id": fatou["user_id"],  "actor_role": "client"},
            {"status": ParcelStatus.OUT_FOR_DELIVERY.value,     "actor_id": driver["user_id"], "actor_role": "driver"},
            {"status": ParcelStatus.DELIVERY_FAILED.value,      "actor_id": driver["user_id"], "actor_role": "driver", "note": "Absent à l'adresse, 3 tentatives"},
            {"status": ParcelStatus.REDIRECTED_TO_RELAY.value,  "actor_id": driver["user_id"], "actor_role": "driver", "note": "Redirigé vers Relais Plateau sur choix du livreur"},
        ],
    )

    await _make_parcel(
        "EXPRESS-1 | R2R express, destinataire paie",
        DeliveryMode.RELAY_TO_RELAY, fatou, ibra,
        origin_relay_id=plateau["relay_id"], dest_relay_id=escale["relay_id"],
        status=ParcelStatus.DROPPED_AT_ORIGIN_RELAY,
        is_express=True,
        who_pays="recipient",
        quoted_price=910,  # 700 * 1.30 arrondi
        events=[
            {"status": ParcelStatus.CREATED.value,              "actor_id": fatou["user_id"], "actor_role": "client"},
            {"status": ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value, "actor_id": users["+221770000005"]["user_id"], "actor_role": "relay_agent", "note": "Déposé au Relais Plateau, livraison express"},
        ],
    )

    # ── 5. Résumé ────────────────────────────────────────────────────────────
    total = await db.parcels.count_documents({"is_simulation": True})
    print(f"\n{'='*60}")
    print(f"[OK] {total} colis de test créés.")
    print()
    print("CONNEXION APP (OTP fixe 123456, PIN 1234) :")
    print("  Admin     : +221770000000")
    print("  Livreur   : +221770000001  (wallet: 12500 XOF, retrait 5000 en attente)")
    print("  Relais A  : +221770000002  (Medina, Dakar)")
    print("  Client S  : +221770000003  (expéditrice Fatou)")
    print("  Client D  : +221770000004  (destinataire Ibrahima)")
    print("  Relais B  : +221770000005  (Plateau, Dakar)")
    print("  Relais C  : +221770000006  (Escale, Thiès)")
    print()
    print("CAS À TESTER :")
    print("  Scan entrée relais  → R2R-2 (DROPPED_AT_ORIGIN_RELAY, relais Medina)")
    print("  Scan sortie relais  → R2R-4 (AT_DESTINATION_RELAY, relais Escale)")
    print("  Mission livreur     → R2R-3 (IN_TRANSIT, mission active créée)")
    print("  Notes vocales       → H2R-1, R2H-1, H2H-1")
    print("  Adresse GPS live    → R2H-2 (dest modifiable via PUT /delivery-address)")
    print("  Retrait admin       → wallet Moussa, payout 5000 XOF PENDING")
    print("  Redirection         → REDIRECT-1 (REDIRECTED_TO_RELAY vers Plateau)")
    print("  EXPRESS             → H2H-1, R2R-3")
    print("  Destinataire paie   → H2R-2, INSURED-1")
    print(f"{'='*60}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--wipe", action="store_true", help="Purger les anciens scénarios avant de créer")
    args = parser.parse_args()
    asyncio.run(main(wipe=args.wipe))
