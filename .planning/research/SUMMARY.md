# Project Research Summary

**Project:** Strata — macOS Audio Practice App
**Domain:** macOS native audio stem separation / karaoke / chord detection with serverless GPU backend
**Researched:** 2026-03-02
**Confidence:** HIGH (stack and features verified; architecture and pitfalls MEDIUM where Apple forum data is the primary source)

## Executive Summary

Strata is a native macOS music practice tool that separates audio into stems, transcribes lyrics with word-level karaoke sync, and detects chords — all processed on a serverless GPU backend (Modal T4) and cached locally. The recommended approach is a two-tier architecture: a SwiftUI client using AVAudioEngine for multi-stem playback, communicating over HTTPS with a Python FastAPI app deployed on Modal. All three AI models (Demucs for stems, WhisperX for lyrics, CREMA for chords) run sequentially inside a single Modal function to avoid triple cold-start penalties. The local cache (`~/Music/Strata/`) ensures each song incurs GPU cost only once.

The primary competitive position is a native macOS app (not an iOS port or web app) that combines features no single competitor offers: stem separation + word-level karaoke + chord detection + YouTube import, all in one tool. Moises is the closest competitor but is mobile/web-only and lacks YouTube import. Capo is native macOS but has no AI transcription. The combination of these features in a native macOS app is an unoccupied niche.

The single most dangerous risk is multi-stem audio drift: if the four AVAudioPlayerNodes are not started at a precisely shared `AVAudioTime`, stems will phase-shift audibly within 30-60 seconds — which is catastrophic for the core product value. This must be solved correctly in the first audio phase and cannot be retrofitted cheaply. The second critical risk is Modal GPU cold start: Demucs + WhisperX + CREMA weights total ~2.3GB; without baking weights into the image and using `@modal.enter` for GPU warm-up, cold starts will blow the 60-second processing budget.

## Key Findings

### Recommended Stack

The client is pure Apple SDK: SwiftUI (macOS 14+) for UI, AVAudioEngine + AVAudioPlayerNode + AVAudioUnitTimePitch for multi-stem playback with pitch shifting, URLSession for networking, and the Security framework (or KeychainAccess 4.2.2) for JWT token storage. No third-party network or UI libraries are needed. The backend is Modal 1.0+ (`modal.App`, not the deprecated `modal.Stub`) wrapping a FastAPI app; GPU functions use `@app.function(gpu="T4")`. yt-dlp 2026.02.21 requires Deno in the container (a breaking change from 2025-11-12 onwards).

**Core technologies:**
- SwiftUI (macOS 14+): UI framework — native macOS, declarative, required by project spec
- AVAudioEngine + AVAudioPlayerNode: multi-stem playback — Apple's own graph API; only correct approach for synchronized multi-stem
- AVAudioUnitTimePitch: real-time pitch shifting — built-in, range ±2400 cents, zero-dependency
- Modal 1.3.4 (T4 GPU): serverless GPU orchestration — $0.000164/s; $30/mo free covers ~100 songs
- FastAPI 0.135.1: HTTP API layer inside Modal — `@modal.fastapi_endpoint` wraps natively
- Demucs 4.0.1 (htdemucs model): stem separation — Facebook Research SOTA; 4-stem in one pass
- WhisperX 3.8.1: lyrics transcription + word timestamps — Whisper large-v2 with forced phoneme alignment; requires CUDA 12.8
- CREMA 0.2.0: chord detection with timestamps — only library providing time-stamped chord predictions from raw audio; last released 2022 (fallback: madmom CRFChordRecognitionProcessor)
- yt-dlp 2026.02.21 + Deno: YouTube audio extraction — Deno is mandatory since 2025-11-12
- PyJWT 2.11.0: JWT auth — replaces unmaintained python-jose

**Critical version note:** whisperx 3.8.1 requires CUDA 12.8 specifically — Modal image must target that CUDA version.

### Expected Features

