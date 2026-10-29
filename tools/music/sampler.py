"""An offline sampler for Donjon's music, shared by build-ambient.py, build-battle.py and build-stings.py.

All three scores are played by the same small baroque band, from real samples in public/soundfonts
(MusyngKite, CC BY-SA 3.0; see public/CREDITS.txt): harpsichord, church organ, string ensemble, choir
"aahs", music box and tubular bells. Only the kettle drums (timpani) and a medieval tabor are synthesised
here. Everything plays in one generated stone hall, so the dungeon, the fights and the fanfares sound
like one game.

How a note is made:
  1. The note's sample is decoded once from the soundfont's base64 MP3 (ffmpeg, mono, 44.1 kHz), its
     leading silence trimmed and its level normalised (RMS over the first second), so every key of an
     instrument is equally loud.
  2. Tuning: the samples are not all in tune (the harpsichord runs up to 14 cents sharp in places).
     Each sample's pitch is measured two ways (harmonic sum on a fine spectrum, and YIN); when they
     agree within 6 cents the sample is resampled by their mean. When they disagree (the choir's
     vibrato fools one of them) it is left alone.
  3. A note the font lacks is pitch-shifted (band-limited resampling) from the nearest key it has;
     those gaps are listed in the build log.
  4. Sustained instruments (organ, strings, choir) only have 3.1 s samples, so long notes loop the
     sample's steady part, with the loop end chosen where the waveform best matches the loop start and
     a 100 ms crossfade over the joint.
  5. Attack and release envelopes per instrument, velocity (level), equal-power pan, a few ms of
     humanising jitter (seeded, so builds are deterministic).

Loops are rendered circularly: a note or a reverb tail that runs past the end wraps to the start, so
the loop point is seamless. A loop file is the loop plus a repeat of its first TAIL seconds.
"""
import base64
import functools
import json
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import correlate, resample

SR = 44100
TAIL = 1.0  # loop files repeat their first second, so the player can loop inside the file
# Mastered loudness (RMS, dBFS) of each kind of track. Fights and stings share one level, so the
# volumes in public/ambient.js treat them alike; explore is mastered softer, as background.
EXPLORE_RMS_DB = -19.0
BATTLE_RMS_DB = -17.0
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "public", "soundfonts")
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


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ---------------------------------------------------------------- instruments

# font: soundfont file; attack/release in seconds; sustain: loop long notes; ring: seconds a plucked
# or struck note keeps sounding after its written length (None = damped at release); offset: start the
# sample this far in (skips a slow bow attack, for marcato); gain: level trim; tune: correct tuning;
# lp: low-pass the sample (Hz). The music box's samples carry a mechanical tick, a one-sample jump of
# up to 0.97 full scale that reads as a click; 5 kHz takes it down to 0.2 and keeps the tone.
INSTRUMENTS = {
    "harpsichord": dict(font="mk_harpsichord", attack=0.0015, release=0.10, sustain=False, ring=None, gain=1.0, tune=True, lp=9000),
    "organ": dict(font="mk_church_organ", attack=0.05, release=0.30, sustain=True, ring=None, gain=0.8, tune=True),
    "strings": dict(font="mk_string_ensemble_1", attack=0.07, release=0.35, sustain=True, ring=None, gain=1.0, tune=True),
    "marcato": dict(font="mk_string_ensemble_1", attack=0.006, release=0.09, sustain=True, ring=None, gain=1.0, tune=True, offset=0.55),
    "choir": dict(font="mk_choir_aahs", attack=0.15, release=0.6, sustain=True, ring=None, gain=1.2, tune=True),
    "music_box": dict(font="mk_music_box", attack=0.002, release=0.3, sustain=False, ring=2.6, gain=0.9, tune=True, lp=5000),
    "bells": dict(font="mk_tubular_bells", attack=0.002, release=0.5, sustain=False, ring=3.0, gain=0.9, tune=False),
}
GAPS = set()  # (font, note) pairs the font lacked and we pitch-shifted
TUNED = {}  # (font, note) -> cents corrected


@functools.lru_cache(None)
def _font(font):
    with open(os.path.join(FONTS, f"{font}.json")) as f:
        return json.load(f)


