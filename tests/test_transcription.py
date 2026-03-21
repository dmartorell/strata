"""Test de integracion para transcripcion WhisperX.

Requiere modal deploy previo y credentials de Modal configuradas.
Se salta automaticamente si no hay token Modal disponible.

Ejecutar con:
    pytest tests/test_transcription.py -m integration -v
"""

import os
import struct
import wave
import io
import pytest

pytestmark = pytest.mark.integration


def _requires_modal():
    """Skip si no hay token Modal disponible."""
    try:
        import modal
        # Intentar acceder al cliente — falla si no hay token
        modal.config._profile  # noqa: B018
    except Exception:
        pytest.skip("Modal token no configurado — test de integracion omitido")


def _generate_sine_wav(duration_s: float = 5.0, sample_rate: int = 44100, freq: float = 440.0) -> bytes:
    """Genera un archivo WAV con un tono sinusoidal como fixture de audio.

    Produce 5 segundos de tono a 440 Hz (La4). Es suficiente para que
    WhisperX detecte ausencia de voz y devuelva segments vacio o con silencio.
    """
    import math

    num_samples = int(sample_rate * duration_s)
    amplitude = 16000  # Amplitud moderada (16-bit PCM)

    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(sample_rate)
        # Generar muestras del seno
        for i in range(num_samples):
            sample = int(amplitude * math.sin(2 * math.pi * freq * i / sample_rate))
            wf.writeframes(struct.pack("<h", sample))

    return buf.getvalue()


@pytest.fixture(scope="module")
def vocals_wav_bytes():
    """Fixture: 5s de tono sinusoidal como proxy de stem vocals."""
    return _generate_sine_wav(duration_s=5.0)


class TestTranscriptionIntegration:
    """Tests de integracion para ProcessingService.transcribe via Modal."""

    def test_transcribe_returns_language(self, vocals_wav_bytes):
        """El output contiene key 'language' con un string no vacio."""
        _requires_modal()
        import modal

        service = modal.Cls.from_name("siyahamba", "ProcessingService")
        result = service().transcribe.remote(vocals_wav_bytes)

        assert isinstance(result, dict), "Output debe ser dict"
        assert "language" in result, "Output debe contener key 'language'"
        assert isinstance(result["language"], str), "'language' debe ser string"

    def test_transcribe_returns_segments(self, vocals_wav_bytes):
        """El output contiene key 'segments' como lista."""
        _requires_modal()
        import modal

        service = modal.Cls.from_name("siyahamba", "ProcessingService")
        result = service().transcribe.remote(vocals_wav_bytes)

        assert "segments" in result, "Output debe contener key 'segments'"
        assert isinstance(result["segments"], list), "'segments' debe ser lista"

    def test_segments_have_required_fields(self, vocals_wav_bytes):
        """Cada segmento tiene los campos text, start, end, words."""
        _requires_modal()
        import modal

        service = modal.Cls.from_name("siyahamba", "ProcessingService")
        result = service().transcribe.remote(vocals_wav_bytes)

        for seg in result.get("segments", []):
            assert "text" in seg, f"Segmento sin 'text': {seg}"
            assert "start" in seg, f"Segmento sin 'start': {seg}"
            assert "end" in seg, f"Segmento sin 'end': {seg}"
            assert "words" in seg, f"Segmento sin 'words': {seg}"
            assert isinstance(seg["words"], list), f"'words' debe ser lista: {seg}"

    def test_words_have_required_fields_if_present(self, vocals_wav_bytes):
        """Si hay words (word-level alignment), cada word tiene word, start, end."""
        _requires_modal()
        import modal

        service = modal.Cls.from_name("siyahamba", "ProcessingService")
        result = service().transcribe.remote(vocals_wav_bytes)

        for seg in result.get("segments", []):
            for w in seg.get("words", []):
                assert "word" in w, f"Word sin 'word': {w}"
                assert "start" in w, f"Word sin 'start': {w}"
                assert "end" in w, f"Word sin 'end': {w}"
                assert isinstance(w["start"], (int, float)), f"'start' debe ser numerico: {w}"
                assert isinstance(w["end"], (int, float)), f"'end' debe ser numerico: {w}"

    def test_output_schema_complete(self, vocals_wav_bytes):
        """Verificacion completa del schema definido en CONTEXT.md."""
        _requires_modal()
        import modal

        service = modal.Cls.from_name("siyahamba", "ProcessingService")
        result = service().transcribe.remote(vocals_wav_bytes)

        # Top level
        assert set(result.keys()) >= {"language", "segments"}

        # Segments es lista (puede estar vacia para audio sin voz)
        assert isinstance(result["segments"], list)

        # Si hay segmentos, validar estructura completa
        for seg in result["segments"]:
            assert isinstance(seg.get("text", None), str)
            assert isinstance(seg.get("start", None), (int, float))
            assert isinstance(seg.get("end", None), (int, float))
            assert isinstance(seg.get("words", None), list)
