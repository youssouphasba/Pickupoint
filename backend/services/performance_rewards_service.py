from copy import deepcopy

from database import db


DEFAULT_PERFORMANCE_REWARDS = {
    "driver": {
        "monthly_goal_deliveries": 20,
        "success_bonus": {
            "enabled": True,
            "min_success_rate": 95,
            "min_deliveries": 20,
            "amount_xof": 5000,
        },
        "volume_bonuses": [
            {"min_deliveries": 50, "amount_xof": 2500},
            {"min_deliveries": 100, "amount_xof": 5000},
            {"min_deliveries": 200, "amount_xof": 10000},
        ],
    },
    "relay": {
        "volume_bonuses": [
            {"min_parcels": 20, "amount_xof": 1000},
            {"min_parcels": 50, "amount_xof": 2000},
        ],
    },
    "client": {
        "loyalty_points_per_delivered_parcel": 10,
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
    if driver_volume:
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
    if relay_volume:
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
    cfg = normalize_performance_rewards(body)
    return cfg
