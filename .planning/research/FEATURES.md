# Feature Research

**Domain:** macOS native app — audio stem separation, karaoke lyrics, chord detection, music practice
**Researched:** 2026-03-02
**Confidence:** HIGH (cross-validated across Moises, Capo, Anytune, Amazing Slow Downer, iReal Pro, PhonicMind)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Stem separation (vocals, drums, bass, other) | Every competitor offers 4-stem split as baseline | MEDIUM | Demucs v4 is the standard model; lower stem counts feel outdated |
| Per-stem volume control | Without this, stem separation is useless for practice | LOW | Sliders per track; mute toggle per stem |
| Per-stem mute/solo toggle | Standard in every DAW and stem app (Moises, Capo, iReal Pro) | LOW | Tap to mute/unmute; solo mode useful |
| Pitch shifting (global, semitone steps) | Vocalists need to shift to their range; instrumentalists transpose for their key | LOW | AVAudioUnitTimePitch covers this; ±12 semitones is standard range |
| Tempo/speed change without pitch drift | Core of every practice app (Amazing Slow Downer, Anytune); users learning solos slow down to 50-70% | LOW | Pitch-preserved time stretching; well-solved problem |
| Local file import (MP3/WAV/FLAC/M4A) | Primary source for users with music collections | LOW | Drag-and-drop is the native macOS pattern |
| Playback progress bar + scrubbing | Basic transport; users skip to sections | LOW | Standard media player behavior |
| Song library / history | Users re-open processed songs without re-paying for GPU time | LOW | Local cache is the solution; users expect instant load for repeat plays |
| Processing status / progress feedback | 60-second processing feels broken without feedback | LOW | Progress indicator with estimated time remaining |
| Audio export of individual stems | Expected by power users for use in DAWs, backing track apps | MEDIUM | File-per-stem export; optional but widely expected |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Word-level karaoke lyrics (WhisperX) | No competitor combines AI lyrics with stem practice in a native macOS app; Moises has it on mobile only | HIGH | WhisperX provides word-level timestamps; display as scrolling karaoke highlight |
| Synchronized chord display (CREMA) | Guitarists/pianists see chords overlaid on timeline; Capo does this from local analysis only | HIGH | CREMA gives ~80-85% accuracy; chords scroll with playback; enough to learn songs |
| YouTube URL import | Removes friction of downloading before processing; half the use case for this project | MEDIUM | yt-dlp on server side; paste URL = start processing |
| Chord timeline visualization | Visual display of chord changes on a scrolling timeline while song plays | MEDIUM | Can be simple text-based timeline; Moises and Capo both have this |
| Key / BPM display | Useful at-a-glance metadata for practice decisions | LOW | CREMA detects key; tempo from beat tracking |
| Native macOS SwiftUI app | No competitor builds a native macOS stem app; all are iOS ports or web apps | HIGH | SwiftUI + AVAudioEngine gives real native feel with low memory footprint |
| Usage / cost tracker | Transparency on GPU spend builds trust; useful for personal budget management | LOW | Song count + estimated Modal cost displayed per month |
| Instant playback from cache | Songs processed once load instantly on subsequent opens | LOW | Cache check before hitting API; core to UX smoothness |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Manual lyric/chord editing | Users find transcription errors and want to fix them | Editing UI is complex to build; scope creep; this is personal use so 85% accuracy is fine | Accept model output as-is; display confidence indicator if needed |
| Real-time stem separation (on-device) | Sounds impressive; Demucs runs locally | Apple Silicon can run Demucs but setup is complex, model is 80MB+, quality varies; latency unpredictable | Serverless GPU ensures consistent quality and frees the client |
| Tabbed/multi-song simultaneous playback | Power users sometimes want A/B comparison | AVAudioEngine session conflicts; complexity vs. reward is unfavorable for 2 users | Sequential use is sufficient; library makes switching fast |
| Social / sharing features | Other apps (Moises) have share-to-community | Completely out of scope for 2-person personal app; adds auth complexity and moderation burden | Stem export to files covers the "share with bandmates" use case |
| Video playback with lyrics overlay | Karaoke apps do this; YouTube shows the video | Out of scope per PROJECT.md; video pipeline multiplies complexity | Audio-only; lyrics display is sufficient without video |
| Real-time collaborative practice | iReal Pro has shared sessions | Requires WebRTC or similar; massive complexity; not needed for 2 local users | Each user runs their own instance |
| In-app recording | Record yourself over a backing track | Requires audio capture pipeline, storage, playback sync; high complexity for low current value | Out of scope; DAWs exist for this |
| Chord editing / custom charts | iReal Pro's core value prop | Building a chord editor is a separate product; CREMA output is sufficient | Display detected chords read-only |
| A/B loop section with markers | Core feature of Amazing Slow Downer and Anytune | High-value feature but adds state management complexity; not in original scope | Can be added in v1.x once core flow works; placeholder in v1 |

