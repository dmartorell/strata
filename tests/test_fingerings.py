from server.pipeline.fingerings import get_fingerings, chord_name_to_key_suffix

_TUNING = [40, 45, 50, 55, 59, 64]


def _bass_note(pos):
    for s in range(6):
        if pos["frets"][s] != -1:
            midi = _TUNING[s] + (pos["baseFret"] - 1) + pos["frets"][s]
            names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
            return names[midi % 12]
    return None


def test_basic_chord_still_works():
    positions = get_fingerings("Am")
    assert len(positions) > 0
    assert all(k in positions[0] for k in ("frets", "fingers", "baseFret", "barres"))


def test_slash_chord_uses_dedicated_db_entry():
    g_positions = get_fingerings("G")
    gb_positions = get_fingerings("G/B")
    assert len(gb_positions) > 0
    assert gb_positions != g_positions
    assert _bass_note(gb_positions[0]) == "B"


def test_slash_chord_am_e():
    positions = get_fingerings("Am/E")
    assert len(positions) > 0
    assert _bass_note(positions[0]) == "E"


def test_slash_chord_dm_f():
    positions = get_fingerings("Dm/F")
    assert len(positions) > 0
    assert _bass_note(positions[0]) == "F"


def test_slash_chord_enharmonic_bass():
    positions = get_fingerings("G/Ab")
    assert len(positions) > 0
    positions2 = get_fingerings("G/G#")
    assert positions == positions2


def test_slash_chord_fallback_no_dedicated_entry():
    base = get_fingerings("B7")
    slash = get_fingerings("B7/D#")
    assert len(slash) > 0
    assert len(slash) == len(base)


def test_chord_name_to_key_suffix_strips_slash():
    result = chord_name_to_key_suffix("G/B")
    assert result == ("G", "major")


def test_unknown_chord_returns_empty():
    assert get_fingerings("Xz/Q") == []
    assert get_fingerings("N") == []
    assert get_fingerings("") == []
