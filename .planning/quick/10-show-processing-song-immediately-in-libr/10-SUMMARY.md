---
phase: quick-10
plan: 01
subsystem: library-import
tags: [library, import, ux, placeholder, swift]
dependency_graph:
  requires: []
  provides: [placeholder-lifecycle]
  affects: [LibraryStore, ImportViewModel, LibraryView]
tech_stack:
  added: []
  patterns: [additive-schema, placeholder-row-pattern]
key_files:
  created: []
  modified:
    - SiyahambaClient/Library/SongEntry.swift
    - SiyahambaClient/Library/LibraryStore.swift
    - SiyahambaClient/Import/ImportViewModel.swift
    - SiyahambaClient/Library/LibraryView.swift
decisions:
  - isPlaceholder as optional Bool (additive-only schema) — nil means false for existing entries, no migration needed
  - replacePlaceholder writes only non-placeholder entries to disk — placeholders never persisted
  - cancel() removes placeholder synchronously before clearing task — avoids orphaned placeholder if task already cancelled
metrics:
  duration: ~10 min
  completed: 2026-03-22
---

# Quick Task 10: Show Processing Song Immediately in Library — Summary

**One-liner:** Placeholder row with spinner appears at position 0 in library table on import start, replaced by real data on success or removed on error/cancel.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Add isPlaceholder to SongEntry + placeholder methods to LibraryStore | 502f3e0 | SongEntry.swift, LibraryStore.swift |
| 2 | Wire placeholder lifecycle in ImportViewModel + style in LibraryView | 60d5a4b | ImportViewModel.swift, LibraryView.swift |

## What Was Built

**SongEntry.swift:**
- Added `isPlaceholder: Bool?` (additive-only, decodeIfPresent, nil = false)
- Added `static func placeholder(fileName:sourceHash:)` factory — strips extension for title, all other fields nil/0

**LibraryStore.swift:**
- `addPlaceholder(_:)` — synchronous insert at index 0, no disk write
- `replacePlaceholder(id:with:)` — async, replaces in-place, writes only non-placeholder entries to disk
- `removePlaceholder(id:)` — synchronous removal, no disk write

**ImportViewModel.swift:**
- `placeholderID: UUID?` tracks the active placeholder
- Placeholder created after hash/cache check, before `.uploading` phase
- On success: `replacePlaceholder` called instead of `addSong`
- On error (429, generic, cancellation) and `cancel()`: `removePlaceholder` called

**LibraryView.swift:**
- Título column: spinner + secondary text for placeholders
- Artista/Tono/Duración columns: `.tertiary` foreground for placeholders
- primaryAction (open song): guarded — skips placeholders
- contextMenu delete: hidden when all selected rows are placeholders

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] SongEntry.swift modified: isPlaceholder field + placeholder factory
- [x] LibraryStore.swift modified: 3 new methods
- [x] ImportViewModel.swift modified: placeholder lifecycle wired
- [x] LibraryView.swift modified: visual distinction + interaction guards
- [x] Commit 502f3e0 exists
- [x] Commit 60d5a4b exists
- [x] BUILD SUCCEEDED

## Self-Check: PASSED
