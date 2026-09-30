from copy import deepcopy
from math import ceil, isfinite

DEFAULT_LOYALTY_TIERS = [
    {"key": "bronze", "label": "Bronze", "min_points": 0, "discount_percent": 0},
    {"key": "silver", "label": "Argent", "min_points": 200, "discount_percent": 10},
    {"key": "gold", "label": "Or", "min_points": 500, "discount_percent": 20},
]


def normalize_loyalty_tiers(raw=None):
    source = {item.get("key"): item for item in raw or [] if isinstance(item, dict)}
    tiers = deepcopy(DEFAULT_LOYALTY_TIERS)
    previous_threshold = -1
    previous_discount = 0
    for tier in tiers:
        item = source.get(tier["key"], {})
        try:
            threshold = int(item.get("min_points", tier["min_points"]))
            discount = float(item.get("discount_percent", tier["discount_percent"]))
        except (TypeError, ValueError):
            threshold, discount = tier["min_points"], tier["discount_percent"]
        if not isfinite(discount):
            discount = tier["discount_percent"]
        tier["min_points"] = 0 if tier["key"] == "bronze" else max(previous_threshold + 1, threshold)
        tier["discount_percent"] = min(100, max(previous_discount, discount))
        previous_threshold = tier["min_points"]
        previous_discount = tier["discount_percent"]
    return tiers


def compute_tier(points, tiers=None):
    points = max(points or 0, 0)
    return next(tier["key"] for tier in reversed(tiers or DEFAULT_LOYALTY_TIERS) if points >= tier["min_points"])


def tier_discount_coeff(key, tiers=None):
    tier = next((item for item in tiers or DEFAULT_LOYALTY_TIERS if item["key"] == key), None)
    return 1 - tier["discount_percent"] / 100 if tier else 1.0


def loyalty_summary(points, client_rules):
    points = max(int(points or 0), 0)
    tiers = client_rules["loyalty_tiers"]
    key = compute_tier(points, tiers)
    index = next(i for i, tier in enumerate(tiers) if tier["key"] == key)
    current = tiers[index]
    following = tiers[index + 1] if index + 1 < len(tiers) else None
    points_per_delivery = client_rules["loyalty_points_per_delivered_parcel"]
    remaining = max(following["min_points"] - points, 0) if following else 0
    progress = min(1, (points - current["min_points"]) / (following["min_points"] - current["min_points"])) if following else 1
    return {
        "points": points, "tier": key, "tier_label": current["label"],
        "discount_percent": current["discount_percent"], "tiers": tiers,
        "next_tier": following, "next_tier_at": following["min_points"] if following else None,
        "points_remaining": remaining, "deliveries_remaining": ceil(remaining / points_per_delivery),
        "points_per_delivery": points_per_delivery, "progress": progress,
        "beneficiary": "sender", "earned_on": "delivered",
        "conditions": "Les points sont crédités à l’expéditeur lorsque son colis est livré. Les réductions sont appliquées automatiquement au devis, selon le tarif minimum et les règles d’arrondi. Les points ne sont pas un solde d’argent.",
    }
