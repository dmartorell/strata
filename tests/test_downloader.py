"""Tests de integracion del downloader YouTube en Modal.

Todos los tests requieren:
- Modal token configurado (MODAL_TOKEN_ID + MODAL_TOKEN_SECRET)
- App "strata" deployada: `modal deploy server/app.py`
- Secret "youtube-cookies" configurado en Modal con YT_COOKIES_TXT

Los tests verifican:
- PROC-08: descarga real de YouTube con cookies desde IPs de Modal
- Rechazo de URLs invalidas (no YouTube) y URLs inexistentes
- Presencia de cookies en el contenedor

Ejecutar con:
    pytest tests/test_downloader.py -x -v --timeout=120
"""

import pytest


# ---------------------------------------------------------------------------
# Test 1: Descarga real de YouTube — PROC-08
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_youtube_download_real_url(modal_pipeline):
    """PROC-08: Descarga audio real de YouTube via AudioPipeline en Modal.

    Usa un video Creative Commons corto y estable.
    Verifica que el pipeline completo funciona desde IPs de datacenter de Modal.
    """
    import io
    import json
    import zipfile

    # Video Creative Commons corto (~60s) — estable y publico
    yt_url = "https://www.youtube.com/watch?v=R6MlUcmOul8"

    result = modal_pipeline.process_youtube.remote(
        url=yt_url,
        username="test_user",
    )

    # El resultado es el ZIP completo del pipeline
    assert isinstance(result, bytes), "El resultado debe ser bytes"
    assert len(result) > 0, "El resultado no debe estar vacio"

    buf = io.BytesIO(result)
    assert zipfile.is_zipfile(buf), "El resultado debe ser un ZIP valido"

    buf.seek(0)
    with zipfile.ZipFile(buf, "r") as zf:
        names = zf.namelist()

        # Verificar metadata YouTube esta presente
        assert "metadata.json" in names, "Falta metadata.json"
        metadata = json.loads(zf.read("metadata.json"))

        # La metadata debe tener info YouTube
        assert metadata.get("youtube_url") == yt_url or metadata.get("source_type") == "youtube", (
            "metadata.json debe contener informacion de YouTube"
        )

        # Verificar que hay stems (audio descargado y procesado)
        has_stems = any(name.endswith(".wav") for name in names)
        assert has_stems, f"El ZIP debe contener stems WAV. Contenido: {names}"

    print(f"\nYouTube download OK: {yt_url}")
    print(f"ZIP contents: {names}")
    if "metadata.json" in names:
        buf.seek(0)
        with zipfile.ZipFile(io.BytesIO(result), "r") as zf:
            metadata = json.loads(zf.read("metadata.json"))
        print(f"Title: {metadata.get('title', 'N/A')}")
        print(f"YouTube ID: {metadata.get('youtube_id', 'N/A')}")
        print(f"Duration: {metadata.get('duration_seconds', 'N/A')}s")


# ---------------------------------------------------------------------------
# Test 2: URLs invalidas y no YouTube
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_youtube_invalid_url(modal_pipeline):
    """URL invalida (no YouTube) debe fallar con ValueError.

    Verifica el rechazo en la capa de validacion del downloader.
    """
    # URL valida pero no de YouTube
    non_youtube_url = "https://soundcloud.com/some-artist/some-track"

    with pytest.raises(Exception) as exc_info:
        modal_pipeline.process_youtube.remote(
            url=non_youtube_url,
            username="test_user",
        )

    error_msg = str(exc_info.value)
    print(f"\nNon-YouTube URL rejection: {error_msg}")

    # El error debe mencionar que solo YouTube esta soportado
    assert any(
        phrase in error_msg
        for phrase in ["YouTube", "youtube", "hostname", "solo", "only"]
    ), f"Error inesperado para URL no YouTube: {error_msg}"


@pytest.mark.integration
def test_youtube_nonexistent_video(modal_pipeline):
    """URL de YouTube con video inexistente debe fallar despues de reintentos.

    El downloader tiene 3 reintentos con backoff exponencial.
    """
    # Video ID claramente invalido
    nonexistent_url = "https://www.youtube.com/watch?v=XXXXXXXXXXX_INVALID"

    with pytest.raises(Exception) as exc_info:
        modal_pipeline.process_youtube.remote(
            url=nonexistent_url,
            username="test_user",
        )

    error_msg = str(exc_info.value)
    print(f"\nNonexistent video error: {error_msg}")

    # No verifica el mensaje exacto — yt-dlp puede variar — solo que falla
    assert exc_info.value is not None, "Debe lanzar una excepcion para video inexistente"


# ---------------------------------------------------------------------------
# Test 3: Presencia de cookies en el contenedor
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_youtube_cookies_present(modal_pipeline):
    """Verifica que el contenedor tiene acceso al Secret de cookies YouTube.

    Este test es indirecto: si test_youtube_download_real_url pasa,
    las cookies estan funcionando. Este test verifica el acceso exitoso
    a la descarga como proxy de la presencia de cookies.

    Si YouTube bloquea desde IPs de Modal sin cookies, este test falla
    aunque el Secret este configurado — puede requerir actualizar las cookies.
    """
    import io
    import zipfile

    # Usamos un video que tipicamente requiere cookies para IPs de datacenter
    yt_url = "https://www.youtube.com/watch?v=R6MlUcmOul8"

    try:
        result = modal_pipeline.process_youtube.remote(
            url=yt_url,
            username="test_user",
        )
        assert isinstance(result, bytes) and len(result) > 0

        buf = io.BytesIO(result)
        assert zipfile.is_zipfile(buf), "Resultado debe ser ZIP valido"

        print("\nCookies present and working: YouTube download succeeded from Modal IPs")

    except Exception as e:
        error_msg = str(e)
        if "cookies" in error_msg.lower() or "403" in error_msg or "sign in" in error_msg.lower():
            pytest.fail(
                f"Fallo de cookies YouTube — actualizar Modal Secret 'youtube-cookies'.\n"
                f"Error: {error_msg}\n\n"
                f"Pasos para actualizar:\n"
                f"  1. Exportar cookies desde navegador (extension EditThisCookie o similar)\n"
                f"  2. modal secret create youtube-cookies YT_COOKIES_TXT=\"$(cat cookies.txt)\"\n"
                f"  3. modal deploy server/app.py"
            )
        else:
            # Otro tipo de error — re-lanzar para debug
            raise
