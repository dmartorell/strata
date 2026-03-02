"""Demucs stem separation logic for the audio pipeline.

La funcion separate_stems recibe un separator pre-cargado (instanciado en
@modal.enter para reusar el modelo entre requests) y bytes de audio,
y devuelve los 4 stems WAV como bytes.

Sample rate de salida: 44100 Hz (nativo de htdemucs, sin resampling).
"""

import gc
import io
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf


def separate_stems(separator, audio_bytes: bytes) -> dict[str, bytes]:
    """Separa un archivo de audio en 4 stems usando Demucs htdemucs.

    Args:
        separator: Instancia de demucs.api.Separator pre-cargada en @modal.enter.
        audio_bytes: Contenido del archivo de audio (MP3, WAV, etc.) como bytes.

    Returns:
        Diccionario con 4 stems en formato WAV como bytes:
        {"vocals": bytes, "drums": bytes, "bass": bytes, "other": bytes}

    Raises:
        RuntimeError: Si la separacion falla por OOM incluso con segment reducido.
    """
    import torch

    stems_result: dict[str, bytes] = {}
    tmp_input: Path | None = None

    try:
        # Escribir audio a fichero temporal para que Demucs pueda leerlo
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
            f.write(audio_bytes)
            tmp_input = Path(f.name)

        # Intentar separacion; si hay OOM, reintentar con segment mas pequeno
        try:
            _, separated = separator.separate_audio_file(tmp_input)
        except torch.cuda.OutOfMemoryError:
            # Reintentar con segment=7.5 para reducir uso de VRAM en canciones largas
            separator.update_parameter(segment=7.5)
            torch.cuda.empty_cache()
            _, separated = separator.separate_audio_file(tmp_input)

        # Convertir cada stem a bytes WAV
        stem_names = ["vocals", "drums", "bass", "other"]
        for stem_name in stem_names:
            if stem_name not in separated:
                continue

            # Mover tensor a CPU y convertir a numpy: shape (channels, samples) -> (samples, channels)
            tensor = separated[stem_name].cpu()
            audio_array = tensor.numpy().T  # (samples, channels)

            # Escribir a WAV en memoria a 44100 Hz (sample rate nativo de htdemucs)
            buffer = io.BytesIO()
            sf.write(buffer, audio_array, samplerate=44100, format="WAV")
            stems_result[stem_name] = buffer.getvalue()

    finally:
        # Limpiar fichero temporal de entrada
        if tmp_input is not None and tmp_input.exists():
            tmp_input.unlink()

        # Liberar VRAM para los siguientes modelos (WhisperX, chord-extractor)
        gc.collect()
        try:
            import torch
            torch.cuda.empty_cache()
        except Exception:
            pass

    return stems_result