def _decode(data_uri):
    raw = base64.b64decode(data_uri.split(",", 1)[1])
    p = subprocess.run(["ffmpeg", "-v", "error", "-i", "pipe:0", "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], input=raw, capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.float32).astype(np.float64)


def _cents_harmonic(x, f_expect):
    """Pitch by harmonic sum over a fine spectrum of the steady part, in cents from f_expect."""
    seg = x[int(0.6 * SR) : int(2.6 * SR)]
    nfft = 1 << 20
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), nfft))
    df = SR / nfft
    cents = np.arange(-50, 50.5, 0.5)
    ks = np.arange(1, 9)
    f = f_expect * 2 ** (cents[:, None] / 1200) * ks[None, :]
    score = (sp[np.clip(np.round(f / df).astype(int), 0, len(sp) - 1)] * (f < 8000) / np.sqrt(ks)).sum(1)
    return cents[np.argmax(score)]


def _cents_yin(x, f_expect):
    """Pitch by YIN difference function (median over frames, parabolic interpolation), in cents."""
    T = SR / f_expect
    W = int(max(2048, 6 * T))
    lags = np.arange(int(T * 0.95), int(T * 1.05) + 2)
    periods = []
    for s in range(int(0.5 * SR), int(2.7 * SR) - 2 * W, W):
        fr = x[s : s + 2 * W]
        d = np.array([np.sum((fr[:W] - fr[L : L + W]) ** 2) for L in lags])
        i = int(np.clip(np.argmin(d), 1, len(d) - 2))
        a, b, c = d[i - 1], d[i], d[i + 1]
        den = a - 2 * b + c
        periods.append(lags[i] + (0.5 * (a - c) / den if den else 0))
    return 1200 * np.log2((SR / np.median(periods)) / f_expect)


def _flatten(x, attack=0.25):
    """Level a sustained sample's slow loudness after its attack. The string samples swell by up to
    +6 dB around 1.2 s (a bow crescendo baked in), which bulges every long note; this keeps the
    attack's shape and holds the sustain steady at its median level."""
    w = int(0.2 * SR)
    env = np.sqrt(np.convolve(x**2, np.ones(w) / w, mode="same")) + 1e-9
    ia = int(attack * SR)
    ref = np.median(env[ia : len(x) - w])
    gain = np.empty_like(x)
    gain[:ia] = ref / env[ia]
    gain[ia:] = ref / env[ia:]
    gain = np.clip(gain, 0.3, 3.0)
    gain[len(x) - w :] = gain[len(x) - w - 1]  # the window runs off the end there; hold the last gain
    return x * gain


@functools.lru_cache(None)
def sample(inst, m):
    """The prepared mono sample for MIDI note m on an instrument: trimmed, in tune, level-normalised."""
    spec = INSTRUMENTS[inst]
    font = _font(spec["font"])
    have = {midi(k): k for k in font}
    src = m if m in have else min(have, key=lambda k: (abs(k - m), k))
    x = _decode(font[have[src]])
    on = np.argmax(np.abs(x) > 0.02 * np.abs(x).max())
    x = x[max(0, on - int(0.002 * SR)) :]
    shift = (m - src) * 100.0
    if src != m:
        GAPS.add((spec["font"], name(m)))
    if spec["tune"]:
        a, b = _cents_harmonic(x, hz(src)), _cents_yin(x, hz(src))
        if abs(a - b) <= 6 and abs((a + b) / 2) >= 2:
            shift -= (a + b) / 2
            TUNED[(spec["font"], have[src])] = -(a + b) / 2
    if abs(shift) > 0.5:
        x = resample(x, int(round(len(x) / 2 ** (shift / 1200))))
    if spec.get("offset"):
        x = x[int(spec["offset"] * SR) :]
    if spec["sustain"]:
        x = _flatten(x)
    if spec.get("lp"):
        pad = np.concatenate([np.zeros(4096), x, np.zeros(4096)])
        x = spectrum_filter(pad[None, :], lowpass(spec["lp"], 2))[0][4096:-4096]
    x = x / np.sqrt(np.mean(x[: SR] ** 2))
    return x * 0.1


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


