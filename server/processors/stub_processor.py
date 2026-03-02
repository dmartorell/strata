"""
Stub processor HTTP endpoints para Strata — Task 01-02

FastAPI router con:
  - POST /process-file: acepta archivo de audio, lanza job, devuelve job_id
  - POST /process-url: acepta URL, lanza job, devuelve job_id
  - GET /result/{job_id}: devuelve progreso o ZIP cuando completado

La funcion de procesamiento real (process_job) esta en app.py como Modal function
top-level. Estos endpoints son solo el HTTP handler (ASGI web container).

Re-exporta build_stub_zip de stub_builder para compatibilidad.
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from fastapi.responses import Response
from auth.auth import require_auth
from processors.stub_builder import build_stub_zip  # noqa: F401 (re-export)

router = APIRouter(tags=["processor"])


def _get_job_dict():
    """Obtiene el modal.Dict de progreso de jobs."""
    import modal
    return modal.Dict.from_name("strata-job-progress", create_if_missing=True)


@router.post("/process-file")
async def process_file(
    audio_file: UploadFile,
    username: str = Depends(require_auth),
):
    """Acepta un archivo de audio, lanza job stub y devuelve job_id."""
    import modal

    job_dict = _get_job_dict()
    process_fn = modal.Function.from_name("strata", "process_job")

    call = await process_fn.spawn.aio(
        source_type="file",
        source_name=audio_file.filename or "upload.mp3",
        username=username,
    )
    job_id = call.object_id
    job_dict[job_id] = "queued"
    return {"job_id": job_id}


@router.post("/process-url")
async def process_url(
    body: dict,
    username: str = Depends(require_auth),
):
    """Acepta una URL, lanza job stub y devuelve job_id."""
    import modal

    url = body.get("url", "")
    if not url:
        raise HTTPException(status_code=400, detail="URL requerida")

    job_dict = _get_job_dict()
    process_fn = modal.Function.from_name("strata", "process_job")

    call = await process_fn.spawn.aio(
        source_type="youtube",
        source_name=url,
        username=username,
    )
    job_id = call.object_id
    job_dict[job_id] = "queued"
    return {"job_id": job_id}


@router.get("/result/{job_id}")
async def get_result(
    job_id: str,
    username: str = Depends(require_auth),
):
    """Devuelve progreso o ZIP cuando el job esta completado."""
    import modal

    job_dict = _get_job_dict()

    try:
        status = job_dict.get(job_id, "unknown")
    except Exception:
        status = "unknown"

    if status != "completed":
        return {"status": status if status != "unknown" else "processing", "job_id": job_id}

    # Job completado — obtener resultado
    try:
        call = modal.FunctionCall.from_id(job_id)
        result = await call.get.aio(timeout=0)
        return Response(
            content=result,
            media_type="application/zip",
            headers={"Content-Disposition": "attachment; filename=result.zip"},
        )
    except TimeoutError:
        return {"status": "processing", "job_id": job_id}
    except modal.exception.OutputExpiredError:
        raise HTTPException(status_code=404, detail="Resultado expirado")
