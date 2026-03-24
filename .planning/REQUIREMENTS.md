# Requirements: Strata

**Defined:** 2026-03-02
**Core Value:** El flujo completo debe funcionar sin fricciones: importar una cancion → esperar ~1 minuto → reproduccion interactiva con stems, letras y acordes.

## v1 Requirements

### Authentication

- [x] **AUTH-01**: User can log in with password only (no username field visible)
- [x] **AUTH-02**: User session persists for 90 days via JWT stored in Keychain
- [x] **AUTH-03**: Token renews silently when close to expiration without user interaction
- [x] **AUTH-04**: Expired token redirects user to login screen automatically

### Audio Import

- [x] **IMPT-01**: User can import audio by dragging MP3/WAV/FLAC/M4A files onto the app
- [x] **IMPT-02**: User can import audio by pasting a YouTube URL
- [x] **IMPT-03**: App validates input (supported format, valid YouTube URL) before processing
- [x] **IMPT-04**: App shows processing state feedback: validating → uploading → processing → ready / error

### Audio Processing (Server)

- [x] **PROC-01**: Server separates audio into 4 stems (vocals, drums, bass, other) using Demucs v4
- [x] **PROC-02**: Server transcribes lyrics with word-level timestamps using WhisperX on vocal stem
- [x] **PROC-03**: Server detects chords with timestamps using CREMA on other stem
- [x] **PROC-04**: Server packages results as ZIP (4 stem WAVs + lyrics.json + chords.json + metadata.json)
- [x] **PROC-05**: Server processes file uploads in <60 seconds
- [x] **PROC-06**: Server processes YouTube URLs in <65 seconds (including download)
- [x] **PROC-07**: Server enforces 50 MB file size limit and 10 min duration limit
- [x] **PROC-08**: Server downloads YouTube audio via yt-dlp with proper cookie configuration

### Playback

- [x] **PLAY-01**: User can play 4 stems in perfect sync (no drift over time) via AVAudioEngine
- [x] **PLAY-02**: User can control volume independently per stem
- [x] **PLAY-03**: User can mute/solo individual stems
- [x] **PLAY-04**: User can play, pause, and seek to any position in the song
- [x] **PLAY-05**: User can shift pitch in real time without stopping playback (AVAudioUnitTimePitch)
- [x] **PLAY-06**: User can set A/B loop markers to repeat a section continuously

### Display

- [x] **DISP-01**: App shows synchronized lyrics with current line highlighted and surrounding context
- [x] **DISP-02**: App highlights current word in lyrics (karaoke-style word-by-word)
- [x] **DISP-03**: App shows current chord prominently with next chord visible
- [x] **DISP-04**: Lyrics and chords update correctly when user seeks or changes pitch
- [x] **DISP-05**: App shows waveform visualization per stem

### Chord Diagrams

- [x] **CHRD-01**: Server generates guitar fingering data (frets, fingers, baseFret, barres) for each detected chord using tombatossals/chords-db
- [x] **CHRD-02**: Server normalizes Chordino chord names and handles enharmonic equivalents for fingering lookup
- [x] **CHRD-03**: App shows guitar chord finger position diagram below chord name via SwiftUI Canvas
- [x] **CHRD-04**: App shows diagrams for both current and next chord with visual hierarchy (current full-size, next smaller/dimmer)
- [x] **CHRD-05**: App provides toggle for diagram visibility (persisted in UserDefaults, enabled by default) with variation navigation

### Library

- [x] **LIBR-01**: Processed songs are cached locally in ~/Music/Strata/ with stems + JSON files
- [x] **LIBR-02**: Previously processed songs load instantly from local cache without server

### Usage Tracking

- [x] **USGR-01**: User can view monthly usage panel (songs processed + estimated GPU cost)
- [x] **USGR-02**: Usage panel shows spending limit progress bar ($10/month cap)
- [x] **USGR-03**: Server tracks usage per user per month (songs, GPU seconds, estimated cost)
- [x] **USGR-04**: Server returns 429 when monthly spending limit is reached

