---
phase: 10-rehearsal-sheet-view
plan: 02
subsystem: ui
tags: [swiftui, lyrics, chords, layout, scroll, playback]

# Dependency graph
requires:
  - phase: 07-player-ui-display-usage
    provides: PlayerViewModel, LyricsView patterns, ChordEntry/LyricLine models
  - phase: 09-show-chord-finger-position-diagram-alongside-chord-name
    provides: ChordTransposer, fingerings data model
provides:
  - RehearsalSheetView — chord sheet with inline chords above lyrics words
  - RehearsalLine/RehearsalWord structs — chord-word timing matched data model
  - DisplayMode.rehearsalSheet enum case in SongEntry
  - rehearsalLines computed property in PlayerViewModel
affects: PlayerView (will need to wire rehearsalSheet display mode), future plan 03 (display mode persistence)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - FlowLayout (Layout protocol) for wrapping word-level VStack cells
    - PreferenceKey + GeometryReader for manual scroll detection on macOS 14
    - rehearsalLines computed property pattern for time-matching chords to lyric words

key-files:
  created:
    - SiyahambaClient/Player/RehearsalSheet/RehearsalSheetView.swift
  modified:
    - SiyahambaClient/Library/SongEntry.swift
    - SiyahambaClient/Player/PlayerViewModel.swift

key-decisions:
  - "FlowLayout (Layout protocol) chosen over AttributedString for word-level VStack cells — allows chord+lyric vertical stacking per word"
  - "onScrollPhaseChange (macOS 15+) replaced with PreferenceKey+GeometryReader offset tracking for macOS 14 compatibility"
  - "rehearsalLines matches chord.start in [word.start, word.end) window; orphan chords (before first word of line) attach to first word"
  - "Chord names always accent blue (0.47, 0.66, 0.84); lyric colors follow LyricsView pattern: white=active, gray=passed, blue=upcoming"

patterns-established:
  - "FlowLayout: custom Layout conformance for wrapping heterogeneous-width views at container width"
  - "Scroll detection on macOS 14: PreferenceKey reports content offset, delta vs lastAutoScrollOffset distinguishes user vs programmatic scroll"

requirements-completed: [RHRS-01, RHRS-02, RHRS-03]

# Metrics
duration: 25min
completed: 2026-03-25
---

# Phase 10 Plan 02: Rehearsal Sheet View Summary

**SwiftUI chord sheet with FlowLayout word-stacks, chord-word timing matching via rehearsalLines, and hybrid auto-scroll (macOS 14 compatible) using GeometryReader offset detection**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-25T22:20:00Z
- **Completed:** 2026-03-25T22:44:49Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- Added `DisplayMode.rehearsalSheet` to SongEntry enum
- Added `RehearsalWord`/`RehearsalLine` structs and `rehearsalLines` computed property to PlayerViewModel with chord-to-word timing matching and transposition support
- Built `RehearsalSheetView` with custom `FlowLayout` (Layout protocol) that wraps word-level VStack cells (chord above, lyric below) at container width
- Hybrid auto-scroll: follows playback by default, detects manual scroll via PreferenceKey offset delta, shows "Seguir reproduccion" resume button

## Task Commits

1. **Task 1: Add DisplayMode.rehearsalSheet and rehearsalLines** - `b3dbf0e` (feat)
2. **Task 2: Create RehearsalSheetView** - `9b6a4dd` (feat)

## Files Created/Modified
- `SiyahambaClient/Player/RehearsalSheet/RehearsalSheetView.swift` - Full rehearsal sheet view with FlowLayout, line highlighting, hybrid scroll
- `SiyahambaClient/Library/SongEntry.swift` - Added `case rehearsalSheet` to DisplayMode enum
- `SiyahambaClient/Player/PlayerViewModel.swift` - Added RehearsalWord/RehearsalLine structs and rehearsalLines computed property

## Decisions Made
- FlowLayout via Layout protocol chosen for word-level VStack cells (chord name above, lyric text below) — gives per-word chord attachment while wrapping naturally
- `onScrollPhaseChange` (macOS 15+) replaced with PreferenceKey + GeometryReader content offset tracking for macOS 14 compatibility; delta threshold of 2pt distinguishes user scroll from programmatic auto-scroll
- Chord-word matching: `chord.start in [word.start, word.end)`; if a chord falls before first word, it is attached to first word of the line

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Replaced onScrollPhaseChange with PreferenceKey-based offset tracking**
- **Found during:** Task 2 (RehearsalSheetView creation)
- **Issue:** `onScrollPhaseChange` requires macOS 15.0; project targets macOS 14.0
- **Fix:** Implemented `ScrollOffsetKey: PreferenceKey` with GeometryReader inside ScrollView content to track minY offset; compare delta against `lastAutoScrollOffset` to detect manual scrolls
- **Files modified:** SiyahambaClient/Player/RehearsalSheet/RehearsalSheetView.swift
- **Verification:** Build succeeded; logic correctly guards auto-scroll only when `isFollowingPlayback == true`
- **Committed in:** 9b6a4dd (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — API availability)
**Impact on plan:** Essential fix for deployment target compatibility. Functionally equivalent result.

## Issues Encountered
- None beyond the macOS 14 compatibility deviation documented above.

## Next Phase Readiness
- RehearsalSheetView is complete and buildable
- Plan 03 needs to wire `DisplayMode.rehearsalSheet` into PlayerView's `mainZone` and `saveDisplayMode`, and add a toggle button in the transport/top bar

---
*Phase: 10-rehearsal-sheet-view*
*Completed: 2026-03-25*
