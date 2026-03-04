---
phase: 07-player-ui-display-usage
plan: "04"
subsystem: ui
tags: [swiftui, dswaveformimage, avfaudio, player, waveforms, stems]

requires:
  - phase: 07-03
    provides: PlayerViewModel @Observable, PlaybackEngine, CacheManager environment key

provides:
  - PlayerView con layout completo (sidebar + zona principal + barras superior/inferior)
  - StemControlsView sidebar con botones M/S y slider de volumen por stem
  - TransportBarView con play/pause/seek/rew/fwd/loop y toggles Letras/Acordes
  - PitchPopover con control de semitones, restablecer y toggle showTransposed
  - WaveformsView con 4 StemWaveformRow (DSWaveformImage) + playhead sincronizado

affects:
  - 07-05 (LyricsView se inserta en la zona principal de PlayerView)

tech-stack:
  added: []
  patterns:
    - "ABLoopButton con enum LoopPhase (idle/startSet/active) para manejar el ciclo A/B"
    - "StemRowView con Binding a engine.getVolume/setVolume para Slider en tiempo real"
    - "WaveformsView usa cacheManager!.stemURL() (síncrono, actor nonisolated)"

key-files:
  created:
    - StrataClient/Player/StemControlsView.swift
    - StrataClient/Player/PitchPopover.swift
    - StrataClient/Player/TransportBarView.swift
    - StrataClient/Player/Waveforms/WaveformsView.swift
  modified:
    - StrataClient/Player/PlayerView.swift

key-decisions:
  - "ABLoopButton implementado como struct privado en PlayerView con LoopPhase enum — encapsula lógica de 3 fases sin contaminar PlayerView"
  - "isSoloed heurística inferida desde engine.getVolume/isMuted — PlaybackEngine no expone soloedStem públicamente, sin añadir API nueva"
  - "TransportBarView sin toggle Secciones — diferido a v2 según decisión previa del usuario"

patterns-established:
  - "Zona principal modal en PlayerView: switch !showLyrics/!showChords para waveforms, stubs para lyrics/chords (plan 05 los sustituye)"
  - "Botones toggle tipo Letras/Acordes: Button plain con background tintado + borde RoundedRectangle"

requirements-completed:
  - DISP-05

duration: 2min
completed: "2026-03-05"
---

# Phase 07 Plan 04: Player Layout Completo Summary

**Layout del reproductor estilo Moises: sidebar de stems con M/S/volumen, barra de transporte completa, pitch popover y 4 waveforms por stem con playhead sincronizado en DSWaveformImage**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-05T23:32:32Z
- **Completed:** 2026-03-05T23:34:59Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- PlayerView con layout HStack completo: sidebar 140px + zona principal + barras superior/inferior
- StemControlsView con 4 filas (Voz/Bateria/Bajo/Otro), botones M/S con tint highlight y Slider de volumen
- TransportBarView con slider de progreso, timestamps, play/pause/rew10s/fwd10s, loop indicator, toggles Letras y Acordes con estilo visual activo/inactivo
- PitchPopover: nota actual (transpuesta si hay key), botones −/+/Restablecer, toggle showTransposed cuando hay acordes
- WaveformsView con 4 StemWaveformRow usando DSWaveformImage con color teal y playhead vertical proporcional a currentTime/duration

## Task Commits

1. **Task 1: PlayerView layout + StemControlsView sidebar + PitchPopover** - `6da43cb` (feat)
2. **Task 2: TransportBarView + WaveformsView con playhead** - `05b0a34` (feat)

## Files Created/Modified

- `StrataClient/Player/PlayerView.swift` — Vista raíz del reproductor con layout completo y ABLoopButton
- `StrataClient/Player/StemControlsView.swift` — Sidebar con controles M/S/volumen por stem
- `StrataClient/Player/PitchPopover.swift` — Popover control pitch con -/+/restablecer/showTransposed
- `StrataClient/Player/TransportBarView.swift` — Barra inferior transporte + toggles Letras/Acordes
- `StrataClient/Player/Waveforms/WaveformsView.swift` — 4 waveforms DSWaveformImage + playhead sincronizado

## Decisions Made

- ABLoopButton como struct privado con enum LoopPhase en vez de 3 @State booleans en PlayerView — más limpio y encapsulado
- isSoloed inferido heurísticamente desde getVolume/isMuted — evita añadir API pública a PlaybackEngine para exponer soloedStem
- TransportBarView sin toggle Secciones según decisión previa del usuario (diferido a v2)

## Deviations from Plan

Ninguna — plan ejecutado exactamente como estaba especificado.

## Issues Encountered

Las tareas 1 y 2 se commitaron por separado aunque PlayerView referencia TransportBarView y WaveformsView (compilación requería ambos ficheros presentes). La compilación se verificó tras crear los 5 ficheros, y los commits se hicieron en orden correcto de tarea.

## Next Phase Readiness

- PlayerView listo para recibir LyricsView y ChordView en la zona principal (plan 05 ya ejecutado anteriormente)
- Todos los slots modales implementados — switch por showLyrics/showChords ya en su lugar
- Build compila limpio (BUILD SUCCEEDED verificado)

---
*Phase: 07-player-ui-display-usage*
*Completed: 2026-03-05*
