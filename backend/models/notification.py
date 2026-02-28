from datetime import datetime
from enum import Enum
from typing import Optional, Dict, Any
from pydantic import BaseModel


class NotificationChannel(str, Enum):
    SMS       = "sms"
    WHATSAPP  = "whatsapp"
    PUSH      = "push"
    IN_APP    = "in_app"


class NotificationStatus(str, Enum):
    PENDING   = "pending"
    SENT      = "sent"
    FAILED    = "failed"
    READ      = "read"


class Notification(BaseModel):
    notif_id:   str
    user_id:    str
    channel:    NotificationChannel
    title:      str
    body:       str
    status:     NotificationStatus = NotificationStatus.PENDING
    metadata:   Dict[str, Any] = {}
    # Lien contextuel (ex: parcel_id, mission_id)
    ref_type:   Optional[str] = None   # "parcel", "mission", "payout"
    ref_id:     Optional[str] = None
    # Timestamps
    created_at: datetime
    sent_at:    Optional[datetime] = None
    read_at:    Optional[datetime] = None
