# Stack Research

**Domain:** macOS native audio processing app with serverless GPU backend
**Researched:** 2026-03-02
**Confidence:** MEDIUM-HIGH (core AI models and Modal verified; some Swift library versions from training data + SPM index)

---

## Recommended Stack

### macOS Client (Swift/SwiftUI)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| SwiftUI | macOS 14+ SDK | UI framework | Native macOS look and feel; declarative; the requirement specifies native macOS |
| AVAudioEngine | macOS 14+ SDK | Multi-stem playback + pitch shift | Apple's own audio graph API; zero dependencies; handles multiple player nodes natively for synchronized playback |
| AVAudioPlayerNode | macOS 14+ SDK | Per-stem playback node | One node per stem (vocals, drums, bass, other) feeds into AVAudioEngine for independent volume/mute control |
| AVAudioUnitTimePitch | macOS 14+ SDK | Real-time pitch shifting | Apple's built-in time/pitch processor; range -2400 to +2400 cents (24 semitones); zero latency configuration change |
| URLSession | macOS 14+ SDK | HTTP client for Modal API | Sufficient for simple REST calls and file upload; no third-party network dep needed |
| KeychainAccess | 4.2.2 | JWT token secure storage | Thin Swift wrapper over Security.framework; SPM-native; avoids raw SecItem calls |

**Install (SPM):**
```
https://github.com/kishikawakatsumi/KeychainAccess.git — from: "4.2.2"
```

**Note on KeychainAccess:** Last release 4 years ago but the Keychain API itself is stable. Alternatively use `Security.framework` directly — the raw API is 20 lines and avoids the dependency. Use KeychainAccess for speed; raw Security for zero-dep preference.

---

### Backend — Modal Serverless GPU (Python)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| modal | 1.3.4 | Serverless GPU orchestration | Stable 1.0 API since May 2025; Python 3.10-3.14 support; T4 GPU at $0.000164/s (≈$0.59/hr); $30/mo free credits covers ~100 songs |
| FastAPI | 0.135.1 | HTTP API layer inside Modal | `@modal.fastapi_endpoint` wraps any FastAPI app natively; handles multipart file upload + JSON responses |
| Python | 3.11 | Runtime | Supported by all three AI models; PyPI packages built for it; Modal images default to 3.11 |

**GPU type:** T4 (as per project constraints). Modal syntax: `@app.function(gpu="T4")`

---

### AI Models (Python backend)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| demucs | 4.0.1 | Stem separation | Facebook Research SOTA; `htdemucs` model separates into vocals/drums/bass/other in one pass; free/open-source; GPU-accelerated |
| whisperx | 3.8.1 | Lyrics transcription + word timestamps | Built on Whisper large-v2; adds forced phoneme alignment for word-level timestamps needed for karaoke sync; released 2026-02-14; requires CUDA 12.8 |
| CREMA (bmcfee/crema) | 0.2.0 | Chord detection | Only library that gives time-stamped chord predictions from raw audio in one call; structured prediction model; 602-class vocabulary |

**CREMA warning:** Last release April 2022; 95 stars; limited maintenance. It still works and is the only clean Python chord-detection-with-timestamps library. If it breaks on Python 3.11+, fall back to `madmom`'s `CRFChordRecognitionProcessor`. Test CREMA first.

---

### Backend Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| PyJWT | 2.11.0 | JWT encode/decode | Auth tokens shared between Modal endpoint and SwiftUI client; released 2026-01-30; actively maintained; replaces deprecated python-jose |
| bcrypt | 5.0.0 | Password hashing | Hash the single shared password at registration; Rust-implemented; deliberately slow; Python 3.8+ |
| yt-dlp | 2026.02.21 | YouTube audio extraction | Only maintained YouTube downloader; Python library interface via `yt_dlp.YoutubeDL`; requires Deno runtime in container |
| Deno | latest | JS runtime for yt-dlp | Required since yt-dlp 2025.11.12 for YouTube support; install in Modal image alongside yt-dlp |
| ffmpeg | system | Audio format conversion | yt-dlp post-processing requires it; also normalizes input audio for Demucs |
| torch | 2.x (CUDA 12.1+) | PyTorch GPU runtime | Required by Demucs and WhisperX; Modal CUDA images ship with it; pin to CUDA version matching Modal's T4 driver |

