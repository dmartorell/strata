---
phase: quick-21
plan: 01
subsystem: swift-client
tags: [drag-and-drop, import, ui, swiftui]
key-files:
  created:
    - SiyahambaClient/App/GlobalDropOverlay.swift
  modified:
    - SiyahambaClient/ContentView.swift
    - SiyahambaClient/Import/ImportView.swift
decisions:
  - GlobalDropOverlay usa allowsHitTesting(false) para no interceptar clicks
  - Sheet de MetadataConfirmationSheet movido a ContentView para funcionar desde cualquier pantalla
  - Drop zone local en ImportView se mantiene como indicador visual
metrics:
  duration: ~10 min
  completed: 2026-03-25
  tasks: 1
  files: 4
---

# Quick Task 21: Global drag-and-drop con marco verde en toda la ventana

**One-liner:** Drop global de audio en ContentView con overlay verde (GlobalDropOverlay) y MetadataConfirmationSheet a nivel app — funciona desde Library y Player sin navegación forzada.

## What Was Built

- **GlobalDropOverlay.swift**: Vista que muestra un borde verde (3pt, `Color.green`) con fill semitransparente (0.05 opacity) alrededor de toda la ventana cuando `isTargeted` es true. Incluye icono y texto "Suelta para importar". Usa `.allowsHitTesting(false)` para no interceptar interacciones.

- **ContentView.swift**: Refactorizado con `ZStack` que incluye el overlay global. Añadido `@State private var isDragTargeted` y `.onDrop(of: [UTType.audio])` a nivel raíz, con la misma lógica de copia a temp que usaba ImportView. El `.sheet(isPresented:)` de MetadataConfirmationSheet se ha movido aquí desde ImportView.

- **ImportView.swift**: Eliminado el `.sheet` de MetadataConfirmationSheet. El drop zone local sigue operativo como indicador visual y sigue llamando `collectPendingFiles`, por lo que el sheet de ContentView lo captura automáticamente.

## Flujo resultante

1. Arrastrar audio sobre cualquier pantalla (Library o Player) → marco verde aparece en toda la ventana
2. Soltar → archivos copiados a temp → `collectPendingFiles` → `pendingItems` se llena → sheet aparece desde ContentView
3. Clicar "Procesar" → `confirmImport()` + `dismiss()` → usuario permanece en la misma pantalla (sin cambio de `selectedSong`)

## Deviations from Plan

None - plan ejecutado exactamente como estaba escrito.

## Self-Check

- [x] `SiyahambaClient/App/GlobalDropOverlay.swift` — CREADO
- [x] `SiyahambaClient/ContentView.swift` — MODIFICADO
- [x] `SiyahambaClient/Import/ImportView.swift` — MODIFICADO
- [x] Commit `1445e99` — EXISTE
- [x] Build `** BUILD SUCCEEDED **` — PASADO

## Self-Check: PASSED
