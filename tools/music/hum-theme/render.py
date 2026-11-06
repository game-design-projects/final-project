"""Render the two finished loops from source: MIDI -> FluidSynth (GeneralUser GS) -> hall reverb -> one exact
loop (the reverb tail folded into the start, so it wraps without a gap) -> Ogg Vorbis + a 2x MP3 preview.

usage (from this folder):  python3 render.py [voice|combat|all]
needs: fluidsynth, ffmpeg with libvorbis/libmp3lame, numpy, scipy, mido, and GeneralUser-GS.sf2 next to this file
       (or set SF2=/path/to/GeneralUser-GS.sf2)
"""
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from render10b import render_dry, hall, air, measure, GU, SR

TRACKS = {  # name: (module, bars, bpm, wet, rms target dBFS)
    "voice": ("dungeon_voice", 64, 88, .62, -18),
    "combat": ("combat", 48, 176, .42, -16),
}


def build(name):
    mod, bars, bpm, wet, target = TRACKS[name]
    m = __import__(mod)
    mid = os.path.join(HERE, f"donjon_{name}.mid")
    (m.piece() if hasattr(m, "piece") else m.song()).write(mid)
    x = air(hall(render_dry(mid, GU), wet=wet))
    n = int(round(bars * 4 * 60 / bpm * SR))
    loop = x[:n].copy()
    loop[:len(x) - n] += x[n:][:n]
    loop *= 10 ** (target / 20) / np.sqrt((loop.mean(axis=1) ** 2).mean())
    if np.abs(loop).max() > .89:
        loop *= .89 / np.abs(loop).max()
    print(f"{name}: {n / SR:.2f} s loop, bands % {measure(loop)}")
    for out, y in ((f"donjon_{name}", loop), (f"donjon_{name}_x2", np.concatenate([loop, loop]))):
        wav = os.path.join(HERE, out + ".wav")
        wavfile.write(wav, SR, (np.clip(y, -1, 1) * 32767).astype(np.int16))
        enc = (["-c:a", "libvorbis", "-q:a", "6", out + ".ogg"] if out == f"donjon_{name}"
               else ["-c:a", "libmp3lame", "-b:a", "256k", out + ".mp3"])
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav] + enc[:-1] + [os.path.join(HERE, enc[-1])], check=True)
        os.remove(wav)


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    for name in (TRACKS if which == "all" else [which]):
        build(name)
