from datetime import datetime, timezone
from enum import Enum
from typing import List, Optional
from uuid import uuid4

from pydantic import BaseModel, Field, HttpUrl, field_validator


class CampaignTargetRole(str, Enum):
    ALL = "all"
    CLIENT = "client"
    DRIVER = "driver"
    RELAY_AGENT = "relay_agent"


class CampaignActionType(str, Enum):
    INTERNAL_ROUTE = "internal_route"
    EXTERNAL_URL = "external_url"


class InAppCampaignCreate(BaseModel):
    title: str
    body: str
    cta_label: str = "Voir"
    image_url: Optional[HttpUrl] = None
    target_roles: List[CampaignTargetRole] = Field(
        default_factory=lambda: [CampaignTargetRole.ALL]
    )
    action_type: CampaignActionType = CampaignActionType.INTERNAL_ROUTE
    action_value: str
    start_date: datetime
    end_date: datetime
    priority: int = 0
    is_active: bool = True

    @field_validator("title", "body", "cta_label", "action_value")
    @classmethod
    def _not_empty(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Champ obligatoire")
        return cleaned

    @field_validator("target_roles")
    @classmethod
    def _dedupe_roles(
        cls,
        value: List[CampaignTargetRole],
    ) -> List[CampaignTargetRole]:
        if not value:
            return [CampaignTargetRole.ALL]
        if CampaignTargetRole.ALL in value:
            return [CampaignTargetRole.ALL]
        return list(dict.fromkeys(value))


class InAppCampaignUpdate(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    cta_label: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    target_roles: Optional[List[CampaignTargetRole]] = None
    action_type: Optional[CampaignActionType] = None
    action_value: Optional[str] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    priority: Optional[int] = None
    is_active: Optional[bool] = None

    @field_validator("title", "body", "cta_label", "action_value")
    @classmethod
    def _not_empty(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return value
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Champ obligatoire")
        return cleaned

    @field_validator("target_roles")
    @classmethod
    def _dedupe_roles(
        cls,
        value: Optional[List[CampaignTargetRole]],
    ) -> Optional[List[CampaignTargetRole]]:
        if value is None:
            return value
        if not value or CampaignTargetRole.ALL in value:
            return [CampaignTargetRole.ALL]
        return list(dict.fromkeys(value))


class InAppCampaign(InAppCampaignCreate):
    campaign_id: str = Field(default_factory=lambda: f"camp_{uuid4().hex[:12]}")
    impressions_count: int = 0
    clicks_count: int = 0
    created_by: str = ""
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
