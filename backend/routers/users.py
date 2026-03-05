"""
Router users : gestion utilisateurs, enregistrement driver/agent relais.
"""
import uuid
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, File, UploadFile
from core.dependencies import get_current_user, require_role
from core.exceptions import not_found_exception, forbidden_exception, bad_request_exception
import shutil
import os
from config import settings
from database import db
from models.common import UserRole
from models.user import User, UserCreate, ProfileUpdate, FavoriteAddress
from services.parcel_service import _record_event

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


from core.utils import mask_phone

@router.get("/{user_id}", response_model=User, summary="Détail utilisateur")
async def get_user(user_id: str, current_user: dict = Depends(get_current_user)):
    # Admin peut tout voir ; sinon seulement soi-même
    is_admin = current_user["role"] in [UserRole.ADMIN.value, UserRole.SUPERADMIN.value]
    if not is_admin:
        if current_user["user_id"] != user_id:
            # On ne devrait pas pouvoir voir d'autres utilisateurs, mais si l'API le permet (ex: via mission), on masque
            user_doc = await db.users.find_one({"user_id": user_id}, {"_id": 0})
            if user_doc:
                user_doc["phone"] = mask_phone(user_doc["phone"])
                return User(**user_doc)
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
    
    await _record_event(
        event_type="USER_ROLE_CHANGED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Changement de rôle pour {user_id} → {role.value}",
        metadata={"target_user_id": user_id, "new_role": role.value}
    )
    
    return {"message": f"Rôle mis à jour → {role.value}"}

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
        "scan_rate_pct":  scan_rate,   # 100% = toutes les livraisons validées par code depuis la maj
    }
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


@router.put("/me/fcm-token", summary="Mettre à jour le token FCM (push)")
async def update_fcm_token(
    token_body: dict,
    current_user: dict = Depends(get_current_user),
):
    """Enregistre le token Firebase Cloud Messaging de l'appareil."""
    token = token_body.get("fcm_token")
    if not token:
        raise bad_request_exception("fcm_token manquant")
        
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"fcm_token": token, "updated_at": datetime.now(timezone.utc)}},
    )
    return {"message": "Token FCM mis à jour"}


@router.put("/me/profile", summary="Mise à jour profil (Bio, Email, Prefs)")
async def update_my_profile(
    body: ProfileUpdate,
    current_user: dict = Depends(get_current_user),
):
    updates = body.model_dump(exclude_none=True)
    if not updates:
        return current_user

    updates["updated_at"] = datetime.now(timezone.utc)
    
    # Si email présent, vérifier unicité (optionnel mais recommandé)
    if body.email:
        existing = await db.users.find_one({"email": body.email, "user_id": {"$ne": current_user["user_id"]}})
        if existing:
            raise bad_request_exception("Cet email est déjà utilisé")

    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": updates}
    )
    
    updated_user = await db.users.find_one({"user_id": current_user["user_id"]}, {"_id": 0})
    return updated_user


@router.get("/me/favorite-addresses", summary="Mes adresses favorites")
async def get_favorites(current_user: dict = Depends(get_current_user)):
    return current_user.get("favorite_addresses", [])


@router.post("/me/favorite-addresses", summary="Ajouter une adresse favorite")
async def add_favorite(
    addr: FavoriteAddress,
    current_user: dict = Depends(get_current_user),
):
    # Vérifier doublons par nom
    favs = current_user.get("favorite_addresses", [])
    if any(f["name"] == addr.name for f in favs):
        raise bad_request_exception(f"Une adresse nommée '{addr.name}' existe déjà")
    
    if len(favs) >= 10:
        raise bad_request_exception("Maximum 10 adresses favorites autorisées")

    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$push": {"favorite_addresses": addr.model_dump()}}
    )
    return {"message": f"Adresse '{addr.name}' ajoutée"}


@router.delete("/me/favorite-addresses/{name}", summary="Supprimer une adresse favorite")
async def delete_favorite(
    name: str,
    current_user: dict = Depends(get_current_user),
):
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$pull": {"favorite_addresses": {"name": name}}}
    )
    return {"message": "Adresse supprimée"}
 
 
