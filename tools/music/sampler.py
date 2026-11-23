"""Donjon's music, mixed and mastered: the scores `build-themes.py` writes, the generated stone hall they
all play in, and the loudness and the knee every track leaves through.

The notes themselves are played by `orchestra.py` (VSCO-2 CE); this module holds the timeline
(`Score`), the filters, the hall (`hall_ir`, `reverb`), the mix (`mix`, `voice`) and the master
(`master`, `write`). `orchestra.use()` sets `render_note`, so a Score plays whatever player is in.

A `Score` is a set of stereo stems on a circular timeline, so a note or a reverb tail that runs past
the end wraps to the start and the loop point is seamless; a loop file is the loop plus a repeat of
its first TAIL seconds. Notes are panned equal-power with a few ms of humanising jitter, seeded, so a
build is repeatable.
"""
import functools
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate

SR = 44100
TAIL = 1.0  # loop files repeat their first second, so the player can loop inside the file
# Mastered loudness (RMS, dBFS) of each kind of track. Fights and stings share one level, so the
# volumes in src/audio/ambient.gd treat them alike; explore is mastered softer, as background.
EXPLORE_RMS_DB = -19.0
BATTLE_RMS_DB = -17.0
rng = np.random.default_rng(1981)  # the year of Wizardry

# ---------------------------------------------------------------- note names

_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_FLATS = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
_SHARPS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def midi(name):
    """'A4' -> 69, 'Bb3' -> 58, 'C#5' -> 73."""
    acc, rest = 0, name[1:]
    while rest and rest[0] in "#b":
        acc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + _PC[name[0]] + acc


def name(m, flats=(10, 3, 8)):
    """Spell a MIDI note; pitch classes in `flats` are spelled flat (default Bb, Eb, Ab), the rest sharp."""
    return f"{(_FLATS if m % 12 in flats else _SHARPS)[m % 12]}{m // 12 - 1}"


def extend(x, n):
    """Make a sustained sample at least n long by looping its steady part with a matched crossfade."""
    if len(x) >= n:
        return x
    F = int(0.1 * SR)
    a = int(0.9 * SR) if len(x) > 2 * SR else len(x) // 3
    ref = x[a - F : a]
    hi = len(x) - int(0.08 * SR)
    lo = max(a + F + int(0.5 * SR), hi - int(0.5 * SR))
    win = x[lo - F : hi]
    c = correlate(win, ref, mode="valid", method="fft")
    energy = np.sqrt(np.convolve(win**2, np.ones(F), mode="valid"))
    b = lo + int(np.argmax(c / (energy + 1e-12)))
    w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, F))
    out = [x[:b]]
    have = b
    while have < n:
        last = out[-1]
        last[-F:] = last[-F:] * (1 - w) + x[a - F : a] * w
        seg = x[a:b].copy()
        out.append(seg)
        have += len(seg)
    return np.concatenate(out)


# ---------------------------------------------------------------- the score: stems on a timeline


def render_note(inst, m, dur, vel=1.0):
    """One note as a mono signal (dur the written seconds, vel 0..1). `orchestra.use()` replaces this with the
    recorded orchestra's renderer, which the tunes are played on; a score rendered without a player says so."""
    raise RuntimeError("no player: call orchestra.use() before rendering a score")


class Score:
    """A set of stereo stems on a timeline. With loop=True the timeline is circular (length = the loop);
    otherwise it is length + `pad` seconds of room for tails, trimmed again by master()."""

    def __init__(self, seconds, loop=True, pad=4.0):
        self.loop = loop
        self.n = int(round(seconds * SR))
        self.size = self.n if loop else self.n + int(pad * SR)
        self.stems = {}
        self.count = 0

    def add(self, stem, sig, t, pan=0.0):
        """Add a mono signal at t seconds, equal-power panned (-1 left .. 1 right)."""
        buf = self.stems.setdefault(stem, np.zeros((2, self.size)))
        i = int(round(t * SR))
        theta = (pan + 1) * np.pi / 4
        gl, gr = np.cos(theta) * np.sqrt(2), np.sin(theta) * np.sqrt(2)
        if self.loop:
            sig = sig[: self.size]
            idx = (i + np.arange(len(sig))) % self.size
            buf[0, idx] += sig * gl
            buf[1, idx] += sig * gr
        else:
            sig = sig[: max(0, self.size - i)]
            buf[0, i : i + len(sig)] += sig * gl
            buf[1, i : i + len(sig)] += sig * gr

    def note(self, stem, inst, m, t, dur, vel=1.0, pan=0.0, jitter=0.006):
        """Play a sampled note: m is a MIDI number or a name like 'D4'."""
        m = midi(m) if isinstance(m, str) else m
        if jitter:
            t += rng.uniform(-jitter, jitter)
            vel *= rng.uniform(0.95, 1.03)
        self.add(stem, render_note(inst, m, dur, vel), max(0.0, t) if not self.loop else t, pan)
        self.count += 1


