"""Small composing toolkit: keys/modes, voicing, a MIDI song builder with humanising,
strums and expression swells, and a theory checker."""
import itertools
import random

import mido

TPB = 480
MODES = {
    "major":      [2, 2, 1, 2, 2, 2, 1],
    "minor":      [2, 1, 2, 2, 1, 2, 2],
    "dorian":     [2, 1, 2, 2, 2, 1, 2],
    "mixolydian": [2, 2, 1, 2, 2, 1, 2],
    "lydian":     [2, 2, 2, 1, 2, 2, 1],
}
NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]


def nm(p):
    return f"{NAMES[p % 12]}{p // 12 - 1}"


class Key:
    def __init__(self, tonic, mode):
        self.tonic, self.mode = tonic, mode

    def p(self, degree, octave_shift=0):
        """Scale degree (0 = tonic; negative or > 6 crosses octaves) -> MIDI pitch."""
        octv, step = divmod(degree, 7)
        return self.tonic + 12 * (octv + octave_shift) + sum(MODES[self.mode][:step])

    def pcs(self):
        return {self.p(d) % 12 for d in range(7)}


def voice(pcs, prev=None, lo=50, hi=74, span=15):
    """Voicing of the given pitch classes in [lo, hi] with the smallest total movement from prev."""
    best = None
    opts = [[p for p in range(lo, hi + 1) if p % 12 == pc] for pc in pcs]
    for combo in itertools.product(*opts):
        v = sorted(combo)
        if v[-1] - v[0] > span or len(set(v)) < len(v):
            continue
        if any(b - a < 3 and a < 55 for a, b in zip(v, v[1:])):   # no seconds down low
            continue
        cost = sum(abs(a - b) for a, b in zip(v, prev)) if prev else v[0]
        if best is None or cost < best[0]:
            best = (cost, v)
    return best[1]


class Song:
    def __init__(self, title, bpm):
        self.title, self.bpm = title, bpm
        self.tracks, self.programs, self.cc, self.ccev = {}, {}, {}, {}
        self.rand = random.Random(title)

    def inst(self, ch, program, reverb=60, chorus=0, volume=100, pan=64):
        self.programs[ch] = program
        self.cc[ch] = {91: reverb, 93: chorus, 7: volume, 10: pan, 11: 100}

    def note(self, ch, start, dur, pitch, vel=90):
        self.tracks.setdefault(ch, []).append((start, dur, pitch, vel))

    def strum(self, ch, start, dur, pitches, vel=70, spread=0.035, down=True):
        order = sorted(pitches) if down else sorted(pitches, reverse=True)
        for i, p in enumerate(order):
            self.note(ch, start + i * spread, dur - i * spread, p, vel - 3 * i)

    def swell(self, ch, points, cc=11, step=0.125):
        """Linear expression automation through (beat, value) points."""
        ev = self.ccev.setdefault(ch, [])
        for (b0, v0), (b1, v1) in zip(points, points[1:]):
            n = max(1, int((b1 - b0) / step))
            for i in range(n):
                ev.append((b0 + i * (b1 - b0) / n, cc, round(v0 + (v1 - v0) * i / n)))
        ev.append((points[-1][0], cc, points[-1][1]))

    def write(self, path):
        mid = mido.MidiFile(ticks_per_beat=TPB)
        meta = mido.MidiTrack()
        meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(self.bpm)))
        meta.append(mido.MetaMessage("track_name", name=self.title))
        mid.tracks.append(meta)
        for ch in sorted(set(self.tracks) | set(self.ccev)):
            msgs = []
            if ch != 9:
                msgs.append((0, 0, mido.Message("program_change", channel=ch, program=self.programs[ch])))
            for c, v in self.cc.get(ch, {}).items():
                msgs.append((0, 0, mido.Message("control_change", channel=ch, control=c, value=v)))
            for b, c, v in self.ccev.get(ch, []):
                msgs.append((int(b * TPB), 1, mido.Message("control_change", channel=ch, control=c, value=v)))
            for start, dur, pitch, vel in self.tracks.get(ch, []):
                jitter = 0 if ch == 9 else self.rand.randint(-6, 6)
                v = max(1, min(127, vel + self.rand.randint(-5, 5)))
                t0 = max(0, int(start * TPB) + jitter)
                t1 = max(t0 + 10, int((start + dur) * TPB) - 8)
                msgs.append((t0, 2, mido.Message("note_on", channel=ch, note=pitch, velocity=v)))
                msgs.append((t1, 0, mido.Message("note_off", channel=ch, note=pitch, velocity=0)))
            msgs.sort(key=lambda m: (m[0], m[1]))
            tr, last = mido.MidiTrack(), 0
            for t, _, m in msgs:
                tr.append(m.copy(time=t - last))
                last = t
            mid.tracks.append(tr)
        mid.save(path)


def check(label, key, chords, melody, others=(), chromatic=()):
    """chords: [(start_beat, pitches)], melody: [(start, dur, pitch)],
    others: [(name, line)] lines checked against the melody for parallel 5ths/8ves."""
    allowed = key.pcs() | set(chromatic)
    out = [nm(p) for _, _, p in melody if p % 12 not in allowed]
    hits = tot = 0
    end = max(s + d for s, d, _ in melody)
    for t in range(0, int(end), 2):
        snd = [p for s, d, p in melody if s <= t < s + d]
        prior = [c for cs, c in chords if cs <= t]
        if snd and prior:
            tot += 1
            hits += snd[0] % 12 in {c % 12 for c in prior[-1]}
    seq = sorted(melody)
    bad_leaps = sum(1 for a, b, c in zip(seq, seq[1:], seq[2:])
                    if abs(b[2] - a[2]) > 4 and not (0 < abs(c[2] - b[2]) <= 2 and (b[2] > a[2]) != (c[2] > b[2])))

    def at(line, t):
        s = [p for st, d, p in line if st <= t < st + d]
        return s[0] if s else None

    par = []
    for name, line in others:
        times = sorted({s for s, _, _ in melody} | {s for s, _, _ in line})
        prev = None
        for t in times:
            a, b = at(melody, t), at(line, t)
            if a is None or b is None:
                prev = None
                continue
            if prev and prev[0] != a and prev[1] != b and (a - b) % 12 in (0, 7) and (prev[0] - prev[1]) % 12 == (a - b) % 12:
                par.append(f"{name} beat {t}: {nm(prev[1])}/{nm(prev[0])} -> {nm(b)}/{nm(a)}")
            prev = (a, b)
    ps = [p for _, _, p in melody]
    print(f"[{label}] out-of-key: {out or 'none'} | chord tones on beats 1 & 3: {hits}/{tot} | "
          f"unrecovered leaps: {bad_leaps} | parallel 5ths/8ves: {par or 'none'} | range {nm(min(ps))}-{nm(max(ps))}")
