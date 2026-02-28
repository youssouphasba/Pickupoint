import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from config import settings
from database import connect_db, close_db

# Routers
from routers import auth, users, relay_points, parcels, tracking, deliveries, pricing, wallets, admin, webhooks

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Rate limiter
limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await connect_db()
    logger.info("PickuPoint API started")
    yield
    # Shutdown
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

# Routers — avec auth
app.include_router(auth.router, prefix="/api/auth", tags=["Auth"])
app.include_router(users.router, prefix="/api/users", tags=["Users"])
app.include_router(relay_points.router, prefix="/api/relay-points", tags=["Relay Points"])
app.include_router(parcels.router, prefix="/api/parcels", tags=["Parcels"])
app.include_router(deliveries.router, prefix="/api/deliveries", tags=["Deliveries"])
app.include_router(pricing.router, prefix="/api/pricing", tags=["Pricing"])
app.include_router(wallets.router, prefix="/api/wallets", tags=["Wallets"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])


@app.get("/health", tags=["Health"])
async def health():
    return {"status": "ok", "app": "pickupoint", "version": "1.0.0"}
