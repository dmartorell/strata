"""Integration tests for AudioPipeline stem separation.

Estos tests invocan la clase AudioPipeline en Modal remotamente.
Requieren `modal deploy` previo y un token de Modal valido.

Para ejecutar:
    pytest tests/test_separation.py -m integration

Se omiten automaticamente si no hay token Modal configurado.
"""

import io
import os

import pytest

pytestmark = pytest.mark.integration


def _has_modal_token() -> bool:
    """Comprueba si hay un token Modal disponible en el entorno."""
    token_id = os.environ.get("MODAL_TOKEN_ID", "")
    token_secret = os.environ.get("MODAL_TOKEN_SECRET", "")
    # Si no hay variables de entorno, intentar con fichero de config de Modal
    if not token_id or not token_secret:
        config_path = os.path.expanduser("~/.modal.toml")
        return os.path.exists(config_path)
    return True


@pytest.fixture(scope="module")
def short_mp3_bytes() -> bytes:
    """Genera un MP3 corto (5s de tono sinusoidal) como fixture de test.

    Usa numpy + soundfile para generar el audio en memoria y lo encoda
    como MP3 via ffmpeg subprocess si esta disponible, o como WAV como
    fallback (Demucs acepta WAV directamente).
    """
    import subprocess
    import tempfile

    import numpy as np
    import soundfile as sf

    # Generar tono sinusoidal de 440 Hz, 5 segundos, mono, 44100 Hz
    sample_rate = 44100
    duration_s = 5
    frequency_hz = 440.0
    t = np.linspace(0, duration_s, int(sample_rate * duration_s), endpoint=False)
    audio = (0.3 * np.sin(2 * np.pi * frequency_hz * t)).astype(np.float32)

    # Intentar encodar como MP3 via ffmpeg; si no disponible, usar WAV
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wav_file:
        sf.write(wav_file.name, audio, sample_rate, format="WAV")
        wav_path = wav_file.name

    try:
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", wav_path, "-codec:a", "libmp3lame", "-qscale:a", "2", "-f", "mp3", "pipe:1"],
            capture_output=True,
            check=True,
        )
        audio_bytes = result.stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback: leer el WAV generado
        with open(wav_path, "rb") as f:
            audio_bytes = f.read()
    finally:
        os.unlink(wav_path)

    return audio_bytes


@pytest.fixture(scope="module")
def audio_pipeline():
    """Obtiene referencia a AudioPipeline.separate en Modal."""
    pytest.importorskip("modal", reason="modal not installed")

    if not _has_modal_token():
        pytest.skip("No Modal token configured — run `modal token new` first")

    import modal

    try:
        cls = modal.Cls.from_name("strata", "AudioPipeline")
        return cls()
    except Exception as exc:
        pytest.skip(f"AudioPipeline not deployed — run `modal deploy server/app.py` first: {exc}")


def test_separate_returns_four_stems(audio_pipeline, short_mp3_bytes):
    """Verificar que separate devuelve exactamente 4 stems."""
    result = audio_pipeline.separate.remote(short_mp3_bytes)

    assert isinstance(result, dict), f"Expected dict, got {type(result)}"
    assert set(result.keys()) == {"vocals", "drums", "bass", "other"}, (
        f"Expected keys {{vocals, drums, bass, other}}, got {set(result.keys())}"
    )


def test_stems_are_valid_wav_bytes(audio_pipeline, short_mp3_bytes):
    """Verificar que cada stem es bytes WAV parseable por soundfile."""
    import soundfile as sf

    result = audio_pipeline.separate.remote(short_mp3_bytes)

    for stem_name, stem_bytes in result.items():
        assert isinstance(stem_bytes, bytes), f"{stem_name}: expected bytes, got {type(stem_bytes)}"
        assert len(stem_bytes) > 0, f"{stem_name}: stem bytes are empty"

        buffer = io.BytesIO(stem_bytes)
        info = sf.info(buffer)
        assert info.format == "WAV", f"{stem_name}: expected WAV format, got {info.format}"


def test_stems_sample_rate_is_44100(audio_pipeline, short_mp3_bytes):
    """Verificar que cada stem tiene sample rate 44100 Hz (nativo de htdemucs)."""
    import soundfile as sf

    result = audio_pipeline.separate.remote(short_mp3_bytes)

    for stem_name, stem_bytes in result.items():
        buffer = io.BytesIO(stem_bytes)
        info = sf.info(buffer)
        assert info.samplerate == 44100, (
            f"{stem_name}: expected 44100 Hz, got {info.samplerate} Hz"
        )
