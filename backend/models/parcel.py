from datetime import datetime
from typing import Optional, Dict, Any
from pydantic import BaseModel
from models.common import DeliveryMode, ParcelStatus, GeoPin, Address


class Parcel(BaseModel):
    parcel_id:      str
    tracking_code:  str        # "PKP-XXX-YYYY"
    # Acteurs
    sender_user_id:  str
    recipient_phone: str
    recipient_name:  str
    # Mode et relais
    delivery_mode:         DeliveryMode
    origin_relay_id:       Optional[str] = None
    destination_relay_id:  Optional[str] = None
    # Adresse domicile (si mode inclut livraison domicile)
    delivery_address:      Optional[Address] = None
    # Colis physique
    weight_kg:             float = 0.5
    dimensions:            Optional[Dict[str, float]] = None  # {"l": 30, "w": 20, "h": 10}
    declared_value:        Optional[float] = None              # XOF
    is_insured:            bool  = False
    description:           Optional[str] = None
    is_express:            bool  = False
    who_pays:              str   = "sender"    # "sender" | "recipient"
    # Prix et paiement
    quoted_price:          float                               # XOF
    paid_price:            Optional[float] = None
    payment_status:        str   = "pending"                   # "pending", "paid", "refunded"
    payment_method:        Optional[str] = None                # "wave", "orange_money", ...
    payment_ref:           Optional[str] = None
    # Codes de validation Sécurité (Phase 3)
    pickup_code:           str   = ""                          # 6 chiffres — expéditeur/relais -> livreur
    delivery_code:         str   = ""                          # 6 chiffres — destinataire -> livreur
    # Statut machine d'états
    status:                ParcelStatus = ParcelStatus.CREATED
    # Driver assigné
    assigned_driver_id:    Optional[str] = None
    # Redirection
    redirect_relay_id:     Optional[str] = None
    # Connexion projet_stock
    external_ref:          Optional[str] = None
    # Timestamps
    created_at:            datetime
    updated_at:            datetime
    expires_at:            Optional[datetime] = None


class ParcelCreate(BaseModel):
    recipient_phone:       str
    recipient_name:        str
    delivery_mode:         DeliveryMode
    origin_relay_id:       Optional[str] = None
    destination_relay_id:  Optional[str] = None
    delivery_address:      Optional[Address] = None
    origin_location:       Optional[Address] = None   # HOME_TO_* : GPS expéditeur capturé dans l'app
    weight_kg:             float = 0.5
    dimensions:            Optional[Dict[str, float]] = None
    declared_value:        Optional[float] = None
    is_insured:            bool = False
    description:           Optional[str] = None
    is_express:            bool = False
    who_pays:              str  = "sender"    # "sender" | "recipient"
    # GPS expéditeur (HOME_TO_* : capturé dans l'app)
    initiated_by:          str = "sender"    # "sender" | "recipient"
    sender_phone:          Optional[str] = None  # flux inverse : expéditeur non-app


class ParcelEvent(BaseModel):
    event_id:    str
    parcel_id:   str
    event_type:  str            # "STATUS_CHANGED", "PAYMENT_RECEIVED", "REDIRECTED", ...
    from_status: Optional[ParcelStatus] = None
    to_status:   Optional[ParcelStatus] = None
    actor_id:    Optional[str] = None
    actor_role:  Optional[str] = None
    location:    Optional[GeoPin] = None
    notes:       Optional[str] = None
    metadata:    Dict[str, Any] = {}
    created_at:  datetime


class ParcelQuote(BaseModel):
    delivery_mode:         DeliveryMode
    origin_relay_id:       Optional[str] = None
    destination_relay_id:  Optional[str] = None
    origin_location:       Optional[Address] = None   # HOME_TO_* : GPS expéditeur
    delivery_address:      Optional[Address] = None
    weight_kg:             float = 0.5
    is_insured:            bool  = False
    declared_value:        Optional[float] = None
    is_express:            bool  = False
    who_pays:              str   = "sender"    # "sender" | "recipient"


class QuoteResponse(BaseModel):
    price:     float
    currency:  str = "XOF"
    breakdown: Dict[str, Any] = {}


class FailDeliveryRequest(BaseModel):
    failure_reason: str   # "absent", "address_not_found", "refused"
    notes:          Optional[str] = None


class RedirectRelayRequest(BaseModel):
    redirect_relay_id: str
    notes:             Optional[str] = None
