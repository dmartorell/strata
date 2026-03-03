---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-03-03T21:23:52.045Z"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 12
  completed_plans: 12
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-02)

**Core value:** Importar una cancion (archivo o YouTube) → esperar ~1 minuto → reproduccion interactiva con stems separados, letras y acordes
**Current focus:** Phase 3 — Swift Client + Auth

## Current Position

Phase: 3 of 7 (Swift Client + Auth)
Plan: 2 of 3 in current phase (03-02 COMPLETE — KeychainService + POST /auth/renew)
Status: Phase 03 en curso — plan 03-02 completo (KeychainService upsert, /auth/renew stateless, 5+8 tests)
Last activity: 2026-03-03 — Plan 03-02 completo (KeychainService Security.framework + endpoint /auth/renew FastAPI)

Progress: [████░░░░░░] 25%

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

### Pending Todos

None yet.

### Blockers/Concerns

- **Plan 01-03 checkpoint:** CREMA 0.2.0 + Python 3.11 compatibilidad se verifica durante el deploy — si falla la build, escalar (no eliminar CREMA silenciosamente)
- **Plan 01-03 checkpoint:** Cold start medido empiricamente tras deploy — gate bloqueante: debe ser <15s
- **Fase 6:** yt-dlp en IPs de datacenter de Modal tiene tasa de exito 20-40% — probar empiricamente con URLs reales; cookies via Modal Secret son obligatorias

## Session Continuity

Last session: 2026-03-03
Stopped at: Completed 03-02-PLAN.md — KeychainService + POST /auth/renew (commits 6918124, dcb49ef, 11315ee, 1a3dde5)
Resume file: None
