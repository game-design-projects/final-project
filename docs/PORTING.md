# Porting contract: Donjon JS → Godot 4.7 (GDScript)

Every agent porting part of the game follows this file. The JS in `crawler/` is the source of truth and stays
read-only until the port lands (it has a `.gdignore`, so Godot never imports it). Read the JS you port **in full**.

## Environment

- Worktree (Godot project root, `res://`): `/private/tmp/temp/final-project-godot` (branch `godot-rewrite`).
- Godot 4.7.2 binary: `G=/private/tmp/claude-501/-private-tmp-temp/9a270d88-2fcd-474a-8038-3c1a423642ac/scratchpad/bin/godot`
  (self-contained: its settings and the web export templates live beside it; do not install anything globally).
- macOS 26 arm64. ffmpeg (with libvorbis), python3, node 26 are installed.
- Renderer: `gl_compatibility` (the web export needs it). Base window 1180×820, stretch `canvas_items`, aspect `expand`.
- The boot splash is off (`application/boot_splash/show_image=false`, black). Don't touch `project.godot`; if you need
  a setting, an autoload or an input action, say so in your final report and the integrator adds it.

Commands (run from the worktree):

```bash
$G --headless --path . --import                                     # after adding files/assets (class cache, imports)
$G --headless --path . --check-only -s res://src/x/y.gd             # parse check one script
$G --headless --path . -s res://tests/run_tests.gd -- --only=rules  # your tests (path substring filter)
$G --headless --path . -s res://tests/run_tests.gd                  # everything
```

Other agents work in the same worktree at the same time. Only create/edit the files you own (below). If an import
or cache error looks unrelated to your files, run `--import` again once. Never delete `.godot/`.

