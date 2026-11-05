#!/usr/bin/env python3
"""Synthesises the "PING" heard inside the tank when a round bounces off it.

A bright metallic ring (inharmonic partials of a thick steel plate, each decaying at
its own rate) after a short hard click. Made from scratch, CC0.
  python3 tools/audio/make_ping.py assets/audio/impact/ping.wav
then convert: ffmpeg -i ping.wav -c:a libvorbis -q:a 6 ping.ogg
"""
import math
import random
import struct
import sys
import wave

RATE = 44100
LENGTH_S = 1.6
# (frequency Hz, amplitude, decay time constant s)
PARTIALS = [
    (1480.0, 1.00, 0.55),
    (2390.0, 0.65, 0.40),
    (3655.0, 0.45, 0.28),
    (5120.0, 0.30, 0.18),
    (6870.0, 0.18, 0.10),
    (1495.0, 0.40, 0.70),  # a slightly detuned twin: the shimmer of a ringing plate
]


def main(path: str) -> None:
    rng = random.Random(7)
    n = int(RATE * LENGTH_S)
    phases = [rng.random() * math.tau for _ in PARTIALS]
    samples = []
    for i in range(n):
        t = i / RATE
        attack = min(t / 0.0015, 1.0)
        v = 0.0
        for (f, a, d), ph in zip(PARTIALS, phases):
            v += a * math.exp(-t / d) * math.sin(math.tau * f * t + ph)
        v *= attack
        # Hard click of the strike: a few ms of decaying noise.
        if t < 0.012:
            v += (rng.random() * 2.0 - 1.0) * 1.2 * math.exp(-t / 0.003)
        samples.append(v)
    peak = max(abs(s) for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.95 * 32767)) for s in samples))


if __name__ == "__main__":
    main(sys.argv[1])
