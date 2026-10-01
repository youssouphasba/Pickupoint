from datetime import datetime, timezone

from core.exceptions import bad_request_exception, not_found_exception
from database import db
from services.wallet_service import _run_in_transaction, record_wallet_transaction


async def settle_payout(payout_id: str, status: str, changes: dict) -> dict:
    if status not in {"approved", "rejected"}:
        raise ValueError("Statut de retrait invalide")

    async def settle(session):
        payout = await db.payout_requests.find_one({"payout_id": payout_id}, {"_id": 0}, session=session)
        if not payout:
            raise not_found_exception("Demande de retrait")
        if payout.get("status") != "pending":
            raise bad_request_exception("Ce retrait n'est plus en attente")
        wallet = await db.wallets.find_one({"wallet_id": payout["wallet_id"]}, session=session)
        if not wallet:
            raise not_found_exception("Wallet")
        if status == "approved":
            if wallet.get("payout_blocked"):
                raise bad_request_exception(wallet.get("payout_block_reason") or "Décaissement bloqué par l'administration")
            owner_id = payout.get("owner_id") or payout.get("user_id")
            owner = await db.users.find_one_and_update(
                {"user_id": owner_id}, {"$inc": {"mission_assignment_revision": 1}}, session=session,
            )
            if owner and owner.get("role") == "driver" and await db.delivery_missions.find_one(
                {"driver_id": owner_id, "status": {"$in": ["assigned", "in_progress", "incident_reported"]}}, session=session,
            ):
                raise bad_request_exception("Décaissement indisponible tant qu'une course est active")
        now = datetime.now(timezone.utc)
        result = await db.payout_requests.update_one(
            {"payout_id": payout_id, "status": "pending"},
            {"$set": {**changes, "status": status, "updated_at": now}}, session=session,
        )
        if result.matched_count != 1:
            raise bad_request_exception("Ce retrait n'est plus en attente")
        increments = {"pending": -payout["amount"]}
        if status == "rejected":
            increments["balance"] = payout["amount"]
        result = await db.wallets.update_one(
            {"wallet_id": payout["wallet_id"], "pending": {"$gte": payout["amount"]}},
            {"$inc": increments, "$set": {"updated_at": now}}, session=session,
        )
        if result.modified_count != 1:
            raise bad_request_exception("Solde réservé incohérent pour cette demande")
        await record_wallet_transaction(
            wallet_id=payout["wallet_id"], amount=payout["amount"],
            tx_type="debit" if status == "approved" else "credit",
            description="Retrait approuvé et versé" if status == "approved" else "Retrait rejeté et montant restitué",
            reference=payout_id, ensure_unique=True, session=session,
        )
        return await db.wallets.find_one({"wallet_id": payout["wallet_id"]}, {"_id": 0}, session=session)
    return await _run_in_transaction(settle)
