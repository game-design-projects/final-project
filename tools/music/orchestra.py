"""A real orchestra for sampler.py: the Versilian Studios Chamber Orchestra 2, Community Edition (VSCO-2 CE, CC0,
https://github.com/sgossner/VSCO-2-CE), recorded sections and soloists with several dynamics and round robins.

`use()` points sampler.py's `render_note` here, so a Score plays these instruments by name: a note picks the recorded
dynamic nearest its velocity (a soft note is a softly played sample, not a loud one turned down), alternates its round
robins, and is pitch-shifted from the nearest recorded key. Sustained notes keep the bow's or the breath's own attack and
release; struck and plucked ones ring as recorded. The kettle drums and the drums are recordings too (`hit`).

The library is not in the repository (it is 2 GB): `fetch.sh` beside this file puts the parts it plays in build/vsco2.
"""
from __future__ import annotations

import functools
import glob
import os
import re
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sampler as S  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
LIB = os.environ.get("VSCO2", os.path.join(ROOT, "build", "vsco2"))

DYN = {"ppp": 1, "pp": 2, "p": 3, "mp": 4, "mf": 5, "f": 6, "ff": 7, "fff": 8, "soft": 3, "quiet": 3, "med": 5, "medium": 5, "loud": 7}
NOTE = re.compile(r"(?:^|[_\-\s])([A-G])(#|b|s)?(-?\d)(?=[_\-\s.]|$)")

# name -> (folders under LIB, kind, release s, gain). kind: "sus" (held as long as written, faded at its end), "short"
# (plays as recorded, cut at its written length plus release), "ring" (plays out). Folders are tried in order and pooled.
SPEC = {
    "violins": (["Strings/Violin Section/susVib"], "sus", 0.35, 1.0),
    "violas": (["Strings/Viola Section/susvib"], "sus", 0.35, 1.0),
    "cellos": (["Strings/Cello Section/susvib"], "sus", 0.35, 1.0),
    "basses": (["Strings/Solo Contrabass/SusVib"], "sus", 0.35, 1.1),
    "violins_spic": (["Strings/Violin Section/Spic"], "short", 0.12, 1.0),
    "violas_spic": (["Strings/Viola Section/spic"], "short", 0.12, 1.0),
    "cellos_spic": (["Strings/Cello Section/spic"], "short", 0.12, 1.0),
    "basses_spic": (["Strings/Solo Contrabass/Spic"], "short", 0.12, 1.1),
    "violins_pizz": (["Strings/Violin Section/Pizz"], "ring", 0.2, 1.0),
    "violas_pizz": (["Strings/Viola Section/pizz"], "ring", 0.2, 1.0),
    "cellos_pizz": (["Strings/Cello Section/pizzT"], "ring", 0.2, 1.0),
    "basses_pizz": (["Strings/Solo Contrabass/Pizz"], "ring", 0.2, 1.1),
    "violins_trem": (["Strings/Violin Section/Trem"], "sus", 0.35, 0.9),
    "violas_trem": (["Strings/Viola Section/trem"], "sus", 0.35, 0.9),
    "cellos_trem": (["Strings/Cello Section/trem"], "sus", 0.35, 0.9),
    "solo_violin": (["Strings/Solo Violin/Arco Vib"], "sus", 0.3, 1.0),
    "solo_violin_spic": (["Strings/Solo Violin/spic"], "short", 0.12, 1.0),
    "harp": (["Strings/Harp"], "ring", 0.4, 1.0),
    "flute": (["Woodwinds/Flute/susvib"], "sus", 0.25, 1.0),
    "flute_stac": (["Woodwinds/Flute/stac"], "short", 0.15, 1.0),
    "oboe": (["Woodwinds/Oboe/Vib", "Woodwinds/Oboe/Sus"], "sus", 0.25, 1.0),
    "oboe_stac": (["Woodwinds/Oboe/Stacc"], "short", 0.15, 1.0),
    "clarinet": (["Woodwinds/Clarinet/susLong"], "sus", 0.25, 1.0),
    "clarinet_stac": (["Woodwinds/Clarinet/stac"], "short", 0.15, 1.0),
    "bassoon": (["Woodwinds/Bassoon/vib", "Woodwinds/Bassoon/sus"], "sus", 0.25, 1.0),
    "bassoon_stac": (["Woodwinds/Bassoon/stac"], "short", 0.15, 1.0),
    "piccolo": (["Woodwinds/Piccolo/Sus"], "sus", 0.2, 0.9),
    "horn": (["Brass/F Horn/sus"], "sus", 0.35, 1.0),
    "horn_stac": (["Brass/F Horn/stac"], "short", 0.2, 1.0),
    "trumpet": (["Brass/Trumpet/sus", "Brass/Trumpet/susvib"], "sus", 0.3, 1.0),
    "trumpet_stac": (["Brass/Trumpet/stac"], "short", 0.2, 1.0),
    "trombone": (["Brass/Tenor Trombone/sus", "Brass/Tenor Trombone/vib"], "sus", 0.35, 1.0),
    "trombone_stac": (["Brass/Tenor Trombone/stac"], "short", 0.2, 1.0),
    "tuba": (["Brass/Tuba/sus"], "sus", 0.35, 1.0),
    "organ": (["Keys/Organ/Quiet", "Keys/Organ/Loud"], "sus", 0.4, 0.8),
    "glock": (["Percussion/Glock"], "ring", 0.5, 0.8),
    "marimba": (["Percussion/Marimba"], "ring", 0.4, 1.0),
}

