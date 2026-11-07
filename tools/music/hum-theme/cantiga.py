"""
Cantiga, polished. The 8 bars the user liked become the REFRAIN; a contrasting VERSE is added,
in the form real cantigas (Cantigas de Santa Maria, virelai) use:
    Refrain A (8 bars) | Verse b, ending ouvert (4) | Verse b, ending clos (4) | Refrain A (8)
What makes it more medieval than the sampler version:
  - long-short trochaic rhythm (first rhythmic mode) instead of even 4/4 notes
  - repeated-note "reciting tone" in the verse (G5, the mode's upper fifth), like chant
  - phrase endings are two equal notes reached from a step below (C-D D open, B-C C closed)
  - the verse's closed ending is a Landini cadence: B - A - C
  - verse harmony moves to Eb (III) and Bb (VII, the "subtonal" chord medieval modal music uses)
  - take 2 adds a soft organetto drone on C+G and a recorder singing in thirds (gymel) in the verse
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loop import block, FLUTE, PIZZ
from motifs10 import N
from brood import BPM, setup, WPAD, CBASS
from backdrop_var import AAH
T = 1 / 3


def seq(bar, items):
    out, t = [], bar * 4
    for d, n in items:
        if n:
            out.append((round(t, 6), d + .04, N(n)))
        t += d
    return out


from motifs2 import Song, chord
from render10b import chain, join, GU

bar1 = [(1, "G4"), (2 * T, "C5"), (T, "C5"), (2 * T, "C5"), (T, "D5"), (1, "D5")]
REFRAIN = (
    seq(0, bar1)
    + seq(1, [(1 + 2 * T, "Eb5"), (T, "D5"), (2, "C5")])
    + seq(2, [(2 * T, "Ab4"), (T, "Bb4"), (1, "C5"), (1, "F5"), (1, "Eb5")])
    + seq(3, [(2 * T, "D5"), (T, "C5"), (1, "D5"), (1.6, "D5")])                # ouvert: C - D D
    + seq(4, bar1)
    + seq(5, [(1 + 2 * T, "Eb5"), (T, "F5"), (2 * T, "Eb5"), (T, "Db5"), (1, "C5")])
    + seq(6, [(2 * T, "D5"), (T, "Eb5"), (1, "D5"), (1, "Ab4"), (1, "B4")])     # the hum's Ab - B -
    + seq(7, [(2, "C5"), (1.6, "C5")])                                          # clos: B - C C
)
CH_REFRAIN = [(0, 8, "Cm"), (8, 4, "Fm"), (12, 4, "G"), (16, 4, "Cm"), (20, 4, "Abmaj7"), (24, 2, "G"), (26, 1, "Fm"), (27, 1, "G"), (28, 4, "Cm")]
vb = (seq(0, [(2 * T, "G5"), (T, "G5"), (2 * T, "G5"), (T, "F5"), (1, "Eb5"), (1, "G5")])   # reciting tone G
      + seq(1, [(2 * T, "F5"), (T, "Eb5"), (2 * T, "D5"), (T, "Eb5"), (2, "F5")]))
VERSE = (
    vb
    + seq(2, [(2 * T, "Eb5"), (T, "D5"), (2 * T, "C5"), (T, "D5"), (1, "Eb5"), (1, "C5")])
    + seq(3, [(1, "B4"), (1, "C5"), (1, "D5"), (1.6, "D5")])                    # ouvert
    + [(s + 16, d, p) for s, d, p in vb]
    + seq(6, [(2 * T, "D5"), (T, "Eb5"), (2 * T, "D5"), (T, "C5"), (1, "B4"), (1, "A4")])
    + seq(7, [(2, "C5"), (1.6, "C5")])                                          # clos, Landini B-A-C
)
CH_VERSE = [(0, 4, "Eb"), (4, 4, "Bb"), (8, 4, "Cm"), (12, 4, "G"), (16, 4, "Eb"), (20, 4, "Bb"), (24, 4, "G"), (28, 4, "Cm")]
FORM = [(REFRAIN, CH_REFRAIN), (VERSE, CH_VERSE), (REFRAIN, CH_REFRAIN)]

C_MINOR = [N(n) for n in ("F4", "G4", "Ab4", "Bb4", "C5", "D5", "Eb5", "F5", "G5", "Ab5")]


def third_below(p):
    below = [q for q in C_MINOR if q < p]
    return below[-2] if len(below) >= 2 else p - 3


def check(mel, chs, label):
    bad = []
    for st, d, p in mel:
        if abs(round(st, 4) % 2) < 1e-6:                                                 # beats 1 and 3
            c = [n for cs, cd, n in chs if cs <= st < cs + cd][0]
            if p % 12 not in chord(c)[1]:
                bad.append(f"beat {st:g} {p}/{c}")
    print(f"[{label}] non-chord tones on beats 1 & 3: {bad or 'none'}")


def build(name, extras):
    s = Song(name, BPM)
    setup(s)
    s.inst(AAH, 52, 0, volume=70, pan=20)
    s.inst(WPAD, 89, 0, volume=66, pan=84)
    s.inst(FLUTE, 73, 0, volume=88, pan=46)
    s.inst(9, 0, 0, volume=88, pan=64)
    s.inst(CBASS, 43, 0, volume=62, pan=64)
    s.inst(PIZZ, 74, 0, volume=68, pan=80)                                     # recorder (gymel)
    s.inst(13 if False else 3, 20, 0, volume=52, pan=56)                        # organetto drone (reed organ)
    prev, ap = None, 67
    for i, (mel, chs) in enumerate(FORM):
        prev, ap = block(s, i * 32, "raw", mel, chs, prev, ap)
    total = 32 * len(FORM)
    if extras:
        for t in range(0, total, 8):
            s.note(3, t, 8, 48, 40)                                            # C3 + G3 open fifth
            s.note(3, t, 8, 55, 34)
        for st, d, p in VERSE:
            if 16 <= st < 28:                                                  # second verse: parallel thirds
                s.note(PIZZ, 32 + st, d, third_below(p), 54)
    s.swell(AAH, [(t, v) for t0 in range(0, total, 8) for t, v in ((t0, 40), (t0 + 3, 100), (t0 + 5, 100), (t0 + 7.9, 50))])
    s.swell(FLUTE, sum(([(t, 74), (t + 1.2, 102), (t + 3.9, 84)] for t in range(0, total, 4)), []))
    path = f"cantiga_{'drone' if extras else 'plain'}.mid"
    s.write(path)
    return path


if __name__ == "__main__":
    check(REFRAIN, CH_REFRAIN, "refrain")
    check(VERSE, CH_VERSE, "verse")
    items = [("Cantiga, polished", chain(build("Cantiga polished", False), GU)),
             ("Cantiga + drone and gymel", chain(build("Cantiga drone", True), GU))]
    join(items, "cantiga_polished.mp3")
