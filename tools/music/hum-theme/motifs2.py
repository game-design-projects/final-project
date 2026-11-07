"""
DONJON MOTIFS, SET 2: five new, contrasting motifs (none is Hometown).
Each is an 8-bar melody (4+4: an antecedent that ends open, a consequent that ends closed or
leads back to the loop) over a looping chord progression, written as scale degrees and checked
against the theory rules. Every motif is rendered as two passes of the loop.

  1 LANTERN WALTZ      G major, 3/4, 96 BPM   I vi IV V | vi IV ii-V I        warm folk, safe-room feel
  2 ASHEN HALLS        A minor, 4/4, 72 BPM   i VII VI V (Andalusian) x2     dungeon, dread, Oblivion-ish
  3 GLASS OBSERVATORY  C Lydian, 4/4, 100 BPM Imaj7 II Imaj7 V | vi7 II iii7 V   magic, wonder, secrets
  4 IRON PULSE         D Dorian, 4/4, 138 BPM i IV i VII | i III IV v         combat, urgency
  5 WINTER SHRINE      E minor, 4/4, 66 BPM   i VI III VII x2                  grief, tenderness, endings

Shared design rules (from the theory notes):
  - one short cell (2-4 notes with a clear rhythm) is stated, then answered or sequenced downward
  - no rising-sequence climbs; one high point per 8 bars
  - chord tones on strong beats, non-chord notes only passing on weak beats
  - bars 1-4 end open, bars 5-8 end closed or lead back into bar 1
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from musiclib import Key, Song, voice, nm

LOOPS = 2
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
QUAL = {"": [0, 4, 7], "m": [0, 3, 7], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10]}


def chord(name):
    """(bass pitch class, chord pitch classes). 'D/F#' = D major over an F# bass (inversion)."""
    name, _, bass = name.partition("/")
    if bass:
        return chord(bass)[0], chord(name)[1]
    r, i = PC[name[0]], 1
    if len(name) > 1 and name[1] in "#b":
        r += 1 if name[1] == "#" else -1
        i = 2
    return r % 12, [(r + x) % 12 for x in QUAL[name[i:]]]


def root_in(pc, lo, hi):
    return next(p for p in range(lo, hi + 1) if p % 12 == pc)


def mel_notes(k, bars, bar_len):
    out = []
    for b, bar in enumerate(bars):
        for off, dur, d in bar:
            p = d[1] if isinstance(d, tuple) else k.p(d)       # ("c", midi) = deliberate chromatic note
            out.append((b * bar_len + off, dur, p))
    return out


def chord_events(bars, bar_len):
    ev = []
    for b, c in enumerate(bars):
        parts = c if isinstance(c, list) else [(0, c)]
        for i, (off, n) in enumerate(parts):
            end = parts[i + 1][0] if i + 1 < len(parts) else bar_len
            ev.append((b * bar_len + off, end - off, n))
    return ev


def rep(ev, length):
    return [(e[0] + i * length,) + tuple(e[1:]) for i in range(LOOPS) for e in ev]


def voicings(cev, lo, hi):
    prev, out = None, []
    for s, d, n in cev:
        v = voice(chord(n)[1], prev, lo, hi)
        prev = v
        out.append((s, d, v))
    return out


def swell_pts(total_bars, bl, lo=70, hi=100):
    return sum(([(b * bl, lo), (b * bl + bl / 2, hi), (b * bl + bl - 0.1, lo + 6)] for b in range(total_bars)), [])


