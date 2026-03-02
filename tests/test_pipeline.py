"""Tests de integracion end-to-end del pipeline AudioPipeline en Modal.

Todos los tests requieren:
- Modal token configurado (MODAL_TOKEN_ID + MODAL_TOKEN_SECRET)
- App "strata" deployada: `modal deploy server/app.py`

Presupuestos de tiempo validados:
- PROC-05: archivo local -> ZIP en <60 segundos
- PROC-06: URL YouTube -> ZIP en <65 segundos
- PROC-07: rechazo de archivos fuera de limites (>50MB, >10min)

Ejecutar con:
    pytest tests/test_pipeline.py -x -v --timeout=120
"""

import io
import os
import time
import zipfile

import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _parse_zip(zip_bytes: bytes) -> zipfile.ZipFile:
    """Abre los bytes como ZipFile y valida que sea un ZIP valido."""
    buf = io.BytesIO(zip_bytes)
    assert zipfile.is_zipfile(buf), "El resultado no es un ZIP valido"
    buf.seek(0)
    return zipfile.ZipFile(buf, "r")


def _get_test_audio(sample_audio_bytes: bytes) -> bytes:
    """Devuelve un MP3 real de 3 minutos si esta disponible, o el sintetico.

    Busca tests/fixtures/sample_3min.mp3 — si existe, lo usa para un test
    mas representativo del budget real. Si no, usa el WAV sintetico de 30s.
    """
    fixture_path = os.path.join(os.path.dirname(__file__), "fixtures", "sample_3min.mp3")
    if os.path.exists(fixture_path):
        with open(fixture_path, "rb") as f:
            return f.read()
    return sample_audio_bytes


# ---------------------------------------------------------------------------
# Test 1: Estructura del ZIP de salida
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_file_pipeline_output_structure(modal_pipeline, sample_audio_bytes):
    """Verifica que el pipeline devuelve un ZIP con todos los artefactos requeridos.

    Comprueba:
    - 4 stems WAV: vocals, drums, bass, other
    - lyrics.json con key 'segments'
    - chords.json es lista JSON
    - metadata.json con keys requeridas
    - Cada WAV es parseable y tiene sample_rate=44100
    """
    import json

    import soundfile as sf

    result = modal_pipeline.process.remote(
        audio_bytes=sample_audio_bytes,
        source_type="file",
        source_name="test_synthetic.wav",
        username="test_user",
    )

    assert isinstance(result, bytes), "El resultado debe ser bytes"
    assert len(result) > 0, "El resultado no debe estar vacio"

    zf = _parse_zip(result)
    names = zf.namelist()

    # Verificar stems WAV
    required_stems = ["vocals.wav", "drums.wav", "bass.wav", "other.wav"]
    for stem in required_stems:
        assert stem in names, f"Falta stem en ZIP: {stem}"
        wav_bytes = zf.read(stem)
        with sf.SoundFile(io.BytesIO(wav_bytes)) as sf_file:
            assert sf_file.samplerate == 44100, f"{stem} debe tener sample_rate=44100"

    # Verificar lyrics.json
    assert "lyrics.json" in names, "Falta lyrics.json en ZIP"
    lyrics = json.loads(zf.read("lyrics.json"))
    assert "segments" in lyrics, "lyrics.json debe tener key 'segments'"
    assert isinstance(lyrics["segments"], list), "'segments' debe ser una lista"

    # Verificar chords.json
    assert "chords.json" in names, "Falta chords.json en ZIP"
    chords = json.loads(zf.read("chords.json"))
    assert isinstance(chords, list), "chords.json debe ser una lista"

    # Verificar metadata.json
    assert "metadata.json" in names, "Falta metadata.json en ZIP"
    metadata = json.loads(zf.read("metadata.json"))
    required_keys = ["title", "source_type", "processed_at", "sample_rate"]
    for key in required_keys:
        assert key in metadata, f"metadata.json debe tener key '{key}'"

    print(f"\nZIP contents: {names}")
    print(f"Chords detected: {len(chords)}")


# ---------------------------------------------------------------------------
# Test 2: Timing archivo local — PROC-05
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_file_pipeline_timing(modal_pipeline, sample_audio_bytes):
    """PROC-05: Pipeline de archivo completo en <60 segundos.

    Usa MP3 real de 3 minutos si esta en tests/fixtures/sample_3min.mp3,
    o el WAV sintetico de 30s si no esta disponible.
    """
    audio = _get_test_audio(sample_audio_bytes)
    audio_label = "3min MP3" if len(audio) != len(sample_audio_bytes) else "30s synthetic WAV"

    start = time.time()
    result = modal_pipeline.process.remote(
        audio_bytes=audio,
        source_type="file",
        source_name=f"test_{audio_label.replace(' ', '_')}.wav",
        username="test_user",
    )
    elapsed = time.time() - start

    print(f"\nPipeline file ({audio_label}): {elapsed:.1f}s")

    assert isinstance(result, bytes) and len(result) > 0, "Resultado invalido"
    assert elapsed < 60, (
        f"PROC-05 FALLIDO: pipeline tardó {elapsed:.1f}s (budget: 60s)"
    )