**Commit as you go**, only your own paths (with the `.uid` / `.import` files Godot makes beside them): `git add <your paths> && git commit -m "feat: ..." -- <your paths>`
(the `-- <paths>` keeps other agents' staged files out of your commit; retry if `index.lock` is busy). Commit message
format `<type>: <description>`. Never push, never rebase, never `git checkout --`/`reset`/`stash`.

Never call the real Jev API or read `.env`: run everything with mock Jev (`mock` flag, `src/jev/mock_jev.gd`).

## Layout and ownership

| Area | Files (res://) | Ported from (crawler/) |
| --- | --- | --- |
| core (integrator) | `src/core/js.gd`, `store.gd` (autoload `Store`), `flags.gd`; `src/view/canvas2d.gd`; `tests/test_case.gd`, `tests/run_tests.gd` | — |
| rules | `src/rules/{dnd,species,emotions,status,narrate,juice,dice,tutorial,achievements,tooltip,inspector}.gd`, `tests/rules/` | `public/` same names |
| jev | `src/jev/{q,jev,mock_jev,enemy,allies,bonds,api,config}.gd`, `cli/scenarios.gd`, `cli/social_scenarios.gd`, `tests/jev/`, `proxy/` | `src/`, `scripts/*scenarios.js`, `proxy/` |
| view | `src/view/{render,art,postfx}.gd`, `src/view/postfx.gdshader`, `tests/view/` (not canvas2d) | `public/render.js`, `art.js`, `postfx.js` |
| audio | `src/audio/{synth,sfx,shout,ambient,mix,tts,voice}.gd`, `assets/audio/`, `tools/music/`, `tests/audio/` | `public/sfx.js` … `voice.js`, `scripts/*.py` |
| genre | `src/genre/{genre_rules,genre_halls}.gd`, `src/genre/genre_halls.tscn`, `tests/genre/` | `public/genre-rules.js`, `genre-halls.js`, `genre-halls.html` |
| game | `src/game/` (`game.gd` + any split files), `tests/game/` | `public/game.js`: the rules and flow |
| ui | `src/ui/` (`main.tscn`, `main.gd`, widgets, theme), `web/shell.html`, `cli/shots.gd`, `tests/ui/` | `public/game.js` presentation, `index.html`, `style.css`, `tooltip.js`/`inspector.js`/`tutorial.js`/`achievements.js` DOM parts |

## Module shape

- **No `class_name`.** A module is a script of static funcs/consts. Use it with a preload named after the file in
  PascalCase: `const Species = preload("res://src/rules/species.gd")`, `const J = preload("res://src/core/js.gd")`,
  `const Canvas2D = preload("res://src/view/canvas2d.gd")`, `const JevApi = preload("res://src/jev/api.gd")`.
- **Names.** Exported `fooBar(a, b)` → `static func foo_bar(a, b)`, same argument order and meaning. Exported
  constants keep their exact UPPER_CASE names. Exported class `Foo` → inner class `class Foo:` in that module
  (`Juice.Shake.new()`), methods snake_case (`shake.add(k, at)`, `sfx.play("hit", {"delay": 0.1})`). Properties keep
  their JS name in snake_case (`sfx.on`, `music.on`, `narrator.supported`).
- **Options objects.** `f(x, { a = 1, b } = {})` → `f(x, opts := {})`, read with `opts.get("a", 1)`. A function whose
  only parameter is a destructured object (`createTutorial({ store, context, … })`, `enemyTurn(req)`) takes one
  Dictionary with the same keys. Callbacks in those objects are `Callable`s.
- **Data stays JSON-shaped.** JS objects → `Dictionary` with the **same camelCase string keys** (`maxHp`, `clsId`,
  `friendliness`): these keys go into Jev's state, the save data and the tests. Arrays → `Array`, `Set` →
  `{item: true}` Dictionary, `Map` → Dictionary. Use `const` only for literals that are never mutated (a const
  Dictionary is read-only in Godot); otherwise `static var`.
- **Every string and number is byte-identical to the JS**: player-facing text, log lines, Jev instructions and
  criteria, balance numbers. That wording is the game's design, and Jev's answers depend on it.
- **Async.** `async`/Promise functions become coroutines (`await`). `await sleep(ms)` → `await J.sleep(ms)`.
  `new Promise(r => …)` waiting on the player → a `J.Waiter` (`var w := J.Waiter.new()`, store it, `w.resolve(v)`
  elsewhere, `return await w.wait()`). `Promise.all([...])` → `await J.all([func(): return await a(), …])`.
- **Errors.** GDScript has no exceptions. Where JS throws and a caller catches, return `{"error": "message"}` (plus
  `"status": int` where HTTP-like) and have the caller check `if r.has("error")`, keeping the JS catch-branch behaviour.
- **Randomness.** `Math.random()` → `randf()`; `rnd(a,b)` → `J.rnd(a, b)`; `pick(arr)` → `J.pick(arr)`;
  `Math.floor(Math.random() * n)` → `randi() % n`. Tests seed with `seed(n)`.
- **Time.** `performance.now()` → `J.now_ms()` (float ms); `Date.now()` → `J.date_ms()`. Keep ms units like the JS.
- **Logging.** `console.debug` → `print_verbose`, `console.log` → `print`, `console.warn` → `push_warning`,
  `console.error` → `push_error`. Keep every log line the JS had; add more where it helps debugging.
- **Persistence.** `localStorage` → the `store` passed in (same keys as JS). The game passes the `Store` autoload
  (`get_item(k)` → String or null, `set_item(k, v)`, `remove_item(k)`); tests pass `Store.Memory.new()`
  (`preload("res://src/core/store.gd").Memory`).
- **Drawing.** Canvas 2D code ports through `src/view/canvas2d.gd`, method for method in snake_case
  (`ctx.begin_path()`, `ctx.fill_style = "#000"`, `ctx.fill_text(...)`, `ctx.measure_text(s).width`,
  `ctx.create_radial_gradient(...).add_color_stop(0, "rgba(...)")`, `ctx.draw_image(texture, ...)`). Make the context
  inside a `_draw()`: `var ctx = Canvas2D.new(self, Vector2(448, 288))`. Keep CSS color strings as they are.
  Fonts: `"9px \"Press Start 2P\", monospace"` and `VT323` map to `res://assets/fonts/`; for UI use
  `Canvas2D.pixel_font("press start 2p")` / `Canvas2D.pixel_font("vt323")`.
- **Flags.** `location.search + location.hash` → `Flags.text()` (`preload("res://src/core/flags.gd")`); keep the JS
  regexes: `/debug/i.test(...)` → `Flags.test("debug")`, `/floor(\d+)/.exec(location.hash)` → `Flags.capture("floor(\\d+)")`.

### JS → GDScript traps (each has bitten ports before)

- `7 / 2` is `3` with ints. Divide as floats wherever JS could produce a fraction: `float(a) / b`.
- `%` doesn't take floats: `fmod`/`fposmod`. JS `%` on negative ints matches GDScript `%` (truncated).
- `Math.round` ≠ `round()` on halves: use `J.round_js(x)`. `Math.floor` → `floori` (int), `Math.ceil` → `ceili`.
- Numbers from `JSON.parse_string` are always floats: `str(7.0)` is `"7.0"`. Use `J.num(x)` or `int(x)` in text.
- `[]` and `{}` are truthy in JS but falsy in GDScript: write `if x != null`, `if not arr.is_empty()`, or `J.truthy(x)`.
- `d.key` on a Dictionary errors if the key is missing (JS gives undefined). Use `d.get("key")` / `d.get("key", def)`
  for optional fields; initialise every field the code later reads with `.`.
- `a?.b?.c` → explicit null checks. `a ?? b` → `J.nz(a, b)` (careful: both sides are evaluated).
- Lambdas capture locals **by value**: a lambda can't increment an outer local counter. Use an Array/Dictionary cell.
- `sort_custom(func(a, b): return a < b)` takes a "comes before" bool, not a number, and isn't stable: add an
  index tie-break where JS relied on stable sorting.
- JS regex `/x/i` → `RegEx.create_from_string("(?i)x")` (PCRE2; compile once in a `static var`). `str.replace(/x/g, y)`
  → `re.sub(str, y, true)`.
- `String(x).slice(0, n)` → `.left(n)`; `arr.slice(-n)` works; `.padStart` → `.lpad`; `.trim` → `.strip_edges`;
  `.includes` → `.contains` / `in`; `.toUpperCase` → `.to_upper`.
- `:=` can't infer from a Variant (an untyped Array element, a Dictionary value): write `var x = …` or `var x: T = …`.
- `Infinity` → `INF`, `Number.isFinite` → `is_finite`, `Math.max(...a)` → `a.max()`.

## Interfaces between areas

**jev → game.** `JevApi.handle(path: String, body: Dictionary, opts := {}) -> Dictionary` (coroutine) replaces
`handleApi`: same paths (`/api/group-turn`, `/api/enemy-turn`, `/api/ally-reactions`, `/api/ally-talk`, `/api/vow`,
`/api/vow-broken`), same sanitising, same replies. Returns `{"status": 200, "body": {...}}`, or
`{"status": 4xx|5xx, "body": {"error": "..."}}`. With `opts.debug == true` the body carries `_debug: {jev: [...]}` (the
trace). `src/jev/config.gd` decides how Jev is reached: `mock` (flag `mock`, env `JEV_MOCK=1`, or no key at all, with
a warning), `openrouter` / `typesafe` (key from `res://config/jev_config.json` in exported builds, or the project's
`.env` when run from source), `proxy` (an `apiBase` that forwards `{model, state, questions}`).

**game ↔ ui.** `src/game/game.gd` (`extends Node`) is the rules and flow of `game.js`; `src/ui/` is everything that
draws or listens. Ownership of game.js's top-level functions:

- **ui owns**: `renderModal`, `nudgeModal`, `nudgeDock`, `listen`, `stopListening`, `render`, `drawFloaters`,
  `drawIcon`, `drawView`, `drawExplore`, `drawMonsterTag`, `drawBossAhead`, `setHtml`, `renderBar`, `sysToggles`,
  `achCap`, `renderLog`, `chip`, `MOODS`, `slotPips`, `powersCell`, `statusChips`, `deathSaves`, `partyRow`,
  `renderParty`, `renderVows`, `ARROWS`, `capOf`, `cmd`, `menuHtml`, `renderDock` (and `dockHint`), `drawRoll`, `bar`,
  `words`, `renderRequests`, `jevTab`, `showJev`, `toggleJev`, `startAudio`, `audioAt`, `perfAt`, `beginTransition`,
  `prevFrame`/`transition`, `frame`, `spacePlan`, `spaceStart`, every `fx.on(...)` subscription, every DOM event
  listener, `installTooltips`, `initTutorial`, `initAchievements` (the DOM wrappers), and the `halls` debug hooks'
  wiring.
- **game owns everything else**, including `ask`/`choose`/`askText`/`closeInput` (state + `J.Waiter`), `say`/`speak`,
  `floatText`/`rollFx`/`spotOf`/`slotOf`/`floatOn`/`floatParty` (they push into state arrays the ui draws), `api`
  (calls `JevApi.handle`, keeps `api_log` for the REQUESTS tab), `key(k)` and `KEYMAP`, `start`, `testRun`, `newRun`,
  combat, vows, boons, the roll of fate's state, and the `halls` debug hook functions (as methods).
- game.gd reaches the ui only through `var ui` (set by main before `start()`), calling the snake_case name of the ui-owned
  JS function wherever the JS called it: `ui.render()`, `ui.nudge_modal()`, `ui.nudge_dock()`, `ui.show_jev(x)`,
  `ui.render_requests()`, `ui.toggle_jev()`; and for the DOM bits inside game-owned functions:
  `ui.open_input(label: String, numeric: bool)`, `ui.close_input()`, `ui.input_text() -> String`,
  `ui.set_input_text(s)`. Anything else you need, add it as `ui.<snake_case_name>(...)` and list it in your report.
- main (ui) creates and hands to the game before `start()`: `game.ui`, `game.music` (`Ambient.Ambient`),
  `game.sfx` (`Sfx.Sfx`), `game.narrator` (`Tts.Narrator`), `game.voice` (`Voice.Listener`), `game.tips` (what
  `initTutorial` returned in JS), `game.ach` (what `initAchievements` returned). game.gd creates `fx`
  (`Juice.create_bus()`), `floaters`, `dice` (`Dice.DicePops`) itself; the ui subscribes to `game.fx`.
- Keys: the ui turns input into the JS key strings (`e.key.toLowerCase()`: `"arrowup"`, `"enter"`, `"escape"`, `" "`,
  `"a"`, `"1"`…) and calls `game.key(k)`; dock/top-bar/modal buttons call `game.key(<their data-key>)`.
- `G` is a Dictionary with exactly the JS shape (`G.mode`, `G.party`, `G.combat`, `G.prompt`, `G.menu`, `G.input`,
  `G.map`, `G.roll`, `G.waitKey`, …); the ui reads it directly (`game.G`). The waiting objects keep their JS fields and
  hold a `waiter` (`J.Waiter`) instead of `resolve`.

**audio.** Ports keep their JS classes as inner classes: `Ambient.Ambient`, `Sfx.Sfx`, `Mix.Mixer`,
`Mix.BeatScheduler`, `Tts.Narrator`, `Voice.Listener`. Classes that play sound extend `Node` and must be added to the
tree by their owner (main). The WebAudio graph becomes Godot audio buses (create them at runtime in `Mixer`). The
`.m4a` music becomes `.ogg` under `assets/audio/` (Godot can't play AAC).

**view.** `Render.draw_corridor(ctx, map, x, y, dir, t)`, `Render.draw_map(...)`, `Render.draw_title(ctx, t, prompt)`,
`Art.draw_monster(ctx, species, t, hurt, slot, pixel, look)` keep the JS signatures with a Canvas2D `ctx`.
`PostFx` becomes a canvas_item shader (`postfx.gdshader`) plus `src/view/postfx.gd` with a `PostFx` inner class that
owns the ShaderMaterial and keeps the JS methods (`hurt(k)`, `flash(color, k)`, `beat(at)`, `set_danger(d)`,
`set_accent(c)`, `render(now)` to update uniforms). The ui puts the material on the TextureRect that shows the view.
