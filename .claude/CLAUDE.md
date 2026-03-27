# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Siyahamba is a macOS audio processing app: import a song → stem separation (Demucs) → chord detection → interactive playback with stems, synced lyrics, and chords. Two-component architecture:

- **Backend:** Python + FastAPI on Modal.com (serverless GPU T4)
- **Client:** Native macOS app in SwiftUI (macOS 14+, Swift 5.9)

Two users (father & son) for personal music practice. Distributed as ad-hoc signed `.app`.

## Build & Run Commands

### Swift Client (XcodeGen-based)

```bash
# Regenerate Xcode project after changing project.yml or adding/removing Swift files
xcodegen generate

# Build from CLI
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug build

# Run Swift tests
xcodebuild -project Siyahamba.xcodeproj -scheme SiyahambaTests -configuration Debug test

# Open in Xcode (then Cmd+R)
open Siyahamba.xcodeproj
```

### Backend (Modal)

```bash
# Local dev with hot reload
cd server && modal serve app.py

# Deploy to Modal
cd server && modal deploy app.py

# Python tests (unit only, no GPU needed)
pytest tests/ -m "not integration"

# Integration tests (requires prior deploy)
pytest tests/ -m integration

# Run a single test
pytest tests/test_chords.py -k "test_name"
```

## Architecture

### Client (Siyahamba/)

Uses Swift `@Observable` macro (not Combine) with `@Environment` injection. All ViewModels and engines are `@MainActor`.

**Dependency graph created in `SiyahambaApp.swift`:**
`CacheManager` → `LibraryStore` → `ImportViewModel` ← `APIClient` + `AuthViewModel`
`PlaybackEngine` → `TunerEngine`
`PlayerViewModel` (created per song in `PlayerView`) merges lyrics, chords, and engine state.

**Key modules:**
- `Audio/PlaybackEngine` — AVAudioEngine graph: 4 `AVAudioPlayerNode`s → per-stem `AVAudioMixerNode`s → `AVAudioUnitTimePitch` → main mixer. Supports real-time pitch shifting and A/B looping.
- `Import/ImportViewModel` — Orchestrates file upload → server processing → polling → ZIP download → cache extraction. Handles drag-and-drop and YouTube URL import.
- `Library/CacheManager` — Manages `~/Music/Siyahamba/` cache directory. Each processed song stored as folder with stems (WAV), metadata, lyrics, and chords JSON.
- `Library/LibraryStore` — In-memory song catalog backed by JSON on disk. Source of truth for the library sidebar.
- `Player/PlayerViewModel` — Per-song controller that loads lyrics/chords from cache, merges chords onto lyric lines for rehearsal view, and tracks current playback position.
- `Network/APIClient` — Authenticated HTTP client using `URLSession`. Token from `AuthViewModel`, endpoints defined in `APIEndpoint`.

**Navigation:** `ContentView` switches between `LibraryView` and `PlayerView` via `selectedSong` state (no NavigationStack).

### Backend (server/)

Single Modal app (`app.py`) with three components:
- **`ProcessingService`** — GPU class (T4, max 2 containers) with `@modal.enter()` for model preloading (Demucs). Runs the full pipeline: download (if URL) → validate → separate → detect chords → transcribe → package ZIP.
- **Web handler** — FastAPI endpoints: auth, file upload, job status polling, results download, usage stats.
- **`modal.Dict`** for job progress, **`modal.Volume`** for usage persistence.

Pipeline stages in `server/pipeline/`: separation → chord detection → transcription alignment → ZIP packaging.

## Key Conventions

- **XcodeGen:** `project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after adding/removing Swift files or changing build settings. Never edit `.xcodeproj` directly.
- **SPM dependencies** (defined in `project.yml`): JWTDecode, ZIPFoundation, DSWaveformImage.
- **API base URL** overridable via `SIYAHAMBA_API_URL` env var.
- **Auth model:** Single shared password, JWT with 90-day expiry stored in Keychain.
- **Language:** Code comments and UI strings are in Spanish. Variable/type names are in English.
- **Cache format:** `~/Music/Siyahamba/{songId}/` containing `vocals.wav`, `drums.wav`, `bass.wav`, `other.wav`, `metadata.json`, `lyrics.json`, `chords.json`.
