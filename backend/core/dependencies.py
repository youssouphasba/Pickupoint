from typing import Optional
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from core.security import verify_access_token
from core.exceptions import credentials_exception, forbidden_exception
from database import db
from models.common import UserRole

bearer_scheme = HTTPBearer(auto_error=False)

ADMIN_COOKIE_NAME = "denkma_admin_session"


def _extract_token(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials],
) -> Optional[str]:
    """Prend le token dans l'Authorization header (mobile) ou le cookie admin (web)."""
    if credentials and credentials.credentials:
        return credentials.credentials
    cookie = request.cookies.get(ADMIN_COOKIE_NAME)
    return cookie or None


async def get_current_user(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> dict:
    token = _extract_token(request, credentials)
    if not token:
        raise credentials_exception()
    payload = verify_access_token(token)
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
    if user.get("is_banned"):
        raise forbidden_exception("Compte suspendu par l'administration")
    return user


async def get_current_user_optional(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> Optional[dict]:
    """Version optionnelle de get_current_user (ne lève pas d'erreur si anonyme)."""
    token = _extract_token(request, credentials)
    if not token:
        return None
    try:
        payload = verify_access_token(token)
        if not payload:
            return None
        user_id = payload.get("sub")
        if not user_id:
            return None
        user = await db.users.find_one({"user_id": user_id}, {"_id": 0})
        if not user or not user.get("is_active", True) or user.get("is_banned"):
            return None
        return user
    except Exception:
        return None


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