# A family of sections, by register: "strings" takes the section whose range a note sits best in.
SECTIONS = {
    "strings": [("basses", 0, 40), ("cellos", 40, 55), ("violas", 55, 64), ("violins", 64, 128)],
    "spic": [("basses_spic", 0, 40), ("cellos_spic", 40, 55), ("violas_spic", 55, 64), ("violins_spic", 64, 128)],
    "pizz": [("basses_pizz", 0, 40), ("cellos_pizz", 40, 55), ("violas_pizz", 55, 64), ("violins_pizz", 64, 128)],
    "trem": [("cellos_trem", 0, 55), ("violas_trem", 55, 64), ("violins_trem", 64, 128)],
}

HITS = {  # percussion: name -> glob under LIB
    "snare": "Percussion/Snare2-HitSN_*",
    "snare_soft": "Percussion/Snare2-taps_*",
    "snare_roll": "Percussion/Snare2-rollSN_*",
    "tamb": "Percussion/Tamb1-Hit_*",
    "tamb_shake": "Percussion/Tamb1-Shake_*",
    "triangle": "Percussion/Triangle3-Hit_*",
    "bassdrum": "Percussion/BDrumNewhit_*",
    "crash": "Percussion/cymbal-crash1_*",
    "cymbal_swell": "Percussion/susCymb1-cresc-*",
    "gong": "Percussion/gongHit_*",
    "timpani": "Percussion/Timpani/Timpani*_Hit_*",
}

MISSING: set = set()


def available() -> bool:
    return os.path.isdir(os.path.join(LIB, "Strings"))


def _note_of(path: str) -> int | None:
    base = os.path.splitext(os.path.basename(path))[0]
    found = NOTE.findall(base)
    if not found:
        return None
    letter, acc, octave = found[-1]
    m = S._PC[letter] + 12 * (int(octave) + 1)
    return m + (1 if acc in ("#", "s") else -1 if acc == "b" else 0)


def _dyn_of(path: str) -> float:
    base = os.path.splitext(os.path.basename(path))[0]
    v = re.search(r"_v(\d+)", base)
    if v:
        return float(v.group(1))
    for tok in re.split(r"[_\-\s]", base)[::-1]:
        if tok.lower() in DYN:
            return float(DYN[tok.lower()])
    if "Loud" in path:
        return 2.0
    return 1.0


