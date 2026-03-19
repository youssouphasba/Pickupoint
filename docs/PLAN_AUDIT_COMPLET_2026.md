# PLAN DE CORRECTION COMPLET — Denkma/PickuPoint
> Audit du 2026-03-18 · 35 issues · 4 niveaux de priorité

---

## P0 — CRITIQUE (avant tout test avec vrais utilisateurs)

### C1. Secrets exposés dans le repo
- **Fichiers** : `.env` (racine) contient `MONGO_URL` avec mot de passe Atlas, `backend/.env` contient `WHATSAPP_ACCESS_TOKEN` réel
- **Action** :
  1. Révoquer/rotater le token WhatsApp sur Meta Dashboard
  2. Changer le mot de passe MongoDB Atlas
  3. S'assurer que `.env` est dans `.gitignore` (racine ET backend/)
  4. Nettoyer l'historique git avec `git filter-repo` ou BFG Cleaner
- **Statut** : [ ] À faire

### C2. Firebase service account JSON dans le repo
- **Fichier** : `denkma-e1246-firebase-adminsdk-fbsvc-08c771e1d1.json` (untracked mais présent)
- **Action** :
  1. Ajouter `*.json` sensibles au `.gitignore` : `firebase-*.json`, `*-adminsdk-*.json`, `google-services*.json`
  2. Stocker les credentials Firebase via variable d'env (`FIREBASE_CREDENTIALS_JSON` en base64)
  3. Ne jamais commit ce fichier
- **Statut** : [ ] À faire

### C3. JWT Secret par défaut faible
- **Fichier** : `backend/config.py:20`
- **Issue** : `JWT_SECRET = "changeme_minimum_32_chars_here_please"` utilisé si env var manquante
- **Action** :
  1. Générer un secret 64 chars aléatoire pour Railway
  2. Ajouter validation bloquante : si `APP_ENV=production` et secret = valeur par défaut → crash au démarrage
- **Statut** : [ ] À faire

### C4. OTP mock par défaut en production
- **Fichier** : `backend/config.py:28` — `OTP_PROVIDER: str = "mock"`
- **Issue** : Si Railway n'a pas `OTP_PROVIDER=firebase`, tout le monde peut login avec `123456`
- **Action** :
  1. Ajouter validation : si `APP_ENV=production` et `OTP_PROVIDER=mock` → crash au démarrage
  2. Vérifier que Railway a `OTP_PROVIDER=firebase`
  3. Ne plus retourner `test_code` dans la réponse API même en debug
- **Statut** : [ ] À faire

### C5. XSS dans tracking.py (HTML sans échappement)
- **Fichier** : `backend/routers/tracking.py:85-99`
- **Issue** : `evt.get('notes')` injecté dans HTML f-string sans `html.escape()`
- **Action** :
  1. `import html` en haut du fichier
  2. Échapper toutes les variables dynamiques : `html.escape(str(value))`
  3. Appliquer sur : notes, to_status, tracking_code, status, timestamps
- **Statut** : [ ] À faire

### C6. XSS dans confirm.py (HTML sans échappement)
- **Fichier** : `backend/routers/confirm.py:28-165`
- **Issue** : `recipient_name` injecté dans HTML sans échappement
- **Action** : Même correction que C5 — `html.escape()` sur toutes les variables dynamiques
- **Statut** : [ ] À faire

---

## P1 — HAUTE PRIORITÉ (avant la mise en production)

### H1. Webhook Flutterwave — comparaison timing-unsafe
- **Fichier** : `backend/routers/webhooks.py:30`
- **Issue** : `verif_hash != settings.FLUTTERWAVE_WEBHOOK_SECRET` vulnérable aux timing attacks
- **Action** : Remplacer par `hmac.compare_digest(verif_hash, settings.FLUTTERWAVE_WEBHOOK_SECRET)`
- **Statut** : [ ] À faire

### H2. Webhook — race condition double-crédit
- **Fichier** : `backend/routers/webhooks.py:70-107`
- **Issue** : Read-then-write non atomique → 2 webhooks simultanés = double crédit wallet
- **Action** :
  1. Utiliser `update_one` avec filtre `{"payment_status": {"$ne": "paid"}}` pour rendre atomique
  2. Ou utiliser MongoDB transactions multi-documents
- **Statut** : [ ] À faire

### H3. CORS trop ouvert en mode DEBUG
- **Fichier** : `backend/main.py:289-295`
- **Issue** : `allow_origins=["*"]` si `DEBUG=true`
- **Action** :
  1. Même en debug, limiter aux origines connues : `["http://localhost:3000", "http://localhost:8080"]`
  2. Ou s'assurer que DEBUG=false en production (lié à C4)
- **Statut** : [ ] À faire

### H4. Répertoire /uploads servi sans authentification
- **Fichier** : `backend/main.py:297-299`
- **Issue** : `StaticFiles(directory=UPLOADS_DIR)` → avatars et voice notes accessibles publiquement
- **Action** :
  1. Servir via un endpoint protégé avec vérification d'accès
  2. Ou ajouter des noms de fichiers non prédictibles (UUID complet)
