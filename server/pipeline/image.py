"""Modal GPU image definition for the audio pipeline.

Esta imagen es exclusiva para el pipeline GPU (Demucs, WhisperX, chord-extractor).
La imagen web (sin GPU) sigue sirviendo los endpoints FastAPI de forma independiente.

Los pesos de htdemucs (~330MB) se bake-an en la imagen mediante run_function,
eliminando la descarga en runtime y garantizando cold starts predecibles.
"""

import modal


def download_demucs_weights():
    """Descarga y cachea los pesos de htdemucs durante el build de la imagen.

    Al ejecutarse en run_function, los pesos quedan persistidos en el
    sistema de ficheros de la imagen — no se descargan en cada cold start.
    """
    from demucs import pretrained
    pretrained.get_model("htdemucs")


gpu_image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "libsndfile1")
    .pip_install(
        "torch",
        "torchaudio",
        "demucs==4.0.1",
        "soundfile",
        "numpy",
        "chord-extractor",
    )
    .run_function(download_demucs_weights, gpu="T4")
    .add_local_dir("auth", remote_path="/root/auth")
    .add_local_dir("pipeline", remote_path="/root/pipeline")
)