@functools.lru_cache(maxsize=None)
def _wav(path: str) -> np.ndarray:
    sr, raw = wavfile.read(path)
    x = raw.astype(np.float64)
    if raw.dtype.kind in "iu":
        x /= float(np.iinfo(raw.dtype).max)
    if x.ndim == 2:
        x = x.mean(axis=1)
    if sr != S.SR:
        g = np.gcd(int(sr), S.SR)
        x = resample_poly(x, S.SR // g, int(sr) // g)
    on = int(np.argmax(np.abs(x) > 0.004 * (np.abs(x).max() + 1e-12)))
    return x[max(0, on - int(0.003 * S.SR)) :]


@functools.lru_cache(maxsize=None)
def _index(inst: str) -> dict:
    """{midi: {dyn: [paths]}} for an instrument, and its recorded dynamics in order."""
    folders, *_ = SPEC[inst]
    paths: list[str] = []
    for f in folders:
        full = os.path.join(LIB, f)
        if os.path.isdir(full):
            paths += sorted(glob.glob(os.path.join(full, "**", "*.wav"), recursive=True))
        else:
            paths += sorted(p for p in glob.glob(full) if p.lower().endswith(".wav"))
            for d in glob.glob(full):
                if os.path.isdir(d):
                    paths += sorted(glob.glob(os.path.join(d, "**", "*.wav"), recursive=True))
        if paths:
            break
    out: dict = {}
    named = [(p, _note_of(p)) for p in paths]
    if all(m is None for _, m in named):  # no note in the names (the organ): measure every sample
        keyed = [(p, int(round(_measure(p)))) for p in paths]
    else:  # the names count octaves their own way, instrument by instrument: measure some to know how
        with_names = [(p, m) for p, m in named if m is not None]
        off = _octave_offset(os.path.relpath(paths[0], LIB).split(os.sep)[:2])
        keyed = [(p, m + off) for p, m in with_names]
        if off:
            print(f"orchestra: {inst} names its notes {off:+d} semitones off; corrected", file=sys.stderr)
    for p, m in keyed:
        out.setdefault(m, {}).setdefault(_dyn_of(p), []).append(p)
    if not out:
        raise FileNotFoundError(f"orchestra: no samples for {inst} under {LIB} ({folders}); run tools/music/fetch.sh")
    return out


def _octave_offset(top: list) -> int:
    """How far an instrument's file names are from the notes it plays, in whole octaves: a vote of samples from every
    articulation it has (one measurement can be fooled by a strong overtone, a dozen are not)."""
    return KNOWN_OFFSET.get("/".join(top), None) if "/".join(top) in KNOWN_OFFSET else _octave_offset_of(os.path.join(LIB, *top))


# Instruments the vote gets wrong (the solo violin's pizzicato and tremolo fool it): their names are the notes they play.
KNOWN_OFFSET = {"Strings/Solo Violin": 0}


@functools.lru_cache(maxsize=None)
def _octave_offset_of(folder: str) -> int:
    votes: list = []
    for sub in sorted({os.path.dirname(p) for p in glob.glob(os.path.join(folder, "**", "*.wav"), recursive=True)}):
        files = [(p, _note_of(p)) for p in sorted(glob.glob(os.path.join(sub, "*.wav")))]
        files = [(p, m) for p, m in files if m is not None]
        for p, m in files[len(files) // 5 :: max(1, len(files) // 4)][:4]:
            votes.append(int(round((_measure(p) - m) / 12.0)) * 12)
    return max(set(votes), key=votes.count) if votes else 0


@functools.lru_cache(maxsize=None)
def _measure(path: str) -> float:
    """A sample's pitch (MIDI, fractional): the harmonic product spectrum of its steady part."""
    x = _wav(path)
    a, b = int(0.15 * S.SR), int(0.9 * S.SR)
    seg = x[a:b] if len(x) > b else x[: max(len(x), 2048)]
    n = 1 << 17
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n=n))
    f = np.fft.rfftfreq(n, 1 / S.SR)
    hps = spec.copy()
    for k in (2, 3):
        dec = spec[::k]
        hps[: len(dec)] *= dec
    band = (f > 27) & (f < 2200)
    f0 = f[band][np.argmax(hps[band])]
    return 69 + 12 * np.log2(f0 / 440.0)


_rr: dict = {}


def _pick(inst: str, m: int, vel: float) -> tuple[str, int]:
    idx = _index(inst)
    src = min(idx, key=lambda k: (abs(k - m), k < m))
    dyns = sorted(idx[src])
    want = vel * (len(dyns) - 1)  # velocity 0..1 across the recorded dynamics, soft to loud
    d = dyns[int(round(min(max(want, 0), len(dyns) - 1)))]
    files = idx[src][d]
    key = (inst, src, d)
    _rr[key] = _rr.get(key, -1) + 1
    return files[_rr[key] % len(files)], src


def _shift(x: np.ndarray, semis: int) -> np.ndarray:
    if semis == 0:
        return x
    ratio = 2 ** (semis / 12)
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


def resolve(inst: str, m: int) -> str:
    if inst in SECTIONS:
        for name, lo, hi in SECTIONS[inst]:
            if lo <= m < hi:
                return name
    return inst


def span(inst: str) -> tuple[int, int]:
    """The lowest and highest notes an instrument (or a family of sections) has recorded."""
    if inst in SECTIONS:
        return min(span(n)[0] for n, _, _ in SECTIONS[inst]), max(span(n)[1] for n, _, _ in SECTIONS[inst])
    keys = sorted(_index(inst))
    return keys[0], keys[-1]


def fit_octave(inst: str, notes: list) -> int:
    """The octave shift (0, then the nearest) that puts most of a line inside what the instrument plays."""
    if not notes or (inst not in SPEC and inst not in SECTIONS):
        return 0
    lo, hi = span(inst)
    return max((0, -12, 12, -24, 24), key=lambda k: sum(lo - 1 <= n + k <= hi + 1 for n in notes))


