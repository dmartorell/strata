---
phase: quick-24
plan: 01
subsystem: player-ui
tags: [rehearsal-sheet, drag-drop, persistence, chord-overrides]
dependency_graph:
  requires: [CacheManager, PlayerViewModel, RehearsalSheetView]
  provides: [chord_overrides.json per song, drag-to-reposition chord UI]
  affects: [RehearsalSheetView, PlayerViewModel, CacheManager]
tech_stack:
  added: []
  patterns: [SwiftUI .draggable/.dropDestination, Codable JSON per-song overrides, enumerated() for index-aware computed property]
key_files:
  created: []
  modified:
    - Siyahamba/Library/CacheManager.swift
    - Siyahamba/Player/PlayerViewModel.swift
    - Siyahamba/Player/RehearsalSheet/RehearsalSheetView.swift
decisions:
  - ChordOverride stores raw (untransposed) chord — transposition applied at display time in rehearsalLines
  - lineIndex as Int (not UUID) because RehearsalLine.id is regenerated each time (computed property)
  - Source word cleared via empty string override ("") rather than deleting the word entry
  - dropDestination isTargeted binding per-word with @State dropTargetIndex for highlight
metrics:
  duration: "~11 minutes"
  completed_date: "2026-03-27"
  tasks_completed: 2
  files_modified: 3
---

# Quick Task 24: Add Manual Chord Drag-to-Reposition in Rehearsal Sheet — Summary

**One-liner:** Per-song chord_overrides.json with SwiftUI drag/drop to move chord labels between words in rehearsal sheet, raw chord stored for transposition-independence.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | ChordOverride model, CacheManager persistence, PlayerViewModel integration | b39963a |
| 2 | Drag-and-drop UI in RehearsalWordFlow with drop highlight | a535b76 |

## What Was Built

### ChordOverride model (PlayerViewModel.swift)
```swift
struct ChordOverride: Codable, Sendable {
    let lineIndex: Int
    let wordIndex: Int
    let chord: String  // raw (untransposed), empty string = cleared
}
```

### CacheManager extensions
- `chordOverridesURL(songID:)` — `{songDir}/chord_overrides.json`
- `readChordOverrides(songID:)` — returns `[]` if file missing
- `writeChordOverrides(songID:overrides:)` — atomic write

### PlayerViewModel additions
- `chordOverrides: [ChordOverride]` observable property
- Loaded in `load()` after lyrics/chords
- `rehearsalLines` switched to `enumerated()` — applies overrides after automatic matching
- `saveChordOverrides() async` — persists to disk
- `applyChordOverride(lineIndex:fromWordIndex:toWordIndex:)` — reverse-transposes to raw, removes old overrides, adds new ones, saves async

### RehearsalSheetView UI
- `RehearsalWordFlow`: chord `Text` gets `.draggable(String(index))` when non-nil
- Each word `VStack` gets `.dropDestination(for: String.self)` — parses source index, calls `onChordMoved`
- `@State private var dropTargetIndex: Int?` drives per-word highlight via `.background(accentColor.opacity(0.3))`
- `RehearsalLineView` updated with `lineIndex: Int` and `onChordMoved: (Int, Int) -> Void`
- `ForEach` in `RehearsalSheetView` uses `Array(vm.rehearsalLines.enumerated())`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- CacheManager.swift: FOUND
- PlayerViewModel.swift: FOUND
- RehearsalSheetView.swift: FOUND
- Commit b39963a: FOUND
- Commit a535b76: FOUND
