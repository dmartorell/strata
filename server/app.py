import modal
from datetime import datetime

# Modal App definition
app = modal.App("strata")

# Modal Dict para progreso de jobs (accesible desde web handler y processing function)
job_progress = modal.Dict.from_name("strata-job-progress", create_if_missing=True)

# Modal Volume para persistencia de datos de uso
usage_vol = modal.Volume.from_name("strata-usage", create_if_missing=True)


# Inline script to bake ML model weights at build time.
# Using run_commands instead of run_function avoids Modal importing app.py
# (which needs the pipeline module) inside the build container.
_DOWNLOAD_WEIGHTS = """\
python -c "
from demucs.pretrained import get_model
get_model('htdemucs')

import whisperx
whisperx.load_model('large-v2', device='cpu', compute_type='int8')
"
"""

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
    .run_commands(_DOWNLOAD_WEIGHTS, gpu="T4")
    .add_local_dir("auth", remote_path="/root/auth")
    .add_local_dir("processors", remote_path="/root/processors")
    .add_local_dir("usage", remote_path="/root/usage")
    .add_local_dir("pipeline", remote_path="/root/pipeline")
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

        # WhisperX large-v2 — transcripcion con word-level timestamps
        import whisperx
        self.whisper_model = whisperx.load_model(
            "large-v2", device="cuda", compute_type="float16"
        )

    @modal.method()
    def transcribe(self, vocals_bytes: bytes) -> dict:
        """Transcribe el stem vocal con WhisperX large-v2.

        Args:
            vocals_bytes: Bytes WAV del stem vocals (output de separacion Demucs).

        Returns:
            Dict con language y segments con word-level timestamps.
            Fallback a timestamps por segmento si idioma no soportado.
        """
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")
        from pipeline.transcription import transcribe_vocals
        return transcribe_vocals(self.whisper_model, vocals_bytes)

    @modal.method()
    def detect_chords(self, other_stem_bytes: bytes) -> list:
        """Detecta acordes con timestamps sobre el stem 'other'.

        Args:
            other_stem_bytes: Contenido WAV del stem 'other' de Demucs.

        Returns:
            Lista de [{chord, start, end}]. Retorna [] si falla (resultado parcial).
        """
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")
        from pipeline.chords import detect_chords
        return detect_chords(other_stem_bytes)

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


# ---------------------------------------------------------------------------
# AudioPipeline — GPU T4, Demucs separation with @modal.enter warm-up
# ---------------------------------------------------------------------------

from pipeline.image import gpu_image  # noqa: E402


