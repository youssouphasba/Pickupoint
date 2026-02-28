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


@router.post("/register-driver", summary="S'enregistrer comme livreur")
async def register_driver(current_user: dict = Depends(get_current_user)):
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"role": UserRole.DRIVER.value, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"message": "Vous êtes maintenant enregistré comme livreur"}


@router.post("/register-relay", summary="S'enregistrer comme agent relais")
async def register_relay(current_user: dict = Depends(get_current_user)):
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"role": UserRole.RELAY_AGENT.value, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"message": "Vous êtes maintenant enregistré comme agent relais"}
