---
phase: 05-multi-stem-playback
plan: 02
subsystem: audio
tags: [AVAudioEngine, AVAudioUnitTimePitch, AVAudioMixerNode, pitch-shift, stem-control, swift]

requires:
  - phase: 05-multi-stem-playback
    plan: 01
    provides: PlaybackEngine con AVAudioEngine, grafo audio 4 stems, play/pause/seek, currentTime 60fps

provides:
  - setPitch(semitones:) con rango -6...+6 en cents via timePitchNode.pitch
  - setVolume(_:for:) / getVolume(for:) por stem con clamping 0.0-1.0
  - setMute(_:for:) / isMuted(_:) persistiendo volumen del usuario en stemVolumes
  - setSolo(_:) silenciando todos los stems excepto el indicado (o nil para desactivar)
  - applyVolumes() privado centralizando logica stemMixers[i].outputVolume
  - Stem enum (vocals, drums, bass, other) exportado a nivel de fichero

affects:
  - 05-multi-stem-playback (plan 03 — loop playback usa el mismo PlaybackEngine)
  - UI que consuma PlaybackEngine para controles por stem

tech-stack:
  added: []
  patterns:
    - "outputVolume = 0 para mute/solo (no detach/reattach — evita clicks y pops)"
    - "applyVolumes() centralizado: toda mutacion de volumen pasa por un solo punto"
    - "stemVolumes persiste el valor del usuario para restaurar tras mute o desactivar solo"

key-files:
  created: []
  modified:
    - StrataClient/Audio/PlaybackEngine.swift

key-decisions:
  - "outputVolume = 0 para mute/solo en lugar de detach/reattach — evita artifacts de audio"
  - "applyVolumes() como punto unico de verdad para stemMixers[i].outputVolume"
  - "stemVolumes persiste el valor del usuario independientemente del estado mute/solo"

patterns-established:
  - "Pitch en cents: semitones * 100 — convencion AVAudioUnitTimePitch"
  - "Guard index bounds en todos los metodos publicos por stem"

requirements-completed: [PLAY-02, PLAY-03, PLAY-05]

duration: 5min
completed: 2026-03-03
---

# Phase 5 Plan 02: Pitch Shift + Per-Stem Volume/Mute/Solo Summary

**setPitch (+-6 semitones en cents), setVolume/setMute/setSolo por stem con applyVolumes() centralizado y Stem enum, todo via outputVolume sin detach/reattach**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-03T22:24:52Z
- **Completed:** 2026-03-03T22:30:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- `Stem` enum con casos `vocals`, `drums`, `bass`, `other` exportado a nivel de fichero
- `setPitch(semitones:)` clampea a -6...+6 y aplica `Float(clamped * 100)` a `timePitchNode.pitch` en tiempo real
- `setVolume(_:for:)` / `getVolume(for:)` con clamping 0.0-1.0 y persistencia en `stemVolumes`
- `setMute(_:for:)` / `isMuted(_:)` con restauracion de volumen del usuario via `stemVolumes`
- `setSolo(_:)` acepta `Int?` — `nil` desactiva solo, indice valido silencia el resto
- `applyVolumes()` privado centraliza toda la logica de `stemMixers[i].outputVolume`
- Reset de `stemVolumes`, `stemMuted` y `soloedStem` al final de `load(stemURLs:)`

## Task Commits

1. **Task 1: Pitch shift global (setPitch) + per-stem volume/mute/solo** - `4d0fa75` (feat)

**Plan metadata:** pendiente (docs commit final)

## Files Created/Modified

- `/Volumes/T7_SAMSUNG/strata/StrataClient/Audio/PlaybackEngine.swift` - Extendido con Stem enum, propiedades stemVolumes/stemMuted/soloedStem, metodos setPitch/setVolume/getVolume/setMute/isMuted/setSolo, y applyVolumes() privado

## Decisions Made

- `outputVolume = 0` para mute/solo en lugar de detach/reattach de nodos: evita clicks y pops en el audio
- `applyVolumes()` como punto centralizado: cualquier cambio de mute, solo o volumen pasa siempre por el mismo codigo
- `stemVolumes` persiste independientemente de `stemMuted` y `soloedStem` para poder restaurar el valor exacto del usuario

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

El build con `CODE_SIGNING_ALLOWED=NO` fue necesario porque el entorno de ejecucion no tiene Development Team configurado. Los warnings de Swift 6 Sendable son pre-existentes y fuera de scope.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- PlaybackEngine listo para Plan 03 (loop playback entre loopStart y loopEnd)
- Todos los controles de pitch, volumen, mute y solo disponibles para la UI
- No hay bloqueantes

---
*Phase: 05-multi-stem-playback*
*Completed: 2026-03-03*
