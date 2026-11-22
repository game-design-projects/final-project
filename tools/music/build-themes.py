#!/usr/bin/env python3
"""Every place and every foe its own music, played on the VSCO-2 CE orchestra (orchestra.py) and mixed by sampler.py.

Each tune belongs to a family, and a family is one melody idea: a two-bar head motif, a mode, a metre, a way of
accompanying, a band. Tunes of one family share the head (so a clan's fights sound like that clan) and differ in key,
tempo, lead instruments, ostinato, harmony and everything after the head (the rest of each phrase is written per tune
from its own seed), so no two are the same. Families differ in all of it.

  explore-<biome>[-deep]  the three biomes; the second time a biome comes round (deeper) it plays its -deep variant
  hall-<clan>             a clan's hall: the clan's family, at rest
  fight-<kind>            every kind of monster (data/kinds.json), its clan's family:
                            burrow (slime)     6/8, Lydian, music box and harpsichord, oom-pah
                            crew (bandit)      4/4 gallop, harmonic minor, harpsichord and marcato strings
                            old_stone (rock)   4/4 stomp, Dorian, organ and choir over kettle drums
                            coil (snake)       7/8 (2+2+3), Hungarian minor, strings and bells
  champion-<name>         the champions (data/floors.json), the Hoard's family: Phrygian dominant, choir and organ;
                          the last one, Vexalith, has the whole theme as it was first written
  trade, practice, test-room   the trader, the practice floor, the test room: one family each
  sting-victory, sting-fanfare  a foe spared, the stairs

The camp keeps the one old theme the game still plays, Abdulla's hum theme (assets/audio/hum-explore.ogg).

usage (from the repository root; needs numpy and scipy, and ffmpeg with libvorbis):
  uv run --no-project --with numpy --with scipy python -I tools/music/build-themes.py [--only name,name] [--jobs N] [--wav-dir /tmp/x]
It renders each tune to a WAV in --wav-dir and encodes it into assets/audio/music/<name>.ogg (tools/music/to_ogg.sh).
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import time
import zlib
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field, replace

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import sampler as S  # noqa: E402
import orchestra as O  # noqa: E402

O.use()  # the notes are played by the recorded orchestra (VSCO-2 CE), not the old soundfont

log = logging.getLogger("themes")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "music")
OGG_QUALITY = "4"

SCALES = {
    "ionian": (0, 2, 4, 5, 7, 9, 11),
    "lydian": (0, 2, 4, 6, 7, 9, 11),
    "mixolydian": (0, 2, 4, 5, 7, 9, 10),
    "dorian": (0, 2, 3, 5, 7, 9, 10),
    "aeolian": (0, 2, 3, 5, 7, 8, 10),
    "harmonic": (0, 2, 3, 5, 7, 8, 11),
    "hungarian": (0, 2, 3, 6, 7, 8, 11),
    "phrygian_dom": (0, 1, 4, 5, 7, 8, 10),
}

Notes = tuple  # ((degree or None for a rest, length in units), ...)


@dataclass(frozen=True)
class Family:
    """One melody idea. Degrees count up the mode from the tune's tonic (0), 7 is the octave; a unit is the metre's
    smallest beat (an eighth)."""

    name: str
    scale: str
    meter: int  # units in a bar
    strong: tuple  # units of a bar where the tune lands on a note of the chord
    bpm: float  # units per minute
    tonic: int  # MIDI of the lead's tonic at key shift 0
    head: Notes  # two bars: what every tune of the family opens its phrases with
    head_chords: tuple  # the chords (degrees) under the head
    cells: tuple  # bar rhythms for the middle of a phrase
    ends: tuple  # bar rhythms for a phrase's last bar
    opens: tuple  # two-chord endings of a phrase that stays open (not on the tonic)
    closes: tuple  # two-chord endings of a phrase that comes home
    bridges: tuple  # four-chord progressions for the B phrase
    style: str  # how it is accompanied (see Accompany)
    leads: tuple  # its lead instruments, in turn
    kind: str = "battle"  # "battle" or "explore": its loudness and how wet the hall is


@dataclass(frozen=True)
class Tune:
    name: str
    family: Family
    shift: int = 0  # semitones from the family's tonic
    tempo: float = 1.0
    lead: int = 0  # which of the family's leads opens
    osti: int = 0  # which accompaniment pattern
    calm: bool = False  # the family at rest (a clan's hall): slower, no drums
    deep: bool = False  # darker: lower, slower, the second lead first
    seed: int = 0
    min_seconds: float = 36.0


# ---------------------------------------------------------------- the families

BURROW = Family(
    "burrow", "lydian", 6, (0, 3), 324, 67,
    head=((4, 1), (2, 1), (4, 1), (7, 3), (6, 2), (4, 1), (3, 2), (4, 1)), head_chords=(0, 4),
    cells=((2, 1, 2, 1), (1, 1, 1, 3), (3, 2, 1), (2, 1, 3), (1, 2, 1, 2)), ends=((3, 3), (2, 1, 3), (6,)),
    opens=((1, 4), (5, 4), (2, 1)), closes=((4, 0), (1, 0), (5, 0)), bridges=((5, 1, 4, 4), (1, 5, 1, 4), (5, 2, 1, 4), (2, 5, 1, 1)),
    style="oompah", leads=("flute", "clarinet", "glock", "oboe"))

CREW = Family(
    "crew", "harmonic", 8, (0, 4), 320, 69,
    head=((0, 1), (0, 1), (4, 3), (3, 1), (2, 1), (1, 1), (2, 2), (-1, 1), (0, 1), (4, 4)), head_chords=(0, 0),
    cells=((1, 1, 2, 1, 1, 2), (3, 1, 2, 2), (2, 1, 1, 2, 2), (1, 1, 1, 1, 2, 2), (3, 3, 2)), ends=((2, 6), (3, 5), (1, 1, 6)),
    opens=((3, 4), (5, 4)), closes=((4, 0), (3, 0)), bridges=((5, 3, 0, 4), (3, 0, 5, 4), (5, 5, 3, 4), (3, 3, 5, 4)),
    style="gallop", leads=("solo_violin", "oboe", "trumpet", "clarinet"))

OLD_STONE = Family(
    "old_stone", "dorian", 8, (0, 4), 192, 62,
    head=((0, 4), (2, 2), (3, 2), (4, 6), (3, 1), (2, 1)), head_chords=(0, 4),
    cells=((4, 2, 2), (2, 2, 4), (3, 1, 2, 2), (6, 2), (2, 2, 2, 2)), ends=((8,), (4, 4), (6, 2)),
    opens=((3, 4), (6, 4), (2, 3)), closes=((3, 0), (6, 0), (4, 0)), bridges=((3, 6, 3, 4), (2, 3, 6, 4), (6, 3, 2, 4), (2, 6, 3, 3)),
    style="stomp", leads=("horn", "cellos", "trombone", "organ"))

COIL = Family(
    "coil", "hungarian", 7, (0, 4), 300, 67,
    head=((4, 2), (3, 1), (2, 1), (3, 3), (4, 1), (5, 1), (4, 1), (3, 1), (2, 1), (1, 1), (0, 1)), head_chords=(0, 0),
    cells=((2, 2, 3), (1, 1, 2, 3), (2, 1, 1, 3), (2, 2, 1, 1, 1), (4, 3)), ends=((4, 3), (2, 5), (7,)),
    opens=((5, 4), (6, 4)), closes=((4, 0), (5, 0)), bridges=((5, 6, 5, 4), (6, 5, 4, 4), (5, 5, 6, 4), (6, 6, 5, 4)),
    style="asym", leads=("oboe", "flute", "solo_violin", "clarinet"))

HOARD = Family(
    "hoard", "phrygian_dom", 8, (0, 4), 276, 67,
    head=((0, 3), (4, 3), (3, 2), (5, 2), (4, 1), (3, 1), (2, 4)), head_chords=(0, 3),
    cells=((3, 3, 2), (2, 1, 1, 4), (2, 2, 2, 2), (3, 1, 2, 2), (4, 2, 2)), ends=((4, 4), (8,), (3, 5)),
    opens=((3, 1), (6, 1)), closes=((1, 0), (6, 0), (3, 0)), bridges=((1, 1, 0, 0), (6, 1, 3, 1), (3, 6, 1, 1), (1, 6, 3, 0)),
    style="dragon", leads=("trumpet", "horn", "violins", "oboe"))

HALLS = Family(
    "halls", "mixolydian", 6, (0,), 184, 62,
    head=((0, 2), (4, 2), (3, 1), (2, 1), (1, 2), (2, 1), (3, 1), (4, 2)), head_chords=(0, 6),
    cells=((2, 2, 2), (2, 1, 1, 2), (3, 1, 2), (4, 2), (1, 1, 2, 2)), ends=((6,), (4, 2), (2, 4)),
    opens=((3, 4), (6, 4), (1, 4)), closes=((6, 0), (3, 0)), bridges=((3, 6, 1, 4), (4, 3, 6, 6), (1, 3, 6, 4), (6, 3, 4, 4)),
    style="minuet", leads=("violins", "flute", "oboe", "clarinet"), kind="explore")

UNDERCROFT = Family(
    "undercroft", "aeolian", 8, (0, 4), 140, 64,
    head=((0, 3), (1, 1), (2, 2), (4, 2), (3, 4), (2, 2), (1, 2)), head_chords=(0, 3),
    cells=((4, 2, 2), (3, 1, 4), (2, 2, 4), (6, 2), (2, 2, 2, 2)), ends=((8,), (4, 4), (6, 2)),
    opens=((5, 4), (3, 4), (5, 6)), closes=((6, 0), (3, 0), (4, 0)), bridges=((5, 2, 6, 4), (2, 6, 3, 4), (5, 6, 2, 4), (3, 5, 6, 4)),
    style="chorale", leads=("organ", "horn", "cellos", "flute"), kind="explore")

CAVES = Family(
    "caves", "dorian", 6, (0, 3), 168, 64,
    head=((0, 3), (4, 2), (3, 1), (4, 2), (5, 1), (6, 3)), head_chords=(0, 6),
    cells=((3, 2, 1), (2, 1, 2, 1), (3, 3), (2, 1, 3), (1, 1, 1, 3)), ends=((6,), (3, 3), (2, 1, 3)),
    opens=((3, 4), (2, 6), (3, 6)), closes=((6, 0), (3, 0)), bridges=((2, 6, 3, 4), (3, 2, 6, 4), (6, 3, 2, 4)),
    style="rocking", leads=("flute", "clarinet", "glock", "violins"), kind="explore")

TRADE = Family(
    "trade", "ionian", 8, (0, 4), 224, 65,
    head=((2, 1), (3, 1), (4, 2), (4, 2), (5, 1), (4, 1), (3, 2), (1, 2), (2, 4)), head_chords=(0, 4),
    cells=((1, 1, 2, 2, 2), (2, 2, 1, 1, 2), (3, 1, 2, 2), (2, 2, 4), (1, 1, 1, 1, 4)), ends=((4, 4), (2, 6), (8,)),
    opens=((3, 4), (1, 4)), closes=((4, 0), (3, 0)), bridges=((5, 1, 4, 4), (3, 0, 1, 4), (5, 3, 1, 4)),
    style="gavotte", leads=("oboe", "clarinet", "flute"), kind="explore")

PRACTICE = Family(
    "practice", "ionian", 8, (0, 4), 152, 60,
    head=((0, 2), (2, 2), (4, 4), (5, 2), (4, 2), (2, 4)), head_chords=(0, 5),
    cells=((2, 2, 4), (4, 4), (2, 2, 2, 2), (3, 1, 4)), ends=((8,), (4, 4)),
    opens=((3, 4), (1, 4)), closes=((4, 0), (3, 0)), bridges=((3, 0, 1, 4), (5, 3, 1, 4)),
    style="gentle", leads=("flute", "harp", "clarinet"), kind="explore")

TEST_ROOM = Family(
    "test_room", "ionian", 8, (0, 4), 240, 67,
    head=((0, 1), (4, 1), (2, 1), (4, 1), (0, 1), (4, 1), (3, 1), (4, 1), (5, 2), (4, 2), (3, 2), (2, 2)), head_chords=(0, 1),
    cells=((1, 1, 1, 1, 2, 2), (2, 2, 2, 2), (1, 1, 2, 1, 1, 2), (2, 1, 1, 4)), ends=((4, 4), (2, 2, 4), (8,)),
    opens=((3, 4), (5, 4)), closes=((4, 0), (3, 0)), bridges=((5, 1, 4, 4), (3, 5, 1, 4)),
    style="toccata", leads=("marimba", "clarinet", "flute"), kind="explore")

CLANS = {"slime": BURROW, "bandit": CREW, "rock": OLD_STONE, "snake": COIL}
CLAN_OF = {"slime": "burrow", "bandit": "crew", "rock": "old_stone", "snake": "coil"}
# A kind's place in its clan (data/kinds.json lists them shallow to deep) moves its key and its tempo: the deeper,
# the faster, round a circle of keys so neighbours never share one.
KEY_STEPS = (0, 3, -2, 5, -4, 2, -5, 4)
TEMPO_STEPS = (1.0, 1.04, 0.95, 1.08, 0.92, 1.06, 0.97, 1.1)


def tunes() -> dict[str, Tune]:
    """Every tune the game plays, by name, from the game's own data."""
    with open(os.path.join(ROOT, "data", "kinds.json")) as f:
        kinds = json.load(f)["kinds"]
    with open(os.path.join(ROOT, "data", "floors.json")) as f:
        champions = [c["name"] for c in json.load(f)["champions"]]
    out: dict[str, Tune] = {}

    def add(t: Tune) -> None:
        out[t.name] = replace(t, seed=zlib.crc32(t.name.encode()))

    add(Tune("explore-halls", HALLS, min_seconds=45))
    add(Tune("explore-halls-deep", HALLS, shift=-3, tempo=0.9, lead=1, osti=1, deep=True, min_seconds=45))
    add(Tune("explore-undercroft", UNDERCROFT, min_seconds=45))
    add(Tune("explore-undercroft-deep", UNDERCROFT, shift=-2, tempo=0.92, lead=1, osti=1, deep=True, min_seconds=45))
    add(Tune("explore-caves", CAVES, min_seconds=45))  # its whole tune is written out: see caves_first
    add(Tune("explore-caves-deep", CAVES, shift=-3, tempo=0.93, lead=1, osti=1, deep=True, min_seconds=45))
    add(Tune("trade", TRADE, min_seconds=40))
    add(Tune("practice", PRACTICE, min_seconds=40))
    add(Tune("test-room", TEST_ROOM, min_seconds=40))
    for species, fam in CLANS.items():
        add(Tune("hall-" + CLAN_OF[species], fam, shift=-2, tempo=0.62, lead=len(fam.leads) - 1, osti=2, calm=True, min_seconds=45))
    seen: dict[str, int] = {}
    for kind, spec in kinds.items():
        species = spec["species"]
        i = seen.get(species, 0)
        seen[species] = i + 1
        fam = CLANS[species]
        add(Tune("fight-" + kind, fam, shift=KEY_STEPS[i % len(KEY_STEPS)], tempo=TEMPO_STEPS[i % len(TEMPO_STEPS)],
                 lead=i % len(fam.leads), osti=i % 3))
    for i, name in enumerate(champions):
        last = i == len(champions) - 1
        add(Tune("champion-" + name.lower(), HOARD, shift=(0 if last else KEY_STEPS[(i + 1) % len(KEY_STEPS)]),
                 tempo=(1.0 if last else TEMPO_STEPS[(i + 2) % len(TEMPO_STEPS)]), lead=i % len(HOARD.leads), osti=i % 3))
    add(Tune("sting-victory", TRADE))
    add(Tune("sting-fanfare", HALLS))
    return out


