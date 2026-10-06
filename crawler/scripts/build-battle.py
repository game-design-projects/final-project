#!/usr/bin/env python3
"""Renders the battle music: a bright, driving 8-bit loop, the opposite of the dungeon's dark ambient.

Chiptune voices, synthesised band-limited (no samples): a pulse-wave lead with a little vibrato and
echo, a 25% pulse arpeggio, a triangle bass pumping octaves, and noise/sine drums. 152 BPM in D,
on the heroic D - C - G - A progression, with a B minor bridge. The render is circular, so the loop
point is seamless.

Needs numpy and scipy:  python3 scripts/build-battle.py out.wav
Then encode:            afconvert -f m4af -d aac -b 160000 out.wav public/battle.m4a
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

from chip import SR, rng, hz, env, pulse, triangle, kick, noise_hit, snare

BPM = 152
EIGHTH = 30 / BPM  # seconds
BAR = EIGHTH * 8
TAIL = 1.0  # the file repeats its first second at the end, so players can loop inside it

# One chord per bar: (root for the bass, chord tones for the arpeggio)
CHORDS = {
    "D": (38, [62, 66, 69]),
    "C": (36, [60, 64, 67]),
    "G": (43, [62, 67, 71]),
    "A": (45, [61, 64, 69]),
    "Bm": (47, [62, 66, 71]),
}
PROGRESSION = ["D", "C", "G", "A", "D", "C", "G", "A", "Bm", "G", "D", "A", "Bm", "G", "A", "A"]

# The lead, bar by bar: (start in eighths, length in eighths, midi note)
MELODY = [
    [(0, 1, 69), (1, 1, 74), (2, 1, 78), (3, 2, 81), (5, 1, 78), (6, 2, 74)],
    [(0, 1, 79), (1, 1, 76), (2, 1, 72), (3, 2, 76), (5, 1, 79), (6, 2, 76)],
    [(0, 2, 74), (2, 1, 71), (3, 1, 74), (4, 2, 79), (6, 1, 78), (7, 1, 79)],
    [(0, 3, 81), (3, 1, 79), (4, 1, 78), (5, 1, 76), (6, 2, 73)],
    [(0, 1, 69), (1, 1, 74), (2, 1, 78), (3, 2, 81), (5, 1, 83), (6, 2, 86)],
    [(0, 2, 84), (2, 1, 83), (3, 1, 81), (4, 2, 79), (6, 2, 76)],
    [(0, 1, 79), (1, 1, 81), (2, 1, 83), (3, 3, 86), (6, 1, 83), (7, 1, 79)],
    [(0, 4, 81), (4, 1, 76), (5, 1, 78), (6, 1, 79), (7, 1, 81)],
    [(0, 3, 83), (3, 1, 81), (4, 2, 78), (6, 2, 74)],
    [(0, 2, 79), (2, 1, 78), (3, 1, 79), (4, 2, 83), (6, 2, 79)],
    [(0, 3, 78), (3, 1, 76), (4, 2, 74), (6, 1, 69), (7, 1, 74)],
    [(0, 4, 76), (4, 2, 73), (6, 2, 69)],
    [(0, 1, 71), (1, 1, 74), (2, 1, 78), (3, 3, 83), (6, 2, 81)],
    [(0, 2, 79), (2, 1, 81), (3, 1, 83), (4, 2, 86), (6, 2, 83)],
    [(0, 2, 85), (2, 2, 81), (4, 2, 76), (6, 2, 73)],
    [(0, 4, 81), (4, 1, 76), (5, 1, 73), (6, 1, 71), (7, 1, 73)],
]
assert len(MELODY) == len(PROGRESSION)

LOOP = BAR * len(PROGRESSION)
N = int(round(LOOP * SR))


def place(buf, sig, start_s, pan=0.0):
    """Add a mono signal into the stereo loop at start_s seconds, wrapping around the end."""
    i = int(round(start_s * SR)) % N
    idx = (i + np.arange(sig.size)) % N
    buf[0, idx] += sig * (1 - pan) * 0.5 ** 0.5 * 1.41
    buf[1, idx] += sig * (1 + pan) * 0.5 ** 0.5 * 1.41


mix = np.zeros((2, N))
lead_bus = np.zeros((2, N))

for bar, (name, notes) in enumerate(zip(PROGRESSION, MELODY)):
    root, tones = CHORDS[name]
    t0 = bar * BAR
    # Lead: 50% pulse, a touch of vibrato on longer notes
    for start, length, m in notes:
        dur = length * EIGHTH * 0.92
        sig = pulse(hz(m), dur, 0.5, vibrato=0.004 if length >= 2 else 0) * env(int(dur * SR), release=0.04)
        place(lead_bus, sig * 0.20, t0 + start * EIGHTH, pan=-0.1)
    # Arpeggio: chord tones up an octave in sixteenths, 25% pulse, quiet and a little to the right
    seq = tones + [tones[1] + 12, tones[2] + 12, tones[0] + 12, tones[2], tones[1]]
    for i in range(16):
        m = seq[i % len(seq)] + 12
        dur = EIGHTH / 2 * 0.8
        sig = pulse(hz(m), dur, 0.25) * env(int(dur * SR), release=0.015, decay=0.05, sustain=0.4)
        place(mix, sig * 0.07, t0 + i * EIGHTH / 2, pan=0.35)
    # Bass: triangle, octave-pumping eighths, with a run up into the next bar on every fourth bar
    for i in range(8):
        m = root + (12 if i % 2 else 0)
        if bar % 4 == 3 and i >= 6:
            m = root + (5 if i == 6 else 7)
        dur = EIGHTH * 0.85
        sig = triangle(hz(m), dur) * env(int(dur * SR), release=0.02)
        place(mix, sig * 0.42, t0 + i * EIGHTH)
    # Drums: kick on 1, the "and" of 2, and 3; snare on 2 and 4; hats on the eighths; a fill to close each phrase
    for beat in (0, 3, 4):
        place(mix, kick() * 0.55, t0 + beat * EIGHTH)
    for beat in (2, 6):
        place(mix, snare() * 0.22, t0 + beat * EIGHTH)
    for i in range(8):
        place(mix, noise_hit(0.05, 0.012 if i % 2 else 0.02, 6000, 15000) * (0.10 if i % 2 else 0.14), t0 + i * EIGHTH, pan=0.2)
    if bar % 8 == 7:
        for i in range(4):
            place(mix, snare() * (0.12 + 0.03 * i), t0 + (6 + i * 0.5) * EIGHTH)

# Lead echo: a dotted-eighth bounce, ping-ponged
d = int(round(EIGHTH * 1.5 * SR))
echo = np.zeros_like(lead_bus)
echo[1] = np.roll(lead_bus[0], d) * 0.28
echo[0] = np.roll(lead_bus[1], 2 * d) * 0.16
mix += lead_bus + echo

# Master: clear rumble, round off peaks, leave headroom.
mix = sosfilt(butter(1, 30, btype="high", fs=SR, output="sos"), mix, axis=1)
mix = np.tanh(mix / 0.85) * 0.85
mix *= 0.9 / np.abs(mix).max()
out = np.concatenate([mix, mix[:, : int(TAIL * SR)]], axis=1)
path = sys.argv[1] if len(sys.argv) > 1 else "battle.wav"
dither = rng.uniform(-1, 1, out.shape) / 32768
wavfile.write(path, SR, np.round((out + dither).T * 32767).clip(-32768, 32767).astype(np.int16))
print(f"wrote {path}: {LOOP:.3f}s loop + {TAIL:.0f}s tail", file=sys.stderr)
