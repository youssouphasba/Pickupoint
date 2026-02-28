# PickuPoint — Phase 1 MVP · Avancement

## Étape 1 — Fondations ✅
- [x] Arborescence complète (dossiers + `__init__.py`)
- [x] `requirements.txt`
- [x] `.env.example`
- [x] `backend/config.py`
- [x] `backend/database.py` (Motor + `create_indexes()`)
- [x] `backend/main.py` (app factory, CORS, rate limiter, lifespan, routers)

## Étape 2 — Modèles Pydantic ✅
- [x] `models/common.py` (GeoPin, Address, enums)
- [x] `models/user.py`
- [x] `models/relay_point.py`
- [x] `models/parcel.py` (+ ParcelEvent)
- [x] `models/delivery.py`
- [x] `models/pricing.py`
- [x] `models/wallet.py`
- [x] `models/notification.py`

## Étape 3 — Core ✅
- [x] `core/security.py` (JWT, bcrypt, OTP helpers, tracking code, HMAC QR)
- [x] `core/dependencies.py` (get_current_user, require_role)
- [x] `core/exceptions.py` (helpers HTTPException)

## Étape 4 — Services ✅
- [x] `services/otp_service.py`
- [x] `services/pricing_service.py`
- [x] `services/parcel_service.py` (machine d'états + event sourcing)
- [x] `services/wallet_service.py`
- [x] `services/notification_service.py`
- [x] `services/payment_service.py`

## Étape 5 — Routers ✅
- [x] `routers/auth.py`
- [x] `routers/users.py`
- [x] `routers/relay_points.py`
- [x] `routers/pricing.py`
- [x] `routers/parcels.py`
- [x] `routers/tracking.py`
- [x] `routers/deliveries.py`
- [x] `routers/wallets.py`
- [x] `routers/admin.py`
- [x] `routers/webhooks.py`

## Étape 6 — Docker & finalisation ✅
- [x] `backend/Dockerfile`
- [x] `docker-compose.yml`
- [ ] Test `uvicorn main:app --reload --port 8001`  ← à faire manuellement
- [ ] Vérifier `/docs` Swagger  ← à faire manuellement

---
> **Prochaine étape** : lancer `pip install -r requirements.txt` puis `uvicorn main:app --reload --port 8001` depuis `backend/`
