# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Combat commands fill a larger three-column grid, with bigger labels and directional navigation.
- ITEM remains visible but disabled when the bag is empty.
- Enemy dialogue waits for a key or tap before combat continues.
- Confirming enemy dialogue starts the attack immediately.
- Enemy dialogue queues early confirmation for 0.3 seconds, and the opening speech box keeps its size when the combat menu appears.
- The combat picture and dock keep their size throughout a fight, including attacks and dodges.
- Camp and other in-game choice menus use larger grid buttons with directional navigation.
- Walking and camp keep the same picture and dock size when opening or closing the camp menu.

### Fixed
- Audio and gameplay checks follow the dialogue prompt and also verify classic mode without it.

### Added
- `tutorial-floor`: a first run starts on a short practice floor above B1F, one corridor with a salve to pick up, a small shy slime to learn sparing on (the old 2D guided first fight, redone with a tip and nothing locked) and the stairs down to B1F. It comes with the TIPS setting, only once (SHOW THE TIPS AGAIN brings it back), and not with `floor=N`; `tools/autoplay.gd -- practice` plays it.
- `dungeon-reveal`: solid rectangular surface panels cascade floor → walls → ceiling on every successful step, including explored corridors, at 100 ms per cell, with configurable timing, biome glow and 450 ms decay; preserves geometry, depth, explored saves and classic rendering.
- `tools/reveal_shots.gd`: stepping and turning captures with exploration lifecycle checks; `tools/panel_reveal_demo.gd` captures a deterministic corridor, 60 fps animation, and monster/hazard readability.
- `hand-drawn`: the whole game is redrawn from sheets made with Codex: brick and flagstone walls, chibi monsters with continuous animation that hop and react, the same drawings walking and fighting, drawn wall decor, chests and sacks, and key art on the menu.
- `warmth`: the halls answer what you do: torches look at you, look away, then shut their eyes, faces go blank one monster at a time, and at the coldest the set is the old wire.
- `wick`: a run opens with a very small witch hopping down the corridor to hand you a heart; she is your first friend, and can be lost like any other.
- Fights now show the halls dimmed behind the monster.
- `tools/art/`: the pipeline that generates sheets with Codex and cuts them into atlases and GIFs; `tools/art_shots.gd` records the look in motion on a fixed clock.
- `tools/art_test.gd`: atlases, figure animation, warmth, moods, wall art and Wick.

## [0.7.0] - 2026-11-07

