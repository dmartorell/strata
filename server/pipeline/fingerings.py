"""Guitar chord fingering lookup from the tombatossals/chords-db database.

Provides chord_name_to_key_suffix() and get_fingerings() for mapping
Chordino chord names (e.g. Am, C#m7) to guitar finger positions.
"""

import json
import os

_GUITAR_DB: dict | None = None

_DB_KEY_MAP = {
    "C#": "Csharp",
    "F#": "Fsharp",
}

DB_KEYS = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

ENHARMONIC = {
    "Db": "C#",
    "D#": "Eb",
    "Gb": "F#",
    "G#": "Ab",
    "A#": "Bb",
}

SUFFIX_MAP = {
    "": "major",
    "m": "minor",
    "7": "7",
    "maj7": "maj7",
    "m7": "m7",
    "dim": "dim",
    "dim7": "dim7",
    "aug": "aug",
    "m7b5": "m7b5",
    "sus2": "sus2",
    "sus4": "sus4",
    "6": "6",
    "m6": "m6",
    "9": "9",
    "m9": "m9",
    "add9": "add9",
    "5": "5",
    "aug7": "aug7",
    "mmaj7": "mmaj7",
    "maj9": "maj9",
}

_SUFFIX_TO_SLASH_PREFIX = {
    "major": "",
    "minor": "m",
    "m9": "m9",
    "7": "7",
}

_TUNING = [40, 45, 50, 55, 59, 64]  # E2 A2 D3 G3 B3 E4

_NOTE_TO_PITCH_CLASS = {
    "C": 0, "C#": 1, "D": 2, "Eb": 3, "E": 4, "F": 5,
    "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11,
}


def _load_db() -> dict:
    global _GUITAR_DB
    if _GUITAR_DB is None:
        db_path = os.path.join(os.path.dirname(__file__), "data", "guitar.json")
        with open(db_path, "r") as f:
            _GUITAR_DB = json.load(f)
    return _GUITAR_DB


def _position_dict(p: dict) -> dict:
    return {
        "frets": p["frets"],
        "fingers": p["fingers"],
        "baseFret": p["baseFret"],
        "barres": p.get("barres", []),
    }


def _bass_pitch_class(position: dict) -> int | None:
    frets = position["frets"]
    base_fret = position["baseFret"]
    for s in range(6):
        if frets[s] != -1:
            return (_TUNING[s] + (base_fret - 1) + frets[s]) % 12
    return None


def _reorder_by_bass(positions: list[dict], bass_note: str) -> list[dict]:
    target = _NOTE_TO_PITCH_CLASS.get(bass_note)
    if target is None:
        return positions
    matching = [p for p in positions if _bass_pitch_class(p) == target]
    non_matching = [p for p in positions if _bass_pitch_class(p) != target]
    return matching + non_matching


def chord_name_to_key_suffix(chord: str) -> tuple[str, str] | None:
    """Parse a Chordino chord name into a (key, suffix) tuple for tombatossals lookup.

    Returns None for no-chord markers (N, -, '') or unrecognized chords.
    """
    if not chord or chord in ("N", "-"):
        return None

    if "/" in chord:
        chord = chord.split("/")[0]

    if len(chord) >= 2 and chord[1] in ("#", "b"):
        root = chord[:2]
        quality = chord[2:]
    else:
        root = chord[:1]
        quality = chord[1:]

    root = ENHARMONIC.get(root, root)

    if root not in DB_KEYS:
        return None

    if quality not in SUFFIX_MAP:
        return None

    return (root, SUFFIX_MAP[quality])


def get_fingerings(chord_name: str) -> list[dict]:
    """Return up to 3 fingering positions for a chord name.

    Returns [] if the chord is unknown or not found in the database.
    Each position dict has: frets, fingers, baseFret, barres.

    For slash chords (e.g. G/B, Am/E), tries a dedicated DB entry first,
    then falls back to the base chord with positions reordered so those
    matching the slash bass note come first.
    """
    try:
        bass_note = None
        if "/" in chord_name:
            parts = chord_name.split("/", 1)
            bass_note = ENHARMONIC.get(parts[1], parts[1])
            if bass_note not in DB_KEYS:
                bass_note = None

        parsed = chord_name_to_key_suffix(chord_name)
        if parsed is None:
            return []

        key, suffix = parsed
        db = _load_db()
        db_key = _DB_KEY_MAP.get(key, key)
        chords_for_key = db.get("chords", {}).get(db_key, [])

        if bass_note:
            slash_prefix = _SUFFIX_TO_SLASH_PREFIX.get(suffix)
            if slash_prefix is not None:
                slash_suffix = f"{slash_prefix}/{bass_note}" if slash_prefix else f"/{bass_note}"
                for entry in chords_for_key:
                    if entry.get("suffix") == slash_suffix:
                        positions = entry.get("positions", [])[:3]
                        return [_position_dict(p) for p in positions]

        for entry in chords_for_key:
            if entry.get("suffix") == suffix:
                positions = entry.get("positions", [])[:3]
                result = [_position_dict(p) for p in positions]
                if bass_note:
                    result = _reorder_by_bass(result, bass_note)
                return result

        return []
    except Exception:
        return []
