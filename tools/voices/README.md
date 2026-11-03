# Voice banks

Every line a monster can say, spoken ahead of time in that monster's voice: `assets/voices/<bank>/` (Ogg files and a
`manifest.json`, read by `src/audio/tts_engines.gd`'s `Bank`). One bank per model, so the playtest can compare them
with **L**:

| Bank | Model | Licence |
| --- | --- | --- |
| `cosyvoice3` | [Fun-CosyVoice3-0.5B-2512](https://huggingface.co/FunAudioLLM/Fun-CosyVoice3-0.5B-2512), the engine of the Feiyu voice stack | Apache 2.0 |
| `qwen3` | [Qwen3-TTS-12Hz-0.6B-Base](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base) | Apache 2.0 |

Each monster's voice is cloned (zero-shot) from a 4–6 s reference clip in `refs/`, all from
[LibriTTS-R](https://www.openslr.org/141/) under CC BY 4.0. `voices.json` says which clip is which monster, with its
exact transcript and attribution, and how each voice is shaped after rendering (semitones, tempo). The Feiyu voice
library is not used: its authorisation covers that project's own voice training only. Credits:
`assets/CREDITS.txt`.

## Samples

The same line from each bank, and the recording the voice was cloned from (on GitHub, a click opens the file):

| Monster | Reference voice (LibriTTS-R) | Line | | | |
| --- | --- | --- | --- | --- | --- |
| dragon | 7729 Tim Bower, −2 st | *Speak, little ones. You have my attention, briefly.* | [CosyVoice3](../../assets/voices/cosyvoice3/dragon/0ac6a445ee27.ogg) | [Qwen3-TTS](../../assets/voices/qwen3/dragon/0ac6a445ee27.ogg) | [reference](refs/dragon_7729.wav) |
| rock golem | 1188 Duncan Murrell, −3 st, slower | *too soon. stone does not move quickly.* | [CosyVoice3](../../assets/voices/cosyvoice3/rock/a57c46af8d50.ogg) | [Qwen3-TTS](../../assets/voices/qwen3/rock/a57c46af8d50.ogg) | [reference](refs/golem_1188.wav) |
| goblin | 260 Brad Bush, −1 st | *Gold. Give Tringus gold, maybe Tringus no smash.* | [CosyVoice3](../../assets/voices/cosyvoice3/goblin/c1c34f9b1b74.ogg) | [Qwen3-TTS](../../assets/voices/qwen3/goblin/c1c34f9b1b74.ogg) | [reference](refs/goblin_260.wav) |
| bandit | 4077 Nathan Markham | *Your purse or your life. Or, we chat. Your call.* | [CosyVoice3](../../assets/voices/cosyvoice3/bandit/9e14e15d8515.ogg) | [Qwen3-TTS](../../assets/voices/qwen3/bandit/9e14e15d8515.ogg) | [reference](refs/bandit_4077.wav) |
| snake | 8463 Michele Fry (breathy), slower | *You broke our deal. Now I break you.* | [CosyVoice3](../../assets/voices/cosyvoice3/snake/faa360ecf482.ogg) | [Qwen3-TTS](../../assets/voices/qwen3/snake/faa360ecf482.ogg) | [reference](refs/snake_8463.wav) |
| slime | 5683 Rachael Lapidis, +3 st, faster | *promise was lie. Squish go now.* | [CosyVoice3](../../assets/voices/cosyvoice3/slime/349128e37aba.ogg) | [Qwen3-TTS](../../assets/voices/qwen3/slime/349128e37aba.ogg) | [reference](refs/slime_5683.wav) |

What the game's speech recognizer heard back from every line (`check.py`):

| Bank | Words heard back | Lines word for word | dragon | rock | bandit | goblin | slime | snake |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cosyvoice3` | 88% | 167 / 322 | 98% | 91% | 89% | 82% | 80% | 78% |
| `qwen3` | 89% | 171 / 322 | 96% | 93% | 88% | 83% | 85% | 78% |

## Rendering

```bash
godot --headless --path . -s res://cli/voice_lines.gd -- --out=build/voice-lines.json   # the 322 lines (render.py does it if missing)
python3 tools/voices/render.py qwen3 --python <qwen venv>/bin/python --model <Qwen3-TTS-12Hz-0.6B-Base>
python3 tools/voices/render.py cosyvoice3 --python <cosy venv>/bin/python --model <Fun-CosyVoice3-0.5B-2512> --src <CosyVoice checkout>
godot --headless --path . --import                                                       # before running the game
python3 tools/voices/check.py qwen3                                                      # hear it back (below)
```

`render.py` renders what's missing (`build/voices/<bank>/raw/` keeps the raw takes; `--force` redoes them,
`--only slime`, `--limit 2` to try things), renders again any take far too short or too long for its words (a
clipped grunt, a runaway) with the next seeds, then trims, shapes, loudness-normalises (EBU R128, -18 LUFS) and
encodes each line to mono Ogg Vorbis, and writes the manifest. ffmpeg (with libvorbis; rubberband if it has it) does
the audio.

The engines run in their own Python environments (Python 3.11), which `render.py` calls with `--python`:

- **Qwen3-TTS**: `pip install torch --index-url https://download.pytorch.org/whl/cpu && pip install qwen-tts`.
- **CosyVoice3**: a checkout of [FunAudioLLM/CosyVoice](https://github.com/FunAudioLLM/CosyVoice) with its
  `third_party/Matcha-TTS` submodule (`--src`), and `pip install -r tools/voices/engines/requirements-cosyvoice3-cpu.txt`
  (CPU wheels: `--extra-index-url https://download.pytorch.org/whl/cpu`). Its English text normaliser (wetext) needs
  ModelScope; without it the model's own English handling runs. All-caps words are lower-cased first (it spells them
  out otherwise).

A GPU isn't needed. On 4 CPU threads both run about 6–8 times slower than real time (CosyVoice3 8.3 GB of memory,
Qwen3-TTS 5.8 GB), so a whole bank takes one to two hours; run one engine at a time. With a running Feiyu or Qwen3-TTS
service, `--service feiyu|qwen --url ...` renders through it instead (with the service's own voices).

## Checking

`check.py <bank>` plays every line of a bank into the game's own speech recognizer (`native/asr`, built with
`native/asr/build.sh`) and compares what it hears with what was meant: the share of words heard back, line by line,
and the lines it understood least. Made-up words ("blorp", "hur hur", "sssuch") come back differently by design; real
words should come back.
