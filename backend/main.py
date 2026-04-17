import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from slowapi.errors import RateLimitExceeded
from slowapi import _rate_limit_exceeded_handler

from core.limiter import limiter

from config import UPLOADS_DIR, settings
from database import connect_db, close_db, db

from apscheduler.schedulers.asyncio import AsyncIOScheduler

# Routers
from routers import auth, users, relay_points, parcels, tracking, deliveries, pricing, wallets, admin, admin_auth, webhooks, confirm, applications, promotions, legal, app_settings

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Rate limiter est maintenant dans core/limiter.py


async def _auto_release_stuck_missions() -> None:
    """
    Toutes les 2 min : libère les missions ASSIGNED depuis plus de 15 min
    sans que le livreur ait confirmé la collecte (started_at absent).
    """
    from database import db as _db
    while True:
        await asyncio.sleep(120)  # vérification toutes les 2 minutes
        try:
            cutoff = datetime.now(timezone.utc) - timedelta(minutes=15)
            cursor = _db.delivery_missions.find({
                "status":      "assigned",
                "assigned_at": {"$lt": cutoff},
                "started_at":  None,          # collecte jamais confirmée
            })
            released = 0
            async for mission in cursor:
                now = datetime.now(timezone.utc)
                update_result = await _db.delivery_missions.update_one(
                    {
                        "mission_id": mission["mission_id"],
                        "status": "assigned",
                        "assigned_at": {"$lt": cutoff},
                        "started_at": None,
                        "driver_id": mission.get("driver_id"),
                    },
                    {"$set": {
                        "status": "pending",
                        "driver_id": None,
                        "assigned_at": None,
                        "updated_at": now,
                    }},
                )
                if update_result.modified_count == 0:
                    continue
                await _db.parcels.update_one(
                    {
                        "parcel_id": mission["parcel_id"],
                        "assigned_driver_id": mission.get("driver_id"),
                    },
                    {"$set": {"assigned_driver_id": None, "updated_at": now}},
                )
                released += 1
            if released:
                logger.info(f"Auto-release : {released} mission(s) libérée(s) après 15 min d'inactivité")
        except Exception as exc:
            logger.error(f"Erreur auto-release missions : {exc}")


async def _monthly_ranking_job():
    """Tourne le 1er de chaque mois à 01:00 UTC."""
    try:
        now = datetime.now(timezone.utc)
        # Calculer pour le mois précédent
        if now.month == 1:
            period = f"{now.year - 1}-12"
        else:
            period = f"{now.year}-{now.month - 1:02d}"

        logger.info(f"Démarrage du calcul des classements mensuels pour {period}...")
        
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
        
        # 3. Stats & Bonus Relais
        await compute_relay_stats_and_pay_bonuses(period)
        
        logger.info(f"Classements et bonus pour {period} terminés avec succès.")
    except Exception as exc:
        logger.error(f"Erreur lors du calcul mensuel des classements : {exc}")


async def _advance_delivery_dispatch_loop() -> None:
    """Fait progresser le dispatch en cascade hors des endpoints GET."""
    while True:
        await asyncio.sleep(15)
        try:
            updated = await deliveries.advance_pending_delivery_dispatch()
            if updated:
                logger.info("Dispatch cascade : %s mission(s) avancée(s)", updated)
        except Exception as exc:
            logger.error("Erreur dispatch cascade : %s", exc)