def render_note(inst: str, m: int, dur: float, vel: float = 1.0) -> np.ndarray:
    """One note: the recorded dynamic nearest `vel`, as long as written (a held note) or as recorded (a struck one).
    A note outside the instrument is folded into it by octaves (a line is fitted whole first, by `fit_octave`)."""
    if inst not in SPEC and inst not in SECTIONS:
        return _old_render(inst, m, dur, vel)
    lo, hi = span(inst)
    while m < lo - 2:
        m += 12
    while m > hi + 2:
        m -= 12
    inst = resolve(inst, m)
    _, kind, release, gain = SPEC[inst]
    path, src = _pick(inst, m, vel)
    x = _shift(_wav(path), m - src)
    ref = np.sqrt(np.mean(x[: int(0.5 * S.SR)] ** 2)) + 1e-9  # each sample's own level: the dynamics differ in timbre
    level = (0.18 if kind != "ring" else 0.2) / ref * (0.12 + 0.88 * vel**1.4)  # a soft part is soft: the band sits under the tune
    if kind == "sus":
        n = int((dur + release) * S.SR)
        if len(x) < n:  # a held note longer than the recording: loop its steady middle
            x = S.extend(x, n)
        x = x[:n].copy()
        r = int(release * S.SR)
        x[-r:] *= np.linspace(1, 0, r) ** 2
    elif kind == "short":
        n = min(len(x), int((dur + release) * S.SR))
        x = x[:n].copy()
        r = min(n, int(release * S.SR))
        x[-r:] *= np.linspace(1, 0, r) ** 2
    else:
        n = min(len(x), int(max(dur + 2.5, 1.0) * S.SR))
        x = x[:n].copy()
        k = min(n, int(0.08 * S.SR))
        x[-k:] *= np.linspace(1, 0, k)
    return x * level * gain


@functools.lru_cache(maxsize=None)
def _timpani_pitches() -> dict:
    """The kettle drums' recordings carry no note in their names: measure each one's pitch."""
    out: dict = {}
    for p in sorted(q for q in glob.glob(os.path.join(LIB, HITS["timpani"])) if q.lower().endswith(".wav")):
        x = _wav(p)[: int(1.0 * S.SR)]
        spec = np.abs(np.fft.rfft(x * np.hanning(len(x)), n=1 << 17))
        f = np.fft.rfftfreq(1 << 17, 1 / S.SR)
        band = (f > 60) & (f < 260)
        f0 = f[band][np.argmax(spec[band])]
        out[p] = 69 + 12 * np.log2(f0 / 440.0)
    return out


def hit(name: str, vel: float = 0.7, m: int | None = None) -> np.ndarray:
    """A drum, a cymbal or a kettle (`m`, its pitch: the nearest drum, tuned to it)."""
    if name == "timpani":
        pitches = _timpani_pitches()
        if not pitches:
            raise FileNotFoundError("orchestra: no timpani; run tools/music/fetch.sh")
        by_dyn: dict = {}
        for p, pm in pitches.items():
            by_dyn.setdefault(_dyn_of(p), []).append((p, pm))
        dyns = sorted(by_dyn)
        d = dyns[int(round(min(max(vel, 0), 1) * (len(dyns) - 1)))]
        p, pm = min(by_dyn[d], key=lambda c: abs(c[1] - (m or 43)))
        x = _wav(p)
        x = np.interp(np.arange(int(len(x) / 2 ** (((m or pm) - pm) / 12))) * 2 ** (((m or pm) - pm) / 12), np.arange(len(x)), x)
    else:
        files = sorted(p for p in glob.glob(os.path.join(LIB, HITS[name])) if p.lower().endswith(".wav"))
        if not files:
            raise FileNotFoundError(f"orchestra: no {name}; run tools/music/fetch.sh")
        by_dyn = {}
        for p in files:
            by_dyn.setdefault(_dyn_of(p), []).append(p)
        dyns = sorted(by_dyn)
        d = dyns[int(round(min(max(vel, 0), 1) * (len(dyns) - 1)))]
        key = ("hit", name, d)
        _rr[key] = _rr.get(key, -1) + 1
        x = _wav(by_dyn[d][_rr[key] % len(by_dyn[d])])
    x = x[: int(4.0 * S.SR)].copy()
    k = min(len(x), int(0.05 * S.SR))
    x[-k:] *= np.linspace(1, 0, k)
    ref = np.sqrt(np.mean(x[: int(0.3 * S.SR)] ** 2)) + 1e-9
    return x * 0.2 / ref * (0.12 + 0.88 * vel**1.4)


_old_render = S.render_note


def use() -> None:
    """Play sampler.py's scores on this orchestra: its notes by these names come from here, others as before."""
    S.render_note = render_note