@router.post("/me/avatar", summary="Uploader photo de profil")
async def upload_avatar(
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Enregistre une nouvelle photo de profil."""
    if not file.content_type.startswith("image/"):
        raise bad_request_exception("Le fichier doit être une image")
        
    ext = os.path.splitext(file.filename)[1].lower()
    if ext not in [".jpg", ".jpeg", ".png", ".webp"]:
        raise bad_request_exception("Format d'image non supporté (.jpg, .png, .webp uniquement)")
        
    filename = f"profile_{current_user['user_id']}_{uuid.uuid4().hex[:8]}{ext}"
    relative_path = os.path.join("profiles", filename)
    absolute_path = os.path.join("uploads", relative_path)
    
    # Surtout sur Windows, s'assurer que le dossier existe (bien que créé par le script)
    os.makedirs(os.path.dirname(absolute_path), exist_ok=True)
    
    with open(absolute_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    # URL finale à enregistrer
    profile_url = f"{settings.BASE_URL}/uploads/profiles/{filename}"
    
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"profile_picture_url": profile_url, "updated_at": datetime.now(timezone.utc)}},
    )
    
    return {"profile_picture_url": profile_url}


@router.post("/me/kyc", summary="Uploader pièce d'identité (KYC)")
async def upload_kyc(
    doc_type: Literal["id_card", "license"] = "id_card",
    file: UploadFile = File(...),
    current_user: dict = Depends(get_current_user),
):
    """Enregistre un document d'identité pour vérification."""
    if not file.content_type.startswith("image/") and file.content_type != "application/pdf":
        raise bad_request_exception("Le fichier doit être une image ou un PDF")
        
    ext = os.path.splitext(file.filename)[1].lower()
    filename = f"kyc_{doc_type}_{current_user['user_id']}_{uuid.uuid4().hex[:8]}{ext}"
    relative_path = os.path.join("kyc", filename)
    absolute_path = os.path.join("uploads", relative_path)
    
    os.makedirs(os.path.dirname(absolute_path), exist_ok=True)
    
    with open(absolute_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    doc_url = f"{settings.BASE_URL}/uploads/kyc/{filename}"
    
    field_to_update = "kyc_id_card_url" if doc_type == "id_card" else "kyc_license_url"
    
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {
            field_to_update: doc_url,
            "kyc_status": "pending",
            "updated_at": datetime.now(timezone.utc)
        }},
    )
    
    return {"kyc_status": "pending", "doc_url": doc_url, "doc_type": doc_type}


@router.get("/me/stats", summary="Statistiques d'activité utilisateur")
async def get_my_stats(current_user: dict = Depends(get_current_user)):
    """Retourne des stats sur les colis envoyés/reçus."""
    user_id = current_user["user_id"]
    
    sent_count = await db.parcels.count_documents({"sender_user_id": user_id})
    received_count = await db.parcels.count_documents({"recipient_phone": current_user["phone"]})
    
    # Points et Tier (déjà en base mais on regroupe ici pour le widget mobile)
    return {
        "parcels_sent": sent_count,
        "parcels_received": received_count,
        "total_parcels": sent_count + received_count,
        "loyalty_points": current_user.get("loyalty_points", 0),
        "loyalty_tier": current_user.get("loyalty_tier", "bronze"),
        "referrals_count": await db.users.count_documents({"referred_by": user_id})
    }


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
    
    await _record_event(
        event_type="USER_RELAY_ASSIGNED",
        actor_id=_admin.get("user_id") if isinstance(_admin, dict) else "admin",
        actor_role="admin",
        notes=f"Agent {user_id} lié au relais {relay_id}",
        metadata={"target_user_id": user_id, "relay_id": relay_id}
    )
    
    return {"message": f"Agent {user_id} lié au relais {relay_id}"}


# ── Fidélité & Parrainage ───────────────────────────────────────────────────

@router.get("/me/loyalty", summary="Statistiques de fidélité")
async def get_my_loyalty(current_user: dict = Depends(get_current_user)):
    """Retourne les points, le tier et l'historique de fidélité."""
    from services.user_service import compute_tier
    
    events = await db.loyalty_events.find(
        {"user_id": current_user["user_id"]},
        sort=[("created_at", -1)],
        limit=20
    ).to_list(length=20)
    
    points = current_user.get("loyalty_points", 0)
    tier = compute_tier(points)
    
    # Prochain palier
    next_tier_at = 200 if tier == "bronze" else 500 if tier == "silver" else None
    
    return {
        "points":        points,
        "tier":          tier,
        "next_tier_at":  next_tier_at,
        "referral_code": current_user.get("referral_code", ""),
        "history":       events,
    }


@router.post("/refer", summary="Code parrainage")
async def get_referral_info(current_user: dict = Depends(get_current_user)):
    """Retourne le code parrainage et le lien."""
    code = current_user.get("referral_code", "")
    return {
        "referral_code": code,
        "referral_url":  f"https://pickupoint.sn/join?ref={code}"
    }


@router.post("/apply-referral", summary="Appliquer un parrain")
async def apply_referral_code(
    body: dict,
    current_user: dict = Depends(get_current_user),
):
    """Lie l'utilisateur courant à un parrain via son code."""
    code = body.get("referral_code", "").upper().strip()
    if not code:
        from core.exceptions import bad_request_exception
        raise bad_request_exception("Code parrainage manquant")
        
    if current_user.get("referred_by"):
        from core.exceptions import bad_request_exception
        raise bad_request_exception("Vous avez déjà un parrain")
        
    parrain = await db.users.find_one({"referral_code": code})
    if not parrain:
        raise not_found_exception("Code parrainage invalide")
        
    if parrain["user_id"] == current_user["user_id"]:
        from core.exceptions import bad_request_exception
        raise bad_request_exception("Action impossible")

    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"referred_by": parrain["user_id"], "updated_at": datetime.now(timezone.utc)}}
    )
    return {"message": "Parrainage appliqué ! Bonus crédité après votre 1ère livraison livrée."}