The feature dependency graph starts at stem separation: every practice feature (volume, mute, pitch, tempo) depends on having Demucs output. WhisperX and CREMA are independent of each other and can be parallelized server-side in a future optimization. The local cache must be designed correctly from the start — changing the cache schema after songs are stored is disruptive.

**Must have (table stakes) — v1:**
- 4-stem separation (Demucs v4) — every competitor offers this; lower stem count feels outdated
- Per-stem volume and mute/solo — without this, stem separation is useless for practice
- Global pitch shifting (±12 semitones) — vocalists need this immediately
- Global tempo control (50-150%, pitch-preserved) — core of every music practice app
- Local file import (drag-and-drop MP3/WAV/FLAC/M4A) — primary source for users with music collections
- Song library with local cache — without this, every open costs GPU time
- Processing status with stage labels — 60-second wait feels broken without feedback
- Simple password auth (JWT + Keychain) — minimum viable access control for 2 users

**Should have (competitive differentiation) — v1:**
- Word-level karaoke lyrics (WhisperX) — no competitor combines AI lyrics + stems in a native macOS app
- Chord display on scrolling timeline (CREMA) — guitarists/pianists see chords while practicing
- YouTube URL import (yt-dlp) — removes friction; half the target use case
- Monthly usage panel — cost transparency for personal GPU budget

**Defer (v1.x — add after core works):**
- A/B loop markers — most-requested practice feature after tempo; add when core is stable
- Stem export to files — useful for DAW users; not blocking launch
- BPM and key display — already available from CREMA data; low-effort add

**Defer (v2+):**
- Per-stem pitch shifting — AVAudioEngine complexity; rarely needed
- On-device Demucs — interesting for offline; model size and setup not worth it now
- iOS app — explicitly out of scope

### Architecture Approach

The system has two independent deployable units: the macOS Xcode project and the `strata_backend/` Modal Python project. The client follows feature-based MVVM (Views own ViewModels; Services are shared infrastructure injected into ViewModels). The backend is a single Modal function class that runs all three models sequentially to minimize cold starts; the FastAPI layer exposes a submit-and-poll job pattern. Audio stems are cached at `~/Music/Strata/{song-uuid}/` with a JSON sidecar for metadata; a `library.json` at the root serves as the song index.

**Major components:**
1. SwiftUI Views + ViewModels (per feature: Library, Player, Import, Usage) — bound to `@Observable` app state
2. PlaybackEngine (AVAudioEngine wrapper) — 4x AVAudioPlayerNode, 4x AVAudioUnitTimePitch, 1 AVAudioMixerNode; frame-accurate multi-stem sync
3. API Client (URLSession) — multipart upload, spawn+poll job pattern, JWT management via Keychain
4. Library Manager + CacheManager — FileManager + `~/Music/Strata/` layout + JSON persistence
5. Modal FastAPI backend — `/auth/login`, `/process` (spawn), `/result/{id}` (poll)
6. GPU Pipeline function — sequential Demucs → WhisperX → CREMA on T4; returns JSON bundle with stems (base64), lyrics (word timestamps), chords (chord + timestamps)

**Build order from ARCHITECTURE.md (dependency-driven):**
Backend skeleton → GPU pipeline → Swift API client + auth → Library/cache → AVAudioEngine playback → Pitch shifting → Lyrics display → Chords display → Import UI → Usage tracking

### Critical Pitfalls

1. **Multi-stem drift (CRITICAL):** Do not call `play()` sequentially on four nodes. Schedule all four `AVAudioPlayerNode`s with the same future `AVAudioTime` using `scheduleFile(_:at:)`. Recovery cost is HIGH (full audio engine rewrite). Fix it correctly in Phase 1.

2. **Modal cold start over budget (CRITICAL):** Cold start for Demucs + WhisperX + CREMA can hit 30-45 seconds alone. Mitigate by: baking model weights into the image during build, using `@modal.enter` to load models into GPU memory once per container, setting `scaledown_window=300`, and using a single Modal function class (not separate functions per model).

