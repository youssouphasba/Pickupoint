from copy import deepcopy

from models.common import UserRole


def driver_rounding_offer(snapshot) -> dict | None:
    if not isinstance(snapshot, dict):
        return None
    rounding = snapshot.get("rounding")
    if not isinstance(rounding, dict) or not rounding.get("version"):
        return None
    return {"rounding": {key: deepcopy(rounding[key]) for key in (
        "version", "driver_bonus_xof",
    ) if key in rounding}}


def serialize_mission(mission: dict, viewer: dict) -> dict:
    result = deepcopy(mission)
    if viewer.get("role") != UserRole.DRIVER.value:
        return result
    contract = result.get("financial_contract")
    snapshot = (contract.get("breakdown") if isinstance(contract, dict) else None) or result.get("financial_rounding")
    for field in (
        "quoted_price", "paid_price", "price_xof", "financial_contract",
        "quote_breakdown", "commission_rules", "commission_rules_snapshot",
        "financial_rounding", "destination_financial_review", "recipient_collection_remittances",
    ):
        result.pop(field, None)
    offer = driver_rounding_offer(snapshot)
    if offer:
        result["financial_rounding"] = offer
    plan = result.get("recipient_collection_plan")
    if isinstance(plan, dict):
        result["recipient_collection_plan"] = {
            key: deepcopy(plan[key]) for key in ("collector", "status", "revision") if key in plan
        }
    return result
