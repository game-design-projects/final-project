# Music and voices

## Music

The music follows the moment (`src/audio/music.gd`). `nomusic` turns it off, and the Settings sound page sets the level.

Every place and every foe has a tune of its own, and no two are the same file. Of the music before, one theme is left: Abdulla's hum theme, at the camp. The passacaglia, the four battle loops, the hum theme's combat loop, the music set and the old stings are gone from the game (their sources stay in git history and in `tools/music/hum-theme/` and `tools/music/music-set/`).

### Where you are: the exploring music

`Music.scene_of(state)` picks the place, and `Music.set_scene` crosses over to it in a second. Each place keeps its own player while you are on its floor, so the camp gives the floor's music back where it left off.

| Place | Tune | Family |
| --- | --- | --- |
| THE OLD HALLS | `explore-halls`, and `explore-halls-deep` the second time round | a minuet, D Mixolydian, 3/4: violins, flute and oboe over harp chords and held strings |
| THE UNDERCROFT | `explore-undercroft`, `explore-undercroft-deep` | a chorale, A Aeolian, slow 4/4: organ, horn and cellos, glockenspiel, an echo a half bar behind |
| THE WET CAVES | `explore-caves` ("Drip Lullaby", written out whole), `explore-caves-deep` | a lullaby, E Dorian, 6/8: flute and clarinet over a rocking harp, glockenspiel drips |
| a clan's hall | `hall-burrow`, `hall-crew`, `hall-old_stone`, `hall-coil` | the clan's own family, at rest: slower, no drums, a pad |
| the camp | `assets/audio/hum-explore.ogg`, Abdulla's hum theme | "Cantiga take C", 174.55 s |
| the trader | `trade` | a gavotte, F major: oboe and clarinet over harp and pizzicato |
| the practice floor | `practice` | flute and harp over strings, C major |
| the test room | `test-room` | a toccata, G major: marimba |

A biome comes round again on a deeper floor (three biomes, five floors), and plays its `-deep` tune then: the same family, lower, slower, with the band turned round. A floor plays a stretch of 80 to 110 s, then rests 60 to 120 s and picks up where it left off; the camp and the trader play for as long as you are there (`STAY`). The game says where you are with the events it already has: `stage` (to the camp, the trader, back to exploring) and `state_replaced` (a new floor, a hall, the test room).

### Who you fight

`Music.fight_of(foe)` picks the tune: a monster its kind's, `fight-<kind>` for each of the 25 kinds in `data/kinds.json`, and a champion its own, `champion-<name>` for each in `data/floors.json`. When a floor is made, its foes' tunes load in the background (`Music.prepare`). The loop cuts in within a third of a second, and the exploring music fades out under it, keeping its place.

Each clan is a family: every tune of the clan opens its phrases with the clan's two-bar head motif, in the clan's mode, metre and band, and differs in key, tempo, lead instruments, ostinato, harmony and everything after the head. A kind's place in its clan (shallow to deep) moves its key round a circle (0, +3, −2, +5, −4, +2, −5) and its tempo up the deeper it lives.

| Clan | Kinds | Family |
| --- | --- | --- |
| burrow (slime) | slime, gumdrop, spitter, ooze, splitter, brood, tide | 6/8, Lydian: flute, clarinet, glockenspiel and oboe over harp and an oom-pah of spiccato strings, kettles |
| crew (bandit) | bandit, pickpocket, lookout, duelist, sapper, captain | 4/4 gallop, harmonic minor: solo violin, oboe, trumpet and clarinet over spiccato eighths, kettles and snare |
| old_stone (rock) | rock, pebble, boulder, quake, crusher, golem | slow 4/4 stomp, Dorian: horn, cellos, trombone and organ over low strings and kettles on one and three |
| coil (snake) | snake, adder, gazer, cobra, twinhead, hypno | 7/8 in 2+2+3, Hungarian minor: oboe, flute, solo violin and clarinet over a harp winding round the fifth, kettles |
| the Hoard (champions) | EMBERLING, CINDERA, ASHKA, SCORIA, and VEXALITH | 4/4, Phrygian dominant: trumpet, horns and violins over a spiccato ostinato, kettles, snare, brass and organ; Vexalith's is "The Champion Stirs", the family's theme written out whole |

