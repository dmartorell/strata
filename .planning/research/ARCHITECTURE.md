# Architecture Research

**Domain:** macOS native audio processing app with serverless GPU backend
**Researched:** 2026-03-02
**Confidence:** HIGH (AVAudioEngine, Modal patterns) / MEDIUM (pipeline chaining specifics)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                     macOS Client (SwiftUI)                        │
├──────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │   UI Layer   │  │  Playback    │  │    Library Manager     │  │
│  │  (SwiftUI    │  │  Engine      │  │  (FileManager +        │  │
│  │   Views)     │  │  (AVAudio    │  │   SQLite/JSON cache    │  │
│  │              │  │   Engine)    │  │   ~/Music/Strata/)     │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬─────────────┘  │
│         │                 │                      │                │
│  ┌──────▼─────────────────▼──────────────────────▼─────────────┐  │
│  │                  App State (@Observable)                      │  │
│  │   SongLibrary · ActiveSong · PlaybackState · ProcessingJob   │  │
│  └──────────────────────────────┬───────────────────────────────┘  │
│                                 │                                  │
│  ┌──────────────────────────────▼───────────────────────────────┐  │
│  │                    API Client Layer                           │  │
│  │   (URLSession · multipart upload · job polling · JWT)        │  │
│  └──────────────────────────────┬───────────────────────────────┘  │
└─────────────────────────────────┼──────────────────────────────────┘
                                  │ HTTPS
┌─────────────────────────────────▼──────────────────────────────────┐
│                     Modal Serverless Backend                        │
├────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                FastAPI Web Endpoints                         │   │
│  │   POST /auth/login  ·  POST /process  ·  GET /result/{id}   │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │ spawn()                              │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │              GPU Processing Pipeline (T4)                    │   │
│  │                                                              │   │
│  │  [yt-dlp] → [Demucs v4] → [WhisperX] → [CREMA] → [Bundle]  │   │
│  │                                                              │   │
│  │  Input:  raw audio bytes (or YouTube URL)                    │   │
│  │  Output: JSON bundle { stems[], lyrics[], chords[] }         │   │
│  └───────────────────────────┬─────────────────────────────────┘   │
│                              │                                      │
│  ┌───────────────────────────▼─────────────────────────────────┐   │
│  │              Modal Volume (Temporary Scratch)                │   │
│  │   Intermediate stems during pipeline · cleaned after job     │   │
│  └─────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| SwiftUI Views | Render library, playback controls, lyrics/chords display | SwiftUI declarative views, bound to @Observable state |
| App State | Single source of truth for all app state | @Observable classes held in @State at app root |
| Playback Engine | Multi-stem synchronized playback, pitch shift, seek | AVAudioEngine + 4x AVAudioPlayerNode + AVAudioUnitTimePitch |
| Library Manager | Persist song metadata + locate cached stems on disk | FileManager, ~/Music/Strata/, JSON sidecar or SQLite |
| API Client | Upload audio, poll for job results, auth token management | URLSession, multipart/form-data, JWT in Keychain |
| FastAPI Endpoints | Receive requests, spawn jobs, return results | Modal @modal.fastapi_endpoint, Python |
| GPU Pipeline | Run Demucs → WhisperX → CREMA sequentially | Python functions on Modal T4 GPU |
| Modal Volume | Scratch space for intermediate files within a job | modal.Volume, auto-cleaned after result is returned |

## Recommended Project Structure

