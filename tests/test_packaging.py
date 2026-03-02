"""Tests unitarios para server/pipeline/packaging.py.

Estos tests se ejecutan en local (sin GPU/Modal) con datos ficticios.
"""

import io
import json
import zipfile

import pytest

from server.pipeline.packaging import package_results


# ---------------------------------------------------------------------------
# Fixtures con datos ficticios
# ---------------------------------------------------------------------------


FAKE_STEMS = {
    "vocals": b"VOCALS_WAV_DATA",
    "drums": b"DRUMS_WAV_DATA",
    "bass": b"BASS_WAV_DATA",
    "other": b"OTHER_WAV_DATA",
}

FAKE_LYRICS = {
    "language": "en",
    "segments": [
        {
            "text": "Hello world",
            "start": 0.0,
            "end": 2.5,
            "words": [
                {"word": "Hello", "start": 0.0, "end": 1.0},
                {"word": "world", "start": 1.2, "end": 2.5},
            ],
        }
    ],
}

FAKE_CHORDS = [
    {"chord": "C:maj", "start": 0.0, "end": 2.0},
    {"chord": "G:maj", "start": 2.0, "end": None},
]

FAKE_METADATA = {
    "title": "Test Song",
    "duration_seconds": 180,
    "sample_rate": 44100,
    "source_type": "file",
    "processed_at": "2026-03-02T00:00:00Z",
    "original_filename": "test.mp3",
}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_package_returns_bytes():
    """package_results devuelve bytes no vacios."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    assert isinstance(result, bytes)
    assert len(result) > 0


def test_zip_is_valid():
    """El resultado es un ZIP valido y no esta corrupto."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    assert zipfile.is_zipfile(io.BytesIO(result))


def test_zip_contains_exactly_7_files():
    """El ZIP contiene exactamente 7 archivos (4 WAV + 3 JSON)."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        names = zf.namelist()
    assert len(names) == 7, f"Esperados 7 archivos, encontrados {len(names)}: {names}"


def test_zip_contains_all_wav_stems():
    """El ZIP contiene los 4 stems WAV con los nombres correctos."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        names = set(zf.namelist())
    expected_wavs = {"vocals.wav", "drums.wav", "bass.wav", "other.wav"}
    assert expected_wavs.issubset(names)


def test_zip_contains_all_jsons():
    """El ZIP contiene los 3 archivos JSON con los nombres correctos."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        names = set(zf.namelist())
    expected_jsons = {"lyrics.json", "chords.json", "metadata.json"}
    assert expected_jsons.issubset(names)


def test_lyrics_json_is_parseable():
    """lyrics.json dentro del ZIP es JSON parseable y contiene los datos correctos."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        lyrics_data = json.loads(zf.read("lyrics.json"))
    assert lyrics_data["language"] == "en"
    assert len(lyrics_data["segments"]) == 1
    assert lyrics_data["segments"][0]["text"] == "Hello world"


def test_chords_json_is_parseable():
    """chords.json dentro del ZIP es JSON parseable y contiene los datos correctos."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        chords_data = json.loads(zf.read("chords.json"))
    assert len(chords_data) == 2
    assert chords_data[0]["chord"] == "C:maj"
    assert chords_data[1]["end"] is None  # Ultimo acorde tiene end=None


def test_metadata_json_is_parseable():
    """metadata.json dentro del ZIP es JSON parseable y contiene los datos correctos."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        meta_data = json.loads(zf.read("metadata.json"))
    assert meta_data["title"] == "Test Song"
    assert meta_data["source_type"] == "file"
    assert meta_data["sample_rate"] == 44100


def test_wav_bytes_preserved():
    """Los bytes de los stems se escriben sin modificacion en el ZIP."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        assert zf.read("vocals.wav") == b"VOCALS_WAV_DATA"
        assert zf.read("drums.wav") == b"DRUMS_WAV_DATA"
        assert zf.read("bass.wav") == b"BASS_WAV_DATA"
        assert zf.read("other.wav") == b"OTHER_WAV_DATA"


def test_zip_uses_compression():
    """El ZIP usa compresion ZIP_DEFLATED."""
    result = package_results(FAKE_STEMS, FAKE_LYRICS, FAKE_CHORDS, FAKE_METADATA)
    with zipfile.ZipFile(io.BytesIO(result)) as zf:
        for info in zf.infolist():
            assert info.compress_type == zipfile.ZIP_DEFLATED, (
                f"{info.filename} no usa ZIP_DEFLATED"
            )
