# Architecture

How the Godot code is put together, for someone about to change it. What the game is and how to run it: [README.md](../README.md).

Donjon was a browser game (`crawler/` in git history, last at `12d2be7`) and was rewritten in GDScript on Godot 4.7. Many comments say "the JS" or name `game.js`: that is the browser version, `git show 12d2be7:crawler/public/game.js`. The port kept every player-facing string, balance number and Jev question byte for byte, because Jev's answers depend on the wording.

## Layout

| Folder | What lives there |
| --- | --- |
| `src/core/` | Shared helpers: `js.gd` (JavaScript semantics), `flags.gd` (run flags), `store.gd` (saved data, the `Store` autoload) |
| `src/rules/` | Pure rules and data, no nodes: `dnd.gd` (classes, spells, monster stats, dice), `species.gd` (the six monsters: stats, tastes, approved lines), `emotions.gd`, `status.gd`, `narrate.gd` (log text), `juice.gd` (fx event bus, shake, hit-stop, danger), `dice.gd` (the tumbling d20), `tutorial.gd` (tips), `achievements.gd`, `tooltip.gd`, `inspector.gd` (REQUESTS-tab JSON) |
| `src/game/` | `game.gd`, the run: state `G`, exploring, combat, talking, vows, boons, every Jev request. `floors.gd`: floor rules and the maze generator |
| `src/jev/` | Everything that asks Jev: `config.gd`, `jev.gd`, `api.gd`, `enemy.gd`, `allies.gd`, `bonds.gd`, `q.gd`, `util.gd`, `mock_jev.gd` |
| `src/view/` | The 448×288 picture: `canvas2d.gd`, `render.gd` (corridor, automap, title), `art.gd` (monsters), `postfx.gd` + two `.gdshader` files |
| `src/audio/` | `synth.gd` (offline DSP), `sfx.gd`, `shout.gd` (line to monster voice), `mix.gd` (buses), `ambient.gd` (music), `tts.gd` + `tts_engines.gd` + `tts_config.gd` (monsters reading aloud), `voice.gd` + `asr.gd` (hold to talk) |
| `src/ui/` | `main.tscn` + `main.gd` (the screen) and its panels, models and helpers |
| `src/genre/` | Genre Halls: `genre_rules.gd` (rules, no UI) and `genre_halls.gd` + `.tscn` (its own scene) |
| `assets/` | `audio/*.ogg` (the music), `voices/<bank>/` (monster lines rendered ahead, with a `manifest.json`), `fonts/` (Press Start 2P, VT323), `CREDITS.txt` |
| `tests/` | Mirrors `src/`, plus `run_tests.gd` and `test_case.gd` |
| `cli/` | Scenario runners and screenshot/sound dump scripts (see the README) |
| `tools/` | `build.sh`, `check-html5.mjs`, `music/` (offline music renders), `voices/` (voice bank renders, their checker and the Creative Commons reference clips), `godot-mcp/` (the Godot MCP server `.mcp.json` and `.codex/config.toml` start). Godot ignores it (`.gdignore`) |
| `native/` | `asr/`: the speech-recognition helper's C source, `build.sh`, `smoke.py` and the licences it ships with (Godot ignores it). `dist/<platform>/`: what `build.sh` builds, not committed; each desktop export carries its own |
| `proxy/` | The Cloudflare Worker that holds the Jev key and forwards the game's requests (JavaScript, its own `package.json` and tests; `.gdignore`) |
| `.github/` | CI: `workflows/ci.yml` (tests, builds, releases), `workflows/worker.yml` (the Worker), `actions/setup-godot` |
| `web/shell.html` | The web export's page |
| `docs/` | This file and the cover image (`.gdignore`) |

`.uid` and `.import` files are committed beside their scripts and assets. After adding files or assets, run `godot --headless --path . --import`. `project.godot` has one autoload (`Store`), the 1180×820 base window (stretch `canvas_items`, aspect `expand`) and the `gl_compatibility` renderer, which the web export needs.

## Modules and data