### Added
- `tools/music/hum-theme/`: an exploring loop and a combat loop on a hummed theme, with their source, MIDI and previews; not in the game yet (refs #49).
- Feature flags for all new game features, on by default: `no-<name>` or `<name>=off` turns one off, and `classic` turns them all off.
- `real-floors`: the stairs lead to the next floor and carry over HP, gold, allies and the tally, and the run ends at the last floor.
- `piece-icons`, `gentle-dodge` and `mini-games`: chess attacks show a piece's shape and reach, dodges run slower and adapt, and every third attack is a mini-game.
- `recruit-step`, `mercy-link`, `party-aid` and `last-door`: a spared monster asks to join, mercy odds show as a gauge, allies help in fights, and the last stairs need a friend.
- `story`: the opening says why you are here, each floor says who holds it, and the header counts the floors.
- `tutorial` and `walk-heal`: one-at-a-time tips with a setting to turn them off, slower first fights, and slow healing while walking.
- `mood-cues` and `show-mind`: a bubble shows how a deed landed, a chime marks when mercy is likely, and `no-show-mind` hides the mind's answers for an A/B test.
- `clear-hp`: the foe's health sits over its head with a number and damage trail, its mood is named, and your bar shows an arrow as it moves.
- `reveal`: CHECK reads one clue at a time, likes and hates are learned by trying them, and monsters answer in their own words.
- `chat`: typed words fly to the monster, its reply gets its own box, and the info key keeps the talk so far.
- `boss-at-exit`, `flee-cost` and `boss-reward`: the champion holds the stairs, backing away has a cost, and beating or befriending a champion makes you stronger.
- `branching`: the stairs offer two seeded ways down to compare.
- `ambush`: a monster that catches you strikes first.
- `toll`: the gate on the third stairs drops unless someone holds its chain and stays, so you pay in health or leave a friend.
- `text-size`: a TEXT SIZE setting; the log and the speech box write larger wherever every line still fits.
- `mini-games`: DANCE, a light that moves on every beat and heals you if you are on it when the beat lands.
- `map-gen`: half of the undercroft's floors are long or tall instead of square.
- `branching` can offer a market stair, with a trader on the floor below.
- `roaming`: an alert sound when a monster sees you, a soft step when one in sight moves, and an arrow at its feet for the way it went.
- `clans`: monsters belong to clans that remember your deeds, later ones say so and start in a different mood, and Jev is told the history.
- `map-gen`: floors come in three biomes with their own generator (maze, authored chunks, caves), size up to 31x31, colours and monsters, with a scrolling automap.
- `secrets`: chests behind cracked walls that break when you walk into them, and pairs of pads that carry you across the floor.
- `items`: things lie about on the floors, and ITEM in a fight heals, sharpens, slips away or gives a gift a monster may love.
- `shop`: some floors have a trader who sells items for gold.
- `heavy-strike`: HEAVY in a fight, a faster line and a smaller mark for a harder hit that rocks and dragons take badly and slimes and snakes barely feel; a miss leaves you off balance.
- `close-camera` and `wide-view`: the camera stands nearer the middle of your cell, and the 3D picture fills the panel instead of keeping 448:288.
- `sprite-look`: the walk models take the outline and face of the fight sprites, so a monster looks the same in both views.
- `lurkers`: something stirs in plain sight on a floor, never on the only way through: walk round it, or walk into it for a fight and its purse.
- `npcs`: some floors have a monster with a request instead of a fight: fetch something, spare its kin, or get someone off the floor, and be paid for it.
- `roaming`: monsters take a turn each step you take, as who they are and how they feel say, the map shows where you last saw them, and backing out of a fight makes one hold still for a few steps.
- `boss-chase`: a champion you have seen comes after you, unless it is holding the stairs.
- `motifs`: Abdulla's FluidSynth motifs take turns with the exploring music if `tools/music/cut_motifs.sh` has put them in `build/motifs/`; `motif=N` tries one, and none of it ships.
- `achievements`: deeds worth keeping go up on the picture and stay earned across runs, with a page in the main menu.
- `legacy`: a run that ends leaves embers, which buy boons on a new main menu page that every later run starts with.
- `hunger`: walking wears on you until the walk stops healing and then costs health; Enter makes camp to eat, floors leave rations about and traders sell them.
- `butcher`: at camp a friend can become roasts, to eat, to sell to a trader who won't ask, or to feed to the others, who like you for it until one works it out, leaves and tells.
- `input-cooldown`: keys do nothing for a moment after a fight, and a key held from it stays dropped until pressed again.
- `smooth-fight`: your soul glides between squares in a fight, and the battle screen fades back to the halls.
- `tools/map_test.gd` checks 1000 floors per generator and logs what big floors cost, and `tools/map_shots.gd` takes pictures of them.
- `tools/features_test.gd` checks each feature, `tools/run_tests.sh` runs the suites with and without the features, and `tools/sim_recruit.gd` measures recruiting against killing.
- `tools/flicker_check.gd` measures flicker in the models frame by frame on the GPU, per species and distance, and marks the blinking pixels on a picture.

### Changed
- A run says who you are and why the Hoard threw you down, and the champions' lore names the clans; FLEE has a tip, and the TIPS setting also skips the slow first fights.
- Monsters answer a sad, frightening or strange deed in their own words too, and two names were changed (Vex read like Vexalith, Mellow like a trait).
- Each mini-game now lives in its own file under `src/rules/minigames/`.
- `Vision.sight` stops 12 cells away, so a big floor costs no more than the classic one.
- CI also runs `features_test` and every suite with `classic`, and `run_tests.sh` includes `audio_test`.

### Fixed
- A monster whose fight was tried again no longer leaves its old model standing on the floor.
- Monster lines no longer break into crawling dots where a part sits close in front of another: the ink spreads across the view only, the bandit's face is drawn on it, and the snake's head stands clear of its hood.
- The snake's tongue slides in and out instead of blinking on and off.
- A monster's name no longer hangs over a wall when only the far corner of its cell is in line and the monster itself is hidden.
- Holding a key against a wall lunges at it once, instead of about six times a second with the bump sound each time.
- `audio_test` no longer fails on the kinds of line that have no recording yet: they are named in `AWAITING_RENDER` until `tools/voices` renders them.

## [0.6.1] - 2026-11-03

### Added
- `tools/menu_test.gd`, `tools/saves_test.gd`, `tools/gameplay_test.gd` and `tools/view_test.gd` check the menus, the save slots (including `nosave`), the views after a new floor or a load, and the 3D view; CI runs them.
- `tools/test_base.gd` holds what the test scripts share, including a timeout that stops a hung test with a failure.
- `Dice` (`src/utils/dice.gd`) is the one source of interaction chances: the slice pins it, and `Odds` and `Allies` take a Dice, not a Rng, so a draw cannot go around the fixed roll.
- `Dice.pin` refuses a roll outside 0 up to below 1 (or NaN), reports it and returns false; `Rng.real()` never returns 1.0.
- A test scan of every script under `src` finds a Dice made outside the flow, a chance rolled from `flow.rng`, and a copy of the game's rng.
- Hover or tap the foe, an ally or the automap for details (key `I` cycles them): the foe's feelings and the last two questions its mind answered, an ally's charm, mood, loyalty and what it cares about, and the map's legend. These were lost in the rewrite.
- A touch pad (arrows, INFO, BACK, OK) on touch devices or with the `pad` flag; clicking the picture strikes and starts the run; hovering a command picks it and shows its help.
- An autosave when a floor starts, and "Saved to slot N" and "CAN'T LOAD" lines.
- Eight named palettes, picked per run from the seed and saved with it (older saves still load).
- The `nomusic` and `nosfx` flags, a Master limiter, a room reverb and music ducking under recorded voices.
- `tools/rules_test.gd`, `tools/network_test.gd` and `tools/audio_test.gd`, plus the Worker tests in `proxy/worker.test.js`; CI runs them and checks that CREDITS ships.
- `README.md`, `AGENTS.md`, `docs/GAME.md`, `docs/DEVELOPMENT.md`, `docs/AUDIO.md` and `docs/ARCHITECTURE.md` again, rewritten for the 3D game alone, with new pictures.
- `State.turn` counts quarter turns, so the camera knows which way the player turned.

### Changed
- A fight ends in the log and back to walking: the CONTINUE screen and its state machine step (`result`) are gone.
- The personality slice goes straight from ROOK to VEX; the log keeps one line, the verdict on ROOK's fight, so VEX's greeting and fight rule still fit.
- A slice whose fixed roll cannot be pinned does not start, and is not tried again.
- Saves are numbered (`seq`, one above every save on disk, read at each write) and Continue offers the highest, so a second window cannot make it offer an older save.
- `saved_at` stays the real clock time, so a clock set forward cannot date new saves in the future.
- The saves log shows each save's number and which slot Continue chose; the number is one above the highest on disk, so there is no counter to keep in step.
- A named save is labelled alike on the list, its page, COPY TO and the REPLACE question (the slot and its name in capitals).
- A long save name is cut off before the date whether or not its row is picked; save dates show no arrows, only settings do.
- The automap also marks where a monster stands once you see it, so it agrees with the 3D view.
- Sound effects are rendered at 44.1 kHz from the 3D scene's recipes again, with per-play variation, a polyphony cap and a prewarm spread over frames.
- The battle theme is random and never the last one, and the exploring music rests between stretches, with the fades and track levels it had before the rewrite.
- A monster's line with no recording uses the synth voice for its species, and a stage direction stays silent.
- The champion stands at scale 0.92 again, so it no longer pokes through the ceiling.
- Builds use the custom web page again, and settings saved under the old `donjon.settings` key are taken over on first read.
- `debug` keeps the mind panel open, and `floor=` is described as what it does (the label and the colours).

### Fixed
- A monster is in view when it is in front of you with nothing in the way: down a corridor however far, across a hall, off to one side.
- The champion in its hall was missing from the view because only monsters straight ahead within six cells were drawn.
- The automap learns the whole corridor ahead, to the wall.
- The log measures a speaker's line the way it draws it (wrapped after the name), so a line is no longer cut off that was counted as fitting.
- A turn no longer hides a monster that is still in the picture while the camera swings.
- Holding LEFT or RIGHT keeps the camera turning that way, instead of shaking left and right.
- Several turns in one slow frame still turn the camera the way they went.
- The snake's eyes, the slime's mouth and the rock's crack were buried inside their bodies and never showed.
- The allies' names at the bottom of the view sit on a dark box, so a wall line no longer runs through them.
- A random run's printed seed is never negative, and `seed=` takes any whole number from 0 to 9223372036854775807, so every printed seed replays.
- A bad, bare or oversized `seed=` gives one warning that names the fallback (autoplay too), and `seed=-0` is seed 0.
- A key hint longer than the menu panel wraps instead of being cut off; the settings hint is shorter too.
- NEW FLOOR and a loaded save point the header, status row, dock and overlay at the new state (the same `state_replaced` event), instead of leaving them on the old one.
- The slice fixes every outcome roll (the feeling a hit or question stirs, mercy, joining, an ally's verdict, whether it leaves, a recruit's starting loyalty).
- Fleeing judges the allies before it ends the slice, and `mock` no longer swaps its local rules, so the same actions give the same results.
- `nosave` keeps the save slots in memory (saving, loading, renaming, copying and deleting included), and DATA no longer offers OPEN SAVE FOLDER under it.
- The credits no longer repeat the CREDITS heading.
- The slice's bandits are built from the roster's own bandit line; a retry no longer saves a HP value it never used.
- Monster models are back at full detail (slime 1308, bandit 1572, snake 2384, rock 762, dragon 2356 triangles) with each species' own movement; far monsters stay readable and name tags stay sharp above each model.
- The camera glides in fixed time (step 150 ms, turn 170 ms), lunges on a wall bump, and held-key repeats wait for it (#20).
- Every monster stands on the set and walls hide it, so nothing pops in or out; the map learns cells from the camera's field of view (#20).
- The automap is crisp, outside the post-processing, with wall lines, monster dots (they had zero size), the champion in red from the start and a ring on the stairs (#20).
- The stairs are a pit with funnel rings and an accent rim, decor is real 3D at 32% density, torches flicker in a flame shader, and the background is black.
- Post-processing is restored: 4x MSAA, sharp scaling, thresholded bloom under the `crt` setting, radial colour split, a red hurt edge, danger desaturation, a pulse that decays with the beat and additive flashes; the floor's accent returns after a fight.
- Fights have their staging back: the encounter flash, the gold "(MERCY 50%+)" by the name, a visible time bar, the lantern's orbit and glow, falling goo, warnings that ramp up and the CHARMS list.
- The HP bar has its border and turns red under 40%, and the title card has its blinking prompt and receding frames.
- ACT results, a refused cut and FLEE make their sounds (they were silent and logged an error), a critical strike sounds like one, and the fight menu's cursor ticks.
- Victory plays on every win, and the fanfare at the stairs and not on a champion kill; the sting fades the loops, and an old fade can no longer stop a reused music player.
- Recorded monster lines match the voice bank (560 of 590 spoken roster lines; stage directions and braces had broken the lookup).
- Digits, the numpad, right-click, PgUp/PgDn and Esc in RENAME work in the menu pages; Esc leaves the route screen; the title card ignores modifier-only keys; long command help wraps.
- A bad save is refused with a message, never a script error, and its values are clamped; a failed load from the pause menu keeps the menu open.
- A proxy with no key is not retried and counts as down at once, a THINKING mark shows while a mind call runs, Jev gets mercy and pressure in one request, and starting a run can no longer race the mind.
- `!!!!!!` counts as one noise cue again, and `assets/CREDITS.txt` ships in every build, so the Credits page is no longer empty.

## [0.6.0] - 2026-11-03

### Changed
- Rewrote the game from scratch as a menu scene and a gameplay scene, with the stages as one state machine and a transition table.
- Monsters think through one mind interface: local rules, a seeded random mind, or Jev through the proxy with the local rules as fallback.
- All network traffic goes through one manager with a shared timeout, retries and a short offline period after repeated failures.
- CI imports the project, plays whole games headless, checks the personality slice, and builds four platforms with `tools/build.sh`.

### Added
- A seeded personality slice (`-- personality-slice seed=7042`) pairs two bandits, ROOK and VEX, with different clues and reactions, plus a participant checklist in `docs/PERSONALITY_PLAYTEST.md`.
- `tools/slice_test.gd` checks the slice headless: its routes, what ends it, the retry, the autosave rule, the seed and the mind.
- Every new monster has an individual motive (proud, jumpy...) that shows in CHECK and the tooltip and shifts its reactions, mercy and recruiting.
- Questions can reveal a stair direction, another monster's aversion and clue, or the champion's opening, depending on personality.
- The run starts with 8 gold, enough for one 6-gold fair cut; acceptance stays uncertain and a refusal keeps the gold but costs a turn.
- Restored `tools/godot-mcp/` (pinned Godot MCP 0.1.1), so the `godot` server in `.mcp.json` starts again.

### Fixed
- The slice's floor is never autosaved, so it no longer overwrites your earlier run in the AUTO slot.
- Trying a fight again starts at full HP, so a retry after a low-HP first fight can no longer loop forever.
- The slice always uses the local rules, and `seed=-5` or `seed=abc` fall back to 7042 instead of a random or zero seed.
- With the flag on, MAIN MENU shows the real menu instead of restarting the slice, and the title card is skipped like `meet`.
- The second slice fight is the queued VEX, not whichever monster shares his name.

### Removed
- The speech helper (hold to talk), the old test suites, the original Donjon code and the old JS-port helpers.

## [0.5.3] - 2026-11-02

### Added
- Genre Halls has the music again: the dungeon loop while walking, a battle loop in each fight, the victory sting after one and the fanfare at the stairs, as in the original Donjon (`nomusic` turns it off).

## [0.5.2] - 2026-11-01

### Changed
- README shrunk to the pitch, the run commands and the key table; the rest moved to `docs/GAME.md`, `docs/DEVELOPMENT.md` and `docs/AUDIO.md`, and `AGENTS.md` added for coding agents.

### Fixed
- Genre Halls monsters no longer vanish down a corridor: what you can see is what the 3D camera sees (its field of view and a clear line over the floor), not the old six-cell rule, every monster on the floor stands in its cell (walls hide the ones you can't see), their lines fade only down to 55% with distance, and their name tags are real 3D text above their heads (walls hide them like the monster, the view's edge cuts them), fade with distance and give way to a nearer monster's tag. The automap reveals what the camera saw.

## [0.5.1] - 2026-11-01

### Changed
- Genre Halls walks in the 3D set: the camera glides cell to cell and bumps walls, torches light the corridor, and the monsters you can see are 3D models standing in their cells with their genre over their heads. Fights stay the flat battle screen; the `flat` flag keeps the old 2D corridor.

### Added
- QUIT GAME on the pause menu (it asks first), and the main menu's Quit is now called QUIT GAME; neither shows in the web build.

## [0.5.0] - 2026-11-01

The dungeon is 3D now, drawn as the 2D line art it always was ("3渲2").

### Changed
- The game starts in the main menu, not in Genre Halls; Esc on Genre Halls' title or route screen goes to the menu instead of the original Donjon, which stays behind the `main` flag.
- **The view is a 3D set drawn as the wireframe.** Walls, floor and ceiling are built from each floor's map (`src/view/dungeon3d.gd`), and the six monsters are models made of simple shapes (`src/view/monsters3d.gd`). Shaders fill every surface black and draw only lines, the way the 2D view did: every wall face outlined in the floor's wall color, each monster in its own color (red champions, gold shinies), the dots and slits filled in, lines dimming with distance exactly as before, torches glowing on the walls with flickering accent flames, the same decorations on the same walls, the stairs as a pit with accent steps. The vector-monitor shader is unchanged, so it glows the same.
- **Moving is a camera move**: a step glides, a turn swings round, walking into a wall lunges at it (same timings as before). When a fight starts the camera backs off and looks down a little, and the monsters stand in the corridor in front of you, two or three in a V; their names, health bars, dice and floating numbers stay 2D, drawn over them.
- **The floor's red champion stands in its hall**, turned toward you, so you can see it from anywhere down a corridor, not only straight ahead.
- The title card is over a torch-lit 3D hall.
- Genre Halls keeps its 2D drawing (the same look).

### Added
- **A main menu** as the startup scene (`src/menu/`): Continue, New Game, Load Game, Save Manager (copy, rename, delete), Settings, Credits, Quit (not on the web). Esc while walking or in a fight's command menu opens a pause menu: resume, save, load, settings, main menu.
- **Settings** kept in the game's saved data and applied at once: window mode, vsync and frame-rate cap, the CRT glow, calm hits, screen shake, sound effects and volume; a Data page resets them, opens the save folder and deletes saves.
- **Saves** for Genre Halls: an autosave whenever you are back to walking, six slots from the pause menu, one file each in `user://saves/`; Continue loads the newest. A fight in progress isn't saved.
- `cli/menu_shots.gd` (screenshots of the menus) and tests for settings, saves, the menu pages and saving in Genre Halls.
- `cli/stage_shots.gd`: screenshots of the 3D view through the shader at 2× (the title hall, corridors on four palettes, the stairs, the champion down a corridor, every monster in a fight, a shiny, a champion, a hurt one, groups, boxed in by walls, danger).
- Tests for the 3D view (`tests/view/test_dungeon3d.gd`, `test_monsters3d.gd`, `test_stage3d.gd`): wall faces, the stairwell, decorations in the wall color, torches, mesh winding, every model's size, single color and movement, the camera's easing, the fight camera and where monsters stand, the champion, the torches' glow, line widths, the title hall.
- **Hold Space to talk in the desktop builds**, on your own computer with nothing sent anywhere: NVIDIA's Nemotron Speech Streaming model (English, 160 ms chunks, int8) in a small helper program on sherpa-onnx 1.13.8 (`native/asr/donjon_asr.c`), which the game runs and streams the microphone to (`src/audio/asr.gd`). The model is a one-time 662 MB download (pinned, SHA-256 checked) that the first hold of Space offers and the next starts. Each desktop build carries its own helper (Windows x86_64, macOS universal, Linux x86_64). The web build keeps the browser's recognizer.
- **Pluggable monster voices** (`src/audio/tts_engines.gd`, `tts_config.gd`): rendered voice banks in `assets/voices/` (CosyVoice3, the Feiyu stack's engine, and Qwen3-TTS; the banks themselves follow), a Feiyu voice service or a Qwen3-TTS service on your network synthesising lines as they're said (`config/tts_config.json` or `.env`), and the system's voice as before. The Feiyu service is only used with a voice of our own named, never its default Feiyu voice library. Flag `tts=<voice>` starts with one.
- `cli/voice_lines.gd`: every line a monster can say aloud (322, `{name}` filled in), for rendering a bank.
- `native/asr/build.sh` builds the helper (Linux, Windows cross-compiled with mingw-w64, macOS) and fetches the model; `native/asr/smoke.py` runs it on recordings. CI builds the three helpers and runs each on its own system, and the tests run the real recognizer through the game's code.
- Tests: `tests/audio/test_asr.gd` (13) and `tests/audio/test_tts_engines.gd` (13).
- **Two voice banks**: all 322 lines, rendered ahead in each monster's own voice, cloned from Creative Commons recordings (LibriTTS-R, CC BY 4.0): `assets/voices/cosyvoice3/` (CosyVoice3, the Feiyu stack's engine) and `assets/voices/qwen3/` (Qwen3-TTS), the same reference voice per monster in both. **L** steps between them.
- `tools/voices/`: `render.py` (a bank from the line list, on CPU or through a Feiyu / Qwen3-TTS service, with retakes for clipped or runaway takes, shaping, loudness and Ogg), `check.py` (plays a bank into the game's own speech recognizer and reports what it heard), the engine scripts and the reference clips. `tests/audio/test_voice_banks.gd`: every bank has every line, and every file is a sound of a sensible length.
- Godot MCP (github.com/Coding-Solo/godot-mcp, 0.1.1) for AI agents, in Claude Code (`.mcp.json`) and Codex (`.codex/config.toml`): both start it through `tools/godot-mcp/run.sh`, which installs the pinned package with `npm ci` on first use. Agents can run the game, read its output and edit scenes.

### Fixed
- Monsters diagonal to you, down a side opening, are drawn in the corridor view (only the one straight ahead was).
- Letting go of Space right after your last word no longer cuts it off ("Insolent morsel" came back "Insol"): the speech helper listens half a second past the end before it finishes. `native/asr/smoke.py` checks it, and paces its spoken test by the clock.
- Talking before listening has started no longer loses your first word ("Know your place" came back "Your place"): the helper starts each utterance with 0.3 s of quiet. `smoke.py` checks it on `native/asr/testdata/know_your_place.wav`.

### Changed
- The game starts in the main menu, not in Genre Halls; Esc on Genre Halls' title or route screen goes to the menu instead of the original Donjon, which stays behind the `main` flag.
- **L** steps through the voices this build has, then off (with only one, it's on and off as before), and the choice is kept.
- The macOS build asks for the microphone (it has the usage description and audio-input entitlement). Godot's microphone input is on in every build but the web one.
- Genre Halls fills the window as one framed screen with far less text (Pear's playtest): the view scales to the free space, the sidebar (automap legend, party, Jev mind) is gone, and the text box under the view holds an HP bar, a three-line log and the commands, at a fixed height so the view never resizes.
- Help moved into tooltips: a command's help on hover (SPARE turns gold when it would work, and its tooltip explains allies and charms), an ally chip's charm and loyalty, the monster's mind (what it seems like, feelings, last two answers) when you hover it in a fight, and the automap's monster colors. The highlighted command shows its tooltip when you use the keys.
- The automap loses its title and legend and sits in the view's corner while exploring; it steps aside in a fight. Opening and exploring messages are shorter.
- The game opens in Genre Halls (`run/main_scene` is `genre_halls.tscn`, so `godot --path .`, the exported builds and the web page start there). The original Donjon is Esc on the Genre Halls title card, or the new `main` flag (`godot --path . -- main mock floor5`); the title card now says so.

## [0.4.0] - 2026-11-01

### Changed
- Genre Halls fills the window with a fixed-height text box, HP bar and tooltips, and monsters diagonal to you are drawn.
- The game opens in Genre Halls; Esc on its title reaches the original Donjon.

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

<!-- No v0.5.3 tag exists yet, so that version has no compare link; add it when the tag is cut. -->
[Unreleased]: https://github.com/game-design-projects/final-project/compare/v0.7.0...main
[0.7.0]: https://github.com/game-design-projects/final-project/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/game-design-projects/final-project/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/game-design-projects/final-project/compare/v0.5.2...v0.6.0
[0.5.2]: https://github.com/game-design-projects/final-project/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/game-design-projects/final-project/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/game-design-projects/final-project/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/game-design-projects/final-project/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/game-design-projects/final-project/releases/tag/v0.3.0
[0.2.1]: https://github.com/game-design-projects/week4-jev-game-ai-by-Aalfalasi/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/game-design-projects/week4-jev-game-ai-by-Aalfalasi/releases/tag/v0.2.0