---

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16+ | macOS app build + SwiftUI preview | Required; macOS 14 SDK included |
| Swift Package Manager | Dependency management (client side) | Built into Xcode; use for KeychainAccess |
| modal CLI | Deploy and debug Modal functions | `pip install modal` then `modal deploy` |
| modal serve | Local dev loop for backend | Hot-reload; runs GPU functions on Modal while you edit locally |
| Python 3.11 venv | Backend local dev | Match Python version to Modal image |

---

## Installation

### macOS Client

```swift
// Package.swift dependency
.package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2")
```

No other external dependencies. AVFoundation, AVFAudio, URLSession are all system frameworks.

### Backend (Modal image definition)

```python
# requirements.txt pinned
modal==1.3.4
fastapi==0.135.1
PyJWT==2.11.0
bcrypt==5.0.0
demucs==4.0.1
whisperx==3.8.1
yt-dlp==2026.2.21
# crema from GitHub (no PyPI release of 0.2.0)
# pip install git+https://github.com/bmcfee/crema.git
```

```python
# Modal image with GPU support and Deno
import modal

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "curl", "unzip")
    # Install Deno for yt-dlp YouTube support
    .run_commands(
        "curl -fsSL https://deno.land/install.sh | sh",
        "ln -s /root/.deno/bin/deno /usr/local/bin/deno",
    )
    .pip_install(
        "demucs==4.0.1",
        "whisperx==3.8.1",
        "yt-dlp==2026.2.21",
        "fastapi==0.135.1",
        "PyJWT==2.11.0",
        "bcrypt==5.0.0",
    )
    .run_commands(
        "pip install git+https://github.com/bmcfee/crema.git"
    )
)
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| demucs (htdemucs) | audio-separator (UVR) | If Demucs v4 cold start is too slow; UVR models are lighter but lower quality |
| whisperx | faster-whisper + manual alignment | If whisperx dependency conflicts with PyTorch version; faster-whisper is faster but no word-alignment built in |
| CREMA | madmom CRFChordRecognitionProcessor | If CREMA breaks on Python 3.11+; madmom is actively maintained (CPJKU) but more complex API |
| FastAPI + @modal.fastapi_endpoint | Modal @app.function + direct invocation | If you want async job pattern (poll for status) instead of synchronous HTTP call; useful if processing > 60s |
| PyJWT | python-jose | Never: python-jose is unmaintained (last release 3+ years ago) and is a security library — do not use |
| URLSession (native) | Alamofire | Only if request complexity grows significantly; Alamofire adds ~10MB to app; not worth it here |
| bcrypt | passlib | passlib wraps bcrypt anyway; use bcrypt directly to remove the abstraction layer |
| AVAudioEngine | CoreAudio | Only if you need sample-level control; AVAudioEngine handles synchronization automatically |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| python-jose | Unmaintained security library; last release 3+ years ago; FastAPI's own tutorial has been updated to recommend PyJWT | PyJWT 2.11.0 |
| youtube-dl | Replaced by yt-dlp; unmaintained; broken YouTube support | yt-dlp 2026.02.21 |
| passlib | Extra abstraction over bcrypt with more surface area; no maintenance needed beyond bcrypt itself | bcrypt 5.0.0 directly |
| AVPlayer (for stems) | Single-track only; no graph routing; can't mix 4 stems independently | AVAudioEngine + AVAudioPlayerNode (one per stem) |
| Modal stub API (old) | Pre-1.0 Modal API used `stub = modal.Stub()`; deprecated; breaking change in Modal 1.0 | `app = modal.App()` (Modal 1.0+ API) |
| htdemucs_ft (fine-tuned) | 4x slower than htdemucs for marginal quality gain; breaks the <60s constraint | htdemucs (default model) |
| Replicate / RunPod | Viable alternatives to Modal, but Modal's Python-native SDK and $30 free credit match project constraints better | Modal |

---

## Stack Patterns by Variant

**For synchronous processing (recommended for <60s songs):**
- `@app.function(gpu="T4")` returns result directly
- SwiftUI calls POST, waits for response with stems + lyrics JSON
- Simple; no polling needed

**If a song exceeds the 60s timeout:**
- Switch to async pattern: POST returns job ID, client polls `/status/{job_id}`
- Use `modal.Queue` or a simple `modal.Dict` for job state
- Only needed for edge cases (songs > 8 min or slow models)

**For model cold start (most important optimization):**
- Download model weights at image build time using `@app.function` + `modal.Volume`
- Use `@modal.enter` to load models into memory once per container (not per call)
- Set `scaledown_window=300` (5 min) to keep container warm between song requests

**For local client development:**
- Point SwiftUI to `modal serve` URL instead of production URL
- Toggle via a `#if DEBUG` constant in Swift

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| whisperx 3.8.1 | Python 3.10–3.13, CUDA 12.8 | Requires CUDA 12.8 specifically — must match Modal's CUDA image |
| demucs 4.0.1 | Python >=3.8, PyTorch 2.x | PyTorch version must match CUDA driver on T4 |
| yt-dlp 2026.02.21 | Python >=3.10 | Requires Deno in PATH for YouTube; ffmpeg must be installed |
| modal 1.3.4 | Python 3.10–3.14 | Modal 1.0+ API (use `modal.App`, not `modal.Stub`) |
| CREMA 0.2.0 | Python 3.8+ (estimated) | Not tested against 3.11 officially; verify at project start |
| KeychainAccess 4.2.2 | macOS 10.15+, Swift 5.x | SPM compatible; works on macOS 14 Sonoma |
| AVAudioUnitTimePitch | macOS 10.10+, all Apple Silicon | No version concerns; stable API |

