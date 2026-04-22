# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

**Denkma** (anciennement PickuPoint) — plateforme de livraison et points relais pour le Sénégal. Monorepo avec 4 applications :

| Dossier | Rôle | Stack |
|---|---|---|
| `backend/` | API REST | FastAPI + Motor (MongoDB async) + Pydantic V2 |
| `mobile/` | App client/driver/relais/admin | Flutter + Riverpod + go_router + Dio |
| `admin-dashboard/` | Console web admin | Next.js 14 + TanStack Query/Table + Tailwind + Radix UI |
| `landing/` | Site vitrine + pages légales | HTML statique |

Prod : `https://api.denkma.com` (Railway + MongoDB Atlas), `https://admin.denkma.com` (Cloudflare Pages), `https://denkma.com` (landing).

## Commandes

### Backend (FastAPI)
```bash
# Dev local (depuis la racine — docker-compose fournit aussi Mongo)
docker-compose up

# Ou en local sans Docker (depuis backend/)
cd backend && uvicorn main:app --reload --port 8001

# Tests ad-hoc (scripts standalone, pas de pytest configuré)
python backend/test_security_fixes.py
python backend/test_transition.py
```
Important : le `Dockerfile` Railway est **à la racine** (pas dans `backend/`). Il `COPY backend/` dans `/app`.

### Mobile (Flutter)
```bash
cd mobile

# Dev contre API locale (10.0.2.2 = host depuis émulateur Android)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001

# Sans API_BASE_URL → pointe automatiquement sur api.denkma.com
flutter run

# Push désactivé tant que Firebase n'est pas branché
flutter run --dart-define=ENABLE_PUSH_NOTIFICATIONS=false

# Build APK release
flutter build apk --release
```

### Admin dashboard (Next.js)
```bash
cd admin-dashboard
npm run dev        # port 3100
npm run typecheck  # tsc --noEmit
npm run lint
npm run build
npm run pages:build  # build Cloudflare Pages
```

## Architecture

### Backend — assemblage
- `main.py` enregistre tous les routers et déclare **3 tâches asynchrones de fond** + un `AsyncIOScheduler` :
  - `_auto_release_stuck_missions` (toutes les 2 min) libère les missions `ASSIGNED` depuis >15 min sans collecte confirmée
  - `_advance_delivery_dispatch_loop` (toutes les 15 s) fait avancer le dispatch en cascade
  - `_gps_confirmation_reminder_loop` (toutes les 2 min) envoie relances SMS/WhatsApp pour confirmations GPS
  - `_monthly_ranking_job` (cron, 1er du mois 01:00 UTC) calcule classements + paye bonus drivers/relais
  - `_expire_stale_parcels` (toutes les heures) expire colis `AVAILABLE_AT_RELAY` / `REDIRECTED_TO_RELAY`
- Toute modification de ces boucles doit rester **idempotente** (race conditions possibles) — voir le pattern `update_one({...filtres stricts...})` dans `_auto_release_stuck_missions`.
- Event sourcing : chaque transition de colis génère un événement immutable via `services.parcel_service._record_event` dans `parcel_events`. **Ne pas contourner** `parcel_service` pour muter un statut.

### Machine d'états colis
```
CREATED → DROPPED_AT_ORIGIN_RELAY → IN_TRANSIT → AT_DESTINATION_RELAY → AVAILABLE_AT_RELAY → DELIVERED
       → OUT_FOR_DELIVERY (H2H/H2R/R2H) → DELIVERED | DELIVERY_FAILED → REDIRECTED_TO_RELAY
```
Terminaux : `DELIVERED`, `CANCELLED`, `EXPIRED`, `DISPUTED`, `RETURNED`. Toute la logique vit dans `services/parcel_service.py`.

### 4 modes de livraison + pricing
Les modes `relay_to_relay`, `relay_to_home`, `home_to_relay`, `home_to_home` ont chacun leur base tarifaire, commissions driver/relais et gagnants (`services/wallet_service.distribute_delivery_revenue`). Les constantes (`BASE_*`, `PRICE_PER_KM`, `PRICE_PER_KG`, coefficients) sont dans `backend/config.py`. Calcul final dans `services/pricing_service.py` : Haversine + coefficient dynamique 0.80–2.00 (heure/jour/zone) + multiplicateur express ×1.40 + arrondi au multiple de 50 XOF supérieur.

### Auth — double mécanisme
- **Mobile** : téléphone + OTP (Firebase Phone Auth côté mobile, aucun provider backend). En `DEBUG=True` le code est fixe `123456`. Voir `routers/auth.py`.
- **Admin dashboard** : email + password → JWT Bearer dans `localStorage` (`routers/admin_auth.py`). Les cookies cross-origin ne fonctionnent **pas** en dev localhost entre `:3100` et `:8001` ; on passe toujours par `Authorization: Bearer`.
- Token JWT stocké côté mobile dans `flutter_secure_storage` ; intercepté par `mobile/lib/core/api/api_client.dart` (Dio).

