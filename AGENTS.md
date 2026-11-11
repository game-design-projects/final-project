# AGENTS.md

Read this first. It is the short version of what the code alone won't tell you.

## Which code is the game

The game is the 3D line only: today's `src/`. The 2D Donjon was abandoned because it couldn't be made smooth. It lives on in git history before `0acd6ef` (`src/ui/`, `src/game/game.gd`, `src/jev/` and others). Never add features to it or port code from it. To check what the rewrite lost, compare against the 3D line at `017b551`: `src/genre/`, `src/menu/` and what they load.

Keep the corridor perspective (FOV 68, eye 0.85, wall height 1.7): it is the correct one, because the old build's walls weren't square (2.0 wide, 2.2 tall; now 2.0 wide, 1.7 tall). A fight ends in the log with no CONTINUE screen, on purpose.

## Commands

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Always pass `nosave` when a script runs the game, so the player's saves stay untouched.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). No `class_name`: modules are used through `preload` constants. Rules live in `src/rules/` with no UI; the stages in `src/game/stages/` are one state machine with a transition table; views only read `flow.state` and listen to `flow.happened`. Every chance roll goes through `Dice`, with one exception: a roaming monster's move (`src/rules/roaming.gd`) is worked out from the floor's seed, the monster's index and the floor's saved step count, because `Dice` isn't saved and is pinned in the slice.

## Gotchas

- Don't name a static function `reload` on a script: it shadows `Script.reload()` and wipes static variables.
- A new sound name needs a recipe in `src/audio/sfx.gd`; `tools/audio_test.gd` scans for this.
- Tests can't judge how it looks or sounds. Take screenshots with `tools/screenshots.gd` and read them; `tools/flicker_check.gd`, `tools/far_check.gd` and `tools/hold_check.gd` measure the real picture and the real scene.
- A new feature is part of the game and gets no flag; one that has to be tried beside the old behaviour goes in `FEATURES` in `src/utils/flags.gd`, on by default (the few in `OPT_IN` are off unless named, see docs/DEVELOPMENT.md). `classic` must stay the game without those, the personality slice (`flow.on_slice()`) stays what it was, and an old save must still load.
- Commit a script's `.uid` file with it (Godot writes one beside every `.gd` on import); every script has one tracked.
- A `-s` tool script can't `preload` anything that uses the `Store` autoload (`src/menu/progress.gd`): `load()` it at run time.
- The art is cut by `tools/art/process.py`: change a source sheet or `tools/art/sheets.json` and run it, rather than editing `assets/art/*.png` or `data/sprites.json` by hand. See [docs/ART.md](docs/ART.md).
- A SubViewport in a tool needs `await process_frame` and then `RenderingServer.force_draw()`: transforms only flush in the main loop, and a hidden window never fires `frame_post_draw`.

## Conventions

- Commits: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci). Keep a Changelog format in `CHANGELOG.md` (version-grouped, one-liners). A `vX.Y.Z` tag must equal `config/version` in `project.godot` and have a `## [X.Y.Z]` section in the changelog, or `release.yml` fails.
- CI (`ci.yml`) uses no secrets. Workflow actions are pinned to commit SHAs.
