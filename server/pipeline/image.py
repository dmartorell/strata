"""Modal GPU image definition for the audio pipeline.

Esta imagen es exclusiva para el pipeline GPU (Demucs, WhisperX, chord-extractor, yt-dlp).
La imagen web (sin GPU) sigue sirviendo los endpoints FastAPI de forma independiente.

Los pesos de htdemucs (~330MB) y WhisperX large-v2 (~1.5GB) se bake-an en la imagen
mediante run_function, eliminando la descarga en runtime y garantizando cold starts
predecibles.
"""

import modal


def download_model_weights():
    """Descarga y cachea los pesos de htdemucs y WhisperX durante el build.

    Al ejecutarse en run_function con gpu="T4", los pesos quedan persistidos en el
    sistema de ficheros de la imagen — no se descargan en cada cold start.
    """
    # Demucs htdemucs (~330 MB)
    from demucs import pretrained
    pretrained.get_model("htdemucs")

    # WhisperX large-v2 (~1.5 GB)
    # int8 en build time (CPU) para minimizar VRAM durante el build
    import whisperx
    whisperx.load_model("large-v2", device="cpu", compute_type="int8")


gpu_image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "libsndfile1")
    .pip_install("numpy")  # vamp (chord-extractor dep) needs numpy at setup time
    .pip_install(
        "torch",
        "torchaudio",
        "demucs==4.0.1",
        "soundfile",
        "chord-extractor",
        "faster-whisper",
        "whisperx",
        "yt-dlp",
    )
    .run_function(download_model_weights, gpu="T4")
    .add_local_dir("auth", remote_path="/root/auth")
    .add_local_dir("pipeline", remote_path="/root/pipeline")
    .add_local_dir("usage", remote_path="/root/usage")
)
