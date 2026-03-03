---
phase: 04-library-cache
plan: 02
subsystem: Library Cache
tags: [swift, cachemanager, librarystore, sha256, youtube, cryptokit]
dependency_graph:
  requires: [04-01]
  provides: [04-03]
  affects: [StrataApp, CacheManager, LibraryStore]
tech_stack:
  added: [CryptoKit]
  patterns: [incremental-hashing, actor-extensions, swiftui-environment]
key_files:
  modified:
    - StrataClient/Library/CacheManager.swift
    - StrataClient/App/StrataApp.swift
decisions:
  - "try! en init() de CacheManager en StrataApp: si ~/Music no es accesible la app no puede funcionar — error fatal aceptable"
  - "Group {} en WindowGroup body: aplica .environment(authViewModel) una sola vez en lugar de duplicarlo en cada rama"
  - ".task en WindowGroup body: loadFromDisk() se ejecuta async sin bloquear el hilo principal desde el arranque"
metrics:
  duration: ~1 min
  completed: "2026-03-03"
  tasks: 2
  files: 2
---

# Phase 04 Plan 02: CacheManager Extensions + StrataApp Wiring Summary

SHA256 incremental via CryptoKit + YouTube video ID extractor + materializeSong en CacheManager; LibraryStore cabeable en StrataApp con carga automatica desde disco al arranque.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extender CacheManager con hashing y materializacion | 35b4929 | StrataClient/Library/CacheManager.swift |
| 2 | Cablear LibraryStore en StrataApp.swift | 5d4ec3b | StrataClient/App/StrataApp.swift |

## What Was Built

**CacheManager.swift** — Tres nuevas extensiones sobre el actor existente:
- `sha256(of:)`: Usa `CryptoKit.SHA256` con `FileHandle` leyendo en chunks de 64 KB para no cargar archivos enteros en memoria
- `youtubeVideoID(from:)`: Extrae el video ID de `youtube.com/watch?v=ID` (via query items) y de `youtu.be/ID` (via path)
- `materializeSong(id:from:)`: Mueve los 7 ficheros del tempDir (`vocals.wav`, `drums.wav`, `bass.wav`, `other.wav`, `lyrics.json`, `chords.json`, `metadata.json`) al directorio permanente `~/Music/Strata/{uuid}/` y elimina el tempDir

`CacheManagerProtocol` actualizado con las 3 nuevas firmas para que mocks de test puedan implementarlas.

**StrataApp.swift** — Inicializacion de `LibraryStore` en `init()` con `try! CacheManager()`, inyeccion via `.environment(libraryStore)` en `ContentView`, y carga automatica con `.task { await libraryStore.loadFromDisk() }` al arrancar la escena raiz.

## Deviations from Plan

None — plan ejecutado exactamente como estaba escrito.

## Self-Check: PASSED

- StrataClient/Library/CacheManager.swift — FOUND
- StrataClient/App/StrataApp.swift — FOUND
- Commit 35b4929 (Task 1) — FOUND
- Commit 5d4ec3b (Task 2) — FOUND