- **No `class_name`.** A module is a script of `static func`s and constants. Use it through a `preload` constant named after the file in PascalCase: `const Species = preload("res://src/rules/species.gd")`, `const J = preload("res://src/core/js.gd")`, `const JevApi = preload("res://src/jev/api.gd")`. Several modules contain inner classes (`Sfx.Sfx`, `Mix.Mixer`, `Juice.Bus`, `J.Waiter`).
- **Data is JSON-shaped.** Monsters, party members, the map, the combat, the prompt: `Dictionary` and `Array` with camelCase string keys (`maxHp`, `clsId`, `friendliness`, `playerAction`). Those keys go into Jev's `state`, into `user://store.json` and into the golden test fixtures, so they stay as they are. Sets are `{key: true}` dictionaries. Everything else (functions, variables, files) is snake_case.
- **`const` tables are read-only** (species, spells, emotions). `.duplicate(true)` before changing a copy; module-level mutable state is a `static var`.
- **Errors are values.** Where the browser version threw, a function returns `{"error": "message"}` (plus `"status"` for HTTP-like failures) and the caller checks `has("error")`. `JevApi.handle` returns `{"status": int, "body": Dictionary}`.
- **Options** are a trailing `opts := {}` read with `opts.get("a", default)`, or one Dictionary with the same keys the JS object had. Callbacks in them are `Callable`s.
- **Logging.** `print` for moments worth seeing on every run (new run, start, a vow, a boon), `print_verbose` for detail (visible with `godot --verbose`: the Jev provider, API timing, audio start), `push_warning` and `push_error` for trouble. Add a log line when you add behaviour you may have to debug.

## The game and the screen

`src/game/game.gd` (a `Node`) owns the rules and the flow. `src/ui/main.gd` (the `Control` that `main.tscn` instantiates) owns everything that draws or listens. They meet at three places only.

**State.** `game.G` is one Dictionary for the run: `G.mode`, `G.floor`, `G.party`, `G.map`, `G.combat`, `G.log`, and the things the game is waiting on: `G.prompt` (yes/no), `G.menu`, `G.input` (the talk box), `G.waitKey`, `G.roll` (the Roll of Fate), `G.busy`. Each waiting object holds a `J.Waiter`; `ask()`, `choose()`, `ask_text()` and `wait_key()` in `game.gd` set `G.*`, call `ui.render()` and `await` the waiter, and `game.key(k)` resolves it. The ui only reads `G`, never writes game rules into it.

**Keys.** The ui turns input into the browser's key strings (`src/ui/keys.gd`: `"arrowup"`, `"enter"`, `"escape"`, `" "`, `"a"`), maps movement keys through `Game.KEYMAP` and calls `game.key(k)`. Every dock, top-bar and modal button calls `ui.press_key(k)`, which ends in the same `game.key`. `key()` is a long if-chain by mode: achievements list open, then waitKey, game over, prompt, menu, talk box, busy, then the global switches, then combat or exploring commands.

**Hooks.** `main.gd` creates the game node and the sound (`Ambient.Ambient`, `Sfx.Sfx`, `Tts.Narrator`, `Voice.Listener`), tips and achievements, and sets `game.ui`, `game.music`, `game.sfx`, `game.narrator`, `game.voice`, `game.tips` and `game.ach` before `start()`. The game calls back through `ui.render()`, `ui.render_bar()`, `ui.render_dock()`, `ui.nudge_dock()`, `ui.nudge_modal()`, `ui.show_jev(x)`, `ui.render_requests()`, `ui.toggle_jev()`, `ui.toggle_map()`, `ui.open_input(label, numeric)`, `ui.close_input()`, `ui.input_text()`, `ui.focus_input()`, `ui.start_audio()` and a few more; `tests/game/helpers.gd` has a stub ui with all of them, which is the list to keep in sync. The game never touches a widget.

