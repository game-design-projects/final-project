"""
TEN SHORT MOTIFS, written with the game-scoring skill (rhythm cell first, small pitch set,
opening interval chosen on purpose, repeat exactly / repeat with new pitches / change on the third pass).

Every motif is 4 bars, played 3 times: pass 1 = A, pass 2 = A (exact), pass 3 = A with a changed
last bar. Layers enter by pass (lead + bass first, harmony second, full band third).

 #  name              key / tempo           rhythm cell                         opening interval
 1  Tavern Skip       G Mixolydian 118      8th 8th quarter | quarter           up a 4th (D-G)
 2  Pale Corridor     E Phrygian 66 (pedal) long, short, long + rests            minor 2nd (E-F)
 3  Heroic Call       D major 96            8th 8th dotted-quarter 8th quarter  octave leap up (D4-D5)
 4  Music Box Lullaby F major 84, 3/4       dotted-quarter 8th quarter          falling triad (C-A-F)
 5  Battle Stomp      A minor 150           8th 8th 8th 8th, quarter, run       repeated note then minor 3rd up
 6  Snow Village      C major 104           off-beat 8th, long, 8th             step-up then 3rd (E-G)
 7  Stormwatch        D minor 84            quarter then 3-beat note            up a 5th (D-A), then a 4th (A-D)
 8  Clockwork         E minor 128           3+3+2 tresillo of 8ths              up a 3rd (E-G) then a 3rd (G-B)
 9  Elegy             B minor 58            dotted-quarter 8th half             falling step (F#-E-D)
10  Sunken Bell       F Lydian 96, 5/4      quarter, half, quarter, quarter     up a 3rd (A-C), the Lydian B in bar 2
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motifs2 import chord, root_in, check2, voice, Song, Key, nm

LET = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def N(s):
    p, i = LET[s[0]], 1
    while s[i] in "#b":
        p += 1 if s[i] == "#" else -1
        i += 1
    return 12 * (int(s[i:]) + 1) + p


def tones(r, pcs, lo, count=5):
    """Ascending chord tones starting on the root near lo (for arpeggios)."""
    seq = [root_in(r, lo, lo + 11)]
    for i in range(1, count):
        q = seq[-1] + 1
        while q % 12 != pcs[i % len(pcs)]:
            q += 1
        seq.append(q)
    return seq


M = []
M.append(dict(
    name="Tavern Skip", key=(67, "mixolydian"), bpm=118, bl=4, chords=["G", "F", "G", "C"],
    bars=[[(0, .5, "D5"), (.5, .5, "D5"), (1, 1, "G5"), (2, 1, "B5")],
          [(0, .5, "C5"), (.5, .5, "C5"), (1, 1, "F5"), (2, 1, "A5")],
          [(0, .5, "D5"), (.5, .5, "D5"), (1, 1, "G5"), (2, 1, "B5")],
          [(0, .5, "E5"), (.5, .5, "E5"), (1, 1, "C5"), (2, 2, "D5")]],
    end3=[(0, .5, "E5"), (.5, .5, "E5"), (1, 1, "G5"), (2, 2, "G5")]))
M.append(dict(
    name="Pale Corridor", key=(64, "minor"), bpm=66, bl=4, chords=["Em"] * 4, chrom=[5],
    bars=[[(0, 1.5, "E4"), (1.5, .5, "F4"), (2, 1, "E4")],
          [(0, 1.5, "G4"), (1.5, .5, "F4"), (2, 1, "E4")],
          [(0, 1.5, "E4"), (1.5, .5, "F4"), (2, 1, "E4")],
          [(0, 1.5, "G4"), (1.5, .5, "F4"), (2, 2, "B3")]],
    end3=[(0, 1.5, "G4"), (1.5, .5, "F4"), (2, 2, "E4")]))
M.append(dict(
    name="Heroic Call", key=(62, "major"), bpm=96, bl=4, chords=["D", "G", "D/F#", "A"],
    bars=[[(0, .5, "D4"), (.5, .5, "D4"), (1, 1.5, "D5"), (2.5, .5, "A4"), (3, 1, "F#4")],
          [(0, .5, "B4"), (.5, .5, "B4"), (1, 1.5, "D5"), (2.5, .5, "B4"), (3, 1, "G4")],
          [(0, .5, "D4"), (.5, .5, "D4"), (1, 1.5, "D5"), (2.5, .5, "A4"), (3, 1, "F#4")],
          [(0, .5, "C#5"), (.5, .5, "C#5"), (1, 1.5, "E5"), (2.5, .5, "C#5"), (3, 1, "A4")]],
    end3=[(0, .5, "C#5"), (.5, .5, "C#5"), (1, 1.5, "E5"), (2.5, 1.5, "D5")]))
M.append(dict(
    name="Music Box Lullaby", key=(65, "major"), bpm=84, bl=3, chords=["F", "Dm/F", "Bb", "C"],
    bars=[[(0, 1.5, "C5"), (1.5, .5, "A4"), (2, 1, "F4")],
          [(0, 1.5, "D5"), (1.5, .5, "A4"), (2, 1, "F4")],
          [(0, 1.5, "D5"), (1.5, .5, "Bb4"), (2, 1, "F4")],
          [(0, 1.5, "E5"), (1.5, .5, "C5"), (2, 1, "G4")]],
    end3=[(0, 1.5, "E5"), (1.5, .5, "D5"), (2, 1, "C5")]))
M.append(dict(
    name="Battle Stomp", key=(69, "minor"), bpm=150, bl=4, chords=["Am", "Am", "F/A", "G"],
    bars=[[(0, .5, "A4"), (.5, .5, "A4"), (1, .5, "C5"), (1.5, .5, "A4"), (2, 1, "E5"), (3, .5, "D5"), (3.5, .5, "C5")],
          [(0, .5, "A4"), (.5, .5, "A4"), (1, .5, "C5"), (1.5, .5, "A4"), (2, 1, "E5"), (3, .5, "C5"), (3.5, .5, "A4")],
          [(0, .5, "F4"), (.5, .5, "F4"), (1, .5, "A4"), (1.5, .5, "F4"), (2, 1, "C5"), (3, .5, "A4"), (3.5, .5, "F4")],
          [(0, .5, "G4"), (.5, .5, "G4"), (1, .5, "B4"), (1.5, .5, "G4"), (2, 2, "D5")]],
    end3=[(0, .5, "G4"), (.5, .5, "G4"), (1, .5, "B4"), (1.5, .5, "G4"), (2, 1, "D5"), (3, 1, "A4")]))
M.append(dict(
    name="Snow Village", key=(60, "major"), bpm=104, bl=4, chords=["C", "Am", "F", "G"],
    bars=[[(0, .5, "E5"), (.5, 1, "G5"), (1.5, .5, "E5"), (2, 1, "C5"), (3, 1, "D5")],
          [(0, .5, "E5"), (.5, 1, "A5"), (1.5, .5, "E5"), (2, 1, "C5"), (3, 1, "A4")],
          [(0, .5, "C5"), (.5, 1, "A5"), (1.5, .5, "C5"), (2, 1, "A4"), (3, 1, "G4")],
          [(0, .5, "D5"), (.5, 1, "G5"), (1.5, .5, "D5"), (2, 2, "B4")]],
    end3=[(0, .5, "D5"), (.5, 1, "G5"), (1.5, .5, "E5"), (2, 2, "C5")]))
M.append(dict(
    name="Stormwatch", key=(62, "minor"), bpm=84, bl=4, chords=["Dm", "Bb", "F", "C"],
    bars=[[(0, 1, "D4"), (1, 3, "A4")],
          [(0, 3, "D5"), (3, 1, "C5")],
          [(0, 2, "A4"), (2, 2, "F4")],
          [(0, 2, "G4"), (2, 2, "E4")]],
    end3=[(0, 2, "G4"), (2, 2, "D4")]))
M.append(dict(
    name="Clockwork", key=(64, "minor"), bpm=128, bl=4, chords=["Em", "C", "D", "Em"],
    bars=[[(o, .5, n) for o, n in zip((0, .75, 1.5, 2, 2.75, 3.5), ("E5", "G5", "B5", "G5", "E5", "G5"))],
          [(o, .5, n) for o, n in zip((0, .75, 1.5, 2, 2.75, 3.5), ("E5", "G5", "C6", "G5", "E5", "G5"))],
          [(o, .5, n) for o, n in zip((0, .75, 1.5, 2, 2.75, 3.5), ("F#5", "A5", "D6", "A5", "F#5", "A5"))],
          [(0, .5, "E5"), (.75, .5, "G5"), (1.5, .5, "B5"), (2, 2, "B5")]],
    end3=[(0, .5, "E5"), (.75, .5, "G5"), (1.5, .5, "B5"), (2, 2, "E6")]))
M.append(dict(
    name="Elegy", key=(59, "minor"), bpm=58, bl=4, chords=["Bm", "G", "D", "A"],
    bars=[[(0, 1.5, "F#5"), (1.5, .5, "E5"), (2, 2, "D5")],
          [(0, 1.5, "B4"), (1.5, .5, "A4"), (2, 2, "G4")],
          [(0, 1.5, "A4"), (1.5, .5, "B4"), (2, 2, "D5")],
          [(0, 1.5, "C#5"), (1.5, .5, "B4"), (2, 2, "A4")]],
    end3=[(0, 1.5, "C#5"), (1.5, .5, "D5"), (2, 2, "B4")]))
M.append(dict(
    name="Sunken Bell", key=(65, "lydian"), bpm=96, bl=5, chords=["Fmaj7", "G", "Fmaj7", "Am7"],
    bars=[[(0, 1, "A4"), (1, 2, "C5"), (3, 1, "E5"), (4, 1, "C5")],
          [(0, 1, "B4"), (1, 2, "D5"), (3, 1, "G5"), (4, 1, "D5")],
          [(0, 1, "A4"), (1, 2, "C5"), (3, 1, "E5"), (4, 1, "C5")],
          [(0, 1, "C5"), (1, 2, "E5"), (3, 1, "A4"), (4, 1, "G4")]],
    end3=[(0, 1, "C5"), (1, 2, "E5"), (3, 1, "A4"), (4, 1, "F4")]))

PASSES = 3


def build(i, m):
    bl, loop = m["bl"], m["bl"] * 4
    k = Key(*m["key"])
    mel = []
    for p in range(PASSES):
        bars = list(m["bars"])
        if p == PASSES - 1:
            bars[3] = m["end3"]
        for b, bar in enumerate(bars):
            for off, dur, n in bar:
                mel.append((p * loop + b * bl + off, dur, N(n)))
    cev = [(p * loop + b * bl, bl, m["chords"][b]) for p in range(PASSES) for b in range(4)]
    s = Song(m["name"], m["bpm"])

    def after(ev, p):
        return [e for e in ev if e[0] >= p * loop]

    def pad(ch, ev, lo, hi, vel):
        prev = None
        for st, d, n in ev:
            v = voice(chord(n)[1], prev, lo, hi)
            prev = v
            for q in v:
                s.note(ch, st, d, q, vel)

    def lead(ch, vel=92):
        for n in mel:
            s.note(ch, *n, vel)

    def drums(pat, ev, vel=1.0):
        for st, d, n in ev:
            for off, pitch, v in pat:
                if off < d:
                    s.note(9, st + off, .25, pitch, int(v * vel))

    n = m["name"]
    if n == "Tavern Skip":
        s.inst(0, 110, 55, volume=112, pan=60); s.inst(1, 32, 35, volume=100, pan=50); s.inst(2, 24, 55, volume=86, pan=82)
        lead(0)
        for st, d, c in cev:
            r = chord(c)[0]; b = root_in(r, 36, 47)
            s.note(1, st, .9, b, 86); s.note(1, st + 2, .9, b + 7, 78)
        prev = None
        for st, d, c in after(cev, 1):
            v = voice(chord(c)[1], prev, 55, 69); prev = v
            for off in (1, 3):
                s.strum(2, st + off, .4, v, 66, spread=.02)
    elif n == "Pale Corridor":
        s.inst(0, 70, 90, volume=112, pan=62); s.inst(1, 42, 85, volume=74, pan=40); s.inst(2, 14, 100, volume=70, pan=75)
        lead(0, 88)
        s.note(1, 0, PASSES * loop, 40, 62)
        for p in range(1, PASSES):
            for b in (1, 3):
                s.note(2, p * loop + b * bl + 3, 1, N("F5"), 52)
    elif n == "Heroic Call":
        s.inst(0, 56, 55, volume=118, pan=60); s.inst(1, 60, 70, volume=84, pan=44); s.inst(2, 47, 70, volume=100, pan=64)
        lead(0, 96)
        pad(1, after(cev, 1), 55, 69, 54)
        for st, d, c in cev:
            r = root_in(chord(c)[0], 38, 50)
            s.note(2, st, .6, r, 92); s.note(2, st + 2, .6, r, 82)
        s.note(9, 2 * loop, 3, 49, 96)
    elif n == "Music Box Lullaby":
        s.inst(0, 10, 85, volume=127, pan=62); s.inst(1, 46, 80, volume=60, pan=38); s.inst(2, 42, 85, volume=46, pan=64)
        lead(0, 104)
        for st, d, c in cev:
            r, pcs = chord(c)
            t = tones(r, pcs, 48, 4)
            for j, q in enumerate((t[0], t[2], t[3])):
                s.note(1, st + j, 1.2, q, 56 if j == 0 else 46)
        for st, d, c in after(cev, 1):
            s.note(2, st, d, root_in(chord(c)[0], 36, 47), 62)
    elif n == "Battle Stomp":
        s.inst(0, 29, 40, volume=108, pan=60); s.inst(1, 33, 25, volume=76, pan=64); s.inst(2, 44, 60, volume=66, pan=40)
        lead(0, 100)
        pat = [0, 0, 12, 0, 0, 12, 0, 7]
        for st, d, c in cev:
            r = root_in(chord(c)[0], 33, 44)
            for j in range(8):
                s.note(1, st + j * .5, .45, r + pat[j], 88 if j % 2 == 0 else 68)
        drums([(0, 36, 80), (1.5, 36, 72), (2, 36, 80)] + [(j * .5, 42, 62 if j % 2 == 0 else 46) for j in range(8)], cev)
        drums([(1, 38, 100), (3, 38, 100)], after(cev, 1))
        pad(2, after(cev, 2), 55, 69, 58)
        s.note(9, 2 * loop, 3, 49, 100)
    elif n == "Snow Village":
        s.inst(0, 12, 60, volume=114, pan=60); s.inst(1, 45, 45, volume=92, pan=50); s.inst(2, 24, 55, volume=80, pan=82)
        lead(0, 92)
        for st, d, c in cev:
            b = root_in(chord(c)[0], 36, 47)
            s.note(1, st, .6, b, 86); s.note(1, st + 2, .6, b + 7, 76)
        prev = None
        for st, d, c in after(cev, 1):
            v = voice(chord(c)[1], prev, 55, 69); prev = v
            for off in (1, 3):
                s.strum(2, st + off, .4, v, 64, spread=.02)
    elif n == "Stormwatch":
        s.inst(0, 60, 90, volume=118, pan=60); s.inst(1, 49, 95, volume=80, pan=44); s.inst(2, 42, 80, volume=84, pan=36); s.inst(3, 47, 80, volume=96, pan=64)
        lead(0, 94)
        pad(1, cev, 55, 69, 50)
        s.swell(1, sum(([(b * 4, 70), (b * 4 + 2, 104), (b * 4 + 3.9, 76)] for b in range(PASSES * 4)), []))
        for st, d, c in after(cev, 1):
            r = root_in(chord(c)[0], 36, 47)
            for j in range(8):
                s.note(2, st + j * .5, .6, (r, r + 7, r + 12, r + 7)[j % 4], 70 if j % 2 == 0 else 54)
        for st, d, c in after(cev, 2):
            s.note(3, st, 1.5, root_in(chord(c)[0], 38, 50), 92)
    elif n == "Clockwork":
        s.inst(0, 80, 45, volume=96, pan=60); s.inst(1, 38, 20, volume=64, pan=64); s.inst(2, 89, 85, volume=60, pan=40)
        lead(0, 92)
        for st, d, c in cev:
            r = root_in(chord(c)[0], 31, 43)
            for j in range(8):
                s.note(1, st + j * .5, .4, r + (12 if j % 4 == 3 else 0), 86 if j % 2 == 0 else 66)
        drums([(j, 36, 76) for j in range(4)], cev)
        drums([(1, 38, 96), (3, 38, 96)] + [(j * .5, 42, 60 if j % 2 == 0 else 44) for j in range(8)], after(cev, 1))
        pad(2, after(cev, 2), 55, 69, 50)
    elif n == "Elegy":
        s.inst(0, 0, 90, volume=120, pan=62); s.inst(1, 42, 80, volume=54, pan=40); s.inst(2, 48, 95, volume=52, pan=64)
        lead(0, 92)
        for st, d, c in cev:
            s.note(1, st, d, root_in(chord(c)[0], 36, 47), 62)
        pad(2, after(cev, 1), 55, 69, 40)
    elif n == "Sunken Bell":
        s.inst(0, 11, 100, volume=112, pan=62); s.inst(1, 46, 90, volume=88, pan=36); s.inst(2, 52, 80, volume=66, pan=64)
        lead(0, 86)
        for st, d, c in cev:
            r, pcs = chord(c)
            t = tones(r, pcs, 48, 5)
            for j, idx in enumerate((0, 1, 2, 3, 4, 3, 2, 1, 2, 3)):
                s.note(1, st + j * .5, .8, t[idx], 58 if j % 2 == 0 else 46)
        pad(2, after(cev, 1), 55, 72, 44)
    # theory report on one pass
    one = [(a, b, c) for a, b, c in mel if a < loop]
    chords = [(st, chord(c)[1]) for st, d, c in cev if st < loop]
    strong = sorted({st for st, d, c in cev if st < loop} | ({b * bl + 2 for b in range(4)} if bl == 4 else set()))
    bass = [(st, d, root_in(chord(c)[0], 36, 47)) for st, d, c in cev if st < loop]
    print(f"{i:2d} {n} | distinct pitches in pass 1: {len({p for _, _, p in one})} | "
          f"opening: {nm(one[0][2])}->{nm(one[1][2])}->{nm(one[2][2])}")
    check2(n, k, chords, one, strong, others=[("bass", bass)], chromatic=m.get("chrom", ()))
    return s


if __name__ == "__main__":
    for i, m in enumerate(M, 1):
        build(i, m).write(f"{i:02d}_{m['name'].lower().replace(' ', '_')}.mid")
    print("wrote", len(M))
