---
phase: quick-8
plan: 1
subsystem: server/pipeline
tags: [youtube, cobalt, downloader, yt-dlp, modal]
dependency_graph:
  requires: []
  provides: [cobalt-based-youtube-downloader]
  affects: [server/pipeline/downloader.py, server/pipeline/image.py, server/app.py]
tech_stack:
  added: []
  patterns: [urllib.request for HTTP (stdlib), Cobalt Tools API POST/GET]
key_files:
  created: []
  modified:
    - server/pipeline/downloader.py
    - server/pipeline/image.py
    - server/app.py
decisions:
  - "Usar urllib stdlib en lugar de requests para mantener downloader.py sin dependencias nuevas"
  - "YouTubeAuthError se lanza cuando el error_code de Cobalt contiene keywords de bloqueo YouTube"
  - "COBALT_API_URL default a https://api.cobalt.tools (instancia publica); COBALT_API_KEY opcional"
  - "output_dir mantenido en firma para compatibilidad pero no se usa (Cobalt devuelve bytes directamente)"
metrics:
  duration: ~5 min
  completed: 2026-03-21
  tasks_completed: 2
  files_modified: 3
---

# Quick Task 8: Replace yt-dlp with Cobalt Tools API — Summary

**One-liner:** Sustitucion de yt-dlp por Cobalt Tools API como motor de descarga YouTube usando urllib stdlib, eliminando cookies y el Secret de Modal.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Reescribir downloader.py con Cobalt API | 84c811b | server/pipeline/downloader.py |
| 2 | Limpiar dependencias y secrets de yt-dlp | 6d535ef | server/pipeline/image.py, server/app.py |

## What Was Built

### Task 1: downloader.py reescrito con Cobalt API

- Eliminado: `yt_dlp`, `_write_cookies`, `_build_ydl_opts`, `_extract_metadata`, `_COOKIES_TMP_PATH`
- Nuevo: `_call_cobalt_api(url)` — POST a `COBALT_API_URL` con `{url, audioFormat: "mp3", audioBitrate: "320"}`
- Nuevo: `_download_bytes(download_url)` — GET con timeout 120s para descargar los bytes de audio
- Nuevo: `_extract_video_id(url)` — regex para youtu.be y youtube.com/watch?v=
- Mantenido: `YouTubeAuthError`, `_ALLOWED_HOSTNAMES`, `_validate_youtube_url`, retry 3 intentos con backoff 1s/2s
- Configuracion: `COBALT_API_URL` (default `https://api.cobalt.tools`), `COBALT_API_KEY` opcional para header `Authorization: Api-Key`

### Task 2: Limpieza de dependencias

- `server/pipeline/image.py`: eliminado `"yt-dlp"` de `.pip_install(...)` en `gpu_image`
- `server/app.py`: eliminado `secrets=[modal.Secret.from_name("youtube-cookies")]` del decorator `@app.cls` de `AudioPipeline`

## Verification

All plan verification checks passed:
1. `from server.pipeline.downloader import download_youtube_audio, YouTubeAuthError` — OK
2. `yt-dlp` count in `image.py` — 0
3. `youtube-cookies` count in `app.py` — 0
4. `cobalt` count in `downloader.py` — 33 (>0)

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `server/pipeline/downloader.py` — present, uses Cobalt API
- `server/pipeline/image.py` — present, yt-dlp removed
- `server/app.py` — present, youtube-cookies secret removed
- Commit `84c811b` — exists (Task 1)
- Commit `6d535ef` — exists (Task 2)
