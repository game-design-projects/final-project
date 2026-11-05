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
| `gameplay_test` | Flow, stages, tooltips, mouse and touch input, views after a new floor or a load |
| `menu_test` | Menu pages and their keys |
| `saves_test` | Save slots, `nosave`, refusing a bad save |
| `slice_test` | The personality slice's routes |
| `rules_test` | Strike, odds, dodge cells, word reading, hints |
| `network_test` | Timeouts, retries, Jev's answers |
| `view_test` | Models, sight, camera, automap, palettes |
| `audio_test` | Every sound name has a recipe, music, voices, mix (run it without `nosound`) |
| `map_test` | The floor generators, biomes and chunks, and what sight costs on a big floor |
| `meta_test` | Achievements, Legacy, hunger, camp, butchering, and a save without any of them |
| `features_test` | Each feature with its flag on and off (it switches them itself) |

`tools/run_tests.sh [on|classic|both]` runs them all, plays whole games in each mode, and with the features on plays five games without a strike.

Tests can't judge how it looks. These draw the real thing and print numbers, with pictures if given `out=<dir>`. They need a window, which may stay hidden:

| Script | What it tells you |
| --- | --- |
| `flicker_check` | Which pixels of a monster blink as it stands there, and how much its lit area jumps gliding (`only=<species>`) |
| `far_check` | Every species at every distance down the longest line of each floor, and across floors: is it seen, and is a name ever over nothing |
| `hold_check` | Each arrow held in the real game scene: cells, turns, bumps, whether the camera turned back, the slowest frame |
| `screenshots`, `camera_shots`, `model_shots`, `map_shots` | Pictures to look at |
| `sim_recruit` | How long winning each monster over takes against killing it |

The Worker's tests run with `node --test worker.test.js` in `proxy/`. CI runs all of them, plays whole games, checks that CREDITS ships, and builds the four platforms.

## Run flags

Flags change one run. From source they go after `--`; the list with descriptions is `KNOWN` in `src/utils/flags.gd`.

`debug` · `mock` · `jev=<url>` · `seed=N` · `floor=N` · `meet=<species>` · `personality-slice` · `nofx` · `pad` · `nosound` · `nosfx` · `nomusic` · `nosave` · `out=<dir>`

## Features

Every game feature since 0.6.1 has a flag, on by default. `FEATURES` in `src/utils/flags.gd` is the list, with what each does. `no-<name>` or `<name>=off` turns one off, and `classic` turns them all off.

A new feature goes in `FEATURES`, is read with `flow.feature(name)`, and if the view has to know, in `flow.VIEW_FEATURES` (the view reads `state.viewing(name)`). A save keeps working with any of them off.

`motifs` is the one exception to shipping: Abdulla's motifs aren't in the repo. See [AUDIO.md](AUDIO.md).

## The Worker (Jev)

CI's builds point at `https://donjon-api.lishuyustevenli.workers.dev` (`JEV_API` in `ci.yml`). `.github/workflows/worker.yml` tests the Worker and deploys it from `main` when `proxy/` changes; pull requests only test it and bundle it, with no credentials. The deploy needs `CLOUDFLARE_API_TOKEN` (Workers Editor on this one Worker) and `CLOUDFLARE_ACCOUNT_ID` in the `cloudflare-production` environment. The Jev key never passes through GitHub: set it on the Worker by hand. After a deploy, a smoke test posts a request with no questions (no Jev call, no credits): 400 means the Worker is up with its key, 503 that it has none yet.

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

Until the Worker has its key it answers 503, and the game falls back to the local rules after one request.

## Building and releasing

`tools/build.sh` writes the export presets itself (`export_presets.cfg` is not committed), so CI and a laptop build the same way. It needs `godot` on `PATH` (or `GODOT=/path/to/godot`) with the 4.7.2 export templates installed.

**The web build** uses its own page, `web/shell.html`: no engine logo and no loading screen, just a black page with a 2px line that fills while the files download (the project's boot splash is off too). If the browser can't run the game, or the page is opened as a file, it prints a plain message saying why. `node tools/check-html5.mjs build/web` (Node) checks the folder against itch.io's HTML5 limits (file count and sizes, `index.html` at the top, no symlinks) before a push.

- Commits: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci). Keep a Changelog format in `CHANGELOG.md` (version-grouped, one-liners). A `vX.Y.Z` tag must equal `config/version` in `project.godot` and have a `## [X.Y.Z]` section in the changelog, or `release.yml` fails.

## Godot MCP for AI agents

[Godot MCP](https://github.com/Coding-Solo/godot-mcp) is registered as the `godot` server for Claude Code (`.mcp.json`) and Codex (`.codex/config.toml`), so an agent can open the editor, run the game and read its output and errors, create scenes and add nodes, and refresh UIDs. It lives in `tools/godot-mcp/`, pinned in that folder's `package.json` and lockfile; `tools/godot-mcp/run.sh` runs `npm ci` there on the first start (and whenever the lockfile changes), then starts the server. It needs Node 18+ and the `godot` binary on `PATH` (or `GODOT_PATH=/path/to/godot` in the environment). To install it ahead of time:

```bash
npm ci --prefix tools/godot-mcp
```

Claude Code asks once whether to trust the project's MCP servers; approve `godot`. Codex loads `.codex/config.toml` only once the project is trusted (it asks on the first start here); `codex mcp list` shows the server, and it forwards `GODOT_PATH` when that is set. The server's own dependencies carry known `npm audit` advisories (an old pinned MCP SDK); it only talks to the agent over stdio, and nothing of it ships in a build.

