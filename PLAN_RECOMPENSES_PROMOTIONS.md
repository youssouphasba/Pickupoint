# Plan d'implémentation — Récompenses, Classements & Promotions

> Document autonome. Un développeur peut l'implémenter sans autre contexte.
> Ordre d'implémentation : Backend modèles → Backend services/routers → Flutter modèles → Flutter écrans.

---

## Contexte technique

- **Backend** : FastAPI + MongoDB (Motor async) + Pydantic V2
- **Frontend** : Flutter (Riverpod + go_router)
- **Répertoire** : `/mnt/c/Users/Utilisateur/pickupoint/`
- **Backend prod** : `https://pickupoint-production.up.railway.app`
- **Devise** : XOF (CFA Sénégal)

---

## Vue d'ensemble

| Bloc | Description |
|---|---|
| **A** | Fidélité clients (points, parrainage, expéditeur fréquent) |
| **B** | Récompenses livreurs (performance, volume, notation) |
| **C** | Récompenses relais (rotation, volume, ponctualité) |
| **D** | Classements livreurs (mensuel, masqué pour pairs, complet pour admin) |
| **E** | Offres promotionnelles admin (réductions, gratuité, codes, ciblage) |

---

## Nouveaux endpoints (résumé)

```
# Fidélité
GET  /api/users/me/loyalty              → points + historique
POST /api/users/refer                   → créer lien parrainage
POST /api/users/apply-referral          → appliquer un code parrainage

# Classements
GET  /api/deliveries/rankings           → top livreurs (driver: masqué | admin: complet)
GET  /api/deliveries/rankings/me        → mon rang + mes stats

# Promotions (admin)
POST   /api/admin/promotions            → créer une offre
GET    /api/admin/promotions            → liste toutes les offres
PUT    /api/admin/promotions/{id}       → modifier / activer / désactiver
DELETE /api/admin/promotions/{id}       → supprimer

# Promotions (client)
POST /api/parcels/check-promo           → vérifier un code promo (retourne réduction)
# (la promo est appliquée automatiquement dans /quote si aucun code manual)
```

---

## BLOC A — Fidélité Clients

### Principe

```
1 colis livré = +10 points
Paliers :
  Bronze  (0–499 pts)   → pas de réduction
  Argent  (500–1499 pts) → -5% sur tarif de base
  Or      (1500+ pts)    → -10% sur tarif de base

Parrainage :
  Client crée son code unique → partage → filleul crée 1er colis → 500 XOF crédités à chacun

Expéditeur fréquent :
  ≥ 10 colis dans les 30 derniers jours → coeff dynamique 0.90 appliqué automatiquement au quote
```

---

### A1 — Backend : champs User

**Fichier** : `backend/models/user.py`

Ajouter dans la classe `User` :
```python
loyalty_points:    int  = 0
loyalty_tier:      str  = "bronze"   # "bronze" | "silver" | "gold"
referral_code:     str  = ""         # code unique généré à l'inscription
referred_by:       Optional[str] = None  # user_id du parrain
referral_credited: bool = False       # évite double crédit
```

---

### A2 — Backend : génération du code parrainage

**Fichier** : `backend/services/user_service.py` (créer si absent)

```python
import random, string

def _generate_referral_code(name: str) -> str:
    """Ex: DAOUDA-4F2K"""
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    prefix = name[:6].upper().replace(" ", "")
    return f"{prefix}-{suffix}"

def _compute_tier(points: int) -> str:
    if points >= 1500: return "gold"
    if points >= 500:  return "silver"
    return "bronze"

def _tier_discount(tier: str) -> float:
    """Retourne le coefficient de réduction (1.0 = pas de réduction)."""
    return {"bronze": 1.0, "silver": 0.95, "gold": 0.90}.get(tier, 1.0)
```

À l'inscription (`POST /api/auth/verify-otp`), générer le `referral_code` et le stocker :
```python
referral_code = _generate_referral_code(user_name)
await db.users.update_one(
    {"user_id": user_id},
    {"$set": {"referral_code": referral_code, "loyalty_points": 0, "loyalty_tier": "bronze"}}
)
```

---

### A3 — Backend : créditer les points après livraison

**Fichier** : `backend/services/parcel_service.py`

Dans la fonction qui gère la transition `DELIVERED` (fin de `_handle_delivered` ou équivalent), ajouter :

```python
POINTS_PER_DELIVERY = 10

async def _credit_loyalty_points(db, sender_user_id: str):
    result = await db.users.find_one_and_update(
        {"user_id": sender_user_id},
        {"$inc": {"loyalty_points": POINTS_PER_DELIVERY}},
        return_document=True,
    )
    new_points = result.get("loyalty_points", 0)
    new_tier   = _compute_tier(new_points)
    if result.get("loyalty_tier") != new_tier:
        await db.users.update_one(
            {"user_id": sender_user_id},
            {"$set": {"loyalty_tier": new_tier}},
        )
    # Enregistrer dans l'historique
    await db.loyalty_events.insert_one({
        "event_id":   f"loy_{uuid4().hex[:12]}",
        "user_id":    sender_user_id,
        "type":       "delivery_completed",
        "points":     POINTS_PER_DELIVERY,
        "balance":    new_points,
        "created_at": datetime.now(timezone.utc),
    })
```

---

### A4 — Backend : endpoint parrainage

**Fichier** : `backend/routers/users.py`

```python
@router.post("/refer")
async def get_my_referral(current_user: dict = Depends(get_current_user)):
    """Retourne le code parrainage de l'utilisateur connecté."""
    return {
        "referral_code": current_user.get("referral_code", ""),
        "referral_url":  f"https://pickupoint.sn/join?ref={current_user.get('referral_code', '')}"
    }


@router.post("/apply-referral")
async def apply_referral(
    body: dict,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    """
    Appliquer un code parrainage.
    Conditions : utilisateur sans parrain + pas encore crédité.
    """
    code = body.get("referral_code", "").upper().strip()
    if not code:
        raise HTTPException(400, "Code manquant")

    # Vérifier que l'utilisateur n'a pas déjà un parrain
    if current_user.get("referred_by"):
        raise HTTPException(400, "Vous avez déjà utilisé un code parrainage")

    # Trouver le parrain
    parrain = await db.users.find_one({"referral_code": code})
    if not parrain:
        raise HTTPException(404, "Code parrainage invalide")
    if parrain["user_id"] == current_user["user_id"]:
        raise HTTPException(400, "Vous ne pouvez pas utiliser votre propre code")

    # Lier le filleul au parrain
    await db.users.update_one(
        {"user_id": current_user["user_id"]},
        {"$set": {"referred_by": parrain["user_id"]}}
    )
    return {"message": "Code enregistré. Le crédit sera versé après votre première livraison."}
```

---

### A5 — Backend : crédit parrainage après 1ère livraison

Dans `_credit_loyalty_points` (A3), après avoir crédité les points, ajouter :

