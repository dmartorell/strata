"""Modulo de transcripcion con WhisperX.

Produce timestamps word-level usando WhisperX large-v2.
Fallback a timestamps por segmento si el idioma no soporta alineacion word-level.

VRAM: El alignment model (wav2vec2) se libera inmediatamente tras alinear.
"""

import gc
import tempfile
import os
from typing import Any


def transcribe_vocals(whisper_model: Any, vocals_bytes: bytes, device: str = "cuda") -> dict:
    """Transcribe el stem vocal y produce timestamps word-level.

    Args:
        whisper_model: Modelo WhisperX pre-cargado desde @modal.enter.
                       NO instanciar el modelo dentro de esta funcion.
        vocals_bytes: Bytes WAV del stem vocals (output de separation.py).
        device: Dispositivo CUDA para inferencia. Default "cuda".

    Returns:
        Dict con schema:
        {
            "language": str,
            "segments": [
                {
                    "text": str,
                    "start": float,
                    "end": float,
                    "words": [{"word": str, "start": float, "end": float}]
                }
            ]
        }

        Si el idioma no soporta alineacion word-level, "words" sera lista vacia
        en cada segmento. Phase 7 maneja ambos modos (word-by-word y scroll por linea).
    """
    import whisperx
    import torch

    # Escribir bytes a archivo temporal WAV
    tmp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    try:
        tmp_file.write(vocals_bytes)
        tmp_file.flush()
        tmp_file.close()

        # Cargar audio desde disco (formato que whisperx espera)
        audio = whisperx.load_audio(tmp_file.name)

        # Transcribir con batch_size=16 para rendimiento optimo en T4
        result = whisper_model.transcribe(audio, batch_size=16)

        # Intentar alineacion word-level
        try:
            model_a, metadata = whisperx.load_align_model(
                language_code=result["language"],
                device=device,
            )
            result = whisperx.align(
                result["segments"],
                model_a,
                metadata,
                audio,
                device,
                return_char_alignments=False,
            )
            # Liberar VRAM del alignment model inmediatamente — OBLIGATORIO
            del model_a
            gc.collect()
            torch.cuda.empty_cache()
        except Exception:
            # Fallback: mantener timestamps por segmento sin word-level
            # Ocurre si el idioma no tiene modelo de alineacion disponible
            pass

        # Formatear output segun schema de CONTEXT.md
        segments = []
        for seg in result.get("segments", []):
            words = [
                {
                    "word": w["word"],
                    "start": w["start"],
                    "end": w["end"],
                }
                for w in seg.get("words", [])
            ]
            segments.append(
                {
                    "text": seg.get("text", ""),
                    "start": seg.get("start", 0.0),
                    "end": seg.get("end", 0.0),
                    "words": words,
                }
            )

        return {
            "language": result.get("language", ""),
            "segments": segments,
        }

    finally:
        # Limpiar archivo temporal siempre
        try:
            os.unlink(tmp_file.name)
        except OSError:
            pass
