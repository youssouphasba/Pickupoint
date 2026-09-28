"""Accès aux données personnelles et traitement des demandes utilisateur."""
from datetime import datetime, timezone
from io import BytesIO
from typing import Literal, Optional
import json
from uuid import uuid4
from xml.sax.saxutils import escape

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field

from core.dependencies import get_current_user, require_role
from core.exceptions import bad_request_exception, not_found_exception
from database import db
from models.common import UserRole

router = APIRouter()
require_admin_dep = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)

REQUEST_TYPES = {"export", "access", "rectification", "deletion", "opposition", "restriction"}
REQUEST_STATUSES = {"pending", "in_progress", "completed", "rejected"}


class PrivacyRequestCreate(BaseModel):
    request_type: Literal["export", "access", "rectification", "deletion", "opposition", "restriction"]
    message: Optional[str] = Field(default=None, max_length=2000)


class PrivacyRequestUpdate(BaseModel):
    status: Literal["pending", "in_progress", "completed", "rejected"]
    admin_response: Optional[str] = Field(default=None, max_length=3000)


def _request_payload(item: dict) -> dict:
    item.pop("_id", None)
    return item


def _safe_profile(user: dict) -> dict:
    fields = (
        "user_id", "name", "phone", "email", "role", "user_type", "language",
        "country_code", "notification_prefs", "favorite_addresses", "bio",
        "accepted_legal", "accepted_legal_at", "created_at", "updated_at",
    )
    return {field: user.get(field) for field in fields if field in user}


def _safe_parcel(parcel: dict, user_id: str) -> dict:
    is_sender = parcel.get("sender_user_id") == user_id
    return {
        "parcel_id": parcel.get("parcel_id"),
        "tracking_code": parcel.get("tracking_code"),
        "role": "expéditeur" if is_sender else "destinataire",
        "recipient_name": parcel.get("recipient_name") if is_sender else None,
        "delivery_mode": parcel.get("delivery_mode"),
        "status": parcel.get("status"),
        "origin_relay_id": parcel.get("origin_relay_id"),
        "destination_relay_id": parcel.get("destination_relay_id"),
        "delivery_address": parcel.get("delivery_address") if is_sender else None,
        "quoted_price": parcel.get("quoted_price") if is_sender else None,
        "paid_price": parcel.get("paid_price") if is_sender else None,
        "payment_status": parcel.get("payment_status"),
        "created_at": parcel.get("created_at"),
        "updated_at": parcel.get("updated_at"),
    }


def _user_parcel_query(user: dict) -> dict:
    user_id = user["user_id"]
    clauses = [
        {"sender_user_id": user_id},
        {"recipient_user_id": user_id},
    ]
    phone = str(user.get("phone") or "").strip()
    if phone:
        clauses.append({"recipient_phone": phone})
    return {"$or": clauses}


async def _build_export(user: dict) -> dict:
    user_id = user["user_id"]
    parcels = await db.parcels.find(
        _user_parcel_query(user),
        {"_id": 0},
        sort=[("created_at", -1)],
    ).to_list(length=5000)
    requests = await db.privacy_requests.find(
        {"user_id": user_id}, {"_id": 0}, sort=[("created_at", -1)]
    ).to_list(length=200)
    return {
        "generated_at": datetime.now(timezone.utc),
        "profile": _safe_profile(user),
        "parcels": [_safe_parcel(parcel, user_id) for parcel in parcels],
        "privacy_requests": requests,
    }


@router.get("/users/me/data-summary", summary="Résumé de mes données")
async def get_my_data_summary(current_user: dict = Depends(get_current_user)):
    user_id = current_user["user_id"]
    parcel_query = _user_parcel_query(current_user)
    parcels = await db.parcels.find(
        parcel_query,
        {"_id": 0, "parcel_id": 1, "tracking_code": 1, "delivery_mode": 1, "status": 1, "created_at": 1, "updated_at": 1},
        sort=[("created_at", -1)],
        limit=10,
    ).to_list(length=10)
    request_count = await db.privacy_requests.count_documents({"user_id": user_id})
    open_count = await db.privacy_requests.count_documents({"user_id": user_id, "status": {"$in": ["pending", "in_progress"]}})
    return {
        "profile": _safe_profile(current_user),
        "parcel_count": await db.parcels.count_documents(parcel_query),
        "recent_parcels": parcels,
        "privacy_request_count": request_count,
        "open_privacy_request_count": open_count,
    }


