"""Fixtures y configuracion global de pytest para tests de Siyahamba.

- sample_audio_bytes: MP3 sintetico de ~30s con tono sinusoidal.
- modal_pipeline: referencia a AudioPipeline en Modal (requiere deployment).
- Marker "integration": requiere despliegue en Modal con token valido.

Los tests marcados como integration se saltan automaticamente si no hay
token Modal configurado (MODAL_TOKEN_ID o MODAL_TOKEN_SECRET ausentes).
"""

import io
import os

import pytest


# ---------------------------------------------------------------------------
# Marker registration
# ---------------------------------------------------------------------------


def pytest_configure(config):
    config.addinivalue_line("markers", "integration: requires Modal deployment")


# ---------------------------------------------------------------------------
# Skip automatico si no hay token Modal
# ---------------------------------------------------------------------------


def pytest_collection_modifyitems(config, items):
    has_modal_token = bool(
        os.environ.get("MODAL_TOKEN_ID") or os.environ.get("MODAL_TOKEN_SECRET")
    )
    if not has_modal_token:
        skip_marker = pytest.mark.skip(reason="No Modal token configured (MODAL_TOKEN_ID/MODAL_TOKEN_SECRET)")
        for item in items:
            if item.get_closest_marker("integration"):
                item.add_marker(skip_marker)


# ---------------------------------------------------------------------------
# Fixture: audio sintetico
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def sample_audio_bytes():
    """Genera un WAV sintetico de ~30s con tono sinusoidal de 440 Hz a 44100 Hz.

    Devuelve bytes WAV (no MP3) para no depender de encoders adicionales.
    Para tests que requieren un MP3 real de 3 minutos, colocar el archivo
    en tests/fixtures/sample_3min.mp3 (no incluido en el repo).
    """
    import numpy as np
    import soundfile as sf

    sr = 44100
    duration = 30  # segundos
    t = np.linspace(0, duration, duration * sr, endpoint=False)
    audio = 0.5 * np.sin(2 * np.pi * 440 * t)

    buf = io.BytesIO()
    sf.write(buf, audio, sr, format="WAV")
    buf.seek(0)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Fixture: referencia al AudioPipeline deployado en Modal
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def modal_pipeline():
    """Obtiene referencia al AudioPipeline deployado en Modal.

    Requiere:
    - modal token configurado (MODAL_TOKEN_ID + MODAL_TOKEN_SECRET)
    - App "siyahamba" deployada con modal deploy server/app.py
    """
    import modal

    cls = modal.Cls.from_name("siyahamba", "AudioPipeline")
    return cls()
