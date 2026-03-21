"""
Endpoints HTTP de procesamiento de audio para Strata.

FastAPI router con:
  - POST /process-file: acepta archivo de audio, valida tamano, lanza pipeline real
  - POST /process-url: acepta URL de YouTube, lanza pipeline real
  - GET /result/{job_id}: devuelve progreso o ZIP cuando completado

El procesamiento real se ejecuta en AudioPipeline (GPU Modal) via .spawn.
Los endpoints son solo el HTTP handler (ASGI web container, CPU).
"""

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
    return modal.Dict.from_name("strata-job-progress", create_if_missing=True)


def _get_pipeline():
    """Obtiene una instancia remota de AudioPipeline."""
    import modal
    return modal.Cls.from_name("strata", "AudioPipeline")()


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
    job_dict[job_id] = "queued"
    return {"job_id": job_id}


@router.post("/process-url")
async def process_url(
    body: dict,
    username: str = Depends(require_auth),
):
    """Acepta una URL de YouTube y lanza el pipeline GPU completo.

    AudioPipeline.process_youtube descarga el audio con yt-dlp (cookies via Modal
    Secret) y ejecuta el pipeline completo: Demucs + WhisperX + chord-extractor.
    """
    import modal
    from usage.tracker import check_limit

    if check_limit(username):
        return JSONResponse(
            status_code=429,
            content={"detail": "Monthly spending limit reached"},
        )

    url = body.get("url", "")
    if not url:
        raise HTTPException(status_code=400, detail="URL requerida")

    job_dict = _get_job_dict()
    pipeline = _get_pipeline()

    call = await pipeline.process_youtube.spawn.aio(
        url=url,
        username=username,
    )
    job_id = call.object_id
    # El pipeline usa modal.current_function_call_id() internamente para el progreso
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
        status = await job_dict.get.aio(job_id, "unknown")
    except Exception:
        status = "unknown"

    # Error propagado desde el pipeline (formato "error:{mensaje}")
    if isinstance(status, str) and status.startswith("error:"):
        error_detail = status[len("error:"):]
        if error_detail == "youtube_auth_expired":
            return JSONResponse(
                status_code=502,
                content={
                    "error_code": "youtube_auth_expired",
                    "detail": "No se pudo descargar de YouTube. Prueba subiendo el archivo directamente.",
                },
            )
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