---

## Feature Dependencies

```
YouTube URL Import
    └──requires──> yt-dlp on server
                       └──requires──> Modal server endpoint

Stem Playback
    └──requires──> Stem Separation (Demucs v4)
                       └──requires──> Modal GPU processing

Karaoke Lyrics Display
    └──requires──> WhisperX transcription
                       └──requires──> Modal GPU processing
    └──requires──> Stem Separation (audio must exist first)

Chord Display
    └──requires──> CREMA chord detection
                       └──requires──> Modal GPU processing

Pitch Shifting ──enhances──> Stem Playback (shifts all stems together)
Tempo Control ──enhances──> Stem Playback (slows playback for practice)

Song Library / Cache
    └──requires──> Processing pipeline complete
    └──enhances──> All playback features (instant load)

Per-stem Volume Control ──requires──> Stem Separation
Per-stem Mute ──requires──> Stem Separation

Usage Tracker
    └──requires──> Processing pipeline (counts jobs)
    └──enhances──> Cost transparency
```

### Dependency Notes

- **Stem Separation is the root dependency**: every practice feature (volume, mute, pitch, tempo) depends on having processed stems.
- **WhisperX and CREMA are independent of each other**: can be processed in parallel on the server.
- **Cache must come early**: once songs are processed, the library depends on cache being stable. Changing cache format later is disruptive.
- **Pitch shifting conflicts with per-stem pitch**: shifting all stems together is straightforward; shifting individual stems (e.g., only vocals) requires separate AVAudioUnitTimePitch per stem node and adds AVAudioEngine complexity.

---

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the concept.

- [ ] Local file import (drag-and-drop MP3/WAV/FLAC/M4A) — primary input method
- [ ] YouTube URL import (paste URL) — covers the 50% YouTube use case from day one
- [ ] 4-stem separation via Demucs v4 on Modal — the core value
- [ ] Synchronized multi-stem playback (AVAudioEngine) — must play all stems together
- [ ] Per-stem volume and mute controls — essential for practice (play without drums, etc.)
- [ ] Global pitch shifting (semitone steps, ±12) — vocalists need this immediately
- [ ] Global tempo control (50%-150%, pitch-preserved) — table stakes for learning solos
- [ ] Karaoke lyrics with word-level highlight (WhisperX) — key differentiator, sets Strata apart
- [ ] Chord display on timeline (CREMA) — key differentiator for instrumentalists
- [ ] Song library with local cache — without this, every open costs GPU time
- [ ] Processing status feedback — 60-second wait needs progress indication
- [ ] Simple password auth (JWT + Keychain) — minimum viable access control for 2 users
- [ ] Monthly usage panel — cost transparency for personal GPU budget

### Add After Validation (v1.x)

Features to add once core is working.

