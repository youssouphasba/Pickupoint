from copy import deepcopy

from database import db
from services.loyalty_rules import DEFAULT_LOYALTY_TIERS, normalize_loyalty_tiers
from core.exceptions import bad_request_exception
from math import isfinite


DEFAULT_PERFORMANCE_REWARDS = {
    "driver": {
        "monthly_goal_deliveries": 20,
        "success_bonus": {
            "enabled": False,
            "min_success_rate": 95,
            "min_deliveries": 20,
            "amount_xof": 5000,
        },
        "volume_bonuses": [],
    },
    "relay": {
        "volume_bonuses": [],
    },
    "client": {
        "loyalty_points_per_delivered_parcel": 10,
        "loyalty_tiers": DEFAULT_LOYALTY_TIERS,
        "monthly_goal_sent_parcels": 5,
    },
}


def _positive_int(value, fallback=0):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return fallback
    return max(parsed, 0)


def normalize_performance_rewards(raw: dict | None) -> dict:
    raw = raw or {}
    cfg = deepcopy(DEFAULT_PERFORMANCE_REWARDS)

    driver = raw.get("driver") if isinstance(raw.get("driver"), dict) else {}
    cfg["driver"]["monthly_goal_deliveries"] = max(
        _positive_int(driver.get("monthly_goal_deliveries"), cfg["driver"]["monthly_goal_deliveries"]),
        1,
    )
    success_bonus = driver.get("success_bonus") if isinstance(driver.get("success_bonus"), dict) else {}
    cfg["driver"]["success_bonus"] = {
        "enabled": bool(success_bonus.get("enabled", cfg["driver"]["success_bonus"]["enabled"])),
        "min_success_rate": min(
            max(_positive_int(success_bonus.get("min_success_rate"), cfg["driver"]["success_bonus"]["min_success_rate"]), 0),
            100,
        ),
        "min_deliveries": max(
            _positive_int(success_bonus.get("min_deliveries"), cfg["driver"]["success_bonus"]["min_deliveries"]),
            1,
        ),
        "amount_xof": _positive_int(success_bonus.get("amount_xof"), cfg["driver"]["success_bonus"]["amount_xof"]),
    }
    driver_volume = driver.get("volume_bonuses") if isinstance(driver.get("volume_bonuses"), list) else []
    if isinstance(driver.get("volume_bonuses"), list):
        cfg["driver"]["volume_bonuses"] = sorted(
            [
                {
                    "min_deliveries": max(_positive_int(item.get("min_deliveries"), 0), 1),
                    "amount_xof": _positive_int(item.get("amount_xof"), 0),
                }
                for item in driver_volume
                if isinstance(item, dict) and _positive_int(item.get("amount_xof"), 0) > 0
            ],
            key=lambda item: item["min_deliveries"],
        )

    relay = raw.get("relay") if isinstance(raw.get("relay"), dict) else {}
    relay_volume = relay.get("volume_bonuses") if isinstance(relay.get("volume_bonuses"), list) else []
    if isinstance(relay.get("volume_bonuses"), list):
        cfg["relay"]["volume_bonuses"] = sorted(
            [
                {
                    "min_parcels": max(_positive_int(item.get("min_parcels"), 0), 1),
                    "amount_xof": _positive_int(item.get("amount_xof"), 0),
                }
                for item in relay_volume
                if isinstance(item, dict) and _positive_int(item.get("amount_xof"), 0) > 0
            ],
            key=lambda item: item["min_parcels"],
        )

    client = raw.get("client") if isinstance(raw.get("client"), dict) else {}
    cfg["client"]["loyalty_tiers"] = normalize_loyalty_tiers(client.get("loyalty_tiers"))
    cfg["client"]["loyalty_points_per_delivered_parcel"] = max(
        _positive_int(
            client.get("loyalty_points_per_delivered_parcel"),
            cfg["client"]["loyalty_points_per_delivered_parcel"],
        ),
        1,
    )
    cfg["client"]["monthly_goal_sent_parcels"] = max(
        _positive_int(client.get("monthly_goal_sent_parcels"), cfg["client"]["monthly_goal_sent_parcels"]),
        1,
    )

    return cfg


async def get_performance_rewards_settings() -> dict:
    settings_doc = await db.app_settings.find_one({"key": "global"}, {"_id": 0}) or {}
    return normalize_performance_rewards(settings_doc.get("performance_rewards"))


async def set_performance_rewards_settings(body: dict) -> dict:
    raw_tiers = (body.get("client") or {}).get("loyalty_tiers")
    if raw_tiers is not None:
        try:
            if not isinstance(raw_tiers, list) or len(raw_tiers) != len(DEFAULT_LOYALTY_TIERS):
                raise ValueError()
            previous_threshold, previous_discount = -1, 0
            for item, default in zip(raw_tiers, DEFAULT_LOYALTY_TIERS):
                threshold = int(item["min_points"])
                discount = float(item["discount_percent"])
                if item["key"] != default["key"] or threshold != item["min_points"] or threshold <= previous_threshold:
                    raise ValueError()
                if default["key"] == "bronze" and threshold != 0:
                    raise ValueError()
                if not isfinite(discount) or not previous_discount <= discount <= 100:
                    raise ValueError()
                previous_threshold, previous_discount = threshold, discount
        except (ValueError, TypeError, KeyError, OverflowError):
            raise bad_request_exception("Les seuils doivent augmenter de Bronze à Or, et les réductions être croissantes entre 0 et 100 %.")
    cfg = normalize_performance_rewards(body)
    return cfg
