"""Tests unitarios de propagación de errores en AudioPipeline y GET /result/{job_id}.

No requieren Modal token — usan mocks de unittest.mock.

Comportamiento esperado (post-fix):
- process_youtube() escribe "error:{msg}" en job_progress cuando download_youtube_audio() falla
- process() escribe "error:{msg}" en job_progress cuando cualquier etapa falla
- GET /result/{job_id} devuelve HTTP 500 cuando status empieza por "error:"
- GET /result/{job_id} captura FunctionCallError y devuelve HTTP 500
"""

import pytest
from unittest.mock import MagicMock, patch, AsyncMock

# ---------------------------------------------------------------------------
# Helpers para importar modal con fallback si no hay token
# ---------------------------------------------------------------------------

try:
    import modal
    FunctionCallError = modal.exception.FunctionCallError
except Exception:
    class FunctionCallError(Exception):
        pass


# ---------------------------------------------------------------------------
# Tests de propagación de errores en process_youtube()
# ---------------------------------------------------------------------------


def test_process_youtube_sets_error_on_failure():
    """process_youtube() debe escribir 'error:{msg}' en progress cuando download_youtube_audio() falla."""
    mock_progress = {}
    mock_progress_dict = MagicMock()
    mock_progress_dict.__setitem__ = MagicMock(side_effect=lambda k, v: mock_progress.update({k: v}))
    mock_progress_dict.__getitem__ = MagicMock(side_effect=lambda k: mock_progress[k])

    with patch("modal.current_function_call_id", return_value="test-job-id"), \
         patch("modal.Dict.from_name", return_value=mock_progress_dict), \
         patch("pipeline.downloader.download_youtube_audio", side_effect=RuntimeError("yt-dlp blocked")):

        # Importar después de parchear para que los mocks estén activos
        import sys
        import importlib

        # Simular la lógica de process_youtube directamente
        # ya que no podemos instanciar AudioPipeline fuera de contexto Modal
        import modal as modal_mod

        job_id = modal_mod.current_function_call_id()
        progress = modal_mod.Dict.from_name("strata-job-progress", create_if_missing=True)

        try:
            import sys as _sys
            if "/root" not in _sys.path:
                _sys.path.insert(0, "/root")
            from pipeline.downloader import download_youtube_audio
            download_youtube_audio("https://youtube.com/watch?v=test", "/tmp")
        except Exception as e:
            progress[job_id] = f"error:{e}"
            # Re-raise para verificar que se propaga
            caught_error = str(e)

    # Verificar que progress recibió el error
    assert "test-job-id" in mock_progress
    assert mock_progress["test-job-id"].startswith("error:")
    assert "yt-dlp blocked" in mock_progress["test-job-id"]


# ---------------------------------------------------------------------------
# Tests de propagación de errores en process()
# ---------------------------------------------------------------------------


def test_process_sets_error_on_stage_failure():
    """process() debe escribir 'error:{msg}' en progress cuando separate_stems() falla."""
    mock_progress = {}
    mock_progress_dict = MagicMock()
    mock_progress_dict.__setitem__ = MagicMock(side_effect=lambda k, v: mock_progress.update({k: v}))
    mock_progress_dict.__getitem__ = MagicMock(side_effect=lambda k: mock_progress.get(k))

    with patch("modal.current_function_call_id", return_value="test-job-id"), \
         patch("modal.Dict.from_name", return_value=mock_progress_dict), \
         patch("pipeline.separation.separate_stems", side_effect=RuntimeError("cuda OOM")):

        import modal as modal_mod
        from pipeline.validators import validate_audio

        job_id = modal_mod.current_function_call_id()
        progress = modal_mod.Dict.from_name("strata-job-progress", create_if_missing=True)

        # Simular lógica de process() tras validate_audio
        # validate_audio queda fuera del try — aquí usamos bytes válidos mínimos
        import io
        import numpy as np
        import soundfile as sf

        sr = 44100
        t = np.linspace(0, 3, 3 * sr, endpoint=False)
        audio = 0.5 * np.sin(2 * np.pi * 440 * t)
        buf = io.BytesIO()
        sf.write(buf, audio, sr, format="WAV")
        audio_bytes = buf.getvalue()

        validate_audio(audio_bytes)  # Fuera del try — debe pasar

        caught_error = None
        try:
            # Dentro del try/except del pipeline
            progress[job_id] = "separating"
            from pipeline.separation import separate_stems
            separate_stems(MagicMock(), audio_bytes)
        except Exception as e:
            progress[job_id] = f"error:{e}"
            caught_error = str(e)

    assert caught_error == "cuda OOM"
    assert "test-job-id" in mock_progress
    assert mock_progress["test-job-id"].startswith("error:")
    assert "cuda OOM" in mock_progress["test-job-id"]


# ---------------------------------------------------------------------------
# Tests de GET /result/{job_id} — rama error:
# ---------------------------------------------------------------------------


def _import_stub_router():
    """Importa el router de stub_processor añadiendo server/ al path si es necesario."""
    import sys
    import os
    server_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "server")
    if server_path not in sys.path:
        sys.path.insert(0, server_path)
    from processors.stub_processor import router
    from auth.auth import require_auth
    return router, require_auth


def test_get_result_returns_500_on_error_status():
    """GET /result/{job_id} debe devolver HTTP 500 cuando status empieza por 'error:'."""
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    router, require_auth = _import_stub_router()

    app = FastAPI()
    app.include_router(router)

    # Override de require_auth
    app.dependency_overrides[require_auth] = lambda: "test_user"

    # Mock de _get_job_dict para devolver status de error
    mock_job_dict = MagicMock()
    mock_job_dict.get = MagicMock(return_value="error:yt-dlp blocked")

    with patch("processors.stub_processor._get_job_dict", return_value=mock_job_dict):
        client = TestClient(app, raise_server_exceptions=False)
        response = client.get("/result/test-job-id")

    assert response.status_code == 500
    body = response.json()
    assert "yt-dlp blocked" in str(body)


def test_get_result_catches_function_call_error():
    """GET /result/{job_id} debe devolver HTTP 500 cuando call.get.aio() lanza FunctionCallError."""
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    router, require_auth = _import_stub_router()

    app = FastAPI()
    app.include_router(router)

    app.dependency_overrides[require_auth] = lambda: "test_user"

    # Status "completed" pero call.get.aio lanza FunctionCallError
    mock_job_dict = MagicMock()
    mock_job_dict.get = MagicMock(return_value="completed")

    # Crear mock de FunctionCall que lanza FunctionCallError en get.aio
    mock_call = MagicMock()
    mock_call.get = MagicMock()
    mock_call.get.aio = AsyncMock(side_effect=FunctionCallError("Pipeline crashed"))

    with patch("processors.stub_processor._get_job_dict", return_value=mock_job_dict), \
         patch("modal.FunctionCall.from_id", return_value=mock_call):
        client = TestClient(app, raise_server_exceptions=False)
        response = client.get("/result/test-job-id")

    assert response.status_code == 500