@router.get("/users/me/data-export", summary="Télécharger mes données")
async def download_my_data(current_user: dict = Depends(get_current_user)):
    export = await _build_export(current_user)
    content = json.dumps(export, ensure_ascii=False, default=lambda value: value.isoformat() if hasattr(value, "isoformat") else str(value), indent=2)
    return Response(
        content=content,
        media_type="application/json; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="denkma-mes-donnees.json"'},
    )


def _pdf_value(value) -> str:
    if value is None or value == "":
        return "—"
    if isinstance(value, dict):
        return "; ".join(f"{key}: {_pdf_value(item)}" for key, item in value.items())
    if isinstance(value, list):
        return ", ".join(_pdf_value(item) for item in value)
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return escape(str(value))


def _build_pdf(export: dict) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    buffer = BytesIO()
    document = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=16 * mm, leftMargin=16 * mm, topMargin=16 * mm, bottomMargin=16 * mm, title="Mes données Denkma", author="Denkma")
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("DenkmaTitle", parent=styles["Title"], alignment=TA_CENTER, textColor=colors.HexColor("#1769d1"), spaceAfter=8)
    body_style = ParagraphStyle("DenkmaBody", parent=styles["Normal"], fontSize=9, leading=12)
    small_style = ParagraphStyle("DenkmaSmall", parent=styles["Normal"], fontSize=8, textColor=colors.HexColor("#666666"), leading=10)
    story = [Paragraph("Denkma — Mes données personnelles", title_style), Paragraph(f"Document généré le {_pdf_value(export['generated_at'])}", small_style), Spacer(1, 8)]
    profile = export.get("profile", {})
    profile_rows = [[Paragraph("Information", body_style), Paragraph("Valeur", body_style)]]
    for label, key in (("Nom", "name"), ("Téléphone", "phone"), ("E-mail", "email"), ("Rôle", "role"), ("Pays", "country_code"), ("Langue", "language"), ("Compte créé le", "created_at")):
        profile_rows.append([Paragraph(label, body_style), Paragraph(_pdf_value(profile.get(key)), body_style)])
    story.append(Paragraph("Mon profil", styles["Heading2"]))
    profile_table = Table(profile_rows, colWidths=[45 * mm, 130 * mm], repeatRows=1)
    profile_table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8f1ff")), ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#ccd6e5")), ("VALIGN", (0, 0), (-1, -1), "TOP"), ("PADDING", (0, 0), (-1, -1), 6)]))
    story.extend([profile_table, Spacer(1, 10), Paragraph(f"Colis associés ({len(export.get('parcels', []))})", styles["Heading2"])])
    parcel_rows = [[Paragraph(label, body_style) for label in ("Suivi", "Rôle", "Mode", "Statut", "Créé le")]]
    for parcel in export.get("parcels", []):
        parcel_rows.append([Paragraph(_pdf_value(parcel.get(key)), body_style) for key in ("tracking_code", "role", "delivery_mode", "status", "created_at")])
    if len(parcel_rows) == 1:
        parcel_rows.append([Paragraph("Aucun colis associé", body_style), "", "", "", ""])
    parcel_table = Table(parcel_rows, colWidths=[32 * mm, 25 * mm, 35 * mm, 30 * mm, 53 * mm], repeatRows=1)
    parcel_table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8f1ff")), ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#ccd6e5")), ("VALIGN", (0, 0), (-1, -1), "TOP"), ("PADDING", (0, 0), (-1, -1), 5)]))
    story.extend([parcel_table, Spacer(1, 10), Paragraph("Demandes de données", styles["Heading2"])])
    for request in export.get("privacy_requests", []):
        story.append(Paragraph(f"{_pdf_value(request.get('request_type'))} — {_pdf_value(request.get('status'))} — {_pdf_value(request.get('created_at'))}", body_style))
    document.build(story)
    return buffer.getvalue()