A fight is three or four sections of eight bars (36 to 46 s): the tune, the B phrase with the first lead an octave under, a break with the head on the glockenspiel, and the tune again on the next lead with an echo.

### Good news: the stings

`sting-fanfare.ogg` (4.8 s, E♭ major, trumpet and horn into a snare roll, a kettle, a cymbal and the glockenspiel) plays when you go down the stairs, and the exploring music returns a few seconds after it. `sting-victory.ogg` (2.6 s, B♭ major, harp and flute climbing into a held string chord) plays when a fight ends in mercy; a kill ends the fight with its own sound and no sting (#168).

### Levels and how it's made

The renders are mastered to −19 dBFS RMS (exploring) and −17 dBFS RMS (fights and stings); `VOLUME` (0.7, 0.75) puts a fight about 2.6 dB above the exploring music, and `TRIM_DB` plays the hum theme 1 dB down (it is mastered at −18). `tools/music/build-themes.py` writes every tune: the families are tables at its top (mode, metre, tempo, head motif, rhythm cells, chord progressions, band), and each tune's phrases after the head are written from its own seed, so a build is repeatable. It plays them on a recorded orchestra, the Versilian Studios Chamber Orchestra 2, Community Edition (CC0; `tools/music/orchestra.py`): string sections bowed, spiccato and pizzicato, solo violin, harp, flute, oboe, clarinet, horn, trumpet, trombone, organ, glockenspiel, marimba, real kettle drums, snare, triangle and cymbals. A note takes the recorded dynamic nearest its velocity and alternates the round robins, each phrase swells to its middle and eases at its end, and held instruments join their notes. `tools/music/sampler.py` mixes it in one generated hall and logs each tune's loudness per part and section, spectrum and loop seam. Rebuilding is in [tools/music/README.md](../tools/music/README.md). The orchestra's recordings live in `build/vsco2` (`tools/music/fetch.sh`), out of git and the exports; credits are in `assets/CREDITS.txt`.

### On trial: Abdulla's motifs (issue #49)

Abdulla's FluidSynth audition is five separate pieces of 13 to 24 seconds. None of it ships: the soundfont and its license aren't known yet, and an MP3 can't loop cleanly, so a keeper has to be rendered again from source. To hear them in the game, next to the current music:

```
tools/music/cut_motifs.sh motif_audition.mp3      # the file attached to the issue; writes build/motifs/motif-1.ogg ...
godot --path .                                    # all five, turn about with the exploring music
godot --path . -- motif=3                         # one of them
godot --path . -- no-motifs                       # without them
```

The feature `motifs` is on by default and does nothing unless those files are there: `build/` is ignored by git and left out of every export. Each motif plays once, then a rest of 4 to 8 seconds, then 25 to 35 seconds of the place's tune, and the log prints `music: motif N of 5` as each one starts. A fight or a sting takes it off. Still open for the team: which sections to keep, where they fit, and from Abdulla the source, the soundfont and its license. Whatever stays goes through `tools/music/`, `assets/CREDITS.txt` and `tools/audio_test.gd`, and this section goes away.

## Sound effects

Effects are synthesised at 44.1 kHz from recipes in `src/audio/sfx.gd` on the synth in `src/audio/synth.gd`, and rendered once when the game starts, spread over frames. The Master bus has a compressor and a limiter, and effects send to a room reverb (`src/audio/mix.gd`). `nosfx` silences effects and voices.

## Voices

Monsters speak their lines through `src/audio/voices.gd`. A line with a recording in `assets/voices/cosyvoice3/` plays it, and the music ducks under it. A line with no recording uses the synth voice for its species (`src/audio/shout.gd`), lower and louder for the champion. A stage direction stays silent.

The lines are rendered by `tools/voices/render.py`; see the README beside it.
