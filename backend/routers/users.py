"""
Router users : gestion utilisateurs, enregistrement driver/agent relais.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, forbidden_exception
from database import db
from models.common import UserRole
from models.user import User, UserCreate

router = APIRouter()


@router.get("", summary="Liste utilisateurs (admin)")
async def list_users(
    skip: int = 0,
    limit: int = 50,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    cursor = db.users.find({}, {"_id": 0}).skip(skip).limit(limit)
    users = await cursor.to_list(length=limit)
    return {"users": users, "total": await db.users.count_documents({})}


@router.get("/{user_id}", response_model=User, summary="Détail utilisateur")
async def get_user(user_id: str, current_user: dict = Depends(get_current_user)):
    # Admin peut tout voir ; sinon seulement soi-même
    if current_user["role"] not in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]:
        if current_user["user_id"] != user_id:
            raise forbidden_exception()
    user_doc = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user_doc:
        raise not_found_exception("Utilisateur")
    return User(**user_doc)


@router.put("/{user_id}/role", summary="Changer rôle (admin)")
async def change_role(
    user_id: str,
    role: UserRole,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {"role": role.value, "updated_at": datetime.now(timezone.utc)}},
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")
    return {"message": f"Rôle mis à jour → {role.value}"}




@router.put("/me/availability", summary="Basculer la disponibilité (driver)")
async def toggle_availability(
    current_user: dict = Depends(get_current_user),
):
    """Permet au livreur de se mettre disponible ou hors-ligne."""
    current = current_user.get("is_available", False)
    new_val  = not current
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"is_available": new_val, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"is_available": new_val}


@router.put("/{user_id}/relay-point", summary="Lier un point relais à un agent (admin)")
async def assign_relay_point(
    user_id: str,
    relay_id: str,
    _admin=Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN)),
):
    """Associe relay_point_id à l'utilisateur agent relais."""
    relay = await db.relay_points.find_one({"relay_id": relay_id})
    if not relay:
        raise not_found_exception("Point relais")
    result = await db.users.update_one(
        {"user_id": user_id},
        {"$set": {
            "relay_point_id": relay_id,
            "role": UserRole.RELAY_AGENT.value,
            "updated_at": datetime.now(timezone.utc),
        }},
    )
    if result.matched_count == 0:
        raise not_found_exception("Utilisateur")
    return {"message": f"Agent {user_id} lié au relais {relay_id}"}
