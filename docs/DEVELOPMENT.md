# Development

Setting up Jev, run flags, building, CI, tests and debug tools. The game itself: [GAME.md](GAME.md); code layout: [ARCHITECTURE.md](ARCHITECTURE.md).

## Setting up Jev

The game talks to Jev itself: there is no server between them. `src/jev/config.gd` decides how, once, when the first request goes out, taking the first of these that applies:

1. **Mock**: the `mock` flag (or `JEV_MOCK=1` in the environment). `seed=N` (or `JEV_SEED`) makes the mock's random answers repeat. Nothing else is read.
2. **`config/jev_config.json`**: what an exported build ships. `{"provider": "openrouter" | "typesafe" | "proxy", "key": "...", "apiBase": "...", "debug": true}`. Leave `provider` out and it is `proxy` when only `apiBase` is set, `openrouter` for a key starting `sk-or-`, otherwise `typesafe`. `debug: true` turns debug mode on. The file is git-ignored.
3. **The project's `.env`**, when run from source (the editor build of Godot; an exported build never reads it): `OPENROUTER_API_KEY` is preferred, else `TYPESAFE_API_KEY`. Copy `.env.example` to `.env`; get a TypeSafe key at https://console.typesafe.ai/keys. The `.env` is git-ignored.
4. **Nothing found**: mock Jev, and a warning line in the log (*NO JEV KEY FOUND ... MONSTERS ACT AT RANDOM*). Asking for the mock with the flag prints no warning.

API keys come from those two files only, never from OS environment variables (only `JEV_MOCK` and `JEV_SEED` are read from there).

