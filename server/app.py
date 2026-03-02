import modal

# Modal App definition
app = modal.App("strata")

# Modal Dict para progreso de jobs (accesible desde web handler y processing function)
job_progress = modal.Dict.from_name("strata-job-progress", create_if_missing=True)

# Modal Volume para persistencia de datos de uso
usage_vol = modal.Volume.from_name("strata-usage", create_if_missing=True)


def download_models():
    """Bake ML model weights into the image at build time.

    Se ejecuta con gpu="T4" para que CUDA se inicialice correctamente.
    Los pesos quedan en el sistema de archivos de la imagen (cache de cada libreria).
    """
    # Demucs htdemucs — separacion de stems
    from demucs.pretrained import get_model
    get_model("htdemucs")

    # WhisperX / faster-whisper — transcripcion
    from faster_whisper import WhisperModel
    WhisperModel("base", compute_type="float16")


# Image pesada con dependencias ML y pesos baked in
image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "libsndfile1")
    .pip_install(
        "torch",
        "torchaudio",
        "demucs==4.0.1",
        "faster-whisper",
        "whisperx",
        "fastapi[standard]",
        "pyjwt",
        "bcrypt",
        "python-multipart",
    )
    .run_function(download_models, gpu="T4")
    .add_local_dir("auth", remote_path="/root/auth")
    .add_local_dir("processors", remote_path="/root/processors")
    .add_local_dir("usage", remote_path="/root/usage")
)


# ---------------------------------------------------------------------------
# Processing service — GPU T4, max 2 containers, @modal.enter para preloading
# ---------------------------------------------------------------------------

@app.cls(
    image=image,
    gpu="T4",
    max_containers=2,
    volumes={"/data": usage_vol},
)
class ProcessingService:
    """Servicio de procesamiento de audio con modelos ML pre-cargados en memoria."""

    @modal.enter()
    def preload_models(self):
        """Carga modelos en memoria al arrancar el contenedor.

        Se ejecuta una vez por contenedor antes de la primera request,
        no en cada llamada. Garantiza cold start predecible.
        """
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")

        # Demucs htdemucs
        from demucs.pretrained import get_model
        self.demucs_model = get_model("htdemucs")

        # WhisperX / faster-whisper
        from faster_whisper import WhisperModel
        self.whisper_model = WhisperModel("base", compute_type="float16")

    @modal.method()
    async def process_job(self, source_type: str, source_name: str, username: str):
        """Stub processing job.

        Simula el pipeline de procesamiento con delays por etapa:
          queued -> downloading -> separating -> transcribing ->
          detecting_chords -> packaging -> completed

        Los modelos estan pre-cargados en self.demucs_model, self.whisper_model
        (Phase 2 los usara para procesamiento real, + chord-extractor para acordes).
        """
        import asyncio
        import sys

        # Asegurar que /root esta en sys.path para importar modulos montados
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")

        from processors.stub_builder import build_stub_zip
        from usage.tracker import record_usage

        # Obtener job_id del contexto Modal actual
        current_call = modal.current_function_call_id()
        job_id = current_call

        stages = [
            "downloading",
            "separating",
            "transcribing",
            "detecting_chords",
            "packaging",
        ]

        # Actualizar stage en el Dict
        def update_progress(stage: str):
            job_progress[job_id] = stage

        update_progress("queued")
        await asyncio.sleep(1.5)

        for stage in stages:
            update_progress(stage)
            await asyncio.sleep(1.5)

        # Registrar uso antes de marcar como completado
        record_usage(username=username, source_type=source_type, source_name=source_name)

        # Construir y devolver el ZIP
        zip_bytes = build_stub_zip(source_type=source_type, source_name=source_name)

        update_progress("completed")

        return zip_bytes


# ---------------------------------------------------------------------------
# Web handler — ASGI, CPU only, high concurrency
# ---------------------------------------------------------------------------

@app.function(image=image, volumes={"/data": usage_vol})
@modal.concurrent(max_inputs=10)
@modal.asgi_app()
def web():
    from fastapi import FastAPI
    from auth.auth import router as auth_router
    from processors.stub_processor import router as processor_router
    from usage.tracker import router as usage_router

    web_app = FastAPI(title="Strata API")

    @web_app.get("/health")
    def health():
        return {"status": "ok"}

    web_app.include_router(auth_router)
    web_app.include_router(processor_router)
    web_app.include_router(usage_router)

    return web_app
