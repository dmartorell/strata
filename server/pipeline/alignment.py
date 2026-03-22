"""WhisperX forced alignment for lyrics re-synchronization.

Takes plain text lyrics + vocals audio bytes, runs whisperx.align()
to produce word-level timestamps. Only uses alignment (not transcription).
"""

import gc
import os
import tempfile
import torch
import whisperx


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

    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    try:
        tmp.write(vocals_bytes)
        tmp.close()
        audio_np = whisperx.load_audio(tmp.name)
    finally:
        os.unlink(tmp.name)

    lines = [l.strip() for l in lyrics_text.strip().split("\n") if l.strip()]
    duration = len(audio_np) / 16000.0
    n = len(lines)
    seg_dur = duration / n if n > 0 else duration
    transcript_segments = [
        {"text": line, "start": round(i * seg_dur, 3), "end": round((i + 1) * seg_dur, 3)}
        for i, line in enumerate(lines)
    ]

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
