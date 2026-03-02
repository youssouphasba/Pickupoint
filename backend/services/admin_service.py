"""
Service d'administration : Opérations sensibles (réassignations, règlements COD, surcharges de statut).
"""
import logging
from datetime import datetime, timezone
from database import db
from core.exceptions import not_found_exception, bad_request_exception
from models.common import ParcelStatus

logger = logging.getLogger(__name__)

async def settle_driver_cod(driver_id: str, amount: float = None) -> dict:
    """
    Marque le cash collecté par un livreur comme encaissé par la plateforme.
    Si amount est None, solde tout le compte.
    """
    driver = await db.users.find_one({"user_id": driver_id})
    if not driver:
        raise not_found_exception("Livreur")
    
    current_bal = driver.get("cod_balance", 0.0)
    if amount is None:
        amount = current_bal
    
    if amount > current_bal:
        raise bad_request_exception(f"Le montant à solder ({amount}) dépasse le solde ({current_bal})")
    
    now = datetime.now(timezone.utc)
    await db.users.update_one(
        {"user_id": driver_id},
        {"$inc": {"cod_balance": -float(amount)}, "$set": {"updated_at": now}}
    )
    
    # Historiser le règlement dans une collection dédiée (optionnel pour la Phase 9)
    settlement = {
        "driver_id": driver_id,
        "amount": amount,
        "created_at": now,
        "status": "completed"
    }
    await db.cod_settlements.insert_one(settlement)
    
    logger.info(f"Règlement COD : livreur {driver_id}, montant {amount} XOF")
    return {"driver_id": driver_id, "amount_settled": amount, "new_balance": current_bal - amount}

async def override_parcel_status(parcel_id: str, new_status: ParcelStatus, notes: str) -> dict:
    """
    Force le changement de statut d'un colis (SuperAdmin).
    """
    from services.parcel_service import transition_status
    
    # On utilise le transition_status normal pour garder les logs d'events
    # Mais ici c'est une intervention manuelle
    success = await transition_status(
        parcel_id, 
        new_status, 
        actor_id="ADMIN_OVERRIDE", 
        actor_role="admin", 
        notes=f"FORCE OVERRIDE: {notes}"
    )
    
    if not success:
        raise bad_request_exception("Transition de statut impossible (même en override)")
        
    return {"parcel_id": parcel_id, "new_status": new_status, "notes": notes}