```
Strata/                          # Xcode project root
├── App/
│   ├── StrataApp.swift          # App entry point, inject root state
│   └── AppState.swift           # @Observable root state object
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift
│   │   ├── LibraryViewModel.swift
│   │   └── SongRowView.swift
│   ├── Player/
│   │   ├── PlayerView.swift
│   │   ├── PlayerViewModel.swift
│   │   ├── LyricsView.swift
│   │   └── ChordsView.swift
│   ├── Import/
│   │   ├── ImportView.swift
│   │   └── ImportViewModel.swift
│   └── Usage/
│       ├── UsageView.swift
│       └── UsageViewModel.swift
├── Services/
│   ├── Audio/
│   │   ├── PlaybackEngine.swift  # AVAudioEngine wrapper
│   │   └── StemPlayer.swift      # Per-stem node management
│   ├── Network/
│   │   ├── APIClient.swift       # URLSession wrapper
│   │   ├── ProcessingJob.swift   # submit + poll logic
│   │   └── AuthService.swift     # JWT + Keychain
│   └── Storage/
│       ├── LibraryStore.swift    # FileManager + metadata persistence
│       └── CacheManager.swift    # ~/Music/Strata/ layout
├── Models/
│   ├── Song.swift
│   ├── StemTrack.swift
│   ├── LyricLine.swift
│   └── ChordEvent.swift
└── Resources/

strata_backend/                  # Modal Python project
├── app.py                       # FastAPI app, endpoint definitions
├── pipeline.py                  # GPU function: Demucs → WhisperX → CREMA
├── auth.py                      # Password verification, JWT issue
└── requirements.txt
```

### Structure Rationale

- **Features/:** Each screen owns its View + ViewModel. Views are thin; business logic stays in ViewModels.
- **Services/:** Cross-feature infrastructure (audio engine, network, disk) shared by multiple ViewModels.
- **Models/:** Pure value types (structs). No business logic — only data shapes matching API responses.
- **strata_backend/:** Kept separate from Xcode project. Deployed independently with `modal deploy`.

## Architectural Patterns

### Pattern 1: Spawn + Poll for GPU Jobs

**What:** Client submits a job and receives a `call_id`. Client polls `/result/{call_id}` until HTTP 200 replaces 202.

**When to use:** Any GPU workload exceeding ~30 seconds. Avoids HTTP timeout (Modal default 150s for web endpoints, configurable up to 3600s but polling is cleaner).

**Trade-offs:** Adds polling complexity client-side; eliminates risk of dropped connections for long jobs. Results persist 7 days on Modal, so no race condition.

**Example:**

```python
# Backend: app.py
@web_app.post("/process")
async def submit_job(audio: UploadFile = File(...)):
    data = await audio.read()
    call = process_song.spawn(data, audio.filename)
    return {"call_id": call.object_id}

@web_app.get("/result/{call_id}")
async def poll_result(call_id: str):
    fc = modal.functions.FunctionCall.from_id(call_id)
    try:
        result = fc.get(timeout=0)
        return result  # HTTP 200 with JSON bundle
    except TimeoutError:
        return JSONResponse({}, status_code=202)  # still running
```

```swift
// Client: ProcessingJob.swift
func submitAndPoll(audioData: Data, filename: String) async throws -> SongBundle {
    let callId = try await apiClient.submitJob(audioData: audioData, filename: filename)
    return try await poll(callId: callId)
}

private func poll(callId: String) async throws -> SongBundle {
    while true {
        let response = try await apiClient.getResult(callId: callId)
        if let bundle = response.bundle { return bundle }
        try await Task.sleep(for: .seconds(3))
    }
}
```

### Pattern 2: AVAudioEngine Multi-Stem Graph

**What:** One AVAudioEngine with four AVAudioPlayerNodes (one per stem), each routed through an AVAudioUnitTimePitch, then to a shared AVAudioMixerNode, then to the output node.

**When to use:** Always — this is the only correct approach for synchronized multi-stem playback with independent pitch/volume control.

**Trade-offs:** All stems must be pre-loaded as AVAudioFile from disk (not streamed) for frame-accurate sync. Memory cost for 4 stems of a 5-min song ≈ 4 × ~30 MB uncompressed = manageable.

**Example:**

