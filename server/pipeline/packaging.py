"""ZIP packaging for audio pipeline results.

Empaqueta los 2 tracks WAV (original + instrumental) y los 2 JSONs en un
archivo ZIP en memoria.

Estructura del ZIP de salida:
    original.wav
    instrumental.wav
    chords.json
    metadata.json

Total: 4 archivos (2 WAV + 2 JSON).
"""

import io
import json
import zipfile


def package_results(
    stems: dict[str, bytes],
    chords: list,
    metadata: dict,
) -> bytes:
    """Empaqueta tracks y JSONs en un ZIP en memoria.

    Args:
        stems: Diccionario con 2 tracks WAV como bytes.
               Claves esperadas: "original", "instrumental".
        chords: Lista de acordes con timestamps.
                Se serializa a chords.json.
        metadata: Metadatos del job (title, duration_seconds, source_type, etc.).
                  Se serializa a metadata.json.

    Returns:
        Bytes del archivo ZIP comprimido con ZIP_DEFLATED.
    """
    buffer = io.BytesIO()

    with zipfile.ZipFile(buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        for track_name in ("original", "instrumental"):
            track_bytes = stems.get(track_name, b"")
            zf.writestr(f"{track_name}.wav", track_bytes)

        zf.writestr("chords.json", json.dumps(chords, ensure_ascii=False, indent=2))
        zf.writestr("metadata.json", json.dumps(metadata, ensure_ascii=False, indent=2))

    return buffer.getvalue()
