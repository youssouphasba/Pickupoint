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
    promo_id:              Optional[str] = None  # Promotion appliquée
    # Codes de validation Sécurité (Phase 3)
    pickup_code:           str   = ""                          # 6 chiffres — expéditeur/relais -> livreur
    delivery_code:         str   = ""                          # 6 chiffres — destinataire -> livreur
    # Statut machine d'états
    status:                ParcelStatus = ParcelStatus.CREATED
    # Driver assigné
    assigned_driver_id:    Optional[str] = None
    # Redirection et Transit
    redirect_relay_id:     Optional[str] = None
    transit_relay_id:      Optional[str] = None
    # Notation & Pourboires (Phase 6)
    rating:                Optional[int]   = None  # 1-5
    rating_comment:        Optional[str]   = None
    driver_tip:            float           = 0.0   # XOF
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
    transit_relay_id:      Optional[str] = None
    origin_location:       Optional[Address] = None   # HOME_TO_* : GPS expéditeur capturé dans l'app
    weight_kg:             float = 0.5
    dimensions:            Optional[Dict[str, float]] = None
    declared_value:        Optional[float] = None
    is_insured:            bool = False
    description:           Optional[str] = None
    is_express:            bool = False
    who_pays:              str  = "sender"    # "sender" | "recipient"
    promo_id:              Optional[str] = None
    # GPS expéditeur (HOME_TO_* : capturé dans l'app)
    initiated_by:          str = "sender"    # "sender" | "recipient"
    sender_phone:          Optional[str] = None  # flux inverse : expéditeur non-app
    pickup_voice_note:     Optional[str] = None  # note vocale/textuelle expéditeur -> livreur
    delivery_voice_note:   Optional[str] = None  # note vocale/textuelle destinataire -> livreur


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
    promo_code:            Optional[str] = None


class QuoteResponse(BaseModel):
    price:          float
    currency:       str = "XOF"
    breakdown:      Dict[str, Any] = {}
    original_price: Optional[float] = None  # Si une promo est appliquée
    discount_xof:   float = 0.0
    promo_applied:  Optional[Dict[str, Any]] = None


class FailDeliveryRequest(BaseModel):
    failure_reason: str   # "absent", "address_not_found", "refused"
    notes:          Optional[str] = None


class RedirectRelayRequest(BaseModel):
    redirect_relay_id: str
    notes:             Optional[str] = None


class ParcelRatingRequest(BaseModel):
    rating:         int   # 1-5
    comment:        Optional[str] = None
    tip:            float = 0.0   # XOF pour le livreur


class DeliveryAddressUpdatePayload(BaseModel):
    lat:         float
    lng:         float
    accuracy:    Optional[float] = None
    label:       Optional[str] = None
    district:    Optional[str] = None
    city:        Optional[str] = "Dakar"
    voice_note:  Optional[str] = None

class LocationConfirmPayload(BaseModel):
    lat:       float
    lng:       float
    accuracy:  Optional[float] = None
    voice_note: Optional[str]  = None
