"""Chord detection module using chord-extractor (VAMP/Chordino).

Ejecuta sobre el stem 'other' (guitarra/piano/keys) — no sobre el mix completo.
Output: [{chord, start, end}] con start/end en segundos.

Decision de diseno (CONTEXT.md):
- Si la extraccion falla por cualquier motivo, retorna [] (resultado parcial).
- El ultimo acorde tiene end=None (Phase 7 puede cerrar con la duracion del audio).
- NO usar CREMA — incompatible con Python 3.11 (Keras 3 rompe model_from_config).
"""

import os
import tempfile


def detect_chords(other_stem_bytes: bytes) -> list[dict]:
    """Detecta acordes con timestamps a partir del stem 'other' en bytes WAV.

    Args:
        other_stem_bytes: Contenido WAV del stem 'other' de Demucs.

    Returns:
        Lista de dicts [{chord: str, start: float, end: float|None}].
        Retorna [] si chord-extractor falla por cualquier razon.
    """
    try:
        from chord_extractor.extractors import Chordino
        from pipeline.fingerings import get_fingerings

        # Escribir bytes a archivo temporal WAV
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(other_stem_bytes)
            tmp_path = f.name

        try:
            extractor = Chordino()
            chords = extractor.extract(tmp_path)
            # chords: [ChordChange(chord='D:maj', timestamp=0.0), ...]

            result = []
            for i, chord_change in enumerate(chords):
                end = chords[i + 1].timestamp if i + 1 < len(chords) else None
                result.append({
                    "chord": chord_change.chord,
                    "start": chord_change.timestamp,
                    "end": end,
                    "fingerings": get_fingerings(chord_change.chord),
                })
            return result
        finally:
            # Limpiar archivo temporal siempre, incluso si extract falla
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    except Exception as e:
        print(f"Chord detection failed: {e}")
        return []
