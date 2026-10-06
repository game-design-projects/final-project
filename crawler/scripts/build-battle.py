#!/usr/bin/env python3
"""Renders the battle music: four bright, driving 8-bit loops, the opposite of the dungeon's dark ambient.

Every loop is the game's own melody (A B C D D D E D E D C C C D D D, first written in A minor over
Am | F | Dm | E), moved into other keys and modes, with its own tempo, groove and lead tone. A fight
picks one at random, and long fights move on to another (public/ambient.js), so no single tune wears out.

  heroic: D major, 124 BPM. Twice in D, then lifted into B-flat and C.
  fury:   E minor (the melody's own minor colour), 132 BPM, four-on-the-floor kick. Through C and D.
  march:  F major, 112 BPM, a reedy narrow-pulse lead over a snare march. Through D minor and B-flat.
  gallop: A major, 120 BPM, galloping kick and a thin lead. Through F and G.
No loop goes faster than 132 BPM.

Chiptune voices, synthesised band-limited (no samples): a pulse-wave lead with a little vibrato and echo,
a pulse arpeggio, a triangle bass and noise/sine drums (scripts/chip.py). Each render is circular, so its
loop point is seamless.

Needs numpy and scipy:  python3 scripts/build-battle.py /tmp     (writes /tmp/battle-<name>.wav)
Then encode each:       afconvert -f m4af -d aac -b 160000 /tmp/battle-heroic.wav public/battle-heroic.m4a
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

from chip import SR, rng, hz, env, pulse, triangle, kick, noise_hit, snare

TAIL = 1.0  # each file repeats its first second at the end, so players can loop inside it
BARS = 16

SCALES = {"maj": [0, 2, 4, 5, 7, 9, 11], "min": [0, 2, 3, 5, 7, 8, 10]}
# The melody as scale degrees from the key's tonic, with its original rhythm: the repeated notes land
# short-short-long. One 4-bar phrase, bar by bar: (start in eighths, length in eighths, degree).
THEME = [
    [(0, 1, 0), (1, 1, 1), (2, 1, 2), (3, 1, 3), (4, 1, 3), (5, 3, 3)],  # A B C D D D (in A)
    [(0, 1, 4), (1, 1, 3), (2, 1, 4), (3, 3, 3), (6, 1, 2), (7, 1, 1)],  # E D E D (and a run down)
    [(0, 1, 2), (1, 1, 2), (2, 6, 2)],  # C C C
    [(0, 1, 3), (1, 1, 3), (2, 4, 3), (6, 1, 4), (7, 1, 5)],  # D D D (and a pickup up)
]
# The same phrase, landing home instead of hanging on the 4th
CADENCE = [(0, 1, 3), (1, 1, 2), (2, 1, 1), (3, 5, 0)]
# Each phrase's chords, one per bar, as (root above the tonic, quality): I IV vi V7 in major, i VI iv V7 in minor
PHRASE_CHORDS = {"maj": [(0, "maj"), (5, "maj"), (9, "min"), (7, "dom7")], "min": [(0, "min"), (8, "maj"), (5, "min"), (7, "dom7")]}
QUALITY = {"maj": [0, 4, 7], "min": [0, 3, 7], "dom7": [4, 7, 10]}

MAX_BPM = 132  # battle music stays at or under this
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "Bb": 10}
VARIANTS = {
    "heroic": dict(bpm=124, keys=[("D", "maj"), ("D", "maj", "home"), ("Bb", "maj"), ("C", "maj")], duty=0.5, arp="up", drums="rock", bass="octave"),
    "fury": dict(bpm=132, keys=[("E", "min"), ("E", "min", "home"), ("C", "maj"), ("D", "maj")], duty=0.5, arp="down", drums="drive", bass="octave"),
    "march": dict(bpm=112, keys=[("F", "maj"), ("F", "maj", "home"), ("D", "min"), ("Bb", "maj")], duty=0.25, arp="broken", drums="march", bass="fifth"),
    "gallop": dict(bpm=120, keys=[("A", "maj"), ("A", "maj", "home"), ("F", "maj"), ("G", "maj")], duty=0.125, arp="updown", drums="gallop", bass="octave"),
}
# Drum grooves, in eighths within a bar
DRUMS = {
    "rock": dict(kicks=(0, 3, 4), snares=(2, 6), hats=8),
    "drive": dict(kicks=(0, 2, 4, 6), snares=(2, 6), hats=16),
    "march": dict(kicks=(0, 4), snares=(2, 6, 7, 7.5), hats=0),
    "gallop": dict(kicks=(0, 1, 1.5, 4, 5, 5.5), snares=(2, 6), hats=8),
}


def chord(tonic_pc, root, quality):
    """(bass note, arpeggio tones) for a chord `root` semitones above the key's tonic."""
    r = (tonic_pc + root) % 12
    return 36 + r, sorted(60 + (r + i) % 12 for i in QUALITY[quality])


def lead_tonic(pc):
    """The key's tonic in the lead's register (G4 to F#5), so every key sits in the same range."""
    return 67 + (pc - 7) % 12


assert all(v["bpm"] <= MAX_BPM for v in VARIANTS.values())


