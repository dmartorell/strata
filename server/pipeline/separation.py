"""Demucs stem separation logic for the audio pipeline.

Usa la API de bajo nivel de demucs (pretrained + apply_model) en lugar de
demucs.api.Separator, que no está disponible en todas las versiones instalables
junto a torch<2.9.

Devuelve 2 tracks (original + instrumental) mas el stem "other" para acordes.
Sample rate de salida: el nativo del modelo (44100 Hz para htdemucs).
"""

import gc
import io
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf


def separate_stems(demucs_model, audio_bytes: bytes) -> dict[str, bytes]:
    """Separa un archivo de audio y devuelve original, instrumental y other.

    El instrumental se calcula como original - vocals, preservando la mezcla
    original del resto de instrumentos sin artefactos de suma de stems.

    Args:
        demucs_model: Modelo demucs pre-cargado en @modal.enter (output de get_model).
        audio_bytes: Contenido del archivo de audio (MP3, WAV, etc.) como bytes.

    Returns:
        Diccionario con 3 tracks en formato WAV como bytes:
        {"original": bytes, "instrumental": bytes, "other": bytes}
        "other" se usa internamente para deteccion de acordes, no se empaqueta.

    Raises:
        RuntimeError: Si la separacion falla por OOM incluso reduciendo el segmento.
    """
    import torch
    import torchaudio
    from demucs.apply import apply_model
    from demucs.audio import convert_audio

    tmp_input: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
            f.write(audio_bytes)
            tmp_input = Path(f.name)

        wav, sr = torchaudio.load(str(tmp_input))
        wav = convert_audio(wav, sr, demucs_model.samplerate, demucs_model.audio_channels)

        original_tensor = wav.clone()

        wav = wav.unsqueeze(0).cuda()  # (1, channels, samples)

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
        vocals_idx = stem_names.index("vocals")
        other_idx = stem_names.index("other")

        vocals_tensor = sources[vocals_idx].cpu()
        instrumental_tensor = original_tensor - vocals_tensor

        result: dict[str, bytes] = {}
        sr_out = demucs_model.samplerate

        for name, tensor in [("original", original_tensor), ("instrumental", instrumental_tensor)]:
            audio_array = tensor.numpy().T  # (samples, channels)
            buffer = io.BytesIO()
            sf.write(buffer, audio_array, samplerate=sr_out, format="WAV")
            result[name] = buffer.getvalue()

        other_array = sources[other_idx].cpu().numpy().T
        buffer = io.BytesIO()
        sf.write(buffer, other_array, samplerate=sr_out, format="WAV")
        result["other"] = buffer.getvalue()

        return result

    finally:
        if tmp_input is not None and tmp_input.exists():
            tmp_input.unlink()

        gc.collect()
        try:
            torch.cuda.empty_cache()
        except Exception:
            pass