- [ ] A/B loop section with markers — most requested practice feature after tempo control; add when core flow is stable
- [ ] Export individual stems to files — useful for DAW users; not blocking launch
- [ ] BPM and key metadata display — nice to surface from CREMA analysis already being run

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] Per-stem pitch shifting (independent per track) — AVAudioEngine complexity; rarely needed
- [ ] On-device Demucs (Apple Neural Engine) — interesting for offline use; model size and setup complexity not worth it now
- [ ] iOS app — explicitly out of scope per PROJECT.md

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| 4-stem separation (Demucs v4) | HIGH | MEDIUM | P1 |
| Per-stem volume / mute | HIGH | LOW | P1 |
| Karaoke lyrics word-level (WhisperX) | HIGH | MEDIUM | P1 |
| Chord display (CREMA) | HIGH | MEDIUM | P1 |
| Pitch shifting (global) | HIGH | LOW | P1 |
| Tempo control (pitch-preserved) | HIGH | LOW | P1 |
| YouTube URL import | HIGH | MEDIUM | P1 |
| Local file drag-and-drop import | HIGH | LOW | P1 |
| Song library / local cache | HIGH | LOW | P1 |
| Processing status / progress | HIGH | LOW | P1 |
| Monthly usage panel | MEDIUM | LOW | P1 |
| Password auth (JWT + Keychain) | MEDIUM | LOW | P1 |
| A/B loop markers | HIGH | MEDIUM | P2 |
| Stem export to files | MEDIUM | LOW | P2 |
| BPM / key metadata display | LOW | LOW | P2 |
| Per-stem pitch shifting | MEDIUM | HIGH | P3 |
| On-device Demucs | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

| Feature | Moises | Capo (macOS) | Anytune (macOS) | Amazing Slow Downer | Strata Approach |
|---------|--------|--------------|-----------------|---------------------|-----------------|
| Stem separation | Yes (4-6 stems, AI) | Partial (simple vocal removal) | No | No | Yes (4 stems, Demucs v4) |
| Synchronized lyrics | Yes (word-level, premium) | No | No | No | Yes (WhisperX, word-level) |
| Chord detection | Yes (timeline) | Yes (timeline + tabs) | No | No | Yes (CREMA, timeline display) |
| Pitch shifting | Yes (semitones) | Yes + capo simulation | Yes (±24 semitones) | Yes | Yes (global, semitone steps) |
| Tempo control | Yes | Yes | Yes (down to 0.05x) | Yes (20%-200%) | Yes (global, pitch-preserved) |
| A/B loop section | Yes | Yes | Yes | Yes | v1.x (deferred) |
| YouTube import | No | No | No | No | Yes (key differentiator) |
| Native macOS app | No (iOS port/web) | Yes | Yes | Yes | Yes (SwiftUI, first-class) |
| Local cache | Cloud-first | Local | Local | Local | Yes (~/Music/Strata/) |
| Offline playback | No (cloud-only) | Yes | Yes | Yes | Yes (once cached) |
| Pricing | Subscription | One-time purchase | One-time purchase | One-time purchase | Free (personal GPU cost) |

---

## Sources

- [Moises App — Products page](https://moises.ai/products/moises-app/)
- [Moises — Latest Features 2025](https://moises.ai/blog/moises-news/moises-features/)
- [Capo for macOS — Supermegaultragroovy](http://supermegaultragroovy.com/products/capo/mac/)
- [Capo — Chord Detection](http://supermegaultragroovy.com/products/capo/get-guitar-chords-mac/)
- [Anytune for Mac](https://www.anytune.app/)
- [Amazing Slow Downer for macOS](https://www.ronimusic.com/amsldox.htm)
- [iReal Pro](https://www.irealpro.com)
- [PhonicMind AI vocal remover](https://phonicmind.com/)
- [Best iOS Apps for AI Stem Separation 2025 — Mixcord](https://www.mixcord.co/blogs/content-creators/best-ios-apps-for-ai-stem-separation-2025)
- [Amazing Slow Downer vs Anytune vs Practice Session 2026](https://www.practicesession.app/blog/practice-session-vs-amazing-slow-downer-vs-anytune/)
- [MusicRadar — 11 best stem separation tools tested](https://www.musicradar.com/music-tech/i-tested-11-of-the-best-stem-separation-tools-and-you-might-already-have-the-winner-in-your-daw)
- [Musical U — Learning by repetition with looping](https://www.musical-u.com/learn/learning-by-repetition-how-musicians-can-improve-with-looping/)

---

*Feature research for: macOS audio stem separation / karaoke / chord detection app (Strata)*
*Researched: 2026-03-02*