# ---------------------------------------------------------------- the hall, filters, master


def spectrum_filter(x, gain_of_freq):
    """Zero-phase filter in the frequency domain. Circular, so on a loop it stays seamless."""
    freqs = np.fft.rfftfreq(x.shape[-1], 1 / SR)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * gain_of_freq(freqs), x.shape[-1], axis=-1)


def lowpass(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def highpass(fc, order=2):
    return lambda f: (f / fc) ** order / np.sqrt(1 + (f / fc) ** (2 * order))


@functools.lru_cache(None)
def hall_ir(seconds=3.6):
    """A stone hall: 20 ms pre-delay, a handful of early reflections off near walls, then a dense tail
    that decays slower in the lows (RT60 ~2.8 s) than the highs (~0.9 s above 5 kHz). Seeded, so every
    track is rendered in the very same room."""
    r = np.random.default_rng(1981)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    freqs = np.fft.rfftfreq(n, 1 / SR)
    edge = lambda f0: 1 / (1 + (freqs / f0) ** 6)
    bands = [(0, 300, 2.8, 0.9), (300, 1500, 2.3, 1.0), (1500, 5000, 1.5, 0.7), (5000, 12000, 0.9, 0.3)]
    ir = np.zeros((2, n))
    for ch in range(2):
        spec = np.fft.rfft(r.standard_normal(n))
        for lo, hi, rt60, gain in bands:
            mask = edge(hi) * (1 - edge(lo) if lo else 1)
            ir[ch] += gain * np.fft.irfft(spec * mask, n) * np.exp(-6.91 * t / rt60)
    ir *= 1 - np.exp(-t / 0.04)  # the tail builds up rather than starting at full density
    early = np.sqrt(np.mean(ir[:, : int(0.1 * SR)] ** 2))
    for k in range(8):  # early reflections off near walls, alternating sides
        d = int((0.011 + 0.008 * k + r.uniform(0, 0.004)) * SR)
        ir[k % 2, d] += 20 * early * 0.8**k
    pre = int(0.02 * SR)
    ir = np.concatenate([np.zeros((2, pre)), ir[:, : n - pre]], axis=1)
    ir = spectrum_filter(ir, lowpass(7000, 1))  # stone soaks up the fizz
    return ir / np.sqrt((ir**2).sum() / 2)


def reverb(x):
    """Convolve a stereo signal with the hall (circularly, over the signal's length)."""
    ir = hall_ir()
    n = x.shape[-1]
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * np.fft.rfft(ir, n, axis=-1), n, axis=-1)


def db(x):
    return 20 * np.log10(max(x, 1e-12))


def rms(x):
    return float(np.sqrt(np.mean(np.square(x))))


def mix(score, levels, sends, eq=None, wet=1.0, sections=None):
    """Sum the stems: each at its gain (dB), each sent into the hall by its own amount. Logs every
    stem's loudness (dB RMS, relative to the whole mix) per section: [(label, start s, end s)], so the
    balance of lead against accompaniment can be read off without ears."""
    eq = eq or {}
    sections = sections or [("all", 0, score.size / SR)]
    dry = np.zeros((2, score.size))
    hall = np.zeros((2, score.size))
    rows = {}
    for stem, x in score.stems.items():
        if stem in eq:
            x = spectrum_filter(x, eq[stem])
        x = x * 10 ** (levels.get(stem, 0) / 20)
        rows[stem] = x
        dry += x
        hall += x * sends.get(stem, 0.3)
    out = dry + wet * reverb(hall)
    cut = lambda x, a, b: x[:, int(a * SR) : int(b * SR)]
    print("    stem loudness, dB relative to the mix in each section (blank = silent):", file=sys.stderr)
    print("      " + " " * 12 + "".join(f"{s[0][:9]:>10s}" for s in sections), file=sys.stderr)
    for stem, x in rows.items():
        cells = []
        for _, a, b in sections:
            r, ref = rms(cut(x, a, b)), rms(cut(out, a, b))
            cells.append(f"{db(r) - db(ref):10.1f}" if r > ref * 1e-3 else " " * 10)
        print(f"      {stem:12s}" + "".join(cells) + f"   send {sends.get(stem, 0.3):.2f}", file=sys.stderr)
    return out


