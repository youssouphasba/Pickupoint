from enum import Enum
from typing import Optional
from pydantic import BaseModel


class DeliveryMode(str, Enum):
    RELAY_TO_RELAY = "relay_to_relay"
    RELAY_TO_HOME  = "relay_to_home"
    HOME_TO_RELAY  = "home_to_relay"   # Phase 2
    HOME_TO_HOME   = "home_to_home"    # Phase 2


class RelayType(str, Enum):
    STANDARD = "standard"
    MOBILE   = "mobile"   # Bus / Transporteur inter-urbain
    STATION  = "station"  # Gare / Point de transit majeur


class ParcelStatus(str, Enum):
    CREATED                  = "created"
    DROPPED_AT_ORIGIN_RELAY  = "dropped_at_origin_relay"
    IN_TRANSIT               = "in_transit"
    AT_DESTINATION_RELAY     = "at_destination_relay"
    AVAILABLE_AT_RELAY       = "available_at_relay"
    OUT_FOR_DELIVERY         = "out_for_delivery"
    DELIVERED                = "delivered"
    DELIVERY_FAILED          = "delivery_failed"
    REDIRECTED_TO_RELAY      = "redirected_to_relay"
    CANCELLED                = "cancelled"
    EXPIRED                  = "expired"
    DISPUTED                 = "disputed"
    RETURNED                 = "returned"


class UserRole(str, Enum):
    CLIENT      = "client"
    RELAY_AGENT = "relay_agent"
    DRIVER      = "driver"
    ADMIN       = "admin"
    SUPERADMIN  = "superadmin"


class GeoPin(BaseModel):
    lat: float
    lng: float
    accuracy: Optional[float] = None  # mètres


class Address(BaseModel):
    label:    Optional[str]    = None   # "Quartier Plateau, près de la mairie"
    geopin:   Optional[GeoPin] = None   # obligatoire pour livraison domicile
    city:     str              = "Dakar"
    district: Optional[str]   = None   # quartier
    notes:    Optional[str]   = None   # instructions livreur
