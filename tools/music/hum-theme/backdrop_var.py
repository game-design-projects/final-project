"""
Backdrop variations: the eerie backdrop the user liked (brood_backdrop), with the hummed melody
changed in five ways. Each block is 8 bars: bars 1-2 bed alone, bars 3-6 melody at half speed on
celesta + "ooh" voices, bars 7-8 the bed on G (V) leading into the next block.
New: a faint separate "aaah" choir line drifting above everything, moving only by the smallest step
to the next chord tone (voice leading), with slow swells.

  1 Original      the hum as transcribed
  2 Skeleton      only the long notes: the quick wiggles (Db, E, Eb) removed, more air
  3 Going home    bar 2 keeps falling Gb F Eb Db C and lands on C (closed) instead of hanging on F
  4 New shadows   exact hum notes, new chords under them: Ab | Fm | Gb | Db
  5 Answer first  the two halves swapped: the falling Gb-F line comes first, then the C figure,
                  ending on the Ab-B-C climb
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from brood import (HUM, BPM, setup, SBASS, CBASS, PIANO, TREM, CEL, OOH, REV, CHOIR, WPAD,
                   C3, Db3, Eb3, Ab2, B2, F2, E2, Gb2, Eb2)
from motifs2 import chord, root_in, voice, Song

D3 = 50
AAH = 14

VARS = [
    ("Original", HUM,
     [(0, 8, "Cm"), (8, 4, "Cm"), (12, 4, "Abmaj7"), (16, 8, "Db"), (24, 8, "G")]),
    ("Skeleton",
     [(0, .75, C3), (.75, .75, Eb3), (1.5, .5, C3), (2, .5, Ab2), (2.5, .5, B2), (3, .25, C3), (3.25, .75, F2),
      (4, 1.25, Gb2), (5.25, 2, F2)],
     [(0, 8, "Cm"), (8, 4, "Cm"), (12, 4, "Abmaj7"), (16, 8, "Db"), (24, 8, "G")]),
    ("Going home",
     HUM[:11] + [(4, 1, Gb2), (5, .5, F2), (5.5, .5, Eb2), (6, .5, Db3 - 12), (6.5, 1.5, C3 - 12)],
     [(0, 8, "Cm"), (8, 4, "Cm"), (12, 4, "Abmaj7"), (16, 4, "Db"), (20, 4, "Cm"), (24, 8, "G")]),
    ("New shadows", HUM,
     [(0, 8, "Cm"), (8, 4, "Ab"), (12, 4, "Fm"), (16, 4, "Gb"), (20, 4, "Db"), (24, 8, "G")]),
    ("Answer first",
     [(0, 1, Gb2), (1.25, .25, F2), (1.5, .25, E2), (1.75, .25, Eb2), (2, 1.5, F2),
      (4, .5, C3), (4.5, .25, Db3), (4.75, .25, Eb3), (5, .25, C3), (5.25, .25, Db3), (5.5, .5, C3),
      (6, .5, Ab2), (6.5, .5, B2), (7, 1, C3)],
     [(0, 8, "Cm"), (8, 8, "Db"), (16, 4, "Cm"), (20, 4, "Ab"), (24, 8, "G")]),
]


def at(chs, t):
    return [c for st, d, c in chs if st <= t < st + d][0]


def block(s, t0, mel, chs, prev, aah_prev):
    # pads (warm pad only; the choir now has its own "aaah" line)
    for st, d, n in chs:
        v = voice(chord(n)[1], prev, 52, 68)
        prev = v
        for q in v:
            s.note(WPAD, t0 + st, d, q, 46)
    # heartbeat bass: the ostinato's first three hits, following the chord under each bar
    for b in range(8):
        r = root_in(chord(at(chs, b * 4))[0], 33, 44)
        for pos, v in ((0, 78), (3, 56), (6, 62)):
            s.note(SBASS, t0 + b * 4 + pos / 4, .3, r, v)
    s.note(CBASS, t0, 32, 36, 52)
    # melody at half speed, bars 3-6
    for st, d, p in mel:
        s.note(CEL, t0 + 8 + 2 * st, 2 * d, p + 24, 74)
        s.note(OOH, t0 + 8 + 2 * st, 2 * d, p + 12, 48)
    # tremolo strings creep in over bars 5-8
    for b in (4, 5, 6, 7):
        for q in voice(chord(at(chs, b * 4))[1], None, 60, 76):
            s.note(TREM, t0 + b * 4, 4, q, 34 + 6 * (b - 4))
    # low piano tolls on the roots at bars 1 and 5
    for b in (0, 4):
        r = root_in(chord(at(chs, b * 4))[0], 36, 47)
        s.note(PIANO, t0 + b * 4, 6, r, 58)
        s.note(PIANO, t0 + b * 4, 6, r + 12, 46)
    # faint "aaah": nearest chord tone in F4-D5, held through each chord
    for st, d, n in chs:
        pcs = chord(n)[1]
        cands = [q for q in range(65, 75) if q % 12 in pcs]
        q = min(cands, key=lambda c: (abs(c - aah_prev), c))
        aah_prev = q
        s.note(AAH, t0 + st, d, q, 44)
    s.note(REV, t0 + 32 - 2.4, 2.4, 60, 80)
    return prev, aah_prev


def piece():
    s = Song("Backdrop variations", BPM)
    setup(s)
    s.inst(AAH, 52, 0, volume=70, pan=20)
    s.inst(WPAD, 89, 0, volume=66, pan=84)
    prev, ap = None, 67
    for i, (name, mel, chs) in enumerate(VARS):
        prev, ap = block(s, i * 32, mel, chs, prev, ap)
    end = len(VARS) * 32
    for q in voice(chord("Cm")[1], prev, 52, 68):
        s.note(WPAD, end, 8, q, 46)
    s.note(AAH, end, 8, 67, 44)
    s.note(SBASS, end, 1, 36, 80)
    s.note(PIANO, end, 8, 36, 64)
    s.note(PIANO, end, 8, 48, 50)
    s.note(CBASS, end, 8, 36, 52)
    # slow breaths on the "aaah": in over 3 beats, out over 3, around each 8-beat span
    total = end + 8
    s.swell(AAH, sum(([(t, 40), (t + 3, 100), (t + 5, 100), (t + 7.9, 50)] for t in range(0, total, 8)), []))
    s.swell(OOH, sum(([(b * 2, 86), (b * 2 + 1, 112), (b * 2 + 1.9, 92)] for b in range(total // 2)), []))
    return s


if __name__ == "__main__":
    piece().write("backdrop_variations.mid")
    for i, (name, mel, chs) in enumerate(VARS):
        t = i * 32 * 60 / BPM
        print(f"{int(t // 60)}:{int(t % 60):02d}  {i + 1} {name}  (melody enters {int((t + 8 * 60 / BPM) // 60)}:{int((t + 8 * 60 / BPM) % 60):02d})")
