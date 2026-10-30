# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Work in progress on `feat/opensource-jev`: replacing Jev with an open-source System One model that runs on the player's computer. The route is still being decided; [docs/system-one-research.md](docs/system-one-research.md) has the survey, the measurements and the open questions.

### Added
- Godot MCP (github.com/Coding-Solo/godot-mcp, 0.1.1) for AI agents, in Claude Code (`.mcp.json`) and Codex (`.codex/config.toml`): both start it through `tools/godot-mcp/run.sh`, which installs the pinned package with `npm ci` on first use. Agents can run the game, read its output and edit scenes.
- Decider (Mapika, Apache-2.0) as the monsters' model, read through a stock llama.cpp `llama-server`: `src/jev/decider.gd` (Decider's readout ported from decider-ai 1.10.0, checked byte for byte against its own output in `tests/jev/golden/decider/`, written by `tools/decider_golden.py`), `src/jev/local.gd` (the transport: the state first, then one `/completion` per question), `src/jev/local_server.gd` (starts and stops the server) and `src/jev/local_setup.gd` (downloads a pinned llama.cpp build and model for this OS and backend, sha256-checked).
- A `systemone` way in: any server that answers `POST /v1/systemone`, such as Decider's own.
- `tools/system-one/`: the scripts behind the research page (readout parity, latency on GPU and CPU, a perception probe), with `run_all.sh` to run every llama-server measurement in one go and `prime_check.py` to see how far priming moves each answer.
- NVIDIA measurements in the research page (RTX 4070 Ti SUPER, CUDA, and its i7-14700K CPU): the 4B's schema-first round takes 93 ms for `enemy_turn` and 215 ms for `group_talk`, and one row per question takes 1.7 s on llama-server and on Decider's own CUDA-graph server.

### Changed
- `Jev.configure_jev(opts)` takes no key; the ways in are `local`, `systemone` and `mock`. `config.gd` reads `config/jev_config.json`, then the setup's `user://local-model/install.json`, and falls back to the mock with a warning (*NO LOCAL MODEL INSTALLED*).

### Removed
- The game's TypeSafe, OpenRouter and Worker providers, and API keys in `.env` (the Worker in `proxy/` is still in the repo for now).

## [0.3.0] - 2026-10-29

Donjon moves from the browser to Godot. The web version's last changes, made just before the port, are listed with it (game feel, mixing, Genre Halls); file names in those entries are the web version's.

