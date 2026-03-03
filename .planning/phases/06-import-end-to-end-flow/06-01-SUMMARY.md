---
phase: 06-import-end-to-end-flow
plan: 01
subsystem: api
tags: [swift, apiClient, zipfoundation, import, observable, concurrency]

requires:
  - phase: 04-library-cache
    provides: CacheManager actor con sha256, youtubeVideoID, materializeSong
  - phase: 03-swift-client-auth
    provides: APIClient con HTTPTransport, AuthViewModel con token

provides:
  - APIEndpoint con .processFile (/process-file) y .processURL (/process-url)
  - APIClient.uploadURL para POST /process-url con JSON body
  - APIClient.pollJobStatus con ZIP detection (Content-Type: application/zip)
  - JobResult struct Sendable con zipData y status
  - ImportPhase enum con display labels en español
  - ImportViewModel @Observable @MainActor con flujo completo hash→cache→upload→poll→unzip→materializeSong→addSong

affects: [06-import-end-to-end-flow/06-02, 06-import-end-to-end-flow/06-03]

tech-stack:
  added: [ZIPFoundation 0.9.20 via SPM]
  patterns: [extractToTemp nonisolated + await cacheManager.materializeSong en actor hop, ZIP detection antes de JSON decode en pollJobStatus]

key-files:
  created:
    - StrataClient/Import/ImportPhase.swift
    - StrataClient/Import/ImportViewModel.swift
  modified:
    - StrataClient/Network/APIClient.swift
    - StrataClient/Network/APIEndpoint.swift
    - project.yml

key-decisions:
  - "extractToTemp como función nonisolated libre para Task.detached; materializeSong llamado con await desde @MainActor context tras el detached — respeta actor isolation sin hop explícito"
  - "JobResult redefinido como Sendable struct (no Decodable): zipData se construye desde raw Data del response, no desde JSON — eliminado campo obsoleto result en JobStatusResponse"
  - "ZIPFoundation 0.9.x vía project.yml/xcodegen en lugar de editar project.pbxproj a mano — consistente con patrón del proyecto"

patterns-established:
  - "ZIP polling: checkResponse → Content-Type detection → JSON decode (ese orden)"
  - "ImportViewModel: cancel con Task.checkCancellation() en cada paso del flujo"

requirements-completed: [IMPT-01, IMPT-02, IMPT-03, IMPT-04]

duration: 2min
completed: 2026-03-03
---

# Phase 06 Plan 01: Network Layer + ImportViewModel Summary

**APIClient corregido a /process-file y /process-url con ZIP detection; ImportViewModel @Observable que orquesta el flujo completo de importación usando ZIPFoundation**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-03T22:41:34Z
- **Completed:** 2026-03-03T22:43:56Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- APIEndpoint refactorizado: `.process` → `.processFile` (/process-file POST), añadido `.processURL` (/process-url POST)
- JobResult rediseñado como Sendable struct con `zipData: Data?` y `status: String`; `pollJobStatus` detecta `Content-Type: application/zip` antes del JSON decode
- `APIClient.uploadURL` implementado para envío de URLs de YouTube
- `ImportPhase` enum con estados idle/validating/uploading/processing/ready/error y display labels en español
- `ImportViewModel` implementa flujo completo con manejo correcto de actor isolation: `extractToTemp` nonisolated en `Task.detached`, seguido de `await cacheManager.materializeSong` en contexto @MainActor

## Task Commits

1. **Task 1: Fix APIClient + APIEndpoint para endpoints reales** - `2569503` (feat)
2. **Task 2: ImportPhase enum + ImportViewModel con flujo completo** - `4378fe2` (feat)

## Files Created/Modified

- `StrataClient/Network/APIEndpoint.swift` - Casos .processFile y .processURL con paths correctos
- `StrataClient/Network/APIClient.swift` - JobResult Sendable, uploadURL, pollJobStatus con ZIP detection
- `StrataClient/Import/ImportPhase.swift` - Enum de estado con displayLabel en español e isActive
- `StrataClient/Import/ImportViewModel.swift` - ViewModel @Observable @MainActor con flujo completo + ImportError
- `project.yml` - ZIPFoundation 0.9.x añadido a packages y dependencias de StrataClient target

## Decisions Made

- `extractToTemp` como función libre nonisolated para `Task.detached`; `materializeSong` llamado con `await` después del detached en contexto @MainActor — respeta actor isolation de CacheManager sin actor hop explícito
- `JobResult` redefinido como `Sendable` struct no-Decodable: el ZIP llega como `Data` raw del response, construido manualmente en `pollJobStatus`; `JobStatusResponse.result` eliminado por obsoleto
- ZIPFoundation añadido vía `project.yml` + `xcodegen generate` — sin edición manual de `project.pbxproj`

## Deviations from Plan

None - plan ejecutado exactamente como especificado.

## Issues Encountered

Build requirió `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` en `xcodebuild` por ausencia de Development Team — comportamiento esperado en este entorno de desarrollo, no un error.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Capa de red lista para el flujo real contra el servidor Modal
- `ImportViewModel` listo para ser wired en `ImportView` (plan 06-02)
- ZIPFoundation disponible en el target; `extractToTemp` + actor hop verificados en compilación
