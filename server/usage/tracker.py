"""
Usage tracker para Strata — Task 01-02

Registra el uso mensual en Modal Volume (strata-usage).
Proporciona:
  - record_usage(username, source_type, source_name): registra un procesamiento
  - get_usage(username): devuelve resumen del mes actual
  - FastAPI router con GET /usage (protegido por JWT)

Estructura de usage.json:
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

NOTA: Este modulo se usa en dos contextos:
  1. Contexto web (ASGI): get_usage() lee /data/usage.json via Volume montado en web handler
     (el Volume NO se monta en web — get_usage lee via modal.Volume.lookup si es necesario)
  2. Contexto GPU (process_job): record_usage() escribe en /data/usage.json (Volume montado)
"""

import json
import modal
from datetime import datetime, timezone
from pathlib import Path
from fastapi import APIRouter, Depends

# Modal Volume para persistencia de datos de uso entre deploys
# Se declara aqui para que app.py pueda referenciarla
usage_vol = modal.Volume.from_name("strata-usage", create_if_missing=True)

# Tasa Modal T4: $0.000164/s
MODAL_T4_RATE_PER_SECOND = 0.000164
# Segundos GPU estimados por procesamiento stub (equivalente real ~45s)
GPU_SECONDS_PER_SONG = 45
# Limite de gasto mensual
SPENDING_LIMIT_USD = 10.00

USAGE_FILE = Path("/data/usage.json")

router = APIRouter(tags=["usage"])


def _read_usage() -> dict:
    """Lee usage.json del Volume. Devuelve dict vacio si no existe."""
    try:
        with USAGE_FILE.open("r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        return {}


def _write_usage(data: dict) -> None:
    """Escribe usage.json en el Volume y hace commit."""
    USAGE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with USAGE_FILE.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    # Commit del Volume para persistir los cambios
    usage_vol.commit()


def record_usage(username: str, source_type: str, source_name: str) -> None:
    """Registra un procesamiento en usage.json.

    Incrementa songs_processed y gpu_seconds para el mes actual y el usuario.
    Debe llamarse desde una funcion Modal que tenga el Volume montado en /data.
    """
    now = datetime.now(timezone.utc)
    month_key = now.strftime("%Y-%m")

    data = _read_usage()

    # Inicializar estructura del mes si no existe
    if month_key not in data:
        data[month_key] = {
            "songs_processed": 0,
            "gpu_seconds": 0,
            "estimated_cost_usd": 0.0,
            "by_user": {},
        }

    month = data[month_key]

    # Incrementar totales del mes
    month["songs_processed"] += 1
    month["gpu_seconds"] += GPU_SECONDS_PER_SONG
    month["estimated_cost_usd"] = round(
        month["gpu_seconds"] * MODAL_T4_RATE_PER_SECOND, 4
    )

    # Incrementar totales por usuario
    if username not in month["by_user"]:
        month["by_user"][username] = {"songs": 0, "gpu_seconds": 0}

    month["by_user"][username]["songs"] += 1
    month["by_user"][username]["gpu_seconds"] += GPU_SECONDS_PER_SONG

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
    """Devuelve el resumen de uso del mes actual.

    Lee directamente desde el Volume si esta montado (/data),
    o devuelve ceros si no hay datos todavia.

    Formato de respuesta:
    {
      "month": "YYYY-MM",
      "songs_processed": N,
      "gpu_seconds": N,
      "estimated_cost_usd": float,
      "spending_limit_usd": 10.00
    }
    """
    now = datetime.now(timezone.utc)
    month_key = now.strftime("%Y-%m")

    data = _read_usage()
    month = data.get(month_key, {})

    return {
        "month": month_key,
        "songs_processed": month.get("songs_processed", 0),
        "gpu_seconds": month.get("gpu_seconds", 0),
        "estimated_cost_usd": month.get("estimated_cost_usd", 0.0),
        "spending_limit_usd": SPENDING_LIMIT_USD,
    }


# ---------------------------------------------------------------------------
# FastAPI endpoint
# ---------------------------------------------------------------------------

def _lazy_require_auth(credentials=None):
    """Dependencia lazy que delega a require_auth en auth.auth."""
    from auth.auth import require_auth
    from fastapi import Depends
    # FastAPI llama a esta funcion como dependency
    # Necesitamos que sea un callable que FastAPI pueda invocar como Depends
    # Pero esto no funciona directamente — se resuelve en el endpoint con la solucion de abajo
    return require_auth(credentials)


# Importamos require_auth aqui — este import ocurre cuando tracker.py se carga,
# lo que solo sucede desde web() (donde /root esta en sys.path) o desde process_job
# (donde sys.path ya tiene /root por el sys.path.insert al inicio de process_job)
from auth.auth import require_auth  # noqa: E402


@router.get("/usage")
def usage_endpoint(username: str = Depends(require_auth)):
    """Devuelve el uso mensual del usuario autenticado."""
    return get_usage(username)