3. **yt-dlp blocked by YouTube (HIGH):** Datacenter IPs have 20-40% success rates against YouTube bot detection. Fix: pin yt-dlp version, store a YouTube cookies file in a Modal Secret (not baked into image), implement 3-attempt retry logic.

4. **WhisperX timestamp misalignment (MEDIUM):** Run WhisperX on the isolated vocal stem from Demucs, not on the original mix. Use a 2-3 word highlight window in the UI to mask ±0.5s alignment errors. Set `language` parameter explicitly for non-English songs.

5. **Demucs OOM on long tracks (MEDIUM):** T4 has 16GB VRAM; tracks over 5-7 minutes can exhaust it. Enforce 10-minute max duration at the API entry point; use Demucs's `segment` parameter in `apply_model()`. Clear GPU cache with `torch.cuda.empty_cache()` between models.

6. **AVAudioEngine in SwiftUI View (HIGH):** Engine must live in a persistent `@StateObject` class, never as a View property. Recovery cost is HIGH (full audio layer refactor). Enforce this architectural constraint from the first audio task.

7. **AVAudioUnitTimePitch crackling (MEDIUM):** Debounce pitch slider updates to 50ms intervals; pre-warm the node at engine start by setting pitch to 0 before audio plays.

## Implications for Roadmap

Based on research, suggested phase structure (10 phases, dependency-driven):

### Phase 1: Backend Foundation
**Rationale:** The GPU pipeline is the root dependency of every feature. No client feature can be tested end-to-end without it. Building a stub backend first lets Swift development proceed against a real API immediately.
**Delivers:** Modal FastAPI with `/auth/login`, `/process` (stub returning fake data), `/result/{id}`. Deployed to Modal. Swift can hit real HTTPS endpoints.
**Addresses:** Auth (JWT + Keychain), basic API contract
**Avoids:** Building Swift network code against localhost mocks that don't reflect real Modal behavior

### Phase 2: GPU Processing Pipeline
**Rationale:** The pipeline is the core product value. It must be proven on real GPU hardware before building UI around it.
**Delivers:** Demucs → WhisperX → CREMA running sequentially on T4; model weights baked into image; `@modal.enter` warm-up; tested cold-start time.
**Uses:** demucs 4.0.1, whisperx 3.8.1 (CUDA 12.8), CREMA 0.2.0, yt-dlp + Deno
**Avoids:** Cold-start overrun (Pitfall 3), Demucs OOM on long tracks (Pitfall 4), WhisperX misalignment (Pitfall 6 — run on vocal stem)
**Research flag:** CREMA on Python 3.11 is unverified; test at start of this phase and have madmom fallback ready

### Phase 3: Swift API Client + Auth
**Rationale:** Swift networking and auth are prerequisites for every client feature.
**Delivers:** URLSession wrapper, multipart upload, spawn+poll job client, JWT stored in Keychain, login screen
**Uses:** URLSession (native), KeychainAccess 4.2.2 or raw Security.framework, PyJWT 2.11.0 backend
**Avoids:** Synchronous HTTP blocking main thread; token hardcoded in Swift source

### Phase 4: Library Manager + Local Cache
**Rationale:** Cache must be designed correctly before any song data is persisted. Schema changes after songs are stored are disruptive. This phase has no UI dependencies — it can proceed in parallel with Phase 3.
**Delivers:** `~/Music/Strata/{uuid}/` directory layout, `library.json` index, JSON sidecar metadata, CacheManager and LibraryStore services
**Avoids:** Using NSCachesDirectory (purged by macOS); storing stems in app sandbox instead of ~/Music/Strata/

### Phase 5: Multi-Stem Playback Engine
**Rationale:** Frame-accurate stem sync is the most technically risky component. It must be solved before lyrics/chords display are built on top of it. Getting it wrong here means high-cost rewrite.
**Delivers:** AVAudioEngine with 4x AVAudioPlayerNode + 4x AVAudioUnitTimePitch; frame-accurate start using shared `AVAudioTime`; per-stem volume and mute; seek; currentTime reporting
**Avoids:** Multi-stem drift (Pitfall 1 — CRITICAL); AVAudioEngine in SwiftUI View body (Pitfall 6); pitch node crackling (Pitfall 2)
**Note:** Engine must live in a `@StateObject`/`@Observable` class from day one

