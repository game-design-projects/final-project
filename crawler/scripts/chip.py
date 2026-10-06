"""Chiptune voices shared by the music build scripts (build-battle.py, build-stings.py).

Band-limited pulse and triangle oscillators, a sine-sweep kick, and band-passed noise hits, all
synthesised with numpy/scipy (no samples).
"""
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(11)

hz = lambda m: 440.0 * 2 ** ((m - 69) / 12)


def env(n, attack=0.004, release=0.03, decay=0.0, sustain=1.0):
    t = np.arange(n) / SR
    e = np.minimum(1, t / attack)
    if decay:
        e *= sustain + (1 - sustain) * np.exp(-t / decay)
    r = int(release * SR)
    if r and n > r:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def saw_phase(phase, f, nmax):
    """Band-limited sawtooth from a phase array (cycles), harmonics kept under Nyquist."""
    out = np.zeros_like(phase)
    for k in range(1, nmax + 1):
        if k * f > 16000:
            break
        out += np.sin(2 * np.pi * k * phase) / k
    return out * (2 / np.pi)


def pulse(f, dur, duty=0.5, vibrato=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    wob = 1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.18)
    phase = np.cumsum(f * wob) / SR
    return saw_phase(phase, f, 60) - saw_phase(phase - duty, f, 60)


def triangle(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, k in enumerate(range(1, 40, 2)):
        if k * f > 16000:
            break
        out += (-1) ** i * np.sin(2 * np.pi * k * f * t) / k**2
    return out * (8 / np.pi**2)


def kick():
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f = 50 + 110 * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)


def noise_hit(dur, decay, lo, hi):
    n = int(dur * SR)
    t = np.arange(n) / SR
    sos = butter(2, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, rng.standard_normal(n)) * np.exp(-t / decay) * np.minimum(1, t / 0.0015)


def snare():
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04) * 0.5
    return noise_hit(0.2, 0.06, 1200, 9000) * 1.6 + tone
