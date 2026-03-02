"""
Service de Gamification : Gestion de l'XP, des niveaux et des badges pour les livreurs.
"""
import logging
from database import db
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# Config simple des niveaux (tous les 100 XP)
XP_PER_LEVEL = 100

# XP Awards
XP_DELIVERY_COMPLETE = 10
XP_RATING_MULTIPLIER = 2  # rating * 2 (ex: 5 stars = 10 XP)

async def update_driver_gamification(driver_id: str, action: str, **kwargs):
    """
    Met à jour la progression d'un livreur.
    Actions : 'delivery_completed', 'rating_received'.
    """
    user = await db.users.find_one({"user_id": driver_id})
    if not user:
        return

    xp_to_add = 0
    update_fields = {}

    if action == "delivery_completed":
        xp_to_add = XP_DELIVERY_COMPLETE
        update_fields["deliveries_completed"] = user.get("deliveries_completed", 0) + 1
        
        # Geofence check or On-time check could be here
        if kwargs.get("on_time", True):
            update_fields["on_time_deliveries"] = user.get("on_time_deliveries", 0) + 1

    elif action == "rating_received":
        rating = kwargs.get("rating", 0)
        xp_to_add = rating * XP_RATING_MULTIPLIER
        
        count = user.get("total_ratings_count", 0) + 1
        total_sum = user.get("total_rating_sum", 0.0) + float(rating)
        
        update_fields["total_ratings_count"] = count
        update_fields["total_rating_sum"] = total_sum
        update_fields["average_rating"] = total_sum / count

    if xp_to_add > 0:
        new_xp = user.get("xp", 0) + xp_to_add
        new_level = (new_xp // XP_PER_LEVEL) + 1
        
        update_fields["xp"] = new_xp
        if new_level > user.get("level", 1):
            update_fields["level"] = new_level
            logger.info(f"Driver {driver_id} leveled up to {new_level}!")

    # Evaluation des Badges
    new_badges = await _evaluate_badges(user, update_fields)
    if new_badges:
        update_fields["badges"] = list(set(user.get("badges", []) + new_badges))

    if update_fields:
        update_fields["updated_at"] = datetime.now(timezone.utc)
        await db.users.update_one({"user_id": driver_id}, {"$set": update_fields})
        logger.info(f"Gamification updated for {driver_id}: {action} (+{xp_to_add} XP)")

async def _evaluate_badges(user: dict, current_updates: dict) -> list[str]:
    """Vérifie si de nouveaux badges doivent être attribués."""
    badges = []
    existing = user.get("badges", [])
    
    total_deliv = current_updates.get("deliveries_completed", user.get("deliveries_completed", 0))
    ratings_count = current_updates.get("total_ratings_count", user.get("total_ratings_count", 0))
    avg_rating = current_updates.get("average_rating", user.get("average_rating", 0.0))

    if "first_flight" not in existing and total_deliv >= 1:
        badges.append("first_flight")
    
    if "road_warrior" not in existing and total_deliv >= 10:
        badges.append("road_warrior")
        
    if "dakar_legend" not in existing and total_deliv >= 50:
        badges.append("dakar_legend")
        
    if "five_star_general" not in existing and ratings_count >= 5 and avg_rating >= 4.8:
        badges.append("five_star_general")

    return badges
