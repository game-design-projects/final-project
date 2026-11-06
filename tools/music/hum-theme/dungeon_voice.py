"""
Donjon - dungeon exploration loop, v2: same structure and backing; the flute is replaced by a slow
a-cappella voice singing Cantiga C at half speed, with echoes (delayed, quieter copies panned
left and right). Only whole phrases, never chopped fragments.

  block  voice
  1  nothing (bed only)
  2  phrase 1 (G C C D | Eb D C), echo x2
  3  phrase 2 (Ab C F Eb | D, open), echo x2
  4  phrase 1 on a soft solo cello instead, no echo
  5  nothing (bed only, heartbeat every other bar)
  6  phrase 1, quieter, longer echo trail (x3)
  7  phrase 2, quieter, longer echo trail (x3)
  8  the ending (D C Bb | C), heard only here, then the loop starts again
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from loop import block, REV
from brood import BPM, setup, WPAD, CBASS, CELLO
from backdrop_var import AAH
from cantiga2 import MOD
from motifs2 import Song

VOX, ECHO1, ECHO2 = 15, 6, 4


def half(a, b, start=8):
    """take C's notes in beats [a, b), at half speed, starting at `start` within the block"""
    return [(start + (st - a) * 2, d * 2, p) for st, d, p in MOD if a <= st < b]


P1, P2, END = half(0, 8), half(8, 16), half(24, 32)
CH_P1 = [(0, 16, "Cm"), (16, 4, "Abmaj7"), (20, 4, "Cm"), (24, 8, "Bb")]
CH_P2 = [(0, 8, "Cm"), (8, 8, "Fm"), (16, 8, "Gm"), (24, 8, "Bb")]
CH_END = [(0, 8, "Cm"), (8, 4, "Bb"), (12, 2, "F"), (14, 2, "Bb"), (16, 16, "Cm")]
CH_BED1 = [(0, 16, "Cm"), (16, 8, "Abmaj7"), (24, 8, "Bb")]
CH_BED2 = [(0, 8, "Cm"), (8, 8, "Fm"), (16, 8, "Db/F"), (24, 8, "Gm")]

# (phrase, chords, how: "voice" | "cello" | None, lead velocity, echo taps [(delay beats, gain)])
NEAR = [(1.5, .5), (3, .28)]
FAR = [(1.5, .5), (3, .32), (4.5, .18)]
BLOCKS = [
    (None, CH_BED1, None, 0, []),
    (P1, CH_P1, "voice", 80, NEAR),
    (P2, CH_P2, "voice", 80, NEAR),
    (P1, CH_P1, "cello", 58, []),
    (None, CH_BED2, None, 0, []),
    (P1, CH_P1, "voice", 64, FAR),
    (P2, CH_P2, "voice", 64, FAR),
    (END, CH_END, "voice", 76, FAR),
]


def piece():
    s = Song("Donjon - dungeon exploration (voice)", BPM)
    setup(s)
    s.inst(AAH, 52, 0, volume=66, pan=20)
    s.inst(WPAD, 89, 0, volume=66, pan=84)
    s.inst(9, 0, 0, volume=88, pan=64)
    s.inst(CBASS, 43, 0, volume=62, pan=64)
    s.inst(VOX, 53, 0, volume=108, pan=58)          # "voice oohs": the solo singer
    s.inst(ECHO1, 53, 0, volume=92, pan=26)
    s.inst(ECHO2, 53, 0, volume=86, pan=100)
    s.inst(CELLO, 42, 0, volume=92, pan=60)
    prev, ap = None, 67
    for i, (mel, chs, how, vel, taps) in enumerate(BLOCKS):
        t0 = i * 32
        prev, ap = block(s, t0, "bed", [], chs, prev, ap)
        if how == "voice":
            for st, d, p in mel:
                s.note(VOX, t0 + st, d, p, vel)
                for k, (delay, gain) in enumerate(taps):
                    ch = ECHO1 if k % 2 == 0 else ECHO2
                    s.note(ch, t0 + st + delay, d, p, int(vel * gain) + 8)
        elif how == "cello":
            for st, d, p in mel:
                s.note(CELLO, t0 + st, d + .05, p - 12, vel)
    total = 32 * len(BLOCKS)
    s.swell(AAH, sum(([(t, 40), (t + 3, 100), (t + 5, 100), (t + 7.9, 50)] for t in range(0, total, 8)), []))
    for ch in (VOX, ECHO1, ECHO2, CELLO):            # soft swelling attacks, like breath
        s.swell(ch, sum(([(t, 64), (t + 1.2, 104), (t + 3.9, 84)] for t in range(0, total, 4)), []))
    s.note(REV, total - 2.4, 2.4, 60, 56)
    return s


if __name__ == "__main__":
    piece().write("donjon_dungeon_voice.mid")
    for i in range(len(BLOCKS)):
        t = i * 32 * 60 / BPM
        print(f"{int(t // 60)}:{int(t % 60):02d}  block {i + 1}")
