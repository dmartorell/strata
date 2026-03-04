---
phase: 07-player-ui-display-usage
plan: 02
subsystem: api
tags: [spending-limit, 429, rate-limiting, fastapi, swift, modal]

requires:
  - phase: 01-backend-foundation
    provides: usage tracker con record_usage y get_usage
  - phase: 07-player-ui-display-usage
    provides: plan 01 (tracker existente con SPENDING_LIMIT_USD)

provides:
  - check_limit(username) en server/usage/tracker.py — devuelve True si gasto mensual >= $10
  - 429 en /process-file y /process-url cuando se supera el límite
  - Captura de 429 en ImportViewModel con mensaje informativo en español

affects:
  - 07-player-ui-display-usage (planes posteriores pueden asumir que el límite se enforcea)

tech-stack:
  added: []
  patterns:
    - "check-before-spawn: límite de gasto verificado en HTTP handler antes de spawnar GPU"
    - "specific-catch-before-generic: catch APIError where == .httpError(429) antes del catch genérico en Swift"

key-files:
  created: []
  modified:
    - server/usage/tracker.py
    - server/processors/stub_processor.py
    - StrataClient/Import/ImportViewModel.swift

key-decisions:
  - "check_limit lee usage.json directamente via _read_usage() — sin dependencia de estado en memoria"
  - "429 devuelto con JSONResponse (no HTTPException) para mantener el content-type JSON correcto"
  - "catch APIError.httpError(429) en lugar de APIError.rateLimited — wave 1 paralelo, no asumir que plan 01 añadió rateLimited"

patterns-established:
  - "Enforcement de límite en HTTP handler, no en GPU: el check ocurre en stub_processor.py antes del spawn"

requirements-completed: [USGR-03, USGR-04]

duration: 15min
completed: 2026-03-05
---

# Phase 7 Plan 02: Spending Limit Summary

**Límite mensual de $10 USD en servidor (429 antes de spawn GPU) + mensaje informativo al usuario en cliente Swift**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-05T00:00:00Z
- **Completed:** 2026-03-05T00:15:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `check_limit(username)` añadida a tracker.py: lee usage.json y compara coste estimado del mes contra SPENDING_LIMIT_USD ($10)
- Endpoints `/process-file` y `/process-url` devuelven HTTP 429 antes de spawnar GPU cuando se supera el límite
- ImportViewModel captura `APIError.httpError(429)` en runFileImport y runURLImport con mensaje en español: "Limite mensual de procesamiento alcanzado. Puedes seguir reproduciendo canciones ya procesadas."

## Task Commits

1. **Task 1: Server — check_limit() + 429 en endpoints de proceso** - `927da52` (feat)
2. **Task 2: Cliente — capturar 429 en ImportViewModel** - `f5cf12c` (feat)

## Files Created/Modified

- `server/usage/tracker.py` - Añade check_limit(username) que retorna bool
- `server/processors/stub_processor.py` - Añade check de límite al inicio de process_file y process_url
- `StrataClient/Import/ImportViewModel.swift` - Añade catch específico para httpError(429) en runFileImport y runURLImport

## Decisions Made

- `check_limit` lee usage.json directamente via `_read_usage()` sin estado en memoria — consistente con el patrón existente en el módulo
- 429 devuelto con `JSONResponse` (no `HTTPException`) para mantener el content-type JSON correcto y el body `{"detail": "Monthly spending limit reached"}`
- En Swift se usa `APIError.httpError(429)` directamente en lugar de un hipotético `APIError.rateLimited` porque este plan ejecuta en wave 1 paralelo con plan 01 — sin asumir cambios de plan 01

## Deviations from Plan

None — plan ejecutado exactamente como estaba especificado.

## Issues Encountered

El tool `Edit` falló repetidamente porque un proceso externo (Xcode o un linter) modificaba `ImportViewModel.swift` entre la lectura y la escritura. Se resolvió usando Python directamente para aplicar los patches de forma atómica.

## Next Phase Readiness

- El enforcement de gasto está activo en servidor y cliente
- Planes 07-03+ pueden asumir que nuevos procesamientos se bloquean al alcanzar $10/mes
- Canciones ya procesadas y en caché siguen siendo reproducibles sin restricción

---
*Phase: 07-player-ui-display-usage*
*Completed: 2026-03-05*