### Infrastructure

- [x] **INFR-01**: All server endpoints validate JWT before processing
- [x] **INFR-02**: Server runs on Modal with GPU T4, concurrency limit of 2
- [ ] **INFR-03**: ML model weights baked into Modal image (no download at inference time)
- [ ] **INFR-04**: Server cold start + processing stays within time budget

## v2 Requirements

### Playback

- **PLAY-07**: User can change tempo independently of pitch (AVAudioUnitVarispeed)

### Library

- **LIBR-03**: Library shows metadata (title, artist, YouTube thumbnail) for each song
- **LIBR-04**: User can delete songs from library

### Display

- **DISP-06**: Keyboard shortcuts (space=play, arrows=seek, ⌘V=paste URL)

### Import

- **IMPT-05**: User can import multiple songs in a batch queue

## Out of Scope

| Feature | Reason |
|---------|--------|
| Real-time chat | Not relevant to music practice use case |
| Video playback | Audio-only app, no video rendering |
| Mobile app (iOS/Android) | macOS only for 2 personal users |
| OAuth / social login | Password-only is sufficient for 2 users |
| Manual lyrics/chord editing | Accept ML model output as-is; high complexity, low value |
| App Store distribution | Personal use, no signing needed |
| In-app recording | Triples scope, not in vision |
| Social/sharing features | Personal app for 2 users |
| Tempo control independent of pitch | Deferred to v2 — pitch shift covers primary use case |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 3 | Complete |
| AUTH-02 | Phase 3 | Complete |
| AUTH-03 | Phase 3 | Complete |
| AUTH-04 | Phase 3 | Complete |
| IMPT-01 | Phase 6 | Complete |
| IMPT-02 | Phase 6 | Complete |
| IMPT-03 | Phase 6 | Complete |
| IMPT-04 | Phase 6 | Complete |
| PROC-01 | Phase 2 | Complete |
| PROC-02 | Phase 2 | Complete |
| PROC-03 | Phase 2 | Complete |
| PROC-04 | Phase 2 | Complete |
| PROC-05 | Phase 2 | Complete |
| PROC-06 | Phase 2 | Complete |
| PROC-07 | Phase 2 | Complete |
| PROC-08 | Phase 2 | Complete |
| PLAY-01 | Phase 5 | Complete |
| PLAY-02 | Phase 5 | Complete |
| PLAY-03 | Phase 5 | Complete |
| PLAY-04 | Phase 5 | Complete |
| PLAY-05 | Phase 5 | Complete |
| PLAY-06 | Phase 5 | Complete |
| DISP-01 | Phase 7 | Complete |
| DISP-02 | Phase 7 | Complete |
| DISP-03 | Phase 7 | Complete |
| DISP-04 | Phase 7 | Complete |
| DISP-05 | Phase 7 | Complete |
| CHRD-01 | Phase 9 | Complete |
| CHRD-02 | Phase 9 | Complete |
| CHRD-03 | Phase 9 | Complete |
| CHRD-04 | Phase 9 | Complete |
| CHRD-05 | Phase 9 | Complete |
| LIBR-01 | Phase 4 | Complete |
| LIBR-02 | Phase 4 | Complete |
| USGR-01 | Phase 7 | Complete |
| USGR-02 | Phase 7 | Complete |
| USGR-03 | Phase 7 | Complete |
| USGR-04 | Phase 7 | Complete |
| INFR-01 | Phase 1 | Complete |
| INFR-02 | Phase 1 | Complete |
| INFR-03 | Phase 1 | Pending |
| INFR-04 | Phase 1 | Pending |

**Coverage:**
- v1 requirements: 42 total
- Mapped to phases: 42
- Unmapped: 0

---
*Requirements defined: 2026-03-02*
*Last updated: 2026-03-24 after Phase 9 planning*
