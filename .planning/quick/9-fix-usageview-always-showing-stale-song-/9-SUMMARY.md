---
phase: quick-9
plan: 1
subsystem: server/usage + StrataClient/Library
tags: [bugfix, modal-volume, swiftui, usage-tracking]
dependency_graph:
  requires: []
  provides: [usage-data-fresh, usage-view-auto-refresh]
  affects: [server/usage/tracker.py, StrataClient/Library/UsageView.swift]
tech_stack:
  added: []
  patterns: [modal-volume-shared-instance, swiftui-task-id-refresh]
key_files:
  modified:
    - server/usage/tracker.py
    - StrataClient/Library/UsageView.swift
decisions:
  - "usage_vol importado desde app.py en tracker.py: garantiza que commit() y reload() usan la misma instancia montada en /data"
  - "task(id: refreshID) + onAppear: patron SwiftUI para re-ejecutar async task al reaparecer sin race condition"
metrics:
  duration: ~5 min
  completed: 2026-03-21
---

# Quick Task 9: Fix UsageView Always Showing Stale Song Count Summary

**One-liner:** Corrige datos stale en GET /usage eliminando instancia duplicada de Modal Volume en tracker.py, y fuerza re-fetch en UsageView con `.task(id: refreshID)` al reaparecer.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Fix server — importar usage_vol desde app.py | c444445 | server/usage/tracker.py |
| 2 | Fix cliente — refrescar UsageView al reaparecer | 639fd63 | StrataClient/Library/UsageView.swift |

## What Was Built

**Task 1 — server/usage/tracker.py**

tracker.py declaraba su propia instancia `usage_vol = modal.Volume.from_name("strata-usage")` (línea 36). Esta instancia era un objeto Python diferente al `usage_vol` de app.py que es el que se monta como filesystem en `/data` vía `volumes={"/data": usage_vol}`. El `reload()` en `usage_endpoint` operaba sobre la instancia local — no la montada — por lo que nunca veía los cambios escritos por el GPU container.

Fix: eliminar la declaración local y reemplazarla con `from app import usage_vol`. Ahora `commit()` en `_write_usage` y `reload()` en `usage_endpoint` operan en la misma referencia de Volume.

**Task 2 — StrataClient/Library/UsageView.swift**

UsageView usaba `.task { await fetchUsage() }` que sólo ejecuta una vez al crear la vista. Como UsageView vive siempre en LibraryView (parte inferior), el `.task` no volvía a ejecutar al navegar de vuelta desde PlayerView.

Fix:
- `@State private var refreshID = UUID()` como trigger
- `.task(id: refreshID)` re-ejecuta el fetch cada vez que cambia el ID
- `.onAppear { refreshID = UUID() }` genera nuevo ID al reaparecer
- `fetchUsage()` resetea `usage = nil` y `loadError = false` al inicio para mostrar spinner durante el re-fetch

## Deviations from Plan

None — plan ejecutado exactamente como estaba escrito.

## Self-Check: PASSED

- server/usage/tracker.py: modificado, import from app verificado con AST
- StrataClient/Library/UsageView.swift: modificado, refreshID + task(id:) + onAppear verificados con grep
- Commits: c444445, 639fd63 presentes en git log
