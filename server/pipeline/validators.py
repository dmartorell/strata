"""Validadores de audio para el pipeline de Siyahamba.

Rechaza archivos que superen los limites de tamano y duracion ANTES de tocar GPU,
evitando costes innecesarios y tiempos de espera excesivos.

Limites por defecto:
- Tamano maximo: 50 MB
- Duracion maxima: 10 minutos

Estos rechazos deben producir HTTP 400 en el endpoint (el endpoint es responsable
de capturar ValueError y convertirlo en HTTPException).
"""

import io


def validate_audio(
    audio_bytes: bytes,
    max_mb: int = 50,
    max_minutes: int = 10,
) -> None:
    """Valida que el audio no supere los limites de tamano y duracion.

    Args:
        audio_bytes: Contenido del archivo de audio a validar.
        max_mb: Tamano maximo en MB (default 50).
        max_minutes: Duracion maxima en minutos (default 10).

    Raises:
        ValueError: Si el archivo supera el limite de tamano o duracion.
            - "Archivo excede limite de {max_mb} MB" si es demasiado grande.
            - "Audio excede limite de {max_minutes} minutos" si es demasiado largo.
    """
    # --- Validacion de tamano ---
    max_bytes = max_mb * 1024 * 1024
    if len(audio_bytes) > max_bytes:
        raise ValueError(f"Archivo excede limite de {max_mb} MB")

    # --- Validacion de duracion ---
    duration_seconds = _get_duration(audio_bytes)
    max_seconds = max_minutes * 60
    if duration_seconds is not None and duration_seconds > max_seconds:
        raise ValueError(f"Audio excede limite de {max_minutes} minutos")


def _get_duration(audio_bytes: bytes) -> float | None:
    """Obtiene la duracion del audio en segundos.

    Intenta soundfile primero (rapido, sin dependencias pesadas).
    Si falla (formato no soportado por libsndfile, p.ej. MP3/M4A),
    usa librosa como fallback.

    Returns:
        Duracion en segundos, o None si no se puede determinar.
    """
    # Intento 1: soundfile (soporta WAV, FLAC, OGG, AIFF — no MP3)
    try:
        import soundfile as sf

        with sf.SoundFile(io.BytesIO(audio_bytes)) as audio_file:
            frames = len(audio_file)
            samplerate = audio_file.samplerate
            if samplerate > 0:
                return frames / samplerate
    except Exception:
        pass

    # Intento 2: librosa (soporta MP3, M4A via audioread/ffmpeg)
    try:
        import librosa

        duration = librosa.get_duration(
            path=_bytes_to_tmp_file(audio_bytes)
        )
        return duration
    except Exception:
        pass

    return None


def _bytes_to_tmp_file(audio_bytes: bytes) -> str:
    """Escribe bytes a un fichero temporal y devuelve la ruta."""
    import tempfile
    import os

    with tempfile.NamedTemporaryFile(delete=False, suffix=".audio") as f:
        f.write(audio_bytes)
        return f.name
