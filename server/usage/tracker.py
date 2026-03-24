"""
Usage tracker para Siyahamba

Registra canciones procesadas en Modal Volume (siyahamba-usage) para rate limiting.
El credito restante se calcula via modal.billing.workspace_billing_report() con datos
reales del workspace (plan Starter: $30/mes).

Proporciona:
  - record_usage(username, source_type, source_name, gpu_seconds): registra procesamiento
  - get_usage(username): devuelve credito restante via Modal billing API
  - FastAPI router con GET /usage (protegido por JWT)

Estructura de usage.json (para rate limiting interno):
{
  "YYYY-MM": {
    "songs_processed": N,
    "gpu_seconds": N,
    "estimated_cost_usd": float,
    "by_user": {
      "username": {"songs": N, "gpu_seconds": N}
    }
  }
}
"""

import json
import modal
from datetime import datetime, timezone
from pathlib import Path

MODAL_T4_RATE_PER_SECOND = 0.000164
CONTAINER_OVERHEAD_USD = 0.08
GPU_SECONDS_PER_SONG = 45
SPENDING_LIMIT_USD = 10.00
MONTHLY_CREDIT_USD = 30.0

USAGE_FILE = Path("/data/usage.json")

usage_vol = modal.Volume.from_name("siyahamba-usage")


def _read_usage() -> dict:
    try:
        with USAGE_FILE.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _write_usage(data: dict) -> None:
    USAGE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with USAGE_FILE.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    usage_vol.commit()


def _estimate_cost(songs: int, gpu_seconds: float) -> float:
    """Estima coste real: overhead por contenedor + GPU de procesamiento.

    CONTAINER_OVERHEAD_USD ($0.12) cubre cold start (~90s cargando modelos)
    + scaledown_window (300s idle) por activacion de contenedor.
    Calibrado con datos reales de Modal billing (marzo 2026).
    """
    return round(songs * CONTAINER_OVERHEAD_USD + gpu_seconds * MODAL_T4_RATE_PER_SECOND, 4)


def record_usage(username: str, source_type: str, source_name: str, gpu_seconds: float | None = None) -> None:
    """Registra un procesamiento en usage.json."""
    actual_gpu_seconds = gpu_seconds if gpu_seconds is not None else GPU_SECONDS_PER_SONG
    now = datetime.now(timezone.utc)
    month_key = now.strftime("%Y-%m")

    data = _read_usage()

    if month_key not in data:
        data[month_key] = {
            "songs_processed": 0,
            "gpu_seconds": 0,
            "estimated_cost_usd": 0.0,
            "by_user": {},
        }

    month = data[month_key]

    month["songs_processed"] += 1
    month["gpu_seconds"] += actual_gpu_seconds
    month["estimated_cost_usd"] = _estimate_cost(month["songs_processed"], month["gpu_seconds"])

    if username not in month["by_user"]:
        month["by_user"][username] = {"songs": 0, "gpu_seconds": 0}

    month["by_user"][username]["songs"] += 1
    month["by_user"][username]["gpu_seconds"] += actual_gpu_seconds

    _write_usage(data)


def check_limit(username: str) -> bool:
    """Devuelve True si el gasto estimado del mes actual supera SPENDING_LIMIT_USD."""
    now = datetime.now(timezone.utc)
    month_key = now.strftime("%Y-%m")

    data = _read_usage()
    month = data.get(month_key, {})
    estimated_cost = month.get("estimated_cost_usd", 0.0)

    return estimated_cost >= SPENDING_LIMIT_USD


def get_usage(username: str) -> dict:
    """Devuelve credito restante del mes actual via Modal billing API.

    Usa workspace_billing_report() para obtener datos reales de coste.
    Fallback: estimacion local si la API de billing no esta disponible.
    """
    from datetime import timedelta

    now = datetime.now(timezone.utc)
    month_key = now.strftime("%Y-%m")
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    end = now

    try:
        from modal.billing import workspace_billing_report
        report = workspace_billing_report(start=start, end=end)
        total_spent = sum(
            item.cost if hasattr(item, "cost") else item.get("cost", 0.0)
            for item in report
        )
        credit_remaining = max(0.0, MONTHLY_CREDIT_USD - total_spent)
        return {
            "month": month_key,
            "credit_remaining_usd": round(credit_remaining, 2),
            "monthly_credit_usd": MONTHLY_CREDIT_USD,
            "total_spent_usd": round(total_spent, 2),
        }
    except Exception:
        data = _read_usage()
        month = data.get(month_key, {})
        estimated = month.get("estimated_cost_usd", 0.0)
        credit_remaining = max(0.0, MONTHLY_CREDIT_USD - estimated)
        return {
            "month": month_key,
            "credit_remaining_usd": round(credit_remaining, 2),
            "monthly_credit_usd": MONTHLY_CREDIT_USD,
            "total_spent_usd": round(estimated, 2),
        }


# ---------------------------------------------------------------------------
# FastAPI endpoint — solo se usa en el web container (tiene fastapi instalado)
# ---------------------------------------------------------------------------

def build_router():
    """Construye el router FastAPI. Llamar solo desde el web container."""
    from fastapi import APIRouter, Depends
    from auth.auth import require_auth

    router = APIRouter(tags=["usage"])

    @router.get("/usage")
    def usage_endpoint(username: str = Depends(require_auth)):
        usage_vol.reload()
        return get_usage(username)

    return router