### Added
- Builds for Windows, macOS (universal, ad-hoc signed), Linux and the web from one script (`tools/build.sh`). CI (`ci.yml`) tests and builds all four on every push to `main` and pull request (kept as workflow artifacts). A `vX.Y.Z` tag matching `config/version` in `project.godot` runs only its own workflow (`release.yml`), which calls CI once and publishes a GitHub release with those builds' zips and this file's notes for that version.
- No engine splash: Godot's boot logo is off, and the web build's page (`web/shell.html`) shows no loading screen, only a thin line while it loads.
- 479 headless tests (`godot --headless --path . -s res://tests/run_tests.gd`): the old suite's assertions, Jev's questions compared word for word with the web version's, its rules compared decision for decision on 137 recorded requests (`tests/jev/golden/`), play-throughs of whole runs on mock Jev, and a test that turns any script error into a failure. Windowed screenshot scripts check the look (`cli/shots.gd`, `cli/view_shots.gd`, `cli/genre_shots.gd`).
- The Jev API Worker, rebuilt on Steven's Cloudflare account as `donjon-api` (https://donjon-api.lishuyustevenli.workers.dev; it was `halls-of-jev-api` on an account we no longer reach). `.github/workflows/worker.yml` deploys it on every push to `main` that changes what it bundles, then checks that it answers without spending Jev credits; pull requests test and bundle it with no credentials. The deploy is scoped tight: a Cloudflare token with Workers Editor on this one Worker only, used by a `cloudflare-production` environment that deploys only from `main`. The Jev key stays a Worker secret and never passes through GitHub.
- The Worker caps each IP at 60 requests a minute (then a 429 for a minute), and only lets outbound requests reach Jev (`api.typesafe.ai`, `openrouter.ai`) over https, so nothing in the game code can send the key elsewhere.
- `proxy/worker.test.js` (13 tests): the Worker fails closed without a key, the rate limit (preflights exempt), the outbound allowlist and that it covers every Jev provider the game uses, that it forwards only the game's question shapes, and a guard that keeps `wrangler.jsonc` to one workers.dev Worker named `donjon-api` with no routes, builds or extra bindings.
- **Genre Halls** (`crawler/public/genre-halls.html`, http://localhost:5174/genre-halls.html): a pitch for Undertale-style battles, built on Donjon's renderer, monster art, species, feelings and synth. You explore a small wireframe floor; a fight switches into a 7×7 box where each faction attacks in its own genre, with one rule: lit squares hurt. Slimes rain goo, bandits play chess (rook, bishop, knight), snake people swing a lantern you hide from behind pillars, and rock entities stomp on the beat. The red dragon champion cycles through all four. Commands are FIGHT (a timing bar), ACT (three species-specific acts, CHECK, or typing once per fight), SPARE (when its mercy odds pass 50%) and FLEE. A spared monster may join as a passive charm (BOUNCY, KEEN EYE, SLIPPERY, STEADY, HOARD-FIRE) that judges what you do and can walk out. Reaching the stairs names your route: ghost, quiet, blood or tangled. The monster's mind answers the same choice / score / yes-no questions the main game sends to Jev, with a local stand-in, and the Jev mind panel shows each answer with its odds.
- `crawler/public/genre-rules.js`: Genre Halls' rules without the DOM, and `crawler/test/genre-halls.test.js` (8 tests). Besides the data and the odds, they check that every floor's stairs and monsters can be reached, that every chess piece and every stomp leaves a safe square wherever you stand, and that the lantern always leaves a shadow to hide in.
- **The view glows like an old vector monitor** (`public/postfx.js`, a WebGL shader over the game's canvas): lines bloom, pixels stay sharp at any window size instead of blurring, faint scanlines run along the game's own rows, the edges fall into the dark, and each floor's accent tints the shadows. Without WebGL, or with `?nofx` in the address, the plain canvas shows as before.
- **The screen tells you how close the party is to falling.** As health runs out (or someone is rolling death saves) the colors drain, a red edge closes in, the music sinks behind a low-pass filter as if heard through your own pulse, and a heartbeat thumps on the music's beat: every other beat while hurt, every beat when someone is about to die. The red edge pulses with each heartbeat (`public/juice.js` `dangerOf`, `public/mix.js`).
- **Hits land.** Screen shake now follows the size of the blow (trauma-based: small hits nudge, big ones rattle, smooth rather than jittery), a critical hit or a kill freezes the monsters for a few frames (hit-stop) and flashes the view, getting hurt flashes the edges red and splits the colors for a moment, and big moments dip the music so they punch through.
- **Moving eases instead of snapping**: a step dollies the old view past you as it fades, a turn pans, and walking into a wall lunges the view at it. Prefers-reduced-motion turns off the shake, the transitions and the strobing.
- **Repeated sounds vary**: hits, misses, hurts, kills, bumps and coins get a random detune and volume each time, so a fight doesn't sound like one sample on repeat. At most a few copies of one sound start together (QUICK ATTACK can land six hits at once), each a little quieter, so a pile-up sounds big without clipping (`public/sfx.js` `VARY`, `POLY`).
- A typed event bus (`public/juice.js` `FX_EVENTS`): the rules announce hits, kills, falls, steps and fights, and the shake, hit-stop, shader and mixing desk answer them without the rules knowing about any of them. An unknown event or a missing field throws, so a typo can't silently drop an effect.
- `npm run crawler:shots`: a smoke test in real Chrome on mock Jev that saves screenshots of the title, a corridor, a turn mid-pan, a fight, a critical hit, the party in danger, the plain-canvas fallback and a phone-sized window, and fails on any page error. `npm run crawler:bench`: frame time, 2D canvas calls, allocations, WebGL draws, style recalcs and layouts per frame, with `Math.random` seeded so two checkouts play the same dungeon (`--root=<other checkout>` to compare).
- Tests: `crawler/test/juice.test.js` (11) and `crawler/test/mix.test.js` (12), plus three for the corridor's cached layer.

### Changed
- **Donjon is a Godot 4.7 game now.** Everything is rewritten in GDScript with the same rules, numbers, words and Jev questions: the dungeon, D&D combat, talking, recruiting, vows, boons and the Roll of Fate (`src/game/`), the wireframe view and the monster art through a Canvas 2D adapter (`src/view/`), the vector-monitor shader (`src/view/postfx.gdshader`), the CRT screen with its party panel, log, command dock, tooltips, achievements and tips (`src/ui/`), and Genre Halls (`src/genre/`, or `-- genre-halls`).
- The game calls Jev itself (`src/jev/`): through OpenRouter or TypeSafe with the key from the project's `.env` when run from source, from `config/jev_config.json` in a build, or on mock Jev when there is no key (the log says so). The Jev API Worker (`proxy/`) now only forwards the game's Jev questions, and every CI and release build reaches Jev through it, so no build carries a key.
- Sound effects are synthesized from the same recipes when first played (`src/audio/synth.gd`), within 0.5 dB of Chrome's WebAudio renders. The music is Ogg Vorbis (Godot can't play AAC), each loop cut to exactly one loop so it wraps without a seam.
- Monsters speak with the operating system's text to speech; hold-Space speech recognition works in the web build.
- Achievements, seen tips and the switches are saved in `user://store.json`. The address flags (`?debug`, `#floor5`, `?nofx`) are words after `--` on the command line (`godot --path . -- floor5 debug`), and still work in the web build's address.
- The music's build scripts live in `tools/music/`, with the six soundfonts they sample, and encode to Ogg (`to_ogg.sh`).
- Music and sound effects share one audio context and one mixing desk (`public/mix.js`), with a limiter at the end: they keep one clock (so the heartbeat lands on the beat) and can react to each other. Turning the music off (P) now mutes it rather than pausing the whole audio engine.
- The corridor is painted once per step into a cached layer and copied on every other frame; with a torch in sight it repaints at the flames' own 24 frames a second. Standing still, the view went from about 120 canvas calls and 33 new paths and gradients per frame to 3 calls and none (`crawler/scripts/bench-view.mjs`, Chrome, CPU slowed 4×).
- The top bar, party panel, log and command dock are rewritten only when their contents change, which keeps hover state and cuts layout work while walking by about two thirds (32 to 10 layouts over the same 16 moves).

### Removed
- The Node server and npm scripts, the beat maker, the monster gallery and cover pages, the `music.js` engine and the soundfonts only it used. They stay in git history (`12d2be7`).

### Fixed
- On a phone, the switches (tips, achievements, voices, sound, music) no longer hide behind the view: the top bar grows to two rows.

### Removed
- Publishing to itch.io from CI: the final ships as a native build. CI builds every platform and releases on tags without any secret; `tools/build.sh web` still makes the browser zip by hand, through the Worker or OpenRouter.

## [0.2.1] - 2026-10-06

### Fixed
- Monster allies no longer crowd the log out of view: each ally takes one compact line in the party panel (name, health, mood, armor; its kind and level on hover) instead of a two-line card, so a full party of six leaves about twice as much room for the log.

### Added
- An "ALLIES 2/3" line above your monster allies: how many have joined and how many seats are left (the party holds six, so three beside your adventurers), lit when the party is full.

### Changed
- The switches in the top bar follow keyboard order, H J K L O P (tips, Jev mind, achievements, voices, sound, music), so each keycap sits where its key is.

## [0.2.0] - 2026-10-06

### Added
- A guided first fight: a new player's first encounter is one shy orange slime, and it teaches the game's heart by doing it. Only TALK works at first (it glows; the other commands are dimmed, and pressing one shakes the dock and brings the tip back), then only RECRUIT, and the invitation is a sure yes (beginner's luck on the Persuasion roll; the server is told `guided`, so Jev's answer can't refuse and the slime doesn't wander off). Every later fight is unguided. H (tips off) skips or releases it; H again replays it. Debug: `halls.lesson()`.

### Fixed
- No more jump when the game starts, or later: the top bar has a fixed height, the side column (party and log) always matches the view and map beside it with the log scrolling inside, hiding the map keeps its space, and the command dock has a steady minimum height. Measured identical from the title screen through exploring and fights.
- The top status line no longer jumps around: one row, every slot (facing, gold, boons, achievements, toggles) a fixed width, so turning, earning gold or starting a fight only changes the text in place. Only the floor's name shortens (with an ellipsis, full name on hover) when space is tight.
- The dark ambient no longer plays on under the battle music: it now gets out of the way within 0.4 s when a fight starts (it took 5 s, so both played together for the first seconds).
- Yes/no questions (stairs down, Revivify, a monster asking to join) no longer hide in the top bar while every other key is silently ignored: they open as a glowing box over the view in the floor's accent color, with clickable answers, Enter/Esc for yes/no, and any other key shakes the box to show where to look. At the stairs you can simply walk away.
- Dungeon view perspective: the corridor is now a real 1/z projection (it used a geometric series, so far cells looked squashed), painted far to near with black-filled faces so nearer walls hide farther ones.
- No more phantom walls across side openings that lead into rooms and the boss hall.
- Wall decorations and stairs are mapped in perspective (a torch halfway down a side wall now sits halfway down it), and a torch's glow no longer leaks around the wall that hides it.
- The automap only reveals floor you could actually see.
- The automap shows walls: each side of seen floor that faces a wall gets a line in the floor's wall color, so walls no longer look the same as unexplored dark.

### Changed
- The itch.io build no longer needs the Cloudflare Worker: it calls Jev through OpenRouter straight from the browser, with the game's rules shipped in the page and a deliberately low-credit OpenRouter key in its config (`build-itch.js --openrouter`; CI uses the `OPENROUTER_API_KEY` secret). The server and Worker can reach Jev through OpenRouter too.
- The music is re-scored as baroque dungeon music on real sampled instruments (harpsichord, church organ, strings, choir, music box, tubular bells, kettle drums), all built on the game's melody and played in one stone hall: exploring is a D minor passacaglia (64 BPM, five variations on a lament bass); fights pick one of four toccata-style loops at random, never the last one (toccata D minor, charge A minor, crusade G minor, gallop E minor; 112-132 BPM), and keep it for the whole fight rather than switching mid-fight; going downstairs and winning get organ, strings and bells resolving in D major. Replaces the synth ambient and the chiptune loops (`scripts/sampler.py`).
- The top bar's switches (Jev panel, tips, music, sound, voices) are a keycap and a pixel icon each, slashed red when off, with the words in the tooltip, so the bar fits in one row even in debug runs.
- Scrollbars everywhere (log, panels) are square pixel bars instead of the browser's rounded ones, and focus rings are square.
- Tooltips are pixel art: every hover note is a framed box in the pixel fonts and the floor's color, with a pixel arrow, instead of the browser's grey system tooltip. Multi-part notes get one line each, and ability scores show as a small table (`public/tooltip.js`).
- The itch.io build starts in debug mode (Jev mind panel, `[DEBUG]` log lines, console hooks); `?nodebug` turns it off. Local play is unchanged.
- The party panel sits beside the view instead of at the bottom of the page, so you see everyone's health while choosing moves; the member choosing glows, and the one you're about to heal lights up. The automap moved right under the view, with a small key, and steps aside in fights; the whole screen fits in less height.
- Fights have their own music, built on the game's own melody (A B C D D D E D E D C C C D D D) moved into D major and lifted through B♭ and C: a bright, driving 8-bit loop (`battle.m4a`, rendered by `scripts/build-battle.py`) crossfades in when a fight starts, and the dark ambient comes back when it ends. No more creepy ambient under combat.
- The ambient comes back quickly: a 2-second fade-in, 2 seconds after a fight and 4 seconds after the stairs fanfare.
- The dark ambient no longer plays nonstop: about 90 seconds of music, then a minute or two of quiet, then it drifts back.
- You see 6 cells ahead instead of 4, with lines fading into the dark with distance.
- Stairs down are larger and drawn in the floor's accent color so they stand out from a distance.

### Added
- Monsters read their lines aloud with the browser's text to speech, each species with its own pitch and pace. Off by default; on by itself once you use voice input; L toggles it for good. While a monster talks, the music ducks to a quarter and the effects to half so the words are heard (`public/tts.js`).
- Achievements: 30 of them, about what makes Donjon different (talking, recruiting, vows, dice, champions, a few secrets), kept across runs. Unlocks slide in over the view with a jingle; K (or the trophy in the top bar) opens the full list with dates, progress bars and ??? for secrets (`public/achievements.js`).
- Debug REQUESTS tab in the Jev panel, in the game's pixel style (framed sections with label tabs, pixel triangles, JSON colored by token, square scrollbars): every API request with status, time, Jev calls, questions and tokens; open one for the exact request and response and each raw Jev call (state, questions, answers), with COPY buttons. The server returns the Jev calls for a request when asked with `?debug=1` (`public/inspector.js`).
- Mock Jev (`src/mock-jev.js`): seeded, well-formed random answers. `npm run crawler:mock` runs the game on it; the scenario scripts use it by default (`--live` for real calls); `npm test` now covers every API endpoint with it, and CI runs the scenarios on it.
- Hold Space to talk (or the HOLD TO SPEAK button) and speak instead of typing: in a fight it talks to the monsters, exploring to an ally, and in an empty talk box it just listens; the browser's built-in speech recognition fills the box live and sends it when you let go (`public/voice.js`).
- GitHub Actions CI (`.github/workflows/ci.yml`): tests and a validated itch bundle on every push and pull request; pushes to `main` publish to https://aalfalasi.itch.io/donjon with butler.
- Music cues for good news, both quoting the same melody: a bright 8-bit fanfare when you go down the stairs, and a short victory jingle when you win a fight.
- `npm test`: tests for the view geometry (`crawler/test/render.test.js`) and music mood switching (`crawler/test/ambient.test.js`).

[Unreleased]: https://github.com/game-design-projects/week4-jev-game-ai-by-Aalfalasi/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/game-design-projects/week4-jev-game-ai-by-Aalfalasi/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/game-design-projects/week4-jev-game-ai-by-Aalfalasi/releases/tag/v0.2.0
