#!/usr/bin/env python3
"""Renders the dungeon's background music: a slow, dark ambient loop.

Everything is synthesised here (no samples): a warm low pad that drifts between minor chords a
third apart, a sub drone, a soft glassy bell melody with echo, a distant heartbeat thump and
cave air, all in a long dark reverb. The render is circular, so the loop point is seamless.

Needs numpy and scipy:  python3 scripts/build-ambient.py out.wav
Then encode:            afconvert -f m4af -d aac -b 160000 out.wav public/ambient.m4a
"""
import sys
import numpy as np
from scipy.io import wavfile

SR = 44100
CHORD = 12.0  # seconds per chord
BEAT = 1.5  # the slow pulse the bell and the echo sit on
FADE = 3.0  # crossfade between chords
TAIL = 1.0  # the file repeats its first second at the end, so players can loop inside it
rng = np.random.default_rng(7)

hz = lambda m: 440.0 * 2 ** ((m - 69) / 12)

# (pad notes as (midi, level), sub fundamental in Hz, bell notes as (beat, midi, level))
SONG = [
    ("Dm", [(38, 1.0), (45, 0.8), (50, 0.7), (53, 0.6), (57, 0.5), (64, 0.3)], hz(26), [(1, 69, 0.8), (2, 74, 0.8), (3, 76, 0.9), (4, 77, 1.0)]),
    ("Bbm", [(46, 1.0), (53, 0.8), (58, 0.65), (61, 0.6), (65, 0.45)], hz(34), [(1, 77, 0.8), (3, 73, 0.8), (4, 70, 0.7), (6, 65, 0.8)]),
    ("Dm", [(38, 1.0), (45, 0.8), (50, 0.7), (53, 0.6), (57, 0.5), (64, 0.3)], hz(26), [(1, 69, 0.8), (2, 74, 0.8), (3, 77, 1.0), (4.5, 76, 0.8), (6, 69, 0.7)]),
    ("F#m", [(42, 1.0), (49, 0.8), (54, 0.7), (57, 0.6), (61, 0.5), (68, 0.3)], hz(30), [(1, 73, 0.8), (3, 68, 0.8), (4, 69, 0.9), (6, 81, 0.45)]),
    ("Dm", [(38, 1.0), (45, 0.8), (50, 0.7), (53, 0.6), (57, 0.5), (64, 0.3)], hz(26), [(2, 81, 0.6), (4, 77, 0.7), (5, 74, 0.8), (6.5, 69, 0.8)]),
    ("F#m", [(42, 1.0), (49, 0.8), (54, 0.7), (57, 0.6), (61, 0.5), (68, 0.3)], hz(30), [(1, 73, 0.8), (2, 78, 0.9), (4, 76, 0.8), (6, 73, 0.8)]),
    ("Bbm", [(46, 1.0), (53, 0.8), (58, 0.65), (61, 0.6), (65, 0.45)], hz(34), [(1, 77, 0.9), (3, 73, 0.8), (4, 70, 0.7), (6, 73, 0.8)]),
    ("A7b9", [(45, 1.0), (52, 0.8), (57, 0.6), (61, 0.6), (64, 0.45), (67, 0.25), (70, 0.2)], hz(33), [(1, 76, 0.8), (2.5, 73, 0.8), (4, 70, 0.9), (5.5, 69, 0.9)]),
]
LOOP = CHORD * len(SONG)
N = int(LOOP * SR)


def place(buf, sig, start_s):
    """Add a (2, M) signal into the loop at start_s seconds, wrapping around the end."""
    i = int(round(start_s * SR)) % N
    idx = (i + np.arange(sig.shape[1])) % N
    buf[:, idx] += sig


def swell(n, fade_s):
    f = int(fade_s * SR)
    env = np.ones(n)
    ramp = np.sin(np.linspace(0, np.pi / 2, f)) ** 2
    env[:f] = ramp
    env[-f:] = ramp[::-1]
    return env


