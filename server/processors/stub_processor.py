"""
Endpoints HTTP de procesamiento de audio para Siyahamba.

FastAPI router con:
  - POST /process-file: acepta archivo de audio, valida tamano, lanza pipeline real
  - GET /result/{job_id}: devuelve progreso o ZIP cuando completado

El procesamiento real se ejecuta en AudioPipeline (GPU Modal) via .spawn.
Los endpoints son solo el HTTP handler (ASGI web container, CPU).
"""

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from fastapi.responses import JSONResponse, Response
from auth.auth import require_auth

router = APIRouter(tags=["processor"])

# Limite de tamano pre-GPU (PROC-07): rechazar antes de invocar GPU
_MAX_UPLOAD_MB = 50
_MAX_UPLOAD_BYTES = _MAX_UPLOAD_MB * 1024 * 1024


def _get_job_dict():
    """Obtiene el modal.Dict de progreso de jobs."""
    import modal
    return modal.Dict.from_name("siyahamba-job-progress", create_if_missing=True)


def _get_pipeline():
    """Obtiene una instancia remota de AudioPipeline."""
    import modal
    return modal.Cls.from_name("siyahamba", "AudioPipeline")()


@router.post("/cancel/{job_id}")
async def cancel_job(job_id: str, username: str = Depends(require_auth)):
    import modal

    job_dict = _get_job_dict()

    try:
        status = await job_dict.get.aio(job_id, "unknown")
    except Exception:
        status = "unknown"

    if status in ("completed", "unknown") or (isinstance(status, str) and status.startswith("error:")):
        return {"status": "already_finished", "job_id": job_id}

    await job_dict.put.aio(job_id, "cancelled")

    try:
        call = modal.FunctionCall.from_id(job_id)
        await call.cancel.aio()
    except Exception:
        pass

    return {"status": "cancelled", "job_id": job_id}


@router.post("/process-file")
async def process_file(
    audio_file: UploadFile,
    username: str = Depends(require_auth),
):
    """Acepta un archivo de audio, valida limites y lanza el pipeline GPU.

    Rechaza archivos >50 MB con HTTP 400 antes de invocar la GPU (PROC-07).
    El procesamiento real ocurre en AudioPipeline.process via Modal spawn.
    """
    import modal
    from usage.tracker import check_limit

    if check_limit(username):
        return JSONResponse(
            status_code=429,
            content={"detail": "Monthly spending limit reached"},
        )

    # Leer bytes del archivo
    audio_bytes = await audio_file.read()

    # Validar tamano pre-GPU — rechazar antes de tocar GPU
    if len(audio_bytes) > _MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=400,
            detail=f"Archivo excede limite de {_MAX_UPLOAD_MB} MB",
        )

    job_dict = _get_job_dict()
    pipeline = _get_pipeline()

    call = await pipeline.process.spawn.aio(
        audio_bytes=audio_bytes,
        source_type="file",
        source_name=audio_file.filename or "upload.mp3",
        username=username,
    )
    job_id = call.object_id
    # El pipeline usa modal.current_function_call_id() internamente para el progreso
    await job_dict.put.aio(job_id, "queued")
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
        status = await job_dict.get.aio(job_id, "unknown")
    except Exception:
        status = "unknown"

    # Error propagado desde el pipeline (formato "error:{mensaje}")
    if isinstance(status, str) and status.startswith("error:"):
        error_detail = status[len("error:"):]
        raise HTTPException(status_code=500, detail=f"Pipeline error: {error_detail}")

    # Error sin mensaje adjunto
    if status == "error":
        raise HTTPException(status_code=500, detail="Pipeline failed with unknown error")

    if status != "completed":
        return {"status": status if status != "unknown" else "processing", "job_id": job_id}

    # Job completado — obtener resultado ZIP
    try:
        call = modal.FunctionCall.from_id(job_id)
        result = await call.get.aio(timeout=5)
        return Response(
            content=result,
            media_type="application/zip",
            headers={"Content-Disposition": "attachment; filename=result.zip"},
        )
    except TimeoutError:
        return {"status": "processing", "job_id": job_id}
    except Exception as e:
        if "expired" in str(e).lower():
            raise HTTPException(status_code=404, detail="Resultado expirado")
        raise HTTPException(status_code=500, detail=f"Pipeline error: {e}")


@router.post("/align-lyrics")
async def align_lyrics_endpoint(
    request: dict[str, Any],
    username: str = Depends(require_auth),
):
    """Forced alignment con WhisperX. No se usa desde el cliente (LRCLib line-level sync es suficiente).
    Disponible para uso futuro o herramientas externas.

    Request body: {"vocals_base64": str, "lyrics_text": str, "language": str (optional, default "en")}
    Response: {"segments": [...aligned segments with word timestamps...]}
    """
    import base64

    lyrics_text = request.get("lyrics_text", "")
    language = request.get("language", "en")
    vocals_base64 = request.get("vocals_base64")

    if not lyrics_text:
        raise HTTPException(status_code=400, detail="lyrics_text is required")
    if not vocals_base64:
        raise HTTPException(status_code=400, detail="vocals_base64 is required")

    vocals_data = base64.b64decode(vocals_base64)

    pipeline = _get_pipeline()
    segments = await pipeline.align_lyrics.remote.aio(
        vocals_bytes=vocals_data,
        lyrics_text=lyrics_text,
        language=language,
    )

    return {"segments": segments}
