import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from config import settings
from database import connect_db, close_db

# Routers
from routers import auth, users, relay_points, parcels, tracking, deliveries, pricing, wallets, admin, webhooks, confirm, applications

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Rate limiter
limiter = Limiter(key_func=get_remote_address)


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
                await _db.delivery_missions.update_one(
                    {"mission_id": mission["mission_id"]},
                    {"$set": {
                        "status":      "pending",
                        "driver_id":   None,
                        "assigned_at": None,
                        "updated_at":  now,
                    }},
                )
                await _db.parcels.update_one(
                    {"parcel_id": mission["parcel_id"]},
                    {"$set": {"assigned_driver_id": None, "updated_at": now}},
                )
                released += 1
            if released:
                logger.info(f"Auto-release : {released} mission(s) libérée(s) après 15 min d'inactivité")
        except Exception as exc:
            logger.error(f"Erreur auto-release missions : {exc}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await connect_db()
    task = asyncio.create_task(_auto_release_stuck_missions())
    logger.info("PickuPoint API started")
    yield
    # Shutdown
    task.cancel()
    await close_db()
    logger.info("PickuPoint API stopped")


app = FastAPI(
    title="PickuPoint API",
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
    allow_origins=["*"] if settings.DEBUG else ["https://pickupoint.sn"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers — publics (sans auth)
app.include_router(tracking.router, prefix="/api/tracking", tags=["Tracking"])
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["Webhooks"])
app.include_router(confirm.router, prefix="/confirm", tags=["Confirmation GPS"])  # lien SMS/WhatsApp

# Routers — avec auth
app.include_router(auth.router, prefix="/api/auth", tags=["Auth"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(relay_points.router, prefix="/api/relay-points", tags=["Relay Points"])
app.include_router(parcels.router, prefix="/api/parcels", tags=["Parcels"])
app.include_router(deliveries.router, prefix="/api/deliveries", tags=["Deliveries"])
app.include_router(pricing.router, prefix="/api/pricing", tags=["Pricing"])
app.include_router(wallets.router, prefix="/api/wallets", tags=["Wallets"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])
app.include_router(applications.router, prefix="/api/applications", tags=["Applications"])


@app.get("/health", tags=["Health"])
async def health():
    return {"status": "ok", "app": "pickupoint", "version": "1.0.0"}
