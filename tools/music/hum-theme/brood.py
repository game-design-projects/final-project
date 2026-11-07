"""
"Brood": built on the user's hummed melody (hum.m4a), transcribed with pYIN pitch tracking.

THE HUM (as sung, octave 2-3, ~88 BPM), 2 bars of 4/4:
  bar 1: C . Db Eb C Db C .  | Ab . B . C F . E      phrase 1 circles C; phrase 2 climbs Ab-B-C, drops to F
  bar 2: Gb ~~~ . F E Eb F ~~~ . rest                 the Gb leans on F, F is the landing note
Harmony that fits it (theory): bar 1 = Cm then Ab (Ab-B-C = harmonic-minor climb), bar 2 = Db (the
Neapolitan bII of C minor: Gb is its sus4 resolving to F, its 3rd). Db -> Cm on the repeat is a
Phrygian-flavoured cadence: dark, unresolved, brooding.

Form (88 BPM, 28 bars, ~76 s):
  A  bars 1-4   bass ostinato alone over a C pedal (original 16th pattern 3+3+2+3+1+2+2)
     bars 5-8   hum melody x2 on piano (pedal stays C; pads move Cm / Ab / Db above it)
     bars 9-12  hum melody x2 on cello + strings + horn; the bass now follows the chords; taiko enters;
                bar 12 ends on G (V) for a half cadence
  B  bars 13-20 the eerie backdrop: same bass rhythm cut to a quiet 3-note heartbeat, choir and pad,
                the melody once at half speed on celesta + "ooh" voices, tremolo strings creep in
  A' bars 21-28 full ostinato returns, melody x3 (last one ends on G), final low C
B is also exported as its own loop (brood_backdrop.mid).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motifs2 import chord, root_in, voice, Song

BPM = 88
C3, Db3, Eb3, Ab2, B2, F2, E2, Gb2, Eb2 = 48, 49, 51, 44, 47, 41, 40, 42, 39
HUM = [(0.0, .5, C3), (0.5, .25, Db3), (0.75, .25, Eb3), (1.0, .25, C3), (1.25, .25, Db3), (1.5, .5, C3),
       (2.0, .5, Ab2), (2.5, .5, B2), (3.0, .25, C3), (3.25, .5, F2), (3.75, .25, E2),
       (4.0, 1.0, Gb2), (5.25, .25, F2), (5.5, .25, E2), (5.75, .25, Eb2), (6.0, 1.25, F2)]
# bass ostinato: 16th positions, 'r' = root, 'o' = octave up, 'n' = semitone above root (b2 neighbour)
OST = [(0, "r", 110), (3, "r", 92), (6, "r", 96), (8, "r", 100), (11, "o", 92), (12, "r", 96), (14, "n", 84)]

PIANO, SBASS, STR, CELLO, HORN, CEL, OOH, CHOIR, WPAD, TAIKO, REV, TREM, CBASS = 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13


def setup(s):
    s.inst(PIANO, 0, 0, volume=124, pan=60)
    s.inst(SBASS, 38, 0, volume=78, pan=64)
    s.inst(STR, 48, 0, volume=92, pan=44)
    s.inst(CELLO, 42, 0, volume=100, pan=70)
    s.inst(HORN, 60, 0, volume=96, pan=56)
    s.inst(CEL, 8, 0, volume=118, pan=66)
    s.inst(OOH, 53, 0, volume=84, pan=50)
    s.inst(CHOIR, 52, 0, volume=62, pan=40)
    s.inst(WPAD, 89, 0, volume=58, pan=84)
    s.inst(TAIKO, 116, 0, volume=74, pan=64)
    s.inst(REV, 119, 0, volume=80, pan=64)
    s.inst(TREM, 44, 0, volume=72, pan=30)
    s.inst(CBASS, 43, 0, volume=50, pan=64)


def mel(s, ch, t0, shift, vel, aug=1):
    for st, d, p in HUM:
        s.note(ch, t0 + st * aug, d * aug + (.03 if aug == 1 else 0), p + shift, vel)


def ostinato(s, t0, roots, vel=1.0, piano=True):
    """roots: list of (bar_offset_beats, dur_beats, root_pc) covering the bar(s)."""
    for bs, bd, pc in roots:
        r = root_in(pc, 33, 44)
        for pos, kind, v in OST:
            b = pos / 4
            if bs <= b < bs + bd:
                p = r + {"r": 0, "o": 12, "n": 1}[kind]
                s.note(SBASS, t0 + b, .22 if kind != "r" or pos else .4, p, int(v * vel))
                if piano and pos in (0, 11):
                    s.note(PIANO, t0 + b, .5, r + (12 if kind == "o" else 0), int(56 * vel))


def pads(s, t0, chs, prev=None, lo=50, hi=65, vel=40, choir=True):
    for st, d, n in chs:
        v = voice(chord(n)[1], prev, lo, hi)
        prev = v
        for q in v:
            s.note(WPAD, t0 + st, d, q, vel)
            if choir:
                s.note(CHOIR, t0 + st, d, q, vel - 6)
    return prev


def taiko(s, t0, hits=((0, 100), (2.5, 84))):
    for b, v in hits:
        s.note(TAIKO, t0 + b, 1, 36, v)


HARM_A = [(0, 2, "Cm"), (2, 2, "Ab"), (4, 4, "Db")]          # under one statement (2 bars)
HARM_HALF = [(0, 2, "Cm"), (2, 2, "Ab"), (4, 4, "G")]        # last statement: ends on V


def section_A(s, t0):
    # bars 1-4: ostinato alone on the C pedal, a low contrabass drone fades in
    for b in range(4):
        ostinato(s, t0 + b * 4, [(0, 4, 0)], vel=.8 + .05 * b, piano=b >= 2)
    s.note(CBASS, t0, 16, 36, 60)
    # bars 5-8: melody x2 on piano over the pedal; pads move above it
    prev = None
    for k in range(2):
        t = t0 + 16 + k * 8
        for b in range(2):
            ostinato(s, t + b * 4, [(0, 4, 0)])
        mel(s, PIANO, t, 24, 92)
        if k:
            mel(s, PIANO, t, 36, 54)
        prev = pads(s, t, HARM_A, prev, choir=False)
    s.note(CBASS, t0 + 16, 16, 36, 56)
    # bars 9-12: melody x2 on cello + strings (+ horn 2nd time); bass follows the chords; taiko
    for k, harm in enumerate((HARM_A, HARM_HALF)):
        t = t0 + 32 + k * 8
        ostinato(s, t, [(0, 2, 0), (2, 2, 8)])
        ostinato(s, t + 4, [(0, 4, chord(harm[2][2])[0])])
        mel(s, CELLO, t, 12, 92)
        mel(s, STR, t, 24, 82)
        if k:
            mel(s, HORN, t, 12, 72)
        prev = pads(s, t, harm, prev)
        for b in range(2):
            taiko(s, t + b * 4)
    s.note(REV, t0 + 48 - 2.4, 2.4, 60, 90)                 # reverse cymbal into B
    return prev


def section_B(s, t0, prev=None):
    chs = [(0, 8, "Cm"), (8, 4, "Cm"), (12, 4, "Abmaj7"), (16, 8, "Db"), (24, 8, "G")]
    prev = pads(s, t0, chs, prev, lo=52, hi=68, vel=46)
    for b in range(8):                                        # heartbeat: the ostinato's first 3 hits
        pc = {0: 0, 1: 0, 2: 0, 3: 8, 4: 1, 5: 1, 6: 7, 7: 7}[b]
        r = root_in(pc, 33, 44)
        for pos, v in ((0, 78), (3, 56), (6, 62)):
            s.note(SBASS, t0 + b * 4 + pos / 4, .3, r, v)
    s.note(CBASS, t0, 32, 36, 52)
    mel(s, CEL, t0 + 8, 24, 74, aug=2)                        # melody at half speed, high and glassy
    mel(s, OOH, t0 + 8, 12, 48, aug=2)
    for b in (4, 5, 6, 7):                                    # tremolo strings creep in
        v = voice(chord(chs[3 if b < 6 else 4][2])[1], None, 60, 76)
        for q in v:
            s.note(TREM, t0 + b * 4, 4, q, 34 + 6 * (b - 4))
    s.note(PIANO, t0, 6, 36, 60)                              # low C2 + C3 tolls
    s.note(PIANO, t0, 6, 48, 50)
    s.note(PIANO, t0 + 16, 6, 37, 56)                         # Db2: the Neapolitan in the depths
    s.note(PIANO, t0 + 16, 6, 49, 46)
    s.note(REV, t0 + 32 - 2.4, 2.4, 60, 96)
    return prev


def section_A2(s, t0, prev):
    for k, harm in enumerate((HARM_A, HARM_A, HARM_HALF)):
        t = t0 + k * 8
        ostinato(s, t, [(0, 2, 0), (2, 2, 8)])
        ostinato(s, t + 4, [(0, 4, chord(harm[2][2])[0])])
        mel(s, PIANO, t, 24, 94)
        mel(s, PIANO, t, 36, 58)
        mel(s, STR, t, 24, 84)
        if k >= 1:
            mel(s, CELLO, t, 12, 92)
        if k == 2:
            mel(s, HORN, t, 12, 80)
        prev = pads(s, t, harm, prev)
        for b in range(2):
            taiko(s, t + b * 4, ((0, 104), (2.5, 88), (3.5, 76)))
            for q in voice(chord(harm[0 if b == 0 else 2][2])[1], None, 60, 76):
                s.note(TREM, t + b * 4, 4, q, 46)
    t = t0 + 24                                               # bars 27-28: final low C
    s.note(SBASS, t, 3, 36, 110)
    s.note(PIANO, t, 6, 36, 84)
    s.note(PIANO, t, 6, 48, 74)
    s.note(TAIKO, t, 2, 36, 110)
    s.note(CELLO, t, 6, 48, 80)
    s.note(CBASS, t, 6, 36, 70)
    pads(s, t, [(0, 7, "Cm")], prev)


def song():
    s = Song("Brood", BPM)
    setup(s)
    prev = section_A(s, 0)
    prev = section_B(s, 48, prev)
    section_A2(s, 80, prev)
    for ch in (STR, CELLO, HORN, OOH):
        s.swell(ch, sum(([(b * 2, 86), (b * 2 + 1, 112), (b * 2 + 1.9, 92)] for b in range(60)), []))
    return s


def backdrop_loop():
    s = Song("Brood - backdrop", BPM)
    setup(s)
    prev = None
    for k in range(2):
        prev = section_B(s, k * 32, prev)
    return s


def hum_check():
    s = Song("Hum check", BPM)
    s.inst(PIANO, 0, 0, volume=120, pan=64)
    mel(s, PIANO, 0, 12, 100)
    return s


if __name__ == "__main__":
    song().write("brood.mid")
    backdrop_loop().write("brood_backdrop.mid")
    hum_check().write("hum_check.mid")
    print("written")
