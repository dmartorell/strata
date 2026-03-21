"""Modal GPU image definition for the audio pipeline.

Esta imagen es exclusiva para el pipeline GPU (Demucs, WhisperX, chord-extractor).
La imagen web (sin GPU) sigue sirviendo los endpoints FastAPI de forma independiente.

Los pesos de htdemucs (~330MB) y WhisperX large-v2 (~1.5GB) se bake-an en la imagen
mediante run_commands, eliminando la descarga en runtime y garantizando cold starts
predecibles.
"""

import modal

# Inline script to download model weights during image build.
# Using run_commands instead of run_function avoids Modal importing app.py
# (which needs the pipeline module) inside the build container.
_DOWNLOAD_WEIGHTS_CMD = (
    "python -c \""
    "from demucs import pretrained; pretrained.get_model('htdemucs'); "
    "import whisperx; whisperx.load_model('large-v2', device='cpu', compute_type='int8')"
    "\""
)

gpu_image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "libsndfile1", "curl", "unzip")
    .run_commands(
        "curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh",
    )
    .pip_install("numpy")  # vamp (chord-extractor dep) needs numpy at setup time
    .pip_install(
        "torch<2.9",
        "torchaudio<2.9",
        "demucs==4.0.1",
        "soundfile",
        "chord-extractor",
        "faster-whisper",
        "whisperx",
    )
    .run_commands(_DOWNLOAD_WEIGHTS_CMD, gpu="T4")
    .add_local_dir("pipeline", remote_path="/root/pipeline")
    .add_local_dir("auth", remote_path="/root/auth")
    .add_local_dir("usage", remote_path="/root/usage")
)
