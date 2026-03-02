from datetime import datetime
from typing import Optional, List, Dict
from pydantic import BaseModel
from models.common import Address, RelayType


class RelayPoint(BaseModel):
    relay_id:         str
    owner_user_id:    str
    agent_user_ids:   List[str] = []
    name:             str
    address:          Address
    relay_type:       RelayType = RelayType.STANDARD
    phone:            str
    description:      Optional[str] = None
    # Capacité et horaires
    max_capacity:     int = 20
    current_load:     int = 0
    opening_hours:    Optional[Dict[str, str]] = None  # {"mon": "08:00-20:00", ...}
    # Zone de couverture
    zone_ids:         List[str] = []
    coverage_radius_km: float = 5.0
    # Scoring et statut
    is_active:        bool  = True
    is_verified:      bool  = False
    score:            float = 5.0
    # Connexion projet_stock
    store_id:         Optional[str] = None
    external_ref:     Optional[str] = None
    # Timestamps
    created_at:       datetime
    updated_at:       datetime


class RelayPointCreate(BaseModel):
    name:          str
    address:       Address
    relay_type:    RelayType = RelayType.STANDARD
    phone:         str
    description:   Optional[str] = None
    max_capacity:  int = 20
    opening_hours: Optional[Dict[str, str]] = None
    store_id:      Optional[str] = None


class RelayPointUpdate(BaseModel):
    name:          Optional[str]             = None
    address:       Optional[Address]         = None
    phone:         Optional[str]             = None
    description:   Optional[str]             = None
    max_capacity:  Optional[int]             = None
    opening_hours: Optional[Dict[str, str]] = None
    relay_type:    Optional[RelayType]      = None
    is_active:     Optional[bool]            = None
