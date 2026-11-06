"""Render dry through a chosen soundfont, add a convolution hall, level-match, join, encode.
usage: render10b.py <soundfont.sf2> <out.mp3>      (also: --ab for the Heroic Call comparison)"""
import glob
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

D = "."
SR = 44100
GU = os.environ.get("SF2", os.path.join(os.path.dirname(os.path.abspath(__file__)), "GeneralUser-GS.sf2"))
FL = os.environ.get("SF2_FLUID", "/usr/share/sounds/sf2/FluidR3_GM.sf2")
BANDS = [(20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 16000)]


def make_ir(secs=2.6, seed=7):
    rng = np.random.default_rng(seed)
    n = int(secs * SR)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2):
        x = np.zeros(n)
        for lo, hi, rt, g in [(60, 500, 2.8, .8), (500, 3000, 2.1, 1.0), (3000, 10000, 1.0, .7)]:
            b = sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), rng.standard_normal(n))
            x += g * b / np.sqrt((b ** 2).mean()) * 10 ** (-3 * t / rt)
        pre = int(.018 * SR)
        x = np.concatenate([np.zeros(pre), x[:-pre]])
        x[:int(.006 * SR)] *= np.linspace(0, 1, int(.006 * SR))
        chans.append(x)
    ir = np.stack(chans, 1)
    return ir / np.sqrt((ir ** 2).sum(axis=0))[None, :]


IR = make_ir()


def render_dry(mid, sf, gain=0.5):
    wav = mid[:-4] + ".wav"
    subprocess.run(["fluidsynth", "-ni", "-q", "-g", str(gain), "-r", str(SR), "-o", "synth.reverb.active=0",
                    "-o", "synth.chorus.active=0", "-F", wav, sf, mid], check=True)
    return wavfile.read(wav)[1].astype(np.float32) / 32768.0


def hall(dry, wet=.62):
    w = np.stack([fftconvolve(dry[:, c], IR[:, c]) for c in range(2)], 1).astype(np.float32)
    w *= wet * np.sqrt((dry ** 2).mean()) / np.sqrt((w ** 2).mean())
    out = np.zeros_like(w)
    out[:len(dry)] += dry
    return out + w


def trim(x):
    idx = np.where(np.abs(x).max(axis=1) > 10 ** (-55 / 20))[0]
    y = x[:min(len(x), idx[-1] + int(2.0 * SR))].copy()
    f = int(1.6 * SR)
    y[-f:] *= np.linspace(1, 0, f)[:, None]
    return y


def measure(x):
    mono = x.mean(axis=1)
    e = [float((sosfilt(butter(4, [lo, min(hi, SR / 2 - 1)], btype="band", fs=SR, output="sos"), mono) ** 2).sum())
         for lo, hi in BANDS]
    return [round(100 * v / sum(e), 1) for v in e]


def air(x):
    """high shelf (~+5 dB above 3.5 kHz): the dry samples are dull compared with real recordings"""
    return x + .9 * sosfilt(butter(2, 3500, 'highpass', fs=SR, output='sos'), x, axis=0).astype(np.float32)


def chain(mid, sf):
    x = hall(render_dry(mid, sf))
    if np.abs(x).max() >= .999:
        x = hall(render_dry(mid, sf, .32))
    x = trim(air(x))
    y = x * (10 ** (-18 / 20) / np.sqrt((x.mean(axis=1) ** 2).mean()))
    if np.abs(y).max() > .89:
        y *= .89 / np.abs(y).max()
    return y


def join(items, out):
    gap = np.zeros((int(1.2 * SR), 2), np.float32)
    parts, t, rows = [], 0.0, []
    for name, y in items:
        print(f"{name:22s} {len(y) / SR:5.1f}s bands% {measure(y)}")
        rows.append((name, t))
        parts += [y, gap]
        t += len(y) / SR + 1.2
    wavfile.write(out[:-4] + ".wav", SR, (np.clip(np.concatenate(parts[:-1]), -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", out[:-4] + ".wav", "-c:a", "libmp3lame", "-b:a", "256k", out], check=True)
    os.remove(out[:-4] + ".wav")
    for nme, s in rows:
        print(f"{int(s // 60)}:{int(s % 60):02d}  {nme}")


if __name__ == "__main__":
    if sys.argv[1] == "--ab":
        old = chain("03_heroic_call.mid", GU)
        new_gu = chain(f"{D}/03_heroic_call.mid", GU)
        new_fl = chain(f"{D}/03_heroic_call.mid", FL)
        join([("A old sound", old), ("B new orchestration, GeneralUser", new_gu), ("C new orchestration, FluidR3", new_fl)],
             f"{D}/ab_heroic_call.mp3")
    else:
        sf, out = sys.argv[1], sys.argv[2]
        items = [(os.path.basename(p)[3:-4].replace("_", " ").title(), chain(p, sf))
                 for p in sorted(glob.glob(f"{D}/[0-9][0-9]_*.mid"))]
        join(items, out)