### Phase 6: Import UI + End-to-End Flow
**Rationale:** First phase that connects all layers. Drag-and-drop local file and URL paste wire the API client to the library, completing the full processing flow.
**Delivers:** Drag-and-drop file import, YouTube URL paste, processing status UI with stage labels, cache hit detection ("already processed")
**Addresses:** Local file import, YouTube URL import, processing status feedback, cache
**Avoids:** No progress indication (UX pitfall); no retry logic for downloads; yt-dlp YouTube blocking (cookies configured here)

### Phase 7: Player UI — Playback Controls
**Rationale:** With the playback engine and import flow working, the player UI is straightforward to wire up.
**Delivers:** Transport controls (play/pause/seek), progress bar with scrubbing, pitch slider (debounced), tempo slider, per-stem volume and mute controls
**Avoids:** Pitch slider crackling (debounce to 50ms); all stems muted simultaneously (UX pitfall)

### Phase 8: Lyrics Display (Karaoke)
**Rationale:** Depends on playback engine's currentTime being accurate. Built after player controls are stable.
**Delivers:** Scrolling karaoke view with word-level highlight synced to playback position; 2-3 word highlight window to mask alignment error
**Addresses:** Word-level karaoke lyrics (key differentiator)
**Avoids:** WhisperX misalignment UX problem — wide highlight window is the intentional mitigation

### Phase 9: Chord Display
**Rationale:** Architecturally identical to lyrics display; same currentTime sync pattern with a different data shape. Ships together or immediately after lyrics.
**Delivers:** Scrolling chord timeline with active chord highlighted during playback; key and BPM display from CREMA metadata
**Addresses:** Chord display on timeline, key/BPM metadata

### Phase 10: Polish + Usage Tracking
**Rationale:** All functional features are complete; this phase handles cost transparency and UX polish.
**Delivers:** Monthly usage panel (song count + estimated Modal cost), error message mapping (human-readable errors), export stems to files, BPM/key surface
**Addresses:** Monthly usage panel, stem export (v1.x feature pulled in if time allows)

### Phase Ordering Rationale

- **Backend before client:** Every client feature tests against a real deployed endpoint; no localhost mocking that diverges from production behavior
- **GPU pipeline before UI:** The AI models are the biggest uncertainty (especially CREMA on Python 3.11 and cold-start time); proving the pipeline early de-risks the entire project
- **Cache before UI:** Cache schema is expensive to change once songs are stored; locking it in before the import UI prevents later disruption
- **Playback engine before display:** Lyrics and chords display require a reliable currentTime from the engine; building display before playback is stable wastes effort
- **Import before player UI:** End-to-end flow validation happens at Phase 6; finding API contract issues before building a full player UI is cheaper

### Research Flags

Phases needing deeper research or early validation:
- **Phase 2 (GPU Pipeline):** CREMA 0.2.0 compatibility with Python 3.11 is unverified — test at phase start; have madmom fallback API mapped out
- **Phase 2 (GPU Pipeline):** Cold-start total time with all three models loaded is untested; measure against 65-second budget early and adjust `scaledown_window` or memory snapshotting if needed
- **Phase 6 (Import):** yt-dlp YouTube blocking with Modal datacenter IPs needs empirical testing; cookies configuration required before YouTube testing; do not test from local dev

