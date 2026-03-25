---
phase: 10-rehearsal-sheet-view
plan: "03"
subsystem: ui
tags: [rehearsal-sheet, player, transport-bar, chord-diagrams, difficulty]
dependency_graph:
  requires:
    - 10-01 (ChordSimplifier, DifficultyLevel)
    - 10-02 (RehearsalSheetView, RehearsalLine/RehearsalWord, DisplayMode.rehearsalSheet)
  provides:
    - R key shortcut activates rehearsal sheet
    - Ensayo toggle in TransportBar
    - Collapsible reference panel with chord diagrams
    - Font size (Aa) and offset popover in rehearsal sheet
    - Chord difficulty simplification throughout rehearsal sheet
    - Display mode .rehearsalSheet persists per song
  affects:
    - PlayerView (mainZone routing, key handlers, display mode persistence)
    - TransportBarView (Ensayo toggle, Letras/Acordes clear rehearsal mode)
    - PlayerViewModel (saveDisplayMode extended with showRehearsalSheet parameter)
tech_stack:
  added: []
  patterns:
    - AppStorage-persistence (rehearsalSheet.showReferencePanel, rehearsalSheet.fontSize)
    - Binding propagation for three-way exclusive display mode (lyrics/chords/rehearsalSheet)
key_files:
  created: []
  modified:
    - SiyahambaClient/Player/PlayerView.swift
    - SiyahambaClient/Player/TransportBarView.swift
    - SiyahambaClient/Player/RehearsalSheet/RehearsalSheetView.swift
    - SiyahambaClient/Player/PlayerViewModel.swift
decisions:
  - "showRehearsalSheet is a third exclusive state alongside showLyrics/showChords — activating any one clears the others"
  - "RehearsalFontSizePopover is inline (not reusing LyricsFontSizePopover) — separate AppStorage key rehearsalSheet.fontSize with independent range 14-40pt"
  - "Reference panel toggle button uses bottomLeading overlay to avoid conflict with Aa (bottomTrailing) and offset (topTrailing) buttons"
  - "uniqueChords applies transposition + difficulty simplification so reference panel matches inline chord names exactly"
metrics:
  duration: "~3 min"
  completed: "2026-03-25"
  tasks_completed: 3
  files_modified: 4
---

# Phase 10 Plan 03: Rehearsal Sheet Wiring Summary

**One-liner:** R key + Ensayo transport toggle wire rehearsal sheet into PlayerView with collapsible chord-diagram reference panel, Aa font size popover, offset control, and difficulty simplification applied throughout.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Wire rehearsal sheet into PlayerView, TransportBar, and display mode persistence | a09e5d0 | PlayerView.swift, TransportBarView.swift, PlayerViewModel.swift |
| 2 | Add reference panel, font/offset controls, and difficulty integration | c7fe981 | RehearsalSheetView.swift |
| 3 | Verify complete rehearsal sheet feature end-to-end | auto-approved | — |

## What Was Built

**PlayerView.swift:**
- `showRehearsalSheet` State initialized from `song.displayMode == .rehearsalSheet`
- `mainZone` renders `RehearsalSheetView()` when `showRehearsalSheet` is true, otherwise existing lyrics/chords logic
- R key handler activates rehearsal sheet (guarded by `!chords.isEmpty`), clears showLyrics/showChords
- L and A key handlers now set `showRehearsalSheet = false` when activating other modes
- Back button `saveDisplayMode` call passes `showRehearsalSheet: showRehearsalSheet`

**TransportBarView.swift:**
- Added `@Binding var showRehearsalSheet: Bool`
- Added `hasChords` computed var
- "Ensayo" toggle button (music.note.list icon) next to Letras/Acordes; disabled when no chords
- Letras and Acordes toggle actions set `showRehearsalSheet = false`

**PlayerViewModel.swift:**
- `saveDisplayMode(showLyrics:showChords:showRehearsalSheet:)` — if showRehearsalSheet, saves `.rehearsalSheet`; otherwise existing switch logic

**RehearsalSheetView.swift:**
- `simplified(_ chord: String) -> String` using `@AppStorage("chordView.difficultyLevel")` + `ChordSimplifier`
- `uniqueChords: [String]` — deduped list after transposition + difficulty simplification
- Collapsible reference panel (80×80pt ChordDiagramView per chord, 120pt tall horizontal ScrollView)
- Current chord highlighted in reference panel via `isCurrent` background
- `RehearsalFontSizePopover` (bottomTrailing overlay, 14-40pt, `rehearsalSheet.fontSize`)
- Offset popover (topTrailing overlay, reuses `LyricsOffsetPopover`)
- Reference panel toggle button (bottomLeading overlay, `rehearsalSheet.showReferencePanel`)
- Difficulty simplification applied to inline chords (via `RehearsalWordFlow.simplify`), chordsOnlyView, and reference panel

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] PlayerView.swift: contains `showRehearsalSheet`, `rehearsalSheet` routing, R key, L/A clear rehearsal
- [x] TransportBarView.swift: contains `Ensayo` toggle, `showRehearsalSheet` binding
- [x] RehearsalSheetView.swift: contains `referencePanel`, `ChordSimplifier.simplify`, font/offset popovers
- [x] PlayerViewModel.swift: `saveDisplayMode` extended with `showRehearsalSheet` parameter
- [x] Build succeeds (BUILD SUCCEEDED, warnings only — all preexisting)
- [x] Commit a09e5d0 exists (Task 1)
- [x] Commit c7fe981 exists (Task 2)
