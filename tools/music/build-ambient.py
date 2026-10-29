#!/usr/bin/env python3
"""Renders the dungeon's exploring music: "Passacaglia of the Deep", a slow baroque passacaglia in D minor.

Form: five variations on an eight-bar ground bass, 3/4 at 64 BPM, 40 bars = 112.5 s, one seamless loop.
The ground starts with the lament bass (D C Bb A, the falling fourth of every baroque lament), then
Bb A D A, ending on the dominant so each variation falls back into the next and the last into the first.

The game's melody (A B C D D D E D E D C C C D D D, written in A minor over Am | F | Dm | E) is set in
D minor over the ground, note for note, with its short-short-long repeats:

    bar  bass  chord    melody (eighths)            the owner's harmony, moved to D minor
     1   D     Dm       D  E  F   (quarters)        Am  -> Dm
     2   C     C        G G G--                     (C, the modal flat-seventh chord)
     3   Bb    Bb       A G A G                     F   -> Bb, A and G as 7-6 colour over it
     4   A     F/A      F F F--                     Dm  -> F/A (the same notes, F on top)
     5   Bb    Gm/Bb    G G G--                     E   -> Gm/Bb, then
     6   A     A7       A G F E                     a cadence: E D C B -> A G F E
     7   D     Dm       D---
     8   A     Asus4 A  (rest: the harpsichord fills)

Variations (the melody comes and goes on a different voice each time):
  I   the ground alone: soft organ chords, low strings, harpsichord broken chords in quarters, a far bell.
  II  the melody on music box, high, over harpsichord arpeggios in eighths.
  III the melody on the strings, the harpsichord drops to a low continuo; the choir starts to rise.
  IV  the fullest: choir swelling bar by bar, the melody on harpsichord doubled by music box an octave
      up, a strings counter-line falling in tenths with the bass, organ pedal; a bell.
  V   it thins out: the melody's first bars on high strings, then only organ, ground and harpsichord,
      back to the quiet of variation I.

Instruments are real samples (scripts/sampler.py: MusyngKite harpsichord, church organ, string
ensemble, choir aahs, music box, tubular bells), all in the same stone hall as the fights and fanfares.
No synth pads, no sub drones.

Needs numpy and scipy:  python3 tools/music/build-ambient.py /tmp      (writes /tmp/ambient.wav)
     (or a .wav path)
Then encode:            tools/music/to_ogg.sh loop /tmp/ambient.wav assets/audio/ambient.ogg 112.5
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sampler import EXPLORE_RMS_DB, INSTRUMENTS, Score, check_outer_voices, highpass, log_samples, lowpass, master, midi, mix, name, report, voice, write  # noqa: E402

BPM = 64
BEAT = 60 / BPM
EIGHTH = BEAT / 2
BAR = 3 * BEAT
BARS = 40
LOOP = BAR * BARS  # 112.5 s; src/audio/ambient.gd TRACKS.explore.loopSeconds must match

GROUND = ["D3", "C3", "Bb2", "A2", "Bb2", "A2", "D3", "A2"]
# Per bar: (beat, chord tones root first, label)
HARMONY = [
    [(0, "D F A", "Dm")],
    [(0, "C E G", "C")],
    [(0, "Bb D F", "Bb")],
    [(0, "F A C", "F/A")],
    [(0, "G Bb D", "Gm/Bb")],
    [(0, "A C# E G", "A7")],
    [(0, "D F A", "Dm")],
    [(0, "A D E", "Asus4"), (2, "A C# E", "A")],
]
# The melody, per bar: (start in eighths, length in eighths, note)
MELODY = [
    [(0, 2, "D4"), (2, 2, "E4"), (4, 2, "F4")],
    [(0, 1, "G4"), (1, 1, "G4"), (2, 4, "G4")],
    [(0, 1, "A4"), (1, 1, "G4"), (2, 2, "A4"), (4, 2, "G4")],
    [(0, 1, "F4"), (1, 1, "F4"), (2, 4, "F4")],
    [(0, 1, "G4"), (1, 1, "G4"), (2, 4, "G4")],
    [(0, 1, "A4"), (1, 1, "G4"), (2, 2, "F4"), (4, 2, "E4")],
    [(0, 6, "D4")],
    [],
]
# Variation IV's strings counter-line: tenths over the ground, half + quarter
COUNTER = ["F4", "E4", "D4", "C4", "D4", "C#4", "D4", "C#4"]

PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11}
DM = (10, 3)  # spell Bb and Eb flat, C# sharp
INSTRUMENTS["choir_swell"] = dict(INSTRUMENTS["choir"], attack=0.9, release=1.4)
INSTRUMENTS["organ_soft"] = dict(INSTRUMENTS["organ"], attack=0.35, release=0.8)

# name: (melody voice, melody octave shift, dynamics 0..1, harpsichord figure and range, extras)
VARIATIONS = [
    dict(title="I   the ground", melody=None, dyn=0.78, harp="pulse", harp_range=(57, 72), organ=0.55, choir=None, bell={0: "D4", 4: "A3"}),
    dict(title="II  music box", melody=("music_box", 12, 0.75), dyn=0.68, harp="arp", harp_range=(57, 72), organ=0.4, choir=None, bell={}),
    dict(title="III strings", melody=("strings", 0, 0.8), dyn=0.8, harp="arp", harp_range=(45, 59), organ=0.5, choir=[0, 0, 0, 0, 0, 0, 0.45, 0.6], bell={}),
    dict(title="IV  choir", melody=("harpsichord", 12, 0.9), dyn=0.84, harp=None, harp_range=None, organ=0.0, choir=[0.7, 0.75, 0.8, 0.85, 0.85, 0.8, 0.75, 0.65], bell={0: "D4"}, counter=True, pedal=True),
    dict(title="V   dissolving", melody=("strings", 12, 0.62), melody_bars=3, dyn=0.74, harp="pulse", harp_range=(57, 72), organ=0.55, choir=None, bell={4: "A3"}),
]
assert len(VARIATIONS) * len(GROUND) == BARS


def pcs(tones):
    return [PC[t] for t in tones.split()]


def chord_at(bar, beat):
    current = HARMONY[bar][0]
    for c in HARMONY[bar]:
        if c[0] <= beat:
            current = c
    return current


def compose(score):
    organ_prev, harp_prev, choir_prev = None, None, None
    pairs = []  # (time, melody, bass) for the outer-voice check
    table = []
    for v, var in enumerate(VARIATIONS):
        dyn = var["dyn"]
        for b in range(len(GROUND)):
            bar = v * len(GROUND) + b
            t0 = bar * BAR
            bass = midi(GROUND[b])
            # Ground: low strings in octaves, legato
            score.note("ground", "strings", bass, t0, BAR * 0.97, vel=0.72 * dyn)
            score.note("ground", "strings", bass - 12, t0, BAR * 0.97, vel=0.62 * dyn)
            if var.get("pedal"):
                score.note("organ", "organ_soft", bass - 12, t0, BAR * 0.98, vel=0.5)
            # Chords
            for k, (beat, tones, _label) in enumerate(HARMONY[b]):
                start = t0 + beat * BEAT
                end = t0 + (HARMONY[b][k + 1][0] * BEAT if k + 1 < len(HARMONY[b]) else BAR)
                organ_prev = voice(pcs(tones), organ_prev, 50, 65)
                if var["organ"]:
                    for m in organ_prev:
                        score.note("organ", "organ_soft", m, start, (end - start) * 0.99, vel=var["organ"] * dyn, pan=-0.25)
                if var["choir"] and var["choir"][b]:
                    choir_prev = voice(pcs(tones), choir_prev, 55, 69, n=3)
                    for m in choir_prev:
                        score.note("choir", "choir_swell", m, start, (end - start) * 0.98, vel=var["choir"][b], pan=0.2)
            # Harpsichord figuration
            if var["harp"]:
                lo, hi = var["harp_range"]
                steps = 3 if var["harp"] == "pulse" else 6
                for s in range(steps):
                    beat = s * 3 / steps
                    _, tones, _ = chord_at(b, beat)
                    harp_prev = voice(pcs(tones), harp_prev, lo, hi)
                    fig = [harp_prev[0], harp_prev[1], harp_prev[2], harp_prev[0] + 12, harp_prev[2], harp_prev[1]] if steps == 6 else harp_prev
                    m = fig[s]
                    length = BEAT if steps == 3 else EIGHTH
                    accent = 1.0 if s == 0 else 0.85
                    score.note("harpsichord", "harpsichord", m, t0 + beat * BEAT, length * 0.95, vel=0.7 * dyn * accent, pan=0.3)
            # Melody
            mel = var["melody"]
            notes = []
            if mel and b < var.get("melody_bars", 8):
                inst, octave, vel = mel
                for start, length, note in MELODY[b]:
                    m = midi(note) + octave
                    legato = 0.98 if inst in ("strings", "choir") else 0.9
                    if inst == "strings" and length == 1:
                        legato = 0.8  # repeated notes need a breath to be heard as repeats
                    score.note(f"lead {inst}", inst, m, t0 + start * EIGHTH, length * EIGHTH * legato, vel=vel * (1.0 if start == 0 else 0.92), pan=0.0)
                    if var["title"].startswith("IV"):
                        score.note("lead sparkle", "music_box", m + 12, t0 + start * EIGHTH, length * EIGHTH, vel=0.55, pan=0.15)
                    notes.append((t0 + start * EIGHTH, m))
            if var.get("counter"):
                c = midi(COUNTER[b])
                score.note("counter", "strings", c, t0, BEAT * 2 * 0.97, vel=0.55)
                score.note("counter", "strings", c, t0 + 2 * BEAT, BEAT * 0.95, vel=0.48)
            if b in var["bell"]:
                score.note("bells", "bells", var["bell"][b], t0 + 0.02, BAR, vel=0.6)
            # outer voices: every melody onset, and every bar line, against the ground
            if notes:
                pairs.append((t0, notes[0][1], bass))
                pairs += [(t, m, bass) for t, m in notes[1:]]
            else:
                pairs.append((t0, None, bass))
            labels = " ".join(c[2] for c in HARMONY[b])
            mel_txt = " ".join(name(m, DM) for _, m in notes) if notes else "-"
            table.append(f"    {bar + 1:2d} {name(bass, DM):4s} {labels:10s} organ {'/'.join(name(m, DM) for m in organ_prev):12s} melody {mel_txt}")
    return pairs, table


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "ambient.wav"
    if os.path.isdir(out):
        out = os.path.join(out, "ambient.wav")
    score = Score(LOOP, loop=True)
    pairs, table = compose(score)
    print(f"explore: passacaglia in D minor, 3/4 at {BPM} BPM, {BARS} bars = {LOOP:.3f}s, {score.count} notes", file=sys.stderr)
    for v, var in enumerate(VARIATIONS):
        print(f"  variation {var['title']}", file=sys.stderr)
        print("\n".join(table[v * 8 : v * 8 + 8]), file=sys.stderr)
    check_outer_voices("explore", pairs)
    log_samples()
    levels = {"ground": -3.0, "organ": -1.0, "harpsichord": -1.0, "bells": -12.0, "lead music_box": 0.0, "lead strings": 0.0,
              "lead harpsichord": 2.0, "lead sparkle": -6.0, "counter": -4.0, "choir": -8.0}
    sends = {"ground": 0.35, "organ": 0.45, "harpsichord": 0.4, "bells": 1.0, "lead music_box": 0.5, "lead strings": 0.45,
             "lead harpsichord": 0.4, "lead sparkle": 0.6, "counter": 0.4, "choir": 0.6}
    eq = {"organ": lowpass(2400, 1), "bells": lowpass(2200, 2), "ground": highpass(40, 2), "choir": lowpass(5000, 1)}
    sections = [(v["title"][:3].strip(), i * 8 * BAR, (i + 1) * 8 * BAR) for i, v in enumerate(VARIATIONS)]
    x = mix(score, levels, sends, eq=eq, wet=0.9, sections=sections)
    x, hits = master(x, EXPLORE_RMS_DB)
    report("explore", x, hits, loop=True)
    write(out, x, loop=True)
    print(f"wrote {out}: {LOOP:.3f}s loop + 1s tail", file=sys.stderr)


if __name__ == "__main__":
    main()