```python
REFERRAL_BONUS_XOF = 500

# Vérifier si c'est la 1ère livraison ET si un parrain existe
user_full = await db.users.find_one({"user_id": sender_user_id})
is_first   = await db.parcels.count_documents(
    {"sender_user_id": sender_user_id, "status": "delivered"}
) == 1   # vient juste d'être livré, donc count = 1

if is_first and user_full.get("referred_by") and not user_full.get("referral_credited"):
    parrain_id = user_full["referred_by"]
    now = datetime.now(timezone.utc)

    # Crédit filleul
    await db.wallets.update_one(
        {"user_id": sender_user_id},
        {"$inc": {"balance": REFERRAL_BONUS_XOF}},
        upsert=True,
    )
    await db.wallet_transactions.insert_one({
        "tx_id": f"tx_{uuid4().hex[:12]}", "user_id": sender_user_id,
        "type": "referral_bonus", "amount": REFERRAL_BONUS_XOF,
        "description": "Bonus parrainage — 1ère livraison", "created_at": now,
    })

    # Crédit parrain
    await db.wallets.update_one(
        {"user_id": parrain_id},
        {"$inc": {"balance": REFERRAL_BONUS_XOF}},
        upsert=True,
    )
    await db.wallet_transactions.insert_one({
        "tx_id": f"tx_{uuid4().hex[:12]}", "user_id": parrain_id,
        "type": "referral_bonus", "amount": REFERRAL_BONUS_XOF,
        "description": f"Bonus parrainage — filleul livré", "created_at": now,
    })

    # Marquer comme crédité
    await db.users.update_one(
        {"user_id": sender_user_id},
        {"$set": {"referral_credited": True}}
    )
```

---

### A6 — Backend : réduction fidélité au quote

**Fichier** : `backend/services/pricing_service.py`

Dans `compute_quote()`, ajouter un paramètre `sender_tier: str = "bronze"` et appliquer avant l'arrondi :

```python
# Réduction fidélité (après toutes les autres majorations)
tier_coeff = {"bronze": 1.0, "silver": 0.95, "gold": 0.90}.get(sender_tier, 1.0)
price = price * tier_coeff

# Arrondi final
price = round_to_50(price)
```

Dans `routers/parcels.py` (`POST /quote`), récupérer le tier de l'utilisateur et le passer :
```python
sender = await db.users.find_one({"user_id": current_user["user_id"]})
sender_tier = sender.get("loyalty_tier", "bronze")
quote = await compute_quote(..., sender_tier=sender_tier)
```

---

### A7 — Backend : expéditeur fréquent

Dans `routers/parcels.py`, avant `compute_quote`, compter les colis du mois :

```python
from datetime import datetime, timezone, timedelta

month_ago = datetime.now(timezone.utc) - timedelta(days=30)
recent_count = await db.parcels.count_documents({
    "sender_user_id": current_user["user_id"],
    "status": "delivered",
    "created_at": {"$gte": month_ago},
})
is_frequent = recent_count >= 10
# Passer is_frequent à compute_quote → coeff *= 0.90 si True (cumulable avec tier)
```

---

### A8 — Endpoint loyalty

```python
@router.get("/me/loyalty")
async def get_loyalty(current_user: dict = Depends(get_current_user), db=Depends(get_db)):
    events = await db.loyalty_events.find(
        {"user_id": current_user["user_id"]},
        sort=[("created_at", -1)], limit=20
    ).to_list(20)

    return {
        "points":   current_user.get("loyalty_points", 0),
        "tier":     current_user.get("loyalty_tier", "bronze"),
        "next_tier_at": 500 if current_user.get("loyalty_tier") == "bronze" else 1500,
        "referral_code": current_user.get("referral_code", ""),
        "history":  events,
    }
```

---

## BLOC B — Récompenses Livreurs

### Principe

```
Taux de succès ≥ 95% sur 30 jours + ≥ 20 missions → bonus 5 000 XOF/mois (versé le 1er)
Volume mensuel :
  ≥ 50 courses  → +2 500 XOF
  ≥ 100 courses → +5 000 XOF
  ≥ 200 courses → +10 000 XOF
Note client ≥ 4.5/5 sur le mois → +1 000 XOF
```

### B1 — Modèle DriverStats (collection MongoDB)

Collection : `driver_stats`

```json
{
  "stat_id":           "stat_abc123",
  "driver_id":         "user_xxx",
  "period":            "2026-03",
  "deliveries_total":  87,
  "deliveries_success":83,
  "deliveries_failed": 4,
  "success_rate":      95.4,
  "avg_rating":        4.6,
  "total_earned_xof":  142500,
  "bonus_paid_xof":    7500,
  "rank":              3,
  "badge":             "silver",
  "created_at":        "2026-03-01T00:00:00Z",
  "updated_at":        "2026-03-15T10:00:00Z"
}
```

---

### B2 — Service calcul stats mensuel

**Fichier** : `backend/services/ranking_service.py` (créer)

```python
from datetime import datetime, timezone
from calendar import monthrange
from uuid import uuid4
from typing import Optional

async def compute_driver_stats_for_period(db, period: str) -> list[dict]:
    """
    period = "2026-03"
    Calcule les stats de tous les drivers pour une période donnée.
    Appelé par un cron le 1er du mois ou manuellement par l'admin.
    """
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end   = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    # Agréger par driver
    pipeline = [
        {"$match": {
            "assigned_at": {"$gte": start, "$lte": end},
            "status": {"$in": ["completed", "failed"]},
        }},
        {"$group": {
            "_id": "$driver_id",
            "total":   {"$sum": 1},
            "success": {"$sum": {"$cond": [{"$eq": ["$status", "completed"]}, 1, 0]}},
            "failed":  {"$sum": {"$cond": [{"$eq": ["$status", "failed"]}, 1, 0]}},
            "earned":  {"$sum": "$earn_amount"},
        }},
    ]
    results = await db.delivery_missions.aggregate(pipeline).to_list(None)

    # Récupérer les notes moyennes (depuis parcel_events ou collection ratings si elle existe)
    # Pour l'instant : avg_rating = 0.0 (à connecter quand notation client implémentée)

    stats_list = []
    for r in results:
        driver_id = r["_id"]
        if not driver_id:
            continue
        total   = r["total"]
        success = r["success"]
        rate    = round(success / total * 100, 1) if total > 0 else 0.0

        stat = {
            "stat_id":            f"stat_{uuid4().hex[:12]}",
            "driver_id":          driver_id,
            "period":             period,
            "deliveries_total":   total,
            "deliveries_success": success,
            "deliveries_failed":  r["failed"],
            "success_rate":       rate,
            "avg_rating":         0.0,   # à remplir quand ratings implémenté
            "total_earned_xof":   r["earned"],
            "bonus_paid_xof":     0,
            "rank":               0,     # calculé après tri
            "badge":              "none",
            "created_at":         datetime.now(timezone.utc),
            "updated_at":         datetime.now(timezone.utc),
        }
        stats_list.append(stat)

    # Trier par success_rate desc, puis total desc
    stats_list.sort(key=lambda x: (-x["success_rate"], -x["deliveries_total"]))

    # Attribuer rang + badge
    for i, stat in enumerate(stats_list):
        stat["rank"] = i + 1
        stat["badge"] = "gold" if i == 0 else "silver" if i == 1 else "bronze" if i == 2 else "none"

    return stats_list


async def pay_monthly_bonuses(db, period: str):
    """
    Verse les bonus mensuel en wallet.
    Appeler après compute_driver_stats_for_period().
    """
    from datetime import datetime, timezone
    stats = await db.driver_stats.find({"period": period}).to_list(None)

    for stat in stats:
        bonus = 0
        driver_id = stat["driver_id"]
        total     = stat["deliveries_total"]
        rate      = stat["success_rate"]

        # Bonus taux de succès
        if rate >= 95 and total >= 20:
            bonus += 5000

        # Bonus volume
        if total >= 200:
            bonus += 10000
        elif total >= 100:
            bonus += 5000
        elif total >= 50:
            bonus += 2500

        # Bonus note (quand rating disponible)
        if stat.get("avg_rating", 0) >= 4.5:
            bonus += 1000

        if bonus > 0:
            now = datetime.now(timezone.utc)
            await db.wallets.update_one(
                {"user_id": driver_id},
                {"$inc": {"balance": bonus}},
                upsert=True,
            )
            from uuid import uuid4
            await db.wallet_transactions.insert_one({
                "tx_id":       f"tx_{uuid4().hex[:12]}",
                "user_id":     driver_id,
                "type":        "monthly_bonus",
                "amount":      bonus,
                "description": f"Bonus performance — {period}",
                "created_at":  now,
            })
            await db.driver_stats.update_one(
                {"stat_id": stat["stat_id"]},
                {"$set": {"bonus_paid_xof": bonus}},
            )
```

