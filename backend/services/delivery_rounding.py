"""Arrondis de livraison et répartition figée, sans modifier les anciens contrats."""

from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_FLOOR, ROUND_HALF_UP

from config import settings
from core.exceptions import DeliveryRoundingError


POLICY_VERSION = "customer_down_driver_up_v1"
CENT = Decimal("0.01")
CALCULATION_PRECISION = Decimal("0.00000001")
AMOUNT_FIELDS = (
    "price_xof", "platform_commission_xof", "origin_relay_commission_xof",
    "destination_relay_commission_xof", "relay_commission_xof",
    "total_commission_xof", "wallet_balance_required_xof", "driver_revenue_xof",
)


def decimal_amount(value) -> Decimal:
    try:
        result = Decimal(str(value))
        if not result.is_finite() or result < 0:
            raise DeliveryRoundingError()
        return result.quantize(CALCULATION_PRECISION, rounding=ROUND_HALF_UP)
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise DeliveryRoundingError() from exc


def money(value) -> Decimal:
    return decimal_amount(value).quantize(CENT, rounding=ROUND_HALF_UP)


def _step(value=None) -> Decimal:
    result = decimal_amount(settings.DELIVERY_ROUNDING_STEP_XOF if value is None else value)
    if result <= 0 or result != result.to_integral_value():
        raise DeliveryRoundingError()
    return result


def round_down(value, step=None) -> int:
    increment = _step(step)
    return int((decimal_amount(value) / increment).to_integral_value(rounding=ROUND_FLOOR) * increment)


def round_up(value, step=None) -> int:
    increment = _step(step)
    return int((decimal_amount(value) / increment).to_integral_value(rounding=ROUND_CEILING) * increment)


def build_financial_rounding(
    basis_price, mode: str, commission_rules: dict, *, enabled: bool = True, step=None,
) -> dict:
    basis = decimal_amount(basis_price)
    increment = _step(step)
    try:
        rules = commission_rules[mode]
        rates = {key: Decimal(str(rules[key])) for key in (
            "platform_rate", "origin_relay_rate", "destination_relay_rate", "driver_rate",
        )}
    except (KeyError, TypeError, ValueError, InvalidOperation) as exc:
        raise DeliveryRoundingError() from exc
    if any(not rate.is_finite() or rate < 0 for rate in rates.values()) or abs(sum(rates.values()) - 1) > Decimal("0.00000002"):
        raise DeliveryRoundingError()
    if not enabled:
        rates = {key: Decimal(1 if key == "driver_rate" else 0) for key in rates}

    price = Decimal(round_down(basis, increment))
    raw_driver = decimal_amount(basis * rates["driver_rate"])
    raw_origin = decimal_amount(basis * rates["origin_relay_rate"])
    raw_destination = decimal_amount(basis * rates["destination_relay_rate"])
    driver = Decimal(round_up(raw_driver, increment))
    origin = Decimal(round_down(raw_origin, increment))
    destination = Decimal(round_down(raw_destination, increment))
    platform = price - driver - origin - destination
    if platform < 0:
        raise DeliveryRoundingError(insufficient_margin=True)
    commission = price - driver
    theoretical_platform = basis - raw_driver - raw_origin - raw_destination
    contribution = max(Decimal(0), theoretical_platform - platform)

    return {
        "delivery_mode": mode,
        "price_xof": int(price),
        "platform_commission_xof": int(platform),
        "origin_relay_commission_xof": int(origin),
        "destination_relay_commission_xof": int(destination),
        "relay_commission_xof": int(origin + destination),
        "total_commission_xof": int(commission),
        "wallet_balance_required_xof": int(commission),
        "driver_revenue_xof": int(driver),
        "driver_revenue_rate": float(rates["driver_rate"]),
        "platform_rate": float(rates["platform_rate"]),
        "origin_relay_rate": float(rates["origin_relay_rate"]),
        "destination_relay_rate": float(rates["destination_relay_rate"]),
        "settlement_model": "origin_relay_collects" if mode == "relay_to_relay" else "driver_collects",
        "commission_rules_snapshot": commission_rules,
        "delivery_commissions_enabled": enabled,
        "rounding": {
            "version": POLICY_VERSION,
            "step_xof": int(increment),
            "basis_price_xof": float(basis),
            "customer_discount_xof": float(money(basis - price)),
            "driver_bonus_xof": float(money(driver - raw_driver)),
            "denkma_contribution_xof": float(money(contribution)),
            "relay_adjustment_xof": float(money(raw_origin + raw_destination - origin - destination)),
        },
    }


def validate_financial_rounding(snapshot: dict, *, price, mode: str) -> dict:
    rounding = snapshot.get("rounding") or {}
    if rounding.get("version") != POLICY_VERSION or snapshot.get("delivery_mode") != mode:
        raise DeliveryRoundingError()
    expected = build_financial_rounding(
        rounding.get("basis_price_xof"), mode, snapshot.get("commission_rules_snapshot"),
        enabled=snapshot.get("delivery_commissions_enabled", True), step=rounding.get("step_xof"),
    )
    if decimal_amount(price) != decimal_amount(expected["price_xof"]):
        raise DeliveryRoundingError()
    if any(decimal_amount(snapshot.get(key)) != decimal_amount(expected[key]) for key in AMOUNT_FIELDS):
        raise DeliveryRoundingError()
    for key in ("customer_discount_xof", "driver_bonus_xof", "denkma_contribution_xof", "relay_adjustment_xof"):
        if money(rounding.get(key)) != money(expected["rounding"][key]):
            raise DeliveryRoundingError()
    return expected


def financial_rounding_fields(quote_breakdown: dict | None) -> dict:
    snapshot = (quote_breakdown or {}).get("financial_rounding")
    if not snapshot:
        return {}
    return {
        "financial_rounding": snapshot,
        "commission_rules_snapshot": snapshot["commission_rules_snapshot"],
        "delivery_commissions_enabled": snapshot["delivery_commissions_enabled"],
    }
