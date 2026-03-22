"""WhisperX forced alignment for lyrics re-synchronization.

Takes plain text lyrics + vocals audio bytes, runs whisperx.align()
to produce word-level timestamps. Only uses alignment (not transcription).
"""

import gc
import io
import torch
import whisperx
import soundfile as sf


def align_lyrics(
    vocals_bytes: bytes,
    lyrics_text: str,
    language: str = "en",
) -> list[dict]:
    """Run WhisperX forced alignment on lyrics against vocals audio.

    Args:
        vocals_bytes: WAV bytes of the vocals stem.
        lyrics_text: Plain text lyrics (newline-separated lines).
        language: Language code for alignment model selection.

    Returns:
        List of segment dicts with word-level timestamps:
        [{"start": float, "end": float, "text": str, "words": [{"word": str, "start": float, "end": float}]}]
    """
    device = "cuda" if torch.cuda.is_available() else "cpu"

    with io.BytesIO(vocals_bytes) as buf:
        audio_np, sample_rate = sf.read(buf, dtype="float32")

    if audio_np.ndim > 1:
        audio_np = audio_np.mean(axis=1)

    lines = [l.strip() for l in lyrics_text.strip().split("\n") if l.strip()]
    transcript_segments = [{"text": line} for line in lines]

    model_a, metadata = whisperx.load_align_model(
        language_code=language,
        device=device,
    )

    result = whisperx.align(
        transcript_segments,
        model_a,
        metadata,
        audio_np,
        device,
        return_char_alignments=False,
    )

    del model_a
    gc.collect()
    if device == "cuda":
        torch.cuda.empty_cache()

    aligned_segments = []
    for seg in result.get("segments", []):
        words = []
        for w in seg.get("words", []):
            if "start" in w and "end" in w:
                words.append({
                    "word": w.get("word", ""),
                    "start": round(w["start"], 3),
                    "end": round(w["end"], 3),
                })
        aligned_segments.append({
            "start": round(seg.get("start", 0), 3),
            "end": round(seg.get("end", 0), 3),
            "text": seg.get("text", ""),
            "words": words,
        })

    return aligned_segments
