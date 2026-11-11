# Music and voices

## Music

The music follows the moment (`src/audio/music.gd`). `nomusic` turns it off, and the Settings sound page sets the level.

### The hum theme (the default, feature `hum-theme`)

Abdulla's hum theme plays by default: two loops on one hummed melody, "Cantiga take C", an 8-bar tune in modal C minor. Their source, MIDI and render script are in `tools/music/hum-theme/` (see its README), rendered with the GeneralUser GS soundfont.

- **Exploring: `hum-explore.ogg`**, 64 bars of 4/4 at 88 BPM, 174.55 s, one exact loop. A slow a-cappella "ooh" voice with echoes sings the theme a phrase at a time over a soft drum, bowed bass, pad, a faint choir, piano tolls and tremolo strings. It keeps the same pacing as before: a stretch of music, then a rest, then it picks up where it left off.
- **Fights: `hum-combat.ogg`**, 48 bars at 176 BPM, 65.45 s, one exact loop, in every fight. The same melody and chords on driving low strings, horns and violins, with choir, taiko, timpani and toms, and a breakdown with the echoing voice.
- **Stings:** the `victory` and `fanfare` stings below are kept.

The loops are mastered 1 dB hotter than the old music (−18 and −16 dBFS RMS), so `HUM_TRIM_DB` plays them 1 dB under the same volumes. `no-hum-theme` or `classic` brings back the old music below.

### The old music (`classic`, or `no-hum-theme`)

All of it is baroque dungeon music, in the spirit of Wizardry and Dragon Quest: one small band of real samples (harpsichord, church organ, strings, choir, music box and tubular bells, from the MusyngKite soundfont) plus synthesised kettle drums and a tabor, all in the same stone hall. Every piece is built on the game's own melody, **A B C D D D E D E D C C C D D D**, with its repeated notes short-short-long. The pieces are rendered offline and ship as Ogg Vorbis files in `assets/audio/` (about 5 MB in all).

**Exploring: `ambient.ogg`**, a passacaglia in D minor: 112.5 seconds, 3/4 at 64 BPM, five variations on an eight-bar ground bass (the lament D C B♭ A, then B♭ A D A). The melody lies over it note for note (Dm | C | B♭ | F/A | Gm/B♭ | A7 | Dm | A) and comes and goes. Variation I has no melody, only organ, low strings, harpsichord and a far bell. Then the melody passes to the music box, the strings, and the harpsichord over a swelling choir, and in the last variation a fragment on high strings while the texture thins back to the start. The ambient also comes and goes in time: about a minute and a half of music, then a minute or two of quiet before it drifts back. It fades in over two seconds, two seconds after a fight ends.

**Fights: four toccata-style loops, picked at random** (`battle-*.ogg`). Each is 16 bars: the melody in the minor, again coming home with a string run, lifted into the relative major on a second lead, then everyone together.

| Loop | Key, tempo | Lead (and the major lift) | Groove |
| --- | --- | --- | --- |
| toccata | D minor, 132 BPM | organ (strings, F major) | harpsichord 16ths against a pedal note, pumping bass, strings marcato |
| charge | A minor, 126 BPM | strings (choir, C major) | harpsichord arpeggios, organ chords, driving kettle drums |
| crusade | G minor, 112 BPM | choir (strings, B♭ major) | full organ, chugging strings, kettle drums and tabor in march time |
| gallop | E minor, 120 BPM | harpsichord (organ, G major) | galloping strings, kettle drums and tabor |

None goes faster than 132 BPM. Each fight picks one at random, never the one you heard last, and keeps it for the whole fight, because switching tunes mid-fight was jarring. The loop cuts in within a third of a second when a fight starts, and the ambient fades out underneath, keeping its place.

**Good news: one-shot cues** by the same band. `fanfare.ogg` (3.9 s) plays when you go down the stairs, and the ambient returns a few seconds after it. `victory.ogg` (2.3 s) plays when you win a fight (every foe killed, driven off, won over or let go; not when you run). Both quote the melody's opening in D major (D E F♯ G G G) and land on a IV6–V7–I cadence with bells.

**Levels.** The renders are mastered to −19 dBFS RMS (explore) and −17 dBFS RMS (fights and stings). The volumes in `TRACKS`/`STINGS` (0.7 and 0.75) put a fight about 2.6 dB above the exploring music.

**How it's made.** `tools/music/sampler.py` is an offline sampler. It decodes each soundfont key once, fixes the samples' tuning where two pitch estimators agree (the harpsichord runs up to 14 cents sharp), loops long organ, string and choir notes, and renders into a circular timeline so the loop points are seamless. The notes, chords and mix levels are tables at the top of each build script, and each build prints its bar-by-bar chord and melody table, a check of the outer voices for parallel fifths and octaves, the loudness of every part per section, and the peak, RMS, spectrum and loop seam. `tools/music/to_ogg.sh` cuts exactly one loop out of a render and encodes it, so Godot's gapless Ogg loop wraps inside the music. Rebuilding (numpy, scipy and ffmpeg with libvorbis) is in [tools/music/README.md](../tools/music/README.md); if you change a loop's tempo or length, update its `loopSeconds` in `TRACKS` (`src/audio/ambient.gd`), which `tests/audio/test_ambient.gd` checks. The soundfonts live in `tools/music/soundfonts/` and stay out of the exports; only the rendered `.ogg` files ship. Credits are in `assets/CREDITS.txt`.

### On trial: Abdulla's motifs (issue #49)

Abdulla's FluidSynth audition is five separate pieces of 13 to 24 seconds. None of it ships: the soundfont and its license aren't known yet, and an MP3 can't loop cleanly, so a keeper has to be rendered again from source. To hear them in the game, next to the current music:

```
tools/music/cut_motifs.sh motif_audition.mp3      # the file attached to the issue; writes build/motifs/motif-1.ogg ...
godot --path .                                    # all five, turn about with the exploring music
godot --path . -- motif=3                         # one of them
godot --path . -- no-motifs                       # without them
```

The feature `motifs` is on by default and does nothing unless those files are there: `build/` is ignored by git and left out of every export. Each motif plays once, then a rest of 4 to 8 seconds, then 25 to 35 seconds of `ambient.ogg`, and the log prints `music: motif N of 5` as each one starts. A fight or a sting takes it off. Still open for the team: which sections to keep, where they fit, and from Abdulla the source, the soundfont and its license. Update: two finished loops on a hummed theme, an exploring loop (88 BPM) and a combat loop (176 BPM), are in [tools/music/hum-theme/](../tools/music/hum-theme/README.md) with their source and soundfont license (GeneralUser GS, free for commercial use); they are not wired into the game yet. Whatever stays goes through `tools/music/`, `assets/CREDITS.txt` and `tools/audio_test.gd`, and this section goes away.

## Sound effects

Effects are synthesised at 44.1 kHz from recipes in `src/audio/sfx.gd` on the synth in `src/audio/synth.gd`, and rendered once when the game starts, spread over frames. The Master bus has a compressor and a limiter, and effects send to a room reverb (`src/audio/mix.gd`). `nosfx` silences effects and voices.

## Voices

Monsters speak their lines through `src/audio/voices.gd`. A line with a recording in `assets/voices/cosyvoice3/` plays it, and the music ducks under it. A line with no recording uses the synth voice for its species (`src/audio/shout.gd`), lower and louder for the champion. A stage direction stays silent.

The lines are rendered by `tools/voices/render.py`; see the README beside it.
