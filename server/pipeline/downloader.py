"""YouTube audio downloader with cookies, retry and exponential backoff.

Descarga audio de una URL de YouTube usando yt-dlp con:
- Autenticacion via cookies (Modal Secret YT_COOKIES_TXT)
- 3 reintentos con backoff exponencial (1s, 2s, 4s)
- Extraccion de metadatos para metadata.json

El cookie handling usa una env var porque Modal Secrets inyectan variables de
entorno, NO ficheros en disco. downloader.py escribe el contenido a
/tmp/yt-cookies.txt antes de cada descarga.

Configurar el Secret:
    modal secret create youtube-cookies YT_COOKIES_TXT="$(cat cookies.txt)"
"""

import os
import time
from urllib.parse import urlparse


class YouTubeAuthError(Exception):
    """YouTube requiere autenticación — cookies expiradas o ausentes."""
    pass


_ALLOWED_HOSTNAMES = frozenset({
    "youtube.com",
    "www.youtube.com",
    "youtu.be",
    "m.youtube.com",
})

_COOKIES_TMP_PATH = "/tmp/yt-cookies.txt"


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


def _write_cookies() -> str | None:
    """Escribe cookies de la env var YT_COOKIES_TXT a fichero temporal.

    Returns:
        Ruta al fichero de cookies, o None si la env var no esta definida.
    """
    yt_cookies_env = os.environ.get("YT_COOKIES_TXT", "")
    if yt_cookies_env:
        with open(_COOKIES_TMP_PATH, "w") as f:
            f.write(yt_cookies_env)
        return _COOKIES_TMP_PATH
    return None


def _build_ydl_opts(output_dir: str, cookies_path: str | None) -> dict:
    """Construye las opciones de yt-dlp."""
    opts = {
        "format": "m4a/bestaudio/best",
        "outtmpl": os.path.join(output_dir, "%(id)s.%(ext)s"),
        "retries": 3,
        "socket_timeout": 30,
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "m4a",
            }
        ],
        "quiet": True,
    }
    if cookies_path:
        opts["cookiefile"] = cookies_path
    return opts


def _extract_metadata(url: str, info: dict) -> dict:
    """Extrae los campos de metadatos YouTube del info_dict de yt-dlp."""
    return {
        "youtube_url": url,
        "youtube_id": info.get("id"),
        "title": info.get("title"),
        "uploader": info.get("uploader"),
        "thumbnail_url": info.get("thumbnail"),
        "duration_seconds": info.get("duration"),
    }


def download_youtube_audio(url: str, output_dir: str) -> tuple[bytes, dict]:
    """Descarga audio de YouTube y devuelve bytes + metadatos.

    Args:
        url: URL de YouTube (youtube.com o youtu.be).
        output_dir: Directorio donde yt-dlp escribe el archivo descargado.

    Returns:
        Tupla (audio_bytes, metadata) donde:
        - audio_bytes: Contenido del archivo de audio descargado (m4a).
        - metadata: Dict con campos YouTube para metadata.json:
            {youtube_url, youtube_id, title, uploader, thumbnail_url, duration_seconds}

    Raises:
        ValueError: Si la URL no es de YouTube.
        Exception: Si la descarga falla tras 3 intentos.
    """
    import yt_dlp

    _validate_youtube_url(url)

    cookies_path = _write_cookies()
    ydl_opts = _build_ydl_opts(output_dir, cookies_path)

    last_exception: Exception | None = None

    for attempt in range(3):
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)

            # Localizar el archivo descargado en output_dir
            video_id = info.get("id", "")
            audio_path: str | None = None

            # yt-dlp puede cambiar la extension tras el postprocessor
            for ext in ("m4a", "mp4", "webm", "opus", "ogg", "mp3"):
                candidate = os.path.join(output_dir, f"{video_id}.{ext}")
                if os.path.exists(candidate):
                    audio_path = candidate
                    break

            if audio_path is None:
                # Buscar cualquier archivo en output_dir con ese id como prefijo
                for fname in os.listdir(output_dir):
                    if fname.startswith(video_id):
                        audio_path = os.path.join(output_dir, fname)
                        break

            if audio_path is None:
                raise RuntimeError(
                    f"yt-dlp no genero ningun archivo en {output_dir} para video_id={video_id!r}"
                )

            with open(audio_path, "rb") as f:
                audio_bytes = f.read()

            # Limpiar archivo descargado
            try:
                os.unlink(audio_path)
            except OSError:
                pass

            metadata = _extract_metadata(url, info)
            return audio_bytes, metadata

        except Exception as e:
            last_exception = e
            if "Sign in to confirm" in str(e) or "confirm you're not a bot" in str(e):
                raise YouTubeAuthError(
                    "YouTube requiere autenticación. Las cookies han expirado o no están configuradas."
                ) from e
            if attempt < 2:
                sleep_seconds = 2 ** attempt  # 1s, 2s
                time.sleep(sleep_seconds)

    raise last_exception  # type: ignore[misc]