def pad_chord(notes, bright=1.0):
    """Additive 'analog' pad: detuned saw-like voices whose filter slowly opens and closes."""
    n = int((CHORD + FADE) * SR)
    t = np.arange(n) / SR
    arc = np.sin(np.pi * t / t[-1]) ** 2  # each chord opens up, then closes again
    fc = 240 + 900 * bright * arc
    out = np.zeros((2, n))
    for m, level in notes:
        for v in range(4):
            f = hz(m) * 2 ** (rng.uniform(-7, 7) / 1200)
            drift = rng.uniform(0.8, 1.8) * np.sin(2 * np.pi * rng.uniform(0.08, 0.25) * t + rng.uniform(0, 6.28))
            ph = 2 * np.pi * f * t + drift
            breathe = 1 - 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.07, 0.2) * t + rng.uniform(0, 6.28)))
            sig = np.zeros(n)
            for h in range(1, int(2600 / f) + 1):
                amp = (1 / h) / np.sqrt(1 + (h * f / fc) ** 4)
                sig += amp * np.sin(h * ph + rng.uniform(0, 6.28))
            sig *= level * breathe
            pan = 0.18 if v % 2 == 0 else 0.82
            out[0] += sig * np.cos(pan * np.pi / 2)
            out[1] += sig * np.sin(pan * np.pi / 2)
    return out * swell(n, FADE) * (0.6 + 0.4 * arc)


def sub_drone(f):
    n = int((CHORD + FADE) * SR)
    t = np.arange(n) / SR
    low = f if f > 45 else f * 2  # keep the weight where speakers can play it
    sig = 0.55 * np.sin(2 * np.pi * f * t) + 0.8 * np.sin(2 * np.pi * low * t + 1.0) + 0.16 * np.sin(2 * np.pi * low * 2 * t) + 0.06 * np.sin(2 * np.pi * low * 3 * t)
    sig *= 1 - 0.22 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 6))
    sig = np.tanh(1.2 * sig) * swell(n, FADE)
    return np.stack([sig, sig])


def bell(m, level):
    """A soft glass bell: nearly a sine, two slightly detuned copies left and right, with a low octave under it."""
    n = int(7 * SR)
    t = np.arange(n) / SR
    attack = 1 - np.exp(-t / 0.012)
    out = np.zeros((2, n))
    for ch, cents in enumerate((-4, 4)):
        f = hz(m) * 2 ** (cents / 1200)
        sig = np.sin(2 * np.pi * f * t) * np.exp(-t / 2.0)
        sig += 0.3 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 1.2)
        sig += 0.12 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t / 0.7)
        sig += 0.05 * np.sin(2 * np.pi * 4 * f * t) * np.exp(-t / 0.4)
        sig += 0.08 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / 0.3)
        sig += 0.3 * np.sin(2 * np.pi * 0.5 * f * t) * np.exp(-t / 2.6) * (1 - np.exp(-t / 0.08))
        out[ch] = sig * attack * level
    out[:, -2000:] *= np.linspace(1, 0, 2000)
    return out


def thump(level, pitch=1.0):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = pitch * (44 + 50 * np.exp(-t / 0.05))
    ph = 2 * np.pi * np.cumsum(f) / SR
    sig = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * np.exp(-t / 0.32)
    sig *= 1 - np.exp(-t / 0.004)
    sig[-2000:] *= np.linspace(1, 0, 2000)
    return np.stack([sig, sig]) * level


def spectrum_filter(x, gain_of_freq):
    """Filter a whole-loop signal in the frequency domain (circular, so it stays seamless)."""
    freqs = np.fft.rfftfreq(x.shape[-1], 1 / SR)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * gain_of_freq(freqs), x.shape[-1], axis=-1)


def cave_air():
    """Low, slow-moving filtered noise, like air moving through tunnels."""
    out = np.zeros((2, N))
    t = np.arange(N) / SR
    for ch in range(2):
        noise = rng.standard_normal(N)
        shape = lambda f: (f / 240) ** 2 / (1 + (f / 240) ** 2) / (1 + (f / 700) ** 4) / np.sqrt(np.maximum(f, 20) / 240)
        air = spectrum_filter(noise, shape)
        gust = 0.55 + 0.25 * np.sin(2 * np.pi * 5 * t / LOOP + ch) + 0.2 * np.sin(2 * np.pi * 13 * t / LOOP + 2 * ch)
        out[ch] = air * gust
    return out


