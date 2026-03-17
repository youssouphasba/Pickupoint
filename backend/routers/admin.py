"""
Router admin : tableau de bord, gestion globale colis/relais/drivers/wallets.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from core.dependencies import require_role
from core.exceptions import not_found_exception, bad_request_exception
from database import db
from models.common import UserRole, ParcelStatus
from services.parcel_service import _record_event, sync_active_mission_with_parcel
from services.notification_service import notify_payout_result, notify_relay_agent_parcel_arrived

router = APIRouter()

require_admin_dep = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)


class PaymentOverrideRequest(BaseModel):
    reason: str


@router.get("/dashboard", summary="KPIs temps réel")
async def dashboard(_admin=Depends(require_admin_dep)):
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    total_parcels = await db.parcels.count_documents({})
    parcels_today = await db.parcels.count_documents({"created_at": {"$gte": today_start}})
    delivered     = await db.parcels.count_documents({"status": ParcelStatus.DELIVERED.value})
    failed        = await db.parcels.count_documents({"status": ParcelStatus.DELIVERY_FAILED.value})
    active_relays = await db.relay_points.count_documents({"is_active": True})
    active_drivers = await db.users.count_documents({"role": UserRole.DRIVER.value, "is_active": True})

    success_rate = round(delivered / total_parcels * 100, 1) if total_parcels else 0.0

    # Chiffre d'affaires : somme des paid_price des colis livrés
    pipeline = [
        {"$match": {"status": ParcelStatus.DELIVERED.value, "paid_price": {"$ne": None}}},
        {"$group": {"_id": None, "total": {"$sum": "$paid_price"}}},
    ]
    ca_result = await db.parcels.aggregate(pipeline).to_list(length=1)
    ca = ca_result[0]["total"] if ca_result else 0.0

    return {
        "total_parcels":  total_parcels,
        "parcels_today":  parcels_today,
        "delivered":      delivered,
        "failed":         failed,
        "success_rate":   success_rate,
        "active_relays":  active_relays,
        "active_drivers": active_drivers,
        "revenue_xof":    ca,
    }


@router.get("/parcels", summary="Tous les colis avec filtres")
async def admin_list_parcels(
    status: str = None,
    skip: int = 0,
    limit: int = 100,
    _admin=Depends(require_admin_dep),
):
    query = {}
    if status:
        query["status"] = status
    cursor = db.parcels.find(query, {"_id": 0}).skip(skip).limit(limit)
    total = await db.parcels.count_documents(query)
    return {"parcels": await cursor.to_list(length=limit), "total": total}


@router.post("/parcels/{parcel_id}/confirm-payment", summary="Valider manuellement le paiement (Admin)")
async def admin_confirm_payment(
    parcel_id: str,
    _admin=Depends(require_admin_dep),
):
    """
    Force le statut de paiement à 'paid'. Utile pour les paiements hors-ligne
    ou pour débloquer un flux si le webhook de paiement a échoué.
    """
    now = datetime.now(timezone.utc)
    result = await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {"payment_status": "paid", "payment_method": "admin_manual", "updated_at": now}},
    )
    if result.matched_count == 0:
        raise not_found_exception("Colis")
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    await sync_active_mission_with_parcel(parcel)
    await _record_event(
        parcel_id=parcel_id,
        event_type="ADMIN_PAYMENT_CONFIRMED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes="Paiement validé manuellement par l'admin",
    )
    return {"message": "Paiement validé avec succès"}


@router.post("/parcels/{parcel_id}/payment-override", summary="Lever le blocage paiement d'un colis")
async def admin_payment_override(
    parcel_id: str,
    body: PaymentOverrideRequest,
    _admin=Depends(require_admin_dep),
):
    reason = body.reason.strip()
    if not reason:
        raise bad_request_exception("Le motif d'override paiement est obligatoire")

    now = datetime.now(timezone.utc)
    result = await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {
            "payment_override": True,
            "payment_override_reason": reason,
            "payment_override_by": _admin.get("user_id") if isinstance(_admin, dict) else "admin",
            "payment_override_at": now,
            "updated_at": now,
        }},
    )
    if result.matched_count == 0:
        raise not_found_exception("Colis")

    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    await sync_active_mission_with_parcel(parcel)
    await _record_event(
        parcel_id=parcel_id,
        event_type="ADMIN_PAYMENT_OVERRIDE",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=reason,
    )
    return {"message": "Blocage paiement levé", "parcel_id": parcel_id}


@router.post("/parcels/{parcel_id}/suspend", summary="Suspendre un colis (Admin)")
async def admin_suspend_parcel(
    parcel_id: str,
    _admin=Depends(require_admin_dep),
):
    """
    Bloque temporairement toutes les actions sur le colis (collecte, livraison).
    """
    from services.parcel_service import transition_status
    actor = {"actor_id": _admin["user_id"] if isinstance(_admin, dict) else "admin_system", "actor_role": "admin"}
    
    await transition_status(
        parcel_id, ParcelStatus.SUSPENDED,
        notes="Colis suspendu par l'administration",
        **actor
    )
    return {"message": "Colis suspendu"}


@router.post("/parcels/{parcel_id}/unsuspend", summary="Lever la suspension (Admin)")
async def admin_unsuspend_parcel(
    parcel_id: str,
    to_status: ParcelStatus,
    _admin=Depends(require_admin_dep),
):
    """
    Relance le colis vers un statut actif (ex: CREATED, OUT_FOR_DELIVERY).
    """
    from services.parcel_service import transition_status
    actor = {"actor_id": _admin["user_id"] if isinstance(_admin, dict) else "admin_system", "actor_role": "admin"}
    
    await transition_status(
        parcel_id, to_status,
        notes=f"Suspension levée vers {to_status.value}",
        **actor
    )
    return {"message": f"Suspension levée vers {to_status.value}"}


@router.get("/relay-points", summary="Réseau relais complet")
async def admin_relay_points(
    skip: int = 0, limit: int = 100,
    _admin=Depends(require_admin_dep),
):
    cursor = db.relay_points.find({}, {"_id": 0}).skip(skip).limit(limit)
    total = await db.relay_points.count_documents({})
    return {"relay_points": await cursor.to_list(length=limit), "total": total}


@router.put("/relay-points/{relay_id}/verify", summary="Valider un relais")
async def verify_relay(relay_id: str, _admin=Depends(require_admin_dep)):
    result = await db.relay_points.update_one(
        {"relay_id": relay_id},
        {"$set": {"is_verified": True, "updated_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        raise not_found_exception("Point relais")
    return {"message": "Relais vérifié"}


@router.get("/drivers", summary="Liste livreurs + stats")
async def admin_drivers(_admin=Depends(require_admin_dep)):
    cursor = db.users.find({"role": UserRole.DRIVER.value}, {"_id": 0})
    drivers = await cursor.to_list(length=200)
    # Enrichir avec nb de missions
    for d in drivers:
        d["missions_count"] = await db.delivery_missions.count_documents(
            {"driver_id": d["user_id"]}
        )
    return {"drivers": drivers}


@router.get("/wallets/payouts", summary="Demandes de retrait en attente")
async def admin_pending_payouts(_admin=Depends(require_admin_dep)):
    cursor = db.payout_requests.find({"status": "pending"}, {"_id": 0}).sort("created_at", 1)
    return {"payouts": await cursor.to_list(length=200)}


@router.put("/wallets/payouts/{payout_id}/approve", summary="Valider retrait")
async def approve_payout(payout_id: str, _admin=Depends(require_admin_dep)):
    payout = await db.payout_requests.find_one({"payout_id": payout_id}, {"_id": 0})
    if not payout:
        raise not_found_exception("Demande de retrait")

    now = datetime.now(timezone.utc)
    await db.payout_requests.update_one(
        {"payout_id": payout_id},
        {"$set": {"status": "approved", "updated_at": now}},
    )
    # Libérer le pending
    await db.wallets.update_one(
        {"wallet_id": payout["wallet_id"]},
        {"$inc": {"pending": -payout["amount"]}, "$set": {"updated_at": now}},
    )
    
    await _record_event(
        event_type="PAYOUT_APPROVED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Retrait approuvé pour le montant {payout['amount']} XOF",
        metadata={"payout_id": payout_id, "amount": payout["amount"]}
    )
    
    # Notifier le driver/relay
    owner_id = payout.get("user_id") or payout.get("owner_id")
    if owner_id:
        await notify_payout_result(owner_id, payout["amount"], approved=True)

    return {"message": "Retrait approuvé", "payout_id": payout_id}


# ── Gestion des Utilisateurs & Bannissement ───────────────────────────────────

@router.get("/users", summary="Liste tous les utilisateurs (Admin)")
async def admin_list_users(
    skip: int = 0,
    limit: int = 100,
    role: str = None,
    _admin=Depends(require_admin_dep),
):
    query = {}
    if role:
        query["role"] = role
    
    cursor = db.users.find(query, {"_id": 0}).skip(skip).limit(limit).sort("created_at", -1)
    users = await cursor.to_list(length=limit)
    total = await db.users.count_documents(query)
    
    return {"users": users, "total": total}


@router.post("/users/{user_id}/ban", summary="Bannir un utilisateur")
async def admin_ban_user(
    user_id: str,
    _admin=Depends(require_admin_dep),
):
    """
    Marque un utilisateur comme banni. 
    Empêche toute nouvelle connexion et invalide les sessions actives.
    """
    now = datetime.now(timezone.utc)
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {"is_banned": True, "updated_at": now}}
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")
    
    # Invalider toutes les sessions en cours
    await db.user_sessions.delete_many({"user_id": user_id})
    
    await _record_event(
        event_type="USER_BANNED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Utilisateur {user_id} banni par l'administration",
        metadata={"target_user_id": user_id}
    )
    
    return {"message": "Utilisateur banni et sessions révoquées"}


@router.post("/users/{user_id}/unban", summary="Lever le bannissement")
async def admin_unban_user(
    user_id: str,
    _admin=Depends(require_admin_dep),
):
    now = datetime.now(timezone.utc)
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {"is_banned": False, "updated_at": now}}
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")
    
    await _record_event(
        event_type="USER_UNBANNED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Bannissement levé pour l'utilisateur {user_id}",
        metadata={"target_user_id": user_id}
    )
    
    return {"message": "Bannissement levé"}


# ── Nouveaux Endpoints "Contrôle Max" (Phase 9) ────────────────────────────────

@router.get("/fleet/live", summary="Position GPS temps réel de la flotte")
async def get_live_fleet(_admin=Depends(require_admin_dep)):
    """
    Retourne la position GPS de tous les livreurs connectés 
    ayant mis à jour leur position récemment.
    """
    # On cherche les livreurs actifs (mis à jour depuis < 1h)
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(hours=1)
    
    cursor = db.delivery_missions.find(
        {"location_updated_at": {"$gte": cutoff}},
        {"_id": 0, "mission_id": 1, "parcel_id": 1, "driver_id": 1, "driver_location": 1, "status": 1, "location_updated_at": 1}
    )
    fleet = await cursor.to_list(length=500)
    
    # On enrichit avec le nom du livreur
    for m in fleet:
        driver = await db.users.find_one({"user_id": m["driver_id"]}, {"_id": 0, "name": 1})
        if driver:
            m["driver_name"] = driver["name"]
            
    return {"fleet": fleet}


@router.get("/analytics/stale-parcels", summary="Colis stagnant en relais (> 7j)")
async def get_stale_parcels(_admin=Depends(require_admin_dep)):
    """
    Liste les colis qui sont en relais
    depuis plus de 7 jours sans mouvement.
    """
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    
    query = {
        "status": {
            "$in": [
                ParcelStatus.DROPPED_AT_ORIGIN_RELAY.value,
                ParcelStatus.AT_DESTINATION_RELAY.value,
                ParcelStatus.AVAILABLE_AT_RELAY.value,
            ]
        },
        "updated_at": {"$lt": cutoff}
    }
    
    cursor = db.parcels.find(query, {"_id": 0})
    stale = await cursor.to_list(length=200)
    
    return {"stale_parcels": stale, "total": len(stale)}


@router.get("/analytics/anomaly-alerts", summary="Détection d'anomalies (Immobilité/Retard)")
async def get_anomaly_alerts(_admin=Depends(require_admin_dep)):
    """
    Identifie les anomalies opérationnelles :
    - Signal perdu : Pas de mise à jour GPS depuis > 20 min sur une mission active.
    - Retard critique : Mission active depuis > 3 heures.
    """
    from datetime import timedelta
    now = datetime.now(timezone.utc)
    signal_lost_cutoff = now - timedelta(minutes=20)
    long_mission_cutoff = now - timedelta(hours=3)
    
    anomalies = []
    
    # 1. Signal Perdu
    lost_cursor = db.delivery_missions.find({
        "status": {"$in": ["assigned", "in_progress"]},
        "location_updated_at": {"$lt": signal_lost_cutoff}
    }, {"_id": 0})
    
    async for m in lost_cursor:
        anomalies.append({
            "type": "signal_lost",
            "severity": "high",
            "mission_id": m["mission_id"],
            "driver_id": m["driver_id"],
            "last_seen": m.get("location_updated_at"),
            "description": "Aucun signal GPS depuis plus de 20 minutes."
        })
        
    # 2. Mission Trop Longue
    long_cursor = db.delivery_missions.find({
        "status": {"$in": ["assigned", "in_progress"]},
        "assigned_at": {"$lt": long_mission_cutoff}
    }, {"_id": 0})
    
    async for m in long_cursor:
        # Éviter les doublons si déjà en signal_lost
        if any(a["mission_id"] == m["mission_id"] for a in anomalies):
            continue
            
        anomalies.append({
            "type": "critical_delay",
            "severity": "medium",
            "mission_id": m["mission_id"],
            "driver_id": m["driver_id"],
            "assigned_at": m.get("assigned_at"),
            "description": "Mission active depuis plus de 3 heures."
        })

    # Enrichir avec les noms des drivers
    for a in anomalies:
        driver = await db.users.find_one({"user_id": a["driver_id"]}, {"_id": 0, "name": 1})
        if driver:
            a["driver_name"] = driver["name"]
            
    return {"anomalies": anomalies, "total": len(anomalies)}


@router.get("/analytics/heatmap", summary="Données pour la heatmap des demandes")
async def get_heatmap_data(_admin=Depends(require_admin_dep)):
    """
    Retourne les coordonnées GPS de tous les points de collecte et livraison
    pour visualiser la densité de la demande sur les 30 derniers jours.
    """
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    
    pipeline = [
        {"$match": {"created_at": {"$gte": cutoff}}},
        {"$project": {
            "_id": 0,
            "origin_lat": "$origin_location.geopin.lat",
            "origin_lng": "$origin_location.geopin.lng",
            "dest_lat": "$delivery_address.geopin.lat",
            "dest_lng": "$delivery_address.geopin.lng"
        }}
    ]
    
    cursor = db.parcels.aggregate(pipeline)
    parcels = await cursor.to_list(length=2000)
    
    points = []
    for p in parcels:
        if p.get("origin_lat") and p.get("origin_lng"):
            points.append({"lat": p["origin_lat"], "lng": p["origin_lng"]})
        if p.get("dest_lat") and p.get("dest_lng"):
            points.append({"lat": p["dest_lat"], "lng": p["dest_lng"]})
            
    return {"points": points}


@router.get("/parcels/{parcel_id}/audit", summary="Audit Trail complet du colis")
async def get_parcel_audit(parcel_id: str, _admin=Depends(require_admin_dep)):
    """
    Retourne l'historique complet des événements avec métadonnées techniques 
    (Scans, traces GPS, etc.) et noms des intervenants.
    """
    from services.parcel_service import get_parcel_timeline
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
        
    # Enrichir les infos de base du colis
    if parcel.get("sender_user_id") and not parcel.get("sender_name"):
        sender = await db.users.find_one({"user_id": parcel["sender_user_id"]}, {"_id": 0, "name": 1})
        if sender:
            parcel["sender_name"] = sender["name"]

    if parcel.get("origin_relay_id"):
        relay = await db.relay_points.find_one({"relay_id": parcel["origin_relay_id"]}, {"_id": 0, "name": 1})
        if relay:
            parcel["origin_relay_name"] = relay["name"]

    if parcel.get("destination_relay_id"):
        relay = await db.relay_points.find_one({"relay_id": parcel["destination_relay_id"]}, {"_id": 0, "name": 1})
        if relay:
            parcel["destination_relay_name"] = relay["name"]

    timeline = await get_parcel_timeline(parcel_id)
    # Enrichir la timeline avec les noms des acteurs si possible
    for event in timeline:
        event["timestamp"] = event.get("created_at")
        if event.get("actor_id"):
            actor = await db.users.find_one({"user_id": event["actor_id"]}, {"_id": 0, "name": 1})
            if actor:
                event["actor_name"] = actor["name"]

    # On cherche aussi les traces GPS associées aux missions de ce colis
    missions_cursor = db.delivery_missions.find({"parcel_id": parcel_id}, {"_id": 0})
    missions = await missions_cursor.to_list(length=10)
    
    # Enrichir les missions avec le nom du livreur
    for m in missions:
        if m.get("driver_id"):
            driver = await db.users.find_one({"user_id": m["driver_id"]}, {"_id": 0, "name": 1})
            if driver:
                m["driver_name"] = driver["name"]
    
    return {
        "parcel": parcel,
        "financial_summary": {
            "who_pays":       parcel.get("who_pays"),
            "payment_status": parcel.get("payment_status"),
            "payment_method": parcel.get("payment_method"),
            "payment_override": parcel.get("payment_override"),
            "payment_override_reason": parcel.get("payment_override_reason"),
            "quoted_price":   parcel.get("quoted_price"),
            "payment_url":    parcel.get("payment_url"),
            "address_change_surcharge_xof": parcel.get("address_change_surcharge_xof", 0.0),
            "driver_bonus_xof": parcel.get("driver_bonus_xof", 0.0),
        },
        "timeline": timeline,
        "missions": missions
    }


@router.get("/users/{user_id}/history", summary="Historique complet d'un utilisateur")
async def get_user_history(user_id: str, _admin=Depends(require_admin_dep)):
    """
    Retourne la liste des activités liées à cet utilisateur :
    - Colis envoyés
    - Colis dont il est destinataire
    - Missions de livraison (si livreur)
    - Événements d'audit liés
    """
    user = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user:
        raise not_found_exception("Utilisateur")

    # 1. Colis envoyés
    parcels_sent = await db.parcels.find({"sender_user_id": user_id}, {"_id": 0}).to_list(length=100)
    
    # 2. Colis reçus (basé sur le numéro de téléphone ou user_id si lié)
    parcels_received = await db.parcels.find({
        "$or": [
            {"recipient_phone": user["phone"]},
            {"recipient_user_id": user_id}
        ]
    }, {"_id": 0}).to_list(length=100)

    # 3. Missions (si livreur)
    missions = []
    if user.get("role") == UserRole.DRIVER.value:
        missions = await db.delivery_missions.find({"driver_id": user_id}, {"_id": 0}).to_list(length=100)

    # 4. Événements récents où il est l'acteur
    events = await db.parcel_events.find({"actor_id": user_id}, {"_id": 0}).sort("created_at", -1).to_list(length=50)

    return {
        "user": user,
        "parcels_sent": parcels_sent,
        "parcels_received": parcels_received,
        "missions": missions,
        "events": events
    }


@router.get("/finance/cod-monitoring", summary="Suivi du cash autorisé")
async def get_cod_monitoring(_admin=Depends(require_admin_dep)):
    """
    Retourne le montant de cash théoriquement détenu par chaque livreur/relais
    pour les transactions autorisées hors-app (point 2).
    """
    # Ici on simule une agrégation sur les missions ou wallets
    # Selon le schéma, on peut chercher les "cash_collected" dans les événements
    pipeline = [
        {"$match": {"role": UserRole.DRIVER.value}},
        {"$project": {"_id": 0, "user_id": 1, "name": 1, "cod_balance": {"$ifNull": ["$cod_balance", 0]}}}
    ]
    drivers_cash = await db.users.aggregate(pipeline).to_list(length=100)
    return {"entities": drivers_cash}


    return {"message": "Mission réassignée avec succès"}


from pydantic import BaseModel
from typing import Optional

class IncidentResolutionRequest(BaseModel):
    action: str  # "reassign", "return", "cancel"
    notes: Optional[str] = None

@router.post("/incidents/{parcel_id}/resolve", summary="Résoudre un incident (Admin)")
async def admin_resolve_incident(
    parcel_id: str,
    body: IncidentResolutionRequest,
    _admin=Depends(require_admin_dep),
):
    """
    Prend une décision suite à un incident signalé par un livreur.
    """
    parcel = await db.parcels.find_one({"parcel_id": parcel_id})
    if not parcel:
        raise not_found_exception("Colis")

    now = datetime.now(timezone.utc)
    from services.parcel_service import transition_status, _create_delivery_mission, _record_event
    from models.delivery import MissionStatus

    # 1. Clôturer l'ancienne mission si elle est encore active
    await db.delivery_missions.update_one(
        {"parcel_id": parcel_id, "status": {"$in": ["assigned", "in_progress", "incident_reported"]}},
        {"$set": {"status": MissionStatus.FAILED.value, "completed_at": now, "updated_at": now}}
    )

    actor = {"actor_id": _admin["user_id"] if isinstance(_admin, dict) else "admin_system", "actor_role": "admin"}

    if body.action == "reassign":
        # Repasser en OUT_FOR_DELIVERY (ou CREATED/IN_TRANSIT selon l'endroit)
        # Pour simplifier, on force OUT_FOR_DELIVERY pour qu'une nouvelle mission soit créée
        await db.parcels.update_one(
            {"parcel_id": parcel_id},
            {"$set": {"assigned_driver_id": None, "updated_at": now}}
        )
        # On recrée une mission
        await _create_delivery_mission(parcel, ParcelStatus(parcel["status"]))
        notes = f"Incident résolu par réassignation. {body.notes or ''}"
    
    elif body.action == "return":
        await transition_status(parcel_id, ParcelStatus.RETURNED, notes=f"Incident résolu par retour à l'envoyeur. {body.notes or ''}", **actor)
        return {"message": "Incident résolu : Colis en cours de retour"}

    elif body.action == "cancel":
        await transition_status(parcel_id, ParcelStatus.CANCELLED, notes=f"Incident résolu par annulation. {body.notes or ''}", **actor)
        return {"message": "Incident résolu : Colis annulé"}

    else:
        raise bad_request_exception("Action de résolution invalide")

    await _record_event(
        parcel_id=parcel_id,
        event_type="INCIDENT_RESOLVED",
        actor_role="admin",
        notes=notes,
        metadata={"action": body.action}
    )
    
    return {"message": "Incident résolu avec succès"}


@router.post("/finance/settle", summary="Confirmer l'encaissement du cash (COD)")
async def admin_settle_cod(
    driver_id: str,
    amount: float = None,
    _admin=Depends(require_admin_dep),
):
    """
    Solde tout ou partie du cash on delivery collecté par un livreur.
    """
    from services.admin_service import settle_driver_cod
    res = await settle_driver_cod(driver_id, amount)
    
    await _record_event(
        event_type="COD_SETTLED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Encaissement COD validé pour le livreur {driver_id}: {res['amount_settled']} XOF",
        metadata={"driver_id": driver_id, "amount_settled": res["amount_settled"]}
    )
    
    return res


@router.post("/parcels/{parcel_id}/override", summary="Forcer un changement de statut (SuperAdmin)")
async def admin_override_status(
    parcel_id: str,
    new_status: ParcelStatus,
    notes: str,
    _admin=Depends(require_admin_dep),
):
    """
    Intervention manuelle sur le cycle de vie d'un colis.
    """
    from services.admin_service import override_parcel_status
    return await override_parcel_status(parcel_id, new_status, notes)


# ── Fidélité & Récompenses (Phase 8) ─────────────────────────────────────────

@router.post("/recompenses/trigger-monthly", summary="Lancer manuellement le calcul mensuel (Admin)")
async def admin_trigger_monthly(
    period: str, # YYYY-MM
    _admin=Depends(require_admin_dep),
):
    """
    Déclenche le calcul des stats et le versement des bonus pour une période donnée.
    """
    from services.ranking_service import (
        compute_driver_stats_for_period, 
        pay_monthly_driver_bonuses,
        compute_relay_stats_and_pay_bonuses
    )
    
    # 1. Stats Drivers
    stats = await compute_driver_stats_for_period(period)
    for stat in stats:
        await db.driver_stats.update_one(
            {"driver_id": stat["driver_id"], "period": period},
            {"$set": stat},
            upsert=True,
        )
    
    # 2. Bonus Drivers
    await pay_monthly_driver_bonuses(period)
    
    # 3. Bonus Relais
    await compute_relay_stats_and_pay_bonuses(period)
    
    return {"message": f"Calculs terminés pour la période {period}"}


@router.get("/recompenses/driver-stats", summary="Voir les stats de performance drivers")
async def admin_get_driver_stats(
    period: str,
    _admin=Depends(require_admin_dep),
):
    stats = await db.driver_stats.find({"period": period}).sort("rank", 1).to_list(length=200)
    return {"period": period, "stats": stats}


@router.get("/audit-log", summary="Journal d'audit global")
async def admin_get_audit_log(
    limit: int = 100,
    offset: int = 0,
    _admin=Depends(require_admin_dep),
):
    """
    Récupère les derniers événements système pour une traçabilité complète.
    """
    cursor = db.parcel_events.find({}, {"_id": 0}).sort("created_at", -1).skip(offset).limit(limit)
    events = await cursor.to_list(length=limit)
    
    # Enrichissement avec les noms des acteurs et codes de colis
    for ev in events:
        if ev.get("actor_id"):
            actor = await db.users.find_one({"user_id": ev["actor_id"]}, {"_id": 0, "name": 1})
            if actor:
                ev["actor_name"] = actor["name"]
        
        if ev.get("parcel_id"):
            parcel = await db.parcels.find_one({"parcel_id": ev["parcel_id"]}, {"_id": 0, "tracking_code": 1})
            if parcel:
                ev["tracking_code"] = parcel["tracking_code"]
                
    return {"events": events}


@router.put("/wallets/payouts/{payout_id}/reject", summary="Rejeter retrait")
async def reject_payout(payout_id: str, _admin=Depends(require_admin_dep)):
    payout = await db.payout_requests.find_one({"payout_id": payout_id}, {"_id": 0})
    if not payout:
        raise not_found_exception("Demande de retrait")
    if payout["status"] != "pending":
        raise bad_request_exception("Ce retrait n'est plus en attente")

    now = datetime.now(timezone.utc)
    await db.payout_requests.update_one(
        {"payout_id": payout_id},
        {"$set": {"status": "rejected", "updated_at": now}},
    )
    # Libérer le montant bloqué → retour au solde disponible
    await db.wallets.update_one(
        {"wallet_id": payout["wallet_id"]},
        {"$inc": {"pending": -payout["amount"], "balance": payout["amount"]}, "$set": {"updated_at": now}},
    )
    await _record_event(
        event_type="PAYOUT_REJECTED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Retrait rejeté pour {payout['amount']} XOF",
        metadata={"payout_id": payout_id, "amount": payout["amount"]}
    )
    # Notifier le driver/relay
    owner_id = payout.get("user_id") or payout.get("owner_id")
    if owner_id:
        await notify_payout_result(owner_id, payout["amount"], approved=False)

    return {"message": "Retrait rejeté", "payout_id": payout_id}


# ── App Settings (Express, etc.) ─────────────────────────────────────────────

@router.get("/settings", summary="Lire les paramètres globaux de l'app")
async def get_app_settings(_admin=Depends(require_admin_dep)):
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0})
    if not settings_doc:
        return {"express_enabled": False}
    return {
        "express_enabled": settings_doc.get("express_enabled", False),
    }


@router.put("/settings/express", summary="Activer/désactiver la livraison Express")
async def toggle_express(body: dict, _admin=Depends(require_admin_dep)):
    enabled = bool(body.get("enabled", False))
    await db.app_settings.update_one(
        {"key": "global"},
        {"$set": {"express_enabled": enabled, "updated_at": datetime.now(timezone.utc)}},
        upsert=True,
    )
    status = "activée" if enabled else "désactivée"
    return {"express_enabled": enabled, "message": f"Livraison Express {status}"}