### Rôles & workflow d'onboarding
- **Client** = rôle par défaut à l'inscription OTP. Tout le monde s'inscrit comme client.
- **Driver / Relay Agent** = l'admin doit manuellement changer le rôle via `PUT /api/admin/users/{id}/role` (ou le dashboard).
- **Admin** = créé directement en base MongoDB (une fois au départ).
- Lier un relay_agent à son point : `PUT /api/users/{id}/relay-point?relay_id=xxx`.

### Backend ↔ Flutter — conventions de nommage
Le backend émet du snake_case avec des IDs préfixés ; le mobile parse en camelCase. **Respecter ces mappings dans tout nouveau code** :

| Backend | Flutter |
|---|---|
| `parcel_id`, `relay_id`, `wallet_id`, `tx_id`, `owner_id` | `id`, `id`, `id`, `id`, `userId` |
| `sender_user_id`, `is_insured`, `quoted_price` | `senderId`, `hasInsurance`, `totalPrice` |
| `max_capacity`, `current_load` | `capacity`, `currentStock` |
| `pending` (wallet), `tx_type` | `pendingBalance`, `type` |
| `is_recipient` (calculé backend, **ne pas recalculer côté client**) | `isRecipientView` |

Les endpoints liste retournent toujours un objet enveloppé : `{"parcels": [...]}`, `{"missions": [...]}`, `{"transactions": [...]}`. Les providers Riverpod extraient la clé nommée (**jamais `items`**).

### Mobile — organisation
- `core/api/` : Dio client + constantes d'endpoints (`api_endpoints.dart` utilise `String.fromEnvironment('API_BASE_URL')`)
- `core/router/app_router.dart` : routing conditionnel par rôle (go_router)
- `features/{client,driver,relay,admin,auth}/screens/` : un dossier par rôle
- `shared/utils/phone_utils.dart` : `normalizePhone()` convertit tous les numéros sénégalais en E.164 — **toujours** l'appeler avant un appel API.

### Admin dashboard
- Pages dynamiques sous `app/dashboard/*` — certaines forcent `export const runtime = 'edge'` pour Cloudflare Pages. Ne pas retirer sans raison.
- Appels API centralisés dans `lib/api.ts` (axios + interceptor Bearer).
- Middleware `middleware.ts` protège les routes `/dashboard/*`.

## Environnement
Le fichier `.env.example` à la racine liste toutes les variables (Mongo, JWT, WhatsApp Cloud API, Flutterwave, pricing). Copier vers `.env` pour docker-compose. Jamais commiter `.env` ni les JSON Firebase (`denkma-e1246-firebase-adminsdk-*.json`, `google-services*.json`, `GoogleService-Info.plist`).

## Pièges connus
- **Git CRLF** : `git status` affiche beaucoup de fichiers comme modifiés à cause des fins de ligne Windows/WSL. Utiliser `git diff -w` pour voir les **vraies** modifications.
- **Flutter `dispose()`** : uniquement sur `State<>` / `ConsumerState<>`, **jamais** sur `ConsumerWidget` (compile mais ne s'exécute pas).
- **Route légale côté mobile** : `/legal/privacy` (pas `/legal/privacy_policy`).
- **Manifest merger Android** : en cas d'erreur au build, vérifier les conflits `tools:replace` dans `mobile/android/app/src/main/AndroidManifest.xml`.
- **Railway healthcheck** : doit taper `/health` (déjà exposé dans `main.py`). Le Dockerfile est à la racine, pas dans `backend/`.
- **Comptes de test** (DEBUG=True, OTP fixe `123456`) : admin `+221770000000`, driver `+221770000001`, relay A `+221770000002`, client expéditeur `+221770000003`, destinataire `+221770000004`, relay B `+221770000005`.

## Documentation projet
- `docs/BUSINESS_PLAN_DENKMA_2026.md` — contexte produit
- `docs/PLAN_AUDIT_COMPLET_2026.md` + `_REVISE.md` — plan d'audit sécurité/qualité (34 items P0→P3)
- `docs/LEGAL_CGU_CGV.md` + `LEGAL_PRIVACY_POLICY.md` — textes juridiques sources
- `mobile/PLAN_FLUTTER.md` — roadmap mobile
- `PLAN_RECOMPENSES_PROMOTIONS.md`, `PLAN_TRACKING_SECURITE.md` — plans spécifiques à la racine