def master(x, target_db, ceiling=0.89, length=None, fade=0.0):
    """Clear rumble, set the loudness (RMS in dBFS), then a soft knee so only rare peaks are rounded
    off under the ceiling. For a one-shot, trim to `length` seconds with a `fade`-second fade-out;
    its loudness is measured before the fade, so a sting is as loud as a loop while it plays."""
    x = spectrum_filter(x, highpass(32, 2))
    body = x
    if length is not None:
        x = x[:, : int(length * SR)]
        body = x[:, : x.shape[1] - int(fade * SR)]
        if fade:
            k = int(fade * SR)
            x[:, -k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    x = x * 10 ** (target_db / 20) / rms(body)
    knee = 0.7 * ceiling
    a = np.abs(x)
    over = a > knee
    x[over] = np.sign(x[over]) * (knee + (ceiling - knee) * np.tanh((a[over] - knee) / (ceiling - knee)))
    return x, int(over.sum())


def write(path, x, loop=True):
    """Write 16-bit WAV with TPDF dither. A loop gets its first TAIL seconds appended."""
    out = np.concatenate([x, x[:, : int(TAIL * SR)]], axis=1) if loop else x
    dither = (rng.random(out.shape) - rng.random(out.shape)) / 32768
    wavfile.write(path, SR, np.round((out + dither).T * 32767).clip(-32768, 32767).astype(np.int16))
    return out


def report(label, x, knee_hits=0, loop=True):
    """Engineer's ears: level, peak, NaNs, spectral balance and (for loops) the seam."""
    assert np.isfinite(x).all(), f"{label}: NaN or inf in the render"
    peak = np.abs(x).max()
    freqs = np.fft.rfftfreq(x.shape[-1], 1 / SR)
    power = (np.abs(np.fft.rfft(x, axis=-1)) ** 2).sum(0)
    bands = [(20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 20000)]
    total = power[(freqs >= 20)].sum()
    bal = " ".join(f"{lo}-{hi}:{100 * power[(freqs >= lo) & (freqs < hi)].sum() / total:4.1f}%" for lo, hi in bands)
    line = f"  {label}: {x.shape[-1] / SR:.3f}s  rms {db(rms(x)):.1f} dBFS  peak {db(peak):.1f} dBFS  knee hits {knee_hits}\n    spectrum {bal}"
    if loop:
        step = np.abs(np.diff(x, axis=1))
        seam = np.abs(x[:, 0] - x[:, -1]).max()
        line += f"\n    seam jump {seam:.4f} (typical step p99.9 {np.percentile(step, 99.9):.4f}, max {step.max():.4f})"
    print(line, file=sys.stderr)
    return dict(rms_db=db(rms(x)), peak_db=db(peak))


# ---------------------------------------------------------------- a little harmony


def check_outer_voices(label, pairs):
    """pairs: [(time, melody midi, bass midi)] at every point either moves. Flags parallel fifths and
    octaves between the outer voices (both move, same direction, same perfect interval)."""
    bad = []
    for (_, m0, b0), (t1, m1, b1) in zip(pairs, pairs[1:]):
        if m0 is None or m1 is None or b0 is None or b1 is None or m0 == m1 or b0 == b1:
            continue
        i0, i1 = (m0 - b0) % 12, (m1 - b1) % 12
        if i0 == i1 and i0 in (0, 7) and np.sign(m1 - m0) == np.sign(b1 - b0):
            bad.append(f"{t1:.2f}s {name(m0)}/{name(b0)} -> {name(m1)}/{name(b1)}")
    print(f"  {label}: outer voices checked at {len(pairs)} points, parallel 5ths/8ves: {', '.join(bad) or 'none'}", file=sys.stderr)
    return bad


def voice(pcs, prev, lo, hi, n=3):
    """Voice a chord (pitch classes, root first) as n notes in [lo, hi], moving as little as possible
    from `prev` (smooth voice leading), with the root and third always present."""
    import itertools

    cands = [m for m in range(lo, hi + 1) if m % 12 in pcs]
    if len(cands) < n + 1:
        return voice(pcs, prev, lo - 2, hi + 2, n)  # too tight for this chord: give it a little room
    best = None
    for combo in itertools.combinations(cands, n):
        got = {c % 12 for c in combo}
        if pcs[0] not in got or (len(pcs) > 1 and pcs[1] not in got):
            continue
        if len(pcs) >= 3 and n >= 3 and len(got) < min(3, len(pcs)):
            continue
        cost = sum(abs(a - b) for a, b in zip(combo, prev)) if prev else abs(sum(combo) / n - (lo + hi) / 2)
        cost += 6 * sum(b - a < 3 for a, b in zip(combo, combo[1:]))  # avoid seconds: keeps it clean
        if best is None or cost < best[0]:
            best = (cost, combo)
    if best is None:
        return voice(pcs, prev, lo - 2, hi + 2, n)
    return list(best[1])
