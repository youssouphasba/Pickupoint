"""
Helpers fidélité clients : points, paliers, parrainage.
"""
import random
import string


def generate_referral_code(name: str) -> str:
    """Génère un code parrainage unique. Ex: DAOUDA-4F2K"""
    suffix = "".join(random.choices(string.ascii_uppercase + string.digits, k=4))
    prefix = (name or "USER")[:6].upper().replace(" ", "")
    return f"{prefix}-{suffix}"


def compute_tier(points: int) -> str:
    if points >= 1500:
        return "gold"
    if points >= 500:
        return "silver"
    return "bronze"


def tier_discount_coeff(tier: str) -> float:
    """Coefficient de réduction fidélité (1.0 = aucune réduction)."""
    return {"bronze": 1.0, "silver": 0.95, "gold": 0.90}.get(tier, 1.0)


POINTS_PER_DELIVERY = 10
REFERRAL_BONUS_XOF  = 500