async def _maybe_send_gps_reminder(parcel: dict, actor: str, now: datetime) -> bool:
    from services.notification_service import notify_location_confirmation_request
    from services.parcel_service import _record_event

    reminders = parcel.get("gps_reminders") or {}
    reminder_state = reminders.get(actor) or {}
    if reminder_state.get("confirmed_at"):
        return False

    token_field = "sender_confirm_token" if actor == "sender" else "recipient_confirm_token"
    token = parcel.get(token_field)
    if not token:
        return False

    count = int(reminder_state.get("count") or 0)
    if count >= settings.GPS_REMINDER_MAX_COUNT:
        return False

    last_sent_at = reminder_state.get("last_sent_at")
    if last_sent_at and last_sent_at.tzinfo is None:
        last_sent_at = last_sent_at.replace(tzinfo=timezone.utc)

    user_id = parcel.get("sender_user_id") if actor == "sender" else parcel.get("recipient_user_id")
    has_app = bool(user_id)
    initial_delay = timedelta(minutes=settings.GPS_REMINDER_INITIAL_MINUTES)
    escalation_delay = timedelta(minutes=settings.GPS_REMINDER_ESCALATION_MINUTES)

    if last_sent_at is None:
        reference_time = parcel.get("created_at") or now
        if reference_time.tzinfo is None:
            reference_time = reference_time.replace(tzinfo=timezone.utc)
        if now - reference_time < initial_delay:
            return False
        escalate_external = not has_app
    else:
        min_delay = escalation_delay if has_app and count == 1 else initial_delay
        if now - last_sent_at < min_delay:
            return False
        escalate_external = (not has_app) or (has_app and count >= 1)

    confirm_url = f"{settings.BASE_URL}/confirm/{token}"
    await notify_location_confirmation_request(
        parcel,
        actor=actor,
        confirm_url=confirm_url,
        escalate_external=escalate_external,
    )

    channel = "sms_whatsapp"
    if has_app and escalate_external:
        channel = "in_app_push+sms_whatsapp"
    elif has_app:
        channel = "in_app_push"

    await db.parcels.update_one(
        {"parcel_id": parcel["parcel_id"]},
        {"$set": {
            f"gps_reminders.{actor}.count": count + 1,
            f"gps_reminders.{actor}.last_sent_at": now,
            f"gps_reminders.{actor}.last_channel": channel,
            "updated_at": now,
        }},
    )
    await _record_event(
        parcel_id=parcel["parcel_id"],
        event_type="GPS_CONFIRMATION_REMINDER_SENT",
        actor_id="system",
        actor_role="system",
        notes=f"Relance GPS {actor}",
        metadata={"actor": actor, "channel": channel, "count": count + 1},
    )
    return True


async def _gps_confirmation_reminder_loop() -> None:
    while True:
        await asyncio.sleep(120)
        try:
            query = {
                "status": {
                    "$nin": [
                        "delivered",
                        "cancelled",
                        "returned",
                        "expired",
                    ]
                },
                "$or": [
                    {
                        "delivery_mode": {"$regex": "^home_to_"},
                        "pickup_confirmed": False,
                        "sender_confirm_token": {"$exists": True},
                    },
                    {
                        "delivery_mode": {"$regex": "_to_home$"},
                        "delivery_confirmed": False,
                        "recipient_confirm_token": {"$exists": True},
                    },
                ],
            }
            parcels_to_remind = await db.parcels.find(query, {"_id": 0}).to_list(length=200)
            reminded = 0
            now = datetime.now(timezone.utc)
            for parcel in parcels_to_remind:
                if parcel.get("delivery_mode", "").startswith("home_to_") and not parcel.get("pickup_confirmed"):
                    reminded += 1 if await _maybe_send_gps_reminder(parcel, "sender", now) else 0
                if parcel.get("delivery_mode", "").endswith("_to_home") and not parcel.get("delivery_confirmed"):
                    reminded += 1 if await _maybe_send_gps_reminder(parcel, "recipient", now) else 0
            if reminded:
                logger.info("Relances GPS envoyées : %s", reminded)
        except Exception as exc:
            logger.error("Erreur relances GPS : %s", exc)


async def _expire_stale_parcels():
    """Expire les colis AVAILABLE_AT_RELAY / REDIRECTED_TO_RELAY dont expires_at est dépassé."""
    try:
        from services.notification_service import notify_parcel_expired
        now = datetime.now(timezone.utc)
        query = {
            "status": {"$in": ["available_at_relay", "redirected_to_relay"]},
            "expires_at": {"$lte": now},
        }
        expired_parcels = await db.parcels.find(query, {"_id": 0}).to_list(length=100)
        for parcel in expired_parcels:
            await db.parcels.update_one(
                {"parcel_id": parcel["parcel_id"]},
                {"$set": {"status": "expired", "updated_at": now}},
            )
            await notify_parcel_expired(parcel)
            logger.info("Colis %s expiré automatiquement", parcel.get("tracking_code"))
    except Exception as exc:
        logger.error("Erreur job expiration colis : %s", exc)


