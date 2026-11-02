# Music and voices

How the music was made and how the monsters speak. Code layout: [ARCHITECTURE.md](ARCHITECTURE.md#audio).

## Music

The music follows the moment (`src/audio/ambient.gd`). **P** turns it on and off.

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

## Voices

The monsters' voices are engines behind one interface (`src/audio/tts_engines.gd`); `src/audio/tts_config.gd` works out which ones this build has and their order, and **L** steps through them. `godot --path . --verbose` lists them at start and logs every line spoken, with the engine.

| Voice | `tts=` | What it needs |
| --- | --- | --- |
| A rendered bank | `cosyvoice3`, `qwen3` | `assets/voices/<bank>/manifest.json` and its Ogg files (see below) |
| Feiyu service | `feiyu` | a running Feiyu voice service (CosyVoice3 behind a FastAPI job queue) and a voice of our own on it |
| Qwen3-TTS service | `qwen` | a running Qwen3-TTS service |
| Your system's | `system` | a speech engine on the system (or the browser's) |

**The services** synthesise each line as it's said, so they speak any line, not just the fixed ones, but each line takes a second or more (CosyVoice3 needs an NVIDIA GPU; on a shared laptop GPU it ran at about twice real time). Configure them in `config/tts_config.json` (it ships with an export, like `jev_config.json`), or, running from source, in `.env`:

```json
{
  "engines": ["feiyu", "system"],
  "feiyu": {"url": "http://gpu-box:8000", "key": "...", "voice": "<voice package>", "style": "gentle",
            "voices": {"dragon": {"voice": "<another>", "style": "cute"}}},
  "qwen": {"url": "http://mac:8001", "language": "en", "voices": {"slime": {"speaker": "Aiden"}}}
}
```

```bash
FEIYU_TTS_URL=http://gpu-box:8000
FEIYU_TTS_KEY=...
FEIYU_TTS_VOICE=<voice package>
QWEN_TTS_URL=http://mac:8001
```

- **Feiyu**: `POST /v1/speech` with `{voice, style, text}` (plus whatever `voices.<species>` adds for that monster) and `Authorization: Bearer <key>`, then `GET /v1/jobs/<id>` until it succeeds, then `GET /v1/jobs/<id>/audio` (WAV). The game only offers it once a `voice` is named: the service's default voice is the Feiyu voice library, whose licence covers that project's own voice training only, so it may not be used here. Use a voice made from Creative Commons recordings.
- **Qwen3-TTS**: `POST /synthesize` with `{text, language, speaker}` (and anything `voices.<species>` adds), answered with the WAV. Without a `voices` entry a monster gets one of the CustomVoice model's English speakers (`QWEN_SPEAKERS` in `tts_config.gd`).
- A service that fails (unreachable, an error, no WAV) steps aside for 30 seconds, and the next voice speaks meanwhile. The last 64 lines synthesised are kept, so a line heard again plays at once.

**A rendered bank** is a folder `assets/voices/<bank>/` with Ogg files and a `manifest.json`: `{"id", "label", "lines": {"<species>": {"<words>": "<file>.ogg"}}}`, where `<words>` is what's said, lower-case with single spaces (`Tts.line_key`: no stage directions). `cli/voice_lines.gd` lists every line to render: 322, with `{name}` filled with each of the monster's own names; the 6 that name their `{target}` can't be rendered ahead. The game has two, `cosyvoice3` and `qwen3`, each monster cloned from the same Creative Commons recording in both, so **L** compares the models on equal terms. `tools/voices/render.py` makes a bank (on a CPU, an hour or two), `tools/voices/check.py` plays it back into the game's speech recognizer to check every line is understood, and `tests/audio/test_voice_banks.gd` checks every line is there; see [tools/voices/README.md](../tools/voices/README.md). Import new files (`godot --headless --path . --import`) before running the game.
