from datetime import datetime
from enum import Enum
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field, field_validator

from models.common import clean_optional_text


class NotificationChannel(str, Enum):
    SMS = "sms"
    WHATSAPP = "whatsapp"
    PUSH = "push"
    IN_APP = "in_app"


class NotificationStatus(str, Enum):
    PENDING = "pending"
    SENT = "sent"
    FAILED = "failed"
    READ = "read"


class Notification(BaseModel):
    notif_id: str
    user_id: str
    channel: NotificationChannel
    title: str = Field(..., min_length=1, max_length=120)
    body: str = Field(..., min_length=1, max_length=1000)
    status: NotificationStatus = NotificationStatus.PENDING
    metadata: Dict[str, Any] = Field(default_factory=dict)
    ref_type: Optional[str] = Field(default=None, max_length=64)
    ref_id: Optional[str] = Field(default=None, max_length=128)
    created_at: datetime
    sent_at: Optional[datetime] = None
    read_at: Optional[datetime] = None

    @field_validator("title", "body", "ref_type", "ref_id")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)