def check2(label, key, chords, melody, strong, others=(), chromatic=()):
    allowed = key.pcs() | set(chromatic)
    out = [nm(p) for _, _, p in melody if p % 12 not in allowed]
    hits = tot = 0
    for t in strong:
        snd = [p for s, d, p in melody if s <= t < s + d]
        prior = [c for cs, c in chords if cs <= t]
        if snd and prior:
            tot += 1
            hits += snd[0] % 12 in {c % 12 for c in prior[-1]}
    seq = sorted(melody)
    leaps = [f"{nm(a[2])}-{nm(b[2])}" for a, b, c in zip(seq, seq[1:], seq[2:])
             if abs(b[2] - a[2]) > 4 and not (0 < abs(c[2] - b[2]) <= 2 and (b[2] > a[2]) != (c[2] > b[2]))]

    def at(line, t):
        s = [p for st, d, p in line if st <= t < st + d]
        return s[0] if s else None

    par = []
    for name, line in others:
        prev = None
        for t in sorted({s for s, _, _ in melody} | {s for s, _, _ in line}):
            a, b = at(melody, t), at(line, t)
            if a is None or b is None:
                prev = None
                continue
            if prev and prev[0] != a and prev[1] != b and (a - b) % 12 in (0, 7) and (prev[0] - prev[1]) % 12 == (a - b) % 12:
                par.append(f"{name}@{t}")
            prev = (a, b)
    ps = [p for _, _, p in melody]
    print(f"  [{label}] out-of-key: {out or 'none'} | chord tones on strong beats: {hits}/{tot} | "
          f"leaps not recovered: {leaps or 'none'} | parallel 5ths/8ves vs bass: {par or 'none'} | "
          f"range {nm(min(ps))}-{nm(max(ps))}")
    print("   melody:", " ".join(nm(p) for _, _, p in sorted(melody)))


def finish(s, name, k, mel, cev, bl, chrom=()):
    chords = [(st, chord(n)[1]) for st, d, n in cev]
    strong = sorted({st for st, d, n in cev} | ({b * bl + 2 for b in range(8)} if bl == 4 else set()))
    bass = [(st, d, root_in(chord(n)[0], 36, 47)) for st, d, n in cev]
    check2(name, k, chords, mel, strong, others=[("bass", bass)], chromatic=chrom)


# ------------------------------------------------------------------ 1  LANTERN WALTZ
def m1():
    k, bl = Key(67, "major"), 3                      # 0 = G4
    chs = ["G", "Em", "C", "D/F#", "Em", "C", [(0, "Am"), (1.5, "D")], "G"]   # D/F#: bass steps F# - E, no parallel 5ths with the A
    bars = [
        [(0, 1, 0), (1, 1, 2), (2, 1, 4)],              # G B D  rising arpeggio (the hook)
        [(0, 2, 5), (2, 1, 4)],                          # E D
        [(0, 2, 3), (2, 1, 2)],                          # C B    the line steps down
        [(0, 3, 1)],                                     # A      open (5th of D)
        [(0, 1, 2), (1, 1, 5), (2, 1, 7)],               # B E G  the hook again, Em arpeggio, to the peak
        [(0, 2, 7), (2, 1, 5)],                          # G E
        [(0, 1.5, 5), (1.5, 1.5, 4)],                    # E (Am) D (D)
        [(0, 1, 2), (1, 2, 0)],                          # B G    closed
    ]
    mel, cev = mel_notes(k, bars, bl), chord_events(chs, bl)
    s = Song("Lantern Waltz", 96)
    s.inst(0, 21, reverb=70, volume=108, pan=60)         # accordion
    s.inst(1, 24, reverb=60, volume=88, pan=84)          # nylon guitar
    s.inst(2, 45, reverb=55, volume=90, pan=50)          # pizzicato bass
    s.inst(3, 48, reverb=85, volume=66, pan=44)          # strings
    for n in rep(mel, 8 * bl):
        s.note(0, *n, 90)
    full = rep(cev, 8 * bl)
    prev = None
    for st, d, n in full:                                # oom-pah-pah
        r, pcs = chord(n)
        v = voice(pcs, prev, 55, 69)
        prev = v
        s.note(1, st, 0.9, root_in(r, 43, 54), 78)
        s.note(2, st, 0.9, root_in(r, 36, 47), 84)
        for off in (1, 2):
            if off < d - 0.01:
                s.strum(1, st + off, 0.8, v, 58, spread=0.02)
    for st, d, v in voicings(full, 55, 70):
        for p in v:
            s.note(3, st, d, p, 42)
    s.swell(3, swell_pts(8 * LOOPS, bl, 66, 92))
    finish(s, "1 Lantern Waltz", k, mel, cev, bl)
    return s


