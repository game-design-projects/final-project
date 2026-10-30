# Donjon

![Donjon cover: an orange slime waiting down a torch-lit wireframe corridor](docs/donjon-cover.png)

A Wizardry-style wireframe dungeon crawler with roguelike runs. You can talk to the monsters, SMT-style. Every enemy decision comes from **Jev**, TypeSafe's System One model: what your words meant, whether it fights, flees, haggles or joins you, who it attacks, and what it says. Monsters you befriend join the party. They judge what you do and may walk out, or turn on you, mid-run.

Donjon is a Godot 4.7 project (GDScript). It runs in the browser, on Windows, on macOS and on Linux. How the code is laid out is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); changes are listed in [CHANGELOG.md](CHANGELOG.md).

**Contents:** [What you get](#what-you-get) · [Run it](#run-it) · [Playing](#playing) · [Setting up Jev](#setting-up-jev) · [Run flags](#run-flags) · [Platform differences](#platform-differences) · [Building and publishing](#building-and-publishing) · [Tests](#tests) · [The rules](#the-rules) · [The monsters](#the-monsters) · [Genre Halls](#genre-halls-undertale-style-battles) · [How Jev runs it](#how-jev-runs-it) · [Music](#music) · [Debug mode](#debug-mode-developers-only) · [Coming from the browser version](#coming-from-the-browser-version)

## What you get

- **Monsters that listen.** In a fight you press T and say what you want. Each monster hears it, decides how it feels (delighted, offended, terrified, in stitches...), and acts on that: a joke can leave a slime too busy laughing to fight, flattery lowers a dragon's guard, a threat can make a goblin drop its gold. Every species likes and hates different things, so what works on one fails on another.
- **A party that grows.** Ask a monster to join and, if it likes you enough, it does. Up to three monsters travel beside your three adventurers. They fight on their own, they have values, and they react to what you do afterwards: kill a monster that was begging for mercy and the slime in your party notices.
- **Promises that count.** Swear a vow to an ally (*I WON'T KILL SLIMES*) and the game checks it against everything you do. Break it and the ally forgives you, leaves, attacks you or steals your gold.
- **Real dice.** Combat follows D&D 5e, simplified. Every roll shows in the log in words, and d20s tumble across the view. Spell slots, death saves, advantage, critical hits, levels.
- **A run worth restarting.** Floors are new mazes every time. Every flight of stairs earns a Roll of Fate (a random boon that stacks), every fifth floor has a red champion, and death is permanent.
- **It looks and sounds like a place.** Wireframe corridors in true perspective run through a shader that makes the lines glow like an old vector monitor. The screen drains of color, closes in red and starts a heartbeat when the party is dying. The music is original baroque dungeon music; every sound effect is synthesized.
- **Genre Halls.** A side mode that pitches Undertale-style battles on the same dungeon: each faction attacks in its own genre (goo rain, chess, shadow, rhythm).

## Run it

You need [Godot 4.7.2](https://godotengine.org/download). From the project folder:

```bash
godot --headless --path . --import   # once, and again after adding files or assets
godot --path .                       # play
godot --path . -- mock               # play on mock Jev: no key, no credits
```

With no Jev key, the monsters run on **mock Jev**: random but well-formed answers, so everything works, but the monsters act at random instead of sensibly. The game says so in the log when that happens. [Setting up Jev](#setting-up-jev) puts a real key in. Everything after `--` is a [run flag](#run-flags).

Prebuilt web, Windows, macOS and Linux builds come out of CI: every push has them as workflow artifacts, and every `vX.Y.Z` tag becomes a [GitHub release](https://github.com/game-design-projects/final-project/releases) with all four zips. They carry no key; they reach Jev through a Worker that holds it. See [Building and publishing](#building-and-publishing). The web build opens from a web server only, not by double-clicking `index.html` (the page tells you; `python3 -m http.server` inside the unzipped folder is enough).

## Playing

| Where | Keys |
| --- | --- |
| Exploring | ↑/W forward · ↓/S back · ←/A and →/D turn · **C** camp (long rest; may be ambushed) · **E** talk to an ally · **V** make a vow to an ally · **B** boons · **M** map |
| Combat | **F** quick attack: everyone does their usual move at once (weapons; the wizard's free Fire Bolt; no spell slots) · **C** choose moves: pick each adventurer's action one by one (attack, Second Wind or Action Surge, or any spell they have slots for) · **T** talk (everyone hears) · **R** recruit the target · **G** give gold · **V** vow to the target · **E** escape · **1–3** pick target |
| Menus | ↑/↓ (or W/S) move the highlight, ←/→ jump columns, **Enter** picks it · **1–9** and **0** pick directly · **Esc** goes back |
| Anywhere | hold **Space** to talk · **K** achievements · **H** tips off / back on from the start · **P** music on/off · **O** sound effects on/off · **L** voices (monsters read aloud): the next voice, then off · (**J** Jev mind panel, debug runs only) |

Keys pressed with Cmd, Ctrl or Alt are left to the system. On the title card, any key starts the game and **G** opens [Genre Halls](#genre-halls-undertale-style-battles). Every key on the screen is also a button: click it.

**The screen.** The top line says where you are: the floor, the way you face (or that you're in a fight), gold, boons, and the switches as keycaps with pixel icons (H tips, J Jev panel in debug runs, K achievements, L voices, O sound, P music; slashed red when off, hover for what they do). Beside the view sit **the party** (top), your active vows (bottom) and the log between them; monster allies get one line each under an "ALLIES 2/3" count (the party holds six: your three adventurers and up to three monsters). The automap sits right under the view with a small key (you, stairs down, the champion), and steps aside in a fight. Everything you can do sits in the **command dock right under the view**, as keycap buttons: press the key or click the button. Hover a button to read what it does on the line beneath. When the game waits on you (a menu like CHOOSE MOVES' spell list, the talk box, "any key" after a Roll of Fate), the dock lights up in the floor's color, and a key it doesn't take shakes it instead of vanishing. The window can be any size: the screen lays itself out for 1180 × 820 and scales or rearranges from there.

**Questions wait where you're looking.** When the game needs a yes or no (stairs down, Revivify, a monster asking to join), a box lights up over the view in the floor's accent color with clickable answers. **Y**/**Enter** says yes, **N**/**Esc** no, and any other key shakes the box so you can't miss it. At the stairs you can simply walk away.

**The party panel** reads at a glance, mostly without words. While you choose moves, the member choosing glows with a ▶; while you pick who to heal or revive, the one highlighted in the menu lights up here too:

- **Health** is a segmented bar: its length and color say how hurt someone is (green healthy, yellow HURT, red CRITICAL). At 0 it reads DYING (blinking) with their death saves as boxes, three green for successes and three red for failures; STABLE once three succeed; the dead get a skull and a struck-through name.
- **Armor** is a shield with the number an attacker has to reach.
- **Spells** are pips, one per spell slot, colored by circle (blue first, violet second, gold third); lit pips are left, hollow ones are spent. The fighter's two pips are Second Wind and Action Surge. In the CHOOSE MOVES menu each spell shows the same colored pips for the slots it would draw on, or FREE.
- **Status** chips pair a pixel icon with a word: POISONED (droplet), ENTANGLED (chain), KNOCKED DOWN (arrow), an ally's loyalty (heart: DEVOTED, CONTENT, UNEASY, RESENTFUL, MAY LEAVE), its talk buff (PUMPED, BOUNCY, ...) or mood. Monsters in a fight wear the same icons over their health bars (ASLEEP, PARALYZED, ENRAGED, SCARED, VETERAN, ...).

Hover any of them for the details (exact numbers, ability scores, boons).

**Monsters answer out loud.** Monsters and allies read their lines aloud, each kind in its own voice (a deep, slow dragon; a squeaky slime), skipping the *stage directions*. It starts off, and turns on by itself the first time you talk to the game with your voice: someone speaking to the monsters wants to hear them answer. **L** steps through the voices this build has, then off, and the game keeps your choice:

- **Rendered ahead**, when the game has a voice bank in `assets/voices/`: every line in the game spoken by an open text-to-speech model, one bank per model (`cosyvoice3`, the engine of the Feiyu stack, and `qwen3`), each monster's voice cloned from a Creative Commons recording. A bank plays instantly and sounds the same on every machine. A line that names someone (*"You side with them, ROLF?"*) isn't in it and goes to the next voice. How they're made: [tools/voices/README.md](tools/voices/README.md).
- **A live service** on your network, when one is set up: a Feiyu voice service or a Qwen3-TTS service synthesises each line as it's said. Any line, a second or more to start (they need a good GPU). See [Voices](#voices).
- **Your system's voice**: the macOS, Windows or Linux speech engine, or the browser's on the web; each monster gets its own pitch and pace.

The keycap only shows when there is at least one. Speech can't be turned up past full volume, so while a monster talks the music drops to a quarter and the effects to half, then come back as it finishes. It goes quiet while the microphone listens, and drops a backlog rather than falling behind the fight (`src/audio/tts.gd`, `tts_engines.gd`).

**How it looks, sounds and feels.** The view runs through a shader (`src/view/postfx.gd`, `postfx.gdshader`) that makes the wireframe glow like an old vector monitor: lines bloom, the pixels stay sharp at any window size, faint scanlines follow the game's own rows, and each floor's accent color tints the dark. Game state drives it, along with the music and the shake, through one event bus (`src/rules/juice.gd` `FX_EVENTS`): the rules announce hits, kills, falls, steps and fights, and the presentation answers.

- **Danger** (`danger_of`: how much health the living have left, and whether anyone is rolling death saves) drains the color, closes in a red edge, muffles the music behind a low-pass filter and starts a heartbeat on the music's beat: every other beat while hurt, every beat when someone is about to die. The red edge pulses with each heartbeat, timed from the audio clock.
- **Hits** shake the screen in proportion to the blow (trauma that drains away, so small hits nudge and big ones rattle). Critical hits and kills freeze the monsters for a few frames and flash the view; getting hurt flashes the edges red. Big moments dip the music for an instant so they punch through.
- **Moving** eases: a step dollies the old view past you, a turn pans, a wall bump lunges the view at the wall.
- **Sound**: music and effects share one mixing desk (`src/audio/mix.gd`: Godot audio buses, ending in a limiter). Repeated effects (hits, misses, coins...) get a random detune and volume each time, and at most a few copies of one sound start at once (`src/audio/sfx.gd` `VARY`, `POLY`).

The `nofx` flag turns the shader off: the plain view shows, and everything else works the same. When the browser reports prefers-reduced-motion (web build only; see [Platform differences](#platform-differences)) the game turns off the shake, the step and turn transitions, the pulsing glows and the blinking, and tones the flashes down.

**Hold Space to talk.** Instead of typing, hold **Space**, say it, and let go: the words fill the talk box as you speak and are sent when you let go. In a fight it talks to the monsters (like T); exploring, it talks to a monster ally (like E; pick one first if you have several); with a talk box already open and empty (after T, R or E) it just listens. A quick tap of Space is still an ordinary key, and with words already in the box Space types a space. With a mouse or a finger, press and hold the **HOLD TO SPEAK** button beside the box.

- **Desktop builds** hear you on your own computer, with nothing sent anywhere: NVIDIA's Nemotron Speech Streaming model (English) running in a small helper program the game carries (sherpa-onnx). The model is a one-time **662 MB download**: the first time you hold Space the game offers it, and holding Space again starts it (keep typing meanwhile; the log says when it's done). It loads in a few seconds the first time you speak in a session, and uses about 1 GB of memory while the game runs. macOS asks for the microphone once.
- **The web build** uses the browser's speech recognition (Web Speech API: Chrome, Edge and Safari; Chrome sends the audio to Google's recognizer, Safari to Apple's), in the browser's language, and asks for the microphone the first time. In Firefox the button hides and Space is an ordinary key: type instead.

The logic is `src/audio/voice.gd`, and `src/audio/asr.gd` for the desktop recognizer.

**Achievements.** Thirty of them, for what makes this game itself rather than for grinding: words that leave a monster DELIGHTED or IN STITCHES, a fight won without a single attack, your first ally, a shiny, three monster allies at once, a vow carried down the stairs (or broken and forgiven), a natural 20 while talking, a death save that pulls someone back up, floors 5 and 10, a red champion slain or talked down, a legendary boon. Five are secret and read **???** until you stumble on them. When you earn one, a gold note slides down over the top of the view with a short jingle (the **O** toggle mutes it) and the log says so; it never takes a key or a click away from you. **K** (or the trophy keycap in the top bar, which also shows your count) lists them all over the view: earned ones lit in their group's color with the date, locked ones dimmed with what to do, and progress bars for the two that count up across runs (EMPATH, every feeling; MENAGERIE, every kind of monster). While the list is open it glows, **K** or **Esc** closes it, the arrows scroll it, and any other key shakes it. Achievements are kept across runs, deaths and restarts in the game's saved data (`donjon.achievements`, see [Platform differences](#platform-differences)). The list and its rules live in `src/rules/achievements.gd`; the game calls it from one-line hooks.

**Tips.** New players get one short hint at a time, the first time each thing matters: how to walk, the automap, the stairs, your first fight (and that you can talk), targeting, feelings, a monster warming to you, your first ally, camping when hurt, levelling up, someone going down, a champion's floor. Each shows once, in a framed note over the bottom of the view, and lights up what it talks about (the keys' buttons, the map, the party). It never blocks anything: your next key does its job and clears the hint, and a key that does nothing nudges it instead. **H** turns tips off; **H** again turns them back on from the start. Seen tips are remembered (`hallsOfJev.tipsSeen`, `hallsOfJev.tipsOff`). The hints and their wording live in `src/rules/tutorial.gd`. **Your first fight is a lesson**: one shy slime, and only TALK works (it glows, the rest wait, dimmed), then only RECRUIT, and the slime always says yes. It's how you learn that monsters here listen and can join you. It happens once (H off skips it; H back on replays it); every later fight is yours.

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
godot --path . -- mock debug         # mock Jev, debug mode
godot --path . -- floor5-debug       # start on floor 5, debug mode
godot --path . res://src/genre/genre_halls.tscn -- meet=rock   # Genre Halls, straight into a rock fight
```

| Flag | Does |
| --- | --- |
| `mock` | Jev is mocked (see [Setting up Jev](#setting-up-jev)) |
| `seed=N` | seeds the mock's answers, so a run repeats |
| `debug` | [debug mode](#debug-mode-developers-only) |
| `nodebug` | debug mode off for this run, even in a build that ships with it on |
| `floorN` | a **test run**: start on floor N (clamped to 2 to 30) with a party that got there, every member at level N, one Roll of Fate boon per floor cleared, some gold, fully rested |
| `nofx` | no shader: the plain view |
| `tts=<voice>` | start with that voice: `cosyvoice3`, `qwen3`, `feiyu`, `qwen` or `system` (see [Voices](#voices)) |
| `genre-halls` | open [Genre Halls](#genre-halls-undertale-style-battles) instead of the game |
| `meet=<species>` | in Genre Halls, jump into that faction's fight: `slime`, `bandit`, `snake`, `rock` or `dragon` |
| `nosound` or `nosfx` | Genre Halls without sound |
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

The runner finds every `tests/**/test_*.gd`, runs each `test_*` method, and exits non-zero on a failure. A script error inside a test (a bad index, a null access) fails that test too. Tests run on mock Jev and need no key or network; one, in `tests/audio/test_asr.gd`, runs the real speech recognizer on a recording when `native/asr/build.sh linux` (or your system) and `native/asr/build.sh model` have been run, and says it skipped otherwise; [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#testing) says how they are built. The Worker has its own: `node --test proxy/worker.test.js` (Node, nothing to install, the upstream is stubbed).

Scripts for looking at the game, in `cli/`:

| Script | Run | What it does |
| --- | --- | --- |
| `scenarios.gd` | `godot --headless --path . -s res://cli/scenarios.gd -- [filter] [--live] [--seed=N]` | scripted encounters, one monster at a time, then how its allies judge the fight |
| `social_scenarios.gd` | `godot --headless --path . -s res://cli/social_scenarios.gd -- [filter] [--live] [--seed=N]` | group fights, ally talk and vows |
| `shots.gd` | `godot --path . -s res://cli/shots.gd -- out=<dir>` | opens a window, plays the real screen on mock Jev, saves a screenshot of every state (title, exploring, a question, a fight, CHOOSE MOVES, the talk box, the Jev panel, the achievements list, the Roll of Fate, danger, game over, a tip, `nofx`, a small window) and fails on any script error |
| `view_shots.gd` | `godot --path . -s res://cli/view_shots.gd -- --out=<dir>` | the view modules alone: the title, corridors on three palettes, the automap, every monster (plus a shiny, a champion and a group of three), and the shader at two danger levels |
| `genre_shots.gd` | `godot --path . -s res://cli/genre_shots.gd -- out=<dir> [sound]` | Genre Halls: each faction's box, the mind panel, the strike bar, a route screen |
| `sfx_dump.gd` | `godot --headless --path . -s res://cli/sfx_dump.gd -- --out=<dir>` | renders every sound effect to WAV with a table of length, peak and RMS, to listen to or measure |
| `voice_lines.gd` | `godot --headless --path . -s res://cli/voice_lines.gd -- --out=build/voice-lines.json` | every line a monster can say aloud, for rendering a voice bank (see [Voices](#voices)) |

The scenario scripts use mock Jev by default (random answers, no credits, repeatable with `--seed`): that checks the plumbing and the game's rules, not Jev's judgement. `--live` calls the real API with the key from `.env` or `config/jev_config.json`: every call is billed, and each raw reply is saved under `user://jev-raw` before it is parsed. The three screenshot scripts open a window briefly (they are not headless); pass `out=` (or `--out=`), because their default folder is a scratch path.

### Godot MCP for AI agents

[Godot MCP](https://github.com/Coding-Solo/godot-mcp) is registered as the `godot` server for Claude Code (`.mcp.json`) and Codex (`.codex/config.toml`), so an agent can open the editor, run the game and read its output and errors, create scenes and add nodes, and refresh UIDs. It lives in `tools/godot-mcp/`, pinned in that folder's `package.json` and lockfile; `tools/godot-mcp/run.sh` runs `npm ci` there on the first start (and whenever the lockfile changes), then starts the server. It needs Node 18+ and the `godot` binary on `PATH` (or `GODOT_PATH=/path/to/godot` in the environment). To install it ahead of time:

```bash
npm ci --prefix tools/godot-mcp
```

Claude Code asks once whether to trust the project's MCP servers; approve `godot`. Codex loads `.codex/config.toml` only once the project is trusted (it asks on the first start here); `codex mcp list` shows the server, and it forwards `GODOT_PATH` when that is set. The server's own dependencies carry known `npm audit` advisories (an old pinned MCP SDK); it only talks to the agent over stdio, and nothing of it ships in a build.

## The rules

### D&D-style combat

The rules follow D&D 5e, simplified (`src/rules/dnd.gd`). Every roll is shown in the log, in words, e.g. `HORTENSE ATTACKS KRUNK: ROLLED 16 (ADVANTAGE) +5 = 21 VS ARMOR 12. HIT! 7 DAMAGE.` Saving throws read `ROLLED 9, NEEDED 15`, spell descriptions give damage as a range (`8-48 FIRE TO EVERY ENEMY`) rather than dice notation, and floors are FLOOR 1, FLOOR 2... in the game.

- **The party:** HORTENSE is a fighter (longsword, AC 16, Second Wind and Action Surge once per rest, a second attack at level 5). ROLF is a cleric (mace, healing and holy spells). EUGENE is a wizard (Fire Bolt and attack spells). Each has ability modifiers; hover a party row to see them. The game calls armor class ARMOR, hit points HEALTH and experience EXPERIENCE on screen.
- **Initiative:** each fight opens with a d20 roll for each side. Whoever wins acts first.
- **Attacks:** d20 + proficiency + ability against the target's armor class. A natural 20 is a critical hit and rolls the damage dice twice; a natural 1 always misses.
- **Advantage:** roll two d20s and keep the higher. You get it against monsters that are asleep, paralyzed, glowing from Guiding Bolt, or off guard from flattery. Disadvantage (keep the lower) comes from being poisoned or restrained, or attacking a monster that is dodging.
- **Spells use slots** on the 5e table (2 first-circle slots at level 1, up to third-circle spells at level 5). Cantrips are free and roll a second die from level 5. Camping restores slots.
  - Wizard: Fire Bolt, Magic Missile, Burning Hands, Sleep, Scorching Ray, Hold Monster, Fireball.
  - Cleric: Sacred Flame, Cure Wounds, Bless, Guiding Bolt, Prayer of Healing, Revivify, Spirit Guardians.
- **Saving throws:** area spells, Hold Monster and monster specials call for a save against a DC; a success halves the damage or avoids the effect. From FLOOR 3, monster specials also poison, entangle (restrained) or knock down (prone, losing your next action).
- **Death saves:** at 0 HP a member falls unconscious instead of dying. At the start of each of your turns they roll a d20: 10+ is a success and below 10 a failure (a natural 1 counts as two). Three successes stabilize them, three failures kill them, and a natural 20 brings them back with 1 HP. Any healing gets them up, and after a fight they come to with 1 HP. The dead can be brought back with Revivify, in a fight or while camping.
- **Camping (C)** heals every living member by half their maximum health, clears conditions and returns spell slots and skills. A cleric who knows Revivify offers to raise the dead (it costs a third-circle slot). One camp in four is found by a wandering encounter.
- **Monster allies** act on their own each round: an attack, or their species' special every few rounds.

### Talking always matters

- **Charisma checks:** when you talk, your best talker rolls Charisma. A strong roll makes your words land harder (up to ×2 on a natural 20); a natural 1 halves them.
- **Feelings:** every time you talk to monsters, pay them, or ask them to join, Jev picks how each one **feels**, and code gives every feeling a visible effect (`src/rules/emotions.gd`):

  | Feeling | Effect |
  | --- | --- |
  | DELIGHTED | won't attack this round |
  | IN STITCHES | too busy laughing to fight |
  | TOUCHED | its heart opens: it won't attack you this round, and if it likes you enough it asks to come along |
  | FLATTERED | lowers its guard: you get advantage against it |
  | INTRIGUED | lets slip a weak spot: +2 to hit it for the rest of the fight |
  | CONFUSED | loses its turn |
  | SADDENED | disadvantage on its attacks |
  | OFFENDED | +2 damage against you |
  | ENRAGED | advantage and +3 damage, but reckless (armor −3) |
  | TERRIFIED | disadvantage on attacks, and it drops gold |

  Each feeling also moves its friendliness, anger or fear. You never see those numbers: you read the mood the way you would at a table, from what it says and how it moves. The log narrates a tell for every feeling ("Grak lets its big ears droop."), and when a monster changes sides ("the fight has gone out of it", "You've made an enemy").
- **Recruit (R):** ask your target to join, with or without words. Your talker rolls Persuasion against a DC set by how much it likes you, how angry it is, and whether it is losing. A convincing or irresistible pitch brings it up to the point where it would consider joining; a close, clumsy or disastrous one only nudges (or sours) its mood. Then the monster answers in character, and the log always says why, so what it seems to feel and what it does agree:
  - *"Grak grins, showing crooked teeth, but grunts that it won't leave Snag."* (likes you, but won't abandon its brother)
  - *"Glop still quivers a little, but burbles that it won't be alone down here anymore."* (unsure of you, but comes anyway)
  - *"Drip wobbles from side to side and burbles that it didn't like how you asked."* (a botched pitch to a friend)

  Reasons to refuse: it doesn't know you well enough yet, wants more first, is still angry, didn't like how you asked, won't leave the others with it, is too proud, won't leave its home, is afraid of what lies deeper, or you let it down before. Reasons to come: it likes you, respects your strength, wants gold and loot, is lonely, wants to be with its kind in your party, feels safer with you, is curious, or is grateful. Winning a monster over, or letting it leave in peace, gives half its XP.
- **Ally talks (E)** always have a result, by how your words land (0–4): it sulks and sits out the next fight, gets distracted (−2 to hit), feels steady (+1 to hit), gets its species buff, or is inspired (buff, full heal and a level).

### Floors and champions

- **Complexity grows as you descend.** FLOOR 1 is a small maze with lone slimes and goblins. FLOOR 2 brings pairs, bandits and snake people; FLOOR 3 groups of three, rock entities, and specials that inflict conditions; FLOOR 4 dragons and wider halls (a floor's maze grows two cells a side per floor, from 15 up to 25); FLOOR 6 on, veteran monsters (more health, sharper attacks). Each new rule is announced when you arrive.
- **Every 5th floor** has a 5×5 hall at its heart with a **red champion** in the middle, marked red on your map and visible down the corridor. It is a normal monster of its kind but far harder: about 2.2× the HP, two attacks a turn, a faster special, better saves, and Legendary Resistance against the first two Sleep or Hold spells. You can still talk to it and recruit it, though it takes more to impress.
- Killing it, winning it over, or talking it into leaving earns a **Great Roll of Fate**: a boon at double strength, with a 60% chance of a legendary one (PHOENIX FEATHER, LEGENDARY ARMS, ARCHMAGE'S CROWN, TITAN'S BLOOD, TWIN SOUL). It's optional: the stairs are elsewhere.

### Roguelike progression

- **Roll of Fate:** every time you take the stairs down, you roll one random boon. Its strength scales with the floor you just cleared, and boons stack. The pool:
  - WHETSTONE: +12% damage per floor of depth, multiplying with earlier ones
  - KEEN EYE: crit on a wider range (19–20, then 18–20, down to 15–20)
  - TRUE AIM: + to hit
  - FLURRY: strikes per turn go 1× → 2× → 3× → 4× → 8×
  - IRON SKIN: higher AC
  - VAMPIRIC EDGE: heal a share of damage dealt
  - ARCANE SURGE: a caster gets more spell slots and stronger spells
  - VIGOR: max HP for the whole party
  - GOLDEN TOUCH: more gold from monsters

  Press **B** to list your boons, or hover a party row to see that member's stats.
- **Balance:** monster HP grows 1.3× per floor and damage 1.1× per floor. Armor and to-hit creep up slowly, as in 5e, so your dice keep mattering.
- **Levels:** each party member earns XP and levels up on their own, gaining HP, proficiency, spell slots and new spells, as in 5e. Recruited monsters join at the current floor's level.
- **The view** (`src/view/render.gd`) is a true perspective projection of the maze, six cells deep: walls are painted far to near so nearer ones hide what's behind, side passages open into the rooms and halls that are really there, and lines fade into the dark with distance. The automap fills in only floor you have actually seen, and draws the walls beside it as lines.
- **Floors:** each one gets a random color theme (Bone Crypt, Blood Vault, Frost Warrens and others). Walls carry torches that flicker and glow, chains, banners, barred windows, skull niches and cracks. Placement is seeded per floor, so decorations stay put as you move.
- **Sound effects** (`src/audio/sfx.gd`) are synthesized by the game, with no sound files: hits, crits, misses, kills, spells, heals, dice, feelings, joins, level-ups, and the Roll of Fate's ticking spin and landing fanfare. Each is a recipe built from tones, filtered noise and a formant voice (`src/audio/synth.gd`), rendered once into a sample while the game starts and played from there.

### Groups, ally talks and vows

- **Groups.** You can meet 1–3 monsters at once, possibly of different species, and one Jev request decides all their moves each round. Monsters see which side the others are on. When one warms to the party, the rest hear it "sided with the party against them", and a hostile monster may club the turncoat. A friendly monster that gets attacked by its own group may flee. Code only lets a monster turn on another when they're on opposite sides or one hit the other.
- **Rolled on Jev's odds.** Monsters don't always take Jev's top choice. Any action at 15% or more can happen, in proportion to its probability. Jev's probabilities are calibrated, so a 20% "turn on the traitor" really happens about one time in five.
- **Talking to allies (E).** Each ally hears you once per floor. If your words land well (3+ out of 4), it gets a buff for the next fight: goblin **PUMPED** (double damage), slime **BOUNCY** (absorbs a hit), dragon **STORMING** (free lightning on every enemy), and so on. Worse results have consequences too (see above).
- **Vows (V).** Build a promise from menus: *I WILL / I WON'T* → *KILL / TALK TO / GIVE GOLD TO / RUN FROM / BEFRIEND* → *SLIMES / GOBLINS / DRAGONS / MONSTERS*. Swear to an ally (once per ally per floor) or to the monster you're targeting (once per fight); you can keep six active vows. Jev judges how the monster feels about the promise, which shifts friendliness or loyalty.
- **Breaking vows.** Because vows are structured, code checks them exactly against what you do (killing, sparing, talking, paying, fleeing, attacking, recruiting). A broken vow gets slashed in the ledger, and the monster you swore to responds, with Jev picking one of:
  - **forgive** (only if loyalty is still at least 35)
  - **leave the party**
  - **attack you** (a fight where you can win it back, though rejoining takes more friendliness than before)
  - **steal your gold** (60% chance to get away with 25–50% of it; otherwise you catch it)

  If you swore to a monster that's still in the fight, it gets angry instead. If the one you swore to is gone, nobody holds you to it.
- **Allies explain themselves.** After a fight, each ally's reaction line matches how it judged you, and the log names the moment it can't get past ("Glop can't stomach how you killed Drip while it begged for mercy.") or liked. An ally that nearly walked out "stays. For now." A betrayed ally that wanted to forgive you but can't says so before it leaves.

Test these against the live API with `cli/social_scenarios.gd -- --live`, or in a debug run on the web with `halls.meet("goblin", "slime")`, `halls.hostile("slime")`, `halls.ally("slime", "Glop")`, and the guided first fight with `halls.lesson()`.

## The monsters

| | Likes | Hates | As an ally, it cares about |
| --- | --- | --- | --- |
| **Orange slime** | kindness, jokes, peace | cruelty, killing slimes, being called gross | a gentle party that makes friends instead of killing |
| **Huge brown goblin** | gold, fighting, being called strong | being bossed, insults, cheap offers | loot and victories; hates giving gold away and running |
| **Yellow dragon** | flattery, courage, treasure, wit | rudeness, cowardice, cheap tribute | bold wins; disgusted by fleeing and cruelty |
| **Snake person** | clever bargains, secrets, compliments on its scales | being rushed, clumsy lies, loud brutes | cunning deals and promises kept; hates pointless brutality |
| **Rock entity** | patience, quiet, respect for old things | being hurried, noise, greed | a calm, steady party; hates waste, greed and panicked running |
| **Bandit** (human) | gold, a fair cut, clever tricks | being looked down on, cheapskates | profit and fair shares; hates gold given to monsters |

Their lines, tastes and stats are in `src/rules/species.gd` and `src/rules/dnd.gd`. Any monster (except a champion) has a **15% chance to be shiny**: drawn in metallic gold with twinkling glints. Shinies are tougher (+30% HP, +1 AC, +1 to hit, saves and special DC, +10% damage) and worth double gold and 1.5× XP. They know they're rare and are proud of it. **Recruit one and you get a Shiny Roll of Fate** after the fight: a normal-strength boon, on top of the one you get for the stairs. A recruited shiny keeps its stronger stats. Talking well to an ally earns a species buff for the next fight: slime BOUNCY, goblin PUMPED, dragon STORMING, snake VENOMOUS, rock BULWARK, bandit SNEAKY.

So allies conflict with each other. Killing a monster that was pleading pleases a goblin and upsets a slime.

## Genre Halls: Undertale-style battles

Genre Halls is a pitch for the next version of the fights, built on the same renderer, monster art, species, feelings and synth. Open it with **G** on the title card, with the `genre-halls` flag, or as its own scene (`godot --path . res://src/genre/genre_halls.tscn`). It needs no key; Esc on its title or route screen goes back to the game.

- **One floor, five fights.** A 13×13 maze holds one slime, bandit, snake person and rock entity, plus a red dragon champion in the 5×5 hall at the center. Monsters are drawn down the corridor when you can see them, and show on the automap.
- **One box, one rule: lit squares hurt.** When a monster attacks, you dodge on a 7×7 grid with the arrow keys (or WASD). Every faction attacks in its own genre. Slimes rain goo, and the shadow of each drop shows where it will land. Bandits play chess: a rook lights its row and column, a bishop its diagonals, a knight its L-jumps. Snake people swing a lantern around the box, and you hide in a pillar's shadow. Rock entities stomp on the beat, with each pattern shown two beats ahead. The champion changes genre every turn.
- **FIGHT, ACT, SPARE, FLEE.** FIGHT is a timing bar: strike when the line crosses the middle. ACT gives CHECK, three acts for that species (a slime likes jokes, a bandit a fair cut, a rock quiet), and SAY SOMETHING, a typed line once per fight. SPARE works when the monster's mercy odds are 50% or more. Champions can't be fled.
- **The mind.** Each act asks the same kinds of question the main game asks Jev: how it feels (a choice over the ten feelings in `src/rules/emotions.gd`), whether it accepts mercy (yes/no), and how hard it attacks (a 0–3 score). Here a local stand-in answers them from the species' tastes, two rolled traits and its friendliness, anger and fear. Typed words are read by keyword cues and a nonsense detector. The Jev mind panel shows every answer and its odds. As in the main game, any answer at 15% or more can happen.
- **Allies are charms.** A spared monster may ask to join, up to three. Each ally gives a passive charm: BOUNCY absorbs the first hit, KEEN EYE keeps warnings lit longer, SLIPPERY lengthens your safety after a hit, STEADY slows the strike bar, and HOARD-FIRE adds 4 damage. Allies judge what you do (killing a monster that was ready to stop, fleeing, insults) and walk out when their loyalty runs low.
- **Routes.** The stairs name how you played: ghost (met no one), quiet (killed no one), blood (spared no one) or tangled.

The rules (factions, floor, mind, word reading, box geometry) are in `src/genre/genre_rules.gd`, with no UI, and are tested in `tests/genre/`. Drawing and input are in `src/genre/genre_halls.gd`. The `meet=<species>` flag jumps straight into that faction's fight.

## How Jev runs it

**Each combat round:** one Jev request (`src/jev/enemy.gd`; from a handful to about two dozen questions per monster, depending on what you just did):
- It reads your message: threat, insult, kindness 0–3, joke, offers gold, asks it to join, asks for peace.
- It picks an action from the feasible set and a target from the living party members.
- It also picks one line per possible action from that species' approved lines in `src/rules/species.gd`, so whatever action survives the rules already has a line.
- Whenever joining is possible (you recruited it, your words invite it, or it's warm enough to ask): whether it wants to say yes, plus its main reason to say yes **and** its main reason to say no (both asked at once, since Jev answers in parallel).

**Code owns the rules:**
- Your words move the monster's friendliness, anger and fear, using per-species weights.
- A monster can only join once it's friendly enough (the slime's bar is lower than the dragon's) and calm enough. The answer to an invitation is settled from its mood *after* this round's pitch, words and feeling, plus Jev's yes/no; code then keeps the reason that matches the outcome (an angry refusal always gets an angry reason). Feeling offended, enraged or confused that same round rules out a yes. A monster that likes you and says no declines instead of attacking.
- Tribute must meet the monster's minimum. Code describes the offer in words ("a generous offer") because Jev compares words better than numbers. A refusal says whether the offer was too small, it's too angry, or it can't be bought.
- An angry monster can't just walk away.
- `src/rules/narrate.gd` turns all of this into the log: species body language, and the reason behind an answer. It never shows a number.

**After each encounter:** one request (`src/jev/allies.gd`) scores how each ally feels about what happened, from 0 to 4, by its own values, and picks the moment it reacted to most. Code turns the score into loyalty and picks the reaction line Jev liked best *among the lines that match the score*, so a disapproving ally never cheers (ally talks and vows, in `src/jev/bonds.gd`, do the same). Allies below 45 loyalty are also asked whether they stay, leave or turn on you. Code only allows leaving below 30 and betrayal below 15. A betrayer becomes an enemy that remembers why.

## Music

The music follows the moment (`src/audio/ambient.gd`). **P** turns it on and off.

All of it is baroque dungeon music, in the spirit of Wizardry and Dragon Quest: one small band of real samples (harpsichord, church organ, strings, choir, music box and tubular bells, from the MusyngKite soundfont) plus synthesised kettle drums and a tabor, all in the same stone hall. Every piece is built on the game's own melody, **A B C D D D E D E D C C C D D D**, with its repeated notes short-short-long. The pieces are rendered offline and ship as Ogg Vorbis files in `assets/audio/` (about 5 MB in all).

**Exploring: `ambient.ogg`**, a passacaglia in D minor: 112.5 seconds, 3/4 at 64 BPM, five variations on an eight-bar ground bass (the lament D C B♭ A, then B♭ A D A). The melody lies over it note for note (Dm | C | B♭ | F/A | Gm/B♭ | A7 | Dm | A) and comes and goes. Variation I has no melody, only organ, low strings, harpsichord and a far bell. Then the melody passes to the music box, the strings, and the harpsichord over a swelling choir, and in the last variation a fragment on high strings while the texture thins back to the start. The ambient also comes and goes in time: about a minute and a half of music, then a minute or two of quiet before it drifts back. It fades in over two seconds, two seconds after a fight ends.

**Fights: four toccata-style loops, picked at random** (`battle-*.ogg`). Each is 16 bars: the melody in the minor, again coming home with a string run, lifted into the relative major on a second lead, then everyone together.

| Loop | Key, tempo | Lead (and the major lift) | Groove |
| --- | --- | --- | --- |
| toccata | D minor, 132 BPM | organ (strings, F major) | harpsichord 16ths against a pedal note, pumping bass, strings marcato |
| charge | A minor, 126 BPM | strings (choir, C major) | harpsichord arpeggios, organ chords, driving kettle drums |
| crusade | G minor, 112 BPM | choir (strings, B♭ major) | full organ, chugging strings, kettle drums and tabor in march time |
| gallop | E minor, 120 BPM | harpsichord (organ, G major) | galloping strings, kettle drums and tabor |

None goes faster than 132 BPM. Each fight picks one at random, never the one you heard last, and keeps it for the whole fight, because switching tunes mid-fight was jarring. The loop cuts in within a third of a second when a fight starts, and the ambient fades out underneath, keeping its place.

**Good news: one-shot cues** by the same band. `fanfare.ogg` (3.9 s) plays when you go down the stairs, and the ambient returns a few seconds after it. `victory.ogg` (2.3 s) plays when you win a fight (every foe killed, driven off, won over or let go; not when you run). Both quote the melody's opening in D major (D E F♯ G G G) and land on a IV6–V7–I cadence with bells.

**Levels.** The renders are mastered to −19 dBFS RMS (explore) and −17 dBFS RMS (fights and stings). The volumes in `TRACKS`/`STINGS` (0.7 and 0.75) put a fight about 2.6 dB above the exploring music.

**How it's made.** `tools/music/sampler.py` is an offline sampler. It decodes each soundfont key once, fixes the samples' tuning where two pitch estimators agree (the harpsichord runs up to 14 cents sharp), loops long organ, string and choir notes, and renders into a circular timeline so the loop points are seamless. The notes, chords and mix levels are tables at the top of each build script, and each build prints its bar-by-bar chord and melody table, a check of the outer voices for parallel fifths and octaves, the loudness of every part per section, and the peak, RMS, spectrum and loop seam. `tools/music/to_ogg.sh` cuts exactly one loop out of a render and encodes it, so Godot's gapless Ogg loop wraps inside the music. Rebuilding (numpy, scipy and ffmpeg with libvorbis) is in [tools/music/README.md](tools/music/README.md); if you change a loop's tempo or length, update its `loopSeconds` in `TRACKS` (`src/audio/ambient.gd`), which `tests/audio/test_ambient.gd` checks. The soundfonts live in `tools/music/soundfonts/` and stay out of the exports; only the rendered `.ogg` files ship. Credits are in `assets/CREDITS.txt`.

## Voices

The monsters' voices are engines behind one interface (`src/audio/tts_engines.gd`); `src/audio/tts_config.gd` works out which ones this build has and their order, and **L** steps through them. `godot --path . --verbose` lists them at start and logs every line spoken, with the engine.

| Voice | `tts=` | What it needs |
| --- | --- | --- |
| A rendered bank | `cosyvoice3`, `qwen3` | `assets/voices/<bank>/manifest.json` and its Ogg files (see below) |
| Feiyu service | `feiyu` | a running Feiyu voice service (CosyVoice3 behind a FastAPI job queue) and a voice of our own on it |
| Qwen3-TTS service | `qwen` | a running Qwen3-TTS service |
| Your system's | `system` | a speech engine on the system (or the browser's) |

**The services** synthesise each line as it's said, so they speak any line, not just the fixed ones, but each line takes a second or more (CosyVoice3 needs an NVIDIA GPU; on a shared laptop GPU it ran at about twice real time). Configure them in `config/tts_config.json` (it ships with an export, like `jev_config.json`), or, running from source, in `.env`:

```json
{
  "engines": ["feiyu", "system"],
  "feiyu": {"url": "http://gpu-box:8000", "key": "...", "voice": "<voice package>", "style": "gentle",
            "voices": {"dragon": {"voice": "<another>", "style": "cute"}}},
  "qwen": {"url": "http://mac:8001", "language": "en", "voices": {"slime": {"speaker": "Aiden"}}}
}
```

```bash
FEIYU_TTS_URL=http://gpu-box:8000
FEIYU_TTS_KEY=...
FEIYU_TTS_VOICE=<voice package>
QWEN_TTS_URL=http://mac:8001
```

- **Feiyu**: `POST /v1/speech` with `{voice, style, text}` (plus whatever `voices.<species>` adds for that monster) and `Authorization: Bearer <key>`, then `GET /v1/jobs/<id>` until it succeeds, then `GET /v1/jobs/<id>/audio` (WAV). The game only offers it once a `voice` is named: the service's default voice is the Feiyu voice library, whose licence covers that project's own voice training only, so it may not be used here. Use a voice made from Creative Commons recordings.
- **Qwen3-TTS**: `POST /synthesize` with `{text, language, speaker}` (and anything `voices.<species>` adds), answered with the WAV. Without a `voices` entry a monster gets one of the CustomVoice model's English speakers (`QWEN_SPEAKERS` in `tts_config.gd`).
- A service that fails (unreachable, an error, no WAV) steps aside for 30 seconds, and the next voice speaks meanwhile. The last 64 lines synthesised are kept, so a line heard again plays at once.

**A rendered bank** is a folder `assets/voices/<bank>/` with Ogg files and a `manifest.json`: `{"id", "label", "lines": {"<species>": {"<words>": "<file>.ogg"}}}`, where `<words>` is what's said, lower-case with single spaces (`Tts.line_key`: no stage directions). `cli/voice_lines.gd` lists every line to render: 322, with `{name}` filled with each of the monster's own names; the 6 that name their `{target}` can't be rendered ahead. The game has two, `cosyvoice3` and `qwen3`, each monster cloned from the same Creative Commons recording in both, so **L** compares the models on equal terms. `tools/voices/render.py` makes a bank (on a CPU, an hour or two), `tools/voices/check.py` plays it back into the game's speech recognizer to check every line is understood, and `tests/audio/test_voice_banks.gd` checks every line is there; see [tools/voices/README.md](tools/voices/README.md). Import new files (`godot --headless --path . --import`) before running the game.

## Debug mode (developers only)

Players never see Jev's raw output. Turn debug mode on with the `debug` flag, `donjon.debug` set to `"1"` in the saved data, or `"debug": true` in `config/jev_config.json` (builds made with `--openrouter` or `--proxy` have it on; `nodebug` turns it off), and you get:
- the **Jev mind panel** (toggle with **J**): every monster's meters, what it heard, Jev's action odds, its feeling odds, its answer to an invitation and the reason, every choice code blocked, and how allies scored each fight;
- `[DEBUG]` lines in the log with the numbers behind feelings, ally talks, vows and loyalty changes;
- the `halls` console hooks, in the web build.

**Every API request, in detail.** The panel has a **REQUESTS** tab: every call the game makes to Jev's rules (`group-turn`, `ally-reactions`, `ally-talk`, `vow`, `vow-broken`), newest first, the last hundred, with its status, time, how many Jev calls it took, questions and tokens. Open one to read exactly what was sent and answered, and below it each raw Jev call: the `state` Jev was given, the `questions`, and its `answers` with all their probabilities, each with a COPY button that puts the pretty-printed JSON on the clipboard. The key never appears in it.

**Test runs:** `godot --path . -- floor5` (any number from 2 to 30) starts on that floor with a party that got there. Add `debug` for debug mode: `floor5-debug`.

## Coming from the browser version

The game was a browser game with a Node server and was rewritten in Godot; the JavaScript lives on in git history (`git show 12d2be7:crawler/README.md` is its README). The game's rules, wording and numbers are the same, and the Jev questions are byte for byte the ones the JavaScript sent (`tests/jev/golden/`). What changed:

| Before | Now |
| --- | --- |
| `npm run crawler` | `godot --path .` |
| `npm run crawler:mock` | `godot --path . -- mock` |
| `?debug`, `#floor5-debug`, `?nofx`, `?nodebug` in the URL | the same words after `--`, or in the address on the web build |
| `npm test` | `godot --headless --path . -s res://tests/run_tests.gd` |
| `npm run crawler:scenarios`, `crawler:social` | `cli/scenarios.gd`, `cli/social_scenarios.gd` |
| `npm run crawler:shots` (Playwright in Chrome) | `cli/shots.gd` (the real screen in a Godot window) |
| `npm run crawler:itch`, `build-itch.js` | `tools/build.sh` |
| `TYPESAFE_API_KEY` held by the Node server | `.env` read by the game; in a build, `config/jev_config.json` or the Worker |
| the Worker (`halls-of-jev-api`) ran the game's rules; the itch.io build called Jev from the browser with a public key | the Worker (`donjon-api`) only forwards requests and every build uses it; the rules run in the game; CI no longer publishes to itch.io |
| `localStorage` | `user://store.json` |

Gone for good: `npm run crawler:bench` (the frame-time benchmark), the three developer pages `gallery.html`, `cover.html` and `beatmaker.html` with the Beethoven theme and `music.js` engine behind it, and the monsters' jagged look (`ART.pixel`). To see every monster, run `cli/view_shots.gd`; the cover is `docs/donjon-cover.png` (630 × 500).