@router.get("/users/me/data-export.pdf", summary="Télécharger mes données en PDF")
async def download_my_data_pdf(current_user: dict = Depends(get_current_user)):
    pdf = _build_pdf(await _build_export(current_user))
    return Response(content=pdf, media_type="application/pdf", headers={"Content-Disposition": 'attachment; filename="denkma-mes-donnees.pdf"'})


@router.get("/users/me/privacy-requests", summary="Mes demandes de données")
async def list_my_privacy_requests(current_user: dict = Depends(get_current_user)):
    items = await db.privacy_requests.find(
        {"user_id": current_user["user_id"]}, {"_id": 0}, sort=[("created_at", -1)]
    ).to_list(length=100)
    return {"requests": items}


@router.post("/users/me/privacy-requests", summary="Créer une demande de données")
async def create_privacy_request(
    body: PrivacyRequestCreate,
    current_user: dict = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)
    user_id = current_user["user_id"]
    existing = await db.privacy_requests.find_one({
        "user_id": user_id,
        "request_type": body.request_type,
        "status": {"$in": ["pending", "in_progress"]},
    })
    if existing:
        raise bad_request_exception("Une demande de ce type est déjà en cours de traitement.")
    item = {
        "request_id": f"PR-{now.strftime('%Y%m%d%H%M%S')}-{uuid4().hex[:8].upper()}",
        "user_id": user_id,
        "user_name": current_user.get("name"),
        "user_phone": current_user.get("phone"),
        "request_type": body.request_type,
        "message": (body.message or "").strip() or None,
        "status": "pending",
        "admin_response": None,
        "created_at": now,
        "updated_at": now,
    }
    await db.privacy_requests.insert_one(item)
    return {"request": _request_payload(item)}


@router.get("/admin/privacy-requests", summary="Demandes de données à traiter")
async def admin_list_privacy_requests(
    status: Optional[str] = Query(default=None),
    request_type: Optional[str] = Query(default=None),
    search: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    skip: int = Query(default=0, ge=0),
    _admin=Depends(require_admin_dep),
):
    query: dict = {}
    if status and status in REQUEST_STATUSES:
        query["status"] = status
    if request_type and request_type in REQUEST_TYPES:
        query["request_type"] = request_type
    if search and search.strip():
        term = search.strip()
        query["$or"] = [
            {"request_id": {"$regex": term, "$options": "i"}},
            {"user_name": {"$regex": term, "$options": "i"}},
            {"user_phone": {"$regex": term, "$options": "i"}},
        ]
    items = await db.privacy_requests.find(query, {"_id": 0}, sort=[("created_at", -1)]).skip(skip).limit(limit).to_list(length=limit)
    return {"requests": items, "total": await db.privacy_requests.count_documents(query)}


@router.get("/admin/privacy-requests/{request_id}", summary="Détail d'une demande de données")
async def admin_get_privacy_request(request_id: str, _admin=Depends(require_admin_dep)):
    item = await db.privacy_requests.find_one({"request_id": request_id}, {"_id": 0})
    if not item:
        raise not_found_exception("Demande de données")
    user = await db.users.find_one({"user_id": item["user_id"]}, {"_id": 0})
    return {"request": item, "user": _safe_profile(user or {})}


@router.patch("/admin/privacy-requests/{request_id}", summary="Répondre à une demande de données")
async def admin_update_privacy_request(
    request_id: str,
    body: PrivacyRequestUpdate,
    admin=Depends(require_admin_dep),
):
    item = await db.privacy_requests.find_one({"request_id": request_id}, {"_id": 0})
    if not item:
        raise not_found_exception("Demande de données")
    now = datetime.now(timezone.utc)
    update = {
        "status": body.status,
        "admin_response": (body.admin_response or "").strip() or None,
        "updated_at": now,
        "processed_by": admin.get("user_id"),
    }
    if body.status in {"completed", "rejected"}:
        update["completed_at"] = now
    await db.privacy_requests.update_one({"request_id": request_id}, {"$set": update})
    return {"request": {**item, **update}}
