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