# ------------------------------------------------------------------ 2  ASHEN HALLS
def m2():
    k, bl = Key(69, "minor"), 4                      # 0 = A4
    chs = ["Am", "G/B", "F/A", "E"] * 2              # bass A B A E: stepwise, and no parallel octaves with the melody
    GS = ("c", 68)                                   # G#4: leading tone of E major (harmonic-minor V)
    bars = [
        [(0, 1.5, 4), (1.5, .5, 3), (2, 1, 2), (3, 1, 0)],    # E D C A   falling "sigh"
        [(0, 1.5, 3), (1.5, .5, 2), (2, 1, 1), (3, 1, -1)],   # D C B G   the sigh a step lower
        [(0, 1, 0), (1, 1, 2), (2, 2, 5)],                    # A C F     the one rise, to the b6
        [(0, 3, 4)],                                          # E         F falls to E: open
        [(0, 1.5, 4), (1.5, .5, 3), (2, 1, 2), (3, 1, 0)],    # the sigh returns
        [(0, 1.5, 3), (1.5, .5, 2), (2, 1, 1), (3, 1, -1)],
        [(0, 2, 0), (2, 1, -2), (3, 1, 0)],                   # A F A    settles low, a step up from bar 6's G
        [(0, 1.5, GS), (1.5, .5, 1), (2, 2, 4)],              # G# B E   leading tone rises, back into bar 1
    ]
    mel, cev = mel_notes(k, bars, bl), chord_events(chs, bl)
    s = Song("Ashen Halls", 72)
    s.inst(0, 68, reverb=95, volume=112, pan=62)         # oboe
    s.inst(1, 42, reverb=80, volume=96, pan=36)          # cello ostinato
    s.inst(2, 52, reverb=100, volume=70, pan=64)         # choir
    s.inst(3, 47, reverb=90, volume=84, pan=64)          # timpani
    for n in rep(mel, 32):
        s.note(0, *n, 88)
    full = rep(cev, 32)
    for st, d, n in full:
        r, pcs = chord(n)
        root = root_in(r, 36, 47)
        pat = [root, root + 7, root + 12, root + 7]
        for i in range(8):
            s.note(1, st + i * 0.5, 0.6, pat[i % 4], 72 if i % 2 == 0 else 56)
        s.note(3, st, 2.5, root_in(r, 38, 52), 66)
    for st, d, v in voicings(full, 55, 69):
        for p in v:
            s.note(2, st, d, p, 44)
    s.swell(2, swell_pts(8 * LOOPS, bl, 60, 96))
    finish(s, "2 Ashen Halls", k, mel, cev, bl, chrom=[8])
    return s