scheduler = AsyncIOScheduler()
scheduler.add_job(_monthly_ranking_job, "cron", day=1, hour=1, minute=0)
scheduler.add_job(_expire_stale_parcels, "interval", hours=1)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await connect_db()
    scheduler.start()
    auto_release_task = asyncio.create_task(_auto_release_stuck_missions())
    dispatch_task = asyncio.create_task(_advance_delivery_dispatch_loop())
    gps_reminder_task = asyncio.create_task(_gps_confirmation_reminder_loop())
    logger.info("Denkma API started (with scheduler)")
    yield
    # Shutdown
    auto_release_task.cancel()
    dispatch_task.cancel()
    gps_reminder_task.cancel()
    scheduler.shutdown()
    await close_db()
    logger.info("Denkma API stopped")


app = FastAPI(
    title="Denkma API",
    description="Plateforme de livraison et points relais — Sénégal",
    version="1.0.0",
    lifespan=lifespan,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:8080", "http://localhost:8001"] if settings.DEBUG else ["https://pickupoint.sn", "https://denkma.sn", "https://admin.denkma.com", "https://denkma.com", "https://www.denkma.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    if not settings.DEBUG:
        response.headers.setdefault(
            "Strict-Transport-Security",
            "max-age=31536000; includeSubDomains",
        )
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    response.headers.setdefault("Cross-Origin-Opener-Policy", "same-origin")
    response.headers.setdefault(
        "Permissions-Policy",
        "camera=(), microphone=(), geolocation=(self)",
    )
    response.headers.setdefault(
        "Content-Security-Policy",
        "default-src 'self'; "
        "base-uri 'self'; "
        "frame-ancestors 'none'; "
        "img-src 'self' data: https:; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "script-src 'self' 'unsafe-inline'; "
        "connect-src 'self' https:; "
        "media-src 'self' https: data: blob:;",
    )
    return response

# Les photos de profil sont désormais servies via l'endpoint authentifié
# /api/users/photo/{filename}. StaticFiles reste monté en lecture seule pour
# servir les URLs legacy déjà stockées en base — à retirer après migration
# côté mobile (Dio + JWT sur le chargement d'image).
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")

# Routers — publics (sans auth)
app.include_router(tracking.router, prefix="/api/tracking", tags=["Tracking"])
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["Webhooks"])
app.include_router(confirm.router, prefix="/confirm", tags=["Confirmation GPS"])  # lien SMS/WhatsApp
app.include_router(legal.router, prefix="/api/legal", tags=["Legal"])
app.include_router(app_settings.router, prefix="/api/settings", tags=["App Settings"])

# Routers — avec auth
app.include_router(auth.router, prefix="/api/auth", tags=["Auth"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(relay_points.router, prefix="/api/relay-points", tags=["Relay Points"])
app.include_router(parcels.router, prefix="/api/parcels", tags=["Parcels"])
app.include_router(deliveries.router, prefix="/api/deliveries", tags=["Deliveries"])
app.include_router(pricing.router, prefix="/api/pricing", tags=["Pricing"])
app.include_router(wallets.router, prefix="/api/wallets", tags=["Wallets"])
app.include_router(admin_auth.router, prefix="/api/admin/auth", tags=["Admin Auth"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])
app.include_router(promotions.router, prefix="/api/admin", tags=["Promotions Admin"])
app.include_router(applications.router, prefix="/api/applications", tags=["Applications"])


@app.get("/health", tags=["Health"])
async def health():
    return {"status": "ok", "app": "pickupoint", "version": "1.0.0"}