# ---------------------------------------------------------------- the tune: phrases on a family's head


def deg_midi(fam: Family, tonic: int, d: int) -> int:
    sc = SCALES[fam.scale]
    return tonic + 12 * (d // 7) + sc[d % 7]


def chord_pcs(fam: Family, tonic: int, d: int) -> list[int]:
    return [deg_midi(fam, tonic, d + k) % 12 for k in (0, 2, 4)]


def write_bar(rng: np.random.Generator, fam: Family, chord: int, prev: int, height: float, rhythm: tuple, end: str | None, last_chord: int) -> tuple[list, int]:
    """One bar of melody over `chord`: notes of the chord on the strong units, steps between, drawn toward `height`.
    The last note of a phrase (`end`) comes home to the tonic ("close") or rests on a note of the chord ("open")."""
    tones = {(chord + k) % 7 for k in (0, 2, 4)}
    notes, pos, last_leap = [], 0, 0
    for k, dur in enumerate(rhythm):
        final = end is not None and k == len(rhythm) - 1
        if final:
            home = {(last_chord + j) % 7 for j in (0, 2, 4)} if end == "open" else {0}
            pool = [c for c in range(-3, 11) if c % 7 in home]
            pick = min(pool, key=lambda c: abs(c - prev) + 0.3 * abs(c - height) + (0.5 if end == "open" and c % 7 != last_chord % 7 else 0) + (2.0 if c == prev else 0))
        else:
            def cost(c: int) -> float:
                step = c - prev
                v = abs(step) * 0.9 + abs(c - height) * 0.55 + rng.uniform(0, 1.3)
                if pos in fam.strong and c % 7 not in tones:
                    v += 3.0
                if abs(step) > 4:
                    v += 4.0
                if step == 0:
                    v += 3.0 if last_leap else 6.0  # a note may sound twice, never three times
                if abs(step) == 1 or abs(step) == 2:
                    v -= 0.4  # steps and thirds sing
                if last_leap and abs(last_leap) >= 3 and np.sign(step) == np.sign(last_leap):
                    v += 2.5  # after a leap, turn back
                return v

            pick = min(range(-3, 11), key=cost)
        notes.append((pick, dur))
        last_leap = pick - prev
        prev = pick
        pos += dur
    return notes, prev


def phrase(rng: np.random.Generator, fam: Family, chords: tuple, end: str, heights: tuple, with_head: bool, first_rhythm: tuple | None = None) -> list:
    notes: list = []
    prev = 2
    start = 0
    if with_head:
        notes = list(fam.head)
        prev = [d for d, _ in fam.head if d is not None][-1]
        start = 2
    for b in range(start, 4):
        last = b == 3
        if last:
            rhythm = fam.ends[int(rng.integers(len(fam.ends)))]
        elif b == 0 and first_rhythm is not None:
            rhythm = first_rhythm
        else:
            rhythm = fam.cells[int(rng.integers(len(fam.cells)))]
        bar, prev = write_bar(rng, fam, chords[b], prev, heights[b], rhythm, end if last else None, chords[3])
        notes += bar
    return notes


@dataclass
class Plan:
    """A tune laid out: its sections, the chord of every bar, and the melody of every phrase."""

    sections: list = field(default_factory=list)  # [(label, first bar, bars)]
    chords: list = field(default_factory=list)  # a degree per bar
    phrases: dict = field(default_factory=dict)  # label -> notes


def plan(t: Tune, bars_wanted: int) -> Plan:
    fam = t.family
    rng = np.random.default_rng(t.seed)
    pick = lambda pool: pool[int(rng.integers(len(pool)))]  # noqa: E731
    p1c = fam.head_chords + pick(fam.opens)
    p2c = fam.head_chords + pick(fam.closes)
    p3c = pick(fam.bridges)
    p4c = fam.head_chords + pick(fam.closes)
    first_rhythm = tuple(d for _, d in fam.head[: next(i for i in range(len(fam.head)) if sum(d for _, d in fam.head[: i + 1]) >= fam.meter) + 1])
    lift = 1.0 if t.deep else 0.0
    p = Plan()
    p.phrases = {
        "p1": phrase(rng, fam, p1c, "open", (3, 4, 5 - lift, 4), True),
        "p2": phrase(rng, fam, p2c, "close", (3, 4, 3 - lift, 1), True),
        "p3": phrase(rng, fam, p3c, "open", (5, 6, 7 - lift, 5), False, first_rhythm),
        "p4": phrase(rng, fam, p4c, "close", (4, 5, 2, 0), True),
    }
    order = ["A", "B", "C", "A2"] if fam.kind == "battle" and not t.calm else ["A", "B", "A2", "B2"]
    n = 2
    while n < len(order) and n * 8 < bars_wanted:
        n += 1
    bar = 0
    for label in order[:n]:
        p.sections.append((label, bar, 8))
        if label in ("A", "A2"):
            p.chords += list(p1c + p2c)
        elif label in ("B", "B2"):
            p.chords += list(p3c + p4c)
        else:  # C: the break, the head's chords under the head's first bar twice, then the way home
            p.chords += [fam.head_chords[0], p3c[1], fam.head_chords[0], p3c[3]] + list(p4c)
        bar += 8
    return p


# ---------------------------------------------------------------- playing it

# Held instruments join their notes (a hair of overlap, as a bow or a breath does); struck and plucked ones are let go.
LEGATO = {k: 1.03 for k in ("strings", "violins", "violas", "cellos", "organ", "horn", "flute", "oboe", "clarinet", "trumpet", "solo_violin", "trombone", "bassoon")}


@dataclass
class Ctx:
    t: Tune
    sc: S.Score
    unit: float
    bar_s: float
    tonic: int  # the lead's tonic, MIDI
    rng: np.random.Generator

    @property
    def fam(self) -> Family:
        return self.t.family

    def lead(self, k: int) -> str:
        inst = self.fam.leads[(self.t.lead + k) % len(self.fam.leads)]
        return inst

    def bass(self, d: int) -> int:
        pc = deg_midi(self.fam, self.tonic, d) % 12
        return 36 + (pc - 36) % 12

    def triad(self, d: int, lo: int, prev: list | None) -> list[int]:
        return S.voice(chord_pcs(self.fam, self.tonic, d), prev, lo, lo + 14, 3)


def play(c: Ctx, stem: str, inst: str, notes: list, bar0: int, vel: float, pan: float = 0.0, octave: int = 0, late: float = 0.0, swell: bool = True) -> None:
    """A line on one instrument, fitted whole into its range, each phrase swelling to its middle and easing at its end
    (a player breathes with the line; the recorded dynamics change colour as it does)."""
    t = bar0 * c.bar_s + late
    pos = 0
    pitched = [deg_midi(c.fam, c.tonic, d) + octave for d, _ in notes if d is not None]
    shift = octave + O.fit_octave(inst, pitched)
    phrase_len = 4 * c.fam.meter
    for d, dur in notes:
        if d is not None:
            accent = 0.08 if pos % c.fam.meter in c.fam.strong else 0.0
            x = (pos % phrase_len) / phrase_len
            arc = (0.82 + 0.3 * np.sin(np.pi * min(1.0, x * 1.15))) if swell else 1.0
            c.sc.note(stem, inst, deg_midi(c.fam, c.tonic, d) + shift, t, dur * c.unit * LEGATO.get(inst, 0.95), min(1.0, (vel + accent) * arc), pan)
        t += dur * c.unit
        pos += dur


# The family's small drum, or none: the slimes and the snakes have only their kettles (no shaker, no tambourine).
DRUM = {"burrow": None, "crew": "snare", "old_stone": "snare", "coil": None, "hoard": "snare", "trade": "triangle", "test_room": "snare_soft"}


def drum(c: "Ctx", vel: float) -> np.ndarray:
    """The family's small drum: a snare for most, a triangle at the trader, and silence for the slimes and the snakes."""
    name = DRUM.get(c.fam.name, "snare_soft")
    return O.hit(name, vel) if name else np.zeros(1)


def timp(m: int, vel: float) -> np.ndarray:
    return O.hit("timpani", vel, m)


def kettle(r: int) -> int:
    """A kettle drum on the chord's root, kept between E2 and D#3: lower is only boom."""
    return r + 12 if r < 40 else (r - 12 if r > 51 else r)


def fifth_under(m: int) -> int:
    return m - 5 if m - 5 >= 38 else m + 7


def accompany(c: Ctx, p: Plan) -> None:
    """The family's way of going under its tune, bar by bar."""
    fight = c.fam.kind == "battle" and not c.t.calm
    voiced: list | None = None
    pad_v: list | None = None
    u = c.unit
    for i, d in enumerate(p.chords):
        t = i * c.bar_s
        label, first, _ = next(s for s in p.sections if s[1] <= i < s[1] + s[2])
        k = i - first
        r = c.bass(d)
        tri = c.triad(d, 55, voiced)
        voiced = tri
        third = chord_pcs(c.fam, c.tonic, d)
        q1 = (third[1] - third[0]) % 12
        q2 = (third[2] - third[0]) % 12
        brk = label == "C" and k < 4
        style = "calm" if c.t.calm else c.fam.style
        if style == "calm":
            pad_v = c.triad(d, 52 if c.fam.name == "old_stone" else 57, pad_v)
            pad_inst = "organ" if c.fam.name in ("old_stone", "hoard") else "strings"
            for m in pad_v:
                c.sc.note("pad", pad_inst, m, t, c.bar_s * 0.98, 0.2, pan=0.3)
            c.sc.note("bass", "strings", r, t, c.bar_s * 0.98, 0.26)
            if c.fam.name == "burrow" and c.rng.random() < 0.5:
                c.sc.note("sparkle", "glock", int(c.rng.choice([84, 86, 88, 91])), t + u * int(c.rng.integers(1, c.fam.meter)), u, 0.2, pan=float(c.rng.uniform(-0.7, 0.7)))
            elif c.fam.name == "crew":
                for j, m in enumerate([r + 12, r + 12 + q1, r + 12 + q2, r + 24]):
                    c.sc.note("chords", "harp", m, t + j * 2 * u, u * 1.8, 0.22, pan=-0.3)
            elif c.fam.name == "old_stone" and k % 4 == 0:
                c.sc.note("bell", "glock", deg_midi(c.fam, c.tonic, d) - 12, t, 3.0, 0.28)
            elif c.fam.name == "coil":
                c.sc.note("drone", "strings", c.bass(0) + 7, t, c.bar_s * 0.98, 0.16, pan=-0.4)
                if k % 2 == 1:
                    c.sc.note("bell", "glock", deg_midi(c.fam, c.tonic, d + 4) - 12, t + u * 4, 2.0, 0.2, pan=0.4)
            continue
        if style == "oompah":  # 6/8: the bass, then the chord twice; the second half a fifth up
            hits = ((1, 2, 4, 5), (2, 5), (1, 2, 3, 4, 5))[c.t.osti % 3]
            c.sc.note("bass", "spic", r, t, u * 1.5, 0.55)
            c.sc.note("bass", "spic", r + 7, t + 3 * u, u * 1.5, 0.45)
            for h in hits:
                for m in tri[:2] if h % 3 else tri:
                    c.sc.note("chords", "harp", m, t + h * u, u * 0.9, 0.24, pan=-0.25)
            if fight and not brk:
                c.sc.add("tabor", drum(c, 0.4), t, pan=0.3)
                c.sc.add("tabor", drum(c, 0.3), t + 3 * u, pan=0.3)
                if k % 2 == 0:
                    c.sc.add("drums", timp(kettle(r), 0.45), t)
            if brk and c.rng.random() < 0.7:
                c.sc.note("sparkle", "glock", tri[-1] + 24, t + u * int(c.rng.integers(0, 6)), u, 0.25, pan=float(c.rng.uniform(-0.7, 0.7)))
        elif style == "gallop":  # every eighth on marcato strings, the drums behind
            steps = ((0, 0, 12, 0, 7, 0, 12, 7), (0, 7, 12, 7, 0, 7, 12, 7), (0, 0, 0, 12, 0, 0, 7, 12))[c.t.osti % 3]
            accents = ((0, 3, 6), (0, 4), (0, 3, 6))[c.t.osti % 3]
            inst = "harp" if brk else "spic"
            base = r + 12 if r < 42 else r  # a gallop down at C2 is mud: it runs from D2 up
            for j, s in enumerate(steps):
                c.sc.note("osti", inst, base + s, t + j * u, u * 0.8, 0.6 if j in accents else 0.42, pan=-0.25)
            if not brk:
                c.sc.add("drums", timp(kettle(r), 0.7), t)
                c.sc.add("drums", timp(fifth_under(kettle(r)), 0.5), t + 4 * u)
                for j, v in ((2, 0.55), (6, 0.55), (7, 0.3)):
                    c.sc.add("tabor", drum(c, v), t + j * u, pan=0.3)
                if label != "A":
                    for m in tri:
                        c.sc.note("chords", "harp", m + 12, t + 3 * u, u * 0.7, 0.3, pan=0.35)
        elif style == "stomp":  # slow and heavy: kettles on one and three, low strings chugging, the organ holding
            chug = ((0, 3, 4, 6), (0, 1, 2, 4, 5, 6), (0, 2, 3, 4, 6, 7))[c.t.osti % 3]
            for j in chug:
                c.sc.note("osti", "spic", r + 12, t + j * u, u * 0.85, 0.55 if j in (0, 4) else 0.4, pan=-0.2)
            if not brk:
                low = kettle(r)
                c.sc.add("drums", timp(low, 0.85), t)
                c.sc.add("drums", timp(low, 0.6), t + 4 * u)
                if c.t.osti % 3 == 1:
                    c.sc.add("drums", timp(fifth_under(low), 0.35), t + 7 * u)
                c.sc.add("tabor", drum(c, 0.45), t + 2 * u, pan=0.25)
                c.sc.add("tabor", drum(c, 0.45), t + 6 * u, pan=0.25)
            for m in tri:
                c.sc.note("pad", "organ", m - 12 if m > 60 else m, t, c.bar_s * 0.98, 0.22)
            if label != "A":
                for m in tri:
                    c.sc.note("choir", "horn", m, t, c.bar_s * 0.98, 0.28, pan=0.2)
        elif style == "asym":  # 7/8 in 2+2+3: the strings on each group, the harpsichord winding round the fifth
            wind = ((0, 7, 8, 7, 0, 7, 3), (7, 8, 7, 6, 7, 3, 2), (0, 3, 7, 8, 11, 8, 7))[c.t.osti % 3]
            for j, g in enumerate((0, 2, 4)):
                c.sc.note("bass", "spic", r + (7 if j == 1 else 0), t + g * u, u * 1.6, 0.6 if j == 0 else 0.45)
            for j, s in enumerate(wind):
                c.sc.note("osti", "harp", c.bass(0) + 24 + s, t + j * u, u * 0.85, 0.34 if j in (0, 2, 4) else 0.26, pan=-0.3)
            if not brk:
                for g, v in ((0, 0.5), (2, 0.32), (4, 0.42), (6, 0.25)):
                    c.sc.add("tabor", drum(c, v), t + g * u, pan=0.3)
                if k % 2 == 0:
                    c.sc.add("drums", timp(kettle(r), 0.55), t)
            if label != "A":
                for m in tri:
                    c.sc.note("pad", "strings", m, t, c.bar_s * 0.98, 0.18, pan=0.35)
        elif style == "dragon":  # the champion's drive: an ostinato on the root, kettles, the choir over it
            steps = ((0, 0, 12, 0, 1, 0, 7, 1), (0, 12, 0, 7, 0, 12, 1, 0), (0, 0, 7, 0, 0, 12, 0, 1))[c.t.osti % 3] if d == 0 else (0, 0, 12, 0, 0, 7, 0, 12)
            for j, s in enumerate(steps):
                c.sc.note("osti", "harp" if brk else "spic", r + s, t + j * u, u * 0.8, 0.62 if j in (0, 3, 6) else 0.45, pan=-0.25)
            if not brk:
                low = kettle(r)
                c.sc.add("drums", timp(low, 0.8), t)
                c.sc.add("drums", timp(fifth_under(low), 0.55), t + 4 * u)
                for j, v in ((2, 0.55), (6, 0.55), (7, 0.35)):
                    c.sc.add("tabor", drum(c, v), t + j * u, pan=0.3)
            if label == "A":
                for m in tri:
                    c.sc.note("pad", "organ", m, t, c.bar_s * 0.98, 0.24)
            elif not brk:
                for m in tri:
                    c.sc.note("choir", "horn", m + 12 if m < 60 else m, t, c.bar_s * 0.98, 0.3, pan=0.2)
        elif style == "minuet":  # 3/4: the bass held, the chord on two and three
            c.sc.note("bass", "strings", r, t, c.bar_s * 0.98, 0.3)
            chord_inst = "organ" if c.t.deep else "harp"
            for h in ((2, 4), (2, 3, 4, 5), (1, 2, 4))[c.t.osti % 3]:
                for m in tri:
                    c.sc.note("chords", chord_inst, m, t + h * u, u * (1.6 if chord_inst == "organ" else 0.9), 0.22 if chord_inst == "organ" else 0.28, pan=-0.25)
            if label != "A":
                pad_v = c.triad(d, 60, pad_v)
                for m in pad_v:
                    c.sc.note("pad", "strings", m, t, c.bar_s * 0.98, 0.18, pan=0.35)
        elif style == "chorale":  # the organ holding the chord, the strings under it, a bell now and then
            for m in tri:
                c.sc.note("pad", "organ", m, t, c.bar_s * 0.98, 0.22)
            c.sc.note("bass", "strings", r, t, c.bar_s * 0.98, 0.3)
            if c.t.osti % 2 == 1:
                for j, m in enumerate((r + 12, r + 12 + q2, r + 24, r + 12 + q2)):
                    c.sc.note("chords", "harp", m, t + j * 2 * u, u * 1.9, 0.18, pan=-0.3)
            if k % 4 == 0:
                c.sc.note("bell", "glock", deg_midi(c.fam, c.tonic, d) - 12, t, 3.5, 0.3, pan=0.3)
            if label != "A":
                pad_v = c.triad(d, 60, pad_v)
                for m in pad_v:
                    c.sc.note("choir", "horn", m, t, c.bar_s * 0.98, 0.22, pan=0.2)
        elif style == "rocking":  # 6/8: a broken chord rocking up and back, drips high in the cave
            for j, m in enumerate((r, r + 12 + q1, r + 12 + q2, r + 24, r + 12 + q2, r + 12 + q1)):
                c.sc.note("chords", "harp", m, t + j * u, u * 1.6, 0.4 if j == 0 else 0.28, pan=-0.3 + 0.12 * j)
            c.sc.note("bass", "strings", r, t, c.bar_s * 0.98, 0.33)
            if label != "A":
                pad_v = c.triad(d, 62, pad_v)
                for m in pad_v[1:]:
                    c.sc.note("pad", "strings", m, t, c.bar_s * 0.98, 0.2, pan=0.35)
            if c.rng.random() < 0.45:
                c.sc.note("sparkle", "glock", int(c.rng.choice([81, 83, 86, 88, 90])) + c.t.shift, t + u * int(c.rng.integers(1, 6)), u, 0.22, pan=float(c.rng.uniform(-0.8, 0.8)))
        elif style == "gavotte":  # the bass on one and three, the chord between
            for j in (0, 4):
                c.sc.note("bass", "harp", r + 12, t + j * u, u * 1.8, 0.42)
            for j in (2, 6) if c.t.osti % 2 == 0 else (2, 3, 6, 7):
                for m in tri:
                    c.sc.note("chords", "harp", m, t + j * u, u * 0.9, 0.26, pan=-0.3)
            c.sc.note("bass", "spic", r, t, u * 1.2, 0.3)
            c.sc.note("bass", "spic", r + 7, t + 4 * u, u * 1.2, 0.26)
            if label != "A":
                c.sc.add("tabor", drum(c, 0.25), t + 2 * u, pan=0.3)
                c.sc.add("tabor", drum(c, 0.25), t + 6 * u, pan=0.3)
        elif style == "gentle":  # a slow broken chord, the strings holding, a bell every four bars
            pad_v = c.triad(d, 57, pad_v)
            for m in pad_v:
                c.sc.note("pad", "strings", m, t, c.bar_s * 0.98, 0.18, pan=0.3)
            for j, m in enumerate((r + 12, r + 12 + q1, r + 12 + q2, r + 12 + q1)):
                c.sc.note("chords", "harp", m, t + j * 2 * u, u * 1.9, 0.24, pan=-0.3)
            c.sc.note("bass", "strings", r, t, c.bar_s * 0.98, 0.28)
        elif style == "toccata":  # eighths running round the chord, a light drum
            for j, s in enumerate((0, q1, q2, 12, q2, q1, 0, q1)):
                c.sc.note("osti", "marimba", r + 12 + s, t + j * u, u * 0.85, 0.34 if j % 4 == 0 else 0.26, pan=-0.3)
            c.sc.note("bass", "strings", r, t, c.bar_s * 0.98, 0.28)
            c.sc.add("tabor", drum(c, 0.28), t, pan=0.3)
            c.sc.add("tabor", drum(c, 0.2), t + 4 * u, pan=0.3)
            if label != "A":
                for m in tri:
                    c.sc.note("pad", "strings", m + 12, t, c.bar_s * 0.98, 0.15, pan=0.35)


def melody(c: Ctx, p: Plan) -> None:
    """Who plays the tune in each section: the first lead, then the next with the first an octave under it, a break of
    the head on bells, and the tune again with an echo."""
    for label, bar0, _ in p.sections:
        if label == "A":
            play(c, "lead", c.lead(0), p.phrases["p1"], bar0, 0.78, pan=0.05)
            play(c, "lead", c.lead(0), p.phrases["p2"], bar0 + 4, 0.78, pan=0.05)
        elif label in ("B", "B2"):
            inst = c.lead(1) if label == "B" else c.lead(2)
            play(c, "lead", inst, p.phrases["p3"], bar0, 0.8, pan=0.05)
            play(c, "lead", inst, p.phrases["p4"], bar0 + 4, 0.8, pan=0.05)
            if c.fam.kind == "battle" and not c.t.calm:
                play(c, "lead2", c.lead(0), p.phrases["p3"] + p.phrases["p4"], bar0, 0.42, pan=-0.3, octave=-12)
        elif label == "C":  # the break: the head's first bar on the bells, answered an octave up, then the way home
            first_bar, acc = [], 0
            for d, dur in c.fam.head:
                if acc >= c.fam.meter:
                    break
                first_bar.append((d, dur))
                acc += dur
            play(c, "bell", "glock", first_bar, bar0, 0.5, pan=0.2)
            play(c, "lead2", c.lead(1), first_bar, bar0 + 2, 0.45, pan=-0.2, octave=12)
            play(c, "lead", c.lead(2), p.phrases["p4"], bar0 + 4, 0.72, pan=0.05)
        elif label == "A2":
            inst = c.lead(1)
            play(c, "lead", inst, p.phrases["p1"] + p.phrases["p2"], bar0, 0.8, pan=0.05)
            echo = c.lead(2) if c.lead(2) != inst else c.lead(3)
            delay = c.unit * (3 if c.fam.meter in (6, 7) else 4)
            play(c, "echo", echo, p.phrases["p1"] + p.phrases["p2"], bar0, 0.34, pan=0.5, octave=12, late=delay)


LEVELS = {"lead": -2, "lead2": -7, "echo": -9, "bass": -2, "chords": -2, "pad": -6, "osti": -3, "drums": -4, "tabor": -4,
          "bell": -6, "sparkle": -6, "choir": -7, "drone": -6}
SENDS = {"lead": 0.4, "lead2": 0.35, "echo": 0.6, "bass": 0.3, "chords": 0.35, "pad": 0.5, "osti": 0.2, "drums": 0.3,
         "tabor": 0.2, "bell": 0.65, "sparkle": 0.8, "choir": 0.5, "drone": 0.5}


def air(x: np.ndarray) -> np.ndarray:
    """A gentle lift above 2.5 kHz (about +4 dB by 8 kHz): close-miked sections in a generated hall come out dull, and a
    dull orchestra reads as a synthesised one. Zero-phase and circular, so a loop stays seamless."""
    return S.spectrum_filter(x, lambda f: 1.0 + 0.6 * np.clip((f - 2500.0) / 5500.0, 0.0, 1.0))


def master(x: np.ndarray, target_db: float, **kw) -> tuple[np.ndarray, int]:
    """The lift, then the loudness and the knee (`sampler.master`). It goes first: the knee keeps the mix under the
    ceiling, and a lift after it put peaks past full scale that the 16-bit write clipped flat (fight-gumdrop did)."""
    return S.master(air(x), target_db, **kw)


def render_tune(t: Tune) -> tuple[np.ndarray, float, str]:
    fam = t.family
    unit = 60.0 / (fam.bpm * t.tempo)
    bar_s = fam.meter * unit
    bars = max(16, int(np.ceil(t.min_seconds / bar_s / 8)) * 8)
    p = plan(t, bars)
    seconds = len(p.chords) * bar_s
    sc = S.Score(seconds)
    tonic = fam.tonic + t.shift - (12 if t.deep and fam.tonic + t.shift > 64 else 0)
    c = Ctx(t, sc, unit, bar_s, tonic, np.random.default_rng(t.seed + 1))
    accompany(c, p)
    melody(c, p)
    secs = [(label, b0 * bar_s, (b0 + n) * bar_s) for label, b0, n in p.sections]
    battle = fam.kind == "battle" and not t.calm
    log.info("%s: %s, %s, %d bars of %d at %.0f/min (%.1f s), tonic %s, leads %s", t.name, fam.name, fam.scale, len(p.chords), fam.meter,
             fam.bpm * t.tempo, seconds, S.name(tonic), "/".join(c.lead(k) for k in range(3)))
    x = S.mix(sc, LEVELS, SENDS, sections=secs, wet=0.8 if battle else 1.05)
    x, hits = master(x, S.BATTLE_RMS_DB if battle else S.EXPLORE_RMS_DB)
    S.report(t.name, x, hits)
    return x, seconds, "loop"


# ---------------------------------------------------------------- the two written out whole, and the stings


def melody_named(sc: S.Score, stem: str, inst: str, notes: list, t0: float, unit: float, vel: float, pan: float = 0.0, shift: int = 0) -> None:
    shift += O.fit_octave(inst, [S.midi(n) + shift for n, _ in notes if n != "r"])
    t = t0
    for n, d in notes:
        if n != "r":
            sc.note(stem, inst, S.midi(n) + shift, t, d * unit * 0.95, vel, pan)
        t += d * unit


QUAL = {"m": (0, 3, 7), "M": (0, 4, 7), "dim": (0, 3, 6)}


def named_chord(nm: str) -> tuple[int, tuple]:
    root, q = nm.split(":")
    return S.midi(root), QUAL[q]


def caves_first() -> tuple[np.ndarray, float, str]:
    """The Wet Caves, "Drip Lullaby": E Dorian in 6/8, its tune written out (the caves family's head is its opening)."""
    unit = 60 / 168
    bar = 6 * unit
    a = [("E4", 3), ("B4", 2), ("A4", 1), ("B4", 2), ("C#5", 1), ("D5", 3), ("E5", 2), ("D5", 1), ("C#5", 2), ("B4", 1),
         ("B4", 3), ("F#4", 3), ("G4", 2), ("A4", 1), ("B4", 3), ("E5", 3), ("D5", 2), ("B4", 1),
         ("C#5", 2), ("B4", 1), ("A4", 2), ("F#4", 1), ("E4", 6)]
    b = [("B4", 3), ("F#5", 2), ("E5", 1), ("D5", 2), ("E5", 1), ("F#5", 3), ("G5", 2), ("F#5", 1), ("E5", 2), ("D5", 1),
         ("C#5", 6), ("D5", 2), ("C#5", 1), ("B4", 3), ("A4", 2), ("B4", 1), ("C#5", 3),
         ("B4", 2), ("A4", 1), ("F#4", 2), ("A4", 1), ("E4", 6)]
    ca = ["E3:m", "D3:M", "A2:M", "B2:m", "C3:M", "D3:M", "A2:M", "E3:m"]
    cb = ["E3:m", "D3:M", "G2:M", "A2:M", "B2:m", "A2:M", "D3:M", "E3:m"]
    chords = ca + cb + ca
    sc = S.Score(len(chords) * bar)
    rng = np.random.default_rng(7)
    for i, ch in enumerate(chords):
        r, q = named_chord(ch)
        t = i * bar
        for k, m in enumerate([r - 12, r + q[1], r + q[2], r + 12, r + q[2], r + q[1]]):
            sc.note("chords", "harp", m, t + k * unit, unit * 1.6, 0.42 if k == 0 else 0.3, pan=-0.3 + 0.12 * k)
        sc.note("bass", "strings", r - 12, t, bar * 0.98, 0.35)
        if i >= 8:
            for m in (r + q[1] + 12, r + q[2] + 12):
                sc.note("pad", "strings", m, t, bar * 0.98, 0.22, pan=0.35)
        if rng.random() < 0.45:
            sc.note("sparkle", "glock", int(rng.choice([88, 83, 86, 81, 90])), t + unit * int(rng.integers(1, 6)), unit, 0.22, pan=float(rng.uniform(-0.8, 0.8)))
    melody_named(sc, "lead", "flute", a, 0, unit, 0.75, pan=0.1)
    melody_named(sc, "lead", "clarinet", b, 8 * bar, unit, 0.75, pan=0.1)
    melody_named(sc, "lead2", "cellos", a, 16 * bar, unit, 0.55, pan=-0.1, shift=-12)
    melody_named(sc, "echo", "glock", a, 16 * bar + unit * 3, unit, 0.3, pan=0.5, shift=12)
    sc.note("bell", "glock", "E5", 0, 4, 0.35)
    sc.note("bell", "glock", "B4", 16 * bar, 4, 0.3)
    secs = [("A", 0, 8 * bar), ("B", 8 * bar, 16 * bar), ("A2", 16 * bar, 24 * bar)]
    x = S.mix(sc, {"chords": -6, "bass": -9, "pad": -8, "lead": 0, "lead2": -1, "sparkle": -10, "bell": -8, "echo": -6},
              {"chords": 0.35, "bass": 0.3, "pad": 0.5, "lead": 0.55, "lead2": 0.5, "sparkle": 0.8, "bell": 0.7, "echo": 0.6}, sections=secs, wet=1.1)
    x, hits = master(x, S.EXPLORE_RMS_DB)
    S.report("explore-caves", x, hits)
    return x, len(chords) * bar, "loop"


def vexalith() -> tuple[np.ndarray, float, str]:
    """The last champion, "The Champion Stirs": the Hoard's theme as it was first written, G Phrygian dominant at 138."""
    unit = 60 / 138 / 2
    bar = 8 * unit
    a = [("G4", 3), ("D5", 3), ("C5", 2), ("Eb5", 2), ("D5", 1), ("C5", 1), ("B4", 4), ("C5", 3), ("G4", 3), ("Ab4", 2), ("G4", 8),
         ("D5", 3), ("G5", 3), ("F5", 2), ("Eb5", 2), ("F5", 1), ("Eb5", 1), ("D5", 4), ("C5", 2), ("Eb5", 2), ("D5", 2), ("Ab4", 2),
         ("B4", 4), ("G4", 4)]
    frag = [("G5", 3), ("D6", 3), ("C6", 2), ("r", 8), ("C6", 3), ("G5", 3), ("Ab5", 2), ("G5", 8)]
    ca = ["G2:M", "C3:m", "Ab2:M", "G2:M", "G2:M", "C3:m", "Ab2:M", "G2:M"]
    cbreak = ["Ab2:M", "Ab2:M", "G2:M", "G2:M", "F2:m", "Ab2:M", "G2:M", "G2:M"]
    chords = ca + ca + cbreak
    sc = S.Score(len(chords) * bar)
    for i, ch in enumerate(chords):
        r, q = named_chord(ch)
        t = i * bar
        breakdown = 16 <= i < 22
        steps = [0, 0, 12, 0, 1, 0, 7, 1] if ch.startswith("G2") else [0, 0, 12, 0, 0, 7, 0, 12]
        for k, s in enumerate(steps):
            sc.note("osti", "harp" if breakdown else "spic", r + s, t + k * unit, unit * 0.8, 0.62 if k in (0, 3, 6) else 0.45, pan=-0.25)
        if not breakdown or i >= 20:
            low = r if r < 45 else r - 12
            sc.add("drums", timp(low, 0.8), t)
            sc.add("drums", timp(low - 5, 0.55), t + 4 * unit)
            for k in (2, 6):
                sc.add("tabor", O.hit("snare", 0.55), t + k * unit, pan=0.3)
            sc.add("tabor", O.hit("snare_soft", 0.35), t + 7 * unit, pan=0.3)
        if i >= 8 and not breakdown:
            for m in (r + 12, r + q[1] + 12, r + q[2] + 12):
                sc.note("choir", "horn", m, t, bar * 0.98, 0.32, pan=0.2)
        if i < 8:
            for m in (r + 12, r + q[1] + 12, r + q[2] + 12):
                sc.note("pad", "organ", m, t, bar * 0.98, 0.25)
    melody_named(sc, "lead", "horn", a, 0, unit, 0.8, pan=0.05, shift=-12)
    melody_named(sc, "lead", "trumpet", a, 8 * bar, unit, 0.85, pan=0.05)
    melody_named(sc, "lead2", "violins", a, 8 * bar, unit, 0.5, pan=-0.3)
    melody_named(sc, "bell", "glock", frag, 16 * bar, unit, 0.45, pan=0.2, shift=-12)
    melody_named(sc, "bell", "glock", frag[:3], 20 * bar, unit, 0.5, pan=-0.2, shift=-12)
    sc.note("bell", "glock", "G3", 0, 3, 0.5)
    secs = [("organ", 0, 8 * bar), ("strings", 8 * bar, 16 * bar), ("break", 16 * bar, 24 * bar)]
    x = S.mix(sc, {"osti": -4, "drums": -8, "tabor": -10, "choir": -9, "pad": -10, "lead": 0, "lead2": -6, "bell": -5},
              {"osti": 0.2, "drums": 0.3, "tabor": 0.2, "choir": 0.5, "pad": 0.4, "lead": 0.35, "lead2": 0.35, "bell": 0.6}, sections=secs, wet=0.8)
    x, hits = master(x, S.BATTLE_RMS_DB)
    S.report("champion-vexalith", x, hits)
    return x, len(chords) * bar, "loop"


def sting(kind: str) -> tuple[np.ndarray, float, str]:
    """victory (a foe spared): bells and harpsichord climbing a B-flat major chord into a held choir chord, 2.6 s.
    fanfare (the stairs): organ and strings in octaves, a kettle roll, landing on E-flat major with bells, 4.8 s."""
    if kind == "victory":
        step, length, fade = 60 / 132 / 4, 2.6, 0.8
        line = [("F4", 1), ("Bb4", 1), ("D5", 1), ("F5", 1), ("Eb5", 2), ("G5", 2), ("F5", 2), ("Bb5", 8)]
        sc = S.Score(length, loop=False)
        melody_named(sc, "lead", "harp", line, 0, step, 0.75)
        melody_named(sc, "lead", "flute", line, 0, step, 0.6)
        melody_named(sc, "lead2", "glock", line[-2:], 8 * step, step, 0.5)
        land = 10 * step
        for m in ("Bb3", "D4", "F4", "Bb4"):
            sc.note("choir", "strings", m, land, 1.6, 0.4, pan=0.2)
        for m, t in (("Bb2", 0), ("Eb3", 4 * step), ("F3", 6 * step), ("Bb2", land)):
            sc.note("bass", "strings", m, t, 0.5 if t < land else 1.6, 0.42)
        x = S.mix(sc, {"lead": 0, "lead2": -4, "choir": -7, "bass": -8}, {"lead": 0.4, "lead2": 0.7, "choir": 0.6, "bass": 0.3}, wet=0.9)
    else:
        step, length, fade = 60 / 132 / 2, 4.8, 1.2
        line = [("Bb4", 1), ("Eb5", 1), ("G5", 2), ("F5", 1), ("Eb5", 1), ("Bb5", 2), ("Ab5", 1), ("G5", 1), ("F5", 1), ("D5", 1), ("Eb5", 6)]
        sc = S.Score(length, loop=False)
        melody_named(sc, "lead", "trumpet", line, 0, step, 0.8)
        melody_named(sc, "lead2", "horn", line, 0, step, 0.7, shift=-12)
        land = 12 * step
        for k in range(8):
            sc.add("drums", O.hit("snare_soft", 0.3 + 0.07 * k), land - (8 - k) * step / 2)
        sc.add("drums", timp(S.midi("Eb2") + 12, 0.85), land)
        sc.add("drums", O.hit("crash", 0.6), land)
        for m in ("Eb4", "G4", "Bb4", "Eb5"):
            sc.note("pad", "strings", m, land, 2.2, 0.38, pan=0.3)
        sc.note("bell", "glock", "Eb5", land, 3.0, 0.45)
        sc.note("bell", "glock", "Bb4", land + step, 3.0, 0.3)
        for m, t in (("Eb3", 0), ("Ab2", 4 * step), ("Bb2", 8 * step), ("Eb2", land)):
            sc.note("bass", "strings", m, t, 2.0 if t < land else 2.2, 0.45)
        x = S.mix(sc, {"lead": 0, "lead2": -5, "drums": -6, "pad": -6, "bell": -4, "bass": -7},
                  {"lead": 0.4, "lead2": 0.4, "drums": 0.3, "pad": 0.55, "bell": 0.7, "bass": 0.3}, wet=0.9)
    x, hits = master(x, S.BATTLE_RMS_DB, length=length, fade=fade)
    S.report("sting-" + kind, x, hits, loop=False)
    return x, length, "sting"


# ---------------------------------------------------------------- build


def build(name: str, wav_dir: str) -> tuple[str, float, float]:
    """Render one tune and encode it. Returns (name, its length, seconds it took)."""
    logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
    started = time.time()
    S.rng = np.random.default_rng(zlib.crc32(name.encode()))  # the sampler's humanising, per tune: a build is repeatable
    O.reset()  # and the orchestra's round robins start over, so the tune does not depend on what its worker played before
    if name == "explore-caves":
        x, seconds, how = caves_first()
    elif name == "champion-vexalith":
        x, seconds, how = vexalith()
    elif name.startswith("sting-"):
        x, seconds, how = sting(name.removeprefix("sting-"))
    else:
        x, seconds, how = render_tune(tunes()[name])
    peak = float(np.abs(x).max())
    if peak > 1.0:  # the knee keeps a master under its ceiling; anything over full scale is clipped flat on the way out
        log.warning("%s: peak %+.2f dBFS is over full scale, and the 16-bit write will clip it", name, 20 * np.log10(peak))
    wav = os.path.join(wav_dir, name + ".wav")
    S.write(wav, x, loop=how == "loop")
    out = os.path.join(OUT_DIR, name + ".ogg")
    args = [os.path.join(HERE, "to_ogg.sh"), how, wav, out] + ([f"{seconds:.9f}"] if how == "loop" else [])
    subprocess.run(args, check=True, env=dict(os.environ, OGG_QUALITY=OGG_QUALITY))
    took = time.time() - started
    log.info("%s: %.2f s -> %s (%.0f KB) in %.1f s", name, seconds, os.path.relpath(out, ROOT), os.path.getsize(out) / 1024, took)
    return name, seconds, took


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", default="", help="comma-separated tune names (default: all)")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument("--wav-dir", default="/tmp/donjon-themes-wav")
    ap.add_argument("--list", action="store_true", help="print the tune names and stop")
    a = ap.parse_args()
    names = list(tunes())
    if a.list:
        print("\n".join(names))
        return
    if a.only:
        wanted = [n.strip() for n in a.only.split(",") if n.strip()]
        unknown = [n for n in wanted if n not in names]
        if unknown:
            sys.exit(f"unknown tune(s): {', '.join(unknown)}; --list shows them")
        names = wanted
    os.makedirs(a.wav_dir, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    started = time.time()
    with ProcessPoolExecutor(max_workers=a.jobs) as pool:
        done = list(pool.map(build, names, [a.wav_dir] * len(names)))
    log.info("built %d tunes in %.0f s (%d at a time)", len(done), time.time() - started, a.jobs)


if __name__ == "__main__":
    main()
