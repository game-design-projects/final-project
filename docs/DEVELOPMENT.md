# Development

## Commands

```bash
godot --headless --path . --import                                # once, and after adding files or assets
godot --path .                                                    # play
godot --path . -s res://tools/screenshots.gd -- out=/some/dir seed=7   # pictures of each moment (opens a window)
godot --headless --path . -s res://tools/autoplay.gd -- seed=7042 mock nosound nosave   # play whole games
tools/build.sh web                                                # export to build/web/ and zip it
```

## Tests

Each script prints one line per check and exits 1 if any failed. Pass `nosave` so your own saves stay untouched:

```bash
godot --headless --path . -s res://tools/<name>.gd -- nosave nosound
```

| Script | Checks |
| --- | --- |
| `social_test` | Contextual monster offers, personality outcomes, combat/resources, safe popup, custom text, saves/retry and the game without it |
| `moods_test` | Seeded dynamic moods, pressure and old-save defaults |
| `gameplay_test` | Flow, stages, tooltips, mouse and touch input, views after a new floor or a load |
| `menu_test` | Menu pages and their keys, the opening film is there and plays |
| `saves_test` | Save slots, `nosave`, refusing a bad save |
| `rules_test` | Strike, odds, dodge cells, word reading, hints |
| `kinds_test` | Five kinds to a floor and none on two, each clan on every floor, a floor's monsters and champion, warrens, old saves, and every attack: it makes hazards, warns your square 0.3 s ahead, never lights the whole box or walls you in |
| `network_test` | Timeouts, retries, Jev's answers |
| `view_test` | Models, sight, camera, automap, palettes |
| `audio_test` | Every sound name has a recipe, music, voices, mix (run it without `nosound`) |
| `map_test` | The floor generators, biomes and chunks, what sight costs on a big floor, charting the rest of a floor and the full map |
| `meta_test` | Achievements, Legacy, hunger, camp, butchering, and a save without any of them |
| `art_test` | The atlases, how a figure moves, warmth, moods, what hangs on the walls, Wick from her first hop to a saved game |
| `features_test` | Each feature with its flag on and off (it switches them itself), and the champion holding the stairs over 1,000 seeds (the issue #26 measurement) |

`tools/run_tests.sh` runs them all and plays whole games: as the game ships, without a strike, from the practice floor and with `skill-combat`. A suite that makes faults on purpose says where: `network_test` prints `errors expected below` before the checks that provoke them and `errors expected above` after, and the runner only fails a suite for a `SCRIPT ERROR` outside such a block.

Tests can't judge how it looks. These draw the real thing and print numbers, with pictures if given `out=<dir>`. They need a window, which may stay hidden:

| Script | What it tells you |
| --- | --- |
| `flicker_check` | Which pixels of a monster blink as it stands there, and how much its lit area jumps gliding (`only=<species>`) |
| `far_check` | Every species at every distance down the longest line of each floor, and across floors: is it seen, and is a name ever over nothing |
| `hold_check` | Each arrow held in the real game scene: cells, turns, bumps, whether the camera turned back, the slowest frame |
| `reveal_shots` | Deterministic step/turn panel frames at 0, 40, 70, 100, 200, 1000 ms through bloom/CRT, plus lifecycle assertions (`out=<dir>`) |
| `screenshots`, `camera_shots`, `map_shots`, `nerve_shots` | Pictures to look at (`nofocus` keeps the window from taking the keyboard) |
| `sim_recruit` | How long winning each monster over takes against killing it |
| `sim_chart` | How much of a floor is seen when the stairs first show, and the steps instinct saves on the way to them, per biome and depth (`seeds=N`); for tuning `chart` in `data/floors.json` |
| `sim_dodge` | How hard each attack is: a bot that reads the warnings plays it over many seeds and intensities (`only=<attack,...>`, `seeds=N`, `csv=1`); it prints hits, how much of the box is lit, and moments with no way out |

The Worker's tests run with `node --test worker.test.js` in `proxy/`. CI runs all of them, plays whole games, checks that CREDITS ships, and builds the four platforms.

## When a part fails: debug stops, an export carries on

`src/utils/fault.gd` holds the one rule. A debug build (the editor, the tools, CI) fails fast: a script error ends the function it is in and, under the editor's debugger, pauses the game on that line. An export does neither: measured on 4.7.2 with the 0.9.3 macOS build, a missing key reads as `null`, the function runs to its end, nothing is logged and `assert` is not evaluated, so a typed `float` can hold `null`.

So a paused game in the editor is the debug build doing its job, and what an export needs is a place where a wrong answer is noticed. `src/mind/safe_mind.gd` is that place for the minds: every answer is checked (odds that can be rolled, a number in range, both halves of a pair, an answer within 30 s). A bad one is reported with `Fault.report` (`fault N: mind: ...` in the log); a debug build hands it on untouched so the run fails as before, an export asks the local rules instead. `tools/network_test.gd` runs both sides by setting `Fault.forced`.

To see what an export really does with a piece of code, swap a pack into a copy of a released app (an export template refuses `--path` and `-s`): `godot --headless --path <project> --export-pack <preset> out.pck`, copy it over `Donjon.app/Contents/Resources/Donjon.pck`, run `Donjon.app/Contents/MacOS/Donjon --headless`.

## Run flags

Flags change one run. From source they go after `--`; the list with descriptions is `KNOWN` in `src/utils/flags.gd`.

`debug` · `mock` · `nojev` · `jev=<url>` · `seed=N` · `floor=N` · `meet=<species or kind>` · `social-demo` · `notips` · `nofx` · `pad` · `nosound` · `nosfx` · `nomusic` · `nosave` · `out=<dir>` · `nofocus`

## Playing from source with Jev

`godot --path .` asks Jev through the public proxy (`DEFAULT_URL` in `src/mind/minds.gd`, the Worker below) with no setup, the same as a build; the local rules answer whenever it can't be reached. To change that:

- `-- nojev`: the local rules, no network. `-- mock`: the seeded random mind.
- `-- jev=<url>` or `"jev_url"` in the Store file (`user://store.json`, on macOS `~/Library/Application Support/donjon/store.json`): another proxy, such as `node proxy/dev.js` (`jev=http://localhost:5175`). The command line wins over the Store, and either wins over a build's shipped address.

The default applies only to the game. A headless run or a `-s` tool script (every suite, `autoplay`, the screenshot tools) never gets it, so tests repeat exactly and spend no credits. `config/jev_url.txt` is how a build ships its address (`tools/build.sh --proxy`) and stays gitignored.

## Features

What shipped from 0.6.1 on is simply the game now. Twenty features still have a flag, on by default, because they are meant to be tried against the game without them: `branching`, `toll`, `last-door`, `roaming`, `heavy-strike`, `flee-cost`, `ambush-prompt`, `dynamic-moods`, `initiated-dialogue`, `wick`, `dungeon-reveal`, `hum-theme`, `motifs`, `achievements`, `legacy`, `nerve`, `mood-attacks`, `follow-through`, `keepsakes` and the opt-in `skill-combat`. `FEATURES` in `src/utils/flags.gd` is the list, with what each does. `no-<name>` or `<name>=off` turns one off; there is no switch for all of them at once.

The exception is `OPT_IN`: experiments that replace part of the game and are tried beside it, off unless named. Today that is `skill-combat` (`godot --path . -- skill-combat`, or `?skill-combat` on the web build): SKILLS takes FIGHT's place. Its numbers are in `data/skills.json`.

A new feature is part of the game and gets no flag. Give it one in `FEATURES` only when it has to be tried beside the old behaviour: it is read with `flow.feature(name)`, and if the view has to know, it goes in `flow.VIEW_FEATURES` (the view reads `state.viewing(name)`). A save keeps working with any of them off.

`motifs` is the one exception to shipping: Abdulla's motifs aren't in the repo. See [AUDIO.md](AUDIO.md).

## The art

The drawings come from Codex's image generation (`codex exec` on a ChatGPT login, no API key), and everything in the game is cut from them by a script. [ART.md](ART.md) says what they are for.

```bash
tools/art/generate.sh decor                         # one sheet from tools/art/prompts/, into tools/art/raw/ (gitignored, numbered, never overwritten)
tools/art/animate.sh witch set1 tools/art/source/witch.png  # a figure's 6x4 sheet of continuous frames, drawn from a reference
tools/art/keep.sh decor 2                           # promote that take to tools/art/source/ as 8-bit grey
uv run --script tools/art/process.py [name]         # cut sheets into assets/art/ and data/sprites.json, and write GIFs to docs/art/
godot --headless --path . --import                  # a new PNG needs importing; set mipmaps/generate=true in its .import
```

`process.py` prints how much each frame moves from the one before it and marks a jump: read that before looking at the GIF. A figure's silhouette (the alpha of its atlas) is worked out by flood fill, so a drawing with an open outline shows through; the script warns.

### The opening film

NEW GAME plays `assets/video/intro.ogv` (`src/menu/intro_cg.gd`) before the run. Godot plays Ogg Theora only, so a rendered mp4 is re-encoded by a script; the prompt it came from, and what each render got right and wrong, are in [intro/seedance-prompt.md](intro/seedance-prompt.md).

```bash
tools/intro_video.sh path/to/render.mp4            # mp4 -> assets/video/intro.ogv (30 fps, Theora q7, Vorbis at the loudness of the music; about 5 MB)
godot --path . -s res://tools/cg_shots.gd -- out=/some/dir [skip=1]   # pictures of the film and the run's first seconds (needs a window: n8)
```

The film is shown whole on black; any key, click or tap skips it after half a second; a film that can't be read or shows nothing for 3 seconds is skipped by itself. It goes through the SFX bus, so the sound settings apply. Only the menu's NEW GAME plays it (not Continue, Load, a retry, or `meet=`), and never with no screen (the headless tests).

`tools/art_shots.gd` records the look in motion on a fixed clock, however slow the machine (it needs a window, so it goes to n8):

```bash
godot --path . --fixed-fps 20 -s res://tools/art_shots.gd -- out=/some/dir seed=7 [only=menu,opening,walk,fight,warmth]
tools/art/reels.sh /some/dir docs/art/game 20       # its clips as GIFs
```

## The Worker (Jev)

CI's builds point at `https://donjon-api.lishuyustevenli.workers.dev` (`JEV_API` in `ci.yml`). `.github/workflows/worker.yml` tests the Worker and deploys it from `main` when `proxy/` changes; pull requests only test it and bundle it, with no credentials. The deploy needs `CLOUDFLARE_API_TOKEN` (Workers Editor on this one Worker) and `CLOUDFLARE_ACCOUNT_ID` in the `cloudflare-production` environment. The Jev key never passes through GitHub: set it on the Worker by hand. The live Worker holds `LLMGW_API_KEY`, an `sk-llmgw-` key from the LLM gateway (llm.lishuyu.app) limited to `~typesafe/jev-latest` and $2 a day; the Worker posts to the gateway's `/llm/v1/systemone`, which reaches Jev through OpenRouter. Of `LLMGW_API_KEY`, `OPENROUTER_API_KEY` and `TYPESAFE_API_KEY`, the first one set is used. After a deploy, a smoke test posts a request with no questions (no Jev call, no credits): 400 means the Worker is up with its key, 503 that it has none yet.

To run your own:

```bash
cd proxy
npm ci --ignore-scripts                      # installs wrangler
npx wrangler login                           # opens your browser to sign in to Cloudflare
npx wrangler secret put OPENROUTER_API_KEY   # or LLMGW_API_KEY (gateway) or TYPESAFE_API_KEY
npx wrangler deploy                          # prints https://donjon-api.<you>.workers.dev
cd ..
tools/build.sh --proxy https://donjon-api.<you>.workers.dev
```

The rate limit's `namespace_id` in `proxy/wrangler.jsonc` has to be unique on the Cloudflare account. Its one service binding is the LLM gateway's Worker: `LLMGW` -> `api-cf-llmgateway-front`, a request for the gateway handed to that Worker inside Cloudflare instead of going out to `api.lishuyu.app` and back (30-100 ms, whenever it lands on a new machine). It is the same request with the same key; with no binding configured (local runs, the tests, an account without that Worker) the Worker fetches the gateway over https, as it did before. On your own account, delete that line in your copy before deploying: `proxy/worker.test.js` expects it, so a change to `main` that removes it fails the check. That test keeps the file to one workers.dev Worker with no routes, builds or other bindings, read as a parsed config rather than one line of it. To test locally, `node proxy/dev.js` runs the same handler on port 5175 (it reads `.env`, and has no rate limit): `tools/build.sh --proxy http://localhost:5175 web`. To take the game offline, delete the secret (`npx wrangler secret delete OPENROUTER_API_KEY`: the Worker then answers 503 and the game reports *JEV UNREACHABLE*) or the Worker in the Cloudflare dashboard.

Until the Worker has its key it answers 503, and the game falls back to the local rules after one request.

## Building and releasing

`tools/build.sh` writes the export presets itself (`export_presets.cfg` is not committed), so CI and a laptop build the same way. It needs `godot` on `PATH` (or `GODOT=/path/to/godot`) with the 4.7.2 export templates installed.

**The web build** uses its own page, `web/shell.html`: no engine logo and no loading screen, just a black page with a 2px line that fills while the files download (the project's boot splash is off too). If the browser can't run the game, or the page is opened as a file, it prints a plain message saying why. `node tools/check-html5.mjs build/web` (Node) checks the folder against itch.io's HTML5 limits (file count and sizes, `index.html` at the top, no symlinks) before a push.

- Commits: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci). Keep a Changelog format in `CHANGELOG.md` (version-grouped, one-liners). A `vX.Y.Z` tag must equal `config/version` in `project.godot` and have a `## [X.Y.Z]` section in the changelog, or `release.yml` fails. A change made after a release goes under `## [Unreleased]`, and only the release commit moves it under the new `## [X.Y.Z]`: `release.yml` builds that version's notes out of that one section, so a line filed under the release already tagged is never read by anything.

## Godot MCP for AI agents

[Godot MCP](https://github.com/Coding-Solo/godot-mcp) is registered as the `godot` server for Claude Code (`.mcp.json`) and Codex (`.codex/config.toml`), so an agent can open the editor, run the game and read its output and errors, create scenes and add nodes, and refresh UIDs. It lives in `tools/godot-mcp/`, pinned in that folder's `package.json` and lockfile; `tools/godot-mcp/run.sh` runs `npm ci` there on the first start (and whenever the lockfile changes), then starts the server. It needs Node 18+ and the `godot` binary on `PATH` (or `GODOT_PATH=/path/to/godot` in the environment). To install it ahead of time:

```bash
npm ci --prefix tools/godot-mcp
```

Claude Code asks once whether to trust the project's MCP servers; approve `godot`. Codex loads `.codex/config.toml` only once the project is trusted (it asks on the first start here); `codex mcp list` shows the server, and it forwards `GODOT_PATH` when that is set. The server's own dependencies carry known `npm audit` advisories (an old pinned MCP SDK); it only talks to the agent over stdio, and nothing of it ships in a build.


## Dungeon reveal tuning

`src/view/stage.gd` exposes the panel choreography (seconds):

| Parameter | Default | Meaning |
| --- | --- | --- |
| `reveal_stagger` | 0.100 | Delay per cell of distance from the nearest new cell |
| `reveal_wall_delay` | 0.040 | Floor to walls |
| `reveal_ceiling_delay` | 0.030 | Walls to ceiling |
| `reveal_seconds` | 0.450 | Each surface's afterglow decay |
| `reveal_intensity` | 3.0 | Peak exposure, compressed before LDR clipping; halved in calm mode |
| `reveal_panel_inset` | 0.14 | Black border as a fraction of each face |

The opaque dungeon shader draws filled rectangular panels on existing faces only,
using face UVs and cell addresses in UV2. Floor, walls and ceiling activate separately.
The original wire appearance returns as the panels decay. Existing bloom/CRT stays
in charge of the glow; monsters, hazards and props retain their own depth and materials.
Stair holes remain holes. `no-dungeon-reveal` restores the original output.

A small RF texture stores start times, uploaded only on steps or exploration changes;
frames update uniforms, never geometry. The stage compares `state.seen` with its
prior snapshot for steps and turns. Every successful step replays all currently
visible corridor cells, including explored cells and backtracking. Stationary frames and wall bumps do not restart
the wave; turns still reveal newly discovered cells. Initial/save views start
settled, and wall breaks preserve reveal history on the same floor.

```bash
godot --path . -s res://tools/reveal_shots.gd -- nosave nosound out=/tmp/dungeon-reveal
godot --path . -s res://tools/panel_reveal_demo.gd -- nosave nosound out=/tmp/panel-reveal
ffmpeg -y -framerate 60 -i /tmp/panel-reveal/frames/%04d.png -c:v libx264 -pix_fmt yuv420p /tmp/panel-reveal/reveal.mp4
```

The deterministic demo uses the actual Stage, camera (FOV 68, eye 0.85), dungeon
mesh and postfx in a 13-cell straight corridor. It captures before, floor, walls,
ceiling, cells 2/3, settled, a monster/hazard readability frame and 150 frames at
60 fps, plus three rapid steps through explored cells and backtracking/bump checks.
Pass `frames=off` to run the demo assertions and still captures without writing the 150 animation frames.
The visibility batch is explicitly supplied by the fixture to show the
full corridor; normal play continues using its existing visibility rules.

## Social-combat playtest

`godot --path . -- social-demo seed=7042 nosave notips` starts five deterministic encounters. Append `no-initiated-dialogue` for comparison. See [SOCIAL_COMBAT.md](SOCIAL_COMBAT.md) for the 5–7 minute protocol, exact tradeoffs and screenshot command.
