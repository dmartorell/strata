---
phase: 05-multi-stem-playback
plan: 01
subsystem: audio
tags: [avfaudio, avaudioengine, avaudioplayernode, avaudiounittimepitch, observable, mainactor]

requires:
  - phase: 04-library-cache
    provides: CacheManager.stemURL(songID:stem:) — URL de cada stem WAV en disco

provides:
  - PlaybackEngine (@Observable @MainActor) con grafo AVAudioEngine de 4 stems sincronizados
  - API publica: load(stemURLs:), play(), pause(), stop(), seek(to:)
  - currentTime actualizado a ~60fps via Timer; duration derivada del stem mas largo
  - Propiedades observables: currentTime, duration, isPlaying, pitchSemitones, loopStart, loopEnd

affects:
  - 05-02 (pitch shift: implementar setter de pitchSemitones sobre timePitchNode)
  - 05-03 (loop AB: implementar logica de loopStart/loopEnd)
  - 07 (player UI: consumir currentTime, duration, isPlaying desde PlaybackEngine)

tech-stack:
  added:
    - AVFAudio (sistema, sin dependencias nuevas de SPM)
  patterns:
    - "@Observable @MainActor para motor de audio — mismo patron que AuthViewModel"
    - "play(at: sharedAVAudioTime) con +0.1s delay para arranque sincronizado frame-accurate"
    - "seekOffset + playerTime(forNodeTime:) para currentTime robusto tras pause/seek"
    - "Timer a 60fps en main thread via Task @MainActor desde closure"

key-files:
  created:
    - StrataClient/Audio/PlaybackEngine.swift
  modified:
    - StrataClient.xcodeproj/project.pbxproj (regenerado con xcodegen)

key-decisions:
  - "Timer (Foundation) sobre CADisplayLink: mas simple, cumple requisito de ~60fps, evita dependencia de CoreVideo en target macOS"
  - "deinit incompatible con @MainActor en Swift 5.9 — documentado en clase; cleanup via stop() explicito"
  - "xcodegen generate para incorporar nuevo directorio Audio/ al proyecto sin editar pbxproj manualmente"

patterns-established:
  - "Audio graph: players[i] → stemMixers[i] → preMixNode → timePitchNode → mainMixerNode"
  - "scheduleAndPlay() centraliza stop+scheduleSegment+play(at:) para reutilizacion en play() y seek()"
  - "handlePlaybackCompletion() con guard isPlaying: solo el primer stem que termina dispara el estado"

requirements-completed: [PLAY-01, PLAY-04]

duration: 1min
completed: 2026-03-03
---

# Phase 5 Plan 01: PlaybackEngine Summary

**Motor AVAudioEngine con 4 AVAudioPlayerNode sincronizados via shared AVAudioTime, play/pause/seek/stop, y currentTime a 60fps mediante Timer + seekOffset**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-03T22:21:53Z
- **Completed:** 2026-03-03T22:23:03Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- PlaybackEngine creado como @Observable @MainActor con grafo AVAudioEngine completo
- Sincronizacion frame-accurate: todos los stems arrancan con el mismo AVAudioTime (+0.1s)
- currentTime actualizado a ~60fps conservando seekOffset correcto tras pause y seek
- BUILD SUCCEEDED en primera compilacion

## Task Commits

1. **Task 1: PlaybackEngine — grafo AVAudioEngine + load + play/pause** - `0356c9c` (feat)

## Files Created/Modified

- `StrataClient/Audio/PlaybackEngine.swift` - Motor de audio central (@Observable @MainActor), grafo de 4 stems, play/pause/seek/stop/load, currentTime a 60fps
- `StrataClient.xcodeproj/project.pbxproj` - Regenerado con xcodegen para incluir Audio/

## Decisions Made

- Foundation.Timer en lugar de CADisplayLink: mas simple para macOS, cumple el requisito de ~60fps sin dependencia adicional de CoreVideo
- deinit no disponible con @MainActor en Swift 5.9 — documentado con comentario en la clase; caller debe invocar stop() antes de soltar la referencia
- xcodegen generate para incorporar el nuevo directorio Audio/ al proyecto Xcode

## Deviations from Plan

None - plan ejecutado exactamente como estaba escrito.

## Issues Encountered

El primer intento de build falló con error de firma de equipo (no de compilacion Swift). Resuelto pasando `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` a xcodebuild, igual que en fases anteriores.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- PlaybackEngine listo para Plan 02 (pitch shift: setter de pitchSemitones → timePitchNode.pitch)
- Plan 03 (loop AB) puede implementar la logica de loopStart/loopEnd sobre la base existente
- Phase 7 puede consumir currentTime, duration, isPlaying directamente desde @Observable

---
*Phase: 05-multi-stem-playback*
*Completed: 2026-03-03*