def compose(spec):
    """Bar by bar: (bass root, arpeggio tones, melody notes as (start, length, midi))."""
    bars = []
    for key, mode, *home in spec["keys"]:
        pc = PC[key]
        tonic = lead_tonic(pc)
        scale = SCALES[mode]
        note = lambda deg: tonic + 12 * (deg // 7) + scale[deg % 7]
        for i, theme_bar in enumerate(THEME):
            last = i == 3
            notes = CADENCE if last and home else theme_bar
            root, quality = (0, "min" if mode == "min" else "maj") if last and home else PHRASE_CHORDS[mode][i]
            bass, tones = chord(pc, root, quality)
            bars.append((bass, tones, [(a, b, note(deg)) for a, b, deg in notes]))
    # The very last bar swings back to the first key: its V7
    first = PC[spec["keys"][0][0]]
    bass, tones = chord(first, 7, "dom7")
    bars[-1] = (bass, tones, bars[-1][2])
    assert len(bars) == BARS
    return bars


ARPS = {
    "up": lambda t: t + [t[1] + 12, t[2] + 12, t[0] + 12, t[2], t[1]],
    "down": lambda t: [t[2] + 12, t[1] + 12, t[0] + 12, t[2], t[1], t[0], t[1], t[2]],
    "broken": lambda t: [t[0], t[2], t[1], t[2]],
    "updown": lambda t: [t[0], t[1], t[2], t[0] + 12, t[2], t[1]],
}


def render(spec):
    eighth = 30 / spec["bpm"]
    bar_s = eighth * 8
    n = int(round(bar_s * BARS * SR))
    mix = np.zeros((2, n))
    lead_bus = np.zeros((2, n))
    drums = DRUMS[spec["drums"]]

    def place(buf, sig, start_s, pan=0.0):
        """Add a mono signal into the stereo loop at start_s seconds, wrapping around the end."""
        i = int(round(start_s * SR)) % n
        idx = (i + np.arange(sig.size)) % n
        buf[0, idx] += sig * (1 - pan)
        buf[1, idx] += sig * (1 + pan)

    for bar, (root, tones, notes) in enumerate(compose(spec)):
        t0 = bar * bar_s
        # Lead: pulse wave, a touch of vibrato on longer notes
        for start, length, m in notes:
            dur = length * eighth * 0.92
            sig = pulse(hz(m), dur, spec["duty"], vibrato=0.004 if length >= 2 else 0) * env(int(dur * SR), release=0.04)
            place(lead_bus, sig * 0.20, t0 + start * eighth, pan=-0.1)
        # Arpeggio: chord tones up an octave in sixteenths, 25% pulse, quiet and a little to the right
        seq = ARPS[spec["arp"]](tones)
        for i in range(16):
            dur = eighth / 2 * 0.8
            sig = pulse(hz(seq[i % len(seq)] + 12), dur, 0.25) * env(int(dur * SR), release=0.015, decay=0.05, sustain=0.4)
            place(mix, sig * 0.07, t0 + i * eighth / 2, pan=0.35)
        # Bass: triangle eighths (octave pump, or root and fifth), with a run up into each new phrase
        for i in range(8):
            if spec["bass"] == "octave":
                m = root + (12 if i % 2 else 0)
            else:
                m = root + (7 if i % 4 == 2 else 0) + (12 if i % 4 == 3 else 0)
            if bar % 4 == 3 and i >= 6:
                m = root + (5 if i == 6 else 7)
            dur = eighth * 0.85
            place(mix, triangle(hz(m), dur) * env(int(dur * SR), release=0.02) * 0.42, t0 + i * eighth)
        # Drums, and a snare fill to close every second phrase
        for beat in drums["kicks"]:
            place(mix, kick() * 0.55, t0 + beat * eighth)
        for beat in drums["snares"]:
            place(mix, snare() * (0.22 if beat == int(beat) and beat in (2, 6) else 0.1), t0 + beat * eighth)
        for i in range(drums["hats"]):
            step = 8 / drums["hats"]
            loud = 0.14 if i % 2 == 0 else 0.09
            place(mix, noise_hit(0.05, 0.012 if i % 2 else 0.02, 6000, 15000) * loud * (0.8 if drums["hats"] > 8 else 1), t0 + i * step * eighth, pan=0.2)
        if bar % 8 == 7:
            for i in range(4):
                place(mix, snare() * (0.12 + 0.03 * i), t0 + (6 + i * 0.5) * eighth)

    # Lead echo: a dotted-eighth bounce, ping-ponged
    d = int(round(eighth * 1.5 * SR))
    echo = np.zeros_like(lead_bus)
    echo[1] = np.roll(lead_bus[0], d) * 0.28
    echo[0] = np.roll(lead_bus[1], 2 * d) * 0.16
    mix += lead_bus + echo

    # Master: clear rumble, round off peaks, leave headroom (every variant peaks at the same level).
    mix = sosfilt(butter(1, 30, btype="high", fs=SR, output="sos"), mix, axis=1)
    mix = np.tanh(mix / 0.85) * 0.85
    mix *= 0.9 / np.abs(mix).max()
    return mix, bar_s * BARS


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    for name, spec in VARIANTS.items():
        mix, loop = render(spec)
        out = np.concatenate([mix, mix[:, : int(TAIL * SR)]], axis=1)
        dither = rng.uniform(-1, 1, out.shape) / 32768
        path = f"{out_dir}/battle-{name}.wav"
        wavfile.write(path, SR, np.round((out + dither).T * 32767).clip(-32768, 32767).astype(np.int16))
        print(f"wrote {path}: {loop:.3f}s loop + {TAIL:.0f}s tail ({spec['bpm']} BPM)", file=sys.stderr)
