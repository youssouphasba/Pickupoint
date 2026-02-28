from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from core.security import verify_access_token
from core.exceptions import credentials_exception, forbidden_exception
from database import db
from models.common import UserRole

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> dict:
    if not credentials:
        raise credentials_exception()
    payload = verify_access_token(credentials.credentials)
    if not payload:
        raise credentials_exception()

    user_id = payload.get("sub")
    if not user_id:
        raise credentials_exception()

    user = await db.users.find_one({"user_id": user_id}, {"_id": 0})
    if not user:
        raise credentials_exception()
    if not user.get("is_active", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Compte désactivé",
        )
    return user


def require_role(*roles: UserRole):
    """
    Dépendance qui vérifie que l'utilisateur connecté possède l'un des rôles donnés.
    Usage : Depends(require_role(UserRole.ADMIN, UserRole.SUPERADMIN))
    """
    async def _check(current_user: dict = Depends(get_current_user)) -> dict:
        if current_user.get("role") not in [r.value for r in roles]:
            raise forbidden_exception()
        return current_user
    return _check


# Raccourcis pratiques
require_admin = require_role(UserRole.ADMIN, UserRole.SUPERADMIN)
require_relay_agent = require_role(UserRole.RELAY_AGENT, UserRole.ADMIN, UserRole.SUPERADMIN)
require_driver = require_role(UserRole.DRIVER, UserRole.ADMIN, UserRole.SUPERADMIN)
