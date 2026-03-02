"""Tests unitarios para server/pipeline/validators.py.

Estos tests se ejecutan en local (sin GPU/Modal) con datos sinteticos.
"""

import io
import struct
import wave

import pytest

from server.pipeline.validators import validate_audio


# ---------------------------------------------------------------------------
# Helpers para generar WAVs sinteticos
# ---------------------------------------------------------------------------


def _make_wav_bytes(duration_seconds: float, sample_rate: int = 8000) -> bytes:
    """Genera un WAV sintetico (silencio) de la duracion indicada.

    Usa 8000 Hz mono para mantener el tamano por debajo del limite de 50 MB
    incluso para duraciones de 11 minutos (~10.5 MB).
    """
    n_samples = int(duration_seconds * sample_rate)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(sample_rate)
        # Silencio: n_samples frames de 2 bytes cada uno
        wf.writeframes(b"\x00\x00" * n_samples)
    return buf.getvalue()


def _make_fake_bytes(size_mb: float) -> bytes:
    """Genera bytes aleatorios del tamano indicado en MB (no son WAV valido)."""
    return b"\xff" * int(size_mb * 1024 * 1024)


# ---------------------------------------------------------------------------
# Tests de tamano
# ---------------------------------------------------------------------------


def test_small_file_passes():
    """Un archivo de 1 MB pasa la validacion."""
    audio = _make_fake_bytes(1)
    # No debe lanzar excepcion (la duracion no se puede leer de bytes aleatorios)
    # validate_audio no debe fallar por tamano
    try:
        validate_audio(audio)
    except ValueError as e:
        # Solo acepta el error de duracion si soundfile/librosa lo detectan,
        # pero nunca el de tamano para 1 MB
        assert "limite de 50 MB" not in str(e)


def test_oversized_file_raises():
    """Un archivo de 51 MB lanza ValueError con mensaje claro."""
    audio = _make_fake_bytes(51)
    with pytest.raises(ValueError, match="limite de 50 MB"):
        validate_audio(audio)


def test_exact_limit_passes():
    """Un archivo de exactamente 50 MB pasa la validacion de tamano."""
    audio = _make_fake_bytes(50)
    try:
        validate_audio(audio)
    except ValueError as e:
        assert "limite de 50 MB" not in str(e)


# ---------------------------------------------------------------------------
# Tests de duracion con WAVs sinteticos
# ---------------------------------------------------------------------------


def test_short_wav_passes():
    """Un WAV de 5 minutos pasa la validacion."""
    audio = _make_wav_bytes(5 * 60)
    # No debe lanzar excepcion
    validate_audio(audio)


def test_long_wav_raises():
    """Un WAV de 11 minutos lanza ValueError con mensaje claro."""
    audio = _make_wav_bytes(11 * 60)
    with pytest.raises(ValueError, match="limite de 10 minutos"):
        validate_audio(audio)


def test_exactly_10_minutes_passes():
    """Un WAV de exactamente 10 minutos pasa la validacion."""
    audio = _make_wav_bytes(10 * 60)
    validate_audio(audio)


def test_custom_limits():
    """Los limites maximos son configurables."""
    audio = _make_wav_bytes(6 * 60)  # 6 minutos
    # Con limite de 5 min debe fallar
    with pytest.raises(ValueError, match="limite de 5 minutos"):
        validate_audio(audio, max_minutes=5)

    # Con limite de 7 min debe pasar
    validate_audio(audio, max_minutes=7)
