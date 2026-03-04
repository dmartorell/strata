---
phase: 07-player-ui-display-usage
plan: "01"
subsystem: models-data-layer
tags: [models, decodable, lyrics, chords, transpose, library, api, spm]
dependency_graph:
  requires: []
  provides:
    - LyricsFile/LyricLine/LyricWord Decodable structs
    - ChordsFile/ChordEntry Decodable structs
    - ChordTransposer.transpose() e inferKey()
    - SongEntry.pitchOffset y key opcionales
    - LibraryStore.deleteSongs(ids:)
    - APIClient.fetchUsage(token:) + UsageData
    - DSWaveformImage SPM dependency
  affects:
    - StrataClient/Player (nuevos modelos)
    - StrataClient/Library (SongEntry ampliado, deleteSongs)
    - StrataClient/Network (UsageData, fetchUsage)
tech_stack:
  added:
    - DSWaveformImage 14.0.0 (DSWaveformImageViews product via SPM)
  patterns:
    - Decodable con CodingKeys para UUID generado (excluido de JSON)
    - Equatable semántico (start+text en vez de UUID) para SwiftUI .onChange
    - ChordTransposer como enum namespace (no instanciable)
key_files:
  created:
    - StrataClient/Player/Lyrics/LyricsModels.swift
    - StrataClient/Player/Chords/ChordModels.swift
    - StrataClient/Player/Chords/ChordTransposer.swift
  modified:
    - StrataClient/Library/SongEntry.swift
    - StrataClient/Library/LibraryStore.swift
    - StrataClient/Network/APIClient.swift
    - StrataClient/Network/APIError.swift
    - project.yml
decisions:
  - "UUID generado en init(from decoder:) — excluido de CodingKeys para que no falle al decodificar JSON sin id"
  - "Equatable basado en start+text/chord (no UUID) para que SwiftUI .onChange detecte cambios de contenido correctamente"
  - "ChordTransposer allRoots ordenado por longitud desc para que C# matchee antes de C en hasPrefix"
  - "UsageData separado de UsageResponse: nuevo tipo con CodingKeys camelCase y estimatedCostEur; UsageResponse legacy mantenido sin romper"
  - "deleteSongs elimina directorio antes de escribir índice: si falla el removeItem, el índice se actualiza igual (best-effort filesystem)"
metrics:
  duration: ~15 min
  completed_date: "2026-03-05"
  tasks_completed: 2
  files_created: 3
  files_modified: 5
---

# Phase 07 Plan 01: Modelos de datos para Player UI Summary

Modelos Decodable completos para lyrics/chords JSON, ChordTransposer puro, SongEntry ampliado con pitchOffset/key, LibraryStore.deleteSongs, APIClient.fetchUsage con UsageData camelCase+EUR, y DSWaveformImage como dependencia SPM.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Modelos Lyrics, Chords, ChordTransposer | 91d0722 | LyricsModels.swift, ChordModels.swift, ChordTransposer.swift |
| 2 | SongEntry, LibraryStore, APIClient, project.yml | 2d4a73b | SongEntry.swift, LibraryStore.swift, APIClient.swift, APIError.swift, project.yml |

## Verification

- xcodegen generate: OK
- xcodebuild build (CODE_SIGNING_ALLOWED=NO): BUILD SUCCEEDED
- LyricsModels, ChordModels, ChordTransposer creados en StrataClient/Player/
- SongEntry tiene pitchOffset y key opcionales con init(from decoder:) compatible con library.json existente
- LibraryStore.deleteSongs(ids:) compila
- APIClient.fetchUsage(token:) + UsageData compila
- APIError.rateLimited anadido
- DSWaveformImage 14.0.0 en project.yml packages

## Deviations from Plan

None — plan ejecutado exactamente como estaba escrito.

## Self-Check: PASSED

- StrataClient/Player/Lyrics/LyricsModels.swift: FOUND
- StrataClient/Player/Chords/ChordModels.swift: FOUND
- StrataClient/Player/Chords/ChordTransposer.swift: FOUND
- Commits 91d0722 y 2d4a73b: FOUND