# ------------------------------------------------------------------ 3  GLASS OBSERVATORY
def m3():
    k, bl = Key(60, "lydian"), 4                     # 0 = C4, #4 = F#
    chs = ["Cmaj7", "D", "Cmaj7", "G", "Am7", "D", "Em7", "G"]
    bars = [
        [(0, 1, 9), (1, 1, 11), (2, 2, 13)],                  # E G B   up to the major 7th
        [(0, 1.5, 12), (1.5, .5, 10), (2, 2, 8)],             # A F# D  down, F# is the Lydian colour
        [(0, 1, 9), (1, 1, 11), (2, 2, 14)],                  # E G C   same start, higher end
        [(0, 1, 13), (1, 1, 11), (2, 2, 13)],                 # B G B   open, ends a step below bar 5's C
        [(0, 1, 14), (1, 1, 12), (2, 2, 9)],                  # C A E   answer: falls
        [(0, 1, 10), (1, 1, 12), (2, 2, 15)],                 # F# A D  the peak (D6)
        [(0, 1.5, 13), (1.5, .5, 11), (2, 2, 9)],             # B G E
        [(0, 2, 8), (2, 2, 11)],                              # D G     steps down from E, rises into bar 1
    ]
    mel, cev = mel_notes(k, bars, bl), chord_events(chs, bl)
    s = Song("Glass Observatory", 100)
    s.inst(0, 8, reverb=80, volume=127, pan=62)          # celesta
    s.inst(1, 46, reverb=85, volume=66, pan=34)          # harp, rolling 16ths
    s.inst(2, 89, reverb=95, volume=52, pan=64)          # warm pad
    s.inst(3, 43, reverb=70, volume=62, pan=64)          # contrabass
    s.inst(4, 9, reverb=85, volume=70, pan=66)           # glockenspiel, melody an octave up for sparkle
    for n in rep(mel, 32):
        s.note(0, *n, 104)
        s.note(4, n[0], n[1], n[2] + 12, 62)
    full = rep(cev, 32)
    for st, d, n in full:
        r, pcs = chord(n)
        p = root_in(r, 48, 59)
        tones = [p]
        for i in range(1, 5):
            q = tones[-1] + 1
            while q % 12 != pcs[i % len(pcs)]:
                q += 1
            tones.append(q)
        idx = [0, 1, 2, 3, 4, 3, 2, 1]
        for i in range(16):
            s.note(1, st + i * 0.25, 0.55, tones[idx[i % 8]], 66 if i % 4 == 0 else 48)
        s.note(3, st, d, root_in(r, 33, 45), 70)
    for st, d, v in voicings(full, 55, 72):
        for p in v:
            s.note(2, st, d, p, 42)
    s.swell(2, swell_pts(8 * LOOPS, bl, 64, 94))
    finish(s, "3 Glass Observatory", k, mel, cev, bl)
    return s


# ------------------------------------------------------------------ 4  IRON PULSE
def m4():
    k, bl = Key(62, "dorian"), 4                     # 0 = D4
    # inversions (Dm/F, Am/C) give contrary motion against the melody's falling arpeggios
    chs = ["Dm", "G", "Dm/F", "C", "Dm/F", "F", "G", "Am/C"]
    bars = [
        [(0, 1.5, 4), (1.5, .5, 7), (2, 2, 9)],               # A D F    the call: dotted rhythm, rising
        [(0, 1.5, 10), (1.5, .5, 9), (2, 2, 7)],              # G F D    falls
        [(0, 1.5, 4), (1.5, .5, 7), (2, 1, 9), (3, 1, 11)],   # A D F A  call again, one note more
        [(0, 1.5, 10), (1.5, .5, 8), (2, 2, 6)],              # G E C    open on the b7 chord
        [(0, 1.5, 14), (1.5, .5, 11), (2, 2, 9)],             # D A F    from the peak (D6), falling...
        [(0, 1.5, 13), (1.5, .5, 11), (2, 2, 9)],             # C A F    ...a step lower
        [(0, 1.5, 12), (1.5, .5, 10), (2, 2, 7)],             # B G D    ...and again (B natural: Dorian)
        [(0, 1.5, 8), (1.5, .5, 6), (2, 2, 4)],               # E C A    lands on bar 1's first note
    ]
    mel, cev = mel_notes(k, bars, bl), chord_events(chs, bl)
    s = Song("Iron Pulse", 138)
    s.inst(0, 61, reverb=60, volume=127, pan=60)         # brass section
    s.inst(1, 33, reverb=30, volume=72, pan=64)         # fingered bass
    s.inst(2, 44, reverb=70, volume=70, pan=40)          # tremolo strings
    s.inst(3, 116, reverb=75, volume=64, pan=64)         # taiko
    s.inst(4, 57, reverb=60, volume=76, pan=72)          # trombone, melody an octave down
    full_m = rep(mel, 32)
    for n in full_m:
        s.note(0, *n, 92)
        s.note(4, n[0], n[1], n[2] - 12, 70)
    full = rep(cev, 32)
    for st, d, n in full:
        r, pcs = chord(n)
        root = root_in(r, 34, 45)
        pat = [0, 0, 12, 0, 0, 12, 0, 7]
        for i in range(8):
            s.note(1, st + i * 0.5, 0.45, root + pat[i], 84 if i % 2 == 0 else 66)
        s.note(3, st, 1, root_in(r, 38, 50), 92)
        s.note(3, st + 2, 1, root_in(r, 38, 50), 80)
        for t in (0, 2, 3.5):
            s.note(9, st + t, 0.25, 36, 78)
        for t in (1, 3):
            s.note(9, st + t, 0.25, 38, 86)
        for i in range(8):
            s.note(9, st + i * 0.5, 0.25, 42, 70 if i % 2 == 0 else 46)
    for i in range(LOOPS):
        s.note(9, i * 32, 2, 49, 100)
    for st, d, v in voicings(full, 55, 69):
        for p in v:
            s.note(2, st, d, p, 58)
    s.swell(2, swell_pts(8 * LOOPS, bl, 78, 110))
    finish(s, "4 Iron Pulse", k, mel, cev, bl)
    return s


