---
phase: 09-show-chord-finger-position-diagram-alongside-chord-name
plan: "01"
subsystem: server-pipeline
tags: [chords, fingerings, guitar, tombatossals, chords-db]
dependency_graph:
  requires: []
  provides: [guitar-fingerings-data, fingerings-lookup-module, detect-chords-with-fingerings]
  affects: [server/pipeline/chords.py, server/pipeline/fingerings.py, server/pipeline/data/guitar.json]
tech_stack:
  added: [tombatossals/chords-db guitar.json]
  patterns: [lazy-load JSON DB, enharmonic normalization, module-level cache]
key_files:
  created:
    - server/pipeline/data/guitar.json
    - server/pipeline/fingerings.py
  modified:
    - server/pipeline/chords.py
decisions:
  - "guitar.json stored at lib/guitar.json in tombatossals repo (not src/db/guitar.json as plan assumed) — downloaded from correct path"
  - "tombatossals DB uses 'Csharp'/'Fsharp' as key names (not 'C#'/'F#') — _DB_KEY_MAP added in fingerings.py to translate before lookup"
  - "get_fingerings import inside try block in chords.py (same level as Chordino) — avoids import error when guitar.json not present outside GPU"
metrics:
  duration: ~8 min
  completed: "2026-03-24"
  tasks_completed: 2
  files_modified: 3
---

# Phase 09 Plan 01: Guitar Chord Fingerings Data Summary

**One-liner:** Guitar fingering database (tombatossals/chords-db) bundled in pipeline with lookup module that maps Chordino chord names to fret positions via enharmonic normalization.

## What Was Built

- `server/pipeline/data/guitar.json` — 377KB tombatossals chord database with fingering positions for all 12 keys and 60+ chord qualities
- `server/pipeline/fingerings.py` — Lookup module with `chord_name_to_key_suffix()` (Chordino name parser with enharmonic normalization) and `get_fingerings()` (returns up to 3 fingering positions per chord)
- `server/pipeline/chords.py` — Extended `detect_chords()` to include `"fingerings"` array alongside `chord`, `start`, `end` in each output entry

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] guitar.json path was wrong in plan**
- **Found during:** Task 1
- **Issue:** Plan specified `https://raw.githubusercontent.com/tombatossals/chords-db/master/src/db/guitar.json` which returned 404. The file is at `lib/guitar.json`.
- **Fix:** Downloaded from `https://raw.githubusercontent.com/tombatossals/chords-db/master/lib/guitar.json`
- **Files modified:** server/pipeline/data/guitar.json
- **Commit:** f56dda7

**2. [Rule 1 - Bug] DB key format uses 'Csharp'/'Fsharp' not 'C#'/'F#'**
- **Found during:** Task 1 — inspecting downloaded guitar.json structure
- **Issue:** The plan's `DB_KEYS` and lookup logic assumed `C#` and `F#` as dict keys. Actual tombatossals DB uses `Csharp` and `Fsharp`.
- **Fix:** Added `_DB_KEY_MAP = {"C#": "Csharp", "F#": "Fsharp"}` in fingerings.py and translate before DB lookup. Internal logic still uses `C#`/`F#` (standard notation).
- **Files modified:** server/pipeline/fingerings.py
- **Commit:** f56dda7

## Self-Check: PASSED

- FOUND: server/pipeline/data/guitar.json
- FOUND: server/pipeline/fingerings.py
- FOUND: server/pipeline/chords.py
- FOUND: commit f56dda7 (Task 1)
- FOUND: commit 2acb4a1 (Task 2)