**Events.** Combat moments go the other way over `game.fx`, a typed bus (`Juice.create_bus()`, events and required fields in `Juice.FX_EVENTS`; `emit` reports an unknown event or a missing field, so a typo can't silently drop an effect). `main.gd` subscribes: shake and hit-stop, shader flashes and hurt pulses, `Mixer.impact` dips, and the step/turn/bump easing.

**The screen.** `main.gd` builds it all in code. Panels extend `src/ui/widget.gd`, which paints itself in `_draw()` with the helpers in `src/ui/css.gd` (the old stylesheet as colors, keycaps, glows, pixel icons) and registers hit regions (`add_hit`) for hover, clicks, the dock's hint line and the pixel tooltips. Pure models turn `G` into data a widget paints: `dock_model.gd`, `party_model.gd`, `layout.gd` (where every part goes for a window size), `keys.gd`. Those four are tested without a window. The 448×288 picture is `view_canvas.gd` drawing into a `SubViewport`; a `TextureRect` shows it through the post-processing shader. `jev_panel.gd` is the debug panel; `tip_box.gd`, `toasts.gd`, `ach_screen.gd` and `modal.gd` are the overlays.

## Jev

`JevApi.handle(path, body, opts)` (`api.gd`) is what the browser used to POST to its server, now answered in-process. It sanitises the request (player text stays short before it reaches the model), routes by path (`/api/group-turn`, `/api/ally-reactions`, `/api/ally-talk`, `/api/vow`, `/api/vow-broken`, `/api/enemy-turn`) and returns `{status, body}`. With `opts.debug` the body carries `_debug: {jev: [...]}`, every raw Jev call behind the request; `game.api()` keeps those in `api_log` for the REQUESTS tab.

Below it: `enemy.gd` (a round for 1 to 3 monsters), `allies.gd` (the after-fight judgement) and `bonds.gd` (ally talk, vows) build the questions with `q.gd` (`Q.noul`, `Q.choice`, `Q.score`), call `Jev.jev(state, questions, trace)`, and fold the answers into numbers, choices and lines. The split to keep: Jev reads and picks; code owns the rules, the odds and what is allowed.

`jev.gd` sends one request and retries 429/529. A **transport** (anything with `fetch(url, headers, body)`) can replace the real `HTTPRequest`; that is how the mock and the tests plug in. `config.gd` decides once which provider to configure (mock, `config/jev_config.json`, the project's `.env`, or nothing): see the README's "Setting up Jev". `mock_jev.gd` answers every question with a seeded, well-formed random answer (its `mulberry32` is bit-exact with the browser's).

## View

- **`canvas2d.gd`** is a Canvas 2D context over a `CanvasItem`'s `draw_*` calls, so the drawing code ported line for line: `ctx.begin_path()`, `ctx.line_to(x, y)`, `ctx.fill_style = "#e8e8e8"`, `ctx.create_radial_gradient(...)`. Make one inside a `_draw()` (`draw_*` only works there): `Canvas2D.new(self, Vector2(448, 288))`. Styles take CSS color strings. The header lists the approximations (holes in fills, radial gradients as textures, `shadow_blur` as a soft second pass, no `line_join`).
- **`render.gd`** draws the wireframe corridor (a true 1/z perspective, painted far to near, six cells deep), the automap and the title. What you can see from a cell is computed once per cell and cached. **`art.gd`** draws the monsters, one function per species, with the shiny and champion looks.
- **`postfx.gd`** is the last pass. The view's `SubViewport` is shown by a `TextureRect` carrying a `ShaderMaterial` (`postfx.gdshader`: glow, scanlines, edges, accent tint, danger pulse, hurt split) and a small second viewport for the bloom (`postfx_bloom.gdshader`). `PostFx.create(...)` returns null with the `nofx` flag; otherwise `attach(rect)` once, then `set_danger`, `set_accent` and `render(now)` each frame, and `hurt`, `flash` and `beat` from events.

## Audio

Nothing is a sound file except the music and the monster lines rendered ahead (`assets/voices/`).

- **Effects.** `sfx.gd` holds recipes (`snd_hit`, `snd_levelup`...) made of tones, filtered noise and a formant voice, built on `synth.gd` (oscillators, WebAudio-compatible biquad filters, envelopes, rendered offline into sample buffers). A recipe is rendered once into an `AudioStreamWAV` and cached, a few milliseconds per frame in the background (`PREWARM`), and each play picks the cached stream and sets pitch and volume (`VARY`, `POLY`). `shout.gd` classifies a monster's line (a roar, a squelch, a hiss...) into a plan the voice recipes play.
- **Buses.** `Mix.Mixer` builds the audio buses at runtime: music (`MusicIn` then `Music`, with the danger low-pass and impact dips), effects (`SFX`) with a reverb send (`SFXRoom`), all into `Master` with a limiter. `Mix.BeatScheduler` lands the heartbeat on the music's beat. The mixer is made on the first key press (browsers keep audio locked until then), and `sfx.init(mixer)` and `music.attach(mixer)` plug the players in.
- **Music.** `Ambient.Ambient` plays seamless `.ogg` loops from `assets/audio/` (one for exploring, four for fights) and two stings, switching by mood. They are rendered offline by the scripts in `tools/music/`; the loop lengths in `TRACKS` must match the files (a test checks).
- **Monsters speaking.** `tts.gd`'s `Narrator` decides when a line is said (off until the player talks or presses L, a backlog dropped, the music and effects ducked) and hands an `Utterance` (words, species, callbacks) to an engine. Engines share one interface: `get_voices()`, `speak(u)`, `cancel()` and, when they may not have a line, `can_say(u)`. `tts_engines.gd` has them: `Bank` (lines rendered ahead into `assets/voices/<id>/`, looked up by species and `Tts.line_key`), `Feiyu` and `Qwen` (HTTP services, through an injectable `fetch`; a failure takes one out of the chain for 30 s), `Chain` (the first engine that can say it does) and `Player` (plays banked and synthesised lines in the order they were asked for). `DisplayServerSynth` in `tts.gd` is the system's engine. `tts_config.gd` works out which engines exist (banks on disk, services in `config/tts_config.json` or `.env`, the system's) and their order; L steps through them.
- **Hold to talk.** `voice.gd`'s `Listener` runs one listening session against anything shaped like the browser's `SpeechRecognition` (`start()`, `stop()`, `abort()`, `onresult`, `onerror`, `onend`). The web build gives it the Web Speech API through `JavaScriptBridge`. The desktop builds give it `asr.gd`'s `NativeRecognition`: `Runtime` (one, under the root) captures the microphone (`AudioStreamMicrophone` into a muted `Mic` bus with an `AudioEffectCapture`), runs `native/asr`'s helper as a child process (`OS.execute_with_pipe`, non-blocking) and streams the audio to it as frames on stdin; the helper answers with JSON lines. It also downloads the speech model when the player asks (`prepare()`), checks it, and copies the helper out of the `.pck` in an exported build. Without either, `supported` is false and the ui hides the mic.

## Core helpers

`src/core/js.gd` (`const J = preload(...)`) exists because the game was ported from JavaScript and its numbers and text must come out the same. It holds the few JavaScript behaviours GDScript does differently: `J.round_js` (`Math.round` rounds halves up), `J.num` (`3.0` prints as `3`), `J.truthy`, `J.nz` (`??`), `J.rnd` and `J.pick`, `J.now_ms` and `J.date_ms`, `J.sleep` (`await J.sleep(ms)`), and the two pieces of promise machinery: `J.Waiter` (a promise settled by hand) and `J.all` (`Promise.all` over callables). Use them instead of rewriting the idiom inline.

`flags.gd` gives `Flags.test(regex)` and `Flags.capture(regex)` over one string: the address (`location.search + location.hash`) on the web plus the command-line arguments after `--`. `Flags.override` lets tests pretend a different command line. `store.gd` is the saved data (`user://store.json`, the `Store` autoload) with a localStorage-shaped API (`get_item`, `set_item`, `remove_item`, string values); `Store.Memory` is the same without a file, for tests.

## Genre Halls

A separate scene (`genre_halls.tscn`, one `Control` with `genre_halls.gd`) that reuses `Render`, `Art`, `Species`, `Emotions`, `Sfx` and `PostFx` but not `game.gd`. `genre_rules.gd` has the factions, the floor, the monster's local "mind", word reading and the box geometry, with no UI. `genre_halls.gd` draws and runs the fight on a clock: `tick(t)` advances it to time `t` (`_process` feeds it the real clock; tests set `clock_override` and call `on_key(key)`).

## Testing

```bash
godot --headless --path . -s res://tests/run_tests.gd -- --only=<substring of the path>
```

- **Runner.** `tests/run_tests.gd` is a `SceneTree` script. It loads every `tests/**/test_*.gd`, runs each `test_*` method in a fresh instance (`before_each` and `after_each` may `await`), and exits 1 on any failure or if nothing ran. Test files extend `tests/test_case.gd`, which has `ok`, `eq` (deep equality where `3 == 3.0`), `ne`, `near`, `match_re` and `fail`.
- **The Logger.** The runner registers a `Logger` (`OS.add_logger`) that records every engine and script error raised while a test runs (a bad index, a null access, `push_error`; warnings are ignored) and fails that test with the message. A GDScript error cannot pass a test silently.
- **Layout.** `tests/` mirrors `src/`. Files without a `test_` prefix are helpers: `tests/game/helpers.gd` wires a `Game` to stub ui, sfx and music objects that record their calls, real tips and achievements, an in-memory store and seeded mock Jev, with `sleep_scale = 0` so a fight plays in frames; `tests/ui/sample_g.gd` builds a hand-made `G`. `tests/ui/test_main.gd` instantiates the real `main.tscn` (`Flags.override = "mock"`, `Main.store_override`).
- **Seams.** Tests set `Flags.override`, pass `Store.Memory`, call `seed(n)`, give `JevConfig.resolve` injected sources (it never reads the real `.env` in a test), or replace Jev's transport; `game.api_handler` replaces `JevApi.handle`.
- **Golden fixtures.** `tests/jev/golden/*.json` hold requests and exactly what the JavaScript game sent to Jev for each (`{model, state, questions}`), and `results.json` holds what its rules made of scripted Jev answers, all recorded from the browser version before it was deleted. `test_golden.gd` replays each request through `JevApi.handle` into a `MockJev.Server`, which records what it was sent, and compares `state` and `questions` as JSON text, including the order of questions and options; `test_golden_results.gd` replays the decisions. Changing Jev's wording is a deliberate edit to a fixture in the same commit.
- **Real paths.** `test_http.gd` runs the real `HTTPRequest` against a throwaway server on 127.0.0.1. `test_playback.gd` plays through the real audio server (the dummy driver) and measures levels at the end of `Master`. `test_asr.gd` runs the real speech helper on a recording through `asr.gd` when `native/asr/build.sh` has built it and the model (CI does; elsewhere that test says it skipped). The helper's own test is `native/asr/smoke.py`. The Worker has its own: `node --test proxy/worker.test.js`.

## GDScript traps that still matter

- **Integer division.** `7 / 2` is `3`. Write `float(a) / b` whenever a fraction is meant; where truncation is meant, use `floori` or `@warning_ignore("integer_division")` (as `floors.gd` does).
- **JSON numbers are floats.** `JSON.parse_string` gives `7.0`, and `str(7.0)` is `"7.0"`: anything shown to the player or sent to Jev goes through `J.num`, `U.norm` (`src/jev/util.gd`) or `int()`. A float `1.0` and an int `1` are different Dictionary keys, so `int()` before using a number as one.
- **Missing keys.** `d.key` on a Dictionary with no such key is an error (in JS it was `undefined`). Use `d.get("key", default)` for anything optional, and initialise every field the code later reads with `.`.
- **Empty is falsy.** `[]` and `{}` were truthy in JS and are falsy in GDScript. Write `if x != null`, `not arr.is_empty()` or `J.truthy(x)`.
- **Lambdas capture by value.** A lambda can't `count += 1` on an outer local; use an Array or Dictionary cell (`var left := [n]`, as `J.all` does).
- **Variants don't infer.** `:=` fails on an untyped Array element or a Dictionary value; write `var x = ...` or `var x: T = ...`.
- **Coroutines.** A function that contains `await` is a coroutine for every caller; callers must `await` it to get its result, and one that doesn't just starts it and moves on.
- **Sorting.** `sort_custom` takes a "comes before" bool, not a number, and isn't stable: add an index tie-break where order matters.
- **Rounding and `%`.** `round()` differs from `Math.round` on halves (`J.round_js`); `%` takes only ints (`fmod`, `fposmod` for floats).
- **Engine errors fail tests.** Any `push_error` or script error during a test is a failure, so a noisy log line you add in an error path will break the test that walks it.
