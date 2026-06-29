from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from models.common import clean_optional_text


class TransactionType(str, Enum):
    CREDIT = "credit"
    DEBIT = "debit"
    PENDING = "pending"
    REVENUE = "revenue"


class Wallet(BaseModel):
    wallet_id: str
    owner_id: str
    owner_type: str
    balance: float = 0.0
    pending: float = 0.0
    currency: str = "XOF"
    is_active: bool = True
    created_at: datetime
    updated_at: datetime


class WalletTransaction(BaseModel):
    tx_id: str
    wallet_id: str
    parcel_id: Optional[str] = None
    amount: float
    tx_type: TransactionType
    description: str = Field(..., min_length=1, max_length=500)
    reference: Optional[str] = Field(default=None, max_length=160)
    created_at: datetime

    @field_validator("description", "reference")
    @classmethod
    def normalize_text_fields(cls, value: Optional[str]) -> Optional[str]:
        return clean_optional_text(value)


class PayoutRequest(BaseModel):
    amount: float = Field(..., gt=0, le=100_000_000)
    method: str = Field(..., min_length=2, max_length=40)
    phone: str = Field(..., min_length=8, max_length=32)

    @field_validator("method", "phone")
    @classmethod
    def normalize_text_fields(cls, value: str) -> str:
        cleaned = clean_optional_text(value)
        if not cleaned:
            raise ValueError("Champ requis")
        return cleaned


class PayoutRecord(BaseModel):
    payout_id: str
    wallet_id: str
    owner_id: str
    amount: float
    method: str
    phone: str
    status: str = "pending"
    created_at: datetime
    updated_at: datetime
