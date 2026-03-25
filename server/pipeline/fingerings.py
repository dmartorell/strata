"""Guitar chord fingering lookup from the tombatossals/chords-db database.

Provides chord_name_to_key_suffix() and get_fingerings() for mapping
Chordino chord names (e.g. Am, C#m7) to guitar finger positions.
"""

import json
import os

_GUITAR_DB: dict | None = None

# tombatossals DB uses 'Csharp'/'Fsharp' as key names
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


def _load_db() -> dict:
    global _GUITAR_DB
    if _GUITAR_DB is None:
        db_path = os.path.join(os.path.dirname(__file__), "data", "guitar.json")
        with open(db_path, "r") as f:
            _GUITAR_DB = json.load(f)
    return _GUITAR_DB


def chord_name_to_key_suffix(chord: str) -> tuple[str, str] | None:
    """Parse a Chordino chord name into a (key, suffix) tuple for tombatossals lookup.

    Returns None for no-chord markers (N, -, '') or unrecognized chords.
    """
    if not chord or chord in ("N", "-"):
        return None

    # Strip slash bass note (e.g. G/B -> G)
    if "/" in chord:
        chord = chord.split("/")[0]

    # Extract root: 2 chars if second char is # or b, else 1 char
    if len(chord) >= 2 and chord[1] in ("#", "b"):
        root = chord[:2]
        quality = chord[2:]
    else:
        root = chord[:1]
        quality = chord[1:]

    # Normalize enharmonic equivalents
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
    """
    try:
        parsed = chord_name_to_key_suffix(chord_name)
        if parsed is None:
            return []

        key, suffix = parsed
        db = _load_db()

        # Convert key to DB format (Csharp / Fsharp)
        db_key = _DB_KEY_MAP.get(key, key)

        chords_for_key = db.get("chords", {}).get(db_key, [])
        for entry in chords_for_key:
            if entry.get("suffix") == suffix:
                positions = entry.get("positions", [])[:3]
                return [
                    {
                        "frets": p["frets"],
                        "fingers": p["fingers"],
                        "baseFret": p["baseFret"],
                        "barres": p.get("barres", []),
                    }
                    for p in positions
                ]
        return []
    except Exception:
        return []
