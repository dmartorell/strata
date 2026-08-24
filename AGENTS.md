# Siyahamba

## Project

Siyahamba is a native macOS audio-practice app. It imports local audio or a YouTube URL, processes it on Modal, then plays separated stems with synchronized lyrics and chords.

- Client: SwiftUI, Swift 5.9, macOS 14+
- Backend: Python, FastAPI, Modal
- UI strings and comments: Spanish. Types and variables: English.

Read `.planning/STATE.md` before work that depends on active roadmap, pending tasks, or prior decisions. Read `.planning/codebase/` for broader architecture context.

## Commands

```bash
# Regenerate the Xcode project after changing project.yml or Swift file membership
xcodegen generate

# Build the macOS client
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug build

# Run Swift tests
xcodebuild -project Siyahamba.xcodeproj -scheme Siyahamba -configuration Debug test

# Run backend unit tests
pytest tests/ -m "not integration"

# Run backend integration tests against a deployed Modal app
pytest tests/ -m integration

# Modal development and deployment
(cd server && modal serve app.py)
(cd server && modal deploy app.py)
```

## Conventions

- `project.yml` is the source of truth for Xcode project settings and file membership. Do not edit `Siyahamba.xcodeproj` directly.
- Swift uses `@Observable` and `@Environment`, not Combine. View models and engines are `@MainActor`.
- The cache is `~/Music/Siyahamba/{songId}/` with the stems and JSON metadata.
- API base URL can be overridden with `SIYAHAMBA_API_URL`.
- Authentication is a shared password and a JWT stored in Keychain.
- Keep changes scoped. Do not deploy Modal or change credentials unless explicitly requested.

## Architecture

- `Siyahamba/Audio`: AVAudioEngine multi-stem playback, pitch shifting, A/B loop, tuner.
- `Siyahamba/Import`: upload/URL import, polling, download, extraction, queue.
- `Siyahamba/Library`: local cache and song catalog.
- `Siyahamba/Player`: lyrics, chords, rehearsal sheet, transport, waveforms.
- `Siyahamba/Network`: authenticated URLSession API client and endpoints.
- `server/app.py`: Modal app and FastAPI web handler.
- `server/pipeline/`: separation, chord detection, alignment, packaging.

## Pi

Pi loads this file automatically. Project skills include Swift audit and SwiftUI guidance, including a performance-audit workflow. Use the relevant skill before specialized SwiftUI audit work.
