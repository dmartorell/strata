"""YouTube audio downloader using Cobalt Tools API with retry and exponential backoff.

Descarga audio de una URL de YouTube usando la API de Cobalt Tools:
- Sin cookies ni autenticacion de YouTube
- 3 reintentos con backoff exponencial (1s, 2s, 4s)
- Extraccion de metadatos para metadata.json

Configuracion via variables de entorno:
    COBALT_API_URL  URL base de la instancia Cobalt (default: https://api.cobalt.tools)
    COBALT_API_KEY  API key opcional para instancias autenticadas
"""

import json
import os
import re
import time
import urllib.request
from urllib.parse import urlparse


class YouTubeAuthError(Exception):
    """YouTube requiere autenticacion -- Cobalt no pudo acceder al video."""
    pass


_ALLOWED_HOSTNAMES = frozenset({
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
    "m.youtube.com",
})

COBALT_API_URL = os.environ.get("COBALT_API_URL", "https://api.cobalt.tools")
COBALT_API_KEY = os.environ.get("COBALT_API_KEY", "")

_COBALT_ERROR_KEYWORDS = (
    "rate limit",
    "ratelimit",
    "content.unavailable",
    "content.age_restricted",
    "content.geoblocked",
    "youtube.login",
    "youtube.age",
    "youtube.blocked",
    "youtube.private",
    "youtube.unavailable",
    "youtube.auth",
)


def _validate_youtube_url(url: str) -> None:
    """Valida que la URL sea de YouTube.

    Raises:
        ValueError: Si el hostname no es de YouTube.
    """
    parsed = urlparse(url)
    if parsed.hostname not in _ALLOWED_HOSTNAMES:
        raise ValueError(
            f"Solo URLs de YouTube soportadas. Hostname recibido: {parsed.hostname!r}"
        )


def _extract_video_id(url: str) -> str | None:
    """Extrae el video ID de una URL de YouTube.

    Soporta:
        https://www.youtube.com/watch?v=XXXXXXXXXXX
        https://youtu.be/XXXXXXXXXXX
    """
    # youtu.be/ID
    short = re.search(r"youtu\.be/([A-Za-z0-9_-]{11})", url)
    if short:
        return short.group(1)
    # youtube.com/watch?v=ID
    full = re.search(r"[?&]v=([A-Za-z0-9_-]{11})", url)
    if full:
        return full.group(1)
    return None


def download_youtube_audio(url: str, output_dir: str) -> tuple[bytes, dict]:
    """Descarga audio de YouTube via Cobalt API y devuelve bytes + metadatos.

    Args:
        url: URL de YouTube (youtube.com o youtu.be).
        output_dir: Directorio de salida (no se usa; se mantiene por compatibilidad).

    Returns:
        Tupla (audio_bytes, metadata) donde:
        - audio_bytes: Contenido del archivo MP3 descargado.
        - metadata: Dict con campos YouTube para metadata.json:
            {youtube_url, youtube_id, title, uploader, thumbnail_url, duration_seconds}

    Raises:
        ValueError: Si la URL no es de YouTube.
        YouTubeAuthError: Si Cobalt reporta error de acceso a YouTube.
        Exception: Si la descarga falla tras 3 intentos.
    """
    _validate_youtube_url(url)

    last_exception: Exception | None = None

    for attempt in range(3):
        try:
            cobalt_response = _call_cobalt_api(url)

            status = cobalt_response.get("status", "")
            if status in ("tunnel", "redirect"):
                download_url = cobalt_response.get("url", "")
                filename = cobalt_response.get("filename", "Unknown")
                audio_bytes = _download_bytes(download_url)

                metadata = {
                    "youtube_url": url,
                    "youtube_id": _extract_video_id(url),
                    "title": filename,
                    "uploader": None,
                    "thumbnail_url": None,
                    "duration_seconds": None,
                }
                return audio_bytes, metadata

            elif status == "error":
                error_info = cobalt_response.get("error", {})
                error_code = error_info.get("code", "") if isinstance(error_info, dict) else str(error_info)
                error_lower = error_code.lower()
                if any(kw in error_lower for kw in _COBALT_ERROR_KEYWORDS):
                    raise YouTubeAuthError(
                        f"Cobalt no pudo acceder al video de YouTube: {error_code}"
                    )
                raise RuntimeError(f"Cobalt API error: {error_code}")

            else:
                raise RuntimeError(f"Cobalt API respuesta inesperada con status: {status!r}")

        except YouTubeAuthError:
            raise
        except Exception as e:
            last_exception = e
            if attempt < 2:
                time.sleep(2 ** attempt)

    raise last_exception  # type: ignore[misc]


def _call_cobalt_api(url: str) -> dict:
    """Hace POST al endpoint Cobalt y devuelve el JSON de respuesta.

    Args:
        url: URL de YouTube a descargar.

    Returns:
        Dict con la respuesta JSON de Cobalt.

    Raises:
        RuntimeError: Si la llamada HTTP falla.
    """
    payload = json.dumps({
        "url": url,
        "audioFormat": "mp3",
        "audioBitrate": "320",
    }).encode("utf-8")

    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    if COBALT_API_KEY:
        headers["Authorization"] = f"Api-Key {COBALT_API_KEY}"

    req = urllib.request.Request(
        COBALT_API_URL,
        data=payload,
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _download_bytes(download_url: str) -> bytes:
    """Descarga los bytes de audio desde la URL proporcionada por Cobalt.

    Args:
        download_url: URL directa de descarga devuelta por Cobalt.

    Returns:
        Bytes del archivo de audio.
    """
    req = urllib.request.Request(download_url)
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()
