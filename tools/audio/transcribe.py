"""Swedish speech-to-text for voice clips (faster-whisper, local, CPU).

geodata/.venv/bin/python tools/audio/transcribe.py [--model medium] <file or dir>...
Prints "<file>\t<text>" per clip, so new ElevenLabs recordings can be named and wired in.
"""
import argparse
import pathlib
import subprocess
import sys

import numpy as np
from faster_whisper import WhisperModel

AUDIO = {".mp3", ".ogg", ".wav", ".m4a", ".flac"}


def _samples(f: pathlib.Path) -> np.ndarray:
    """16 kHz mono float samples by ffmpeg (the bundled PyAV may not match faster-whisper)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(f), "-f", "s16le", "-ac", "1", "-ar", "16000", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, np.int16).astype(np.float32) / 32768.0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--model", default="medium")
    ap.add_argument("--language", default="sv")
    args = ap.parse_args()
    files: list[pathlib.Path] = []
    for p in map(pathlib.Path, args.paths):
        files += sorted(f for f in p.iterdir() if f.suffix.lower() in AUDIO) if p.is_dir() else [p]
    model = WhisperModel(args.model, device="cpu", compute_type="int8")
    for f in files:
        segments, _ = model.transcribe(_samples(f), language=args.language, beam_size=5)
        text = " ".join(s.text.strip() for s in segments)
        print(f"{f.name}\t{text}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