```swift
// PlaybackEngine.swift
class PlaybackEngine {
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var stemPlayers: [Stem: AVAudioPlayerNode] = [:]
    private var pitchNodes: [Stem: AVAudioUnitTimePitch] = [:]

    func load(stems: [Stem: URL]) {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)

        for (stem, url) in stems {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitTimePitch()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: nil)
            engine.connect(pitch, to: mixer, format: nil)
            stemPlayers[stem] = player
            pitchNodes[stem] = pitch
        }
        try? engine.start()
    }

    func play(stems: [Stem: AVAudioFile]) {
        // Schedule all stems at the same future render time for lock-step start
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + 0.1_seconds_in_host_ticks)
        for (stem, file) in stems {
            stemPlayers[stem]?.scheduleFile(file, at: startTime)
            stemPlayers[stem]?.play(at: startTime)
        }
    }

    func setPitch(_ cents: Float) {
        pitchNodes.values.forEach { $0.pitch = cents }
    }

    func setVolume(_ volume: Float, for stem: Stem) {
        stemPlayers[stem]?.volume = volume
    }
}
```

### Pattern 3: Local Cache with JSON Sidecar

**What:** Audio stems stored as files in `~/Music/Strata/{songId}/`. Metadata (title, duration, lyrics, chords) stored in a JSON sidecar `metadata.json` in the same folder. App index (list of all songs) is a single `library.json` at root.

**When to use:** Small personal app with <1000 songs. Avoids Core Data/SwiftData overhead for this scale.

**Trade-offs:** No migration system — breaking schema changes require manual cleanup. Acceptable for 2-user personal app. Use SwiftData if schema evolves significantly.

**Cache layout:**
```
~/Music/Strata/
├── library.json                  # [{id, title, artist, cachedAt, duration}]
└── {song-uuid}/
    ├── metadata.json             # {lyrics, chords, processedAt, sourceUrl}
    ├── vocals.m4a
    ├── drums.m4a
    ├── bass.m4a
    └── other.m4a
```

## Data Flow

### Import Flow (Local File)

```
User drops file onto app window
    ↓
ImportViewModel.handleDrop(providers:)
    ↓
APIClient.submitJob(audioData:filename:) — POST /process (multipart, ~10-50 MB)
    ↓ returns call_id
ProcessingJob.poll(callId:) — GET /result/{call_id} every 3s
    ↓ ~45-55s later, HTTP 200
SongBundle { stems: [Data], lyrics: [LyricLine], chords: [ChordEvent] }
    ↓
CacheManager.save(bundle:) — write stems to ~/Music/Strata/{id}/, write metadata.json
    ↓
LibraryStore.add(song:) — append to library.json
    ↓
AppState.library updated → SwiftUI re-renders song list
```

### Import Flow (YouTube URL)

```
User pastes YouTube URL
    ↓
APIClient.submitJobFromURL(url:) — POST /process with JSON body {url: "..."}
    ↓ Modal backend runs yt-dlp, downloads audio server-side
    ↓ same pipeline as above from Demucs onward
    ↓ same poll + cache flow
```

### GPU Pipeline (server-side)

```
@modal.function(gpu="T4", timeout=120)
def process_song(audio_bytes: bytes, filename: str) -> dict:
    # 1. Write to Modal Volume scratch dir
    # 2. Demucs v4 → 4 stem WAV files (~20-35s on T4)
    # 3. WhisperX on vocals stem → word-level timestamps (~10-15s)
    # 4. CREMA on mix or bass+other → chord timeline (~5-10s)
    # 5. Read stems back as bytes, encode to base64
    # 6. Return { stems: {vocals, drums, bass, other},
    #             lyrics: [{word, start, end}],
    #             chords: [{chord, start, end}] }
```

### Playback State Flow

```
User taps Play
    ↓
PlayerViewModel.play()
    ↓
PlaybackEngine.play(stems:) — schedules all 4 AVAudioPlayerNodes at same startTime
    ↓
DisplayLink / Timer fires every ~16ms
    ↓
PlaybackEngine.currentTime → computed from sampleTime / sampleRate
    ↓
PlayerViewModel.currentTime updated
    ↓
LyricsView: highlight word where start <= currentTime < end
ChordsView: highlight chord where start <= currentTime < end
```

### Authentication Flow

