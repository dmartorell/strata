---
phase: quick-3
plan: "01"
subsystem: player-ui
tags: [seek, waveform, gesture, player]
dependency_graph:
  requires: [PlaybackEngine.seek(to:)]
  provides: [seek-on-tap en WaveformsView]
  affects: [StrataClient/Player/Waveforms/WaveformsView.swift]
tech_stack:
  added: []
  patterns: [DragGesture(minimumDistance:0) para captura de posición de tap]
key_files:
  created: []
  modified:
    - StrataClient/Player/Waveforms/WaveformsView.swift
decisions:
  - DragGesture(minimumDistance:0) en lugar de onTapGesture — permite capturar la posición X exacta del click dentro del ZStack
metrics:
  duration: "~3 min"
  completed: "2026-03-05"
---

# Phase quick-3 Plan 01: Seek-on-tap en Waveforms Summary

**One-liner:** Seek-on-tap en StemWaveformRow via DragGesture que calcula fracción X/width y llama engine.seek(to:) preservando play/pause.

## What Was Built

Añadido un `.gesture(DragGesture(minimumDistance: 0))` al `ZStack` de `StemWaveformRow` dentro del `GeometryReader`. El handler `.onEnded` calcula la fracción de posición horizontal (`value.location.x / geo.size.width`), la clampea a [0, 1], y llama `engine.seek(to: engine.duration * Double(clamped))`. El engine ya preservaba el estado play/pause internamente, por lo que no fue necesario ningún cambio adicional.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Seek-on-tap en StemWaveformRow | 86381f1 | WaveformsView.swift |

## Decisions Made

- `DragGesture(minimumDistance: 0)` en lugar de `onTapGesture`: el gesture de tap de SwiftUI no expone la posición del click; `DragGesture` con distancia mínima 0 se comporta como tap pero proporciona `value.location.x`.

## Deviations from Plan

None - plan ejecutado exactamente como estaba escrito.

## Self-Check: PASSED

- [x] `StrataClient/Player/Waveforms/WaveformsView.swift` existe y contiene el gesture
- [x] Commit `86381f1` existe en git log
- [x] Build `** BUILD SUCCEEDED **` sin errores ni warnings nuevos