Phases with standard patterns (skip additional research):
- **Phase 3 (API Client):** URLSession + multipart + JWT is well-documented; follow standard patterns
- **Phase 5 (Playback Engine):** AVAudioEngine multi-stem sync pattern is documented in Apple forums and WWDC; follow the `scheduleFile(_:at:)` pattern exactly
- **Phase 8/9 (Lyrics/Chords):** Timer-based currentTime → timestamp lookup is a solved problem; no research needed

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Core libraries (Modal, Demucs, WhisperX, FastAPI, AVFoundation) verified against official docs and PyPI. Two exceptions: CREMA Python 3.11 compatibility unverified; KeychainAccess 4.2.2 stable but 4 years since last release |
| Features | HIGH | Cross-validated against 6 competitors (Moises, Capo, Anytune, Amazing Slow Downer, iReal Pro, PhonicMind); feature gaps and expectations well-mapped |
| Architecture | HIGH (patterns) / MEDIUM (pipeline specifics) | AVAudioEngine multi-stem and Modal spawn+poll patterns verified in official docs. Pipeline latency estimates (Demucs ~20-35s, WhisperX ~10-15s, CREMA ~5-10s) are community-reported, not benchmarked |
| Pitfalls | MEDIUM | Multi-stem drift and cold-start issues verified in official Apple forums and Modal docs. yt-dlp blocking and WhisperX misalignment verified in GitHub issue trackers. Some latency numbers are estimates |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **CREMA Python 3.11 compatibility:** Not officially tested. Verify at the start of Phase 2. If it fails, switch to madmom's `CRFChordRecognitionProcessor` — API mapping is documented in STACK.md.
- **Actual GPU processing time:** Cold-start + pipeline latency estimates are from community reports, not project-specific benchmarks. Measure at Phase 2 completion against the 65-second budget.
- **yt-dlp success rate on Modal IPs:** YouTube bot detection is dynamic. Test empirically in Phase 6 with real YouTube URLs before committing to cookies strategy.
- **WhisperX 3.8.1 timestamp regression status:** A regression in v3.3.3 caused word-level misalignment. Verify that 3.8.1 has resolved this; if not, mitigation (wide highlight window + segment-level fallback) is already designed.
- **Stems-as-base64 payload size:** For a 5-minute song, 4 stems as base64 in the JSON response body could approach 50-80MB. If this causes latency issues, switch to Modal Volume + presigned download URL pattern at Phase 2.

## Sources

### Primary (HIGH confidence)
- Modal official docs (modal.com/docs) — GPU types, Volumes, cold start, web endpoints, pricing
- Modal PyPI (pypi.org/project/modal) — version 1.3.4, Python 3.10-3.14 support
- Apple Developer Documentation — AVAudioEngine, AVAudioPlayerNode, AVAudioUnitTimePitch, scheduleFile(_:at:)
- demucs PyPI (pypi.org/project/demucs) — version 4.0.1, Python >=3.8
- whisperx PyPI (pypi.org/project/whisperx) — version 3.8.1, CUDA 12.8 requirement
- PyJWT PyPI — version 2.11.0; replaces unmaintained python-jose
- bcrypt PyPI — version 5.0.0, Rust-implemented
- FastAPI PyPI — version 0.135.1
- yt-dlp GitHub releases + Deno requirement issue

### Secondary (MEDIUM confidence)
- Apple Developer Forums — AVAudioPlayerNode multi-stem sync (thread/14138), TimePitch crackling (thread/781313), TimePitch render latency (thread/708168)
- Demucs GitHub Issue #231 — CUDA OOM on long tracks with T4
- WhisperX GitHub Issues #1220, #1247 — word-level timestamp regression
- yt-dlp GitHub Issue #13067 — YouTube datacenter IP blocking
- Competitor feature analysis — Moises, Capo, Anytune, Amazing Slow Downer, iReal Pro, PhonicMind

### Tertiary (LOW confidence / needs validation)
- CREMA GitHub (github.com/bmcfee/crema) — version 0.2.0; Python 3.11 compatibility unverified; last release April 2022
- GPU pipeline latency estimates (Demucs ~20-35s, WhisperX ~10-15s, CREMA ~5-10s) — community reports, not T4-specific benchmarks
- KeychainAccess 4.2.2 — SPM compatible; 4 years since last release; raw Security.framework is the zero-risk alternative

---
*Research completed: 2026-03-02*
*Ready for roadmap: yes*
