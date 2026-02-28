from datetime import datetime
from enum import Enum
from typing import Optional
from pydantic import BaseModel


class TransactionType(str, Enum):
    CREDIT  = "credit"   # gains
    DEBIT   = "debit"    # retraits
    PENDING = "pending"  # en attente de validation


class Wallet(BaseModel):
    wallet_id:  str
    owner_id:   str       # user_id
    owner_type: str       # "driver", "relay"
    balance:    float = 0.0    # XOF
    pending:    float = 0.0    # XOF en attente
    currency:   str = "XOF"
    is_active:  bool = True
    created_at: datetime
    updated_at: datetime


class WalletTransaction(BaseModel):
    tx_id:       str
    wallet_id:   str
    parcel_id:   Optional[str] = None
    amount:      float
    tx_type:     TransactionType
    description: str
    reference:   Optional[str] = None
    created_at:  datetime


class PayoutRequest(BaseModel):
    amount: float
    method: str    # "wave", "orange_money", "free_money"
    phone:  str    # compte de réception


class PayoutRecord(BaseModel):
    payout_id:  str
    wallet_id:  str
    owner_id:   str
    amount:     float
    method:     str
    phone:      str
    status:     str = "pending"   # "pending", "approved", "rejected"
    created_at: datetime
    updated_at: datetime