# ------------------------------------------------------------------ 5  WINTER SHRINE
def m5():
    k, bl = Key(64, "minor"), 4                      # 0 = E4
    chs = ["Em", "C", "G", "D"] * 2
    bars = [
        [(0, 2, 4), (2, 1.5, 7), (3.5, .5, 6)],               # B E D   up a 4th, step back
        [(0, 2, 7), (2, 1.5, 5), (3.5, .5, 4)],               # E C B   the answer: inverted, falls
        [(0, 2, 6), (2, 1.5, 9), (3.5, .5, 8)],               # D G F#  the cell again, from D
        [(0, 2, 8), (2, 1, 7), (3, 1, 6)],                    # F# E D  open
        [(0, 2, 4), (2, 1.5, 7), (3.5, .5, 6)],               # the cell returns
        [(0, 2, 7), (2, 1.5, 5), (3.5, .5, 4)],
        [(0, 1, 6), (1, 1, 9), (2, 2, 11)],                   # D G B   the one high point
        [(0, 1.5, 10), (1.5, .5, 8), (2, 2, 6)],              # A F# D  falls home
    ]
    mel, cev = mel_notes(k, bars, bl), chord_events(chs, bl)
    s = Song("Winter Shrine", 66)
    s.inst(0, 42, reverb=85, volume=108, pan=62)         # solo cello
    s.inst(1, 0, reverb=80, volume=82, pan=36)           # piano arpeggios
    s.inst(2, 48, reverb=95, volume=62, pan=64)          # strings
    s.inst(3, 43, reverb=75, volume=84, pan=64)          # contrabass
    for n in rep(mel, 32):
        s.note(0, *n, 86)
    s.swell(0, sum(([(b * 2, 84), (b * 2 + 1, 110), (b * 2 + 1.9, 90)] for b in range(8 * LOOPS * 2)), []))
    full = rep(cev, 32)
    for st, d, n in full:
        r, pcs = chord(n)
        t0 = root_in(r, 40, 51)
        t1 = next(q for q in range(t0 + 1, t0 + 13) if q % 12 == pcs[2])
        t2 = t0 + 12
        t3 = next(q for q in range(t2 + 1, t2 + 13) if q % 12 == pcs[1])
        pat = [t0, t1, t2, t3, t2, t1, t2, t1]
        for i in range(8):
            s.note(1, st + i * 0.5, 0.8, pat[i], 60 if i % 2 == 0 else 46)
        s.note(3, st, d, root_in(r, 31, 43), 70)
    for st, d, v in voicings(full, 52, 68):
        for p in v:
            s.note(2, st, d, p, 40)
    s.swell(2, swell_pts(8 * LOOPS, bl, 60, 90))
    finish(s, "5 Winter Shrine", k, mel, cev, bl)
    return s


if __name__ == "__main__":
    names = [("m1_lantern_waltz", m1), ("m2_ashen_halls", m2), ("m3_glass_observatory", m3),
             ("m4_iron_pulse", m4), ("m5_winter_shrine", m5)]
    for fn, f in names:
        f().write(f"{fn}.mid")
    print("wrote", len(names), "midi files")
