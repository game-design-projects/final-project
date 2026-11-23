# Music set: fight, boss and final-boss themes, and three exploring loops

Abdulla's renders and the MIDI they come from. Three of them are in the game (the feature `music-set`, on by default),
copied byte for byte to `assets/audio/` and played by `src/audio/music.gd` (`SET`, `set_theme`) in place of the foe's own
tune: #299 took them out when every foe got a tune of its own, and they are back as a choice beside those
(`no-music-set` plays every foe its own). After a new render, copy the new `.ogg` over the one in `assets/audio/`. This
folder is under `tools/music/`, which Godot ignores.

| File | In the game as | Plays |
| --- | --- | --- |
| `donjon_piano_battle.ogg` | `assets/audio/set-fight.ogg` | A fight with a monster. 41.86 s, one loop. |
| `donjon_battle_boss.ogg` | `assets/audio/set-boss.ogg` | A fight with a champion (a dragon on the stairs). 41.86 s. |
| `donjon_battle_final_boss.ogg` | `assets/audio/set-final.ogg` | The fight with the last champion, at the Last Door. 45.33 s. |
| `donjon_explore_choir.ogg`, `donjon_explore_undercroft.ogg`, `donjon_explore_caves.ogg` | Not in the game | Exploring loops, 130.91 s each. |
| `*.mid` | | The MIDI each render comes from. |

The three fight tracks measure -16.2 to -16.3 dBFS mean against -17.0 for the foes' own tunes, so `TRIM_DB` plays them
1 dB down.

## How they were rendered

From Abdulla's render notes. All of it is offline, with no DAW:

- The notes are written in Python as MIDI (mido 1.3.3).
- Each MIDI channel is rendered on its own with FluidSynth 2.3.4 at 44.1 kHz, with FluidSynth's own reverb and chorus off.
- The stems are levelled against each other in numpy/scipy, then a hall reverb is added by convolution. The impulse is
  generated in code (filtered noise with a 1 to 3 s decay), so no third-party reverb sample is used.
- Note and reverb tails are folded back into the start, so each file is one exact, seamless loop.
- The mix is normalised to a target RMS level with a soft limiter and encoded with ffmpeg 6.1.1 as Ogg Vorbis, quality 6.

| File | Tempo, bars | RMS target | Soundfonts |
| --- | --- | --- | --- |
| `donjon_piano_battle.ogg` | 172 BPM, 30 | -17 dBFS | MuseScore General |
| `donjon_battle_boss.ogg` | 172 BPM, 30 | -17 dBFS | MuseScore General (its choir too) |
| `donjon_battle_final_boss.ogg` | 180 BPM, 34 | -17 dBFS | MuseScore General |
| `donjon_explore_choir.ogg` | 88 BPM, 48 | -19 dBFS | GeneralUser GS voices, MuseScore General piano |
| `donjon_explore_undercroft.ogg`, `donjon_explore_caves.ogg` | 88 BPM, 48 | -19 dBFS | GeneralUser GS voices, MuseScore General |

All the melodies are original (the battle tune is in G Dorian, on Gm, B flat, C and F), and nothing is sampled from a game.

## The soundfonts and their licences

Only rendered audio is in the repo and the game; neither `.sf2` is.

- **MuseScore General** (`MuseScore_General_Full.sf2`, from Ubuntu's `musescore-general-soundfont-lossless` 0.2.1;
  <https://musescore.org/en/node/269869>): the three fight themes, and most of the exploring loops. It is shared under the
  MIT licence, and its licence file asks that its acknowledgements be kept; `assets/CREDITS.txt` carries them. Checked on
  2026-11-23 against `MuseScore_General_License.md` as the soundfont's download site serves it, which is the notice for
  `MuseScore_General.sf2`. Not checked: the Full file's own notice, and the render notes' statement that its grand piano is
  the public-domain "Splendid Grand", which that licence file does not mention.
- **GeneralUser GS v2.0.3** by S. Christian Collins (<https://www.schristiancollins.com/generaluser>), free to use, commercially
  too: the voices ("Voice Oohs", "Choir Aahs") of the three exploring loops, which are not in the game, and everything in
  the hum theme (`../hum-theme/`).

## Not in the repo

The scripts these were written and mixed with (`piano.py`, `explore_choir.py`, `explore_levels.py`, `boss.py`,
`mixrender.py`). The MIDI and the renders are here; a new render needs those scripts from Abdulla.
