# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex) when working with code in this repository.

Donjon: a Godot 4.7 (GDScript) wireframe dungeon crawler whose monsters are driven by Jev, TypeSafe's LLM. It was ported from a browser game (JavaScript, last at `12d2be7`); many comments say "the JS". Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing code, [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for setup, flags, CI and debug tools, and [docs/GAME.md](docs/GAME.md) for the rules.

## Commands

Godot **4.7.2** must be on `PATH` (export templates too, for builds). No linter or formatter is configured.

```bash
godot --headless --path . --import                                  # once, and after adding files or assets (.uid/.import files are committed)
godot --headless --path . -s res://tests/run_tests.gd               # all tests (~500, under a minute); exits non-zero on failure
godot --headless --path . -s res://tests/run_tests.gd -- --only=dnd # only test files whose path contains "dnd"
godot --path .                                                      # play (main menu -> Genre Halls); add `-- main mock` for the original Donjon on mock Jev
godot --path . --verbose                                            # print_verbose logging
node --test proxy/worker.test.js                                    # the Cloudflare Worker's tests (proxy/, JavaScript)
tools/build.sh web                                                  # export one platform to build/<platform>/ and zip it
```

- Run flags go after `--` (`mock`, `seed=N`, `debug`, `floorN`, `main`, `meet=<species>`, `nofx`...); the full table is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#run-flags).
- `cli/*.gd` are scenario runners and screenshot dumps (`cli/scenarios.gd`, `cli/social_scenarios.gd` run headless on mock Jev; the `*_shots.gd` ones open a window and need `out=<dir>`). CI runs both scenario scripts with two seeds, so keep them passing.
- With no key, Jev is mocked (random but well-formed answers). Tests never read `.env` or the network. `--live` runs bill real API calls; don't use them unasked.

## Architecture (the parts that need several files to see)

- **No `class_name`.** Modules are scripts of `static func`s used through `preload` constants (`const Species = preload("res://src/rules/species.gd")`). Data is JSON-shaped Dictionaries/Arrays with camelCase keys (`maxHp`, `clsId`); those keys go to Jev, to `user://store.json` and into golden fixtures, so don't rename them. Everything else is snake_case.
- **Two games share one renderer.** The original Donjon is `src/game/game.gd` (rules/flow, state in one `G` Dictionary) driven by `src/ui/main.gd` (screen, built in code); they meet only through `game.key(k)`, the `ui.*` hooks and the typed `game.fx` event bus. **Genre Halls** (`src/genre/`, the default start via `src/menu/main_menu.tscn`) is a separate Undertale-style scene that reuses `Render`/`Art`/`Species`/`Emotions`/`Sfx`/`PostFx` but not `game.gd`. A change to a shared module can break both.
- **Jev boundary.** `src/jev/api.gd` (`JevApi.handle`) answers what the old server did: `enemy.gd`/`allies.gd`/`bonds.gd` build questions (`q.gd`), `jev.gd` sends them through a swappable transport (real `HTTPRequest`, mock, or tests). Jev reads and picks; **code owns the rules, odds and what is allowed**. Provider is chosen once by `config.gd` (mock flag > `config/jev_config.json` > `.env` > mock with a warning). Builds carry no key: they use the `proxy/` Worker (`JEV_API` in `ci.yml`).
- **Wording is data.** Player-facing strings, balance numbers and Jev questions were ported byte for byte because Jev's answers depend on wording. `tests/jev/golden/*.json` pin the exact requests and results; changing Jev's wording means editing a fixture in the same commit.
- **View.** A real 3D set (`src/view/stage3d.gd`, `dungeon3d.gd`, `monsters3d.gd`) is drawn as black surfaces with line-only shaders, composed with a 2D canvas layer (`canvas2d.gd`) and a post-FX pass, in a 448x288 `SubViewport`. Compatibility renderer only (the web export needs it); no engine lights.
- **Audio** is mostly synthesised at runtime (`synth.gd`, `sfx.gd`, `mix.gd`); only the music (`assets/audio/*.ogg`, track lengths in `ambient.gd` must match the files) and pre-rendered monster voice banks (`assets/voices/`) are files.
- **Saved data** is one JSON file through the `Store` autoload (`user://store.json`); save slots are files under `user://saves/`.

## Gotchas

- GDScript is not JS: use `J.round_js`, `J.num`, `J.truthy`, `J.nz` from `src/core/js.gd` instead of rewriting the idioms; `7 / 2` is `3`; JSON numbers are floats (`int()` before using one as a Dictionary key); `d.key` on a missing key is an error, use `d.get("key", default)`; `[]`/`{}` are falsy; lambdas capture by value; `sort_custom` is not stable.
- Any `push_error` or script error during a test **fails that test** (the runner installs a `Logger`), so a noisy log line in an error path can break the test that walks it.
- `tests/game/helpers.gd` has a stub ui listing every `ui.*` hook; keep it in sync when the game calls a new one.
- Don't name a static function `reload` on a script: it shadows `Script.reload()` and wipes static variables.
- `tools/`, `native/`, `proxy/`, `docs/` carry `.gdignore`: Godot doesn't import them. Don't add game assets there.
- Add `print` for notable run moments, `print_verbose` for detail, `push_warning`/`push_error` for trouble when you add behaviour you may need to debug.

## Conventions

- Commits: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci). Keep a Changelog format in `CHANGELOG.md` (version-grouped, one-liners). A `vX.Y.Z` tag must equal `config/version` in `project.godot` and have a `## [X.Y.Z]` section in the changelog, or `release.yml` fails.
- CI (`ci.yml`) runs tests, then scenarios, then builds all four platforms; it uses no secrets. Workflow actions are pinned to commit SHAs.
- Tooling for agents: the `godot` MCP server is registered in `.mcp.json` (Claude Code) and `.codex/config.toml` (Codex); it runs `tools/godot-mcp/run.sh`.
- `CLAUDE.md` and `AGENTS.md` are ignored by the author's global gitignore; this file is tracked with `git add -f`.