def echo(x, delays=(BEAT * 0.75, BEAT), feedback=0.42):
    """Feedback echo with a dark tail, a different time on each side."""
    freqs = np.fft.rfftfreq(N, 1 / SR)
    w = 2 * np.pi * freqs
    out = np.zeros_like(x)
    for ch, d in enumerate(delays):
        loop = feedback * np.exp(-1j * w * d) / (1 + 1j * freqs / 1800)
        out[ch] = np.fft.irfft(np.fft.rfft(x[ch]) * (1 + 0.8 * loop / (1 - loop)), N)
    return out


def reverb_ir(seconds=9.0):
    """A long dark hall: noise that decays slower in the lows than in the highs."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    freqs = np.fft.rfftfreq(n, 1 / SR)
    edge = lambda f0: 1 / (1 + (freqs / f0) ** 6)
    bands = [(0, 400, 7.0, 0.8), (400, 1500, 6.5, 1.0), (1500, 4000, 4.5, 0.8), (4000, 9000, 2.2, 0.4)]
    ir = np.zeros((2, n))
    for ch in range(2):
        spec = np.fft.rfft(rng.standard_normal(n))
        for lo, hi, rt60, gain in bands:
            mask = edge(hi) * (1 - edge(lo) if lo else 1)
            ir[ch] += gain * np.fft.irfft(spec * mask, n) * np.exp(-6.91 * t / rt60)
    ir *= 1 - np.exp(-t / 0.03)
    ir = np.concatenate([np.zeros((2, int(0.025 * SR))), ir], axis=1)
    return ir / np.sqrt((ir**2).sum() / 2)


def reverb(x, ir):
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * np.fft.rfft(ir, N, axis=-1), N, axis=-1)


rms = lambda x: np.sqrt((x**2).mean())

pad, sub, bells, thumps = (np.zeros((2, N)) for _ in range(4))
for k, (name, notes, sub_f, melody) in enumerate(SONG):
    start = k * CHORD
    place(pad, pad_chord(notes, bright=1.15 if k >= 4 else 1.0), start - FADE / 2)
    place(sub, sub_drone(sub_f), start - FADE / 2)
    for beat, m, level in melody:
        place(bells, bell(m, level), start + beat * BEAT)
    for at, level in ((0, 1.0), (6, 0.6)):
        place(thumps, thump(level), start + at)
        place(thumps, thump(level * 0.55, 0.92), start + at + 0.36)
    print(f"  chord {k + 1}/{len(SONG)} {name}", file=sys.stderr)
air = cave_air()
bells = echo(bells)

# Balance the parts against each other, then send each into the hall by a different amount.
LEVEL = {"pad": 1.0, "sub": 0.5, "bells": 0.55, "thumps": 0.3, "air": 0.14}
SEND = {"pad": 0.4, "sub": 0.0, "bells": 0.9, "thumps": 0.3, "air": 0.35}
stems = {"pad": pad, "sub": sub, "bells": bells, "thumps": thumps, "air": air}
dry = np.zeros((2, N))
to_hall = np.zeros((2, N))
for name, x in stems.items():
    x = x * (LEVEL[name] / rms(x))
    dry += x
    to_hall += x * SEND[name]
mix = dry + 0.8 * reverb(to_hall, reverb_ir())

# Master: clear out rumble and fizz, round off peaks, leave headroom.
mix = spectrum_filter(mix, lambda f: (f / 28) ** 4 / (1 + (f / 28) ** 4) / np.sqrt(1 + (f / 9000) ** 4))
mix *= 10 ** (-20 / 20) / rms(mix)  # background level, with room above it
mix = np.tanh(mix / 0.8) * 0.8  # only the rare peak gets rounded
out = np.concatenate([mix, mix[:, : int(TAIL * SR)]], axis=1)
dither = (rng.random(out.shape) - rng.random(out.shape)) / 32768
path = sys.argv[1] if len(sys.argv) > 1 else "ambient.wav"
wavfile.write(path, SR, np.round((out + dither).T * 32767).clip(-32768, 32767).astype(np.int16))
print(f"wrote {path}: {LOOP:.0f}s loop + {TAIL:.0f}s tail", file=sys.stderr)