- **Statut** : [ ] À faire

### H5. Codes PIN/livraison trop faibles (4 chiffres)
- **Fichier** : `backend/services/parcel_service.py:431-432`
- **Issue** : `relay_pin` et `delivery_code` = 4 chiffres (9000 possibilités)
- **Action** :
  1. Passer à 6 chiffres : `f"{random.randint(100000, 999999)}"`
  2. Ajouter rate limiting sur les endpoints de vérification PIN
  3. Ajouter lockout après 5 tentatives échouées
- **Statut** : [ ] À faire

### H6. Confirmation tokens trop courts
- **Fichier** : `backend/routers/confirm.py:277-279`
- **Issue** : `secrets.token_urlsafe(12)` = ~90 bits d'entropie
- **Action** : Passer à `secrets.token_urlsafe(32)` (256 bits)
- **Statut** : [ ] À faire

### H7. Regex injection dans recherche téléphone
- **Fichier** : `backend/routers/parcels.py:407-411`
- **Issue** : `{"$regex": f"{phone[-9:]}$"}` — caractères spéciaux regex non échappés
- **Action** : `import re` puis `re.escape(phone[-9:])` avant utilisation dans `$regex`
- **Statut** : [ ] À faire

### H8. Payout admin sans vérification de solde
- **Fichier** : `backend/routers/admin.py:216-246`
- **Issue** : `$inc: {"pending": -amount}` sans vérifier que `pending >= amount`
- **Action** : Ajouter filtre `{"pending": {"$gte": payout["amount"]}}` dans le `update_one`
- **Statut** : [ ] À faire

### H9. OTP debug code retourné dans la réponse API
- **Fichier** : `backend/services/otp_service.py:44-52`
- **Issue** : `"test_code": otp_code if settings.DEBUG else None` exposé dans la réponse
- **Action** : Ne jamais retourner le code OTP dans la réponse, même en debug (le logger suffit)
- **Statut** : [ ] À faire

---

## P2 — MOYENNE PRIORITÉ (sprint post-lancement)

### M1. Transactions wallet non atomiques
- **Fichier** : `backend/services/wallet_service.py:56-59, 93-96`
- **Issue** : Update balance + insert transaction = 2 ops séparées, crash entre les 2 = incohérence
- **Action** : Utiliser MongoDB client sessions avec `start_transaction()`
- **Statut** : [ ] À faire

### M2. Transitions parcel non atomiques
- **Fichier** : `backend/services/parcel_service.py:657-827`
- **Issue** : Update parcel + event + wallet + mission + notify = 5 ops séquentielles
- **Action** : Regrouper les ops critiques (parcel + event + wallet) dans une transaction
- **Statut** : [ ] À faire

### M3. Pas de validation GPS coordinates
- **Fichier** : `backend/routers/confirm.py:21-25`
- **Issue** : `lat` et `lng` acceptés sans vérification de plage
- **Action** : Ajouter `Field(..., ge=-90, le=90)` pour lat, `Field(..., ge=-180, le=180)` pour lng
- **Statut** : [ ] À faire

### M4. Pas de limite de taille sur upload avatar
- **Fichier** : `backend/routers/users.py:177-199`
- **Issue** : Fichier copié sans vérification de taille → DOS possible
- **Action** :
  1. Lire max 5 Mo, rejeter au-delà
  2. Valider les magic bytes (pas juste le Content-Type header)
  3. Rejeter SVG (vecteur XSS)
- **Statut** : [ ] À faire

### M5. Pas de rate limiting sur endpoints sensibles
- **Fichiers** : `users.py`, `admin.py`, `wallets.py`
- **Endpoints manquants** :
  - `POST /users/{id}/relay-point`
  - `POST /wallets/me/payout`
  - `POST /confirm/{token}/locate`
  - `POST /admin/users/{id}/ban`
  - `PUT /admin/wallets/payouts/{id}/approve`
  - `POST /users/me/avatar`
- **Action** : Ajouter `@limiter.limit("10/minute")` sur chaque endpoint sensible
- **Statut** : [ ] À faire

### M6. Pas de validation max_length sur champs texte
- **Fichiers** : `backend/routers/admin.py:108`, `backend/routers/users.py:118`
- **Issue** : `reason`, `notes`, `name` sans limite → strings de 1 Mo+ possibles
- **Action** : Ajouter `max_length=500` dans les modèles Pydantic concernés
- **Statut** : [ ] À faire

### M7. Pas de TTL index sur user_sessions
- **Fichier** : `backend/database.py:70-73`
- **Issue** : `expires_at` existe mais pas d'index TTL → tokens accumulés indéfiniment
- **Action** : Ajouter `create_index("expires_at", expireAfterSeconds=0)` sur `user_sessions`
- **Statut** : [ ] À faire

### M8. Pas de token revocation/blacklist
- **Fichier** : `backend/core/security.py`
- **Issue** : JWT valide 120 min, impossible à révoquer avant expiration
- **Action** :
  1. Créer collection `token_blacklist` avec TTL
  2. Vérifier blacklist dans `get_current_user`
  3. Ajouter endpoint `/auth/logout` qui blackliste le token
