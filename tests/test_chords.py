"""Integration tests for chord detection via ProcessingService.detect_chords.

Los tests marcados con @pytest.mark.integration requieren:
- Modal CLI autenticado (modal token set)
- El app desplegado en Modal con chord-extractor en la imagen

Para ejecutar solo tests de integracion:
  pytest tests/test_chords.py -m integration -v

Para saltar tests de integracion (CI local sin Modal):
  pytest tests/test_chords.py -m "not integration" -v
"""

import io
import struct
import wave

import pytest


# ---------------------------------------------------------------------------
# Fixtures de audio
# ---------------------------------------------------------------------------

def _generate_wav_bytes(duration_seconds: float = 2.0, sample_rate: int = 44100) -> bytes:
    """Genera un WAV sintetico con un tono sostenido (acorde de La, 440 Hz).

    Produce audio tonal con contenido armonico claro para que Chordino
    pueda detectar al menos un acorde. No es silencio ni ruido aleatorio.
    """
    import math

    num_samples = int(sample_rate * duration_seconds)
    # Acorde de La mayor: 440 Hz (La) + 554 Hz (Do#) + 659 Hz (Mi)
    frequencies = [440.0, 554.37, 659.25]
    amplitude = 16000  # 16-bit PCM, ~50% de rango maximo

    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        sample = sum(amplitude * math.sin(2 * math.pi * f * t) for f in frequencies)
        sample = int(max(-32768, min(32767, sample / len(frequencies))))
        samples.append(sample)

    buf = io.BytesIO()
    with wave.open(buf, "w") as wf:
        wf.setnchannels(1)           # mono
        wf.setsampwidth(2)           # 16-bit
        wf.setframerate(sample_rate)
        wf.writeframes(struct.pack(f"<{num_samples}h", *samples))

    return buf.getvalue()


@pytest.fixture
def tonal_wav_bytes() -> bytes:
    """WAV con acorde de La mayor sostenido (2 segundos)."""
    return _generate_wav_bytes(duration_seconds=2.0)


@pytest.fixture
def short_tonal_wav_bytes() -> bytes:
    """WAV con acorde de La mayor corto (0.5 segundos) — puede no detectar acordes."""
    return _generate_wav_bytes(duration_seconds=0.5)


# ---------------------------------------------------------------------------
# Tests de integracion (requieren Modal + imagen desplegada)
# ---------------------------------------------------------------------------

@pytest.mark.integration
def test_detect_chords_returns_list(tonal_wav_bytes):
    """detect_chords retorna una lista (puede estar vacia si audio no tonal claro)."""
    import modal
    with modal.enable_output():
        result = modal.Cls.from_name("strata", "AudioPipeline")().detect_chords.remote(
            tonal_wav_bytes
        )

    assert isinstance(result, list), f"Expected list, got {type(result)}"


@pytest.mark.integration
def test_detect_chords_schema(tonal_wav_bytes):
    """Si la lista no esta vacia, cada item tiene las keys {chord, start, end} correctas."""
    import modal
    with modal.enable_output():
        result = modal.Cls.from_name("strata", "AudioPipeline")().detect_chords.remote(
            tonal_wav_bytes
        )

    assert isinstance(result, list)

    for i, item in enumerate(result):
        assert "chord" in item, f"Item {i} missing 'chord' key: {item}"
        assert "start" in item, f"Item {i} missing 'start' key: {item}"
        assert "end" in item, f"Item {i} missing 'end' key: {item}"

        assert isinstance(item["chord"], str), f"Item {i} 'chord' is not str: {item}"
        assert len(item["chord"]) > 0, f"Item {i} 'chord' is empty string: {item}"

        assert isinstance(item["start"], (int, float)), (
            f"Item {i} 'start' is not numeric: {item}"
        )
        assert item["start"] >= 0, f"Item {i} 'start' < 0: {item}"

        # end puede ser None (ultimo acorde) o float mayor que start
        if item["end"] is not None:
            assert isinstance(item["end"], (int, float)), (
                f"Item {i} 'end' is not numeric or None: {item}"
            )
            assert item["end"] > item["start"], (
                f"Item {i} 'end' <= 'start': {item}"
            )
        else:
            # Solo el ultimo acorde puede tener end=None
            assert i == len(result) - 1, (
                f"Item {i} has end=None but is not the last item (total={len(result)})"
            )


@pytest.mark.integration
def test_detect_chords_invalid_bytes_returns_empty():
    """Bytes invalidos (no WAV) -> retorna [] sin crash."""
    import modal
    invalid_bytes = b"this is not a valid wav file at all"

    with modal.enable_output():
        result = modal.Cls.from_name("strata", "AudioPipeline")().detect_chords.remote(
            invalid_bytes
        )

    assert result == [], f"Expected [] for invalid bytes, got: {result}"


@pytest.mark.integration
def test_detect_chords_empty_bytes_returns_empty():
    """Bytes vacios -> retorna [] sin crash."""
    import modal

    with modal.enable_output():
        result = modal.Cls.from_name("strata", "AudioPipeline")().detect_chords.remote(
            b""
        )

    assert result == [], f"Expected [] for empty bytes, got: {result}"


# ---------------------------------------------------------------------------
# Tests de logica local (no requieren Modal)
# ---------------------------------------------------------------------------

def test_wav_fixture_is_valid_wav(tonal_wav_bytes):
    """El fixture genera un WAV valido que soundfile puede leer."""
    buf = io.BytesIO(tonal_wav_bytes)
    with wave.open(buf, "r") as wf:
        assert wf.getnframes() > 0
        assert wf.getframerate() == 44100
        assert wf.getnchannels() == 1


def test_chord_schema_structure():
    """Verifica la estructura esperada del schema de acordes (test de contrato)."""
    example_output = [
        {"chord": "D:maj", "start": 0.0, "end": 2.5},
        {"chord": "G:maj", "start": 2.5, "end": 5.0},
        {"chord": "A:maj", "start": 5.0, "end": None},
    ]

    for i, item in enumerate(example_output):
        assert "chord" in item
        assert "start" in item
        assert "end" in item
        assert isinstance(item["chord"], str)
        assert item["start"] >= 0

        if item["end"] is not None:
            assert item["end"] > item["start"]
        else:
            assert i == len(example_output) - 1