| Provider | Where the request goes | Needs |
| --- | --- | --- |
| `typesafe` | `POST https://api.typesafe.ai/v1/systemone`, model `jev-latest` | a TypeSafe key |
| `openrouter` | `POST https://openrouter.ai/api/alpha/decisions`, model `~typesafe/jev-latest` (OpenRouter serves TypeSafe's Jev, same questions and answers, and allows calls from web pages) | an OpenRouter key |
| `proxy` | `POST <apiBase>/api/jev` with `{state, questions}` and no key; the Worker in `proxy/` holds the key and picks the model | the Worker's URL |
| `mock` | answered in the game (`src/jev/mock_jev.gd`) | nothing |

A request that gets 429 or 529 is retried up to three times with a growing wait (400, 800, 1600 ms); one that takes more than 10 s is dropped. When Jev can't be reached the log says *(JEV UNREACHABLE: ...)* and the monsters hesitate.

The mock (`src/jev/mock_jev.gd`) answers every Jev question with a random but well-formed answer of the right type, seeded so a run repeats, with 150 ms of fake latency per request so the game's waiting states still show. It exercises the plumbing and the game's rules, not Jev's judgement: use a real key when you want to see what Jev actually decides.

**Keys in builds.** A key inside an exported build can be read by anyone who opens the files. The builds CI makes, and so the releases, carry none: they use the `proxy` provider and reach Jev through the Worker below. If you build with `--openrouter` yourself, use an OpenRouter key with a small credit limit (set it at openrouter.ai/settings/keys) and rotate it if it's abused. Keys are never committed: they live in `.env` locally and on the Worker.

**The Worker** (`proxy/worker.js`, the Cloudflare Worker `donjon-api`) holds the key so no build has to. It takes the game's `{state, questions}`, adds its key, pins the model, forwards the request and returns Jev's status and body untouched, so the game still sees the 429s it backs off on. The rules (what to ask, what the answers mean) all run inside the game; the Worker forwards only what the game asks:

- `POST /api/jev` and nothing else; a body of at most 64 KB with 1 to 120 questions of the kinds the game uses (`noul`, `choice`, `score`). Anything else gets a 400, 404 or 413.
- It fails closed: with no key configured it answers 503 to everything, preflights included.
- At most 60 requests per IP per minute (a Cloudflare rate-limit binding in `wrangler.jsonc`; over it, a 429 with `retry-after`). A player makes a few per round.
- It can reach only `api.typesafe.ai` and `openrouter.ai`, over https. When Jev doesn't answer, it returns 502. Any web page may call it.
- It uses `OPENROUTER_API_KEY` if set, else `TYPESAFE_API_KEY`.

Nothing asks a player for a password, so anyone who plays (or finds the address) can reach the Worker; the rate limit and the credit limit on the key are what protect your credits.

CI's builds point at `https://donjon-api.lishuyustevenli.workers.dev` (`JEV_API` in `ci.yml`). `.github/workflows/worker.yml` tests the Worker and deploys it from `main` whenever `proxy/`, `src/jev/jev.gd` or the Worker's fixture changes; pull requests only test it and bundle it, with no credentials. The deploy needs `CLOUDFLARE_API_TOKEN` (Workers Editor on this one Worker) and `CLOUDFLARE_ACCOUNT_ID` in the `cloudflare-production` environment. The Jev key never passes through GitHub: set it on the Worker by hand. After a deploy, a smoke test posts a request with no questions (no Jev call, no credits): 400 means the Worker is up with its key, 503 that it has none yet.

To run your own:

```bash
cd proxy
npm ci --ignore-scripts                      # installs wrangler
npx wrangler login                           # opens your browser to sign in to Cloudflare
npx wrangler secret put OPENROUTER_API_KEY   # or TYPESAFE_API_KEY
npx wrangler deploy                          # prints https://donjon-api.<you>.workers.dev
cd ..
tools/build.sh --proxy https://donjon-api.<you>.workers.dev
```

The rate limit's `namespace_id` in `proxy/wrangler.jsonc` has to be unique on the Cloudflare account; `proxy/worker.test.js` keeps that file to one workers.dev Worker with no routes, builds or extra bindings. To test locally, `node proxy/dev.js` runs the same handler on port 5175 (it reads `.env`, and has no rate limit): `tools/build.sh --proxy http://localhost:5175 web`. To take the game offline, delete the secret (`npx wrangler secret delete OPENROUTER_API_KEY`: the Worker then answers 503 and the game reports *JEV UNREACHABLE*) or the Worker in the Cloudflare dashboard.

## Run flags

Flags change one run. From source they go after `--`; on the web build they come from the address (`index.html?mock&nofx`, `index.html#floor5-debug`). They are matched anywhere in the text, ignoring case, so `debug`, `--debug` and `floor5-debug` all work.

```bash
godot --path . -- main mock debug    # the original Donjon: mock Jev, debug mode
godot --path . -- main floor5-debug  # the original Donjon: start on floor 5, debug mode
godot --path . -- meet=rock          # Genre Halls, straight into a rock fight
```

| Flag | Does |
| --- | --- |
| `mock` | Jev is mocked (see [Setting up Jev](#setting-up-jev)) |
| `seed=N` | seeds the mock's answers, so a run repeats |
| `debug` | [debug mode](#debug-mode-developers-only) |
| `nodebug` | debug mode off for this run, even in a build that ships with it on |
| `floorN` | a **test run**: start on floor N (clamped to 2 to 30) with a party that got there, every member at level N, one Roll of Fate boon per floor cleared, some gold, fully rested |
| `nofx` | no shader: the plain view |
| `tts=<voice>` | start with that voice: `cosyvoice3`, `qwen3`, `feiyu`, `qwen` or `system` (see [Voices](AUDIO.md#voices)) |
| `main` | open the original Donjon instead of [Genre Halls](GAME.md#genre-halls-undertale-style-battles), which is where the game starts. Combine it with the others: `-- main mock floor5` (on the web, `index.html?main&mock`) |
| `genre-halls` | from the original Donjon (`res://src/ui/main.tscn`), jump to Genre Halls |
| `meet=<species>` | in Genre Halls, jump into that faction's fight: `slime`, `bandit`, `snake`, `rock` or `dragon` |
| `personality-slice` | play the seeded two-bandit [personality test](PERSONALITY_PLAYTEST.md); use `seed=7042 nosound` for its checked routes |
| `flat` | Genre Halls walks in the old 2D corridor instead of the 3D set |
| `nosound` or `nosfx` | Genre Halls without sound |
| `nosave` | Genre Halls doesn't write its autosave |
| `pad` | Genre Halls with its on-screen arrow pad (always on a touch screen) |

`godot --path . --verbose` prints the game's debug logging (flag choice, Jev provider, API timing, audio start, boon draws, the voices found and each line spoken, the speech helper's own log).

Floors are new mazes every time you descend. Death is permanent, and your deepest floor is remembered.

## Platform differences

The same project runs everywhere; these parts depend on where.

- **Voices.** The rendered banks play the same everywhere, the web included. The system's voice is `DisplayServer.tts_*`: the macOS, Windows and Linux speech engines, or the browser's `speechSynthesis` on the web, which differ from machine to machine (the game picks an English one, preferring local voices). A live service is reached over your network from any build that has it configured.
- **Hold-Space speech recognition** runs on your machine in the Windows (x86_64), macOS (universal) and Linux (x86_64) builds, with the downloaded model; in the web build it's the browser's (Chrome, Edge, Safari). Elsewhere (Firefox, another processor, a build made without the helper) the HOLD TO SPEAK button stays hidden and Space is an ordinary key.
- **Saved data** (achievements, tips seen and off, the voices choice, the Jev panel's state, your deepest floor) is one JSON file, `user://store.json` (`src/core/store.gd`): `~/Library/Application Support/donjon/` on macOS, `%APPDATA%\donjon\` on Windows, `~/.local/share/donjon/` on Linux, and the browser's IndexedDB for the site on the web. Delete the file to start fresh. Setting `donjon.debug` to `"1"` in it turns debug mode on for every run. The speech model and helper live beside it in `asr/`; delete that folder to get the 662 MB back.
- **Reduced motion**: the web build asks the browser (`prefers-reduced-motion`); desktop builds don't query the system and always run with motion on.
- **Flags** come from the address on the web and from the command line elsewhere (start an exported desktop build from a terminal with `-- mock` and the like).
- **The Jev panel and `window.halls`.** The Jev mind panel and its REQUESTS tab work everywhere in debug mode. The `halls` console hooks (`halls.meet("goblin", "slime")`, `halls.hostile("slime")`, `halls.ally("slime", "Glop")`, `halls.lesson()`, `halls.boss()`, `halls.floor(5)`, `halls.xp(n)`, `halls.roll()`, `halls.shiny()`, `halls.descend()`, `halls.state()`) exist only in the web build, in a debug run.
- **Touch.** Every key on screen is a button you can tap. Typing into the talk box on a phone is untested: the web export leaves Godot's experimental virtual keyboard off.
- **macOS and Windows builds are unsigned** (macOS ad hoc, not notarized), so the system asks you to confirm the first launch. The Linux build is x86_64.

## Building and publishing

`tools/build.sh` exports the game into `build/<platform>/` and zips each one as `build/donjon-<version>-<platform>.zip`, with the version read from `config/version` in `project.godot`.

```bash
tools/build.sh                                 # web, windows, macos, linux; no key, so mock Jev
tools/build.sh web macos                       # only some
tools/build.sh --proxy https://donjon-api.<you>.workers.dev   # Jev via a Worker: nothing secret ships (what CI does)
OPENROUTER_API_KEY=sk-or-... tools/build.sh --openrouter      # Jev via OpenRouter, the key inside the build (public!)
```

It needs the `godot` binary on `PATH` (or `GODOT=/path/to/godot`) with the 4.7.2 export templates installed (Editor → Manage Export Templates). Each desktop build also carries its system's speech helper from `native/dist/<platform>/`, which `native/asr/build.sh <platform>` builds (`linux` and `windows` on Linux, `windows` cross-compiled with mingw-w64; `macos` on a Mac); `build.sh` warns when one is missing, and that build simply has no hold-to-talk. `--openrouter` and `--proxy` write `config/jev_config.json` for the export only and delete it afterwards; both set `debug: true`, so those builds start in debug mode with the Jev panel beside the game (a window or an embed of about 1180 × 820 fits both; the `nodebug` flag plays without it). The exports are the presets in `export_presets.cfg`: **Web** (single-threaded, so no special server headers), **Windows** (x86_64, one `.exe`), **macOS** (universal `.app`, zipped by Godot) and **Linux** (x86_64). Tests, `cli/` and `docs/` stay out of the exports (so do `proxy/` and `tools/`, which Godot ignores through `.gdignore`); the config file and `assets/CREDITS.txt` go in.

**The web build** uses its own page, `web/shell.html`: no engine logo and no loading screen, just a black page with a 2px line that fills while the files download (the project's boot splash is off too). If the browser can't run the game, or the page is opened as a file, it prints a plain message saying why. `node tools/check-html5.mjs build/web` (Node) checks the folder against itch.io's HTML5 limits (file count and sizes, `index.html` at the top, no symlinks) before a push.

**CI** (`.github/workflows/ci.yml`; Godot 4.7.2 is installed by `.github/actions/setup-godot`, Node 22 for the HTML5 check, and every action is pinned to a commit). It uses no secrets and can only read: the builds reach Jev through the Worker.

- First the **speech helper**: built for Linux and Windows on Linux and for macOS on a Mac, then run on a recording on each of the three systems (`native/asr/smoke.py`) against the speech model, which is the game's own pinned download, cached.
- Every push to `main` and every pull request runs the **tests**: the whole suite (with the Linux helper and the model, so the real recognizer is tested through the game's code), then every scripted encounter in `cli/scenarios.gd` and `cli/social_scenarios.gd` on mock Jev with two seeds.
- Then a **build** for web, Windows, macOS and Linux (`tools/build.sh --proxy "$JEV_API"`), each desktop one with its own helper, each kept as a workflow artifact for 14 days (`donjon-<platform>`, a zip, because an artifact folder loses the executable bits). The web one is validated with `check-html5.mjs`.

**Release** (`.github/workflows/release.yml`) is its own workflow, and a tag `vX.Y.Z` is its only trigger: `ci.yml` does not run on tags itself, so a tag tests and builds once. It fails at once unless the tag equals `config/version` in `project.godot` and `CHANGELOG.md` has a `## [X.Y.Z]` section. Then it calls `ci.yml` (the tests and the four builds) and, only if they pass, its last job (the only one with write access) publishes a GitHub release with those exact zips and that version's section of `CHANGELOG.md` as the notes. To release: bump `config/version`, add a `## [X.Y.Z] - date` section to `CHANGELOG.md`, tag `vX.Y.Z`, push the tag.

**Nothing publishes to itch.io**: the final ships native. To put the web build on itch.io by hand, make the page an **HTML** project, upload `build/donjon-<version>-web.zip` and tick "This file will be played in the browser" (or `butler push build/web <user>/<game>:html5`). The web build calls the Worker from the browser, which the Worker allows from any page. `assets/CREDITS.txt` ships in every build; put the same credits on the page.

## Tests

```bash
godot --headless --path . --import                                  # once, and after adding files
godot --headless --path . -s res://tests/run_tests.gd               # everything: about 500 tests, under a minute
godot --headless --path . -s res://tests/run_tests.gd -- --only=dnd # only files whose path contains "dnd"
```

The runner finds every `tests/**/test_*.gd`, runs each `test_*` method, and exits non-zero on a failure. A script error inside a test (a bad index, a null access) fails that test too. Tests run on mock Jev and need no key or network; one, in `tests/audio/test_asr.gd`, runs the real speech recognizer on a recording when `native/asr/build.sh linux` (or your system) and `native/asr/build.sh model` have been run, and says it skipped otherwise; [docs/ARCHITECTURE.md](ARCHITECTURE.md#testing) says how they are built. The Worker has its own: `node --test proxy/worker.test.js` (Node, nothing to install, the upstream is stubbed).

Scripts for looking at the game, in `cli/`:

| Script | Run | What it does |
| --- | --- | --- |
| `scenarios.gd` | `godot --headless --path . -s res://cli/scenarios.gd -- [filter] [--live] [--seed=N]` | scripted encounters, one monster at a time, then how its allies judge the fight |
| `social_scenarios.gd` | `godot --headless --path . -s res://cli/social_scenarios.gd -- [filter] [--live] [--seed=N]` | group fights, ally talk and vows |
| `shots.gd` | `godot --path . -s res://cli/shots.gd -- out=<dir>` | opens a window, plays the real screen on mock Jev, saves a screenshot of every state (title, exploring, a question, a fight, CHOOSE MOVES, the talk box, the Jev panel, the achievements list, the Roll of Fate, danger, game over, a tip, `nofx`, a small window) and fails on any script error |
| `stage_shots.gd` | `godot --path . -s res://cli/stage_shots.gd -- --out=<dir> [--only=<name>]` | the 3D view alone through the shader, at 2x: the title hall, corridors on four palettes, the stairs, the champion down a corridor, every monster in a fight (plus a shiny, a champion, a hurt one, groups of two and three, boxed in by walls), danger |
| `view_shots.gd` | `godot --path . -s res://cli/view_shots.gd -- --out=<dir>` | the 2D view modules alone (the automap, and the wireframe Genre Halls draws): the title, corridors on three palettes, the automap, every monster (plus a shiny, a champion and a group of three), and the shader at two danger levels |
| `menu_shots.gd` | `godot --path . -s res://cli/menu_shots.gd -- out=<dir>` | The main menu, save manager, settings pages and the pause menu |
| `genre_shots.gd` | `godot --path . -s res://cli/genre_shots.gd -- out=<dir> [sound]` | Genre Halls: each faction's box, the mind panel, the strike bar, a route screen |
| `sfx_dump.gd` | `godot --headless --path . -s res://cli/sfx_dump.gd -- --out=<dir>` | renders every sound effect to WAV with a table of length, peak and RMS, to listen to or measure |
| `voice_lines.gd` | `godot --headless --path . -s res://cli/voice_lines.gd -- --out=build/voice-lines.json` | every line a monster can say aloud, for rendering a voice bank (see [Voices](AUDIO.md#voices)) |

The scenario scripts use mock Jev by default (random answers, no credits, repeatable with `--seed`): that checks the plumbing and the game's rules, not Jev's judgement. `--live` calls the real API with the key from `.env` or `config/jev_config.json`: every call is billed, and each raw reply is saved under `user://jev-raw` before it is parsed. The four screenshot scripts open a window briefly (they are not headless); pass `out=` (or `--out=`), because their default folder is a scratch path.

### Godot MCP for AI agents

[Godot MCP](https://github.com/Coding-Solo/godot-mcp) is registered as the `godot` server for Claude Code (`.mcp.json`) and Codex (`.codex/config.toml`), so an agent can open the editor, run the game and read its output and errors, create scenes and add nodes, and refresh UIDs. It lives in `tools/godot-mcp/`, pinned in that folder's `package.json` and lockfile; `tools/godot-mcp/run.sh` runs `npm ci` there on the first start (and whenever the lockfile changes), then starts the server. It needs Node 18+ and the `godot` binary on `PATH` (or `GODOT_PATH=/path/to/godot` in the environment). To install it ahead of time:

```bash
npm ci --prefix tools/godot-mcp
```

Claude Code asks once whether to trust the project's MCP servers; approve `godot`. Codex loads `.codex/config.toml` only once the project is trusted (it asks on the first start here); `codex mcp list` shows the server, and it forwards `GODOT_PATH` when that is set. The server's own dependencies carry known `npm audit` advisories (an old pinned MCP SDK); it only talks to the agent over stdio, and nothing of it ships in a build.

## Debug mode (developers only)

Players never see Jev's raw output. Turn debug mode on with the `debug` flag, `donjon.debug` set to `"1"` in the saved data, or `"debug": true` in `config/jev_config.json` (builds made with `--openrouter` or `--proxy` have it on; `nodebug` turns it off), and you get:
- the **Jev mind panel** (toggle with **J**): every monster's meters, what it heard, Jev's action odds, its feeling odds, its answer to an invitation and the reason, every choice code blocked, and how allies scored each fight;
- `[DEBUG]` lines in the log with the numbers behind feelings, ally talks, vows and loyalty changes;
- the `halls` console hooks, in the web build.

**Every API request, in detail.** The panel has a **REQUESTS** tab: every call the game makes to Jev's rules (`group-turn`, `ally-reactions`, `ally-talk`, `vow`, `vow-broken`), newest first, the last hundred, with its status, time, how many Jev calls it took, questions and tokens. Open one to read exactly what was sent and answered, and below it each raw Jev call: the `state` Jev was given, the `questions`, and its `answers` with all their probabilities, each with a COPY button that puts the pretty-printed JSON on the clipboard. The key never appears in it.

**Test runs:** `godot --path . -- main floor5` (any number from 2 to 30) starts on that floor with a party that got there. Add `debug` for debug mode: `floor5-debug`.

## Coming from the browser version

The game was a browser game with a Node server and was rewritten in Godot; the JavaScript lives on in git history (`git show 12d2be7:crawler/README.md` is its README). The game's rules, wording and numbers are the same, and the Jev questions are byte for byte the ones the JavaScript sent (`tests/jev/golden/`). What changed:

| Before | Now |
| --- | --- |
| `npm run crawler` | `godot --path . -- main` (plain `godot --path .` opens Genre Halls) |
| `npm run crawler:mock` | `godot --path . -- main mock` |
| `?debug`, `#floor5-debug`, `?nofx`, `?nodebug` in the URL | the same words after `--`, or in the address on the web build |
| `npm test` | `godot --headless --path . -s res://tests/run_tests.gd` |
| `npm run crawler:scenarios`, `crawler:social` | `cli/scenarios.gd`, `cli/social_scenarios.gd` |
| `npm run crawler:shots` (Playwright in Chrome) | `cli/shots.gd` (the real screen in a Godot window) |
| `npm run crawler:itch`, `build-itch.js` | `tools/build.sh` |
| `TYPESAFE_API_KEY` held by the Node server | `.env` read by the game; in a build, `config/jev_config.json` or the Worker |
| the Worker (`halls-of-jev-api`) ran the game's rules; the itch.io build called Jev from the browser with a public key | the Worker (`donjon-api`) only forwards requests and every build uses it; the rules run in the game; CI no longer publishes to itch.io |
| `localStorage` | `user://store.json` |

Gone for good: `npm run crawler:bench` (the frame-time benchmark), the three developer pages `gallery.html`, `cover.html` and `beatmaker.html` with the Beethoven theme and `music.js` engine behind it, and the monsters' jagged look (`ART.pixel`). To see every monster, run `cli/view_shots.gd`; the cover is `docs/donjon-cover.png` (630 × 500).
