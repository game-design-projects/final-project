"""
Looping track built on the backdrop the user liked, ~2:55 per loop, 8 blocks of 8 bars (88 BPM).
Changes asked for:
  - "dun dun dun" heartbeat: now a soft lub-dub low bass drum (2 hits/bar) + a bowed contrabass root
  - melody on flute, quiet and distant (no celesta/"ooh" doubling), and NOT in every block:
    full variation, fragment, or nothing, so it doesn't wear out on repeat
  - endings use the smoother Db/F -> G motion (no tritone lurch); the last block ends on G so the
    loop leads back into the first block's C minor

  block  content
  1  bed only              (Cm, Abmaj7, G)
  2  flute: Skeleton       long notes only, open ending F -> G
  3  bed + fragment        just the first figure (C Db Eb C Db C), echoed fainter
  4  flute: New shadows    hum notes over Ab | Fm | Gb, open ending
  5  bed only              (Cm, Fm, Db/F, G)
  6  flute: Going home     ends F G B C: the only block that settles on C
  7  bed + fragment        just the climb Ab B C
  8  flute: Answer first   halves swapped, ends on C over G -> leads back to block 1
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from brood import HUM, BPM, setup, CBASS, PIANO, TREM, REV, WPAD, C3, Db3, Eb3, Ab2, B2, F2, E2, Gb2, Eb2
from backdrop_var import AAH, at
from motifs2 import chord, root_in, voice, Song

G2 = 43
FLUTE, PIZZ, TIMP = 15, 1, 10
HEAD = HUM[:11]
OPEN = [(4, 1, Gb2), (5, 1, F2), (6, 2, G2)]

BLOCKS = [
    ("bed", [], [(0, 16, "Cm"), (16, 8, "Abmaj7"), (24, 8, "G")]),
    ("Skeleton", [(0, .75, C3), (.75, .75, Eb3), (1.5, .5, C3), (2, .5, Ab2), (2.5, .5, B2), (3, .25, C3),
                  (3.25, .75, F2)] + OPEN,
     [(0, 8, "Cm"), (8, 4, "Cm"), (12, 4, "Abmaj7"), (16, 4, "Db/F"), (20, 12, "G")]),
    ("fragment", HUM[:6], [(0, 8, "Cm"), (8, 8, "Fm"), (16, 8, "Abmaj7"), (24, 8, "G")]),
    ("New shadows", HEAD + OPEN, [(0, 8, "Cm"), (8, 4, "Ab"), (12, 4, "Fm"), (16, 4, "Gb"), (20, 12, "G")]),
    ("bed", [], [(0, 8, "Cm"), (8, 8, "Fm"), (16, 8, "Db/F"), (24, 8, "G")]),
    ("Going home", HEAD + [(4, 1, Gb2), (5, 1, F2), (6, 1, G2), (7, 1, B2), (8, 3, C3)],
     [(0, 8, "Cm"), (8, 4, "Cm"), (12, 4, "Abmaj7"), (16, 4, "Db/F"), (20, 4, "G"), (24, 8, "Cm")]),
    ("fragment", [(0, .5, Ab2), (.5, .5, B2), (1, 1.5, C3)], [(0, 8, "Cm"), (8, 8, "Abmaj7"), (16, 8, "Db/F"), (24, 8, "G")]),
    ("Answer first", [(0, 1, Gb2), (1.25, .25, F2), (1.5, .25, E2), (1.75, .25, Eb2), (2, 1.5, F2),
                      (4, .5, C3), (4.5, .25, Db3), (4.75, .25, Eb3), (5, .25, C3), (5.25, .25, Db3), (5.5, .5, C3),
                      (6, .5, Ab2), (6.5, .5, B2), (7, 1, C3)],
     [(0, 8, "Cm"), (8, 8, "Db/F"), (16, 4, "Cm"), (20, 12, "G")]),
]


def block(s, t0, kind, mel, chs, prev, aah_prev):
    for st, d, n in chs:
        v = voice(chord(n)[1], prev, 52, 68)
        prev = v
        for q in v:
            s.note(WPAD, t0 + st, d, q, 46)
    sparse = kind == "bed" and t0 // 32 == 4    # the second bed block: heartbeat every other bar
    for b in range(8):                          # soft "lub-dub" low bass drum + bowed root
        r = root_in(chord(at(chs, b * 4))[0], 33, 44)
        s.note(CBASS, t0 + b * 4, 4, r, 46)
        if sparse and b % 2:
            continue
        s.note(9, t0 + b * 4, .5, 35, 50)
        s.note(9, t0 + b * 4 + .75, .5, 35, 34)
    if kind == "fragment":                      # a figure, then its fainter echo
        for st, d, p in mel:
            s.note(FLUTE, t0 + 8 + 2 * st, 2 * d, p + 24, 64)
            s.note(FLUTE, t0 + 20 + 2 * st, 2 * d, p + 24, 46)
    elif kind == "raw":                         # absolute pitches/beats, written for the block
        for st, d, p in mel:
            s.note(FLUTE, t0 + st, d, p, 70)
    elif kind != "bed":
        for st, d, p in mel:
            s.note(FLUTE, t0 + 8 + 2 * st, 2 * d, p + 24, 68)
    for b in (4, 5, 6, 7):
        for q in voice(chord(at(chs, b * 4))[1], None, 60, 76):
            s.note(TREM, t0 + b * 4, 4, q, 32 + 5 * (b - 4))
    for b in (0, 4):
        r = root_in(chord(at(chs, b * 4))[0], 36, 47)
        s.note(PIANO, t0 + b * 4, 6, r, 54)
        s.note(PIANO, t0 + b * 4, 6, r + 12, 42)
    for st, d, n in chs:                        # faint "aaah"
        pcs = chord(n)[1]
        q = min((c for c in range(65, 75) if c % 12 in pcs), key=lambda c: (abs(c - aah_prev), c))
        aah_prev = q
        s.note(AAH, t0 + st, d, q, 44)
    return prev, aah_prev


def piece():
    s = Song("Backdrop loop", BPM)
    setup(s)
    s.inst(AAH, 52, 0, volume=70, pan=20)
    s.inst(WPAD, 89, 0, volume=66, pan=84)
    s.inst(PIZZ, 45, 0, volume=82, pan=56)
    s.inst(TIMP, 47, 0, volume=70, pan=64)
    s.inst(FLUTE, 73, 0, volume=84, pan=46)
    s.inst(9, 0, 0, volume=88, pan=64)
    s.inst(CBASS, 43, 0, volume=62, pan=64)
    prev, ap = None, 67
    for i, (kind, mel, chs) in enumerate(BLOCKS):
        prev, ap = block(s, i * 32, kind, mel, chs, prev, ap)
    total = len(BLOCKS) * 32
    s.swell(AAH, sum(([(t, 40), (t + 3, 100), (t + 5, 100), (t + 7.9, 50)] for t in range(0, total, 8)), []))
    s.swell(FLUTE, sum(([(t, 70), (t + 1.2, 100), (t + 3.9, 80)] for t in range(0, total, 4)), []))
    s.note(REV, total - 2.4, 2.4, 60, 70)
    return s


if __name__ == "__main__":
    piece().write("backdrop_loop.mid")
    for i, (kind, mel, chs) in enumerate(BLOCKS):
        t = i * 32 * 60 / BPM
        print(f"{int(t // 60)}:{int(t % 60):02d}  {i + 1} {kind}")
