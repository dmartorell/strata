---
phase: 04-library-cache
plan: 01
subsystem: library-cache
tags: [swift, codable, actor, observable, persistence, filesystem]
dependency_graph:
  requires: []
  provides: [SongEntry, SongMetadata, CacheManager, CacheManagerProtocol, LibraryStore]
  affects: [04-02, phase-06-download]
tech_stack:
  added: []
  patterns: [Swift actor for I/O isolation, @Observable @MainActor ViewModel, additive-only Codable schema]
key_files:
  created:
    - StrataClient/Library/SongEntry.swift
    - StrataClient/Library/SongMetadata.swift
    - StrataClient/Library/CacheManager.swift
    - StrataClient/Library/LibraryStore.swift
  modified: []
decisions:
  - "CacheManager como actor: aislamiento de concurrencia para todo I/O de filesystem"
  - "Schema additive-only en SongEntry: campos nuevos como optional con nil por defecto — sin migraciones"
  - "writeLibraryIndex con .atomic: evita corrupcion del indice en escrituras parciales"
  - "LibraryStore filtra huerfanas extrayendo rootURL antes del filter closure — compatibilidad con contexto sincrono"
metrics:
  duration: ~10 min
  completed_date: "2026-03-03"
  tasks_completed: 3
  files_created: 4
  files_modified: 1
---

# Phase 04 Plan 01: Library Cache Model + Persistence Layer Summary

**One-liner:** SongEntry/SongMetadata Codable types + CacheManager actor con escritura atomica + LibraryStore @Observable como fuente de verdad de la biblioteca local.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SongEntry + SongMetadata (tipos Codable) | 10e10d6 | SongEntry.swift, SongMetadata.swift |
| 2 | CacheManager (actor) — filesystem I/O | 572d5a8 | CacheManager.swift |
| 3 | LibraryStore (@MainActor @Observable) | 23ece9e | LibraryStore.swift |

## What Was Built

**SongEntry** (`StrataClient/Library/SongEntry.swift`): Struct Codable + Identifiable + Sendable. Fila de `library.json`. Schema additive-only: campos nuevos se declaran como optional con nil — JSONDecoder ignora claves desconocidas sin CodingKeys personalizados.

**SongMetadata** (`StrataClient/Library/SongMetadata.swift`): Struct Codable + Sendable. Metadata escrita una vez por cancion en `metadata.json` junto al directorio de la cancion. Usa String para `addedAt` (ISO8601 legible en disco).

**CacheManager** (`StrataClient/Library/CacheManager.swift`): Actor Swift con protocolo `CacheManagerProtocol` para inyeccion de dependencias. `init()` crea `~/Music/Strata/` con `createDirectory(withIntermediateDirectories:)`. `readLibraryIndex` usa `JSONDecoder.dateDecodingStrategy = .iso8601` y devuelve `[]` si `library.json` no existe. `writeLibraryIndex` usa `JSONEncoder` con `.iso8601 + .prettyPrinted + .sortedKeys` y escribe con `Data.write(options: .atomic)`. URL helpers para stems WAV, lyrics.json y chords.json.

**LibraryStore** (`StrataClient/Library/LibraryStore.swift`): `@Observable @MainActor final class`. Patron identico a `AuthViewModel`. `loadFromDisk()` lee el indice, extrae `rootURL` del actor antes del filtro (para compatibilidad con closure sincrono), descarta entradas huerfanas si su directorio UUID no existe en disco, reescribe el indice si el count cambia, ordena `songs` por `addedAt` descending. `loadError` es `nil` en exito o contiene el error si `JSONDecoder` falla. `addSong` inserta al inicio y persiste. `isCached` busca por `sourceHash` en memoria O(n).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] rootURL en closure sincrono de filter**
- **Found during:** Task 3
- **Issue:** El codigo del plan usaba `rootURL` como propiedad `get async` dentro de un closure `.filter {}` sincrono — error de compilacion "async property access in a function that does not support concurrency"
- **Fix:** Extraer `let root = await cacheManager.rootURL` antes del closure filter y usar `root` dentro
- **Files modified:** StrataClient/Library/LibraryStore.swift
- **Commit:** 23ece9e (incluido en el mismo commit del task)

## Self-Check: PASSED

- [x] StrataClient/Library/SongEntry.swift — EXISTS
- [x] StrataClient/Library/SongMetadata.swift — EXISTS
- [x] StrataClient/Library/CacheManager.swift — EXISTS
- [x] StrataClient/Library/LibraryStore.swift — EXISTS
- [x] Commit 10e10d6 — FOUND
- [x] Commit 572d5a8 — FOUND
- [x] Commit 23ece9e — FOUND
- [x] BUILD SUCCEEDED con los 4 ficheros nuevos