---

### B3 — Endpoint classement

**Fichier** : `backend/routers/deliveries.py`

```python
@router.get("/rankings")
async def get_rankings(
    period: str = Query(default="", description="Format YYYY-MM. Vide = mois en cours"),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    from datetime import datetime, timezone
    if not period:
        now = datetime.now(timezone.utc)
        period = f"{now.year}-{now.month:02d}"

    is_admin = current_user.get("role") == "admin"
    is_driver = current_user.get("role") == "driver"

    if not (is_admin or is_driver):
        raise HTTPException(403, "Accès réservé aux livreurs et administrateurs")

    stats = await db.driver_stats.find(
        {"period": period},
        sort=[("rank", 1)],
        limit=50,
    ).to_list(50)

    result = []
    for s in stats:
        is_me = s["driver_id"] == current_user["user_id"]

        if is_admin or is_me:
            # Nom complet + gains visibles
            driver = await db.users.find_one({"user_id": s["driver_id"]})
            display_name = driver.get("full_name", "Livreur") if driver else "Livreur"
            total_earned = s.get("total_earned_xof", 0)
            bonus        = s.get("bonus_paid_xof", 0)
        else:
            # Nom masqué pour les autres livreurs
            display_name = f"Livreur #{s['rank']}"
            total_earned = None
            bonus        = None

        result.append({
            "rank":              s["rank"],
            "driver_id":         s["driver_id"] if is_admin else None,
            "display_name":      display_name,
            "badge":             s["badge"],
            "deliveries_total":  s["deliveries_total"],
            "success_rate":      s["success_rate"],
            "avg_rating":        s["avg_rating"],
            "total_earned_xof":  total_earned,
            "bonus_paid_xof":    bonus,
            "is_me":             is_me,
        })

    return {"period": period, "rankings": result}


@router.get("/rankings/me")
async def get_my_ranking(
    period: str = Query(default=""),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.get("role") != "driver":
        raise HTTPException(403, "Réservé aux livreurs")
    from datetime import datetime, timezone
    if not period:
        now = datetime.now(timezone.utc)
        period = f"{now.year}-{now.month:02d}"

    stat = await db.driver_stats.find_one({
        "driver_id": current_user["user_id"],
        "period": period,
    })
    if not stat:
        return {"period": period, "rank": None, "message": "Pas encore de stats pour cette période"}

    return {
        "period":            period,
        "rank":              stat["rank"],
        "badge":             stat["badge"],
        "deliveries_total":  stat["deliveries_total"],
        "deliveries_success":stat["deliveries_success"],
        "success_rate":      stat["success_rate"],
        "avg_rating":        stat["avg_rating"],
        "total_earned_xof":  stat["total_earned_xof"],
        "bonus_paid_xof":    stat["bonus_paid_xof"],
    }
```

---

### B4 — Cron mensuel (calcul + paiement)

**Fichier** : `backend/main.py`

Ajouter au startup (utilise `apscheduler` ou `asyncio` selon ce qui est en place) :

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from services.ranking_service import compute_driver_stats_for_period, pay_monthly_bonuses
from datetime import datetime, timezone

scheduler = AsyncIOScheduler()

async def monthly_ranking_job():
    """Tourne le 1er de chaque mois à 01:00 UTC."""
    now = datetime.now(timezone.utc)
    # Calculer pour le mois précédent
    if now.month == 1:
        period = f"{now.year - 1}-12"
    else:
        period = f"{now.year}-{now.month - 1:02d}"

    db = get_database()  # adapter selon votre pattern
    stats = await compute_driver_stats_for_period(db, period)

    # Upsert les stats
    for stat in stats:
        await db.driver_stats.update_one(
            {"driver_id": stat["driver_id"], "period": period},
            {"$set": stat},
            upsert=True,
        )
    await pay_monthly_bonuses(db, period)

scheduler.add_job(monthly_ranking_job, "cron", day=1, hour=1, minute=0)

@app.on_event("startup")
async def startup():
    scheduler.start()

@app.on_event("shutdown")
async def shutdown():
    scheduler.stop()
```

Ajouter dans `requirements.txt` :
```
apscheduler==3.10.4
```

---

### B5 — Endpoint admin : déclencher manuellement

```python
# Dans routers/admin.py ou routers/deliveries.py