```
App launch
    ↓
KeychainService.load(key: "jwt") → token exists?
    YES → validate expiry → set AppState.isAuthenticated = true
    NO  → show LoginView
         ↓
         User enters password
         ↓
         POST /auth/login { password: "..." }
         ↓ JWT (90-day expiry)
         KeychainService.save(token)
         AppState.isAuthenticated = true
```

## Scaling Considerations

This is a 2-user personal app. Scaling is not a real concern. Relevant constraints instead:

| Concern | Current design | If it becomes a product |
|---------|----------------|------------------------|
| Concurrent GPU jobs | Modal auto-scales, $10/mo cap | Increase spending limit, add queue |
| Disk space | ~100 MB per song, 100 songs = 10 GB | Add eviction policy by LRU |
| Auth | Single password + JWT | Replace with proper user accounts |
| Result payload size | ~30-50 MB base64 stems in JSON response | Use Modal Volume + presigned download URL |

**Note on payload size:** For files approaching 50 MB, returning stems as base64 in the JSON response body is feasible (Modal supports up to 4 GiB response) but wasteful. If latency becomes a concern, switch to: server writes stems to S3/R2, returns presigned download URLs, client downloads each stem independently.

## Anti-Patterns

### Anti-Pattern 1: Waiting on the HTTP connection for GPU work

**What people do:** POST /process and wait for the response to contain the result, with a 120-second timeout.

**Why it's wrong:** Cold-start + Demucs + WhisperX regularly exceeds 60 seconds. HTTP connections are fragile over mobile/wifi. If the connection drops, the job is lost and there's no way to recover the result.

**Do this instead:** Spawn + poll pattern. Submit returns `call_id` in under 1 second. Client polls `/result/{call_id}` independently. Job result persists 7 days on Modal.

### Anti-Pattern 2: Storing stems in app sandbox instead of ~/Music/Strata/

**What people do:** Write stem files to `NSApplicationSupportDirectory` or `NSCachesDirectory` inside the app container.

**Why it's wrong:** `Caches` directory can be purged by macOS without warning. `ApplicationSupport` is correct for persistent data but non-standard for large media files. The project spec explicitly targets `~/Music/Strata/`.

**Do this instead:** Use `FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first` appended with `Strata/`. This is the standard macOS location for user music. Create the directory on first launch if it doesn't exist.

### Anti-Pattern 3: Separate AVAudioEngine instances per stem

**What people do:** Create one `AVAudioPlayerNode` + `AVAudioEngine` per stem and try to synchronize them via timers.

**Why it's wrong:** Multiple engine instances have independent clocks. Timer-based sync drifts over time (detectable within 10-30 seconds). You cannot guarantee sample-accurate alignment.

**Do this instead:** One `AVAudioEngine` with all four `AVAudioPlayerNode`s connected to the same graph. Use `scheduleFile(_:at:)` with an identical `AVAudioTime` for all four nodes. The engine renders them on a single clock — drift is impossible.

### Anti-Pattern 4: Running all three AI models in one Modal function

**What people do:** One monolithic `process_song()` function that imports and runs Demucs, WhisperX, and CREMA in sequence.

**Why it's wrong for a solo developer:** Actually fine for a 2-user personal app. The anti-pattern is splitting them prematurely into separate Modal functions with inter-function calls — this adds cold-start overhead (3 containers instead of 1), complicates the pipeline, and provides no benefit when the models always run together.

**Do this instead:** Single `process_song` function. One container, one cold start, sequential model execution. Only split if you need to run models independently (e.g., re-transcribe without re-separating stems), which is out of scope here.

### Anti-Pattern 5: Pitch-shifting all stems with one TimePitch node post-mix

**What people do:** Route all stems to the mixer, then attach one `AVAudioUnitTimePitch` between mixer and output.

**Why it's wrong:** Pitch shift is applied uniformly — correct. But you lose the ability to mute individual stems without re-routing the graph at runtime (which requires stopping the engine). Also, each stem should have its own TimePitch node to allow per-stem effects in the future.