@app.cls(
    image=gpu_image,
    gpu="T4",
    max_containers=2,
    scaledown_window=300,
    timeout=600,
    secrets=[modal.Secret.from_name("youtube-cookies")],
)
class AudioPipeline:
    """Pipeline end-to-end de audio: Demucs + WhisperX + chord-extractor.

    Los modelos se cargan una sola vez por contenedor en @modal.enter y se
    reutilizan entre requests, garantizando cold starts predecibles.

    Flujo principal (process):
        validate -> separate_stems -> transcribe_vocals -> detect_chords -> package_results
    """

    @modal.enter()
    def load_models(self):
        """Carga Demucs y WhisperX al arrancar el contenedor."""
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")

        # Demucs htdemucs — separacion de stems
        from demucs.api import Separator
        self.separator = Separator(model="htdemucs")

        # WhisperX large-v2 — transcripcion con word-level timestamps
        import whisperx
        self.whisper_model = whisperx.load_model(
            "large-v2", device="cuda", compute_type="float16"
        )

    @modal.method()
    def process(
        self,
        audio_bytes: bytes,
        source_type: str,
        source_name: str,
        username: str,
        youtube_metadata: dict | None = None,
    ) -> bytes:
        """Pipeline end-to-end: audio_bytes -> ZIP con stems + JSONs.

        Args:
            audio_bytes: Bytes del archivo de audio (MP3, M4A, WAV...).
            source_type: "file" o "youtube".
            source_name: Nombre del archivo original o URL de YouTube.
            username: Usuario que solicita el procesamiento (para usage).
            youtube_metadata: Metadatos YouTube de download_youtube_audio().
                              Si se pasa, se hace merge sobre metadata.json.

        Returns:
            Bytes del ZIP con 4 stems WAV + lyrics.json + chords.json + metadata.json.
        """
        import sys
        import soundfile as sf
        import io as _io
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")

        # Obtener job_id del contexto Modal (es el object_id del FunctionCall)
        job_id = modal.current_function_call_id()
        progress = modal.Dict.from_name("strata-job-progress", create_if_missing=True)

        # Validar limites antes de tocar GPU
        from pipeline.validators import validate_audio
        validate_audio(audio_bytes)

        # Step 1: Separar stems (Demucs htdemucs)
        progress[job_id] = "separating"
        from pipeline.separation import separate_stems
        stems = separate_stems(self.separator, audio_bytes)

        # Calcular duracion a partir del stem vocals (disponible siempre)
        duration_seconds: float | None = None
        try:
            vocals_bytes = stems.get("vocals", b"")
            if vocals_bytes:
                with sf.SoundFile(_io.BytesIO(vocals_bytes)) as f:
                    duration_seconds = len(f) / f.samplerate
        except Exception:
            pass

        # Step 2: Transcribir vocals (WhisperX)
        progress[job_id] = "transcribing"
        from pipeline.transcription import transcribe_vocals
        lyrics = transcribe_vocals(self.whisper_model, stems.get("vocals", b""))

        # Step 3: Detectar acordes sobre stem 'other'
        progress[job_id] = "detecting_chords"
        from pipeline.chords import detect_chords
        chords = detect_chords(stems.get("other", b""))

        # Step 4: Empaquetar todo en ZIP
        progress[job_id] = "packaging"
        from pipeline.packaging import package_results
        from usage.tracker import record_usage

        metadata = {
            "title": source_name,
            "duration_seconds": duration_seconds,
            "sample_rate": 44100,
            "source_type": source_type,
            "processed_at": datetime.utcnow().isoformat() + "Z",
            "original_filename": source_name if source_type == "file" else None,
        }
        # Merge YouTube metadata (sobreescribe campos base con info de YT)
        if youtube_metadata:
            metadata.update(youtube_metadata)

        # Registrar uso antes de marcar como completado
        record_usage(username=username, source_type=source_type, source_name=source_name)

        result = package_results(stems, lyrics, chords, metadata)

        progress[job_id] = "completed"
        return result

    @modal.method()
    def process_youtube(self, url: str, username: str) -> bytes:
        """Descarga audio de YouTube y ejecuta el pipeline completo.

        Args:
            url: URL de YouTube a descargar.
            username: Usuario que solicita el procesamiento.

        Returns:
            Bytes del ZIP resultado del pipeline.
        """
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")

        from pipeline.downloader import download_youtube_audio
        audio_bytes, yt_metadata = download_youtube_audio(url, "/tmp")
        return self.process(
            audio_bytes,
            "youtube",
            url,
            username,
            youtube_metadata=yt_metadata,
        )

    @modal.method()
    def separate(self, audio_bytes: bytes) -> dict:
        """Separa audio en 4 stems WAV usando el separator pre-cargado.

        Mantenido para compatibilidad con tests de integracion de 02-01.
        """
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")

        from pipeline.separation import separate_stems
        return separate_stems(self.separator, audio_bytes)

    @modal.method()
    def detect_chords(self, other_stem_bytes: bytes) -> list:
        """Detecta acordes con timestamps sobre el stem 'other'.

        Mantenido para compatibilidad con tests de integracion de 02-03.

        Returns:
            Lista de [{chord, start, end}]. Retorna [] si falla (resultado parcial).
        """
        import sys
        if "/root" not in sys.path:
            sys.path.insert(0, "/root")
        from pipeline.chords import detect_chords
        return detect_chords(other_stem_bytes)
