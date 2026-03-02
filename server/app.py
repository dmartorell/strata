import modal

# Modal App definition
app = modal.App("strata")

# Modal Dict para progreso de jobs (accesible desde web handler y processing function)
job_progress = modal.Dict.from_name("strata-job-progress", create_if_missing=True)

# Modal Volume para persistencia de datos de uso
usage_vol = modal.Volume.from_name("strata-usage", create_if_missing=True)

# Image with all dependencies and auth data baked in
image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "fastapi[standard]",
        "pyjwt",
        "bcrypt",
        "python-multipart",
    )
    .add_local_dir("auth", remote_path="/root/auth")
    .add_local_dir("processors", remote_path="/root/processors")
    .add_local_dir("usage", remote_path="/root/usage")
)


# ---------------------------------------------------------------------------
# Processing function — GPU T4, max 2 containers
# Runs in a separate container, communicates via modal.Dict + FunctionCall
# ---------------------------------------------------------------------------

@app.function(
    image=image,
    gpu="T4",
    max_containers=2,
    volumes={"/data": usage_vol},
)
async def process_job(source_type: str, source_name: str, username: str):
    """Stub processing function.

    Simula el pipeline de procesamiento con delays por etapa:
      queued -> downloading -> separating -> transcribing ->
      detecting_chords -> packaging -> completed

    Al final registra el uso y devuelve el ZIP con datos ficticios.
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
