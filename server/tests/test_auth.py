"""Tests para el endpoint POST /auth/renew en server/auth/auth.py.

Usa TestClient de FastAPI (sin Modal) montando un router de auth directamente.
El endpoint /auth/renew aun no existe — estos tests fallan en fase RED.
"""
import time
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

# Importar el router de auth directamente (sin Modal)
from server.auth.auth import router, JWT_SECRET, JWT_ALGORITHM, JWT_EXPIRY_DAYS


@pytest.fixture
def app():
    """FastAPI app minima con el router de auth montado."""
    _app = FastAPI()
    _app.include_router(router)
    return _app


@pytest.fixture
def client(app):
    """TestClient para la app de auth."""
    return TestClient(app)


def make_valid_token(username: str = "papa", expires_in_days: int = 90) -> str:
    """Genera un JWT valido firmado con el mismo secreto que el servidor."""
    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=expires_in_days)
    payload = {
        "sub": username,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def make_expired_token(username: str = "papa") -> str:
    """Genera un JWT con exp en el pasado."""
    now = datetime.now(timezone.utc)
    exp = now - timedelta(hours=1)  # ya expirado
    payload = {
        "sub": username,
        "iat": int((now - timedelta(hours=2)).timestamp()),
        "exp": int(exp.timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


# ---------------------------------------------------------------------------
# Tests de POST /auth/renew
# ---------------------------------------------------------------------------

class TestRenewEndpoint:
    """Tests para POST /auth/renew."""

    def test_renew_ok_returns_200_with_token(self, client):
        """Renovacion exitosa: token valido → 200 con nuevo 'token'."""
        valid_token = make_valid_token("papa")

        response = client.post(
            "/auth/renew",
            headers={"Authorization": f"Bearer {valid_token}"},
        )

        assert response.status_code == 200
        data = response.json()
        assert "token" in data
        assert isinstance(data["token"], str)
        assert len(data["token"]) > 0

    def test_renew_ok_returns_expires_in(self, client):
        """La respuesta de renovacion incluye expires_in = 90 dias en segundos."""
        valid_token = make_valid_token("papa")

        response = client.post(
            "/auth/renew",
            headers={"Authorization": f"Bearer {valid_token}"},
        )

        assert response.status_code == 200
        data = response.json()
        assert data["expires_in"] == JWT_EXPIRY_DAYS * 24 * 3600

    def test_renew_new_token_has_same_sub(self, client):
        """El nuevo JWT tiene el mismo 'sub' (username) que el token entrante."""
        username = "papa"
        valid_token = make_valid_token(username)

        response = client.post(
            "/auth/renew",
            headers={"Authorization": f"Bearer {valid_token}"},
        )

        assert response.status_code == 200
        new_token = response.json()["token"]
        decoded = jwt.decode(new_token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        assert decoded["sub"] == username

    def test_renew_new_token_has_fresh_expiry(self, client):
        """El nuevo JWT tiene exp = ahora + 90 dias (renovacion completa)."""
        valid_token = make_valid_token("papa")
        before = int(time.time())

        response = client.post(
            "/auth/renew",
            headers={"Authorization": f"Bearer {valid_token}"},
        )

        after = int(time.time())
        assert response.status_code == 200
        new_token = response.json()["token"]
        decoded = jwt.decode(new_token, JWT_SECRET, algorithms=[JWT_ALGORITHM])

        expected_min = before + JWT_EXPIRY_DAYS * 24 * 3600
        expected_max = after + JWT_EXPIRY_DAYS * 24 * 3600
        assert expected_min <= decoded["exp"] <= expected_max

    def test_renew_with_expired_token_returns_401(self, client):
        """Token expirado → 401."""
        expired_token = make_expired_token("papa")

        response = client.post(
            "/auth/renew",
            headers={"Authorization": f"Bearer {expired_token}"},
        )

        assert response.status_code == 401

    def test_renew_without_header_returns_401(self, client):
        """Sin Authorization header → 401."""
        response = client.post("/auth/renew")

        assert response.status_code == 401

    def test_renew_with_corrupt_token_returns_401(self, client):
        """Token con firma invalida → 401."""
        response = client.post(
            "/auth/renew",
            headers={"Authorization": "Bearer not.a.valid.jwt.at.all"},
        )

        assert response.status_code == 401

    def test_renew_with_wrong_secret_returns_401(self, client):
        """Token firmado con secreto diferente → 401."""
        payload = {
            "sub": "papa",
            "iat": int(time.time()),
            "exp": int(time.time()) + 86400,
        }
        wrong_token = jwt.encode(payload, "wrong-secret", algorithm=JWT_ALGORITHM)

        response = client.post(
            "/auth/renew",
            headers={"Authorization": f"Bearer {wrong_token}"},
        )

        assert response.status_code == 401
