---
phase: quick-13
plan: 01
subsystem: client-ui
tags: [lyrics, sync, offset, player, swift]
dependency_graph:
  requires: []
  provides: [lyrics-offset-control]
  affects: [PlayerViewModel, LyricsView, TransportBarView]
tech_stack:
  added: []
  patterns: [SwiftUI-environment-popover, additive-schema-optional]
key_files:
  created:
    - SiyahambaClient/Player/LyricsOffsetPopover.swift
  modified:
    - SiyahambaClient/Library/SongEntry.swift
    - SiyahambaClient/Player/PlayerViewModel.swift
    - SiyahambaClient/Player/Lyrics/LyricsView.swift
    - SiyahambaClient/Player/TransportBarView.swift
decisions:
  - "lyricsOffset in Double seconds (not ms) for internal math, converted to ms only for display"
  - "Offset button only visible when showLyrics is true — no point adjusting hidden panel"
  - "saveLyricsOffset() called on each button press (same pattern as savePitchOffset)"
metrics:
  duration_minutes: 8
  completed_date: "2026-03-22"
  tasks_completed: 2
  files_modified: 5
---

# Quick Task 13: Add Lyrics Sync Offset Control — Summary

**One-liner:** Per-song lyrics timing offset (±ms) persisted in library JSON and applied to both highlight and linePassed dimming in real time.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add lyricsOffset to model and view model | d576d10 | SongEntry.swift, PlayerViewModel.swift |
| 2 | Add offset UI controls and wire into LyricsView | 9ff17dd | LyricsOffsetPopover.swift, LyricsView.swift, TransportBarView.swift |

## What Was Built

- `SongEntry.lyricsOffset: Double?` — additive optional field, persisted in library index JSON
- `PlayerViewModel.lyricsOffset: Double` — loaded from song on `load()`, applied in `currentLine` (`t = currentTime + lyricsOffset`) and `linePassed` (`line.end <= currentTime + lyricsOffset`)
- `LyricsOffsetPopover` — VStack popover with title "Sync letras", value display in ms (`+100ms`), −/+ buttons at 100ms steps, reset button; follows PitchPopover pattern exactly
- `TransportBarView` — timer button showing current offset label, only visible when `showLyrics` is true, opens `LyricsOffsetPopover` via `.popover`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] LyricsOffsetPopover.swift created at `SiyahambaClient/Player/LyricsOffsetPopover.swift`
- [x] SongEntry.lyricsOffset field added (CodingKeys, init, decoder)
- [x] PlayerViewModel.lyricsOffset applied in currentLine and loaded in load()
- [x] saveLyricsOffset() method added
- [x] LyricsView.linePassed uses offset-adjusted time
- [x] TransportBarView timer button conditional on showLyrics
- [x] Commits d576d10 and 9ff17dd exist
- [x] BUILD SUCCEEDED (no code errors)

## Self-Check: PASSED
