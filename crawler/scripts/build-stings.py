#!/usr/bin/env python3
"""Renders the short one-shot music cues ("stings") for good moments, in the battle loop's 8-bit voice.

  fanfare: going down the stairs to a new floor. The game's melody, quick, climbing to a high D major
           chord with a snare roll and a crash. About 3.5 seconds.
  victory: winning a fight. The melody's first notes, rushed, and a held chord. About 2 seconds.

Needs numpy and scipy:  python3 scripts/build-stings.py /tmp   (writes /tmp/fanfare.wav and /tmp/victory.wav)
Then encode each:       afconvert -f m4af -d aac -b 160000 /tmp/fanfare.wav public/fanfare.m4a
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

from chip import SR, rng, hz, env, pulse, triangle, kick, noise_hit, snare

BPM = 150
EIGHTH = 30 / BPM

# Both cues quote the game's melody (A B C D D D ..., here in D major: D E F# G G G, A G A) and land on
# a high D major chord.
STINGS = {
    "fanfare": {
        # (start in eighths, length in eighths, midi)
        "lead": [(0, 0.5, 74), (0.5, 0.5, 76), (1, 0.5, 78), (1.5, 0.5, 79), (2, 0.5, 79), (2.5, 1.5, 79),
                 (4, 0.5, 81), (4.5, 0.5, 79), (5, 1, 81), (6, 0.5, 83), (6.5, 0.5, 85), (7, 7, 86)],
        # (start, length, chord tones, bass root)
        "chords": [(0, 2.5, [62, 66, 69], 38), (2.5, 1.5, [62, 67, 71], 43), (4, 3, [61, 64, 67, 69], 45), (7, 7, [62, 66, 69, 74], 38)],
        "roll": (5, 7),  # snare roll into the landing
        "crash": 7,
        "length": 14,
    },
    "victory": {
        "lead": [(0, 0.5, 74), (0.5, 0.5, 76), (1, 0.5, 78), (1.5, 0.5, 79), (2, 0.5, 79), (2.5, 0.5, 81), (3, 4, 86)],
        "chords": [(0, 2.5, [62, 67, 71], 43), (2.5, 0.5, [61, 64, 69], 45), (3, 4.5, [62, 66, 69, 74], 38)],
        "roll": None,
        "crash": 3,
        "length": 8,
    },
}


def render(spec):
    n = int((spec["length"] * EIGHTH + 0.6) * SR)
    mix = np.zeros((2, n))
    lead = np.zeros(n)

    def put(sig, start_s, pan=0.0, bus=None):
        i = int(round(start_s * SR))
        sig = sig[: max(0, n - i)]
        if bus is not None:
            bus[i : i + sig.size] += sig
            return
        mix[0, i : i + sig.size] += sig * (1 - pan)
        mix[1, i : i + sig.size] += sig * (1 + pan)

    for start, length, m in spec["lead"]:
        dur = length * EIGHTH * (0.92 if length < 2 else 1.0)
        sig = pulse(hz(m), dur, 0.5, vibrato=0.005 if length >= 2 else 0) * env(int(dur * SR), release=0.08 if length >= 2 else 0.03)
        put(sig * 0.24, start * EIGHTH, bus=lead)
    for start, length, tones, root in spec["chords"]:
        dur = length * EIGHTH
        for j, m in enumerate(tones):
            sig = pulse(hz(m), dur, 0.25) * env(int(dur * SR), attack=0.01, release=0.12, decay=0.4, sustain=0.55)
            put(sig * 0.055, start * EIGHTH, pan=0.3 if j % 2 else -0.3)
        steps = max(1, int(length))
        for k in range(steps):
            last = k == steps - 1
            bdur = (length - k if last else 1) * EIGHTH * (1.0 if last else 0.85)
            m = root + (12 if k % 2 else 0)
            put(triangle(hz(m), bdur) * env(int(bdur * SR), release=0.1 if last else 0.02) * 0.4, (start + k) * EIGHTH)
        put(kick() * 0.5, start * EIGHTH)
    if spec["roll"]:
        a, b = spec["roll"]
        steps = int((b - a) * 4)
        for k in range(steps):
            put(snare() * (0.06 + 0.16 * k / steps), (a + k / 4) * EIGHTH)
    crash = noise_hit(1.6, 0.5, 3000, 15000) * 0.22
    put(crash, spec["crash"] * EIGHTH, pan=0.15)
    put(kick() * 0.6, spec["crash"] * EIGHTH)

    # Lead echo, then a fade so the tail never clicks
    d = int(round(EIGHTH * 1.5 * SR))
    mix[0] += lead + np.concatenate([np.zeros(2 * d), lead[: n - 2 * d]]) * 0.14
    mix[1] += lead + np.concatenate([np.zeros(d), lead[: n - d]]) * 0.24
    mix = sosfilt(butter(1, 30, btype="high", fs=SR, output="sos"), mix, axis=1)
    mix = np.tanh(mix / 0.85) * 0.85
    mix *= 0.9 / np.abs(mix).max()
    fade = int(0.25 * SR)
    mix[:, -fade:] *= np.linspace(1, 0, fade)
    return mix


out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
for name, spec in STINGS.items():
    mix = render(spec)
    dither = rng.uniform(-1, 1, mix.shape) / 32768
    path = f"{out_dir}/{name}.wav"
    wavfile.write(path, SR, np.round((mix + dither).T * 32767).clip(-32768, 32767).astype(np.int16))
    print(f"wrote {path}: {mix.shape[1] / SR:.2f}s", file=sys.stderr)
