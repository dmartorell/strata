---
phase: quick-17
plan: 01
subsystem: player-ui
tags: [chords, diagrams, fingerings, ux]
dependency_graph:
  requires: []
  provides: [chord-diagrams-on-pause, bundled-fingerings-db, larger-chord-diagrams]
  affects: [PlayerViewModel, ChordView, ChordDiagramView, ChordFingerings, PlayerView]
tech_stack:
  added: []
  patterns: [lazy-static-db-load, enharmonic-normalization, swift-port-of-python]
key_files:
  created:
    - SiyahambaClient/Player/Chords/ChordFingerings.swift
    - SiyahambaClient/Resources/guitar.json
  modified:
    - SiyahambaClient/Player/PlayerViewModel.swift
    - SiyahambaClient/Player/Chords/ChordView.swift
    - SiyahambaClient/Player/Chords/ChordDiagramView.swift
    - SiyahambaClient/Player/PlayerView.swift
decisions:
  - Remove isPlaying guard from currentChord so the chord at pause position persists (no state variable needed)
  - hasFingerings always true when chords non-empty: bundled DB guarantees coverage for any recognized chord
  - ChordFingerings uses nonisolated(unsafe) static lazy var for thread-safe single DB load without actors
  - suffixMap port covers all 20 Python entries verbatim to maintain parity with server pipeline
metrics:
  duration: ~10 min
  completed_date: "2026-03-25"
  tasks_completed: 2
  files_modified: 6
---

# Quick Task 17: Refinar Diagramas de Acordes — Visibilidad Summary

**One-liner:** Chord diagrams persist on pause and appear for legacy songs via lazy-loaded bundled tombatossals DB, with larger frames (130x150 / 90x108) and improved legibility.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Fix pause persistence + bundle guitar.json + ChordFingerings | 91b1846 | PlayerViewModel.swift, guitar.json, ChordFingerings.swift, project.pbxproj |
| 2 | Integrate fallback fingerings + improve diagram sizing | b7aa6d5 | ChordView.swift, ChordDiagramView.swift, PlayerView.swift |

## What Was Built

**Task 1:**
- `PlayerViewModel.currentChord`: removed `guard engine.isPlaying else { return nil }` — the chord lookup already uses `currentTime`, so the last chord at pause position now persists
- `SiyahambaClient/Resources/guitar.json`: 378KB tombatossals chord database bundled with the app
- `ChordFingerings.swift`: Swift port of `server/pipeline/fingerings.py` — static `lookup(_ chordName: String) -> [ChordPosition]` with lazy DB load, enharmonic normalization, slash chord stripping, and full suffixMap (20 entries)

**Task 2:**
- `ChordView.hasFingerings`: always `true` when chords list is non-empty (bundled DB guarantees coverage)
- `ChordView.fingerings(for:fallbackEntry:)`: third fallback to `ChordFingerings.lookup()` for legacy songs with no server fingerings
- Frame sizes: current chord 100x120 → 130x150, next chord 70x84 → 90x108
- ChordDiagramView: dot radius 0.35→0.38, nut width 3→4, O/X font 11→13, fret label caption2→caption
- Chevron buttons: 24x24 frame + `contentShape(Rectangle())` for larger hit targets
- PlayerView: ChordView maxHeight 360→400 to accommodate larger frames

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `SiyahambaClient/Player/Chords/ChordFingerings.swift` — FOUND
- `SiyahambaClient/Resources/guitar.json` — FOUND
- Commit 91b1846 — FOUND
- Commit b7aa6d5 — FOUND
- Build: SUCCEEDED (no errors in modified files)
