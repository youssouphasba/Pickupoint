"""
Définit / réinitialise le mot de passe d'un administrateur existant.

Usage :
    cd backend
    python -m scripts.create_admin_password <email> <phone> [--superadmin]

L'utilisateur doit déjà exister en base (inscription mobile normale).
Le script met à jour le rôle en admin/superadmin (si demandé), rattache l'email,
et stocke un bcrypt hash du mot de passe.
"""
import asyncio
import sys
import getpass
from datetime import datetime, timezone

from core.security import hash_password
from database import connect_db, db
from models.common import UserRole


async def main() -> int:
    args = sys.argv[1:]
    if len(args) < 2:
        print("Usage: python -m scripts.create_admin_password <email> <phone> [--superadmin]")
        return 1

    email = args[0].strip().lower()
    phone = args[1].strip()
    promote_super = "--superadmin" in args

    await connect_db()

    user = await db.users.find_one({"phone": phone}, {"_id": 0})
    if not user:
        print(f"Aucun utilisateur avec le téléphone {phone} — inscris-toi d'abord sur mobile.")
        return 2

    password = getpass.getpass("Nouveau mot de passe admin (min 8): ")
    confirm = getpass.getpass("Confirmer: ")
    if password != confirm:
        print("Les mots de passe ne correspondent pas.")
        return 3
    if len(password) < 8:
        print("Minimum 8 caractères.")
        return 4

    new_role = UserRole.SUPERADMIN.value if promote_super else UserRole.ADMIN.value
    await db.users.update_one(
        {"user_id": user["user_id"]},
        {"$set": {
            "email": email,
            "role": new_role,
            "admin_password_hash": hash_password(password),
            "admin_password_set_at": datetime.now(timezone.utc),
        }},
    )
    print(f"OK — {email} configuré en {new_role}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
