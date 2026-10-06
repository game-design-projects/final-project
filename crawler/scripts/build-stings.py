#!/usr/bin/env python3
"""Renders the short one-shot music cues ("stings") for good moments, by the same baroque band in the
same hall as the dungeon and battle music.

Both quote the opening of the game's melody (A B C D D D ..., here in D major: D E F# G G G) and land
on a clear perfect cadence, IV6 - V7 - I, with tubular bells ringing on the final D major chord:

    eighth/16th  0   1   2    3   4   5-6  7   8...
    melody       D5  E5  F#5  G5  G5  G5-  A5  D6 (held, bells)
    chord        D   .   .    .   G/B .    A7  D
    bass         D3              B2       A2  D2      (falling, contrary to the rising melody)

  fanfare: going down the stairs to a new floor. In eighths at 104 BPM: organ and strings in octaves,
           a kettle-drum roll into the landing, bells. About 3.9 s.
  victory: winning a fight. The same shape twice as fast (16ths at 120 BPM), a harpsichord flourish up
           into the landing, bells. About 2.3 s.

Needs numpy and scipy:  python3 crawler/scripts/build-stings.py /tmp   (writes /tmp/fanfare.wav and /tmp/victory.wav)
Then encode each:       afconvert -f m4af -d aac -b 160000 /tmp/fanfare.wav crawler/public/fanfare.m4a
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sampler import BATTLE_RMS_DB, INSTRUMENTS, Score, check_outer_voices, highpass, log_samples, lowpass, master, midi, mix, name, report, timpani, write  # noqa: E402

INSTRUMENTS["organ_lead"] = dict(INSTRUMENTS["organ"], attack=0.015, release=0.2)
INSTRUMENTS["strings_lead"] = dict(INSTRUMENTS["strings"], attack=0.025, release=0.3, offset=0.3)

# (start, length) in steps, note
MELODY = [(0, 1, "D5"), (1, 1, "E5"), (2, 1, "F#5"), (3, 1, "G5"), (4, 1, "G5"), (5, 2, "G5"), (7, 1, "A5"), (8, 6, "D6")]
CHORDS = [(0, 4, ["D4", "F#4", "A4"], "D3", "D"), (4, 3, ["D4", "G4", "B4"], "B2", "G/B"), (7, 1, ["C#4", "E4", "G4", "A4"], "A2", "A7"), (8, 6, ["D4", "F#4", "A4", "D5"], "D2", "D")]

STINGS = {
    "fanfare": dict(step=60 / 104 / 2, length=3.9, fade=0.9, roll=(4, 8), flourish=False, choir=True),
    "victory": dict(step=60 / 120 / 4, length=2.3, fade=0.7, roll=None, flourish=True, choir=False),
}


def render(spec):
    step = spec["step"]
    score = Score(spec["length"], loop=False, pad=4.0)
    pairs = []
    for start, length, note in MELODY:
        t = start * step
        dur = length * step * (0.8 if length == 1 and start in (3, 4) else 0.95)  # the repeated Gs re-strike
        if start == 8:
            dur = 1.6
        score.note("lead", "organ_lead", note, t, dur, vel=1.0 if start in (0, 8) else 0.9)
        score.note("lead", "organ_lead", midi(note) - 12, t, dur, vel=0.85)
        score.note("lead strings", "strings_lead", note, t, dur, vel=0.95, pan=0.15)
        pairs.append((t, midi(note), None))
    for start, length, tones, bass, _label in CHORDS:
        t = start * step
        dur = 1.8 if start == 8 else length * step * 0.97
        for m in tones:
            score.note("organ", "organ", m, t, dur, vel=0.75, pan=-0.2)
            score.note("strings", "strings", m, t, dur, vel=0.7, pan=0.25)
        score.note("bass", "strings", bass, t, dur, vel=0.9)
        score.note("bass", "strings", midi(bass) - 12 if midi(bass) - 12 >= 36 else midi(bass), t, dur, vel=0.7)
        if spec["choir"] and start == 8:
            for m in tones:
                score.note("choir", "choir", m, t, 1.8, vel=0.8, pan=0.1)
        pairs.append((t, None, midi(bass)))
    land = 8 * step
    score.note("bells", "bells", "D5", land, 2.0, vel=0.9, pan=0.3)
    score.note("bells", "bells", "A4", land + 0.01, 2.0, vel=0.6, pan=-0.3)
    score.note("bells", "bells", "D4", land + 0.02, 2.0, vel=0.7, pan=0.0)
    score.add("timpani", timpani(midi("D2"), 1.0), land, pan=0.1)
    score.add("timpani", timpani(midi("A2"), 0.7), 0.0, pan=0.1)
    if spec["roll"]:
        a, b = spec["roll"]
        n = int((b - a) * 4)  # 32nd notes across the roll
        for k in range(n):
            score.add("timpani", timpani(midi("A2"), 0.3 + 0.5 * k / n, ring=0.8), (a + k / 4) * step, pan=0.1)
    if spec["flourish"]:
        run = ["D4", "F#4", "A4", "D5", "F#5", "A5"]
        for k, m in enumerate(run):
            score.note("harpsichord", "harpsichord", m, land - (len(run) - k) * 0.035, 0.6, vel=0.6 + 0.06 * k, pan=0.35, jitter=0)
        score.note("harpsichord", "harpsichord", "D6", land, 1.2, vel=0.9, pan=0.35)
    pairs.sort(key=lambda p: p[0])
    merged, mel, bas = [], None, None
    for t, m, b in pairs:
        mel, bas = (m if m is not None else mel), (b if b is not None else bas)
        merged.append((t, mel, bas))
    return score, merged


LEVELS = {"lead": 0.0, "lead strings": -3.0, "organ": -6.0, "strings": -6.0, "bass": -4.0, "choir": -6.0, "bells": -4.0, "timpani": -6.0, "harpsichord": -4.0}
SENDS = {"lead": 0.35, "lead strings": 0.35, "organ": 0.35, "strings": 0.35, "bass": 0.2, "choir": 0.5, "bells": 0.6, "timpani": 0.3, "harpsichord": 0.3}
EQ = {"organ": lowpass(3500, 1), "lead": lowpass(5000, 1), "bass": highpass(38, 2)}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    for sname, spec in STINGS.items():
        score, pairs = render(spec)
        print(f"{sname}: D major, step {spec['step']:.3f}s, {spec['length']}s with a {spec['fade']}s fade, {score.count} notes", file=sys.stderr)
        print("    melody " + " ".join(name(midi(n)) for _, _, n in MELODY) + "   chords " + " | ".join(c[4] for c in CHORDS), file=sys.stderr)
        check_outer_voices(sname, pairs)
        x = mix(score, LEVELS, SENDS, eq=EQ, wet=0.8)
        x, hits = master(x, BATTLE_RMS_DB, length=spec["length"], fade=spec["fade"])
        report(sname, x, hits, loop=False)
        path = os.path.join(out_dir, f"{sname}.wav")
        write(path, x, loop=False)
        print(f"wrote {path}: {x.shape[1] / 44100:.2f}s", file=sys.stderr)
    log_samples()


if __name__ == "__main__":
    main()
