"""
Router admin : tableau de bord, gestion globale colis/relais/drivers/wallets.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from core.dependencies import require_role
from core.exceptions import not_found_exception
from database import db
from models.common import UserRole, ParcelStatus

router = APIRouter()

require_admin_dep = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)


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


@router.put("/parcels/{parcel_id}/status", summary="Forcer changement statut")
async def admin_force_status(
    parcel_id: str,
    new_status: ParcelStatus,
    _admin=Depends(require_admin_dep),
):
    from services.parcel_service import transition_status
    # L'admin bypass les règles métier → on update directement
    now = datetime.now(timezone.utc)
    from services.parcel_service import _record_event
    await db.parcels.update_one(
        {"parcel_id": parcel_id},
        {"$set": {"status": new_status.value, "updated_at": now}},
    )
    await _record_event(
        parcel_id=parcel_id,
        event_type="ADMIN_STATUS_OVERRIDE",
        to_status=new_status,
        actor_role="admin",
        notes="Forçage admin",
    )
    return {"message": f"Statut forcé → {new_status.value}"}


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
    return {"message": "Retrait approuvé", "payout_id": payout_id}


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
        {"_id": 0, "mission_id": 1, "driver_id": 1, "driver_location": 1, "status": 1, "location_updated_at": 1}
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
    Liste les colis qui sont en relais (status AT_ORIGIN_RELAY ou AT_DESTINATION_RELAY)
    depuis plus de 7 jours sans mouvement.
    """
    from datetime import timedelta
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    
    query = {
        "status": {"$in": [ParcelStatus.AT_ORIGIN_RELAY.value, ParcelStatus.AT_DESTINATION_RELAY.value]},
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
    (Scans, traces GPS, etc.)
    """
    from services.parcel_service import get_parcel_timeline
    parcel = await db.parcels.find_one({"parcel_id": parcel_id}, {"_id": 0})
    if not parcel:
        raise not_found_exception("Colis")
        
    timeline = await get_parcel_timeline(parcel_id)
    
    # On cherche aussi les traces GPS associées aux missions de ce colis
    missions_cursor = db.delivery_missions.find({"parcel_id": parcel_id}, {"_id": 0})
    missions = await missions_cursor.to_list(length=10)
    
    return {
        "parcel": parcel,
        "timeline": timeline,
        "missions": missions
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


@router.post("/missions/{mission_id}/reassign", summary="Réassigner manuellement une mission")
async def admin_reassign_mission(
    mission_id: str,
    new_driver_id: str,
    _admin=Depends(require_admin_dep),
):
    """
    Force le changement de livreur pour une mission donnée.
    """
    mission = await db.delivery_missions.find_one({"mission_id": mission_id})
    if not mission:
        raise not_found_exception("Mission")
        
    now = datetime.now(timezone.utc)
    # 1. Libérer l'ancien livreur (logiciel)
    # 2. Assigner le nouveau
    await db.delivery_missions.update_one(
        {"mission_id": mission_id},
        {"$set": {
            "driver_id": new_driver_id,
            "status": "assigned",
            "assigned_at": now,
            "updated_at": now
        }}
    )
    # 3. Update le colis
    await db.parcels.update_one(
        {"parcel_id": mission["parcel_id"]},
        {"$set": {"assigned_driver_id": new_driver_id, "updated_at": now}}
    )
    
    return {"message": "Mission réassignée avec succès"}


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
    return await settle_driver_cod(driver_id, amount)


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
    return await settle_driver_cod(driver_id, amount)


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
