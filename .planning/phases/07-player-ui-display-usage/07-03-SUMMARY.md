---
phase: 07-player-ui-display-usage
plan: 03
subsystem: ui
tags: [swiftui, observable, table, playerviewmodel, lyrics, chords, playbackengine]

requires:
  - phase: 07-01-modelos-de-datos
    provides: LyricsModels, ChordModels, ChordTransposer, SongEntry.pitchOffset/key, APIClient.fetchUsage
  - phase: 05-multi-stem-playback
    provides: PlaybackEngine con currentTime, load(stemURLs:), setPitch(semitones:)
  - phase: 04-library-cache
    provides: CacheManager, LibraryStore, SongEntry

provides:
  - PlayerViewModel @Observable @MainActor con load(), currentLine, currentWord, currentChord, nextChord, displayChord, savePitchOffset
  - LibraryView con SwiftUI Table 4 columnas, seleccion multiple, delete, double-click
  - UsageView panel compacto con fetch /usage y barra de progreso
  - ContentView navegacion state-driven selectedSong: nil=biblioteca, non-nil=reproductor
  - PlayerView placeholder (reemplazado en planes 04-05)
  - CacheManagerKey EnvironmentKey para pasar CacheManager via entorno SwiftUI

affects:
  - 07-04-player-view
  - 07-05-waveform

tech-stack:
  added: []
  patterns:
    - PlayerViewModel patron cerebro del reproductor — carga y expone estado derivado de PlaybackEngine
    - O(1) lookup secuencial para currentLine y currentChord mediante indices lastLineIndex/lastChordIndex
    - EnvironmentKey para actores Swift no-Observable (CacheManager)
    - Table SwiftUI con contextMenu(forSelectionType:) + primaryAction para double-click

key-files:
  created:
    - StrataClient/Player/PlayerViewModel.swift
    - StrataClient/Player/PlayerView.swift
    - StrataClient/Library/LibraryView.swift
    - StrataClient/Library/UsageView.swift
  modified:
    - StrataClient/ContentView.swift
    - StrataClient/App/StrataApp.swift
    - StrataClient/Player/Chords/ChordModels.swift

key-decisions:
  - "ChordEntry.end cambiado a var (era let) para poder cerrar el ultimo acorde con engine.duration sin recrear el struct"
  - "ChordEntry con init() directo ademas del init(from:) Decodable — permite construir instancias fuera del decoder"
  - "CacheManagerKey EnvironmentKey para CacheManager (actor no-Observable) — patron limpio sin @unchecked Sendable"
  - "librarySection como @ViewBuilder computed var en LibraryView — evita Type constraint en Group con if/else"

patterns-established:
  - "PlayerViewModel como capa de indirección entre PlaybackEngine (tiempo) y vistas (linea/acorde actual)"
  - "EnvironmentKey pattern para tipos no-Observable que necesitan inyeccion via environment"

requirements-completed:
  - DISP-04
  - USGR-01
  - USGR-02

duration: 3min
completed: 2026-03-05
---

# Phase 7 Plan 03: Player ViewModel + Library Table + Usage Panel Summary

**PlayerViewModel @Observable que sincroniza PlaybackEngine.currentTime con letras/acordes, LibraryView con SwiftUI Table de 4 columnas y double-click, UsageView con fetch del servidor y ContentView con navegacion state-driven**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-04T23:27:14Z
- **Completed:** 2026-03-04T23:29:22Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- PlayerViewModel carga lyrics.json, chords.json y stems desde CacheManager, expone currentLine/currentWord/currentChord/nextChord con O(1) lookup secuencial para tiempo de reproduccion
- LibraryView reemplaza la lista simple con SwiftUI Table (4 columnas), seleccion multiple, delete via contextMenu y double-click para abrir reproductor
- UsageView fetch /usage y muestra "N canciones este mes · ~€X.XX" con ProgressView con tint naranja si supera 80% del limite
- ContentView reescrita con selectedSong state-driven (nil = biblioteca, non-nil = reproductor)
- CacheManager pasado via EnvironmentKey al no ser @Observable

## Task Commits

1. **Task 1: PlayerViewModel** - `c8ec90a` (feat)
2. **Task 2: LibraryView + UsageView + ContentView + StrataApp** - `c241c82` (feat)

## Files Created/Modified

- `StrataClient/Player/PlayerViewModel.swift` - @Observable ViewModel del reproductor con load(), estado derivado de engine.currentTime
- `StrataClient/Player/PlayerView.swift` - Placeholder temporal hasta planes 04-05
- `StrataClient/Library/LibraryView.swift` - Table con 4 columnas, seleccion multiple, double-click, ImportView + UsageView embebidos
- `StrataClient/Library/UsageView.swift` - Panel compacto con fetch /usage y ProgressView
- `StrataClient/ContentView.swift` - Navegacion state-driven biblioteca/reproductor
- `StrataClient/App/StrataApp.swift` - CacheManagerKey EnvironmentKey + cacheManager como @State
- `StrataClient/Player/Chords/ChordModels.swift` - ChordEntry.end cambiado a var, init() directo añadido

## Decisions Made

- ChordEntry.end cambiado de `let` a `var` para permitir `chords[last].end = engine.duration` sin recrear el struct
- CacheManagerKey EnvironmentKey para pasar el actor CacheManager via environment sin hacks de Sendable
- `@ViewBuilder private var librarySection` para el if/else entre tabla vacía y Table — evita restricciones de tipo en Group

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ChordEntry.end era let, necesitaba var para mutacion directa**
- **Found during:** Task 1 (PlayerViewModel.load())
- **Issue:** El plan indica `chords[chords.count - 1].end = engine.duration` pero `end` era `let`
- **Fix:** Cambiado a `var` y añadido `init()` directo en ChordEntry para compatibilidad
- **Files modified:** StrataClient/Player/Chords/ChordModels.swift
- **Verification:** Build exitosa, mutacion directa funciona
- **Committed in:** c8ec90a (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug en ChordModels.swift)
**Impact on plan:** Corrección necesaria para poder cerrar el ultimo acorde con la duracion del audio.

## Issues Encountered

Ninguno fuera de la desviacion documentada arriba.

## Next Phase Readiness

- PlayerViewModel listo para conectar con PlayerView (plan 04)
- LibraryView funcionando con tabla, seleccion y navegacion
- UsageView mostrando consumo mensual en tiempo real
- CacheManager disponible via environment para PlayerViewModel en plan 04

---
*Phase: 07-player-ui-display-usage*
*Completed: 2026-03-05*
