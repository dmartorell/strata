---
phase: 22-add-guitar-tuner
plan: "01"
subsystem: audio-ui
tags: [tuner, pitch-detection, vdsp, avfoundation, swiftui, microphone]
dependency_graph:
  requires: [PlaybackEngine, StemControlsView, SiyahambaApp]
  provides: [GuitarTuning, TunerEngine, TunerView]
  affects: [StemControlsView, SiyahambaApp]
tech_stack:
  added: [Accelerate/vDSP, AVCaptureDevice, AVAudioEngine (independent instance)]
  patterns: [@Observable @MainActor engine, @Environment injection, vDSP autocorrelation with Hanning window]
key_files:
  created:
    - SiyahambaClient/Audio/GuitarTuning.swift
    - SiyahambaClient/Audio/TunerEngine.swift
    - SiyahambaClient/Player/TunerView.swift
    - SiyahambaClient/SiyahambaClient.entitlements
  modified:
    - SiyahambaClient/Player/StemControlsView.swift
    - SiyahambaClient/App/SiyahambaApp.swift
    - SiyahambaClient/Info.plist
    - project.yml
decisions:
  - TunerEngine uses independent AVAudioEngine (not PlaybackEngine's) to avoid graph conflicts when playback is paused
  - PlaybackEngine reference passed via init to TunerEngine — same class instance shared from SiyahambaApp init
  - vDSP autocorrelation with Hanning window + parabolic interpolation covers E2-E4 guitar range (75-350Hz search window)
  - Update throttle at 100ms intervals in tap callback to reduce MainActor pressure
  - Entitlements include network.client + files.user-selected.read-only to preserve existing sandbox capabilities
metrics:
  duration: "~4 min"
  completed_date: "2026-03-25"
  tasks_completed: 2
  files_modified: 8
---

# Quick Task 22: Add Guitar Tuner Popup — Summary

**One-liner:** Guitar tuner integrated in stem sidebar using vDSP autocorrelation pitch detection with deviation indicator (E2-E4), playback pause coordination, and microphone entitlements for macOS sandbox.

## What Was Built

### GuitarTuning.swift
- `GuitarString` enum (6 cases: E2/A2/D3/G3/B3/E4) with standard frequencies
- `closestString(to:)` using log-frequency distance for accurate nearest-note detection
- `deviationInCents(pitch:target:)` using 1200 * log2(pitch/target) formula

### TunerEngine.swift
- `@Observable @MainActor TunerEngine` with independent `AVAudioEngine` (never shared with `PlaybackEngine`)
- Mic tap: 4096-sample buffer, Hanning window via `vDSP_hann_window` + `vDSP_vmul`
- Autocorrelation: manual dot-product per lag using `vDSP_dotpr`, search range Int(sR/350)..Int(sR/75)
- Confidence threshold: peak > 0.2 * r0; parabolic interpolation for sub-sample accuracy
- Throttle: dispatches to MainActor at most every 100ms
- Pause/resume: saves `wasPlaying`, pauses `PlaybackEngine.pause()` on start, resumes on stop

### TunerView.swift
- Collapsed: single "Afinar" button with `tuningfork` SF Symbol
- Expanded: note name + cents label, deviation bar (green ≤5¢, yellow ≤20¢, red >20¢), string selector (6 strings + Auto button), "Cerrar" button
- `onDisappear` safety: calls `tuner.stop()` if active when view disappears

### Integration
- `StemControlsView`: `TunerView()` added after `Spacer()` at bottom of VStack
- `SiyahambaApp`: `PlaybackEngine` created as local `pe`, `TunerEngine(playbackEngine: pe)` shares same instance; both injected via `.environment()`
- `Info.plist` + `project.yml`: `NSMicrophoneUsageDescription` added
- `SiyahambaClient.entitlements`: `app-sandbox` + `audio-input` + `network.client` + `files.user-selected.read-only`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] vDSP_conv pointer arithmetic warning**
- **Found during:** Task 1 build verification
- **Issue:** `&reversedSamples + (frameCount - 1)` is invalid inout pointer arithmetic in Swift — compiler warning "cannot use inout expression here"
- **Fix:** Replaced with explicit `vDSP_dotpr` per-lag dot product loop, avoiding pointer arithmetic entirely. More readable and correct.
- **Files modified:** SiyahambaClient/Audio/TunerEngine.swift
- **Commit:** 609e391 (included in same task commit after fix)

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 609e391 | feat(22-add-guitar-tuner-01): GuitarTuning model and TunerEngine with vDSP pitch detection |
| 2 | 2217cb4 | feat(22-add-guitar-tuner-01): TunerView UI and wire environment, entitlements, mic permission |

## Self-Check

### Files exist
- [x] SiyahambaClient/Audio/GuitarTuning.swift
- [x] SiyahambaClient/Audio/TunerEngine.swift
- [x] SiyahambaClient/Player/TunerView.swift
- [x] SiyahambaClient/SiyahambaClient.entitlements

### Build status
- [x] BUILD SUCCEEDED (no errors, no warnings from new code)

## Self-Check: PASSED
