# Hum theme: dungeon exploration and combat loops (on trial, issue #49)

Two finished loops built on a hummed melody, with their full source. They are **not in the game yet**:
nothing in `src/` or `assets/` loads them. This folder is under `tools/music/`, which Godot ignores.

| File | What |
| --- | --- |
| `donjon_voice.ogg` | **Exploring.** 64 bars of 4/4 at 88 BPM = 174.55 s, one exact loop. A slow a-cappella "ooh" voice with echoes sings the theme over a soft lub-dub drum, bowed bass, pad, a faint "aah" choir, piano tolls and creeping tremolo strings. |
| `donjon_combat.ogg` | **Fights.** 48 bars at 176 BPM = 65.45 s, one exact loop. The same melody and chords: driving 3+3+2 low strings, horns and violins on the melody, choir, taiko, timpani and toms (no hi-hats or snare), a breakdown with the echoing voice. |
| `donjon_voice_x2.mp3`, `donjon_combat_x2.mp3` | Previews only: each loop played twice so you can hear the seam. An MP3 can't loop cleanly; the game should use the `.ogg`. |
| `donjon_voice.mid`, `donjon_combat.mid` | The MIDI the loops are rendered from. |
| `*.py` | The source (below). |

176 BPM is exactly twice 88, so one exploration bar equals two combat bars: switching on a bar line keeps the pulse.

## The music

- **Melody.** "Cantiga take C": an 8-bar tune in C minor in the style of a medieval cantiga, with a modal close
  (D C B♭ → C, no B-natural leading tone). The exploring loop sings it at half speed, a phrase at a time and only
  whole phrases, and saves the closing phrase for the end of the loop.
- **Harmony.** Modal C minor throughout: Cm, Fm, Gm, A♭maj7, B♭, D♭/F. No G major chord.
- **Form, exploring** (8 blocks of 8 bars): bed only · phrase 1 · phrase 2 (open) · phrase 1 on solo cello · bed only
  (heartbeat every other bar) · phrase 1 quieter, longer echo · phrase 2 quieter · the ending, then the loop restarts.
- **Form, combat** (6 blocks of 8 bars): charge · melody (horns) · melody + violins · breakdown (voice) · build · climax.

## Rebuild

Needs FluidSynth, ffmpeg (with libvorbis and libmp3lame), numpy, scipy and mido, plus the soundfont:

```bash
git clone --depth 1 https://github.com/mrbumpy409/GeneralUser-GS.git /tmp/gugs
cp /tmp/gugs/GeneralUser-GS.sf2 tools/music/hum-theme/     # or: export SF2=/tmp/gugs/GeneralUser-GS.sf2
cd tools/music/hum-theme
python3 render.py all        # or: voice | combat
```

`render.py` writes the MIDI, renders it dry with FluidSynth, adds a convolution hall and a gentle high shelf, folds
the reverb tail into the start so the loop wraps without a gap, normalises (−18 dBFS RMS exploring, −16 combat) and
writes the `.ogg` and the 2x preview. The build is deterministic: the humanising is seeded by the song title.

| Script | What |
| --- | --- |
| `dungeon_voice.py` | the exploring loop: blocks, voice and echo taps |
| `combat.py` | the combat loop |
| `loop.py`, `backdrop_var.py`, `brood.py` | the backing bed and instrument setup the loops share |
| `cantiga2.py`, `cantiga.py` | the melody (take C is `MOD` in `cantiga2.py`) |
| `musiclib.py`, `motifs2.py`, `motifs10.py` | key/voicing helpers, chord parsing, the MIDI writer |
| `render10b.py`, `render.py` | rendering, hall reverb, measurement, the loop cut |

## Licence

Rendered with **GeneralUser GS v2.0.3** by S. Christian Collins (https://www.schristiancollins.com,
https://github.com/mrbumpy409/GeneralUser-GS). Its licence: "You may use GeneralUser GS without restriction for
your own music creation, private or commercial." No attribution is required, though crediting it in
`assets/CREDITS.txt` is good form if these ship. The soundfont itself (about 30 MB) is not committed.

## To ship them

Copy the `.ogg` files into `assets/audio/`, hook them up in `src/audio/music.gd` / `src/audio/ambient.gd`
(set `loopSeconds` to 174.55 and 65.45), credit GeneralUser GS in `assets/CREDITS.txt`, and run
`tools/audio_test.gd`.
