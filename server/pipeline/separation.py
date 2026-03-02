"""Demucs stem separation logic for the audio pipeline.

Usa la API de bajo nivel de demucs (pretrained + apply_model) en lugar de
demucs.api.Separator, que no está disponible en todas las versiones instalables
junto a torch<2.9.

Sample rate de salida: el nativo del modelo (44100 Hz para htdemucs).
"""

import gc
import io
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf


def separate_stems(demucs_model, audio_bytes: bytes) -> dict[str, bytes]:
    """Separa un archivo de audio en 4 stems usando Demucs htdemucs.

    Args:
        demucs_model: Modelo demucs pre-cargado en @modal.enter (output de get_model).
        audio_bytes: Contenido del archivo de audio (MP3, WAV, etc.) como bytes.

    Returns:
        Diccionario con 4 stems en formato WAV como bytes:
        {"vocals": bytes, "drums": bytes, "bass": bytes, "other": bytes}

    Raises:
        RuntimeError: Si la separacion falla por OOM incluso reduciendo el segmento.
    """
    import torch
    import torchaudio
    from demucs.apply import apply_model
    from demucs.audio import convert_audio

    tmp_input: Path | None = None

    try:
        # Escribir audio a fichero temporal para que torchaudio pueda leerlo
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
            f.write(audio_bytes)
            tmp_input = Path(f.name)

        # Cargar audio y convertir al formato esperado por el modelo
        wav, sr = torchaudio.load(str(tmp_input))
        wav = convert_audio(wav, sr, demucs_model.samplerate, demucs_model.audio_channels)
        wav = wav.unsqueeze(0).cuda()  # (1, channels, samples)

        # Separar stems; reintentar con overlap reducido si OOM
        try:
            with torch.no_grad():
                sources = apply_model(demucs_model, wav, device="cuda")[0]
        except torch.cuda.OutOfMemoryError:
            torch.cuda.empty_cache()
            with torch.no_grad():
                sources = apply_model(
                    demucs_model, wav, device="cuda", overlap=0.1, segment=7.5
                )[0]

        # sources shape: (stems, channels, samples)
        stem_names = demucs_model.sources  # ["drums", "bass", "other", "vocals"]
        stems_result: dict[str, bytes] = {}

        for i, stem_name in enumerate(stem_names):
            audio_array = sources[i].cpu().numpy().T  # (samples, channels)
            buffer = io.BytesIO()
            sf.write(buffer, audio_array, samplerate=demucs_model.samplerate, format="WAV")
            stems_result[stem_name] = buffer.getvalue()

        return stems_result

    finally:
        if tmp_input is not None and tmp_input.exists():
            tmp_input.unlink()

        gc.collect()
        try:
            torch.cuda.empty_cache()
        except Exception:
            pass
