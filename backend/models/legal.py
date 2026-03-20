from typing import Optional
from datetime import datetime
from pydantic import BaseModel, ConfigDict
from enum import Enum


class LegalDocumentType(str, Enum):
    PRIVACY_POLICY = "privacy_policy"
    CGU = "cgu"


class LegalContent(BaseModel):
    document_type: LegalDocumentType
    title: str
    content: str
    updated_at: datetime
    updated_by: Optional[str] = None # Admin user_id

    model_config = ConfigDict(populate_by_name=True)


class LegalContentUpdate(BaseModel):
    title: Optional[str] = None
    content: str
