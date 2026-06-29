from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

from models.common import clean_optional_text


class LegalDocumentType(str, Enum):
    PRIVACY_POLICY = "privacy_policy"
    CGU = "cgu"
    MENTIONS_LEGALES = "mentions_legales"


class LegalContent(BaseModel):
    document_type: LegalDocumentType
    title: str = Field(..., min_length=2, max_length=160)
    content: str = Field(..., min_length=1, max_length=60000)
    updated_at: datetime
    updated_by: Optional[str] = Field(default=None, max_length=80)

    model_config = ConfigDict(populate_by_name=True)


class LegalContentUpdate(BaseModel):
    title: Optional[str] = Field(default=None, max_length=160)
    content: str = Field(..., min_length=1, max_length=60000)

    @field_validator("title")
    @classmethod
    def normalize_title(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)
