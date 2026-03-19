"""
simulate_scenarios.py — Scenarios de test end-to-end (v4)

Couvre les 4 modes de livraison avec les flows corriges :
  R2R:  CREATED -> DROPPED_AT_ORIGIN_RELAY -> IN_TRANSIT -> AVAILABLE_AT_RELAY -> DELIVERED
  R2H:  CREATED -> DROPPED_AT_ORIGIN_RELAY -> IN_TRANSIT -> OUT_FOR_DELIVERY -> DELIVERED
  H2R:  CREATED -> IN_TRANSIT -> AVAILABLE_AT_RELAY -> DELIVERED
  H2H:  CREATED -> IN_TRANSIT -> OUT_FOR_DELIVERY -> DELIVERED

Codes par mode :
  pickup_code (6ch) : toujours genere — agent relais ou expediteur le donne au driver
  delivery_code (6ch) : *_to_home uniquement — destinataire le donne au driver
  relay_pin (6ch) : *_to_relay uniquement — destinataire le donne a l'agent relais

Cas speciaux : redirection apres echec, express, destinataire paie

Usage :
    cd pickupoint/backend
    python simulate_scenarios.py          # cree tout
    python simulate_scenarios.py --wipe   # purge d'abord, puis recree

Comptes de test (OTP fixe 123456, PIN 1234) :
  +221770000000  admin          Ibou Admin
  +221770000001  driver         Moussa Livreur
  +221770000002  relay_agent    Aminata (Relais Medina - Dakar)
  +221770000003  client         Fatou Diallo (expeditrice)
  +221770000004  client         Ibrahima Sow (destinataire)
  +221770000005  relay_agent    Cheikh (Relais Plateau - Dakar)
  +221770000006  relay_agent    Mareme (Relais Escale - Thies)
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

def _event(parcel_id, status, actor_id, actor_role, note="", ts=None):
    return {
        "event_id":   _event_id(),
        "parcel_id":  parcel_id,
        "event_type": "STATUS_CHANGED",
        "from_status": None,
        "to_status":  status,
        "actor_id":   actor_id,
        "actor_role": actor_role,
        "notes":      note,
        "metadata":   {},
        "created_at": ts or datetime.now(timezone.utc),
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

    # Codes selon le mode (identique a la logique backend corrigee)
    pickup_code    = _pin6()  # toujours — agent relais ou expediteur le donne au driver
    home_delivery  = mode.value.endswith("_to_home")
    relay_delivery = mode.value.endswith("_to_relay")
    delivery_code  = _pin6() if home_delivery  else None
    relay_pin      = _pin6() if relay_delivery else None

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
        "pickup_confirmed":    mode.value.startswith("home_to_"),
        "delivery_confirmed":  relay_delivery,
        "is_simulation":   True,
        "weight_kg":       1.5,
        "dimensions":      None,
        "created_at":      now,
        "updated_at":      now,
        "expires_at":      now + timedelta(days=7),
    }
    await db.parcels.insert_one(doc)

    # Evenements timeline
    evts = events or []
    if evts:
        await db.parcel_events.insert_many([_event(p_id, **e) for e in evts])

    print(f"  [{status.value:30s}] {label}")
    print(f"    tracking={t_code}  pickup_code={pickup_code}", end="")
    if relay_pin:     print(f"  relay_pin={relay_pin}", end="")
    if delivery_code: print(f"  delivery_code={delivery_code}", end="")
    if is_express:    print("  EXPRESS", end="")
    if who_pays == "recipient": print("  RECIPIENT_PAYS", end="")
    print()
    return doc


async def _make_mission(parcel, driver, pickup_relay=None, pickup_loc=None,
                        delivery_relay=None, delivery_loc=None,
                        status="in_progress", minutes_ago=15):
    """Cree une mission livreur complete pour un colis."""
    now = datetime.now(timezone.utc)

    if pickup_relay:
        pickup_type = "relay"
        pickup_label = pickup_relay["name"]
        pickup_city = (pickup_relay.get("address") or {}).get("city", "Dakar")
        pickup_geopin = (pickup_relay.get("address") or {}).get("geopin")
    else:
        pickup_type = "gps"
        pickup_label = (pickup_loc or {}).get("label", "Position expediteur")
        pickup_city = (pickup_loc or {}).get("city", "Dakar")
        pickup_geopin = (pickup_loc or {}).get("geopin")

    if delivery_relay:
        delivery_type = "relay"
        delivery_label = delivery_relay["name"]
        delivery_city = (delivery_relay.get("address") or {}).get("city", "Dakar")
        delivery_geopin = (delivery_relay.get("address") or {}).get("geopin")
    else:
        delivery_type = "gps"
        delivery_label = (delivery_loc or {}).get("label", "Adresse destinataire")
        delivery_city = (delivery_loc or {}).get("city", "Dakar")
        delivery_geopin = (delivery_loc or {}).get("geopin")

    mode = parcel.get("delivery_mode", "")
    driver_rate = 0.85 if mode == "home_to_home" else 0.70
    earn = int((parcel.get("quoted_price") or 0) * driver_rate)

    doc = {
        "mission_id":        f"msn_{uuid.uuid4().hex[:12]}",
        "parcel_id":         parcel["parcel_id"],
        "tracking_code":     parcel.get("tracking_code"),
        "driver_id":         driver["user_id"],
        "sender_user_id":    parcel.get("sender_user_id"),
        "status":            status,
        "pickup_type":       pickup_type,
        "pickup_relay_id":   (pickup_relay or {}).get("relay_id"),
        "pickup_label":      pickup_label,
        "pickup_city":       pickup_city,
        "pickup_geopin":     pickup_geopin,
        "delivery_type":     delivery_type,
        "delivery_relay_id": (delivery_relay or {}).get("relay_id"),
        "delivery_label":    delivery_label,
        "delivery_city":     delivery_city,
        "delivery_geopin":   delivery_geopin,
        "recipient_name":    parcel.get("recipient_name"),
        "recipient_phone":   parcel.get("recipient_phone"),
        "earn_amount":       earn,
        "payment_status":    parcel.get("payment_status"),
        "who_pays":          parcel.get("who_pays"),
        "assigned_at":       now - timedelta(minutes=minutes_ago + 5),
        "started_at":        now - timedelta(minutes=minutes_ago),
        "created_at":        now - timedelta(minutes=minutes_ago + 10),
        "updated_at":        now,
    }
    await db.delivery_missions.insert_one(doc)
    return doc


# ─── Main ────────────────────────────────────────────────────────────────────

async def main(wipe=False, wipe_only=False):
    await connect_db()

    if wipe or wipe_only:
        print("\n--- PURGE ---")
        r1 = await db.parcels.delete_many({"is_simulation": True})
        r2 = await db.parcel_events.delete_many({})
        r3 = await db.delivery_missions.delete_many({})
        await db.relay_points.update_many({}, {"$set": {"current_load": 0}})
        print(f"  {r1.deleted_count} colis  |  {r2.deleted_count} evts  |  {r3.deleted_count} missions  supprimes")
        if wipe_only:
            print("Purge terminee (--wipe-only).")
            return

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
    agent_medina  = users["+221770000002"]
    agent_plateau = users["+221770000005"]
    agent_escale  = users["+221770000006"]

    # ── 2. Relais ───────────────────────────────────────────────────────────
    print("\n--- RELAIS ---")
    relays = {}
    for defn in RELAYS_DEF:
        owner = users[defn["owner_phone"]]
        r = await _ensure_relay(owner["user_id"], defn)
        relays[defn["owner_phone"]] = r
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
    print("  Wallets initialises (driver=12500 XOF + 3500 pending, relais=4200 XOF chacun)")

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
            "description": "Retrait Wave -- simulation test",
            "payout_method": "wave",
            "payout_phone":  driver["phone"],
            "created_at":  datetime.now(timezone.utc),
        })
        print("  Demande de retrait PENDING creee pour Moussa (5000 XOF)")

    # ── 4. Lieux ────────────────────────────────────────────────────────────
    loc_fatou  = {"label": "Chez Fatou, Medina",        "city": "Dakar",  "geopin": {"lat": 14.680, "lng": -17.443}}
    loc_ibra   = {"label": "Bureau Ibrahima, Plateau",  "city": "Dakar",  "geopin": {"lat": 14.710, "lng": -17.430}}
    loc_ibra2  = {"label": "Domicile Ibrahima, Thies",  "city": "Thies",  "geopin": {"lat": 14.795, "lng": -16.940}}

    # ── 5. Scenarios (4 colis CREATED, 1 par mode — test end-to-end) ───────
    print("\n--- SCENARIOS (1 colis CREATED par mode) ---")

    # ── R2R : Relay to Relay ──────────────────────────────────────────────
    # Flow complet : CREATED → depot relais (scan_in) → DROPPED_AT_ORIGIN_RELAY
    #   → driver collecte (confirm-pickup) → IN_TRANSIT
    #   → agent relais dest scan_in → AVAILABLE_AT_RELAY
    #   → destinataire retire (scan_out + relay_pin) → DELIVERED
    await _make_parcel(
        "R2R | Fatou envoie a Ibrahima : Medina -> Escale Thies",
        DeliveryMode.RELAY_TO_RELAY, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_relay_id=escale["relay_id"],
        status=ParcelStatus.CREATED,
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Colis cree — en attente de depot au relais Medina"}],
    )

    # ── R2H : Relay to Home ──────────────────────────────────────────────
    # Flow complet : CREATED → depot relais (scan_in) → DROPPED_AT_ORIGIN_RELAY
    #   → driver collecte (confirm-pickup) → IN_TRANSIT
    #   → driver arrive domicile (arrive-at-destination) → OUT_FOR_DELIVERY
    #   → destinataire donne delivery_code (confirm-delivery) → DELIVERED
    await _make_parcel(
        "R2H | Fatou envoie a Ibrahima : Medina -> domicile Plateau",
        DeliveryMode.RELAY_TO_HOME, fatou, ibra,
        origin_relay_id=medina["relay_id"], dest_addr=loc_ibra,
        status=ParcelStatus.CREATED,
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Colis cree — en attente de depot au relais Medina"}],
    )

    # ── H2R : Home to Relay ──────────────────────────────────────────────
    # Flow complet : CREATED → dispatch driver → driver collecte chez expediteur
    #   (confirm-pickup + pickup_code) → IN_TRANSIT
    #   → agent relais dest scan_in → AVAILABLE_AT_RELAY
    #   → destinataire retire (scan_out + relay_pin) → DELIVERED
    p_h2r = await _make_parcel(
        "H2R | Fatou envoie a Ibrahima : domicile Medina -> Relais Plateau",
        DeliveryMode.HOME_TO_RELAY, fatou, ibra,
        origin_loc=loc_fatou, dest_relay_id=plateau["relay_id"],
        status=ParcelStatus.CREATED,
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Colis cree — en attente dispatch driver"}],
    )
    await _create_delivery_mission(p_h2r, ParcelStatus.CREATED)

    # ── H2H : Home to Home ──────────────────────────────────────────────
    # Flow complet : CREATED → dispatch driver → driver collecte chez expediteur
    #   (confirm-pickup + pickup_code) → IN_TRANSIT
    #   → driver arrive domicile destinataire (arrive-at-destination) → OUT_FOR_DELIVERY
    #   → destinataire donne delivery_code (confirm-delivery) → DELIVERED
    p_h2h = await _make_parcel(
        "H2H | Fatou envoie a Ibrahima : domicile Medina -> domicile Thies (express)",
        DeliveryMode.HOME_TO_HOME, fatou, ibra,
        origin_loc=loc_fatou, dest_addr=loc_ibra2,
        status=ParcelStatus.CREATED,
        is_express=True,
        events=[{"status": ParcelStatus.CREATED.value, "actor_id": fatou["user_id"], "actor_role": "client", "note": "Colis express cree — en attente dispatch driver"}],
    )
    await _create_delivery_mission(p_h2h, ParcelStatus.CREATED)

    # ── 6. Resume ────────────────────────────────────────────────────────────
    total = await db.parcels.count_documents({"is_simulation": True})
    print(f"\n{'='*65}")
    print(f"[OK] {total} colis de test crees (tous au statut CREATED).")
    print()
    print("CONNEXION APP (OTP fixe 123456, PIN 1234) :")
    print("  Admin     : +221770000000")
    print("  Livreur   : +221770000001  (wallet: 12500 XOF, retrait 5000 en attente)")
    print("  Relais A  : +221770000002  (Medina, Dakar)")
    print("  Client S  : +221770000003  (expeditrice Fatou)")
    print("  Client D  : +221770000004  (destinataire Ibrahima)")
    print("  Relais B  : +221770000005  (Plateau, Dakar)")
    print("  Relais C  : +221770000006  (Escale, Thies)")
    print()
    print("TEST END-TO-END — jouer chaque colis de bout en bout :")
    print()
    print("  R2R (Medina -> Escale Thies) :")
    print("    1. Fatou depose au relais Medina           → Aminata scan_in")
    print("    2. Moussa collecte au relais               → confirm-pickup (pickup_code)")
    print("    3. Moussa livre au relais Escale            → Mareme scan_in → AVAILABLE")
    print("    4. Ibrahima retire                          → Mareme scan_out (relay_pin)")
    print()
    print("  R2H (Medina -> domicile Ibrahima) :")
    print("    1. Fatou depose au relais Medina           → Aminata scan_in")
    print("    2. Moussa collecte au relais               → confirm-pickup (pickup_code)")
    print("    3. Moussa arrive chez Ibrahima             → arrive-at-destination")
    print("    4. Ibrahima donne le code                  → confirm-delivery (delivery_code)")
    print()
    print("  H2R (domicile Fatou -> Relais Plateau) :")
    print("    1. Moussa va chez Fatou                    → mission assignee auto")
    print("    2. Fatou donne le code                     → confirm-pickup (pickup_code)")
    print("    3. Moussa livre au Relais Plateau          → Cheikh scan_in → AVAILABLE")
    print("    4. Ibrahima retire                         → Cheikh scan_out (relay_pin)")
    print()
    print("  H2H express (domicile Fatou -> domicile Ibrahima, Thies) :")
    print("    1. Moussa va chez Fatou                    → mission assignee auto")
    print("    2. Fatou donne le code                     → confirm-pickup (pickup_code) → IN_TRANSIT")
    print("    3. Moussa arrive chez Ibrahima             → arrive-at-destination → OUT_FOR_DELIVERY")
    print("    4. Ibrahima donne le code                  → confirm-delivery (delivery_code) → DELIVERED")
    print()
    print("CODES :")
    print("  pickup_code (6ch) : toujours — agent relais ou expediteur -> driver")
    print("  delivery_code (6ch) : *_to_home — destinataire -> driver")
    print("  relay_pin (6ch) : *_to_relay — destinataire -> agent relais")
    print()
    print("TELEPHONE DESTINATAIRE :")
    print("  *_to_relay : toujours masque (driver ne contacte pas le destinataire)")
    print("  *_to_home  : masque → revele quand driver < 500m (approaching_notified)")
    print(f"{'='*65}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--wipe", action="store_true", help="Purger les anciens scenarios avant de creer")
    parser.add_argument("--wipe-only", action="store_true", help="Purger sans recreer")
    args = parser.parse_args()
    asyncio.run(main(wipe=args.wipe, wipe_only=args.wipe_only))
