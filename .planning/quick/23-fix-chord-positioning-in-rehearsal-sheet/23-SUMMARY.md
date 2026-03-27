---
phase: quick-23
plan: 01
subsystem: player-viewmodel
tags: [rehearsal-sheet, chord-matching, lyrics, swift]
dependency_graph:
  requires: []
  provides: [correct-chord-to-word-assignment-in-rehearsal-sheet]
  affects: [RehearsalSheetView]
tech_stack:
  added: []
  patterns: [nearest-subsequent-word matching, window-based chord collection]
key_files:
  created: []
  modified:
    - Siyahamba/Player/PlayerViewModel.swift
decisions:
  - "rehearsalLines uses window-based chord collection (previous line end to current line end) instead of strict word time containment — covers silence between words and between lines with a single algorithm"
  - "nearest-subsequent-word: firstIndex(where: word.start >= chord.start) with fallback to last word — eliminates separate orphan chord handling block"
  - "first-chord-wins per word (chordForWord[wordIdx] == nil guard) — establishes harmonic change at the earliest point"
metrics:
  duration: ~5 min
  completed: 2026-03-27
---

# Quick Task 23: Fix Chord Positioning in Rehearsal Sheet — Summary

**One-liner:** Replaced strict time-containment chord matching with window-based nearest-subsequent-word algorithm so chords in silence between words and between lines are no longer lost.

## What Was Done

Rewrote the `rehearsalLines` computed property in `PlayerViewModel.swift` (lines 188–232).

**Old algorithm:**
- For each word, find a chord whose `start` falls within `[word.start, word.end)`.
- Separate block to attach "orphan" chords (before first word of line) to the first word.

**Problem:** Chords that fall in silence between two words, or between two lines, would not match any word because no word's time window contained the chord start.

**New algorithm:**
1. For each line, define a collection window: `[prevLine.end, line.end)` (or `[0.0, line.end)` for the first line).
2. Collect all filtered chords whose `start` falls within that window.
3. For each collected chord, assign to the word with the smallest `start >= chord.start` (nearest subsequent word). If no word starts after the chord, assign to the last word.
4. If multiple chords map to the same word, keep only the first (earliest).
5. Build `RehearsalWord` array with optional transposition.

The orphan chord block was removed — the unified algorithm handles that case inherently.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Rewrite rehearsalLines with nearest-subsequent-word chord matching | 46259b5 | Siyahamba/Player/PlayerViewModel.swift |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- [x] `Siyahamba/Player/PlayerViewModel.swift` modified with new algorithm
- [x] Commit `46259b5` exists
- [x] `BUILD SUCCEEDED` with no errors in rehearsalLines
