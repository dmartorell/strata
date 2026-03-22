"""ZIP packaging for audio pipeline results.

Empaqueta los 4 stems WAV y los 2 JSONs en un archivo ZIP en memoria.

Estructura del ZIP de salida:
    vocals.wav
    drums.wav
    bass.wav
    other.wav
    chords.json
    metadata.json

Total: 6 archivos (4 WAV + 2 JSON).
"""

import io
import json
import zipfile


def package_results(
    stems: dict[str, bytes],
    chords: list,
    metadata: dict,
) -> bytes:
    """Empaqueta stems y JSONs en un ZIP en memoria.

    Args:
        stems: Diccionario con 4 stems WAV como bytes.
               Claves esperadas: "vocals", "drums", "bass", "other".
        chords: Lista de acordes con timestamps.
                Se serializa a chords.json.
        metadata: Metadatos del job (title, duration_seconds, source_type, etc.).
                  Se serializa a metadata.json.

    Returns:
        Bytes del archivo ZIP comprimido con ZIP_DEFLATED.
    """
    buffer = io.BytesIO()

    with zipfile.ZipFile(buffer, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        for stem_name in ("vocals", "drums", "bass", "other"):
            stem_bytes = stems.get(stem_name, b"")
            zf.writestr(f"{stem_name}.wav", stem_bytes)

        zf.writestr("chords.json", json.dumps(chords, ensure_ascii=False, indent=2))
        zf.writestr("metadata.json", json.dumps(metadata, ensure_ascii=False, indent=2))

    return buffer.getvalue()
