# Pitfalls Research

**Domain:** macOS audio stem separation app with serverless GPU backend
**Researched:** 2026-03-02
**Confidence:** MEDIUM (mix of official docs, forum reports, and verified community findings)

---

## Critical Pitfalls

### Pitfall 1: AVAudioPlayerNode Multi-Stem Drift Over Time

**What goes wrong:**
Four AVAudioPlayerNode instances (one per stem) gradually drift out of sync during playback. The drift is imperceptible at first but becomes audible after 30-60 seconds, making the reconstituted mix sound phased or doubled. This is catastrophic for a product whose core value is synchronized multi-stem playback.

**Why it happens:**
Each node has its own internal sample clock. If you call `play()` on each node sequentially in a loop, there is a small but non-zero time difference between each call. These differences accumulate. The mistake is scheduling files with `nil` start time and relying on sequential `play()` calls.

**How to avoid:**
Schedule all four nodes to play at a specific future `AVAudioTime` using `scheduleFile(_:at:)`. Calculate a start time ~300ms in the future (enough for file reading), call `scheduleFile` on all four nodes, then call `play()` on all four. Use `prepare(withFrameCount:)` on each node before scheduling to pre-buffer audio into memory. The nodes will start at the exact same sample frame.

```swift
let startDelay: TimeInterval = 0.3
let outputFormat = engine.outputNode.outputFormat(forBus: 0)
let startSampleTime = engine.outputNode.lastRenderTime!.sampleTime +
    AVAudioFramePosition(startDelay * outputFormat.sampleRate)
let startTime = AVAudioTime(sampleTime: startSampleTime, atRate: outputFormat.sampleRate)

for node in stemNodes {
    node.scheduleFile(file, at: startTime, completionHandler: nil)
}
for node in stemNodes { node.play() }
```

**Warning signs:**
- Testing with short clips only (drift not yet audible)
- Calling `play()` without a scheduled `AVAudioTime`
- Audible phasing effect on full-band stems compared to solo stem

**Phase to address:** Multi-stem playback engine phase (core audio infrastructure)

---

### Pitfall 2: AVAudioUnitTimePitch Crackling/Popping at Pitch Change

**What goes wrong:**
When the user moves a pitch slider, crackling or popping sounds appear in real time. The artifact is consistent and reproducible, not intermittent. Removing the `AVAudioUnitTimePitch` node from the graph makes the crackling disappear.

**Why it happens:**
The `AVAudioUnitTimePitch` node has a known rendering latency (~90ms) and a tendency to introduce discontinuities when its `pitch` property is changed while audio is actively rendering. The render thread processes pitch changes without interpolation between the old and new pitch values, causing buffer boundary artifacts. This is a documented issue in Apple's developer forums (thread 781313).

