#!/usr/bin/env python3
"""Renders the battle music: four baroque battle loops in the spirit of a toccata or a Wizardry battle
theme, played by the dungeon's own band (harpsichord, church organ, strings, choir) plus kettle drums.

Every loop is 16 bars of 4/4: the game's melody (A B C D D D E D E D C C C D D D, written in A minor
over Am | F | Dm | E) four times, as four 4-bar phrases:

  P1  home key, minor: the melody on the variant's lead, ending on the dominant (open).
  P2  home key, minor: fuller (marcato strings, more drums); the melody comes home (D C B A, a full
      cadence) and a 16th-note string run climbs into...
  P3  the lift: the relative major, with the melody on a second lead (heroic, brighter).
  P4  home key, minor, tutti: both leads in octaves, kettle-drum roll; its dominant falls back to P1.

The melody keeps the owner's rhythm (the repeated notes short-short-long), harmonised baroque style,
two chords a bar:
  minor (Am):  | i  iv/i | VI  VI | iv7  iv7/3rd | V7  V7/3rd |  (home cadence: | V7  i |)
               | Am Dm/A | F   F  | Dm7  Dm7/F   | E7  E7/G#  |
  major (C):   | I  IV/I | IV  IV | vi   vi/5th  | V7  V7/3rd |
The E D E D over F is a chain of 7-6 suspensions; C C C over Dm7 and D D D over E7 are sevenths.
Two-note pickups climb into each phrase by the melodic minor (F# G# -> A over E7).

The four characters (each <= 132 BPM, the owner's cap; a fight picks one at random):
  toccata  D minor, 132 BPM. Organ lead in octaves; harpsichord 16ths against a pedal note (Bach's
           toccata figure); octave-pumping bass; strings marcato on 2 and 4. Lift: F major, strings.
  charge   A minor, 126 BPM. Strings lead in octaves; harpsichord arpeggios in 16ths; organ chords;
           driving kettle drums. Lift: C major, choir.
  crusade  G minor, 112 BPM. Choir lead in octaves, a hymn at a march; full organ; strings chugging
           eighths; kettle drums and a tabor in march rhythm. Lift: B-flat major, strings.
  gallop   E minor, 120 BPM. Harpsichord lead in octaves; strings and kettle drums in a galloping
           8th-16th-16th; tabor. Lift: G major, organ.

Sampled instruments come from scripts/sampler.py (MusyngKite); kettle drums and tabor are synthesised
there. All four play in the same hall as the dungeon music. Each render is circular, so the loop
point is seamless; each file is the loop plus a repeat of its first second.

Needs numpy and scipy:  python3 tools/music/build-battle.py /tmp    (writes /tmp/battle-<name>.wav)
Then encode each:       tools/music/to_ogg.sh loop /tmp/battle-toccata.wav assets/audio/battle-toccata.ogg 3840/132
Loop length = 16 bars x 4 beats x 60 / BPM = 3840 / BPM seconds: src/audio/ambient.gd TRACKS.battle.variants.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sampler import BATTLE_RMS_DB, INSTRUMENTS, Score, check_outer_voices, highpass, log_samples, lowpass, master, midi, mix, name, report, tabor, timpani, voice, write  # noqa: E402

BARS = 16
MAX_BPM = 132  # battle music stays at or under this

SCALES = {"maj": [0, 2, 4, 5, 7, 9, 11], "min": [0, 2, 3, 5, 7, 8, 10]}
# The melody, one 4-bar phrase, as (start in eighths, length in eighths, scale degree from the tonic)
THEME = [
    [(0, 1, 0), (1, 1, 1), (2, 1, 2), (3, 1, 3), (4, 1, 3), (5, 3, 3)],  # A B C D D D
    [(0, 1, 4), (1, 1, 3), (2, 1, 4), (3, 3, 3), (6, 1, 2), (7, 1, 1)],  # E D E D (C B)
    [(0, 1, 2), (1, 1, 2), (2, 6, 2)],  # C C C
    [(0, 1, 3), (1, 1, 3), (2, 4, 3)],  # D D D (+ a two-note pickup into the next phrase)
]
CADENCE = [(0, 1, 3), (1, 1, 2), (2, 1, 1), (3, 5, 0)]  # D C B A: the phrase comes home
# Harmony, two chords a bar: (root above the tonic, quality, bass above the tonic or None = root)
PLAN = {
    "min": [[(0, "min", None), (5, "min", 0)], [(8, "maj", None), (8, "maj", None)], [(5, "min7", None), (5, "min7", 8)], [(7, "dom7", None), (7, "dom7", 11)]],
    "maj": [[(0, "maj", None), (5, "maj", 0)], [(5, "maj", None), (5, "maj", None)], [(9, "min", None), (9, "min", 4)], [(7, "dom7", None), (7, "dom7", 11)]],
}
HOME = [(7, "dom7", None), (0, "min", None)]
QUALITY = {"min": [0, 3, 7], "maj": [0, 4, 7], "min7": [0, 3, 7, 10], "dom7": [0, 4, 7, 10]}
LABEL = {"min": "m", "maj": "", "min7": "m7", "dom7": "7"}
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "Bb": 10}

INSTRUMENTS["choir_lead"] = dict(INSTRUMENTS["choir"], attack=0.035, release=0.25)
INSTRUMENTS["organ_lead"] = dict(INSTRUMENTS["organ"], attack=0.015, release=0.12)
INSTRUMENTS["strings_lead"] = dict(INSTRUMENTS["strings"], attack=0.025, release=0.15, offset=0.3)

# lead / lift / tutti: [(instrument, octave shift)]; tonic: the melody's tonic in the lead's register
VARIANTS = {
    "toccata": dict(bpm=132, key="D", tonic="D5", flats=(10, 3), lead=[("organ_lead", 0), ("organ_lead", -12)], lift=[("strings_lead", 0), ("strings_lead", -12)],
                    tutti=[("organ_lead", 0), ("organ_lead", -12), ("strings_lead", -12)], harp="toccata", marcato=True, chug=None, bass="pump", organ="lift", timp="toccata", tabor=None),
    "charge": dict(bpm=126, key="A", tonic="A4", flats=(), lead=[("strings_lead", 0), ("strings_lead", 12)], lift=[("choir_lead", 0), ("choir_lead", -12)],
                   tutti=[("strings_lead", 0), ("strings_lead", 12), ("choir_lead", 0)], harp="arp", marcato=False, chug=None, bass="pump", organ="all", timp="charge", tabor=None),
    "crusade": dict(bpm=112, key="G", tonic="G4", flats=(10, 3), lead=[("choir_lead", 0), ("choir_lead", -12)], lift=[("strings_lead", 0), ("strings_lead", 12)],
                    tutti=[("choir_lead", 0), ("choir_lead", -12), ("strings_lead", 12)], harp="broken", marcato=False, chug="eighths", bass="pedal", organ="all", timp="march", tabor="march"),
    "gallop": dict(bpm=120, key="E", tonic="E5", flats=(), lead=[("harpsichord", 0), ("harpsichord", -12)], lift=[("organ_lead", 0), ("organ_lead", -12)],
                   tutti=[("harpsichord", 0), ("harpsichord", -12), ("organ_lead", -12)], harp=None, marcato=False, chug="gallop", bass="gallop", organ="soft", timp="gallop", tabor="gallop"),
}
# Kettle drums, per bar: (16th step, "T" tonic drum or "D" dominant drum, velocity). A hit whose drum
# isn't in the chord swaps to the other drum, so the drums always agree with the harmony.
TIMP = {
    "toccata": [(0, "T", 1.0), (8, "D", 0.8)],
    "charge": [(0, "T", 1.0), (4, "D", 0.65), (8, "T", 0.85), (10, "T", 0.55), (12, "D", 0.7)],
    "march": [(0, "T", 1.0), (6, "T", 0.55), (8, "D", 0.85), (12, "T", 0.65)],
    "gallop": [(0, "T", 1.0), (3, "T", 0.5), (4, "D", 0.65), (8, "T", 0.9), (11, "T", 0.5), (12, "D", 0.65)],
}
TABOR = {
    "march": [(0, 1.0), (4, 0.55), (6, 0.45), (8, 0.85), (12, 0.55), (14, 0.45), (15, 0.4)],
    "gallop": [(s + b, v) for b in (0, 4, 8, 12) for s, v in ((0, 0.9), (2, 0.45), (3, 0.55))],
}
# Harpsichord 16th figures over half a bar; indexes into the chord voicing (0 low .. 2 high), "p" = pedal
HARP = {
    "toccata": ["p", 2, 1, 2, "p", 2, 1, 2],
    "arp": [0, 1, 2, 3, 2, 1, 0, 1],
    "broken": [0, 2, 1, 2],  # eighths
}
assert all(v["bpm"] <= MAX_BPM for v in VARIANTS.values())


def phrases(spec):
    home = PC[spec["key"]]
    rel = (home + 3) % 12
    t = midi(spec["tonic"])
    return [
        dict(pc=home, mode="min", tonic=t, lead=spec["lead"], end="open", dyn=0.82, run=False),
        dict(pc=home, mode="min", tonic=t, lead=spec["lead"], end="home", dyn=0.92, run=True),
        dict(pc=rel, mode="maj", tonic=t + 3, lead=spec["lift"], end="open", dyn=0.92, run=False),
        dict(pc=home, mode="min", tonic=t, lead=spec["tutti"], end="open", dyn=1.0, run=False),
    ]


def degree(ph, d):
    return ph["tonic"] + 12 * (d // 7) + SCALES[ph["mode"]][d % 7]


def below(ph, target, steps):
    """The `steps` scale notes of phrase ph's key just below `target`, rising. In minor, a line rising
    into the tonic takes the melodic minor's raised sixth and seventh (F# G# -> A), never the
    augmented second of the harmonic minor."""
    scale = set((ph["pc"] + s) % 12 for s in SCALES[ph["mode"]])
    if ph["mode"] == "min" and target % 12 == ph["pc"]:
        scale = (scale - {(ph["pc"] + 8) % 12, (ph["pc"] + 10) % 12}) | {(ph["pc"] + 9) % 12, (ph["pc"] + 11) % 12}
    out, m = [], target - 1
    while len(out) < steps:
        if m % 12 in scale:
            out.append(m)
        m -= 1
    return out[::-1]


def compose(spec):
    """Bar by bar: [(chords as (start step, pcs root first, bass pc, label)), melody notes (start
    eighth, length eighths, midi), run notes] for all 16 bars."""
    phs = phrases(spec)
    bars = []
    for p, ph in enumerate(phs):
        nxt = phs[(p + 1) % 4]
        for i in range(4):
            plan = PLAN[ph["mode"]][i]
            if i == 3 and ph["end"] == "home":
                plan = HOME
            chords = []
            for half, (root, q, bass) in enumerate(plan):
                pcs = [(ph["pc"] + root + iv) % 12 for iv in QUALITY[q]]
                bpc = (ph["pc"] + (root if bass is None else bass)) % 12
                lab = name(ph["pc"] + root + 60, spec["flats"])[:-1] + LABEL[q] + ("" if bass is None else "/" + name(bpc + 60, spec["flats"])[:-1])
                chords.append((half * 8, pcs, bpc, lab))
            if i == 3 and ph["end"] == "home":
                notes = [(a, b, degree(ph, d)) for a, b, d in CADENCE]
            else:
                notes = [(a, b, degree(ph, d)) for a, b, d in THEME[i]]
            run = []
            if i == 3 and ph["end"] == "open":
                notes += [(6 + k, 1, m) for k, m in enumerate(below(ph, degree(nxt, 0), 2))]
            if i == 3 and ph["run"]:
                run = below(ph, degree(nxt, 0), 8)
            bars.append(dict(ph=ph, chords=chords, notes=notes, run=run, phrase=p, i=i))
    assert len(bars) == BARS
    return bars


def render(vname, spec):
    bpm = spec["bpm"]
    six = 15 / bpm  # a sixteenth, in seconds
    loop = BARS * 16 * six
    score = Score(loop, loop=True)
    bars = compose(spec)
    t_lead = midi(spec["tonic"])
    T = 36 + (PC[spec["key"]] - 36) % 12  # the tonic drum, C2..B2
    T = T if T >= 38 else T + 12  # keep the drums D2..C#3
    drums = {"T": T, "D": T + 7 if T + 7 <= 50 else T - 5}
    prev = {}
    pairs, table = [], []

    def vo(key, pcs, lo, hi, n=3):
        prev[key] = voice(pcs, prev.get(key), lo, hi, n)
        return prev[key]

    for b, bar in enumerate(bars):
        ph, dyn = bar["ph"], bar["ph"]["dyn"]
        t0 = b * 16 * six
        p = bar["phrase"]
        organ_on = spec["organ"] == "all" or spec["organ"] == "soft" or (spec["organ"] == "lift" and p == 2)
        for step, pcs, bpc, _label in bar["chords"]:
            ts = t0 + step * six
            half = 8 * six
            bass = 36 + (bpc - 36) % 12  # C2..B2
            # Bass
            if spec["bass"] == "pump":
                for e in range(4):
                    m = bass + (12 if e % 2 else 0)
                    score.note("bass", "marcato", m, ts + e * 2 * six, 2 * six * 0.8, vel=(0.95 if e == 0 else 0.8) * dyn)
            elif spec["bass"] == "pedal":
                score.note("bass", "strings", bass, ts, half * 0.97, vel=0.85 * dyn)
                score.note("bass", "organ", bass, ts, half * 0.98, vel=0.6 * dyn)
            elif spec["bass"] == "gallop":
                for beat in range(2):
                    for s, ln, v in ((0, 2, 0.95), (2, 1, 0.7), (3, 1, 0.8)):
                        score.note("bass", "marcato", bass, ts + (beat * 4 + s) * six, ln * six * 0.8, vel=v * dyn)
            pairs.append((ts, None, bass))
            # Organ chords
            if organ_on:
                n = 4 if spec["organ"] == "all" and spec["bass"] == "pedal" else 3
                vel = 0.5 if spec["organ"] == "soft" else 0.7
                for m in vo("organ", pcs, t_lead - 19, t_lead - 5, n):
                    score.note("organ", "organ", m, ts, half * 0.98, vel=vel * dyn, pan=-0.2)
            # Harpsichord figuration
            if spec["harp"]:
                fig = HARP[spec["harp"]]
                v = vo("harp", pcs, t_lead - 14, t_lead - 1)
                ext = v + [v[0] + 12]
                ped = bass + 12 * ((v[0] - bass) // 12)
                ped = ped if ped < v[0] else ped - 12
                step_len = 8 // len(fig)
                for s, idx in enumerate(fig):
                    m = ped if idx == "p" else ext[idx]
                    score.note("harpsichord", "harpsichord", m, ts + s * step_len * six, step_len * six * 0.9, vel=(0.9 if s % 4 == 0 else 0.75) * dyn, pan=0.35, jitter=0.003)
            # Strings marcato on beats 2 and 4 (from P2 on)
            if spec["marcato"] and p in (1, 3):
                for m in vo("marc", pcs, t_lead - 14, t_lead - 3):
                    score.note("marcato", "marcato", m, ts + 4 * six, 1.6 * six, vel=0.85 * dyn, pan=-0.3)
            # Strings chugging
            if spec["chug"] == "eighths":
                v = vo("chug", pcs, t_lead - 17, t_lead - 5, 2)
                for e in range(4):
                    for m in v:
                        score.note("chug", "marcato", m, ts + e * 2 * six, 2 * six * 0.6, vel=(0.9 if e % 2 == 0 else 0.7) * dyn, pan=-0.3, jitter=0.003)
            elif spec["chug"] == "gallop":
                v = [bass + 12, bass + 19]
                for beat in range(2):
                    for s, ln, vv in ((0, 2, 0.9), (2, 1, 0.6), (3, 1, 0.7)):
                        for m in v:
                            score.note("chug", "marcato", m, ts + (beat * 4 + s) * six, ln * six * 0.75, vel=vv * dyn, pan=-0.3, jitter=0.003)
        # Melody, on every lead of this phrase
        for start, length, m in bar["notes"]:
            for inst, octave in ph["lead"]:
                legato = 0.95 if length >= 2 else 0.78
                if inst == "harpsichord":
                    legato = 1.0
                score.note("lead " + inst, inst, m + octave, t0 + start * 2 * six, length * 2 * six * legato, vel=(0.95 if start % 4 == 0 else 0.85) * (0.9 if octave else 1.0), pan=0.05)
            pairs.append((t0 + start * 2 * six, m, None))
        # A 16th-note string run up into the next phrase
        for k, m in enumerate(bar["run"]):
            score.note("run", "marcato", m, t0 + (8 + k) * six, six * 0.9, vel=(0.6 + 0.05 * k) * dyn, pan=-0.15, jitter=0.002)
            score.note("run", "marcato", m - 12, t0 + (8 + k) * six, six * 0.9, vel=(0.5 + 0.05 * k) * dyn, pan=0.15, jitter=0.002)
        # Kettle drums: the groove, then a roll into every phrase
        hits = list(TIMP[spec["timp"]])
        if bar["i"] == 3:
            hits = [h for h in hits if h[0] < 8] + [(8 + s, "D", 0.35 + 0.06 * s) for s in range(8)]
        for step, drum, vel in hits:
            pcs = [c for c in bar["chords"] if c[0] <= step][-1][1]  # the chord sounding at this step
            if drums[drum] % 12 not in pcs:
                drum = "D" if drum == "T" else "T"
            score.add("timpani", timpani(drums[drum], vel * dyn), t0 + step * six, pan=0.1)
        if spec["tabor"]:
            for step, vel in TABOR[spec["tabor"]]:
                score.add("tabor", tabor(vel * dyn), t0 + step * six + 0.003, pan=0.25)
        labels = " ".join(f"{c[3]:8s}" for c in bar["chords"])
        mel = " ".join(name(m, spec["flats"]) for _, _, m in bar["notes"])
        run = (" run " + " ".join(name(m, spec["flats"]) for m in bar["run"])) if bar["run"] else ""
        table.append(f"    {b + 1:2d} {labels} {mel}{run}")
    # merge melody and bass points into outer-voice pairs (carry the last value forward)
    pairs.sort(key=lambda x: x[0])
    merged, mel, bas = [], None, None
    for t, m, bs in pairs:
        mel = m if m is not None else mel
        bas = bs if bs is not None else bas
        merged.append((t, mel, bas))
    return score, loop, table, merged


LEVELS = {
    "bass": -1.0, "organ": -6.0, "harpsichord": -5.0, "marcato": -6.0, "chug": -3.0, "run": -4.0, "timpani": -9.0, "tabor": 7.0,
    "lead organ_lead": 0.0, "lead strings_lead": 0.0, "lead choir_lead": 1.0, "lead harpsichord": -1.0,
}
SENDS = {"bass": 0.15, "organ": 0.3, "harpsichord": 0.25, "marcato": 0.25, "chug": 0.2, "run": 0.3, "timpani": 0.3, "tabor": 0.2,
         "lead organ_lead": 0.3, "lead strings_lead": 0.3, "lead choir_lead": 0.4, "lead harpsichord": 0.3}
EQ = {"organ": lowpass(3500, 1), "bass": highpass(38, 2), "timpani": highpass(35, 2), "lead organ_lead": lowpass(5000, 1)}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    for vname, spec in VARIANTS.items():
        score, loop, table, pairs = render(vname, spec)
        print(f"battle-{vname}: {spec['key']} minor, {spec['bpm']} BPM, {BARS} bars = {loop:.3f}s, {score.count} notes", file=sys.stderr)
        print("\n".join(table), file=sys.stderr)
        check_outer_voices(vname, pairs)
        bar = 64 * 15 / spec["bpm"] / 16 * 4
        sections = [(f"P{p + 1}", p * 4 * bar, (p + 1) * 4 * bar) for p in range(4)]
        x = mix(score, LEVELS, SENDS, eq=EQ, wet=0.8, sections=sections)
        x, hits = master(x, BATTLE_RMS_DB)
        report(f"battle-{vname}", x, hits, loop=True)
        path = os.path.join(out_dir, f"battle-{vname}.wav")
        write(path, x, loop=True)
        print(f"wrote {path}: {loop:.3f}s loop + 1s tail", file=sys.stderr)
    log_samples()


if __name__ == "__main__":
    main()