@router.post("/admin/rankings/compute")
async def compute_rankings_now(
    period: str = Query(..., description="Format YYYY-MM"),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.get("role") != "admin":
        raise HTTPException(403, "Admin seulement")
    from services.ranking_service import compute_driver_stats_for_period, pay_monthly_bonuses
    stats = await compute_driver_stats_for_period(db, period)
    for stat in stats:
        await db.driver_stats.update_one(
            {"driver_id": stat["driver_id"], "period": period},
            {"$set": stat}, upsert=True,
        )
    return {"period": period, "drivers_computed": len(stats)}


@router.post("/admin/rankings/pay-bonuses")
async def pay_bonuses_now(
    period: str = Query(...),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.get("role") != "admin":
        raise HTTPException(403, "Admin seulement")
    from services.ranking_service import pay_monthly_bonuses
    await pay_monthly_bonuses(db, period)
    return {"message": f"Bonus versés pour {period}"}
```

---

## BLOC C — Récompenses Relais

### Principe

```
Volume mensuel ≥ 50 colis traités → commission passe de 7.5% à 10% (relay_to_relay)
Volume mensuel ≥ 50 colis traités → commission passe de 15% à 18% (relay_to_home / home_to_relay)
Zéro retard (aucun colis > 7 jours en stock) → bonus 2 000 XOF/mois
Rotation rapide (tous les colis remis < 3 jours en moyenne) → bonus 1 000 XOF/mois
```

### C1 — Service stats relais

**Fichier** : `backend/services/ranking_service.py` (ajouter)

```python
async def compute_relay_stats_for_period(db, period: str):
    year, month = map(int, period.split("-"))
    start = datetime(year, month, 1, tzinfo=timezone.utc)
    _, last_day = monthrange(year, month)
    end = datetime(year, month, last_day, 23, 59, 59, tzinfo=timezone.utc)

    relays = await db.relay_points.find({"is_active": True}).to_list(None)
    for relay in relays:
        relay_id = relay["relay_id"]

        # Colis traités = reçus dans la période
        arrived = await db.parcels.count_documents({
            "$or": [
                {"origin_relay_id": relay_id},
                {"destination_relay_id": relay_id},
                {"redirect_relay_id": relay_id},
            ],
            "created_at": {"$gte": start, "$lte": end},
        })

        # Colis en retard (> 7 jours en stock actuellement)
        week_ago = datetime.now(timezone.utc) - timedelta(days=7)
        overdue = await db.parcels.count_documents({
            "$or": [
                {"destination_relay_id": relay_id},
                {"redirect_relay_id": relay_id},
            ],
            "status": {"$in": ["available_at_relay", "redirected_to_relay"]},
            "updated_at": {"$lt": week_ago},
        })

        bonus = 0
        if arrived >= 50 and overdue == 0:
            bonus += 2000
        if overdue == 0 and arrived > 0:
            bonus += 1000

        if bonus > 0:
            now = datetime.now(timezone.utc)
            await db.wallets.update_one(
                {"user_id": relay["owner_user_id"]},
                {"$inc": {"balance": bonus}},
                upsert=True,
            )
            await db.wallet_transactions.insert_one({
                "tx_id":       f"tx_{uuid4().hex[:12]}",
                "user_id":     relay["owner_user_id"],
                "type":        "relay_bonus",
                "amount":      bonus,
                "description": f"Bonus relais — {period} ({arrived} colis traités)",
                "created_at":  now,
            })
```

Ajouter l'appel dans `monthly_ranking_job` :
```python
await compute_relay_stats_for_period(db, period)
```

---

## BLOC D — Classements Livreurs (Flutter)

### D1 — Modèle Flutter

**Fichier** : `mobile/lib/core/models/driver_ranking.dart` (créer)

```dart
class DriverRanking {
  const DriverRanking({
    required this.rank,
    required this.displayName,
    required this.badge,
    required this.deliveriesTotal,
    required this.successRate,
    required this.avgRating,
    required this.isMe,
    this.driverId,
    this.totalEarnedXof,
    this.bonusPaidXof,
  });

  final int     rank;
  final String  displayName;
  final String  badge;        // "gold" | "silver" | "bronze" | "none"
  final int     deliveriesTotal;
  final double  successRate;
  final double  avgRating;
  final bool    isMe;
  final String? driverId;
  final double? totalEarnedXof;
  final double? bonusPaidXof;

  factory DriverRanking.fromJson(Map<String, dynamic> j) => DriverRanking(
        rank:            j['rank'] as int,
        displayName:     j['display_name'] as String,
        badge:           j['badge'] as String,
        deliveriesTotal: j['deliveries_total'] as int,
        successRate:     (j['success_rate'] as num).toDouble(),
        avgRating:       (j['avg_rating'] as num).toDouble(),
        isMe:            j['is_me'] as bool? ?? false,
        driverId:        j['driver_id'] as String?,
        totalEarnedXof:  (j['total_earned_xof'] as num?)?.toDouble(),
        bonusPaidXof:    (j['bonus_paid_xof'] as num?)?.toDouble(),
      );
}

class MyRanking {
  const MyRanking({
    required this.period,
    required this.rank,
    required this.badge,
    required this.deliveriesTotal,
    required this.deliveriesSuccess,
    required this.successRate,
    required this.avgRating,
    required this.totalEarnedXof,
    required this.bonusPaidXof,
  });

  final String period;
  final int    rank;
  final String badge;
  final int    deliveriesTotal;
  final int    deliveriesSuccess;
  final double successRate;
  final double avgRating;
  final double totalEarnedXof;
  final double bonusPaidXof;

  factory MyRanking.fromJson(Map<String, dynamic> j) => MyRanking(
        period:           j['period'] as String,
        rank:             j['rank'] as int? ?? 0,
        badge:            j['badge'] as String? ?? 'none',
        deliveriesTotal:  j['deliveries_total'] as int? ?? 0,
        deliveriesSuccess:j['deliveries_success'] as int? ?? 0,
        successRate:      (j['success_rate'] as num?)?.toDouble() ?? 0,
        avgRating:        (j['avg_rating'] as num?)?.toDouble() ?? 0,
        totalEarnedXof:   (j['total_earned_xof'] as num?)?.toDouble() ?? 0,
        bonusPaidXof:     (j['bonus_paid_xof'] as num?)?.toDouble() ?? 0,
      );
}
```

---

### D2 — Provider rankings

**Fichier** : `mobile/lib/features/driver/providers/driver_provider.dart` (ajouter)

```dart
final rankingsProvider = FutureProvider.family<List<DriverRanking>, String>((ref, period) async {
  final api = ref.watch(apiClientProvider);
  final res  = await api.getRankings(period: period);
  final data = res.data as Map<String, dynamic>;
  return (data['rankings'] as List)
      .map((e) => DriverRanking.fromJson(e as Map<String, dynamic>))
      .toList();
});

final myRankingProvider = FutureProvider.family<MyRanking?, String>((ref, period) async {
  final api = ref.watch(apiClientProvider);
  try {
    final res  = await api.getMyRanking(period: period);
    return MyRanking.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});
```

---

### D3 — Écran classements

**Fichier** : `mobile/lib/features/driver/screens/driver_rankings_screen.dart` (créer)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/driver_provider.dart';
import '../../../core/models/driver_ranking.dart';
import '../../../shared/utils/currency_format.dart';

class DriverRankingsScreen extends ConsumerStatefulWidget {
  const DriverRankingsScreen({super.key});

  @override
  ConsumerState<DriverRankingsScreen> createState() => _DriverRankingsScreenState();
}

class _DriverRankingsScreenState extends ConsumerState<DriverRankingsScreen> {
  String _period = _currentPeriod();

  static String _currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String _previousPeriod() {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    return '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rankingsAsync = ref.watch(rankingsProvider(_period));
    final myRankAsync   = ref.watch(myRankingProvider(_period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classement livreurs'),
        actions: [
          // Sélecteur période
          PopupMenuButton<String>(
            onSelected: (p) => setState(() => _period = p),
            itemBuilder: (_) => [
              PopupMenuItem(value: _currentPeriod(),  child: Text('Ce mois')),
              PopupMenuItem(value: _previousPeriod(), child: Text('Mois précédent')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Text(_period, style: const TextStyle(fontSize: 13)),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // Ma carte de rang
        myRankAsync.when(
          data: (my) => my != null ? _MyRankCard(my: my) : const SizedBox.shrink(),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const Divider(height: 1),
        // Leaderboard
        Expanded(
          child: rankingsAsync.when(
            data: (list) => ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              itemBuilder: (_, i) => _RankRow(entry: list[i]),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
          ),
        ),
      ]),
    );
  }
}

class _MyRankCard extends StatelessWidget {
  const _MyRankCard({required this.my});
  final MyRanking my;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blue.shade50,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        _BadgeIcon(badge: my.badge, size: 40),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mon rang : #${my.rank}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text('${my.deliveriesTotal} courses • ${my.successRate.toStringAsFixed(1)}% succès',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatXof(my.totalEarnedXof),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          if (my.bonusPaidXof > 0)
            Text('+${formatXof(my.bonusPaidXof)} bonus',
                style: const TextStyle(fontSize: 11, color: Colors.orange)),
        ]),
      ]),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry});
  final DriverRanking entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: entry.isMe ? Colors.blue.shade50 : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 32,
          child: Text('#${entry.rank}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: entry.rank <= 3 ? Colors.orange.shade700 : Colors.grey,
              )),
        ),
        _BadgeIcon(badge: entry.badge, size: 24),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(entry.displayName,
                style: TextStyle(
                  fontWeight: entry.isMe ? FontWeight.bold : FontWeight.normal,
                )),
            if (entry.isMe) ...[ const SizedBox(width: 6),
              const Text('(moi)', style: TextStyle(fontSize: 11, color: Colors.blue)),
            ],
          ]),
          Text('${entry.deliveriesTotal} courses • ${entry.successRate.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        if (entry.avgRating > 0)
          Row(children: [
            const Icon(Icons.star, size: 13, color: Colors.amber),
            Text(entry.avgRating.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12)),
          ]),
      ]),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.badge, required this.size});
  final String badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (badge) {
      'gold'   => (Icons.emoji_events, Colors.amber.shade600),
      'silver' => (Icons.emoji_events, Colors.grey.shade400),
      'bronze' => (Icons.emoji_events, Colors.brown.shade300),
      _        => (Icons.person_outline, Colors.grey.shade300),
    };
    return Icon(icon, size: size, color: color);
  }
}
```

---

### D4 — Méthodes API client

**Fichier** : `mobile/lib/core/api/api_client.dart` (ajouter dans section Deliveries)

```dart
Future<Response> getRankings({String period = ''}) =>
    _dio.get(ApiEndpoints.rankings, queryParameters: period.isNotEmpty ? {'period': period} : null);

Future<Response> getMyRanking({String period = ''}) =>
    _dio.get(ApiEndpoints.myRanking, queryParameters: period.isNotEmpty ? {'period': period} : null);
```

**Fichier** : `mobile/lib/core/api/api_endpoints.dart` (ajouter)

```dart
static const rankings  = '$_base/api/deliveries/rankings';
static const myRanking = '$_base/api/deliveries/rankings/me';
```

---

### D5 — Intégrer dans driver_wallet_screen ou ajouter un onglet

Dans `driver_home.dart`, ajouter un 3ème onglet "Classement" :

```dart
DefaultTabController(
  length: 3,   // était 2
  child: Scaffold(
    appBar: AppBar(
      ...
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: Column(children: [
          // GPS bar
          const TabBar(tabs: [
            Tab(icon: Icon(Icons.inbox),          text: 'Disponibles'),
            Tab(icon: Icon(Icons.local_shipping),  text: 'Mes missions'),
            Tab(icon: Icon(Icons.leaderboard),     text: 'Classement'),
          ]),
        ]),
      ),
    ),
    body: TabBarView(children: [
      // ... onglets existants ...
      const DriverRankingsScreen(),
    ]),
  ),
);
```

---

## BLOC E — Offres Promotionnelles Admin

### Principe

```
L'admin crée une promo dans l'app admin.
Deux modes d'application :
  1. Automatique : s'applique si les conditions sont remplies (mode livraison, date, tier client)
  2. Code promo  : le client entre un code dans l'écran devis

Au moment du GET /quote :
  → backend cherche promos automatiques actives applicables
  → applique la meilleure (la plus avantageuse pour le client)
  → retourne le prix original + prix réduit + détail promo
```

---

### E1 — Modèle Promotion

**Fichier** : `backend/models/promotion.py` (créer)

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from enum import Enum
from uuid import uuid4

class PromoType(str, Enum):
    PERCENTAGE     = "percentage"       # ex: -20%
    FIXED_AMOUNT   = "fixed_amount"     # ex: -500 XOF
    FREE_DELIVERY  = "free_delivery"    # 0 XOF
    EXPRESS_UPGRADE= "express_upgrade"  # express offert (pas de ×1.40)

class PromoTarget(str, Enum):
    ALL            = "all"              # tous les clients
    FIRST_DELIVERY = "first_delivery"   # 1ère livraison seulement
    TIER_SILVER    = "tier_silver"      # clients Argent+
    TIER_GOLD      = "tier_gold"        # clients Or seulement
    DELIVERY_MODE  = "delivery_mode"    # mode spécifique


class PromotionCreate(BaseModel):
    title:              str
    description:        str = ""
    promo_type:         PromoType
    value:              float = 0.0        # % (20.0 pour -20%) ou XOF (500)
    target:             PromoTarget = PromoTarget.ALL
    delivery_mode:      Optional[str] = None  # si target=DELIVERY_MODE
    min_amount:         Optional[float] = None
    max_uses_total:     Optional[int]   = None  # None = illimité
    max_uses_per_user:  int = 1
    promo_code:         Optional[str]   = None  # None = automatique
    start_date:         datetime
    end_date:           datetime
    is_active:          bool = True


class Promotion(PromotionCreate):
    promo_id:    str = Field(default_factory=lambda: f"promo_{uuid4().hex[:12]}")
    uses_count:  int = 0
    created_by:  str = ""
    created_at:  datetime = Field(default_factory=lambda: datetime.now(__import__('datetime').timezone.utc))
```

---

### E2 — Router promotions admin

**Fichier** : `backend/routers/promotions.py` (créer)

```python
from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import datetime, timezone
from models.promotion import Promotion, PromotionCreate
from core.deps import get_current_user, get_db

router = APIRouter(prefix="/api/admin/promotions", tags=["promotions"])


def _require_admin(current_user: dict):
    if current_user.get("role") != "admin":
        raise HTTPException(403, "Admin seulement")


@router.post("", response_model=dict)
async def create_promotion(
    body: PromotionCreate,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    _require_admin(current_user)
    promo = Promotion(**body.model_dump(), created_by=current_user["user_id"])
    await db.promotions.insert_one(promo.model_dump())
    return {"promo_id": promo.promo_id, "message": "Promotion créée"}


@router.get("", response_model=dict)
async def list_promotions(
    active_only: bool = Query(False),
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    _require_admin(current_user)
    query = {}
    if active_only:
        now = datetime.now(timezone.utc)
        query = {"is_active": True, "start_date": {"$lte": now}, "end_date": {"$gte": now}}
    promos = await db.promotions.find(query, sort=[("created_at", -1)]).to_list(100)
    return {"promotions": promos}


@router.put("/{promo_id}", response_model=dict)
async def update_promotion(
    promo_id: str,
    body: dict,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    _require_admin(current_user)
    allowed = {"title", "description", "is_active", "end_date", "max_uses_total",
               "max_uses_per_user", "value", "min_amount"}
    update = {k: v for k, v in body.items() if k in allowed}
    if not update:
        raise HTTPException(400, "Aucun champ modifiable fourni")
    await db.promotions.update_one({"promo_id": promo_id}, {"$set": update})
    return {"message": "Promotion mise à jour"}


@router.delete("/{promo_id}", response_model=dict)
async def delete_promotion(
    promo_id: str,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    _require_admin(current_user)
    await db.promotions.delete_one({"promo_id": promo_id})
    return {"message": "Promotion supprimée"}
```

---

### E3 — Service application de promo

**Fichier** : `backend/services/promotion_service.py` (créer)

```python
from datetime import datetime, timezone
from typing import Optional

async def find_best_promo(
    db,
    delivery_mode:  str,
    original_price: float,
    user_id:        str,
    user_tier:      str,
    is_first_delivery: bool,
    promo_code:     Optional[str] = None,
) -> Optional[dict]:
    """
    Cherche la meilleure promo applicable.
    Si promo_code fourni → cherche cette promo spécifique.
    Sinon → cherche promos automatiques (sans code) applicables.
    Retourne un dict {promo, discount_xof, final_price} ou None.
    """
    now = datetime.now(timezone.utc)

    if promo_code:
        query = {
            "promo_code": promo_code.upper().strip(),
            "is_active": True,
            "start_date": {"$lte": now},
            "end_date":   {"$gte": now},
        }
    else:
        query = {
            "promo_code": None,   # automatiques seulement
            "is_active": True,
            "start_date": {"$lte": now},
            "end_date":   {"$gte": now},
        }

    promos = await db.promotions.find(query).to_list(50)

    best      = None
    best_disc = 0.0

    for p in promos:
        # Vérifier cible
        target = p.get("target", "all")
        if target == "first_delivery"  and not is_first_delivery: continue
        if target == "tier_silver"     and user_tier not in ("silver", "gold"): continue
        if target == "tier_gold"       and user_tier != "gold": continue
        if target == "delivery_mode"   and p.get("delivery_mode") != delivery_mode: continue

        # Vérifier montant minimum
        if p.get("min_amount") and original_price < p["min_amount"]: continue

        # Vérifier quota total
        if p.get("max_uses_total") and p.get("uses_count", 0) >= p["max_uses_total"]: continue

        # Vérifier quota par utilisateur
        max_per_user = p.get("max_uses_per_user", 1)
        user_uses = await db.promo_uses.count_documents({
            "promo_id": p["promo_id"],
            "user_id":  user_id,
        })
        if user_uses >= max_per_user: continue

        # Calculer réduction
        promo_type = p.get("promo_type")
        if promo_type == "free_delivery":
            disc = original_price
        elif promo_type == "percentage":
            disc = round(original_price * p.get("value", 0) / 100)
        elif promo_type == "fixed_amount":
            disc = min(p.get("value", 0), original_price)
        elif promo_type == "express_upgrade":
            # Cas spécial : retourne un flag, pas une réduction XOF
            if disc := 0: pass
            return {"promo": p, "discount_xof": 0, "final_price": original_price,
                    "express_free": True}
        else:
            disc = 0

        if disc > best_disc:
            best_disc = disc
            best = p

    if best is None:
        return None

    final = max(0, original_price - best_disc)
    return {
        "promo":        best,
        "discount_xof": best_disc,
        "final_price":  final,
        "express_free": False,
    }


async def record_promo_use(db, promo_id: str, user_id: str, parcel_id: str):
    """Enregistrer l'utilisation d'une promo après création du colis."""
    from uuid import uuid4
    from datetime import datetime, timezone
    await db.promo_uses.insert_one({
        "use_id":    f"puse_{uuid4().hex[:12]}",
        "promo_id":  promo_id,
        "user_id":   user_id,
        "parcel_id": parcel_id,
        "created_at": datetime.now(timezone.utc),
    })
    await db.promotions.update_one(
        {"promo_id": promo_id},
        {"$inc": {"uses_count": 1}},
    )
```

---

### E4 — Intégration dans le devis (quote)

**Fichier** : `backend/routers/parcels.py`

Dans `POST /quote`, après calcul du prix de base, ajouter :

```python
from services.promotion_service import find_best_promo

# Récupérer infos sender
sender = await db.users.find_one({"user_id": current_user["user_id"]})
user_tier = sender.get("loyalty_tier", "bronze")
delivered_count = await db.parcels.count_documents({
    "sender_user_id": current_user["user_id"], "status": "delivered"
})
is_first = delivered_count == 0

promo_code = body.promo_code if hasattr(body, 'promo_code') else None

promo_result = await find_best_promo(
    db,
    delivery_mode=body.delivery_mode,
    original_price=quote["price"],
    user_id=current_user["user_id"],
    user_tier=user_tier,
    is_first_delivery=is_first,
    promo_code=promo_code,
)

if promo_result:
    quote["original_price"]  = quote["price"]
    quote["price"]           = promo_result["final_price"]
    quote["discount_xof"]    = promo_result["discount_xof"]
    quote["promo_applied"]   = {
        "promo_id":    promo_result["promo"]["promo_id"],
        "title":       promo_result["promo"]["title"],
        "promo_type":  promo_result["promo"]["promo_type"],
        "express_free":promo_result.get("express_free", False),
    }
```

Aussi ajouter `promo_code: Optional[str] = None` dans `ParcelQuote` (models/parcel.py).

Dans `POST /parcels` (création du colis) : si une promo a été appliquée, appeler `record_promo_use`.

---

### E5 — Endpoint vérification code promo (client)

**Fichier** : `backend/routers/parcels.py`

```python
@router.post("/check-promo")
async def check_promo(
    body: dict,
    current_user: dict = Depends(get_current_user),
    db=Depends(get_db),
):
    code = body.get("promo_code", "").upper().strip()
    price = body.get("price", 0)
    mode  = body.get("delivery_mode", "relay_to_relay")

    if not code:
        raise HTTPException(400, "Code manquant")

    from services.promotion_service import find_best_promo
    sender = await db.users.find_one({"user_id": current_user["user_id"]})
    result = await find_best_promo(
        db, delivery_mode=mode, original_price=price,
        user_id=current_user["user_id"],
        user_tier=sender.get("loyalty_tier", "bronze"),
        is_first_delivery=False,
        promo_code=code,
    )
    if not result:
        raise HTTPException(404, "Code invalide ou non applicable")

    return {
        "valid":         True,
        "promo_title":   result["promo"]["title"],
        "discount_xof":  result["discount_xof"],
        "final_price":   result["final_price"],
    }
```

---

### E6 — Enregistrer le router

**Fichier** : `backend/main.py`

```python
from routers.promotions import router as promotions_router
app.include_router(promotions_router)
```

---

### E7 — Modèle Flutter Promotion

**Fichier** : `mobile/lib/core/models/promotion.dart` (créer)

```dart
class Promotion {
  const Promotion({
    required this.promoId,
    required this.title,
    required this.description,
    required this.promoType,
    required this.value,
    required this.target,
    required this.startDate,
    required this.endDate,
    required this.isActive,
    required this.usesCount,
    this.promoCode,
    this.deliveryMode,
    this.minAmount,
    this.maxUsesTotal,
    this.maxUsesPerUser = 1,
  });

  final String   promoId;
  final String   title;
  final String   description;
  final String   promoType;   // "percentage" | "fixed_amount" | "free_delivery" | "express_upgrade"
  final double   value;
  final String   target;
  final DateTime startDate;
  final DateTime endDate;
  final bool     isActive;
  final int      usesCount;
  final String?  promoCode;
  final String?  deliveryMode;
  final double?  minAmount;
  final int?     maxUsesTotal;
  final int      maxUsesPerUser;

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        promoId:        j['promo_id'] as String,
        title:          j['title'] as String,
        description:    j['description'] as String? ?? '',
        promoType:      j['promo_type'] as String,
        value:          (j['value'] as num?)?.toDouble() ?? 0,
        target:         j['target'] as String? ?? 'all',
        startDate:      DateTime.parse(j['start_date'] as String),
        endDate:        DateTime.parse(j['end_date'] as String),
        isActive:       j['is_active'] as bool? ?? true,
        usesCount:      j['uses_count'] as int? ?? 0,
        promoCode:      j['promo_code'] as String?,
        deliveryMode:   j['delivery_mode'] as String?,
        minAmount:      (j['min_amount'] as num?)?.toDouble(),
        maxUsesTotal:   j['max_uses_total'] as int?,
        maxUsesPerUser: j['max_uses_per_user'] as int? ?? 1,
      );

  String get typeLabel => switch (promoType) {
        'percentage'      => '-${value.toStringAsFixed(0)}%',
        'fixed_amount'    => '-${value.toStringAsFixed(0)} XOF',
        'free_delivery'   => 'Livraison gratuite',
        'express_upgrade' => 'Express offert',
        _                 => '',
      };

  bool get isCurrentlyActive {
    final now = DateTime.now();
    return isActive && now.isAfter(startDate) && now.isBefore(endDate);
  }
}
```

---

### E8 — Écran admin promotions

**Fichier** : `mobile/lib/features/admin/screens/admin_promotions_screen.dart` (créer)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/promotion.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/currency_format.dart';

final _adminPromosProvider = FutureProvider<List<Promotion>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res  = await api.getAdminPromotions();
  final data = res.data as Map<String, dynamic>;
  return (data['promotions'] as List)
      .map((e) => Promotion.fromJson(e as Map<String, dynamic>))
      .toList();
});

class AdminPromotionsScreen extends ConsumerWidget {
  const AdminPromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promosAsync = ref.watch(_adminPromosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Offres promotionnelles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePromoDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle offre'),
      ),
      body: promosAsync.when(
        data: (promos) => promos.isEmpty
            ? const Center(child: Text('Aucune offre créée'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: promos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _PromoCard(
                  promo: promos[i],
                  onToggle: () async {
                    final api = ref.read(apiClientProvider);
                    await api.updatePromotion(promos[i].promoId, {
                      'is_active': !promos[i].isActive,
                    });
                    ref.invalidate(_adminPromosProvider);
                  },
                  onDelete: () async {
                    final api = ref.read(apiClientProvider);
                    await api.deletePromotion(promos[i].promoId);
                    ref.invalidate(_adminPromosProvider);
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
      ),
    );
  }

  void _showCreatePromoDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreatePromoSheet(onCreated: () => ref.invalidate(_adminPromosProvider)),
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo, required this.onToggle, required this.onDelete});
  final Promotion promo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final active = promo.isCurrentlyActive;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: active ? Colors.green.shade100 : Colors.grey.shade200,
          child: Icon(
            active ? Icons.local_offer : Icons.local_offer_outlined,
            color: active ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(promo.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(promo.typeLabel, style: TextStyle(color: Colors.blue.shade700)),
          Text(
            '${_formatDate(promo.startDate)} → ${_formatDate(promo.endDate)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (promo.promoCode != null)
            Text('Code: ${promo.promoCode}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          Text(
            '${promo.usesCount} utilisation(s)'
            '${promo.maxUsesTotal != null ? ' / ${promo.maxUsesTotal}' : ''}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: promo.isActive, onChanged: (_) => onToggle()),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: onDelete,
          ),
        ]),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Formulaire création ────────────────────────────────────────────────────────
class _CreatePromoSheet extends StatefulWidget {
  const _CreatePromoSheet({required this.onCreated});
  final VoidCallback onCreated;

  @override
  State<_CreatePromoSheet> createState() => _CreatePromoSheetState();
}

class _CreatePromoSheetState extends State<_CreatePromoSheet> {
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _valueCtrl    = TextEditingController();
  final _codeCtrl     = TextEditingController();
  final _maxUsesCtrl  = TextEditingController();

  String _promoType = 'percentage';
  String _target    = 'all';
  DateTime _start   = DateTime.now();
  DateTime _end     = DateTime.now().add(const Duration(days: 7));
  bool _hasCode     = false;
  bool _loading     = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nouvelle offre', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Titre *')),
          const SizedBox(height: 8),
          TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description')),
          const SizedBox(height: 12),

          // Type de promo
          DropdownButtonFormField<String>(
            value: _promoType,
            items: const [
              DropdownMenuItem(value: 'percentage',      child: Text('Pourcentage (-X%)')),
              DropdownMenuItem(value: 'fixed_amount',    child: Text('Montant fixe (-X XOF)')),
              DropdownMenuItem(value: 'free_delivery',   child: Text('Livraison gratuite')),
              DropdownMenuItem(value: 'express_upgrade', child: Text('Express offert')),
            ],
            onChanged: (v) => setState(() => _promoType = v!),
            decoration: const InputDecoration(labelText: 'Type de réduction'),
          ),
          const SizedBox(height: 8),

          if (_promoType != 'free_delivery' && _promoType != 'express_upgrade')
            TextField(
              controller: _valueCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _promoType == 'percentage' ? 'Valeur (%)' : 'Montant (XOF)',
              ),
            ),
          const SizedBox(height: 8),

          // Cible
          DropdownButtonFormField<String>(
            value: _target,
            items: const [
              DropdownMenuItem(value: 'all',            child: Text('Tous les clients')),
              DropdownMenuItem(value: 'first_delivery', child: Text('1ère livraison')),
              DropdownMenuItem(value: 'tier_silver',    child: Text('Clients Argent+')),
              DropdownMenuItem(value: 'tier_gold',      child: Text('Clients Or')),
            ],
            onChanged: (v) => setState(() => _target = v!),
            decoration: const InputDecoration(labelText: 'Cible'),
          ),
          const SizedBox(height: 8),

          // Période
          Row(children: [
            Expanded(child: _DateButton(
              label: 'Début: ${_formatDate(_start)}',
              onTap: () async {
                final d = await showDatePicker(context: context,
                    initialDate: _start, firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _start = d);
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: _DateButton(
              label: 'Fin: ${_formatDate(_end)}',
              onTap: () async {
                final d = await showDatePicker(context: context,
                    initialDate: _end, firstDate: _start,
                    lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _end = d);
              },
            )),
          ]),
          const SizedBox(height: 8),

          // Code promo optionnel
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avec code promo'),
            subtitle: const Text('Client doit saisir le code manuellement'),
            value: _hasCode,
            onChanged: (v) => setState(() => _hasCode = v),
          ),
          if (_hasCode)
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(labelText: 'Code (ex: NOEL2026)'),
              textCapitalization: TextCapitalization.characters,
            ),

          TextField(
            controller: _maxUsesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Utilisations max totales (vide = illimité)'),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Créer l\'offre'),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      // Appel API
      final body = <String, dynamic>{
        'title':       _titleCtrl.text,
        'description': _descCtrl.text,
        'promo_type':  _promoType,
        'value':       double.tryParse(_valueCtrl.text) ?? 0.0,
        'target':      _target,
        'start_date':  _start.toIso8601String(),
        'end_date':    _end.toIso8601String(),
        'is_active':   true,
        if (_hasCode && _codeCtrl.text.isNotEmpty) 'promo_code': _codeCtrl.text.toUpperCase(),
        if (_maxUsesCtrl.text.isNotEmpty) 'max_uses_total': int.tryParse(_maxUsesCtrl.text),
      };
      // ignore: use_build_context_synchronously
      // On doit passer par ref mais ce widget est StatefulWidget non Consumer.
      // Solution: utiliser un callback ou convertir en ConsumerStatefulWidget.
      // Pour l'instant, utiliser api via Navigator (pattern à adapter).
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
}
```

> **Note** : Convertir `_CreatePromoSheetState` en `ConsumerStatefulWidget` pour accéder à `ref.read(apiClientProvider)` et appeler `api.createPromotion(body)`.

---

### E9 — Méthodes API client (promotions)

**Fichier** : `mobile/lib/core/api/api_client.dart` (ajouter dans section Admin)

```dart
// Promotions admin
Future<Response> getAdminPromotions({bool activeOnly = false}) =>
    _dio.get(ApiEndpoints.adminPromotions,
        queryParameters: activeOnly ? {'active_only': true} : null);

Future<Response> createPromotion(Map<String, dynamic> body) =>
    _dio.post(ApiEndpoints.adminPromotions, data: body);

Future<Response> updatePromotion(String id, Map<String, dynamic> body) =>
    _dio.put(ApiEndpoints.adminPromotion(id), data: body);

Future<Response> deletePromotion(String id) =>
    _dio.delete(ApiEndpoints.adminPromotion(id));

// Vérification code promo (client)
Future<Response> checkPromoCode(Map<String, dynamic> body) =>
    _dio.post(ApiEndpoints.checkPromo, data: body);
```

**Fichier** : `mobile/lib/core/api/api_endpoints.dart` (ajouter)

```dart
static const adminPromotions  = '$_base/api/admin/promotions';
static String adminPromotion(id) => '$_base/api/admin/promotions/$id';
static const checkPromo       = '$_base/api/parcels/check-promo';
static const loyaltyMe        = '$_base/api/users/me/loyalty';
static const myReferral       = '$_base/api/users/refer';
static const applyReferral    = '$_base/api/users/apply-referral';
```

---

### E10 — Champ code promo dans QuoteScreen

**Fichier** : `mobile/lib/features/client/screens/quote_screen.dart`

Ajouter dans le state :
```dart
final _promoCtrl  = TextEditingController();
String? _promoApplied;
double? _discountXof;
```

Ajouter dans l'UI (avant le bouton confirmer) :
```dart
// Section code promo
Row(children: [
  Expanded(
    child: TextField(
      controller: _promoCtrl,
      decoration: const InputDecoration(
        labelText: 'Code promo (optionnel)',
        prefixIcon: Icon(Icons.local_offer_outlined),
      ),
      textCapitalization: TextCapitalization.characters,
    ),
  ),
  const SizedBox(width: 8),
  ElevatedButton(
    onPressed: _checkPromo,
    child: const Text('Appliquer'),
  ),
]),
if (_promoApplied != null)
  Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.green.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.green.shade200),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 16),
      const SizedBox(width: 6),
      Text('$_promoApplied  |  -${formatXof(_discountXof ?? 0)}',
          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
    ]),
  ),
```

Méthode :
```dart
Future<void> _checkPromo() async {
  final code = _promoCtrl.text.trim();
  if (code.isEmpty) return;
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.checkPromoCode({
      'promo_code':     code,
      'price':          widget.quoteData['price'],
      'delivery_mode':  widget.quoteData['delivery_mode'],
    });
    final data = res.data as Map<String, dynamic>;
    setState(() {
      _promoApplied = data['promo_title'] as String;
      _discountXof  = (data['discount_xof'] as num).toDouble();
    });
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Code invalide'), backgroundColor: Colors.red),
    );
  }
}
```

---

## Ordre d'implémentation (16 étapes)

```
BACKEND (dans cet ordre)
─────────────────────────────────────────────────────────────────────────────
1.  models/user.py            → loyalty_points, loyalty_tier, referral_code, referred_by
2.  models/promotion.py       → Promotion, PromotionCreate (nouveau fichier)
3.  services/user_service.py  → _generate_referral_code, _compute_tier, _tier_discount
4.  services/pricing_service.py → sender_tier + is_frequent params dans compute_quote
5.  services/parcel_service.py → _credit_loyalty_points, crédit parrainage 1ère livraison
6.  services/promotion_service.py → find_best_promo, record_promo_use (nouveau fichier)
7.  services/ranking_service.py → compute_driver_stats, pay_monthly_bonuses,
                                   compute_relay_stats (nouveau fichier)
8.  routers/users.py          → GET /me/loyalty, POST /refer, POST /apply-referral
9.  routers/parcels.py        → intégrer find_best_promo dans /quote + /check-promo endpoint
10. routers/deliveries.py     → GET /rankings, GET /rankings/me
11. routers/promotions.py     → CRUD admin promotions (nouveau fichier)
12. main.py                   → include promotions router + cron apscheduler

FLUTTER (dans cet ordre)
─────────────────────────────────────────────────────────────────────────────
13. core/models/driver_ranking.dart  → DriverRanking, MyRanking (nouveau)
14. core/models/promotion.dart       → Promotion (nouveau)
15. core/api/api_endpoints.dart      → 6 nouvelles URLs
16. core/api/api_client.dart         → 6+ nouvelles méthodes
17. driver/providers/driver_provider.dart → rankingsProvider, myRankingProvider
18. driver/screens/driver_rankings_screen.dart → Leaderboard (nouveau)
19. driver/screens/driver_home.dart  → 3ème onglet Classement
20. admin/screens/admin_promotions_screen.dart → CRUD promos (nouveau)
21. client/screens/quote_screen.dart → champ code promo + affichage réduction
```

---

## Index MongoDB (performances)

```python
# À ajouter dans database.py (startup)
await db.promotions.create_index([("is_active", 1), ("start_date", 1), ("end_date", 1)])
await db.promotions.create_index("promo_code", sparse=True)
await db.promo_uses.create_index([("promo_id", 1), ("user_id", 1)])
await db.driver_stats.create_index([("driver_id", 1), ("period", 1)], unique=True)
await db.loyalty_events.create_index([("user_id", 1), ("created_at", -1)])
```

---

## Résumé des collections MongoDB ajoutées

| Collection | Description |
|---|---|
| `promotions` | Offres créées par l'admin |
| `promo_uses` | Historique d'utilisation des codes |
| `driver_stats` | Stats mensuelles par livreur (rang, bonus) |
| `loyalty_events` | Historique points fidélité client |