---

## Sources

- [Modal official docs — GPU types, Volumes, cold start, web endpoints](https://modal.com/docs/guide) — HIGH confidence
- [Modal PyPI — version 1.3.4, Python 3.10–3.14](https://pypi.org/project/modal/) — HIGH confidence
- [Modal pricing — T4 $0.000164/s, $30/mo free credits](https://modal.com/pricing) — HIGH confidence
- [Modal 1.0 migration guide](https://modal.com/docs/guide/modal-1-0-migration) — HIGH confidence (confirms deprecated Stub API)
- [demucs PyPI — version 4.0.1, Python >=3.8](https://pypi.org/project/demucs/) — HIGH confidence
- [whisperx PyPI — version 3.8.1, Python 3.10–3.13, CUDA 12.8](https://pypi.org/project/whisperx/) — HIGH confidence
- [PyJWT 2.11.0 docs + PyPI](https://pypi.org/project/PyJWT/) — HIGH confidence
- [bcrypt 5.0.0 PyPI](https://pypi.org/project/bcrypt/) — HIGH confidence
- [FastAPI 0.135.1 PyPI](https://pypi.org/project/fastapi/) — HIGH confidence
- [yt-dlp 2026.02.21 release + Deno requirement](https://github.com/yt-dlp/yt-dlp/releases) — HIGH confidence
- [yt-dlp Deno requirement announcement](https://github.com/yt-dlp/yt-dlp/issues/15012) — HIGH confidence
- [CREMA GitHub — version 0.2.0, last release 2022](https://github.com/bmcfee/crema) — MEDIUM confidence (actively used; maintenance unclear)
- [KeychainAccess — SPM, version 4.2.2](https://swiftpackageindex.com/kishikawakatsumi/KeychainAccess) — MEDIUM confidence
- [AVAudioUnitTimePitch Apple docs](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch) — HIGH confidence
- [madmom chord recognition docs](https://madmom.readthedocs.io/en/v0.16/modules/features/chords.html) — MEDIUM confidence (fallback option)

---

*Stack research for: Strata — macOS audio processing app with serverless GPU backend*
*Researched: 2026-03-02*