- **Statut** : [ ] À faire

### M9. Validation status admin non typée
- **Fichier** : `backend/routers/admin.py:59-71`
- **Issue** : `status` paramètre accepté sans validation enum → injection MongoDB possible
- **Action** : Valider contre `ParcelStatus` enum ou whitelist de valeurs autorisées
- **Statut** : [ ] À faire

### M10. Normalisation téléphone absente côté backend
- **Fichier** : `backend/routers/auth.py:72`
- **Issue** : `find_one({"phone": phone})` sans normalisation → `+221` vs `221` vs `00221`
- **Action** : Créer `normalize_phone()` backend (comme Flutter) et l'appliquer à tous les endpoints auth
- **Statut** : [ ] À faire

### M11. Identification destinataire par suffixe téléphone fragile
- **Fichier** : `backend/routers/parcels.py:440-484`
- **Issue** : `phone.endswith(current_user["phone"][-9:])` → collision possible entre 2 numéros
- **Action** : Utiliser uniquement `recipient_user_id` pour l'identification, pas le suffixe téléphone
- **Statut** : [ ] À faire

### M12. Content-Type upload : validation header seulement
- **Fichier** : `backend/routers/users.py:176-206`
- **Issue** : `file.content_type.startswith("image/")` — le header est contrôlé par le client
- **Action** : Valider les magic bytes du fichier (ex: `b'\x89PNG'`, `b'\xff\xd8\xff'` pour JPEG)
- **Statut** : [ ] À faire

---

## P3 — BASSE PRIORITÉ (amélioration continue)

### L1. Security headers manquants
- **Fichier** : `backend/main.py`
- **Issue** : Pas de CSP, HSTS, X-Frame-Options, X-Content-Type-Options
- **Action** : Ajouter middleware FastAPI avec headers de sécurité
- **Statut** : [ ] À faire

### L2. Webhook payload loggué en entier
- **Fichier** : `backend/routers/webhooks.py:38`
- **Issue** : `logger.info(f"payload: {payload}")` peut logger des données sensibles de paiement
- **Action** : Logger uniquement `tx_ref`, `status`, `amount` — pas le payload complet
- **Statut** : [ ] À faire

### L3. Dockerfile copie tout le repo
- **Fichier** : `backend/Dockerfile:15`
- **Issue** : `COPY . .` inclut `.env`, credentials JSON, etc.
- **Action** : Créer `.dockerignore` avec : `.env*`, `*.json` (credentials), `__pycache__`, `.git`
- **Statut** : [ ] À faire

### L4. Pas de rotation de secrets
- **Issue** : JWT_SECRET, WhatsApp token, etc. sans mécanisme de rotation
- **Action** : Documenter procédure de rotation + supporter multi-clés JWT temporairement
- **Statut** : [ ] À faire

### L5. Mission auto-release race condition
- **Fichier** : `backend/main.py:39-61`
- **Issue** : Job toutes les 2 min peut relâcher une mission juste acceptée (14:59 → 15:00)
- **Action** : Ajouter marge de 1 min ou vérifier `updated_at` récent
- **Statut** : [ ] À faire

### L6. Tracking code potentiellement énumérable
- **Fichier** : `backend/routers/tracking.py:16-42`
- **Issue** : 5 req/min = 288 tentatives/jour, codes de 7 chars
- **Action** : Augmenter longueur du code tracking ou ajouter CAPTCHA après N échecs
- **Statut** : [ ] À faire

### L7. Parsing tx_ref webhook fragile
- **Fichier** : `backend/routers/webhooks.py:50-54`
- **Issue** : `tx_ref.split("-")` → si parcel_id contient "-", parsing incorrect
- **Action** : Utiliser un format non ambigu : `PKP_parcelid_timestamp` ou stocker le mapping
- **Statut** : [ ] À faire

---

## RÉSUMÉ

| Priorité | Nombre | Description |
|----------|--------|-------------|
| **P0 — Critique** | 6 | Secrets, XSS, auth bypass |
| **P1 — Haute** | 9 | Webhooks, CORS, codes faibles, injections |
| **P2 — Moyenne** | 12 | Atomicité, validation, rate limiting |
| **P3 — Basse** | 7 | Headers, logging, Docker, ergonomie |
| **Total** | **34** | |

---

## ORDRE D'EXÉCUTION RECOMMANDÉ

1. **C1 + C2** — Secrets : révoquer tokens, nettoyer git, .gitignore
2. **C3 + C4** — Validations startup prod (JWT + OTP)
3. **C5 + C6** — XSS : html.escape() dans tracking + confirm
4. **H1 + H2** — Webhook sécurisé (timing-safe + atomique)
5. **H3 + H9** — CORS + debug OTP
6. **H5 + H6 + H7** — Codes plus forts + regex escape
7. **H4 + H8** — Uploads protégés + payout vérifié
8. **M1→M12** — Validations, atomicité, rate limiting
9. **L1→L7** — Hardening final
