# Modulo de autenticacion para Strata
#
# Contrasenas de prueba (desarrollo):
#   papa: papa123
#   hijo: hijo123
#
# En produccion, regenerar hashes y actualizar users.json antes de desplegar.

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import bcrypt
import jwt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel

router = APIRouter(prefix="/auth", tags=["auth"])

# JWT Secret: leer de variable de entorno, fallback a secreto de desarrollo
JWT_SECRET = os.environ.get("JWT_SECRET", "dev-secret-change-in-prod")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_DAYS = 90

# Ruta al fichero de usuarios (junto al modulo auth)
USERS_FILE = Path(__file__).parent / "users.json"

_bearer = HTTPBearer(auto_error=False)


class LoginRequest(BaseModel):
    password: str


def _load_users() -> list[dict]:
    """Carga la lista de usuarios desde el fichero JSON."""
    with USERS_FILE.open("r", encoding="utf-8") as f:
        return json.load(f)


@router.post("/login")
def login(body: LoginRequest):
    """Autenticacion con solo contrasena.

    Itera todos los usuarios y comprueba el hash bcrypt.
    Devuelve un JWT de 90 dias si hay match; 401 si no.
    """
    users = _load_users()
    password_bytes = body.password.encode("utf-8")

    matched_username: str | None = None
    for user in users:
        stored_hash = user["password_hash"].encode("utf-8")
        if bcrypt.checkpw(password_bytes, stored_hash):
            matched_username = user["username"]
            break

    if matched_username is None:
        raise HTTPException(status_code=401, detail="Contrasena incorrecta")

    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=JWT_EXPIRY_DAYS)
    payload = {
        "sub": matched_username,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

    return {"token": token, "expires_in": JWT_EXPIRY_DAYS * 24 * 3600}


def require_auth(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    """Dependencia FastAPI que valida el JWT Bearer token.

    Devuelve el username (payload['sub']) si el token es valido.
    Lanza 401 en cualquier otro caso.
    """
    if credentials is None:
        raise HTTPException(status_code=401, detail="Token requerido")

    token = credentials.credentials
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload["sub"]
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expirado")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Token invalido")


@router.post("/renew")
def renew_token(username: str = Depends(require_auth)):
    """Renueva el JWT del usuario autenticado.

    El cliente envia el JWT vigente en Authorization: Bearer.
    require_auth lo valida y devuelve el username.
    Se emite un nuevo JWT con 90 dias desde ahora — renovacion stateless.
    """
    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=JWT_EXPIRY_DAYS)
    payload = {
        "sub": username,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    return {"token": token, "expires_in": JWT_EXPIRY_DAYS * 24 * 3600}
