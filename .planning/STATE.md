---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-03-04T23:36:02.899Z"
progress:
  total_phases: 7
  completed_phases: 6
  total_plans: 25
  completed_plans: 24
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-02)

**Core value:** Importar una cancion (archivo o YouTube) → esperar ~1 minuto → reproduccion interactiva con stems separados, letras y acordes
**Current focus:** Phase 3 — Swift Client + Auth

## Current Position

Phase: 7 of 7 (Player UI Display Usage) — COMPLETE
Plan: 5 of 5 (07-05 COMPLETE — LyricsView karaoke + ChordView + PlayerView integración zona principal)
Status: Phase 07 COMPLETE — reproductor completo con letras karaoke, acordes en tiempo real, waveforms, stems M/S/vol, pitch, transport. UsageView con spinner+texto en biblioteca.
Last activity: 2026-03-06 - Completed quick task 7: Cambio de look pantalla de letras

Progress: [██████████] 100% (v1.0 milestone complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01-backend-foundation P01 | ~12 min | 3 tasks | 5 files |
| Phase 01-backend-foundation P02 | ~8 min | 2 tasks | 6 files |
| Phase 02-gpu-pipeline P02 | ~12 min | 3 tasks | 3 files |
| Phase 02-gpu-pipeline P01 | 3 | 3 tasks | 5 files |
| Phase 02-gpu-pipeline P03 | 3 | 3 tasks | 5 files |
| Phase 02-gpu-pipeline P04 | 5 | 3 tasks | 8 files |
| Phase 02-gpu-pipeline P05 | 3 | 3 tasks | 4 files |
| Phase 02-gpu-pipeline P06 | 25 | 3 tasks | 3 files |
| Phase 03-swift-client-auth P01 | 70 | 2 tasks | 15 files |
| Phase 03-swift-client-auth P02 | 16 | 2 tasks | 6 files |
| Phase 03-swift-client-auth P03 | 65 | 2 tasks | 5 files |
| Phase 03-swift-client-auth P03 | 75 | 3 tasks | 5 files |
| Phase 04-library-cache P01 | 10 | 3 tasks | 4 files |
| Phase 04-library-cache P02 | 1 | 2 tasks | 2 files |
| Phase 05-multi-stem-playback P01 | 1 | 1 task | 2 files |
| Phase 05-multi-stem-playback P02 | 5 | 1 tasks | 1 files |
| Phase 05-multi-stem-playback P03 | 2 | 2 tasks | 2 files |
| Phase 06-import-end-to-end-flow P01 | 2 | 2 tasks | 5 files |
| Phase 06-import-end-to-end-flow P02 | 20 | 3 tasks | 4 files |
| Phase 06-import-end-to-end-flow P03 | 15 | 2 tasks | 5 files |
| Phase 07-player-ui-display-usage P01 | 15 | 2 tasks | 8 files |
| Phase 07-player-ui-display-usage P02 | 15 | 2 tasks | 3 files |
| Phase 07-player-ui-display-usage P03 | 3 | 2 tasks | 7 files |
| Phase 07-player-ui-display-usage P04 | 2 | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Backend antes que cliente — todo el codigo Swift se testa contra endpoints HTTPS reales desde el primer dia
- Roadmap: GPU pipeline en Fase 2 — el mayor riesgo tecnico (CREMA Python 3.11, cold-start) se valida antes de construir UI
- Roadmap: Cache schema bloqueado en Fase 4 antes de persistir datos reales — evita migraciones disruptivas
- [Phase 01-backend-foundation]: Login sin username: bcrypt checkpw contra todos los usuarios, match inequivoco por unicidad de contrasenas
- [Phase 01-backend-foundation]: HTTPBearer(auto_error=False) para retornar 401 (no 403) en ausencia/invalidez de token JWT
- [Phase 01-backend-foundation P02]: stub_builder.py separado de stub_processor.py: modulo stdlib puro importable desde GPU sin FastAPI ni auth
- [Phase 01-backend-foundation P02]: Volume montado en web handler Y en process_job para que GET /usage lea datos persistidos
- [Phase 02-gpu-pipeline P02]: whisperx.load_model en lugar de faster_whisper.WhisperModel — API alto nivel con align incluido
- [Phase 02-gpu-pipeline P02]: compute_type='int8' en build time (CPU), 'float16' en runtime (CUDA) — minimiza VRAM durante build
- [Phase 02-gpu-pipeline P02]: del model_a + gc.collect + empty_cache obligatorio tras whisperx.align — wav2vec2 ocupa ~300MB VRAM
- [Phase 02-gpu-pipeline]: htdemucs (no htdemucs_ft): 4x mas rapido, cabe en budget 60s
- [Phase 02-gpu-pipeline]: gpu_image separada de imagen web: pipeline GPU sin FastAPI/auth, imagen web sin ML
- [Phase 02-gpu-pipeline]: separate_stems recibe separator como parametro: desacopla logica de Demucs del lifecycle Modal
- [Phase 02-gpu-pipeline]: chord-extractor (Chordino/VAMP) sobre stem 'other' con fallback a [] si falla — resultado parcial aceptable
- [Phase 02-gpu-pipeline]: end=None para el ultimo acorde en chords.json; Phase 7 cierra con audio duration
- [Phase 02-gpu-pipeline]: modal.current_function_call_id() para job_id en AudioPipeline.process(): disponible desde el contexto Modal sin parametro
- [Phase 02-gpu-pipeline]: timeout=600 en AudioPipeline: pipeline Demucs+WhisperX+chords puede tardar hasta 5 min
- [Phase 02-gpu-pipeline]: process_youtube() llama self.process() directamente (no spawn) para mantener coherencia del job_id
- [Phase 02-gpu-pipeline]: Skip automatico tests integration si sin token Modal — pytest_collection_modifyitems sin pytest.ini extra
- [Phase 02-gpu-pipeline]: test_cold_start_measurement sin assert de tiempo — informativo para decidir si activar GPU memory snapshots
- [Phase 02-gpu-pipeline P06]: validate_audio() queda fuera del try/except en process() — su ValueError va al HTTP handler como 400, no como error de pipeline
- [Phase 02-gpu-pipeline P06]: process_youtube() añade modal.current_function_call_id() y modal.Dict propios — método Modal separado de process()
- [Phase 02-gpu-pipeline P06]: status.startswith('error:') como patrón de error en GET /result/{job_id} → HTTP 500 con mensaje del pipeline
- [Phase 03-swift-client-auth]: HTTPTransport protocol en lugar de URLProtocol mock: evita bugs de concurrencia con Swift Testing
- [Phase 03-swift-client-auth]: project.yml con xcodegen: proyecto Xcode reproducible y versionable en git
- [Phase 03-swift-client-auth]: kSecAttrAccessible configurable via init: produccion usa AfterFirstUnlockThisDeviceOnly, tests usan Always para compat con firma ad-hoc
- [Phase 03-swift-client-auth]: Upsert Keychain: Add-first + Update-if-duplicate (vs Update-first del plan) — mas robusto con firma ad-hoc
- [Phase 03-swift-client-auth]: require_auth reutilizado en /auth/renew sin cambios — sin duplicacion de logica de validacion JWT
- [Phase 03-swift-client-auth]: KeychainServiceProtocol + APIClientProtocol en AuthViewModel: protocolos mínimos para inyección de dependencias en tests sin afectar tipos concretos
- [Phase 03-swift-client-auth]: @Observable @MainActor AuthViewModel: patrón macOS 14 para ViewModels — sin ObservableObject/StateObject
- [Phase 03-swift-client-auth]: checkStoredToken síncrono en init: sesión restaurada del Keychain antes del primer render — sin flash de LoginView
- [Phase 03-swift-client-auth]: Ventana 900x600 por defecto con .windowResizability(.contentMinSize): tamano util para ContentView sin forzar redimension al usuario
- [Phase 04-library-cache]: CacheManager como actor Swift: aislamiento de concurrencia para todo I/O de filesystem en Library
- [Phase 04-library-cache]: Schema additive-only en SongEntry: campos nuevos como optional con nil por defecto — sin migraciones disruptivas
- [Phase 04-library-cache P02]: try! en CacheManager init() en StrataApp: si ~/Music no es accesible la app no puede funcionar — error fatal aceptable
- [Phase 04-library-cache P02]: Group {} en WindowGroup body: aplica .environment(authViewModel) una sola vez en lugar de duplicarlo en cada rama
- [Phase 05-multi-stem-playback P01]: Foundation.Timer sobre CADisplayLink para currentTime a 60fps: mas simple en macOS, evita dependencia de CoreVideo
- [Phase 05-multi-stem-playback P01]: deinit incompatible con @MainActor Swift 5.9 — documentado; cleanup via stop() explicito por el caller
- [Phase 05-multi-stem-playback P01]: xcodegen generate para incorporar Audio/ al proyecto — sin edicion manual de pbxproj
- [Phase 05-multi-stem-playback]: outputVolume = 0 para mute/solo en lugar de detach/reattach — evita clicks y pops en el audio
- [Phase 05-multi-stem-playback]: applyVolumes() como punto centralizado para stemMixers[i].outputVolume — toda mutacion de volumen pasa por un solo punto
- [Phase 05-multi-stem-playback]: completion handler .dataPlayedBack como re-schedule del loop A/B: sin timers, sin drift
- [Phase 05-multi-stem-playback]: handleConfigurationChange guarda wasPlaying/savedTime para restaurar reproduccion tras cambio de dispositivo
- [Phase 06-import-end-to-end-flow P01]: extractToTemp como función nonisolated libre para Task.detached; materializeSong llamado con await en @MainActor context tras el detached — respeta actor isolation de CacheManager
- [Phase 06-import-end-to-end-flow P01]: JobResult redefinido como Sendable struct no-Decodable: zipData construido desde raw Data del response; JobStatusResponse.result eliminado por obsoleto
- [Phase 06-import-end-to-end-flow P01]: ZIPFoundation añadido vía project.yml + xcodegen generate — sin edición manual de project.pbxproj
- [Phase 06-import-end-to-end-flow P02]: Botón "Pegar URL de YouTube" en toolbar de ContentView (no en ImportView) — mejor jerarquía visual
- [Phase 06-import-end-to-end-flow P02]: Copia de archivo a temporaryDirectory dentro del closure NSItemProvider — evita que el security-scoped bookmark caduque antes del Task @MainActor
- [Phase 06-import-end-to-end-flow P02]: isErrorOrReady como computed var en ImportView — progressSection visible en ready y error para que el usuario vea el resultado
- [Phase 06-import-end-to-end-flow P03]: ImportAPIClientProtocol separado de APIClientProtocol (auth): evita mezclar contratos de auth e import en el mismo protocolo
- [Phase 06-import-end-to-end-flow P03]: Protocol extension con pollJobStatus defaults: mantiene retrocompatibilidad en call sites existentes
- [Phase 06-import-end-to-end-flow P03]: AuthTokenProviderProtocol minimal (solo token): ImportViewModel no necesita login/logout
- [Phase 06-import-end-to-end-flow P03]: MockImportAPIClient como actor Swift: Sendable garantizado sin @unchecked
- [Phase 07-player-ui-display-usage]: check_limit lee usage.json directamente via _read_usage() — sin dependencia de estado en memoria
- [Phase 07-player-ui-display-usage]: 429 devuelto con JSONResponse (no HTTPException) para mantener content-type JSON correcto
- [Phase 07-player-ui-display-usage]: catch APIError.httpError(429) en wave 1 paralelo — sin asumir que plan 01 añadió APIError.rateLimited
- [Phase 07-player-ui-display-usage]: ChordEntry.end cambiado a var para mutacion directa en PlayerViewModel.load()
- [Phase 07-player-ui-display-usage]: CacheManagerKey EnvironmentKey para pasar actor CacheManager via SwiftUI environment sin hacks de Sendable
- [Phase 07-player-ui-display-usage]: ABLoopButton como struct privado con LoopPhase enum en PlayerView — encapsula lógica de 3 fases A/B sin contaminar PlayerView
- [Phase 07-player-ui-display-usage]: isSoloed inferido heurísticamente en StemControlsView — evita añadir API pública a PlaybackEngine para exponer soloedStem

### Pending Todos

None yet.

### Roadmap Evolution

- Phase 8 added: YouTube Download Client-Side — descarga local con yt-dlp y upload por /process-file (elimina dependencia de cookies en Modal)

### Blockers/Concerns

- **Plan 01-03 checkpoint:** CREMA 0.2.0 + Python 3.11 compatibilidad se verifica durante el deploy — si falla la build, escalar (no eliminar CREMA silenciosamente)
- **Plan 01-03 checkpoint:** Cold start medido empiricamente tras deploy — gate bloqueante: debe ser <15s
- **Fase 6:** yt-dlp en IPs de datacenter de Modal tiene tasa de exito 20-40% — RESUELTO en quick task 8 via Cobalt Tools API (sin cookies)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Usar nombre original de canción en vez de hash para archivos mp3 guardados | 2026-03-04 | 2ed8683 | [1-usar-nombre-original-de-canci-n-en-vez-d](./quick/1-usar-nombre-original-de-canci-n-en-vez-d/) |
| 2 | Implementa el pause/play pulsando barra espaciadora | 2026-03-05 | 5783189 | [2-implementa-el-pause-play-pulsando-barra-](./quick/2-implementa-el-pause-play-pulsando-barra-/) |
| 3 | Seek-on-tap en waveforms del player | 2026-03-05 | 86381f1 | [3-en-reproducci-n-cuando-clico-encima-de-a](./quick/3-en-reproducci-n-cuando-clico-encima-de-a/) |
| 4 | Mejora UI: progress bar centrado y controles centrados | 2026-03-05 | 422c650 | [4-mejora-de-ui-progress-bar-centrado-y-com](./quick/4-mejora-de-ui-progress-bar-centrado-y-com/) |
| 5 | Retoques UI: flechas seek ±10s, go-to-start, controles centrados, toggle visual M/S | 2026-03-05 | b90a36e | [5-retoques-ui-flechas-seek-controles-centr](./quick/5-retoques-ui-flechas-seek-controles-centr/) |
| 6 | A/B loop visual en waveform con Option+drag y bordes arrastrables | 2026-03-05 | 9b84ad1 | [6-implementar-a-b-loop-visual-en-waveform](./quick/6-implementar-a-b-loop-visual-en-waveform/) |
| 7 | Cambio de look pantalla de letras: background oscuro, fuente mayor, partir frases, color gris a blanco | 2026-03-06 | 4b10407 | [7-cambio-de-look-pantalla-de-letras-backgr](./quick/7-cambio-de-look-pantalla-de-letras-backgr/) |
| 8 | Reemplazar yt-dlp por Cobalt Tools API para descarga de YouTube | 2026-03-21 | 6d535ef | [8-replace-yt-dlp-with-cobalt-tools-api-for](./quick/8-replace-yt-dlp-with-cobalt-tools-api-for/) |
| 9 | Fix UsageView mostrando datos stale: instancia duplicada de Modal Volume en tracker.py + re-fetch al reaparecer en cliente | 2026-03-21 | 639fd63 | [9-fix-usageview-always-showing-stale-song-](./quick/9-fix-usageview-always-showing-stale-song-/) |

## Session Continuity

Last session: 2026-03-21
Stopped at: Completed quick task 9 — Fix UsageView datos stale (Modal Volume instancia compartida + task(id:) refresh)
Resume file: None

### Bugs Resueltos (2026-03-05)

| Bug | Root Cause | Fix | Debug File |
|-----|-----------|-----|------------|
| Espacio sin foco al abrir PlayerView | `.focusable()` no toma foco activo en macOS — el foco va al botón "Volver" | `@FocusState` + `.focused()` binding activado en `.onAppear` | resolved/player-focus-and-position.md |
| Pitch reset al reabrir canción | `engine.setPitch()` llamado antes de `engine.load()` + `scheduleAndPlay` usaba `outputNode.lastRenderTime` stale como base de tiempo | Mover `setPitch` post-`load`; usar `mach_absolute_time()` + ticks Mach en `AVAudioTime(hostTime:)` | resolved/player-focus-and-position.md |
| Seek ±10s errático durante playback | `completionCallbackType:.dataPlayedBack` dispara el callback del segmento anterior tras `players.stop()`, llamando `handlePlaybackCompletion()` que sobreescribe `currentTime` con `duration` | `playbackGeneration` counter: el completion handler solo actúa si la generación capturada coincide con la actual | resolved/seek-erratic-during-playback.md |