**How to avoid:**
- Apply pitch changes on the main thread but guard with a rate-limiting mechanism (debounce slider updates to ~50ms intervals so rapid scrubbing doesn't hammer the audio render thread).
- Pre-warm the `AVAudioUnitTimePitch` node at engine start by setting pitch to 0 before audio plays.
- If crackling persists, consider using `AVAudioUnitVarispeed` (only changes rate, not pitch independently) or implementing pitch via `AVAudioUnitEffect` with a custom AudioUnit.
- Account for the 90ms latency when tracking playback position — node time ≠ output time.

**Warning signs:**
- Slider connected directly to `timePitchNode.pitch` via SwiftUI `onChange` with no debounce
- Audio glitches only present when pitch ≠ 0

**Phase to address:** Multi-stem playback engine phase; verified during pitch shifting UI integration

---

### Pitfall 3: Modal GPU Cold Start Exceeds Processing Budget

**What goes wrong:**
The project target is <60s total processing time. Modal GPU cold start alone (loading Demucs weights into VRAM on a T4) can take 30-45 seconds, leaving only 15-30 seconds for actual inference — which is insufficient for Demucs + WhisperX + CREMA running sequentially.

**Why it happens:**
A cold container must: spin up the OS, import Python packages, load Demucs model weights (~800MB for htdemucs), load WhisperX Whisper weights (~1.5GB), and load CREMA weights — all before processing starts. When the free tier scales to zero between uses (which it will for a 2-user personal app), every request hits a cold start.

**How to avoid:**
- Bundle all three models (Demucs, WhisperX, CREMA) in a single Modal function class, not separate functions. One cold start, one warm container.
- Download model weights during the image build phase (`modal.Image.run_commands()`), not at container startup. Weights are baked into the image layer.
- Use `@modal.enter()` to load models into GPU memory once per container lifecycle, not per request.
- Set `scaledown_window=300` (5 minutes) so the container stays warm between rapid successive requests. For a 2-user app this is sufficient.
- Use `min_containers=0` (default) since cost is the constraint, accept cold starts on first use.
- Enable memory snapshotting if available for your Modal plan to cut warm-up from ~40s to ~5s.

**Warning signs:**
- Three separate `@app.function` decorators for Demucs, WhisperX, CREMA — each incurs its own cold start
- Model weights downloaded via `huggingface_hub` in the function body, not during image build
- Total processing time tested only with warm containers

**Phase to address:** Backend GPU pipeline phase (foundational architecture decision)

---

### Pitfall 4: Demucs OOM on Long Tracks with T4 GPU

**What goes wrong:**
Processing audio tracks longer than ~5-7 minutes on a T4 GPU (16GB VRAM) causes CUDA out-of-memory errors. The job silently fails or crashes the container, and the client receives no useful error message.

**Why it happens:**
Demucs v4 (htdemucs) uses a Transformer-based architecture with cross-domain attention. Memory consumption scales super-linearly with audio duration. A known GitHub issue (#231) reports an attempt to allocate 5.71 GiB on a T4 during long-track inference, exhausting available VRAM when other model state is also resident.

**How to avoid:**
- Enforce the 10-minute max duration constraint at the API level before GPU processing starts. Reject anything over 10 minutes with a clear error.
- Use Demucs's built-in `--segment` parameter to process audio in overlapping chunks. The `demucs` Python API exposes this as `segment` in `apply_model()`. Set segment to 7.8 seconds (default) or lower.
- Alternatively, use `demucs --device cpu` as a fallback for OOM cases, though this is 10x slower and will break the 60s budget.
- Clear GPU cache between model invocations: `torch.cuda.empty_cache()` between Demucs and WhisperX.

**Warning signs:**
- No max duration validation at API entry point
- CUDA OOM errors in Modal logs for test tracks over 6 minutes
- Processing tested only with 3-4 minute pop songs

**Phase to address:** Backend GPU pipeline phase; validated with 8-10 minute test tracks

---

### Pitfall 5: yt-dlp Blocked by YouTube Datacenter IP Detection

**What goes wrong:**
yt-dlp running on Modal's datacenter infrastructure gets blocked by YouTube with HTTP 429 (Too Many Requests) or HTTP 403 (Forbidden) errors. Downloads fail silently or return errors the client doesn't handle gracefully. Datacenter IPs have only 20-40% success rates against YouTube's bot detection.

**Why it happens:**
YouTube actively detects and blocks datacenter IP ranges (AWS, GCP, Modal's infrastructure). Modal containers share IP pools with other users. YouTube fingerprints requests by IP reputation, user-agent, and behavioral patterns. Even with rate limiting, datacenter IPs are flagged.

**How to avoid:**
- Pin the yt-dlp version in the Modal image — do not use `pip install yt-dlp` (gets latest) without pinning, as yt-dlp updates frequently to counter YouTube countermeasures (the project releases weekly).
- Use yt-dlp's `--cookies` or `--cookies-from-browser` option with a cookies file from a logged-in YouTube account. This significantly reduces bot detection for personal use at low volume (2 users, ~50 YouTube downloads/month).
- Do NOT use `--format bestaudio` for long songs — use `--format "bestaudio[ext=m4a]/bestaudio"` to avoid format negotiation failures.
- Set `--socket-timeout 30` and implement retry logic (3 attempts) in the Modal function.
- For a 2-user personal app at low volume, cookies + pinned version is sufficient. Proxies are not needed at this scale.
- Store cookies in a Modal Secret, not baked into the image.

**Warning signs:**
- yt-dlp installed without version pin (`pip install yt-dlp` in image)
- No cookies configured — running as anonymous client
- No retry logic around the yt-dlp subprocess call
- HTTP 403 errors in Modal function logs

**Phase to address:** YouTube import phase; cookies configuration before any YouTube testing

---

### Pitfall 6: WhisperX Timestamp Misalignment on Music/Song Audio

**What goes wrong:**
WhisperX produces word-level timestamps that are off by 0.5-3 seconds. Karaoke highlighting is out of sync with audio. Known regression introduced in WhisperX v3.3.3 where force-alignment timestamps became inaccurate. Numbers in lyrics (e.g., "1999", "24") cause especially large errors (up to 3 seconds).

**Why it happens:**
WhisperX's forced alignment uses wav2vec2 phoneme models trained on speech, not sung vocals. Song audio — especially with instrumentation bleeding through the vocal stem — degrades alignment accuracy. The force-aligner's dictionary may not include numbers or special characters, causing fallback to interpolated timestamps.

**How to avoid:**
- Run WhisperX on the isolated vocal stem from Demucs, not on the original mixed audio. This is the most impactful improvement.
- Pin WhisperX to a known-good version. Check the GitHub issue tracker for v3.3.3 regression status before pinning.
- Set `align_model="WAV2VEC2_ASR_BASE_960H"` explicitly rather than relying on language-auto-detected models.
- Accept that song lyrics will have lower alignment accuracy than speech (~±0.2s average vs. ±0.05s for speech). Communicate this expectation in the UI — show a 2-3 word highlight window rather than single-word to mask small errors.
- Implement graceful fallback: if alignment confidence below threshold, use segment-level timestamps instead of word-level.

**Warning signs:**
- WhisperX running on the original mixed audio, not the vocal stem
- Karaoke display using exact word timestamps without any visual buffer
- Testing only with clear spoken audio, not sung lyrics with instrumentation

**Phase to address:** Lyrics/transcription phase; tested with actual song vocals

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Polling Modal job status from client every 2s | Simple to implement | Unnecessary network requests, battery drain | MVP only — replace with server-sent events or webhook later |
| Loading all stems into memory before playback | Simpler AVAudioEngine setup | High RAM usage for 10min tracks (4 stems × ~50MB each) | Acceptable for target hardware (M1 Macs with 8-16GB RAM) |
| Single Modal function handling all three models sequentially | One cold start | No parallelism; WhisperX + CREMA could run in parallel after Demucs | MVP — parallelize in optimization phase |
| Storing processed stems as raw WAV files in ~/Music/Strata/ | Simple I/O | High disk usage (~200MB per song uncompressed) | MVP — compress to FLAC or ALAC in optimization phase |
| No retry logic for file downloads from Modal | Faster MVP | Any network hiccup fails the whole job silently | Never — add basic retry from day one |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| AVAudioEngine + AVAudioUnitTimePitch | Connecting pitch node after engine start | Connect all nodes before calling `engine.start()` — reconnecting while running causes audio graph reset |
| Modal Python + yt-dlp | Calling `subprocess.run(["yt-dlp", ...])` without capturing stderr | Always capture both stdout and stderr; yt-dlp writes error details to stderr, not stdout |
| Modal + large file return | Returning audio bytes directly from function | Use Modal Volumes or generate a presigned URL — functions have payload size limits |
| SwiftUI + AVAudioEngine | Creating `AVAudioEngine` as a SwiftUI View property | Engine must be owned by a class (`@StateObject ObservableObject`) — value type re-initialization destroys the audio graph |
| WhisperX + language detection | Relying on auto-detection for Spanish songs | Set `language="es"` explicitly for Spanish content — auto-detection on sung audio frequently misidentifies |
| CREMA + audio format | Passing MP3 bytes directly | CREMA requires librosa-compatible audio — decode to float32 numpy array at 22050 Hz before passing to model |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Sequential model loading in Modal container | Cold start >60s; first request always times out | Load models concurrently in `@modal.enter` using threads; bake weights into image | Every first request after scale-to-zero |
| Uncompressed stem files on disk | ~/Music/Strata grows to 10GB after 50 songs | Use FLAC or ALAC (lossless, ~40% of WAV size) | After ~50 processed songs |
| Synchronous HTTP from Swift while blocking main thread | UI freezes during upload/download | Always use `async`/`await` with `URLSession` — never synchronous API calls | Any file >1MB |
| AVAudioEngine keeping all four PCM buffers in RAM | 400-800MB RAM for one 10-min song | Stream from disk using `scheduleFile` (not `scheduleBuffer`) to let AVAudioEngine manage I/O | 10-min songs on 8GB RAM machines |
| Re-creating AVAudioEngine on every SwiftUI view redraw | Audio drops out on state changes | Engine must live in a persistent `@StateObject`, never recreated | Any state change that triggers view re-evaluation |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Hardcoding Modal API token in Swift source | Token exposed in binary — anyone can run GPU jobs on your account | Store in macOS Keychain; load at runtime |
| JWT secret hardcoded in Modal function | Auth bypass if Modal logs leak | Store JWT secret as Modal Secret (`modal.Secret`), not in source code |
| No file type validation on upload | Arbitrary file upload to GPU backend | Validate magic bytes server-side (not just extension) — check for valid audio headers before processing |
| No processing cost guard | Malformed or very long files could exhaust $10/month GPU budget | Validate duration ≤10 minutes and file size ≤50MB before invoking any GPU function |
| Cookies file for YouTube stored in Modal image | Cookies embedded in image — visible to anyone with image pull access | Store cookies in Modal Secret, mount at runtime |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No progress indication during ~60s processing | User thinks app is frozen or crashed | Show a progress bar with stage labels: "Separating stems... Transcribing lyrics... Detecting chords..." — poll server for stage updates |
| Error message "Request failed" with no detail | User doesn't know if it's a YouTube URL issue, network issue, or server error | Map server error codes to human-readable messages: "YouTube URL unavailable", "File too large (max 50 MB)", "Processing timeout — try a shorter song" |
| Pitch slider responding to every frame of drag | Audio crackling during slider movement | Debounce pitch changes to 50-100ms; show numeric value while dragging but only apply on release or after debounce |
| No cache hit indication | User re-uploads a song already in library | Check library before processing; show "Already processed — loading from cache" immediately |
| Playback controls not working while stems are muted | Silent playback is confusing | Never mute all stems simultaneously — keep at least one stem at minimum volume, or show explicit "all muted" warning |

---

## "Looks Done But Isn't" Checklist

- [ ] **Multi-stem sync:** Tested with a song that has a clear transient at 0:00 (like a snare hit or spoken word) — stems must align at that transient, not just approximately
- [ ] **Pitch shifting:** Tested at extreme values (±1200 cents / ±1 octave) — check for crackling and that all four stems shift identically
- [ ] **YouTube import:** Tested with age-restricted videos, music videos with ads, and very recent uploads — these are the most likely failure cases
- [ ] **Cold start:** Timed first request after 10 minutes idle — must complete within 65s including cold start
- [ ] **Large file upload:** Tested with a 50MB FLAC file on a slow connection — UI must show progress, not time out silently
- [ ] **Cache behavior:** Second request for same song skips GPU entirely and loads in <2s
- [ ] **Error recovery:** Backend job failure returns a human-readable error to the client, not a raw stack trace
- [ ] **10-minute song:** Tested Demucs on a 10-minute track — no OOM, completes within budget

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Multi-stem drift discovered post-ship | HIGH | Full audio engine rewrite — must redesign scheduling to use shared `AVAudioTime` |
| Modal function structured as separate functions causing double cold starts | MEDIUM | Merge into single `@modal.cls` — requires refactoring but no client changes |
| Demucs OOM on long tracks | LOW | Add segment parameter to `apply_model()` call — 1-line fix |
| yt-dlp blocked by YouTube | MEDIUM | Add cookies to Modal Secret + update yt-dlp pin — requires testing but no architecture change |
| WhisperX running on mixed audio instead of vocal stem | LOW | Pass vocal stem path to WhisperX instead of original file — 1-line fix but requires re-processing cached songs |
| AVAudioEngine created in SwiftUI View body | HIGH | Requires full audio layer refactor to separate `ObservableObject` |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Multi-stem drift | Core audio playback phase | Play all four stems of a known song, record output, compare transients — must be within 1ms |
| Pitch shifting crackling | Core audio playback phase | Manual test: drag pitch slider rapidly while all stems play, no audible artifacts |
| Modal cold start over budget | Backend GPU pipeline phase | Time 5 consecutive cold-start requests (10 min apart), all must complete <65s |
| Demucs OOM | Backend GPU pipeline phase | Process a 10-minute test track — must complete without CUDA error |
| yt-dlp blocked | YouTube import phase | Import 5 different YouTube URLs — all must succeed |
| WhisperX misalignment | Lyrics phase | Compare karaoke highlight timing against actual word timing in a known song — must be within ±0.5s |
| Datacenter IP YouTube block | YouTube import phase | Test from Modal environment explicitly, not local dev |
| AVAudioEngine in SwiftUI View | UI phase (first audio UI task) | Toggle between different songs and views — audio must not reset or stutter |

---

## Sources

- [Making Sense of Time in AVAudioPlayerNode — Mehdi Samadi](https://medium.com/@mehsamadi/making-sense-of-time-in-avaudioplayernode-475853f84eb6)
- [Playing files simultaneously in AVAudioEngine — Apple Developer Forums](https://developer.apple.com/forums/thread/14138)
- [Crackling/Popping sound when using AVAudioUnitTimePitch — Apple Developer Forums](https://developer.apple.com/forums/thread/781313)
- [AVAudioUnitTimePitch render latency — Apple Developer Forums](https://developer.apple.com/forums/thread/708168)
- [URLSession: Common pitfalls with background download & upload tasks — Antoine van der Lee](https://www.avanderlee.com/swift/urlsession-common-pitfalls-with-background-download-upload-tasks/)
- [Build robust and resumable file transfers — WWDC23](https://developer.apple.com/videos/play/wwdc2023/10006/)
- [Cold start performance — Modal Docs](https://modal.com/docs/guide/cold-start)
- [Best practices for serverless inference — Modal Blog](https://modal.com/blog/serverless-inference-article)
- [Storing model weights on Modal — Modal Docs](https://modal.com/docs/guide/model-weights)
- [CUDA out of memory while processing long tracks — Demucs GitHub Issue #231](https://github.com/facebookresearch/demucs/issues/231)
- [Word-level timestamps inaccurate — WhisperX GitHub Issue #1247](https://github.com/m-bain/whisperX/issues/1247)
- [Wrong word-level timestamps from v3.3.3 — WhisperX GitHub Issue #1220](https://github.com/m-bain/whisperX/issues/1220)
- [YouTube video download fails due to bot detection — yt-dlp GitHub Issue #13067](https://github.com/yt-dlp/yt-dlp/issues/13067)
- [YouTube Proxy: Prevent Server IP Blocks After Deploying yt-dlp-Style Server Workloads](https://proxy001.com/blog/youtube-proxy-prevent-server-ip-blocks-after-deploying-yt-dlp-style-server-workloads)
- [Scaling to zero cold start latency — regolo.ai](https://regolo.ai/scale-to-zero-cold-start-latency-why-serverless-gpu-breaks-real-time-ai-and-how-to-fix-it/)

---
*Pitfalls research for: macOS audio stem separation app (Strata)*
*Researched: 2026-03-02*
