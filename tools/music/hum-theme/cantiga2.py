"""
Cantiga ladder: the sampler's Cantiga (which the user liked) with one authentic change at a time.
  A Original           exactly as in the sampler
  B Dorian             the raised 6th (A natural instead of Ab) in bar 3, over an F major chord.
                       The Dorian 6th is the signature colour of many Cantigas de Santa Maria.
  C Modal cadence      no B-natural leading tone: medieval tunes close by step from the note a whole
                       tone below (Bb -> C, "subtonal") or from above (D -> C). Bar 7 = D C Bb | C
                       over a Bb chord; bar 4's open D sits on G minor instead of G major.
  D B + C + ornaments  quick upper-neighbour "cuts" and a mordent on long notes, as a medieval
                       flute or recorder player would add
  E D + gentle lilt    a few dotted (long-short) rhythms, but no triplets
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loop import block, FLUTE, PIZZ
from brood import BPM, setup, WPAD, CBASS
from backdrop_var import AAH
from cantiga import seq, check
from motifs2 import Song
from render10b import chain, join, GU

G = .12  # grace-note length in beats


def cut(upper, main, dur):
    """a quick upper-neighbour grace note before the main note"""
    return [(G, upper), (dur - G, main)]


def mordent(main, lower, dur):
    return [(G, main), (G, lower), (dur - 2 * G, main)]


ORIG = (seq(0, [(1, "G4"), (1, "C5"), (1, "C5"), (1, "D5")])
        + seq(1, [(1.5, "Eb5"), (.5, "D5"), (2, "C5")])
        + seq(2, [(1, "Ab4"), (1, "C5"), (1, "F5"), (1, "Eb5")])
        + seq(3, [(3, "D5"), (1, None)])
        + seq(4, [(1, "G4"), (1, "C5"), (1, "C5"), (1, "D5")])
        + seq(5, [(1.5, "Eb5"), (.5, "F5"), (1, "Eb5"), (1, "C5")])
        + seq(6, [(2, "D5"), (1, "Ab4"), (1, "B4")])
        + seq(7, [(3, "C5")]))
CH_ORIG = [(0, 8, "Cm"), (8, 4, "Fm"), (12, 4, "G"), (16, 4, "Cm"), (20, 4, "Abmaj7"), (24, 4, "G"), (28, 4, "Cm")]

DOR = (seq(0, [(1, "G4"), (1, "C5"), (1, "C5"), (1, "D5")])
       + seq(1, [(1.5, "Eb5"), (.5, "D5"), (2, "C5")])
       + seq(2, [(1, "A4"), (1, "C5"), (1, "F5"), (1, "Eb5")])
       + seq(3, [(3, "D5"), (1, None)])
       + seq(4, [(1, "G4"), (1, "C5"), (1, "C5"), (1, "D5")])
       + seq(5, [(1.5, "Eb5"), (.5, "F5"), (1, "Eb5"), (1, "C5")])
       + seq(6, [(2, "D5"), (1, "Ab4"), (1, "B4")])
       + seq(7, [(3, "C5")]))
CH_DOR = [(0, 8, "Cm"), (8, 4, "F"), (12, 4, "G"), (16, 4, "Cm"), (20, 4, "Eb"), (24, 4, "G"), (28, 4, "Cm")]

MOD = (ORIG[:-4]
       + seq(6, [(2, "D5"), (1, "C5"), (1, "Bb4")])
       + seq(7, [(3, "C5")]))
CH_MOD = [(0, 8, "Cm"), (8, 4, "Fm"), (12, 4, "Gm"), (16, 4, "Cm"), (20, 4, "Abmaj7"), (24, 4, "Bb"), (28, 4, "Cm")]


def full(lilt):
    b0 = [(1, "G4"), (1.5, "C5"), (.5, "C5"), (1, "D5")] if lilt else [(1, "G4"), (1, "C5"), (1, "C5"), (1, "D5")]
    b2 = [(1, "A4"), (.75, "C5"), (.25, "D5"), (1, "F5"), (1, "Eb5")] if lilt else [(1, "A4"), (1, "C5"), (1, "F5"), (1, "Eb5")]
    return (seq(0, b0)
            + seq(1, cut("F5", "Eb5", 1.5) + [(.5, "D5"), (2, "C5")])
            + seq(2, b2)
            + seq(3, mordent("D5", "C5", 3) + [(1, None)])
            + seq(4, b0)
            + seq(5, cut("F5", "Eb5", 1.5) + [(.5, "F5"), (1, "Eb5"), (1, "C5")])
            + seq(6, [(2, "D5"), (1, "C5"), (1, "Bb4")])
            + seq(7, cut("D5", "C5", 3)))


CH_FULL = [(0, 8, "Cm"), (8, 4, "F"), (12, 4, "Gm"), (16, 4, "Cm"), (20, 4, "Eb"), (24, 4, "Bb"), (28, 4, "Cm")]

TAKES = [("A Original", ORIG, CH_ORIG), ("B Dorian", DOR, CH_DOR), ("C Modal cadence", MOD, CH_MOD),
         ("D Dorian + modal cadence + ornaments", full(False), CH_FULL), ("E D + gentle lilt", full(True), CH_FULL)]

if __name__ == "__main__":
    items = []
    for name, mel, chs in TAKES:
        check([n for n in mel if n[1] > .2], chs, name)
        s = Song(name, BPM)
        setup(s)
        s.inst(AAH, 52, 0, volume=70, pan=20)
        s.inst(WPAD, 89, 0, volume=66, pan=84)
        s.inst(FLUTE, 73, 0, volume=88, pan=46)
        s.inst(9, 0, 0, volume=88, pan=64)
        s.inst(CBASS, 43, 0, volume=62, pan=64)
        block(s, 0, "raw", mel, chs, None, 67)
        s.swell(AAH, [(t, v) for t0 in range(0, 32, 8) for t, v in ((t0, 40), (t0 + 3, 100), (t0 + 5, 100), (t0 + 7.9, 50))])
        s.swell(FLUTE, sum(([(t, 74), (t + 1.2, 102), (t + 3.9, 84)] for t in range(0, 32, 4)), []))
        path = f"cantiga2_{name[0]}.mid"
        s.write(path)
        items.append((name, chain(path, GU)))
    join(items, "cantiga_ladder.mp3")
