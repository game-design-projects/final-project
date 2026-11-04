# AGENTS.md

Read this first. It is the short version of what the code alone won't tell you.

## Which code is the game

The game is the 3D line only: today's `src/`. The 2D Donjon was abandoned because it couldn't be made smooth. It lives on in git history before `0acd6ef` (`src/ui/`, `src/game/game.gd`, `src/jev/` and others). Never add features to it or port code from it. To check what the rewrite lost, compare against the 3D line at `017b551`: `src/genre/`, `src/menu/` and what they load.

Keep the corridor perspective (FOV 68, eye 0.85, wall height 1.7): it is the correct one. A fight ends in the log with no CONTINUE screen, on purpose.

## Commands

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Always pass `nosave` when a script runs the game, so the player's saves stay untouched.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). No `class_name`: modules are used through `preload` constants. Rules live in `src/rules/` with no UI; the stages in `src/game/stages/` are one state machine with a transition table; views only read `flow.state` and listen to `flow.happened`. Every chance roll goes through `Dice`.

## Gotchas

- Don't name a static function `reload` on a script: it shadows `Script.reload()` and wipes static variables.
- A new sound name needs a recipe in `src/audio/sfx.gd`; `tools/audio_test.gd` scans for this.
- Tests can't judge how it looks or sounds. Take screenshots with `tools/screenshots.gd` and read them.

## Conventions

- Commits: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci). Keep a Changelog format in `CHANGELOG.md` (version-grouped, one-liners). A `vX.Y.Z` tag must equal `config/version` in `project.godot` and have a `## [X.Y.Z]` section in the changelog, or `release.yml` fails.
- CI (`ci.yml`) uses no secrets. Workflow actions are pinned to commit SHAs.