def render_note(inst, m, dur, vel=1.0):
    """One note as a mono signal: dur is the written length in seconds, vel 0..1."""
    spec = INSTRUMENTS[inst]
    x = sample(inst, m)
    if spec["ring"] is not None:
        n = int((dur + spec["ring"]) * SR)
    else:
        n = int((dur + spec["release"]) * SR)
    if spec["sustain"]:
        x = extend(x, n)
    x = x[:n].copy()
    if len(x) < n:
        x = np.concatenate([x, np.zeros(n - len(x))])
    env = np.ones(n)
    na = max(1, int(spec["attack"] * SR))
    env[:na] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, na))
    nr = int(spec["release"] * SR)
    if spec["ring"] is None:
        start = n - nr
    else:
        start = n - nr  # a struck note rings, then is let go
    env[start:] *= np.linspace(1, 0, n - start) ** 2
    # never cut a decaying sample off at its end: fade the last 40 ms of what the font gave
    end = min(n, len(sample(inst, m)))
    if spec["sustain"] is False and end < n:
        k = int(0.04 * SR)
        env[end - k : end] *= np.linspace(1, 0, k)
        env[end:] = 0
    return x * env * spec["gain"] * vel**1.5


# ---------------------------------------------------------------- synthesised percussion


def timpani(m, vel=1.0, ring=2.2):
    """A kettle drum: the drum's modes (1, 1.5, 2, 2.5, 3 times the fundamental) with a slight pitch
    drop as the head relaxes, a soft felt-mallet thump, and a low body."""
    n = int(ring * SR)
    t = np.arange(n) / SR
    f0 = hz(m)
    glide = 1 + 0.025 * np.exp(-t / 0.05)
    out = np.zeros(n)
    for ratio, amp, decay in ((1.0, 1.0, 1.1), (1.5, 0.45, 0.7), (1.99, 0.3, 0.55), (2.44, 0.14, 0.35), (2.98, 0.08, 0.25), (0.62, 0.25, 0.25)):
        ph = 2 * np.pi * np.cumsum(f0 * ratio * glide) / SR
        out += amp * np.sin(ph + rng.uniform(0, 6.28)) * np.exp(-t / (decay * (0.6 + 0.4 * vel)))
    thump = rng.standard_normal(n) * np.exp(-t / 0.012)
    thump = np.convolve(thump, np.exp(-np.arange(64) / 10.0), mode="same") * 0.05  # felt: dull, short
    out = (out + thump) * (1 - np.exp(-t / 0.002))
    out[-int(0.05 * SR) :] *= np.linspace(1, 0, int(0.05 * SR))
    return out * 0.32 * vel**1.3


def tabor(vel=1.0):
    """A medieval tabor (a small snared frame drum): a short membrane knock plus a bright snare rattle."""
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    knock = np.sin(2 * np.pi * np.cumsum(190 * (1 + 0.3 * np.exp(-t / 0.01))) / SR) * np.exp(-t / 0.06)
    noise = rng.standard_normal(n)
    sp = np.fft.rfft(noise)
    f = np.fft.rfftfreq(n, 1 / SR)
    sp *= np.exp(-(((np.log(np.maximum(f, 1)) - np.log(3500)) / 0.6) ** 2))
    rattle = np.fft.irfft(sp, n) * np.exp(-t / 0.07)
    rattle /= np.abs(rattle).max() + 1e-12
    out = 0.6 * knock + 0.55 * rattle
    out *= 1 - np.exp(-t / 0.001)
    out[-int(0.02 * SR) :] *= np.linspace(1, 0, int(0.02 * SR))
    return out * 0.16 * vel**1.3


# ---------------------------------------------------------------- the score: stems on a timeline


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


def log_samples():
    if GAPS:
        print("  pitch-shifted (font lacked the key): " + ", ".join(f"{f}:{n}" for f, n in sorted(GAPS)), file=sys.stderr)
    else:
        print("  no sample gaps: every note was played from its own key", file=sys.stderr)
    if TUNED:
        print("  retuned samples (cents): " + ", ".join(f"{f.replace('mk_', '')}:{n} {c:+.0f}" for (f, n), c in sorted(TUNED.items())), file=sys.stderr)


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
