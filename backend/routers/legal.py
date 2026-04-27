from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from database import db
from models.legal import LegalContent, LegalDocumentType, LegalContentUpdate
from core.dependencies import get_current_user, require_admin
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
         
    return LegalContent(**doc)
