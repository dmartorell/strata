---
phase: quick-12
plan: 01
subsystem: server-pipeline, client-network, player
tags: [lyrics, alignment, whisperx, karaoke, modal]
dependency_graph:
  requires: []
  provides: [forced-alignment-endpoint, aligned-lyrics-in-player]
  affects: [PlayerViewModel, AudioPipeline, stub_processor]
tech_stack:
  added: [whisperx, wav2vec2 alignment model]
  patterns: [base64 audio transfer client→server, silent fallback on failure]
key_files:
  created:
    - server/pipeline/alignment.py
  modified:
    - server/pipeline/image.py
    - server/app.py
    - server/processors/stub_processor.py
    - SiyahambaClient/Network/APIEndpoint.swift
    - SiyahambaClient/Network/APIClient.swift
    - SiyahambaClient/Player/PlayerViewModel.swift
    - SiyahambaClient/Player/PlayerView.swift
decisions:
  - "Vocals sent as base64 from client (not fetched by server): processed results stored client-side only, not on Modal Volume"
  - "AuthTokenProviderProtocol injected as optional with default nil: no breaking change to existing init callers"
  - "Alignment check heuristic: lines with >1 word where all word starts are within 0.01s of each other need alignment"
metrics:
  duration: ~8 min
  completed: 2026-03-22
---

# Quick Task 12: Forced Alignment Endpoint with WhisperX Summary

WhisperX forced alignment pipeline: vocals stem + LRCLib text → precise word-level timestamps via POST /align-lyrics endpoint baked into Modal GPU image.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Server: WhisperX alignment + GPU image + endpoint | e96c8df | image.py, alignment.py, app.py, stub_processor.py |
| 2 | Client: APIEndpoint, APIClient, PlayerViewModel integration | a223be8 | APIEndpoint.swift, APIClient.swift, PlayerViewModel.swift, PlayerView.swift |

## What Was Built

### Server (Task 1)

**`server/pipeline/alignment.py`** — New module wrapping `whisperx.align()`:
- Accepts `vocals_bytes` (WAV), `lyrics_text` (newline-separated lines), `language`
- Converts to mono float32, builds transcript segments, loads wav2vec2 alignment model
- Returns list of `{start, end, text, words: [{word, start, end}]}` dicts
- Cleans up GPU VRAM after alignment (del model_a + torch.cuda.empty_cache)

**`server/pipeline/image.py`** — gpu_image now includes:
- `whisperx` in pip_install
- `_DOWNLOAD_ALIGNMENT_MODEL` command bakes wav2vec2 English model at build time (avoids runtime download)

**`server/app.py`** — `AudioPipeline.align_lyrics` `@modal.method`:
- Accepts `vocals_bytes`, `lyrics_text`, `language`
- Delegates to `pipeline.alignment.align_lyrics`

**`server/processors/stub_processor.py`** — `POST /align-lyrics` endpoint:
- Requires auth
- Accepts JSON body: `{vocals_base64, lyrics_text, language}`
- Decodes base64 vocals, calls `pipeline.align_lyrics.remote.aio()`
- Returns `{segments: [...]}`

### Client (Task 2)

**`APIEndpoint.alignLyrics`** — New case, POST method, path `/align-lyrics`

**`APIClient.alignLyrics(vocalsData:lyricsText:language:token:)`** — New method:
- Sends vocals as base64-encoded string in JSON body
- Decodes `AlignLyricsResponse` → maps to `LyricsFile` with `LyricLine`/`LyricWord` types

**`PlayerViewModel`** changes:
- New optional `authViewModel: (any AuthTokenProviderProtocol)?` init parameter (default `nil`, no breaking change)
- `attemptForcedAlignment()` — called at end of `load()`:
  - Checks `lyricsNeedAlignment()`: skips if lyrics already have distinct word timestamps
  - Reads vocals WAV from cache, sends to alignment endpoint
  - On success: replaces `lyrics` array and writes aligned `LyricsFile` to cache
  - On failure: silently falls back to LRCLib approximate timestamps

**`PlayerView`** — passes `@Environment(AuthViewModel.self)` to `PlayerViewModel` init

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] `server/pipeline/alignment.py` exists
- [x] `server/pipeline/image.py` includes whisperx
- [x] `AudioPipeline.align_lyrics` method added
- [x] `POST /align-lyrics` endpoint registered
- [x] `APIEndpoint.alignLyrics` case exists
- [x] `APIClient.alignLyrics()` method exists
- [x] `PlayerViewModel.attemptForcedAlignment()` called in `load()`
- [x] Build succeeded: `** BUILD SUCCEEDED **`
- [x] Commits: e96c8df (server), a223be8 (client)

## Self-Check: PASSED