**Do this instead:** One `AVAudioUnitTimePitch` per stem, between `AVAudioPlayerNode` and `AVAudioMixerNode`. Update all four `pitch` properties simultaneously when the user changes pitch. `AVAudioUnitTimePitch.pitch` is a realtime-safe property — no engine restart needed.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Modal GPU backend | HTTPS REST (submit + poll) | Endpoint URL from `modal deploy` output; store in app config |
| YouTube (via yt-dlp) | Server-side only — client sends URL string | Client never touches YouTube directly |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| SwiftUI Views ↔ ViewModels | @Observable + @Bindable | No Combine needed; Swift Observation framework (iOS 17 / macOS 14) |
| ViewModels ↔ Services | Direct async/await calls | Services are injected via initializer for testability |
| PlaybackEngine ↔ PlayerViewModel | Callback / published currentTime | Engine runs on audio thread; bridge to main actor via @MainActor |
| APIClient ↔ Modal backend | URLSession async/await | Multipart upload for audio; JSON poll for results |
| LibraryStore ↔ FileManager | Synchronous file I/O wrapped in Task | Never on main thread; use `Task.detached` for file writes |
| Swift client ↔ Keychain | Security framework (SecItem) | Wrap in a `KeychainService` actor to avoid data races |

## Suggested Build Order

Dependencies drive this order — each layer requires the one before it:

1. **Backend skeleton** — Modal FastAPI with `/auth/login`, `/process` (stub), `/result/{id}`. No real GPU yet. Lets the iOS client integrate immediately.
2. **GPU pipeline** — Demucs → WhisperX → CREMA wired up on T4. Test via `modal run` before exposing via endpoint.
3. **API Client + Auth** — Swift URLSession wrapper, JWT/Keychain, submit + poll. Test against real backend.
4. **Library Manager + Cache** — FileManager, `~/Music/Strata/` layout, song metadata persistence. Test offline.
5. **AVAudioEngine Playback** — Load stems from disk, multi-stem sync, volume/mute, seek. Test with pre-downloaded stems.
6. **Pitch shifting** — AVAudioUnitTimePitch wired per stem. Thin addition once engine works.
7. **Lyrics display** — Sync LyricLine timestamps to playback currentTime. Requires playback working.
8. **Chords display** — Same as lyrics, different data shape.
9. **Import UI** — Drag & drop + URL paste wired to API Client. End-to-end flow.
10. **Usage tracking** — Count processed songs, estimate GPU cost. Last because it's metadata-only.

## Sources

- [AVAudioEngine — Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [AVAudioPlayerNode — Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudioplayernode)
- [AVAudioUnitTimePitch — Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch)
- [scheduleFile(_:at:completionHandler:) — Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudioplayernode/schedulefile(_:at:completionhandler:))
- [Playing files simultaneously in AVAudioEngine — Apple Developer Forums](https://developer.apple.com/forums/thread/14138)
- [Making Sense of Time in AVAudioPlayerNode — Mehdi Samadi / Medium](https://medium.com/@mehsamadi/making-sense-of-time-in-avaudioplayernode-475853f84eb6)
- [Modal Web Endpoints — Modal Docs](https://modal.com/docs/guide/webhooks)
- [Modal Job Queue — Modal Docs](https://modal.com/docs/guide/job-queue)
- [Modal Volumes — Modal Docs](https://modal.com/docs/guide/volumes)
- [Modal job queue example (doc_ocr_webapp.py)](https://github.com/modal-labs/modal-examples/blob/main/09_job_queues/doc_ocr_webapp.py)
- [WhisperX — GitHub (m-bain/whisperX)](https://github.com/m-bain/whisperX)
- [Demucs — PyPI](https://pypi.org/project/demucs/)
- [MVVM in SwiftUI 2025 — flyingharley.dev](https://flyingharley.dev/posts/mvvm-architecture-in-swift-ui-from-observable-object-to-observable)
- [Build robust and resumable file transfers — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10006/)

---
*Architecture research for: macOS audio processing app (Strata) with Modal serverless GPU backend*
*Researched: 2026-03-02*
