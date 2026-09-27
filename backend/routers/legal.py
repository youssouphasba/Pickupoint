from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel

from database import db
from models.legal import LegalContent, LegalDocumentType, LegalContentUpdate
from core.dependencies import get_current_user, require_admin
from services.notification_service import send_targeted_notifications
from services.parcel_service import _record_event

router = APIRouter()


@router.get("/{doc_type}", response_model=LegalContent, summary="Récupérer un document légal")
async def get_legal_content(doc_type: LegalDocumentType):
    """
    Récupère la politique de confidentialité ou les CGU en fonction du doc_type.
    """
    doc = await db.legal_contents.find_one({"document_type": doc_type.value}, {"_id": 0})
    if not doc:
        # Si le document n'existe pas encore, on renvoie une coquille vide pour ne pas casser l'app
        default_titles = {
            LegalDocumentType.PRIVACY_POLICY: "Politique de confidentialité",
            LegalDocumentType.CGU: "Conditions Générales d'Utilisation",
            LegalDocumentType.MENTIONS_LEGALES: "Mentions légales",
        }
        default_title = default_titles[doc_type]
        return LegalContent(
            document_type=doc_type,
            title=default_title,
            content="Le contenu de ce document sera bientôt mis à jour.",
            updated_at=datetime.now(timezone.utc)
        )
    return LegalContent(**doc)


@router.post("/{doc_type}/view", summary="Enregistrer la lecture d'un document légal")
async def mark_legal_document_view(
    doc_type: LegalDocumentType,
    current_user: dict = Depends(get_current_user),
):
    doc = await db.legal_contents.find_one({"document_type": doc_type.value}, {"_id": 0, "updated_at": 1})
    version = doc.get("updated_at") if doc else None
    if not version:
        return {"recorded": False}
    version_key = version.isoformat() if hasattr(version, "isoformat") else str(version)
    now = datetime.now(timezone.utc)
    await db.legal_document_views.update_one(
        {"user_id": current_user["user_id"], "document_type": doc_type.value, "document_version": version_key},
        {"$set": {"viewed_at": now, "user_name": current_user.get("name"), "user_phone": current_user.get("phone")}},
        upsert=True,
    )
    return {"recorded": True, "document_type": doc_type.value, "document_version": version_key, "viewed_at": now}


@router.get("/admin/{doc_type}/reading-stats", summary="Suivi de lecture d'un document légal")
async def legal_reading_stats(
    doc_type: LegalDocumentType,
    search: str | None = Query(default=None),
    _admin: dict = Depends(require_admin),
):
    doc = await db.legal_contents.find_one({"document_type": doc_type.value}, {"_id": 0, "updated_at": 1})
    version = doc.get("updated_at") if doc else None
    version_key = version.isoformat() if hasattr(version, "isoformat") else str(version or "")
    user_query = {"role": {"$nin": ["admin", "superadmin"]}, "is_active": True}
    if search and search.strip():
        term = search.strip()
        user_query["$or"] = [
            {"name": {"$regex": term, "$options": "i"}},
            {"phone": {"$regex": term, "$options": "i"}},
        ]
    users = await db.users.find(user_query, {"_id": 0, "user_id": 1, "name": 1, "phone": 1, "role": 1}).sort("name", 1).to_list(length=10000)
    viewed_ids = set()
    if version_key:
        viewed_ids = {item["user_id"] async for item in db.legal_document_views.find({"document_type": doc_type.value, "document_version": version_key}, {"_id": 0, "user_id": 1})}
    readers = [{**user, "has_read": user["user_id"] in viewed_ids} for user in users]
    return {"document_type": doc_type.value, "document_version": version_key, "total_users": len(users), "read_count": sum(1 for user in readers if user["has_read"]), "unread_count": sum(1 for user in readers if not user["has_read"]), "users": readers}


@router.put("/{doc_type}", response_model=LegalContent, summary="Mettre à jour un document légal")
async def update_legal_content(
    doc_type: LegalDocumentType,
    body: LegalContentUpdate,
    current_admin: dict = Depends(require_admin)
):
    """
    Met à jour ou crée un document légal (Réservé aux administrateurs).
    """
    now = datetime.now(timezone.utc)
    
    # Prépare les données de mise à jour
    update_data = {
        "content": body.content,
        "updated_at": now,
        "updated_by": current_admin.get("user_id")
    }
    
    if body.title:
        update_data["title"] = body.title

    # Upsert: crée si non existant, met à jour sinon
    await db.legal_contents.update_one(
        {"document_type": doc_type.value},
        {"$set": update_data, "$setOnInsert": {"document_type": doc_type.value}},
        upsert=True
    )
    
    # On gère le titre par défaut s'il n'était pas fourni lors du premier insert
    doc = await db.legal_contents.find_one({"document_type": doc_type.value}, {"_id": 0})
    
    if "title" not in doc:
         default_titles = {
             LegalDocumentType.PRIVACY_POLICY: "Politique de confidentialité",
             LegalDocumentType.CGU: "Conditions Générales d'Utilisation",
             LegalDocumentType.MENTIONS_LEGALES: "Mentions légales",
         }
         default_title = default_titles[doc_type]
         await db.legal_contents.update_one(
             {"document_type": doc_type.value},
             {"$set": {"title": default_title}}
         )
         doc["title"] = default_title
    
    await _record_event(
        event_type="LEGAL_DOC_UPDATED",
        actor_id=current_admin.get("user_id"),
        actor_role="admin",
        notes=f"Mise à jour du document : {doc_type.value}",
        metadata={"doc_type": doc_type.value}
    )

    user_ids = await db.users.distinct("user_id", {"is_active": True, "role": {"$nin": ["admin", "superadmin"]}})
    document_label = "la politique de confidentialité" if doc_type.value == "privacy_policy" else "les CGU" if doc_type.value == "cgu" else "les mentions légales"
    await send_targeted_notifications(
        user_ids=user_ids,
        title="Document juridique mis à jour",
        body=f"{document_label.capitalize()} a été mis à jour. Ouvrez l'application pour en prendre connaissance.",
        category="admin",
        ref_type="legal_document",
        ref_id=doc_type.value,
        dedupe_key=f"legal_update:{doc_type.value}:{now.isoformat()}",
    )
         
    return LegalContent(**doc)