# ---------------------------------------------------------------------------
# Test 3: Timing YouTube — PROC-06
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_youtube_pipeline_timing(modal_pipeline):
    """PROC-06: Pipeline YouTube completo (descarga + proceso) en <65 segundos.

    Usa un video Creative Commons corto (~2 min) para el test.
    Big Buck Bunny clip — video publico y estable.
    """
    # Video Creative Commons corto y estable (~60s)
    # "Tears of Steel" trailer, publico en YouTube
    yt_url = "https://www.youtube.com/watch?v=R6MlUcmOul8"

    start = time.time()
    result = modal_pipeline.process_youtube.remote(
        url=yt_url,
        username="test_user",
    )
    elapsed = time.time() - start

    print(f"\nPipeline YouTube: {elapsed:.1f}s (URL: {yt_url})")

    assert isinstance(result, bytes) and len(result) > 0, "Resultado invalido"
    assert elapsed < 65, (
        f"PROC-06 FALLIDO: pipeline YouTube tardó {elapsed:.1f}s (budget: 65s)"
    )


# ---------------------------------------------------------------------------
# Test 4: Rechazo de archivos fuera de limites — PROC-07
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_reject_oversized_file(modal_pipeline):
    """PROC-07: Archivos >50MB o >10 minutos deben rechazarse con ValueError."""
    import io
    import wave

    # Caso 1: archivo de 51 MB (bytes arbitrarios, no audio valido)
    oversized_bytes = b"\xff" * (51 * 1024 * 1024)

    with pytest.raises(Exception) as exc_info:
        modal_pipeline.process.remote(
            audio_bytes=oversized_bytes,
            source_type="file",
            source_name="oversized.bin",
            username="test_user",
        )
    error_msg = str(exc_info.value)
    print(f"\nOversized rejection error: {error_msg}")
    # El mensaje de error debe mencionar el limite de tamaño
    assert any(
        phrase in error_msg
        for phrase in ["50 MB", "50MB", "limite", "size", "too large", "demasiado"]
    ), f"Error inesperado para archivo >50MB: {error_msg}"

    # Caso 2: WAV de 11 minutos (dentro del limite de tamaño pero excede duracion)
    def _make_wav_bytes(duration_seconds: float, sample_rate: int = 8000) -> bytes:
        import struct

        n_samples = int(duration_seconds * sample_rate)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(b"\x00\x00" * n_samples)
        return buf.getvalue()

    long_wav = _make_wav_bytes(11 * 60)

    with pytest.raises(Exception) as exc_info:
        modal_pipeline.process.remote(
            audio_bytes=long_wav,
            source_type="file",
            source_name="long_audio.wav",
            username="test_user",
        )
    error_msg = str(exc_info.value)
    print(f"Long audio rejection error: {error_msg}")
    assert any(
        phrase in error_msg
        for phrase in ["10 minutos", "10min", "duration", "demasiado largo", "limite"]
    ), f"Error inesperado para audio >10min: {error_msg}"


# ---------------------------------------------------------------------------
# Test 5: Medicion de cold start (informativo, sin assert de tiempo)
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_cold_start_measurement(modal_pipeline, sample_audio_bytes):
    """Mide y documenta el cold start del AudioPipeline.

    NO assert sobre el tiempo de cold start — es informativo para decidir
    si activar GPU memory snapshots. Ver 02-RESEARCH.md para contexto.

    Si cold start > 15s, considerar:
        enable_memory_snapshot=True,
        experimental_options={"enable_gpu_snapshot": True}
    en la definicion de AudioPipeline en app.py.
    """
    # Primera invocacion — incluye cold start si el contenedor no esta warm
    start_cold = time.time()
    result_cold = modal_pipeline.process.remote(
        audio_bytes=sample_audio_bytes,
        source_type="file",
        source_name="cold_start_test_1.wav",
        username="test_user",
    )
    cold_time = time.time() - start_cold

    assert isinstance(result_cold, bytes) and len(result_cold) > 0

    # Segunda invocacion — debe ser significativamente mas rapida (warm container)
    start_warm = time.time()
    result_warm = modal_pipeline.process.remote(
        audio_bytes=sample_audio_bytes,
        source_type="file",
        source_name="cold_start_test_2.wav",
        username="test_user",
    )
    warm_time = time.time() - start_warm

    assert isinstance(result_warm, bytes) and len(result_warm) > 0

    print(f"\nCold start (1st invocation): {cold_time:.1f}s")
    print(f"Warm start (2nd invocation): {warm_time:.1f}s")
    print(f"Cold start overhead: {cold_time - warm_time:.1f}s")

    if cold_time > 15:
        print(
            f"\nWARNING: Cold start {cold_time:.1f}s > 15s threshold. "
            "Considerar enable_memory_snapshot=True en AudioPipeline."
        )
    else:
        print(f"Cold start {cold_time:.1f}s dentro del umbral de 15s.")
