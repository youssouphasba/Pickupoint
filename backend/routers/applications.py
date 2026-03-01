"""
Router applications : candidatures livreur et point relais.
Workflow : Client soumet → Admin examine (pièces + coordonnées) → Approuve ou Rejette
"""
import uuid
from datetime import datetime, timezone
from typing import Optional, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, bad_request_exception
from database import db
from models.common import UserRole, GeoPin

router = APIRouter()


# ── Modèles ──────────────────────────────────────────────────────────────────

class DriverApplicationCreate(BaseModel):
    full_name:       str
    id_card_number:  str                          # numéro CNI
    license_number:  str                          # numéro permis
    vehicle_type:    Literal["moto", "car", "van", "tricycle"] = "moto"
    message:         Optional[str] = None         # message libre au recruteur


class RelayApplicationCreate(BaseModel):
    business_name:   str                          # nom de la boutique / local
    address_label:   str                          # adresse texte
    city:            str = "Dakar"
    geopin:          Optional[GeoPin] = None      # position GPS du local
    business_reg:    Optional[str] = None         # numéro registre commerce
    opening_hours:   Optional[str] = None         # ex: "Lun-Sam 8h-20h"
    message:         Optional[str] = None


# ── Endpoints utilisateur ─────────────────────────────────────────────────────

@router.post("/driver", summary="Soumettre candidature livreur")
async def apply_driver(
    body: DriverApplicationCreate,
    current_user: dict = Depends(get_current_user),
):
    # Vérifier pas déjà candidat en attente
    existing = await db.applications.find_one({
        "user_id": current_user["user_id"],
        "type": "driver",
        "status": "pending",
    })
    if existing:
        raise bad_request_exception("Vous avez déjà une candidature en attente")

    now = datetime.now(timezone.utc)
    doc = {
        "application_id": f"app_{uuid.uuid4().hex[:12]}",
        "user_id":         current_user["user_id"],
        "user_phone":      current_user["phone"],
        "user_name":       current_user.get("name", current_user["phone"]),
        "type":            "driver",
        "status":          "pending",   # pending | approved | rejected
        "data":            body.model_dump(),
        "admin_notes":     None,
        "created_at":      now,
        "updated_at":      now,
    }
    await db.applications.insert_one(doc)
    return {"message": "Candidature soumise. L'équipe PickuPoint vous contactera.", "application_id": doc["application_id"]}


@router.post("/relay", summary="Soumettre candidature point relais")
async def apply_relay(
    body: RelayApplicationCreate,
    current_user: dict = Depends(get_current_user),
):
    existing = await db.applications.find_one({
        "user_id": current_user["user_id"],
        "type": "relay",
        "status": "pending",
    })
    if existing:
        raise bad_request_exception("Vous avez déjà une candidature en attente")

    now = datetime.now(timezone.utc)
    doc = {
        "application_id": f"app_{uuid.uuid4().hex[:12]}",
        "user_id":         current_user["user_id"],
        "user_phone":      current_user["phone"],
        "user_name":       current_user.get("name", current_user["phone"]),
        "type":            "relay",
        "status":          "pending",
        "data":            body.model_dump(),
        "admin_notes":     None,
        "created_at":      now,
        "updated_at":      now,
    }
    await db.applications.insert_one(doc)
    return {"message": "Candidature soumise. L'équipe PickuPoint visitera votre point.", "application_id": doc["application_id"]}


@router.get("/my", summary="Mes candidatures")
async def my_applications(current_user: dict = Depends(get_current_user)):
    cursor = db.applications.find(
        {"user_id": current_user["user_id"]},
        {"_id": 0},
    ).sort("created_at", -1)
    return {"applications": await cursor.to_list(length=20)}


# ── Endpoints admin ───────────────────────────────────────────────────────────

require_admin = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)


@router.get("", summary="Toutes les candidatures (admin)")
async def list_applications(
    status: Optional[str] = "pending",
    app_type: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
    _admin=Depends(require_admin),
):
    query: dict = {}
    if status:
        query["status"] = status
    if app_type:
        query["type"] = app_type
    cursor = db.applications.find(query, {"_id": 0}).sort("created_at", 1).skip(skip).limit(limit)
    total = await db.applications.count_documents(query)
    return {"applications": await cursor.to_list(length=limit), "total": total}


@router.put("/{application_id}/approve", summary="Approuver candidature")
async def approve_application(
    application_id: str,
    admin_notes: Optional[str] = None,
    _admin=Depends(require_admin),
):
    """
    Approuver :
    - Driver → role = driver
    - Relay  → role = relay_agent + création du point relais + relay_point_id sur l'utilisateur
    """
    app = await db.applications.find_one({"application_id": application_id}, {"_id": 0})
    if not app:
        raise not_found_exception("Candidature")
    if app["status"] != "pending":
        raise bad_request_exception("Candidature déjà traitée")

    now = datetime.now(timezone.utc)
    user_id = app["user_id"]

    if app["type"] == "driver":
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {"role": UserRole.DRIVER.value, "updated_at": now}},
        )

    elif app["type"] == "relay":
        data = app["data"]
        relay_id = f"rly_{uuid.uuid4().hex[:12]}"

        relay_doc = {
            "relay_id":          relay_id,
            "owner_user_id":     user_id,
            "agent_user_ids":    [user_id],
            "name":              data["business_name"],
            "address": {
                "label":   data["address_label"],
                "city":    data.get("city", "Dakar"),
                "geopin":  data.get("geopin"),
            },
            "phone":             app["user_phone"],
            "max_capacity":      30,
            "current_load":      0,
            "opening_hours":     data.get("opening_hours", ""),
            "zone_ids":          [],
            "coverage_radius_km": 5.0,
            "is_active":         True,
            "is_verified":       True,   # déjà vérifié par l'admin avant d'approuver
            "score":             5.0,
            "store_id":          None,
            "external_ref":      None,
            "created_at":        now,
            "updated_at":        now,
        }
        await db.relay_points.insert_one(relay_doc)
        await db.users.update_one(
            {"user_id": user_id},
            {"$set": {
                "role":           UserRole.RELAY_AGENT.value,
                "relay_point_id": relay_id,
                "updated_at":     now,
            }},
        )

    # Marquer la candidature comme approuvée
    await db.applications.update_one(
        {"application_id": application_id},
        {"$set": {"status": "approved", "admin_notes": admin_notes, "updated_at": now}},
    )
    return {"message": "Candidature approuvée", "application_id": application_id}


@router.put("/{application_id}/reject", summary="Rejeter candidature")
async def reject_application(
    application_id: str,
    admin_notes: Optional[str] = None,
    _admin=Depends(require_admin),
):
    app = await db.applications.find_one({"application_id": application_id})
    if not app:
        raise not_found_exception("Candidature")
    if app["status"] != "pending":
        raise bad_request_exception("Candidature déjà traitée")

    await db.applications.update_one(
        {"application_id": application_id},
        {"$set": {
            "status":      "rejected",
            "admin_notes": admin_notes,
            "updated_at":  datetime.now(timezone.utc),
        }},
    )
    return {"message": "Candidature rejetée"}
