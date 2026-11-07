"""
Donjon - combat version of the dungeon exploration track.
Same material: Cantiga take C (melody) and the same modal C minor chords (no B-natural pull),
at 176 BPM (2x the exploration tempo, so its pulse lines up with the heartbeat). Intensity comes from the rhythm and orchestration:
  - low strings drive a 3+3+2 eighth-note ostinato: the exploration heartbeat (3 hits) made constant
  - horns carry the melody, violins double it an octave up at the climax, trombone an octave down
  - choir "aah" chords, tremolo strings
  - drums: taiko, timpani, low toms, soft bass drum. No hi-hats or snare (they grated before)
Form (6 blocks x 8 bars, ~87 s, loops):
  1 Charge     ostinato + drums, choir swells          Cm  Abmaj7  Fm  Bb
  2 Melody     horns play the Cantiga                  Cantiga chords
  3 Melody+    horns + violins an octave up, cymbal swells
  4 Breakdown  drums drop to half time; the echoing voice from the exploration track sings
               phrase 1 slowly over tremolo strings
  5 Build      phrase 2 on violins, toms build, reverse cymbal       Fm Abmaj7 Bb
  6 Climax     everything: horns + trombone + violins + choir; ends on C, loops to 1
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cantiga2 import MOD, CH_MOD
from dungeon_voice import half
from motifs2 import chord, root_in, voice, Song

BPM = 176
HORN, CELLO, CBASS, VLN, TREM, CHOIR, VOX, ECHO, TIMP, TAIKO, REV, TBN, WPAD = 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13
CH_CHARGE = [(0, 8, "Cm"), (8, 8, "Abmaj7"), (16, 8, "Fm"), (24, 8, "Bb")]
CH_BREAK = [(0, 16, "Cm"), (16, 8, "Abmaj7"), (24, 8, "Bb")]
CH_BUILD = [(0, 8, "Fm"), (8, 8, "Abmaj7"), (16, 16, "Bb")]
P1, P2 = half(0, 8, start=4), [(st - 8, d, p) for st, d, p in MOD if 8 <= st < 16]


def at(chs, t):
    return [c for st, d, c in chs if st <= t < st + d][0]


def song():
    s = Song("Donjon - combat", BPM)
    s.inst(HORN, 60, 0, volume=118, pan=58)
    s.inst(TBN, 57, 0, volume=92, pan=70)
    s.inst(CELLO, 42, 0, volume=104, pan=44)
    s.inst(CBASS, 43, 0, volume=72, pan=64)
    s.inst(VLN, 48, 0, volume=96, pan=36)
    s.inst(TREM, 44, 0, volume=76, pan=80)
    s.inst(CHOIR, 52, 0, volume=78, pan=50)
    s.inst(WPAD, 89, 0, volume=56, pan=84)
    s.inst(VOX, 53, 0, volume=108, pan=58)
    s.inst(ECHO, 53, 0, volume=90, pan=24)
    s.inst(TIMP, 47, 0, volume=94, pan=64)
    s.inst(TAIKO, 116, 0, volume=70, pan=64)
    s.inst(REV, 119, 0, volume=78, pan=64)
    s.inst(9, 0, 0, volume=86, pan=64)
    prev = [None]

    def harmony(t0, chs, choir_vel=52, pad=True):
        for st, d, n in chs:
            v = voice(chord(n)[1], prev[0], 55, 70)
            prev[0] = v
            for q in v:
                s.note(CHOIR, t0 + st, d, q, choir_vel)
                if pad:
                    s.note(WPAD, t0 + st, d, q, 40)

    def ostinato(t0, chs, vel=1.0, half_time=False):
        for b in range(8):
            r = root_in(chord(at(chs, b * 4))[0], 36, 47)
            for e in range(8):
                acc = e in (0, 3, 6)
                if half_time and not acc:
                    continue
                p = r + (12 if e in (2, 5) else 0)
                s.note(CELLO, t0 + b * 4 + e * .5, .4, p, int((96 if acc else 70) * vel))
                if acc:
                    s.note(CBASS, t0 + b * 4 + e * .5, .5, r - 12 + 12, int(84 * vel))

    def drums(t0, chs, level=1.0, half_time=False, toms_last=False):
        for b in range(8):
            t = t0 + b * 4
            r = root_in(chord(at(chs, b * 4))[0], 38, 50)
            if half_time:
                s.note(TAIKO, t, 1, 36, int(96 * level))
                s.note(TIMP, t, 1.5, r, int(70 * level))
                continue
            for pos, v in ((0, 104), (1.5, 88), (3, 96)):          # the 3+3+2 accents
                s.note(TAIKO, t + pos, .8, 36, int(v * level))
            s.note(TIMP, t, 1, r, int(84 * level))
            s.note(TIMP, t + 2, 1, r, int(70 * level))
            s.note(9, t, .3, 35, int(70 * level))
            s.note(9, t + 2, .3, 35, int(60 * level))
            if b % 4 == 3:                                         # tom fill every 4th bar
                for k, (pos, tom) in enumerate(((2.5, 45), (3, 43), (3.5, 41))):
                    s.note(9, t + pos, .3, tom, int((74 + 8 * k) * level))
        if toms_last:
            t = t0 + 28
            for k in range(8):
                s.note(9, t + k * .5, .3, (45, 45, 43, 43, 41, 41, 41, 41)[k], 70 + 6 * k)

    def melody(ch, t0, notes, shift, vel):
        for st, d, p in notes:
            s.note(ch, t0 + st, d + .02, p + shift, vel)

    # 1 Charge
    t = 0
    ostinato(t, CH_CHARGE, .9)
    drums(t, CH_CHARGE, .9)
    harmony(t, CH_CHARGE, 58)
    s.note(9, t, 3, 49, 70)
    for st, d, n in CH_CHARGE:
        for q in voice(chord(n)[1], None, 60, 76):
            s.note(TREM, t + st, d, q, 58)
        s.note(HORN, t + st, d, root_in(chord(n)[0], 55, 66), 70)        # held horn roots
        s.note(HORN, t + st, d, root_in(chord(n)[0], 55, 66) + 7, 62)
    # 2 Melody (horns)
    t = 32
    ostinato(t, CH_MOD)
    drums(t, CH_MOD)
    harmony(t, CH_MOD, 50)
    melody(HORN, t, MOD, -12, 96)
    # 3 Melody+ (horns + violins octave up)
    t = 64
    ostinato(t, CH_MOD)
    drums(t, CH_MOD, 1.05)
    harmony(t, CH_MOD, 56)
    melody(HORN, t, MOD, -12, 100)
    melody(VLN, t, MOD, 0, 84)
    s.note(9, t, 3, 49, 84)
    for st, d, n in CH_MOD:
        for q in voice(chord(n)[1], None, 60, 76):
            s.note(TREM, t + st, d, q, 46)
    # 4 Breakdown: half-time drums, the voice with its echo, tremolo strings
    t = 96
    ostinato(t, CH_BREAK, .75, half_time=True)
    drums(t, CH_BREAK, .8, half_time=True)
    harmony(t, CH_BREAK, 44, pad=True)
    for st, d, p in P1 + [(s2 + 16, d2, p2) for s2, d2, p2 in P1]:
        s.note(VOX, t + st, d, p, 80)
        s.note(ECHO, t + st + 1.5, d, p, 46)
    for st, d, n in CH_BREAK:
        for q in voice(chord(n)[1], None, 60, 76):
            s.note(TREM, t + st, d, q, 40)
    s.note(REV, t + 32 - 2.4, 2.4, 60, 84)
    # 5 Build: phrase 2 on violins twice, toms build
    t = 128
    ostinato(t, CH_BUILD)
    drums(t, CH_BUILD, 1.0, toms_last=True)
    harmony(t, CH_BUILD, 62)
    for st, d, n in CH_BUILD:
        for q in voice(chord(n)[1], None, 60, 76):
            s.note(TREM, t + st, d, q, 54)
    melody(VLN, t + 0, P2, 0, 86)
    melody(VLN, t + 16, P2, 0, 92)
    melody(HORN, t + 16, P2, -12, 84)
    s.note(REV, t + 32 - 2.4, 2.4, 60, 96)
    # 6 Climax: tutti
    t = 160
    ostinato(t, CH_MOD, 1.08)
    drums(t, CH_MOD, 1.1)
    harmony(t, CH_MOD, 62)
    melody(HORN, t, MOD, -12, 106)
    melody(TBN, t, MOD, -24, 86)
    melody(VLN, t, MOD, 0, 92)
    s.note(9, t, 3, 49, 96)
    for st, d, n in CH_MOD:
        for q in voice(chord(n)[1], None, 60, 76):
            s.note(TREM, t + st, d, q, 52)
    for ch in (HORN, VLN, VOX, ECHO, TBN):
        s.swell(ch, sum(([(b * 2, 88), (b * 2 + 1, 112), (b * 2 + 1.9, 96)] for b in range(96)), []))
    return s


if __name__ == "__main__":
    song().write("donjon_combat.mid")
    for i, n in enumerate(["Charge", "Melody", "Melody+", "Breakdown", "Build", "Climax"]):
        t = i * 32 * 60 / BPM
        print(f"{int(t // 60)}:{int(t % 60):02d}  {n}")
