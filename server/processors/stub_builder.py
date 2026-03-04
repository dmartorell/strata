"""
Stub ZIP builder para Strata.

Modulo puro (solo stdlib) — sin imports de FastAPI, modal ni auth.
Se puede importar tanto desde el contexto web como desde el contexto GPU.
"""

import io
import json
import wave
import zipfile
from pathlib import Path


def build_stub_zip(source_type: str, source_name: str) -> bytes:
    """Construye un ZIP con datos ficticios en formato final de produccion.

    Contenido:
    - vocals.wav, drums.wav, bass.wav, other.wav: 1s de silencio (44100Hz, 16-bit, stereo)
    - metadata.json: metadatos de la cancion
    - lyrics.json: letras con timestamps por palabra
    - chords.json: 4 acordes con timestamps

    Formato JSON segun base-documentation.md.
    """
    buf = io.BytesIO()

    def make_silence_wav(duration_s: float = 1.0, sample_rate: int = 44100) -> bytes:
        """Genera un WAV de silencio: 44100Hz, 16-bit, stereo."""
        n_frames = int(duration_s * sample_rate)
        wav_buf = io.BytesIO()
        with wave.open(wav_buf, "wb") as wf:
            wf.setnchannels(2)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(sample_rate)
            wf.writeframes(b"\x00" * n_frames * 2 * 2)  # n_frames * channels * sampwidth
        return wav_buf.getvalue()

    metadata = {
        "id": "stub-test-001",
        "title": Path(source_name).stem if source_type == "file" else source_name,
        "artist": "Strata Test",
        "duration": 30.0,
        "source": {
            "type": source_type,
            "filename": source_name,
        },
        "processed_at": "2026-03-02T00:00:00Z",
    }

    lyrics = {
        "language": "en",
        "segments": [
            {
                "start": 0.0,
                "end": 5.0,
                "text": "Hello world this is strata",
                "words": [
                    {"word": "Hello", "start": 0.0, "end": 0.8},
                    {"word": "world", "start": 0.9, "end": 1.5},
                    {"word": "this", "start": 1.6, "end": 2.0},
                    {"word": "is", "start": 2.1, "end": 2.4},
                    {"word": "strata", "start": 2.5, "end": 3.2},
                ],
            }
        ],
    }

    chords = {
        "chords": [
            {"start": 0.0, "end": 2.1, "chord": "Am"},
            {"start": 2.1, "end": 4.3, "chord": "F"},
            {"start": 4.3, "end": 6.5, "chord": "C"},
            {"start": 6.5, "end": 8.7, "chord": "G"},
        ]
    }

    silence_wav = make_silence_wav()

    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("vocals.wav", silence_wav)
        zf.writestr("drums.wav", silence_wav)
        zf.writestr("bass.wav", silence_wav)
        zf.writestr("other.wav", silence_wav)
        zf.writestr("metadata.json", json.dumps(metadata, indent=2))
        zf.writestr("lyrics.json", json.dumps(lyrics, indent=2))
        zf.writestr("chords.json", json.dumps(chords, indent=2))

    return buf.getvalue()
