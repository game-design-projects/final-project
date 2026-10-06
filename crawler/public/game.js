import { SPECIES } from "./species.js";
import { DIRS, VIEW, scaleAt, PALETTES, drawCorridor, drawMap, drawTitle, clear } from "./render.js";
import { drawMonster, SLOTS, SHINY_COLOR, BOSS_COLOR, ART } from "./art.js";
import { Ambient } from "./ambient.js";
import { Sfx } from "./sfx.js";
import { DicePops, dieTier, landPunch, DIE_TUMBLE_MS, DIE_ANIM_MS } from "./dice.js";
import { d, d20, rollDice, fmtRoll, diceRange, prof, CLASSES, SPELLS, spellText, ABILITY_WORDS, slotsFor, spellsKnown, cantripDice, MONSTER_STATS } from "./dnd.js";
import { hpState, condList, loyaltyState, slotGroups, classWord, facingWord, floorName, menuStep, CONDITIONS, CIRCLE_COLORS, CIRCLE_WORDS, ICONS, iconSvg } from "./status.js";
import { initTutorial } from "./tutorial.js";
import { groupLog, allyLine, reactionTell, cantForgiveLine } from "./narrate.js";

const $ = (s) => document.querySelector(s);
const view = $("#view").getContext("2d");
const mapCtx = $("#map").getContext("2d");
const music = new Ambient();
const sfx = new Sfx();

// Where the Jev API lives: this server locally, or the Cloudflare Worker in the itch.io build (see config.js).
const API = window.HALLS_CONFIG?.apiBase ?? "";

async function api(path, body) {
  const res = await fetch(API + path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(out.error || `HTTP ${res.status}`);
  return out;
}

const rnd = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const store = {
  get(k) {
    try {
      return localStorage.getItem(k);
    } catch {
      return null;
    }
  },
  set(k, v) {
    try {
      localStorage.setItem(k, v);
    } catch {}
  },
};

// Developer mode: the Jev mind panel (J), raw numbers in the log, and the `halls` console hooks. Players never see
// any of it; monsters' minds reach them through what they say and do. Turn it on with ?debug or #debug in the URL
// (e.g. #floor5-debug), or for good with localStorage "donjon.debug" = "1".
const DEBUG = /debug/i.test(location.search + location.hash) || store.get("donjon.debug") === "1";
// Log lines for developers only, e.g. the numbers behind a feeling or a loyalty change.
const dbg = (text) => DEBUG && say(`[DEBUG] ${text}`, "dim");

// ---------------------------------------------------------------- state

let G;
let uid = 0;

// Tips (tutorial.js): one short hint the first time each thing matters. Hidden over questions and rolls.
const tips = initTutorial({
  store,
  view: $("#view"),
  // A menu or the talk box counts as a question: the lit-up dock has the player's attention, and keys mean something else there
  context: () => (!G || G.mode === "over" ? "off" : G.roll || G.waitKey ? "roll" : G.prompt || G.menu || G.input ? "prompt" : G.combat ? "combat" : "explore"),
  accent: () => G?.map?.palette?.accent,
  onShow: () => sfx.play("tick"),
});
const hint = (id) => tips.hint(id);

function newRun() {
  G = {
    mode: "explore",
    floor: 1,
    party: [human("HORTENSE", "fighter"), human("ROLF", "cleric"), human("EUGENE", "wizard")],
    gold: 30,
    boons: [],
    goldMult: 1,
    combat: null,
    busy: false,
    prompt: null,
    menu: null,
    input: null,
    vows: [],
    pendingBreaks: [],
    graceSteps: 4,
    log: [],
  };
  enterFloor(1);
  say("You descend into the Donjon. The monsters here listen, if you talk to them.", "dim");
  say("HORTENSE IS A FIGHTER, ROLF A CLERIC WHO HEALS, EUGENE A WIZARD. EVERY SWING, SPELL AND PLEA IS A DICE ROLL.", "dim");
  if (!tips.on()) say("MOVE WITH THE ARROW KEYS OR WASD. EVERYTHING ELSE IS ON THE BAR UNDER THE VIEW: PRESS ITS KEY OR CLICK IT.", "dim");
  say("FIND THE STAIRS ON EACH FLOOR. EVERY FLOOR YOU CLEAR EARNS A ROLL OF FATE.", "dim");
  announceFloor(1);
  hint("move");
  render();
}

// A D&D-style adventurer: ability modifiers, armor class, a weapon, and spell slots if they cast.
function human(name, clsId) {
  const c = CLASSES[clsId];
  const hp = c.hitDie + c.abil.con;
  const m = { id: `h${uid++}`, name, kind: "human", clsId, cls: c.code, hp, maxHp: hp, ac: c.ac, abil: { ...c.abil }, dead: false, down: false, level: 1, xp: 0, mods: baseMods(), cond: {}, uses: {} };
  if (c.caster) {
    m.bonusSlots = [0, 0, 0];
    refreshSlots(m, true);
  }
  restoreUses(m);
  return m;
}

// Fighters get Second Wind and Action Surge back on a rest.
function restoreUses(m) {
  if (m.clsId === "fighter") m.uses = { second_wind: 1, action_surge: 1 };
}

// Spell slots follow the 5e table for the caster's level, plus any extra slots from boons.
function refreshSlots(m, fill = false) {
  const old = m.maxSlots ?? [];
  m.maxSlots = slotsFor(m.level).map((n, i) => n + (m.bonusSlots[i] ?? 0));
  m.slots = m.maxSlots.map((n, i) => (fill ? n : Math.min(n, (m.slots?.[i] ?? 0) + Math.max(0, n - (old[i] ?? 0)))));
}

const slotTotal = (m) => m.maxSlots.reduce((a, b) => a + b, 0);

// Per-member modifiers from the Roll of Fate. They compound as you go deeper.
const baseMods = () => ({ dmg: 1, critMin: 20, hits: 1, lifesteal: 0, spell: 1, hitBonus: 0 });

// ---------------------------------------------------------------- depth scaling and levels
// Enemies get much tougher each floor, to balance compounding boons; damage grows more gently.
const hpScale = (f) => Math.pow(1.3, f - 1);
const dmgScale = (f) => Math.pow(1.1, f - 1);
const xpFor = (level) => Math.round(30 * Math.pow(level, 1.6));

function levelUp(m) {
  m.xp -= xpFor(m.level);
  m.level++;
  const notes = [];
  if (m.kind === "human") {
    const c = CLASSES[m.clsId];
    const gain = Math.floor(c.hitDie / 2) + 1 + m.abil.con;
    m.maxHp += gain;
    if (!m.down) m.hp = Math.min(m.maxHp, m.hp + gain + Math.ceil(m.maxHp * 0.25));
    if (m.clsId === "fighter" && m.level === 5) notes.push("EXTRA ATTACK: SWINGS TWICE A TURN");
    if (c.caster) {
      const before = spellsKnown(m.clsId, m.level - 1);
      refreshSlots(m);
      const learned = spellsKnown(m.clsId, m.level).filter((k) => !before.includes(k));
      if (learned.length) notes.push(`LEARNS ${learned.map((k) => SPELLS[k].name).join(", ")}`);
      if (m.level === 5) notes.push("FREE SPELLS NOW ROLL 2 DICE OF DAMAGE");
    }
    if (m.level % 4 === 1) notes.push(`TRAINING BONUS +${prof(m.level)} TO ATTACKS, SPELLS AND TALKING`);
  } else {
    const gain = 3 + Math.floor(m.level / 2);
    m.maxHp += gain;
    if (!m.down) m.hp = Math.min(m.maxHp, m.hp + gain + Math.ceil(m.maxHp * 0.25));
    m.dmg = [m.dmg[0] + (m.level % 2 ? 0 : 1), m.dmg[1] + 1];
  }
  say(`${m.name} REACHES LEVEL ${m.level}!${notes.length ? ` ${notes.join(". ")}.` : ""}`, "big", m.kind === "monster" ? colorOf(m) : undefined);
  sfx.play("levelup");
}

// Everyone still alive learns from the fight.
function grantXp(xp) {
  for (const m of living()) {
    m.xp += xp;
    while (m.xp >= xpFor(m.level)) {
      levelUp(m);
      hint("levelup");
    }
  }
}

const living = () => G.party.filter((m) => !m.dead);
const conscious = () => G.party.filter((m) => !m.dead && !m.down);
const allies = () => G.party.filter((m) => m.kind === "monster" && !m.dead);
const humansAlive = () => G.party.some((m) => m.kind === "human" && !m.dead);
const leader = () => conscious().find((m) => m.kind === "human") ?? conscious()[0] ?? living()[0];
// The party's best talker who is still standing does the talking (Charisma checks).
const face = () => conscious().filter((m) => m.kind === "human").sort((a, b) => b.abil.cha - a.abil.cha)[0];
const UP = (s) => String(s).toUpperCase();
const SHINY_CHANCE = 0.15; // each monster you meet has this chance to be a rare shiny gold variant
const colorOf = (m) => (m.boss ? BOSS_COLOR : m.shiny ? SHINY_COLOR : SPECIES[m.species].color);
const aLabel = (species) => `${/^[aeiou]/.test(SPECIES[species].label) ? "an" : "a"} ${SPECIES[species].label}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- waiting for the player (prompt / menu / text)

// A yes/no question. It shows as a lit-up box over the view, where your eyes already are, and
// any other key shakes it rather than being silently ignored. `walkAway`: moving answers no and moves.
function ask(text, { yes = "YES", no = "NO", walkAway = false } = {}) {
  return new Promise((resolve) => {
    G.prompt = { text, resolve, yes, no, walkAway };
    console.debug("prompt:", text);
    render();
  });
}

function renderModal() {
  const el = $("#modal");
  const p = G?.prompt;
  el.hidden = !p;
  if (!p) return;
  el.style.setProperty("--accent", G.map?.palette?.accent ?? "#ffb347");
  el.innerHTML = `<p>${esc(p.text)}</p><div class="choices"><button data-key="y"><kbd>Y</kbd> ${esc(p.yes)}</button><button data-key="n"><kbd>N</kbd> ${esc(p.no)}</button></div>${
    p.walkAway ? `<p class="aside">OR JUST WALK AWAY</p>` : ""
  }`;
}

// Draws the eye back to whatever is waiting on the player
function nudgeModal() {
  const el = $("#modal");
  el.classList.remove("nudge");
  void el.offsetWidth; // restart the animation
  el.classList.add("nudge");
}

// A list to pick from, shown in the command dock. Options: { label, value, hint?, cost? (spell circle, 0 = free), who? (a member: shows health) }.
// `who` on the menu itself shows that member's spell slots next to the title.
function choose(title, options, { who } = {}) {
  return new Promise((resolve) => {
    G.menu = { title, options, resolve, sel: 0, who };
    console.debug("menu:", title, options.length);
    render();
  });
}

// The dock is waiting on you and a key it doesn't take was pressed: shake it so the eye goes there.
function nudgeDock() {
  const el = $("#dock");
  el.classList.remove("nudge");
  void el.offsetWidth; // restart the animation
  el.classList.add("nudge");
}

function askText(label, numeric = false) {
  return new Promise((resolve) => {
    G.input = { label, resolve, numeric };
    const box = $("#text");
    $("#inputRow").hidden = false;
    $("#inputLabel").textContent = label;
    box.value = "";
    box.inputMode = numeric ? "numeric" : "text";
    render();
    box.focus();
  });
}

function closeInput(value) {
  const inp = G.input;
  G.input = null;
  $("#inputRow").hidden = true;
  $("#text").blur();
  inp?.resolve(value);
}

// ---------------------------------------------------------------- dungeon generation

// How each floor plays. The first floors are small and simple; every new depth adds something.
function floorRules(f) {
  return {
    size: Math.min(25, 13 + 2 * f),
    maxGroup: f === 1 ? 1 : f === 2 ? 2 : 3,
    pool:
      f === 1
        ? { slime: 60, goblin: 40 }
        : f === 2
          ? { slime: 35, goblin: 30, bandit: 20, snake: 15 }
          : f === 3
            ? { slime: 22, goblin: 25, bandit: 18, snake: 20, rock: 15 }
            : { slime: 15, goblin: 22, bandit: 15, snake: 18, rock: 15, dragon: 15 },
    conditions: f >= 3, // special attacks poison, entangle and knock down
    elite: f >= 6 ? Math.min(0.4, 0.12 + 0.04 * (f - 6)) : 0,
    encounter: 0.06 + 0.01 * Math.min(f, 10),
    boss: f % 5 === 0,
  };
}

const NEWS = {
  1: "FLOOR 1 IS QUIET: SMALL HALLS, LONE SLIMES AND GOBLINS. A GOOD PLACE TO LEARN THE DICE.",
  2: "NEW: MONSTERS NOW ROAM IN PAIRS. BANDITS AND SNAKE PEOPLE LURK HERE.",
  3: "NEW: GROUPS OF THREE, AND ROCK ENTITIES. SPECIAL ATTACKS NOW POISON, ENTANGLE AND KNOCK YOU DOWN.",
  4: "NEW: DRAGONS. THE HALLS GROW WIDER.",
  6: "NEW: VETERAN MONSTERS, TOUGHER AND SHARPER THAN THE REST.",
};
function announceFloor(f) {
  if (NEWS[f]) say(NEWS[f], f === 1 ? "dim" : "big", f === 1 ? undefined : G.map.palette.accent);
  if (G.map.boss) hint("boss");
  if (G.map.boss)
    say("A RED CHAMPION WAITS AT THE HEART OF THIS FLOOR (RED ON YOUR MAP). DEFEAT IT, WIN IT OVER OR TALK IT DOWN FOR A GREAT ROLL OF FATE.", "big", BOSS_COLOR);
}

function pickWeighted(table) {
  let r = Math.random() * Object.values(table).reduce((a, b) => a + b, 0);
  for (const [k, w] of Object.entries(table)) if ((r -= w) < 0) return k;
  return Object.keys(table)[0];
}

function genFloor(floor) {
  const rules = floorRules(floor);
  const N = rules.size;
  const grid = Array.from({ length: N }, () => Array(N).fill(0));
  // Maze by randomized depth-first carving on odd cells
  const stack = [[1, 1]];
  grid[1][1] = 1;
  while (stack.length) {
    const [x, y] = stack[stack.length - 1];
    const next = DIRS.map(([dx, dy]) => [x + dx * 2, y + dy * 2, x + dx, y + dy]).filter(
      ([nx, ny]) => nx > 0 && ny > 0 && nx < N - 1 && ny < N - 1 && !grid[ny][nx],
    );
    if (!next.length) {
      stack.pop();
      continue;
    }
    const [nx, ny, wx, wy] = pick(next);
    grid[wy][wx] = 1;
    grid[ny][nx] = 1;
    stack.push([nx, ny]);
  }
  // Knock through some walls so it isn't a perfect maze, and open a few small rooms
  for (let i = 0; i < Math.round(28 * (N / 21) ** 2); i++) {
    const x = rnd(1, N - 2);
    const y = rnd(1, N - 2);
    if (grid[y][x]) continue;
    if ((grid[y][x - 1] && grid[y][x + 1]) || (grid[y - 1][x] && grid[y + 1][x])) grid[y][x] = 1;
  }
  for (let r = 0; r < 2 + Math.floor(N / 10); r++) {
    const x = rnd(1, N - 5) | 1;
    const y = rnd(1, N - 5) | 1;
    for (let yy = y; yy < y + 3; yy++) for (let xx = x; xx < x + 3; xx++) grid[yy][xx] = 1;
  }
  // Boss floors: a 5x5 hall at the heart of the floor, the champion standing in its center
  let boss = null;
  const c = Math.floor(N / 2);
  if (rules.boss) {
    for (let yy = c - 2; yy <= c + 2; yy++) for (let xx = c - 2; xx <= c + 2; xx++) grid[yy][xx] = 1;
    boss = { x: c, y: c, species: pickWeighted(rules.pool), defeated: false, enemy: null };
  }
  const inHall = (x, y) => boss && Math.abs(x - c) <= 2 && Math.abs(y - c) <= 2;
  // Stairs: the floor cell farthest from the start
  const dist = new Map([["1,1", 0]]);
  const q = [[1, 1]];
  let far = [1, 1];
  while (q.length) {
    const [x, y] = q.shift();
    for (const [dx, dy] of DIRS) {
      const k = `${x + dx},${y + dy}`;
      if (grid[y + dy]?.[x + dx] && !dist.has(k)) {
        dist.set(k, dist.get(`${x},${y}`) + 1);
        q.push([x + dx, y + dy]);
        if (!inHall(x + dx, y + dy) && dist.get(k) > dist.get(`${far[0]},${far[1]}`)) far = [x + dx, y + dy];
      }
    }
  }
  const floors = [...dist.keys()].map((k) => k.split(",").map(Number));
  const gold = new Set();
  while (gold.size < 4 + Math.floor(N / 6)) {
    const [x, y] = pick(floors);
    if ((x !== 1 || y !== 1) && (x !== far[0] || y !== far[1]) && !(boss && x === boss.x && y === boss.y)) gold.add(y * N + x);
  }
  return { grid, n: N, stairs: { x: far[0], y: far[1] }, gold, floor, boss };
}

function enterFloor(n) {
  G.floor = n;
  const previous = G.map?.palette;
  G.map = genFloor(n);
  G.map.palette = pick(PALETTES.filter((p) => p !== previous));
  G.map.seed = Math.floor(Math.random() * 1e9);
  G.x = 1;
  G.y = 1;
  G.dir = DIRS.findIndex(([dx, dy]) => G.map.grid[1 + dy]?.[1 + dx] === 1);
  G.seen = new Set();
  G.visited = new Set([1 * G.map.n + 1]);
  const best = Number(store.get("hallsOfJev.deepest") || 0);
  if (n > best) store.set("hallsOfJev.deepest", String(n));
}

// ---------------------------------------------------------------- log + rendering

function say(text, cls = "", color) {
  G.log.push({ text, cls, color });
  if (G.log.length > 150) G.log.shift();
}

// A monster's spoken line gets its voice (RAAH, a hiss, a blorp...), chosen from the wording and the species (shout.js).
function speak(who, line) {
  const plan = who?.species && sfx.shout(line, who.species, { key: who.id, boss: !!who.boss });
  if (plan) console.debug("shout", who.species, plan.kind, JSON.stringify(line));
}

const hurtUntil = {}; // hurt flash window: [until - 300, until)
function render() {
  if (!G) return;
  drawView(performance.now());
  drawMap(mapCtx, G.map, G.seen, G.visited, G.x, G.y, G.dir);
  renderBar();
  renderLog();
  renderParty();
  renderVows();
  renderDock();
  renderModal();
}

// Numbers and words that float up from monsters and party members: damage, misses, feelings.
const floaters = [];
let shakeUntil = 0; // screen shake window: [until - 220, until)
function floatText(text, x, y, color = "#e8e8e8", size = 10) {
  const now = fxNow();
  const stacked = floaters.filter((f) => Math.abs(f.x - x) < 30 && now - f.t0 < 350).length;
  floaters.push({ text, x, y: y + stacked * 14, color, size, t0: now });
}

// Dice: every d20 the player sees tumbles on the view for 200ms (dice.js). What the roll causes (sounds, floating
// numbers, hurt flashes, screen shake) is held back by fxLag so it lands together with the die, not before it.
const dice = new DicePops();
let fxLag = 0;
let lastRattle = 0;
const fxNow = () => performance.now() + fxLag;
// (The small total under a die is skipped in the party row, which is busy with floating numbers.)
function rollFx(r, spot, { total, label = total != null && spot.y < 200 ? `=${total}` : "" } = {}) {
  const now = performance.now();
  dice.add({ ...spot, rolls: r.rolls, kept: r.roll, label, now });
  if (now - lastRattle > 60) sfx.play("dice", { delay: 0 }); // several dice thrown together rattle once
  lastRattle = now;
  sfx.play("diceLand", { delay: DIE_TUMBLE_MS / 1000, tier: dieTier(r.roll) });
  fxLag = DIE_TUMBLE_MS;
  sfx.lag = DIE_TUMBLE_MS / 1000;
  queueMicrotask(() => {
    fxLag = 0;
    sfx.lag = 0;
  });
  console.debug("roll", r.rolls.join("/"), "kept", r.roll, JSON.stringify(label), JSON.stringify(spot));
}
// Where a die sits: on the monster that is the target, or in the party row (the bottom of the view).
function spotOf(x) {
  const i = G.party.indexOf(x);
  return i >= 0 ? { x: (448 / (G.party.length + 1)) * (i + 1), y: 226 } : { x: slotOf(x).cx, y: 160 };
}
function slotOf(e) {
  const here = present();
  const i = Math.max(0, here.indexOf(e));
  return SLOTS[Math.min(3, Math.max(1, here.length))][Math.min(i, 2)];
}
const floatOn = (e, text, color = "#ffffff", size = 11) => floatText(text, slotOf(e).cx, 110, color, size);
function floatParty(m, text, color) {
  const i = Math.max(0, G.party.indexOf(m));
  floatText(`${m.name} ${text}`, (448 / (G.party.length + 1)) * (i + 1), 262, color, 8);
}
function drawFloaters(t) {
  view.save();
  view.textAlign = "center";
  for (let i = floaters.length - 1; i >= 0; i--) {
    const f = floaters[i];
    const age = (t - f.t0) / 1000;
    if (age < 0) continue; // waiting for its die to land
    if (age > 1.3) {
      floaters.splice(i, 1);
      continue;
    }
    const y = f.y - age * 26;
    view.globalAlpha = Math.max(0, Math.min(1, 2.6 - age * 2));
    view.font = `${f.size}px "Press Start 2P", monospace`;
    view.fillStyle = "#000";
    view.fillText(f.text, f.x + 1, y + 1);
    view.fillStyle = f.color;
    view.fillText(f.text, f.x, y);
  }
  view.restore();
}

// One of the 7x7 status icons (status.js), drawn on the canvas at `px` pixels per dot.
function drawIcon(ctx, name, x, y, color, px = 1) {
  ctx.fillStyle = color;
  (ICONS[name] ?? ICONS.dot).forEach((row, j) => [...row].forEach((c, i) => c === "#" && ctx.fillRect(x + i * px, y + j * px, px, px)));
}

function drawView(t) {
  const shaking = t < shakeUntil && t >= shakeUntil - 220;
  if (shaking) {
    view.save();
    view.translate((Math.random() - 0.5) * 7, (Math.random() - 0.5) * 7);
  }
  if (G.combat) {
    clear(view);
    const here = present();
    const slots = SLOTS[Math.min(3, Math.max(1, here.length))];
    here.forEach((e, i) => {
      const slot = slots[i];
      const until = hurtUntil[e.id] ?? 0;
      drawMonster(view, e.species, t, t < until && t >= until - 300 ? 1 : 0, slot, ART.pixel, { shiny: e.shiny, color: e.boss ? BOSS_COLOR : undefined });
      drawMonsterTag(e, slot, i, here.length);
    });
  } else {
    const seen = drawCorridor(view, G.map, G.x, G.y, G.dir, t);
    drawBossAhead(t);
    if (G.roll) drawRoll(t);
    for (const [x, y] of seen) G.seen.add(y * G.map.n + x);
  }
  dice.draw(view, t, { ink: G.map.palette.wall, hot: G.map.palette.accent });
  drawFloaters(t);
  if (shaking) view.restore();
}

// Name, health bar and conditions above each monster in a fight.
function drawMonsterTag(e, slot, i, count) {
  const color = colorOf(e);
  view.save();
  view.textAlign = "center";
  view.fillStyle = color;
  view.strokeStyle = color;
  view.font = `8px "Press Start 2P", monospace`;
  const label = `${count > 1 ? `${i + 1} ` : ""}${UP(e.name)}`;
  view.fillText(e.id === G.combat.target && count > 1 ? `>${label}<` : label, slot.cx, 13);
  // Health bar: its length and its color (green, yellow, red) both say how close to falling it is
  const st = hpState(e);
  const w = 72;
  const x0 = Math.round(slot.cx - w / 2);
  view.lineWidth = 1;
  view.strokeRect(x0 + 0.5, 18.5, w, 5);
  view.fillStyle = st.color;
  view.fillRect(x0 + 2, 20, Math.max(0, Math.round((w - 3) * st.pct)), 3);
  // Veteran mark and conditions: an icon each, with its word while there is room
  const tags = [...(e.elite ? [{ icon: "star", word: "VETERAN", color: "#e8e8e8" }] : []), ...condList(e.cond)].slice(0, 3);
  if (tags.length) {
    const withWords = count > 2 ? 1 : 2;
    view.font = `7px "Press Start 2P", monospace`;
    view.textAlign = "left";
    const widths = tags.map((t, j) => 7 + (j < withWords ? 3 + view.measureText(t.word).width : 0));
    let x = Math.round(slot.cx - (widths.reduce((a, b) => a + b, 0) + 6 * (tags.length - 1)) / 2);
    tags.forEach((t, j) => {
      drawIcon(view, t.icon, x, 28, t.color);
      if (j < withWords) view.fillText(t.word, x + 10, 35);
      x += widths[j] + 6;
    });
  }
  view.restore();
}

// The floor's champion, seen standing down the corridor before you reach it.
function drawBossAhead(t) {
  const b = G.map.boss;
  if (!b || b.defeated) return;
  const [fx, fy] = DIRS[G.dir];
  for (let dd = 1; dd <= VIEW; dd++) {
    const cx = G.x + fx * dd;
    const cy = G.y + fy * dd;
    if (G.map.grid[cy]?.[cx] !== 1) return;
    if (cx === b.x && cy === b.y) {
      // Standing in the middle of its cell, feet on the floor there
      const s = scaleAt(dd + 0.5);
      drawMonster(view, b.species, t, 0, { cx: 224, s: s * 0.92, by: 144 + 140 * s }, ART.pixel, { color: BOSS_COLOR });
      return;
    }
  }
}

// The status line on top: where you are, which way you face (or the fight's round), gold and boons.
// Commands live in the dock under the view, where the eyes already are.
function renderBar() {
  const pal = G.map.palette;
  const c = G.combat;
  const n = G.boons.length;
  $("#where").innerHTML = [
    `<span class="loc"><b style="color:${pal.accent}">${floorName(G.floor)}</b> ${esc(pal.name)}</span>`,
    c
      ? `<span class="fight">${iconSvg("flame", "#ff5a4a")}IN A FIGHT</span>`
      : `<span class="face" title="THE WAY YOU ARE LOOKING (UP ON THE MAP IS NORTH)">${iconSvg(["up", "right", "down", "left"][G.dir], "#8a8a8a")}FACING ${facingWord(G.dir)}</span>`,
    `<span class="gold">${iconSvg("coin", "#ffd27a")}${G.gold} GOLD</span>`,
    `<span class="boons" title="ROLL OF FATE BOONS YOU HAVE WON. PRESS B TO LIST THEM">${iconSvg("star", n ? "#ffd27a" : "#5a5a5a")}${n} BOON${n === 1 ? "" : "S"}</span>`,
    // Settings you rarely touch sit up here, out of the way of the commands; dimmed means off
    // (J, the Jev mind panel, exists only in debug runs)
    `<span class="sys">${!DEBUG ? "" : cmd("j", "JEV", { cls: $("#jev").classList.contains("hidden") ? "off" : "", hint: "SHOW OR HIDE THE JEV PANEL" })}${cmd("h", "TIPS", { cls: tips.on() ? "" : "off" })}${cmd("p", "MUSIC", { cls: music.on ? "" : "off" })}${cmd("o", "SOUND", { cls: sfx.on ? "" : "off" })}</span>`,
  ].join("");
}

function renderLog() {
  const el = $("#log");
  el.innerHTML = G.log
    .slice(-50)
    .map((l) => `<p class="${l.cls}"${l.color ? ` style="color:${l.color}"` : ""}>${esc(l.text)}</p>`)
    .join("");
  el.scrollTop = el.scrollHeight;
}

const loyaltyWord = (l) => loyaltyState(l).word;

// The party panel: one row per member. Health is a bar (length + color) with a word once it matters,
// armor a shield, spell slots pips colored by circle, and conditions icon chips. Hover anything for the details.
const chip = (icon, word, color, tip) => `<span class="chip" style="--c:${color}" title="${esc(tip)}">${iconSvg(icon, color)}${esc(word)}</span>`;
const MOODS = { SULKING: ["frown", "#8a8a8a"], DISTRACTED: ["what", "#ffd23f"], STEADY: ["target", "#8fd3ff"] };

function slotPips(m) {
  const groups = slotGroups(m.slots, m.maxSlots);
  const tip = `SPELL SLOTS LEFT: ${groups.map((g) => `${CIRCLE_WORDS[g.circle - 1]} CIRCLE ${g.left} OF ${g.max}`).join(", ")}. A SPELL USES ONE SLOT OF ITS CIRCLE. CAMP TO REFILL`;
  return `<span class="pips" title="${esc(tip)}">${groups.map((g) => `<span class="pg" style="--c:${g.color}">${g.pips.map((on) => `<i${on ? ' class="on"' : ""}></i>`).join("")}</span>`).join("")}</span>`;
}

function powersCell(m) {
  if (m.maxSlots) return slotPips(m);
  if (m.clsId !== "fighter") return "";
  const skills = [
    ["second_wind", "SECOND WIND"],
    ["action_surge", "ACTION SURGE"],
  ];
  const tip = `SKILLS: ${skills.map(([k, w]) => `${w} ${m.uses?.[k] ? "READY" : "USED"}`).join(", ")}. THEY COME BACK WHEN YOU CAMP`;
  return `<span class="pips" title="${tip}"><span class="pg sq" style="--c:#ffb347">${skills.map(([k]) => `<i${m.uses?.[k] ? ' class="on"' : ""}></i>`).join("")}</span></span>`;
}

function statusChips(m) {
  const chips = [];
  if (m.kind === "monster" && !m.dead) {
    const l = loyaltyState(m.loyalty ?? 50);
    chips.push(chip("heart", l.word, l.color, `LOYALTY ${m.loyalty ?? 50} OF 100: ${l.word}. AN UNHAPPY ALLY MAY LEAVE OR TURN ON YOU`));
  }
  for (const c of condList(m.cond)) chips.push(chip(c.icon, c.word, c.color, c.tip));
  if (m.buff) chips.push(chip("star", m.buff.id, "#ffe14a", `${m.buff.id}: ${UP(m.buff.desc)}`));
  if (m.mood) chips.push(chip(...(MOODS[m.mood.id] ?? ["dot", "#e8e8e8"]), m.mood.id, `${m.mood.id}: ${UP(m.mood.desc)}`));
  if (m.phoenix && !m.dead) chips.push(chip("flame", "PHOENIX", "#ffb347", "PHOENIX FEATHER: WILL CHEAT DEATH ONCE"));
  return chips.join("");
}

// Down members: three boxes for death-save successes, three for failures.
function deathSaves(m) {
  const s = m.saves ?? { s: 0, f: 0 };
  const box = (on, cls) => `<i class="${cls}${on ? " on" : ""}"></i>`;
  const tip = `DEATH SAVES: ${s.s} OF 3 SUCCESSES, ${s.f} OF 3 FAILURES. THREE FAILURES AND ${m.name} DIES. ANY HEALING GETS THEM UP`;
  return `<span class="saves" title="${esc(tip)}">${[0, 1, 2].map((j) => box(j < s.s, "ok")).join("")}${[0, 1, 2].map((j) => box(j < s.f, "bad")).join("")}</span>`;
}

function partyRow(m, i) {
  const st = hpState(m);
  const hp = Math.max(0, m.hp);
  const ink = m.kind === "monster" ? ` style="color:${colorOf(m)}"` : "";
  const who = `<span class="who"${ink}><b>${m.dead ? iconSvg("skull", "#8a8a8a") : ""}${esc(m.name)}</b><small>${classWord(m)}${m.kind === "monster" ? " ALLY" : ""} · LEVEL ${m.level ?? 1}</small></span>`;
  const word = st.id === "healthy" ? "" : `<em>${st.word}</em>`;
  const health = `<span class="hp" style="--st:${st.color}" title="HEALTH ${hp} OF ${m.maxHp}: ${st.word}"><span class="hpbar"><i style="width:${Math.round(st.pct * 100)}%"></i></span><small>${
    m.dead ? word : m.down ? `${word}${m.stable ? "" : deathSaves(m)}` : `${hp}/${m.maxHp} ${word}`
  }</small></span>`;
  const armor = `<span class="ac" title="ARMOR ${m.ac}: AN ATTACKER NEEDS ${m.ac} OR MORE, WITH ITS BONUS, TO HIT">${iconSvg("shield", "#9fb0c0")}${m.ac}</span>`;
  return `<div class="prow ${st.id}"${boonTitle(m)}><span class="num">${i + 1}</span>${who}${health}${armor}<span class="pw">${powersCell(m)}</span><span class="chips">${statusChips(m)}</span></div>`;
}

function renderParty() {
  $("#party").innerHTML = `<div class="prow phead" aria-hidden="true"><span></span><span>PARTY</span><span>HEALTH</span><span>ARMOR</span><span>SPELLS</span><span>STATUS</span></div>${G.party.map(partyRow).join("")}`;
}

// The vow ledger. Re-rendered only when something changes, so a fresh slash animates exactly once.
let vowSig = "";
function renderVows() {
  const sig = G.vows.map((v) => `${v.id}:${v.status}`).join("|");
  if (sig === vowSig) return;
  vowSig = sig;
  const box = $("#vows");
  box.hidden = !G.vows.length;
  $("#vowList").innerHTML = G.vows
    .map((v) => {
      const color = SPECIES[v.toSpecies]?.color ?? "#e8e8e8";
      const cls = v.status === "broken" ? (v.fresh ? "broken fresh" : "broken") : "";
      v.fresh = false;
      return `<li class="${cls}"><span class="vow-text">${esc(v.text)}</span> <span class="vow-to" style="color:${color}">TO ${esc(UP(v.toName))}</span></li>`;
    })
    .join("");
  if (G.vows.some((v) => v.status === "broken" && v.justBroken)) {
    box.classList.remove("shake");
    void box.offsetWidth;
    box.classList.add("shake");
    G.vows.forEach((v) => (v.justBroken = false));
  }
}

// ---------------------------------------------------------------- the command dock
// Every command is a keycap button: the key to press and what it does, clickable too. One place for keyboard,
// mouse and touch. When the game waits on you (a menu, the talk box, "any key"), the dock lights up in the
// floor's accent color and shakes if you press a key it doesn't take.

const ARROWS = { fwd: "up", back: "down", turnL: "left", turnR: "right" };
const capOf = (k) => (ARROWS[k] ? iconSvg(ARROWS[k]) : { escape: "ESC", enter: "ENTER" }[k] ?? esc(k.toUpperCase()));
function cmd(k, label, { hint = "", sub = "", cls = "", cap, style = "" } = {}) {
  return `<button type="button" class="cmd ${cls}" data-key="${k}"${hint ? ` data-hint="${esc(hint)}"` : ""}${style ? ` style="${style}"` : ""}><kbd>${cap ?? capOf(k)}</kbd>${
    label ? `<span class="lbl">${label}${sub ? `<small>${sub}</small>` : ""}</span>` : ""
  }</button>`;
}

// The hint line under the commands: what the hovered (or highlighted) command does.
let dockHint = "";

function menuHtml(m) {
  const n = m.options.length;
  const rows = n > 4 ? Math.ceil(n / 2) : n;
  const opts = m.options
    .map((o, i) => {
      const key = i < 9 ? String(i + 1) : i === 9 ? "0" : "";
      let tail = "";
      if (o.cost === 0) tail = `<span class="free">FREE</span>`;
      else if (o.cost && m.who?.slots) {
        const left = m.who.slots[o.cost - 1] ?? 0;
        tail = `<span class="pg" style="--c:${CIRCLE_COLORS[o.cost - 1]}" title="USES ONE ${CIRCLE_WORDS[o.cost - 1]}-CIRCLE SLOT. ${left} LEFT">${"<i class=\"on\"></i>".repeat(left)}</span>`;
      } else if (o.who) {
        const st = hpState(o.who);
        tail = `<span class="hpbar mini" style="--st:${st.color}"><i style="width:${Math.round(st.pct * 100)}%"></i></span>`;
      }
      return `<button type="button" class="opt${i === m.sel ? " sel" : ""}" data-key="pick:${i}" data-i="${i}" data-hint="${esc(o.hint ?? "")}"><kbd>${key || "&nbsp;"}</kbd><span class="lbl">${esc(o.label)}</span>${tail}</button>`;
    })
    .join("");
  const slots = m.who?.maxSlots ? ` ${slotPips(m.who)}` : "";
  return `<p class="ask">${esc(m.title)}${slots}</p><div class="menu" style="grid-template-rows:repeat(${rows},auto)">${opts}</div><div class="row keys"><span class="how"><kbd>${iconSvg("up")}</kbd><kbd>${iconSvg("down")}</kbd> CHOOSE <kbd>ENTER</kbd> PICK${n > 1 ? ` <kbd>1</kbd>-<kbd>${Math.min(n, 9)}</kbd>` : ""}</span>${cmd("escape", "BACK")}</div>`;
}

function renderDock() {
  const dock = $("#dock");
  let html;
  let hint = "";
  let waiting = false;
  if (G.waitKey) {
    waiting = true;
    html = `<div class="row">${cmd("enter", "CONTINUE", { cap: "ANY KEY", cls: "go" })}</div>`;
  } else if (G.roll) html = `<p class="wait">THE ROLL OF FATE IS SPINNING<span class="dots"></span></p>`;
  else if (G.mode === "over") {
    waiting = true;
    html = `<p class="ask">YOUR PARTY HAS FALLEN.</p><div class="row">${cmd("enter", "NEW RUN", { cls: "go" })}</div>`;
  } else if (G.prompt) html = `<p class="wait echo">${iconSvg("up")} ANSWER THE QUESTION ON THE VIEW</p>`;
  else if (G.menu) {
    waiting = true;
    html = menuHtml(G.menu);
    hint = G.menu.options[G.menu.sel]?.hint ?? "";
  } else if (G.input) {
    waiting = true;
    html = `<div class="row">${cmd("enter", G.input.numeric ? "GIVE" : "SAY IT", { cls: "go" })}${cmd("escape", "CANCEL")}</div>`;
  } else if (G.busy) html = `<p class="wait">${G.combat ? "THE FIGHT PLAYS OUT" : "LISTENING"}<span class="dots"></span></p>`;
  else if (G.combat) {
    const here = present();
    const t = targetEnemy();
    const tn = t ? UP(t.name) : "THE TARGET";
    html =
      `<div class="row">` +
      cmd("f", "QUICK ATTACK", { cls: "main", sub: "EVERYONE'S USUAL MOVE", hint: "EVERYONE DOES THEIR USUAL MOVE AT ONCE: WEAPONS, AND THE WIZARD'S FREE FIRE BOLT. USES NO SPELL SLOTS. ALLIES ACT ON THEIR OWN" }) +
      cmd("c", "CHOOSE MOVES", { cls: "main", sub: "SPELLS AND SKILLS", hint: "PICK A MOVE FOR EACH ADVENTURER, ONE BY ONE: ATTACK, A SKILL, OR A SPELL (SPELLS USE SLOTS)" }) +
      cmd("t", "TALK", { hint: "SAY SOMETHING. EVERY MONSTER HERE HEARS IT" }) +
      cmd("r", "RECRUIT", { hint: `ASK ${tn} TO JOIN YOUR PARTY` }) +
      cmd("g", "GIVE GOLD", { hint: `OFFER ${tn} SOME GOLD` }) +
      cmd("v", "VOW", { hint: `SWEAR A PROMISE TO ${tn}, ONCE PER FIGHT` }) +
      cmd("e", "ESCAPE", { hint: "TRY TO RUN AWAY" }) +
      `</div>`;
    if (here.length > 1)
      html += `<div class="row targets"><span class="lab">TARGET</span>${here
        .map((e, i) => cmd(String(i + 1), esc(UP(e.name)), { cls: e.id === G.combat.target ? "on" : "", hint: `AIM YOUR ATTACKS AND WORDS AT ${UP(e.name)}`, style: `--c:${colorOf(e)}` }))
        .join("")}</div>`;
  } else {
    const none = !allies().length;
    const noAlly = { cls: none ? "off" : "", hint: "NO MONSTER ALLIES YET. WIN ONE OVER IN A FIGHT (RECRUIT)" };
    html =
      `<div class="row"><span class="pad">${cmd("turnL", "", { hint: "TURN LEFT (A)" })}${cmd("fwd", "", { hint: "STEP FORWARD (W)" })}${cmd("back", "", { hint: "STEP BACK (S)" })}${cmd("turnR", "", { hint: "TURN RIGHT (D)" })}<span class="lab">MOVE</span></span>` +
      cmd("c", "CAMP", { hint: "REST: HEAL HALF YOUR WOUNDS, GET SPELL SLOTS AND SKILLS BACK. SOMETHING MAY FIND YOU" }) +
      cmd("e", "TALK TO ALLY", none ? noAlly : { hint: "TALK TO A MONSTER ALLY, ONCE PER ALLY PER FLOOR" }) +
      cmd("v", "VOW", none ? noAlly : { hint: "SWEAR A PROMISE TO A MONSTER ALLY" }) +
      cmd("b", "BOONS", { hint: "LIST THE ROLL OF FATE BOONS YOU HAVE WON" }) +
      cmd("m", "MAP", { hint: "SHOW OR HIDE THE MAP" }) +
      `</div>`;
  }
  dock.classList.toggle("waiting", waiting);
  if (!waiting) dock.classList.remove("nudge");
  dock.style.setProperty("--accent", G.map?.palette?.accent ?? "#ffb347");
  $("#cmds").innerHTML = html;
  dockHint = hint;
  $("#hint").textContent = hint;
}

// ---------------------------------------------------------------- exploring

function step(dir) {
  const [dx, dy] = DIRS[dir];
  const nx = G.x + dx;
  const ny = G.y + dy;
  if (G.map.grid[ny]?.[nx] !== 1) {
    say("OUCH! A WALL.", "dim");
    sfx.play("bump");
    return render();
  }
  G.x = nx;
  G.y = ny;
  const k = ny * G.map.n + nx;
  G.visited.add(k);
  if (G.map.gold.delete(k)) {
    const g = rnd(3, 10) * G.floor;
    G.gold += g;
    say(`YOU FIND ${g} GOLD.`);
    sfx.play("gold");
  }
  if (G.visited.size >= 6) hint("map");
  if (G.seen.has(G.map.stairs.y * G.map.n + G.map.stairs.x)) hint("stairs");
  const b = G.map.boss;
  if (b && !b.defeated && nx === b.x && ny === b.y) return bossEncounter();
  if (nx === G.map.stairs.x && ny === G.map.stairs.y) {
    ask(`STAIRS DOWN TO ${floorName(G.floor + 1)}. DESCEND?`, { yes: "DESCEND", no: "STAY", walkAway: true }).then((yes) => (yes ? descend() : render()));
    return;
  }
  if (--G.graceSteps <= 0 && Math.random() < floorRules(G.floor).encounter) return encounter();
  render();
}

function bossEncounter() {
  const b = G.map.boss;
  b.enemy ??= makeBoss(b.species);
  say(`THE AIR TURNS RED. ${UP(b.enemy.name)} RISES TO MEET YOU.`, "big", BOSS_COLOR);
  return encounter([b.enemy], { boss: true });
}

async function descend() {
  sfx.play("stairs");
  music.sting("fanfare");
  await rollOfFate(G.floor);
  enterFloor(G.floor + 1);
  G.graceSteps = 4;
  say(`YOU DESCEND TO ${floorName(G.floor)}: THE ${G.map.palette.name}. THE MONSTERS HERE ARE TOUGHER.`, "", G.map.palette.accent);
  announceFloor(G.floor);
  if (allies().length) say("YOUR ALLIES WILL HEAR YOU OUT AGAIN ON THIS FLOOR (E).", "dim");
  render();
}

// A long rest: wounds half close, spell slots and fighter skills come back, conditions clear.
async function camp() {
  for (const m of living()) {
    m.hp = Math.min(m.maxHp, m.hp + Math.ceil(m.maxHp / 2));
    m.cond = {};
    if (m.maxSlots) m.slots = [...m.maxSlots];
    restoreUses(m);
  }
  say("THE PARTY RESTS. WOUNDS CLOSE; SPELL SLOTS AND SKILLS RETURN.");
  sfx.play("heal");
  // A cleric who knows Revivify can bring back the dead while you rest
  const cleric = conscious().find((m) => m.slots && spellsKnown(m.clsId, m.level).includes("revivify"));
  for (const dead of G.party.filter((m) => m.dead)) {
    if (!cleric || !(cleric.slots[2] > 0)) break;
    render();
    if (!(await ask(`${cleric.name} CAN CAST REVIVIFY ON ${dead.name} (USES A THIRD-CIRCLE SPELL SLOT). DO IT?`, { yes: "REVIVE", no: "NOT NOW" }))) continue;
    cleric.slots[2]--;
    revive(dead);
  }
  if (Math.random() < 0.25) {
    say("...SOMETHING FINDS YOUR CAMP!", "warn");
    return encounter();
  }
  render();
}

async function pickAlly(title) {
  const list = allies();
  if (!list.length) {
    say("YOU HAVE NO MONSTER ALLIES YET.", "dim");
    render();
    return null;
  }
  if (list.length === 1) return list[0];
  return choose(title, list.map((a) => ({ label: a.name, value: a })));
}

// Talk to an ally: once per ally per floor, so it stays a special moment rather than a chatbot.
// Every talk has a result: it can sulk, get distracted, steady itself, power up, or be inspired.
async function talkToAlly() {
  const ally = await pickAlly("TALK TO WHOM?");
  if (!ally) return;
  if (ally.talkedFloor === G.floor) {
    say(`${ally.name} HAS SAID ALL IT WANTS TO SAY ON THIS FLOOR.`, "dim");
    return render();
  }
  const text = await askText(`SAY TO ${ally.name}:`);
  if (!text) return render();
  ally.talkedFloor = G.floor;
  say(`YOU, TO ${ally.name}: "${text}"`, "you");
  G.busy = true;
  render();
  try {
    const r = await api("/api/ally-talk", {
      ally: { id: ally.id, species: ally.species, name: ally.name, traits: ally.traits, loyalty: ally.loyalty },
      message: text,
      vows: G.vows.filter((v) => v.toId === ally.id).map((v) => ({ text: v.text, status: v.status })),
    });
    ally.loyalty = clamp(ally.loyalty + r.loyaltyDelta);
    const color = colorOf(ally);
    say(`${ally.name}: ${r.line}`, "npc", color);
    speak(ally, r.line);
    const tell = reactionTell(ally.species, ally.name, r.level);
    if (tell) say(tell, "", color);
    if (r.buff) {
      ally.buff = r.buff;
      say(`${ally.name} IS ${r.buff.id}: ${UP(r.buff.desc)}.`, "big", color);
    }
    if (r.outcome) {
      if (r.outcome.id === "INSPIRED") {
        ally.hp = ally.maxHp;
        ally.xp += xpFor(ally.level);
        levelUp(ally);
      } else ally.mood = r.outcome;
      say(`${ally.name} ${UP(r.outcome.desc)}.`, r.level <= 1 ? "big warn" : "big", r.level <= 1 ? undefined : color);
    }
    dbg(`LANDED ${r.resonance.toFixed(1)}/4, LOYALTY ${r.loyaltyDelta >= 0 ? "+" : ""}${r.loyaltyDelta} → ${ally.loyalty} (${loyaltyWord(ally.loyalty)})`);
    sfx.play(r.level <= 0 ? "bad" : r.level === 1 ? "sad" : r.level >= 4 ? "levelup" : "good");
    showJev({ kind: "talk", ally, r });
  } catch (err) {
    say(`(JEV UNREACHABLE: ${err.message})`, "dim");
  }
  G.busy = false;
  render();
}

const clamp = (v) => Math.max(0, Math.min(100, Math.round(v)));

// ---------------------------------------------------------------- vows

const VERBS = [
  { id: "kill", label: "KILL" },
  { id: "talk", label: "TALK TO" },
  { id: "give", label: "GIVE GOLD TO" },
  { id: "run", label: "RUN FROM" },
  { id: "befriend", label: "BEFRIEND" },
];
const TARGETS = [
  { id: "slime", label: "SLIMES" },
  { id: "goblin", label: "GOBLINS" },
  { id: "dragon", label: "DRAGONS" },
  { id: "snake", label: "SNAKE PEOPLE" },
  { id: "rock", label: "ROCK ENTITIES" },
  { id: "bandit", label: "BANDITS" },
  { id: "monsters", label: "ANYONE" },
];
// Which game events break a vow. Vows are structured, so code checks them exactly.
const BREAKS = {
  kill: { will: ["spare"], wont: ["kill"] },
  talk: { will: ["attack_unspoken"], wont: ["talk"] },
  give: { will: ["kill"], wont: ["give"] },
  run: { will: ["attack"], wont: ["flee"] },
  befriend: { will: ["kill"], wont: ["recruit"] },
};
const MAX_VOWS = 6;

async function makeVow() {
  const inCombat = !!G.combat;
  let to;
  if (inCombat) {
    to = targetEnemy();
    if (G.combat.vowed) {
      say("YOU'VE ALREADY SWORN SOMETHING IN THIS FIGHT.", "dim");
      return render();
    }
  } else {
    to = await pickAlly("SWEAR TO WHOM?");
    if (!to) return render();
    if (to.vowFloor === G.floor) {
      say(`YOU'VE ALREADY SWORN TO ${to.name} ON THIS FLOOR.`, "dim");
      return render();
    }
  }
  if (G.vows.filter((v) => v.status === "active").length >= MAX_VOWS) {
    say("YOU CAN'T KEEP TRACK OF MORE PROMISES THAN THIS.", "dim");
    return render();
  }
  const will = await choose("I...", [
    { label: "WILL", value: true },
    { label: "WON'T", value: false },
  ]);
  if (will === null) return render();
  const verb = await choose(will ? "I WILL..." : "I WON'T...", VERBS.map((v) => ({ label: v.label, value: v })));
  if (!verb) return render();
  const target = await choose(`${will ? "I WILL" : "I WON'T"} ${verb.label}...`, TARGETS.map((t) => ({ label: t.label, value: t })));
  if (!target) return render();

  const text = `I ${will ? "WILL" : "WON'T"} ${verb.label} ${target.label}`;
  const vow = { id: `v${uid++}`, will, verb: verb.id, target: target.id, text, toId: to.id, toName: to.name, toSpecies: to.species, status: "active", floor: G.floor };
  G.vows.push(vow);
  if (inCombat) G.combat.vowed = true;
  else to.vowFloor = G.floor;
  say(`YOU SWEAR TO ${UP(to.name)}: "${text}"`, "you");
  if (inCombat) history(`The party swore to ${to.name}: "${text.toLowerCase()}".`);

  G.busy = true;
  render();
  try {
    const r = await api("/api/vow", { monster: { species: to.species, name: to.name, traits: to.traits }, vow: { text: text.toLowerCase() } });
    const color = colorOf(to);
    say(`${UP(to.name)}: ${r.line}`, "npc", color);
    speak(to, r.line);
    const tell = reactionTell(to.species, to.name, r.level);
    if (tell) say(tell, "", color);
    dbg(`${UP(to.name)} LIKES THE VOW ${r.liking.toFixed(1)}/4`);
    const shift = r.level - 2;
    if (inCombat) {
      to.meters.friendliness = clamp(to.meters.friendliness + shift * 9);
      to.meters.anger = clamp(to.meters.anger - shift * 5);
      to.impressions.push(`The party swore to you: "${text.toLowerCase()}".`);
    } else {
      to.loyalty = clamp(to.loyalty + shift * 5);
    }
    showJev({ kind: "vow", to, vow, r });
  } catch (err) {
    say(`(JEV UNREACHABLE: ${err.message})`, "dim");
  }
  G.busy = false;
  render();
}

// Something happened that could break a vow (kill, spare, talk, give, flee, attack, recruit a species).
function vowEvent(type, species, how) {
  for (const v of G.vows) {
    if (v.status !== "active") continue;
    if (v.target !== "monsters" && v.target !== species) continue;
    if (!BREAKS[v.verb][v.will ? "will" : "wont"].includes(type)) continue;
    v.status = "broken";
    v.fresh = true;
    v.justBroken = true;
    v.brokenHow = how;
    G.pendingBreaks.push(v);
  }
}

// Deal with broken vows: the wronged monster answers (Jev picks how), code applies it.
async function flushBreaks() {
  while (G.pendingBreaks.length) {
    const v = G.pendingBreaks.shift();
    say(`YOU BROKE YOUR VOW: "${v.text}"`, "big warn");
    sfx.play("slash");
    render();
    const ally = G.party.find((m) => m.id === v.toId && !m.dead);
    const enemy = G.combat?.enemies.find((e) => e.id === v.toId && e.status === "here");
    if (enemy) {
      enemy.meters.anger = clamp(enemy.meters.anger + 35);
      enemy.meters.friendliness = clamp(enemy.meters.friendliness - 35);
      enemy.impressions.push(`The party broke the promise it made to you: "${v.text.toLowerCase()}".`);
      enemy.thisRound.push(`The party just broke its promise to you: "${v.text.toLowerCase()}".`);
      say(`${UP(enemy.name)} SAW THAT.`, "warn", colorOf(enemy));
      continue;
    }
    if (!ally) {
      say("...BUT NO ONE IS LEFT TO HOLD YOU TO IT.", "dim");
      continue;
    }
    G.busy = true;
    render();
    let r;
    try {
      r = await api("/api/vow-broken", {
        monster: { species: ally.species, name: ally.name, traits: ally.traits, loyalty: ally.loyalty },
        vow: { text: v.text.toLowerCase() },
        how: v.brokenHow,
        gold: G.gold,
      });
    } catch (err) {
      say(`(JEV UNREACHABLE: ${err.message})`, "dim");
      G.busy = false;
      continue;
    }
    G.busy = false;
    showJev({ kind: "broken", ally, v, r });
    const color = colorOf(ally);
    // It wanted to forgive, but the wound runs too deep: say so, or the walk-out reads like a contradiction
    if (r.picked === "forgive" && r.response !== "forgive") say(cantForgiveLine(ally.species, ally.name), "", color);
    say(`${ally.name}: ${r.line}`, "npc", color);
    speak(ally, r.line);
    ally.loyalty = r.loyalty;
    if (r.response === "forgive") say(`${ally.name} STAYS. FOR NOW.`, "dim", color);
    if (r.response === "leave_party") {
      G.party = G.party.filter((m) => m !== ally);
      say(`${ally.name} LEAVES THE PARTY.`, "warn", color);
    }
    if (r.response === "steal_gold") {
      if (r.stolen) {
        const took = Math.min(G.gold, r.stolen);
        G.gold -= took;
        G.party = G.party.filter((m) => m !== ally);
        say(`${ally.name} RUNS OFF WITH ${took} GOLD!`, "big warn", color);
      } else say(`${ally.name} TRIES TO STEAL YOUR GOLD, BUT YOU CATCH IT. IT STAYS, SULKING.`, "warn", color);
    }
    if (r.response === "attack_party") {
      G.party = G.party.filter((m) => m !== ally);
      const foe = enemyFromAlly(ally, `The party broke its promise to you: "${v.text.toLowerCase()}". You turned on them.`);
      if (G.combat) {
        addEnemy(foe);
        say(`${ally.name} TURNS ON YOU!`, "big", color);
      } else {
        render();
        await encounter([foe]);
        return;
      }
    }
    render();
  }
}

// ---------------------------------------------------------------- roll of fate
// Clearing a floor earns one random boon. Strength scales with the floor you cleared, and boons compound.
// Beating a floor's red champion earns a GREAT roll: double strength, with a chance at legendary boons.

const BOONS = [
  {
    name: "WHETSTONE",
    weight: 5,
    target: "member",
    apply: (m, tier) => {
      const add = 0.12 * tier;
      m.mods.dmg *= 1 + add;
      return `${m.name} DEALS +${Math.round(add * 100)}% DAMAGE (NOW X${m.mods.dmg.toFixed(2)})`;
    },
  },
  {
    name: "KEEN EYE",
    weight: 4,
    target: "member",
    valid: (m) => m.mods.critMin > 15,
    apply: (m, tier) => {
      m.mods.critMin = Math.max(15, m.mods.critMin - Math.max(1, Math.round(tier / 3)));
      return `${m.name} NOW SCORES CRITICAL HITS ON A ${m.mods.critMin}-20 (CRITICAL HITS ROLL DOUBLE DAMAGE DICE)`;
    },
  },
  {
    name: "TRUE AIM",
    weight: 3,
    target: "member",
    apply: (m, tier) => {
      const add = Math.max(1, Math.round(tier / 2));
      m.mods.hitBonus += add;
      return `${m.name} GETS +${add} TO HIT (NOW +${m.mods.hitBonus} FROM BOONS)`;
    },
  },
  {
    name: "FLURRY",
    weight: 3,
    target: "member",
    valid: (m) => m.mods.hits < 8 && m.clsId !== "wizard",
    apply: (m) => {
      m.mods.hits = { 1: 2, 2: 3, 3: 4, 4: 8 }[m.mods.hits] ?? 8;
      return `${m.name} NOW STRIKES ${m.mods.hits} TIMES EVERY TURN`;
    },
  },
  {
    name: "IRON SKIN",
    weight: 3,
    target: "member",
    apply: (m, tier) => {
      const add = Math.max(1, Math.round(tier / 3));
      m.ac += add;
      return `${m.name}'S ARMOR RISES BY ${add} TO ${m.ac}. MONSTERS MISS IT MORE`;
    },
  },
  {
    name: "VAMPIRIC EDGE",
    weight: 2,
    target: "member",
    valid: (m) => m.clsId !== "wizard",
    apply: (m, tier) => {
      m.mods.lifesteal += 0.08 * tier;
      return `${m.name} HEALS ${Math.round(m.mods.lifesteal * 100)}% OF THE DAMAGE IT DEALS`;
    },
  },
  {
    name: "ARCANE SURGE",
    weight: 3,
    target: "caster",
    apply: (m, tier) => {
      m.bonusSlots[0] += 1 + Math.floor(tier / 3);
      if (tier >= 3) m.bonusSlots[1] += 1;
      if (tier >= 6) m.bonusSlots[2] += 1;
      refreshSlots(m, true);
      m.mods.spell *= 1 + 0.2 * tier;
      return `${m.name} GETS MORE SPELL SLOTS (NOW ${slotTotal(m)}) AND SPELLS HIT X${m.mods.spell.toFixed(2)}`;
    },
  },
  {
    name: "VIGOR",
    weight: 4,
    target: "party",
    apply: (party, tier) => {
      const add = 2 * tier;
      for (const m of party) {
        m.maxHp += add;
        m.hp += add;
      }
      return `THE WHOLE PARTY GAINS +${add} MAX HEALTH`;
    },
  },
  {
    name: "GOLDEN TOUCH",
    weight: 2,
    target: "global",
    apply: (_, tier) => {
      G.goldMult *= 1 + 0.15 * tier;
      return `ALL GOLD FROM MONSTERS IS NOW X${G.goldMult.toFixed(2)}`;
    },
  },
];

// Only a champion's great roll can land these.
const LEGENDARY = [
  {
    name: "PHOENIX FEATHER",
    weight: 3,
    target: "global",
    apply: () => {
      for (const m of G.party) {
        if (m.dead) revive(m, m.maxHp);
        m.phoenix = true;
      }
      return "THE FALLEN RISE AT FULL HEALTH, AND EVERYONE WILL CHEAT DEATH ONCE";
    },
  },
  {
    name: "LEGENDARY ARMS",
    weight: 3,
    target: "party",
    apply: (party) => {
      for (const m of party) {
        m.mods.dmg *= 1.5;
        m.mods.critMin = Math.max(15, m.mods.critMin - 1);
      }
      return "THE WHOLE PARTY DEALS X1.5 DAMAGE AND LANDS CRITICAL HITS MORE OFTEN";
    },
  },
  {
    name: "ARCHMAGE'S CROWN",
    weight: 2,
    target: "caster",
    apply: (m) => {
      m.bonusSlots = m.bonusSlots.map((n) => n + 2);
      refreshSlots(m, true);
      m.mods.spell *= 1.5;
      return `${m.name} GAINS 2 SPELL SLOTS OF EVERY CIRCLE (NOW ${slotTotal(m)}) AND SPELLS HIT X${m.mods.spell.toFixed(2)}`;
    },
  },
  {
    name: "TITAN'S BLOOD",
    weight: 3,
    target: "party",
    apply: (party, tier) => {
      const add = 3 * tier;
      for (const m of party) {
        m.maxHp += add;
        m.hp = m.maxHp;
      }
      return `THE WHOLE PARTY GAINS +${add} MAX HEALTH AND HEALS FULLY`;
    },
  },
  {
    name: "TWIN SOUL",
    weight: 2,
    target: "member",
    valid: (m) => m.mods.hits < 8 && m.clsId !== "wizard",
    apply: (m) => {
      m.mods.hits = Math.min(8, m.mods.hits * 2);
      return `${m.name} NOW STRIKES ${m.mods.hits} TIMES EVERY TURN`;
    },
  },
];

function targetsFor(boon) {
  for (const m of living()) m.mods ??= baseMods();
  if (boon.target === "party") return [living()];
  if (boon.target === "global") return [null];
  return living().filter((m) => (boon.target === "caster" ? !!m.maxSlots : true) && (boon.valid?.(m) ?? true));
}

function waitKey() {
  return new Promise((r) => {
    G.waitKey = r;
    render();
  });
}

// kind: "floor" (took the stairs), "shiny" (recruited a shiny), or a great roll from a champion.
// Picks and applies a random boon (no animation). The Roll of Fate shows it; test runs use it directly.
function drawBoon(tier, great = false, kind = "floor") {
  const pool = great && Math.random() < 0.6 ? LEGENDARY : BOONS;
  let options = pool.filter((b) => targetsFor(b).length);
  if (!options.length) options = BOONS.filter((b) => targetsFor(b).length);
  let r = Math.random() * options.reduce((t, b) => t + b.weight, 0);
  const boon = options.find((b) => (r -= b.weight) < 0) ?? options[0];
  const text = boon.apply(pick(targetsFor(boon)), great ? tier * 2 : tier);
  G.boons.push({ name: boon.name, text, floor: tier, great, kind });
  return { boon, text };
}

async function rollOfFate(tier, great = false, kind = "floor") {
  const { boon, text } = drawBoon(tier, great, kind);
  const names = (great ? [...LEGENDARY, ...BOONS] : BOONS).map((b) => b.name);
  G.roll = { start: performance.now(), names, result: { name: boon.name, text, tier }, landed: false, great, kind, lastIdx: -1 };
  G.busy = true;
  render();
  await sleep(great ? 2800 : 1900);
  G.roll.landed = true;
  G.roll.landedAt = performance.now();
  console.debug("roll of fate landed", boon.name, great ? "great" : kind);
  sfx.play(great ? "great" : "land");
  say(`${great ? "GREAT " : kind === "shiny" ? "SHINY " : ""}ROLL OF FATE: ${boon.name}! ${text}.`, "big", great ? BOSS_COLOR : kind === "shiny" ? SHINY_COLOR : G.map.palette.accent);
  render();
  await waitKey();
  G.roll = null;
  G.busy = false;
}

function drawRoll(t) {
  const ctx = view;
  const { width: W, height: H } = ctx.canvas;
  const r = G.roll;
  const pal = G.map.palette;
  const shiny = r.kind === "shiny";
  const ink = r.great ? BOSS_COLOR : shiny ? SHINY_COLOR : pal.wall;
  const hot = r.great ? "#ffd27a" : shiny ? "#ffffff" : pal.accent;
  ctx.fillStyle = "rgba(0,0,0,0.9)";
  ctx.fillRect(36, 36, W - 72, H - 72);
  ctx.strokeStyle = ink;
  ctx.lineWidth = 2;
  ctx.strokeRect(36.5, 36.5, W - 72, H - 72);
  if (r.great) ctx.strokeRect(41.5, 41.5, W - 82, H - 82);
  ctx.textAlign = "center";
  ctx.fillStyle = ink;
  ctx.font = `9px "Press Start 2P", monospace`;
  ctx.fillText(r.great ? `B${r.result.tier}F CHAMPION OVERCOME` : shiny ? "A SHINY JOINED YOUR PARTY" : `B${r.result.tier}F CLEARED`, W / 2, 64);
  ctx.font = `12px "Press Start 2P", monospace`;
  ctx.fillText(r.great ? "GREAT ROLL OF FATE" : shiny ? "SHINY ROLL OF FATE" : "ROLL OF FATE", W / 2, 86);
  const elapsed = t - r.start;
  // The names spin fast, then slow down before landing; each change ticks
  const idx = Math.floor(Math.sqrt(elapsed) * 0.9) % r.names.length;
  if (!r.landed && idx !== r.lastIdx) {
    r.lastIdx = idx;
    sfx.play("tick");
  }
  const name = r.landed ? r.result.name : r.names[idx];
  ctx.fillStyle = r.landed ? hot : ink;
  ctx.font = `${name.length > 14 ? 15 : 18}px "Press Start 2P", monospace`;
  // The landing: the name slams down (scale punch), the panel flashes, and a great roll glows
  const since = r.landed ? t - r.landedAt : -1;
  if (since >= 0 && since < DIE_ANIM_MS) {
    ctx.globalAlpha = (r.great ? 0.4 : 0.25) * (1 - since / DIE_ANIM_MS);
    ctx.fillRect(37, 37, W - 74, H - 74);
    ctx.globalAlpha = 1;
  }
  const punch = landPunch(since, r.great ? 0.7 : 0.45);
  ctx.save();
  ctx.translate(W / 2, 136);
  ctx.scale(punch, punch);
  if (r.landed && r.great) {
    ctx.shadowColor = hot;
    ctx.shadowBlur = 12;
  }
  ctx.fillText(name, 0, 0);
  ctx.restore();
  if (r.landed) {
    ctx.fillStyle = ink;
    ctx.font = `8px "Press Start 2P", monospace`;
    const words = r.result.text.split(" ");
    const lines = [""];
    for (const w of words) {
      if ((lines[lines.length - 1] + " " + w).trim().length > 40) lines.push(w);
      else lines[lines.length - 1] = (lines[lines.length - 1] + " " + w).trim();
    }
    lines.forEach((l, i) => ctx.fillText(l, W / 2, 170 + i * 14));
    if (Math.floor(t / 500) % 2 === 0) ctx.fillText("PRESS ANY KEY", W / 2, H - 52);
  }
  ctx.textAlign = "left";
}

function listBoons() {
  if (!G.boons.length) say("NO BOONS YET. CLEAR A FLOOR AND ROLL FOR ONE.", "dim");
  else for (const b of G.boons) say(`${floorName(b.floor)}: ${b.great ? "GREAT " : b.kind === "shiny" ? "SHINY " : ""}${b.name}: ${b.text}`, "dim");
  render();
}

function boonTitle(m) {
  const md = m.mods;
  if (!md) return "";
  const bits = [`LEVEL ${m.level ?? 1}`, `EXPERIENCE ${m.xp ?? 0} OF ${xpFor(m.level ?? 1)} TO THE NEXT LEVEL`, `DAMAGE X${md.dmg.toFixed(2)}`, `CRITICAL HITS ON A ${md.critMin === 20 ? "20" : `${md.critMin}-20`}`];
  if (md.hits > 1) bits.push(`STRIKES ${md.hits} TIMES A TURN`);
  if (m.abil) bits.push(Object.entries(m.abil).map(([k, v]) => `${ABILITY_WORDS[k]} ${sign(v)}`).join(" "));
  if (md.hitBonus) bits.push(`+${md.hitBonus} TO HIT`);
  if (md.lifesteal) bits.push(`HEALS ${Math.round(md.lifesteal * 100)}% OF THE DAMAGE IT DEALS`);
  if (m.phoenix) bits.push("WILL CHEAT DEATH ONCE");
  return ` title="${esc(bits.join(" · "))}"`;
}
const sign = (n) => (n >= 0 ? `+${n}` : `${n}`);

// ---------------------------------------------------------------- encounters & combat
// D&D-style: initiative, d20 attack rolls against armor class, damage dice, critical hits, saving throws,
// spell slots, conditions, and death saving throws at 0 HP. Jev still decides what every monster does.

const speciesForFloor = (f) => pickWeighted(floorRules(f).pool);

function groupSize(f) {
  const max = floorRules(f).maxGroup;
  const r = Math.random();
  if (max === 1) return 1;
  if (max === 2) return r < 0.6 ? 1 : 2;
  return f === 3 ? (r < 0.4 ? 1 : r < 0.85 ? 2 : 3) : r < 0.3 ? 1 : r < 0.7 ? 2 : 3;
}

function makeEnemy(species, takenNames = []) {
  const sp = SPECIES[species];
  const st = MONSTER_STATS[species];
  const f = G.floor;
  const elite = Math.random() < floorRules(f).elite;
  const shiny = Math.random() < SHINY_CHANCE;
  const hp = Math.round(rnd(...sp.hp) * hpScale(f) * (elite ? 1.5 : 1) * (shiny ? 1.3 : 1));
  const kin = allies().some((m) => m.species === species);
  const names = sp.names.filter((n) => !takenNames.includes(n));
  const traits = [...sp.traits].sort(() => Math.random() - 0.5).slice(0, 2);
  if (shiny) traits.push("a rare shiny gold one of its kind, and proud of it");
  if (elite) traits.push("a battle-scarred veteran, tougher than most of its kind");
  // Shinies are rarer and stronger: +30% HP, +1 AC, +1 to hit and saves, +10% damage
  const sh = shiny ? 1 : 0;
  return {
    species,
    shiny,
    elite,
    name: pick(names.length ? names : sp.names),
    traits,
    hp,
    maxHp: hp,
    // Bounded accuracy, as in 5e: armor and to-hit creep up slowly; HP and damage carry the scaling
    ac: st.ac + Math.min(3, Math.floor((f - 1) / 4)) + sh,
    hit: st.hit + Math.floor((f - 1) / 3) + (elite ? 2 : 0) + sh,
    dc: st.special.dc + Math.floor((f - 1) / 2) + sh,
    saveBonus: Math.floor((f - 1) / 3) + (elite ? 1 : 0) + sh,
    dmgMult: dmgScale(f) * (elite ? 1.2 : 1) * (shiny ? 1.1 : 1),
    dmg: sp.dmg.map((x) => Math.round(x * dmgScale(f) * (shiny ? 1.1 : 1))), // its damage range if it ever joins the party
    legendary: 0,
    multiattack: 1,
    recharge: 3,
    meters: { ...sp.start, friendliness: sp.start.friendliness + (kin ? 15 : 0) },
    cooldown: 0,
    paid: false,
    demanded: false,
    impressions: kin ? ["One of your own kind travels with this party."] : [],
    formerAlly: false,
    cond: {},
  };
}

// The floor's red champion: a normal monster of its kind, but far harder. Two attacks a turn, a faster
// special, and Legendary Resistance (it shrugs off the first two spells that would sleep or hold it).
function makeBoss(species) {
  const sp = SPECIES[species];
  const e = makeEnemy(species);
  const hp = Math.round(rnd(...sp.hp) * hpScale(G.floor) * 2.2);
  Object.assign(e, {
    boss: true,
    shiny: false,
    elite: false,
    name: `${e.name} the Red`,
    traits: [...e.traits.filter((t) => !/shiny|veteran/.test(t)).slice(0, 2), "the towering red champion of this floor, far stronger than others of its kind"],
    hp,
    maxHp: hp,
    ac: e.ac + 1,
    hit: e.hit + 2,
    dc: e.dc + 2,
    saveBonus: e.saveBonus + 3,
    dmgMult: e.dmgMult * 1.2,
    dmg: e.dmg.map((x) => Math.round(x * 1.2)),
    legendary: 2,
    multiattack: 2,
    recharge: 2,
    meters: { friendliness: Math.max(0, sp.start.friendliness - 15), anger: sp.start.anger + 10, fear: 0 },
  });
  return e;
}

function makeGroup() {
  const n = groupSize(G.floor);
  const group = [];
  for (let i = 0; i < n; i++) {
    let species = speciesForFloor(G.floor);
    if (species === "dragon" && group.some((e) => e.species === "dragon")) species = "goblin";
    group.push(makeEnemy(species, group.map((e) => e.name)));
  }
  return group;
}

function enemyFromAlly(ally, why) {
  const st = MONSTER_STATS[ally.species];
  return {
    species: ally.species,
    shiny: ally.shiny,
    boss: ally.boss,
    name: ally.name,
    traits: ally.traits,
    hp: Math.max(1, ally.hp),
    maxHp: ally.maxHp,
    ac: ally.ac,
    hit: 2 + prof(ally.level) + (ally.mods?.hitBonus ?? 0),
    dc: st.special.dc + Math.floor((G.floor - 1) / 2),
    saveBonus: Math.floor(ally.level / 3),
    dmgMult: dmgScale(G.floor),
    dmg: ally.dmg,
    legendary: ally.boss ? 2 : 0,
    multiattack: ally.boss ? 2 : 1,
    recharge: 3,
    meters: { friendliness: 10, anger: 75, fear: 5 },
    cooldown: 0,
    paid: true,
    demanded: false,
    impressions: [why],
    formerAlly: true,
    cond: {},
  };
}

const present = () => (G.combat ? G.combat.enemies.filter((e) => e.status === "here" && e.hp > 0) : []);
const targetEnemy = () => present().find((e) => e.id === G.combat.target) ?? present()[0];

function addEnemy(e) {
  const c = G.combat;
  Object.assign(e, { id: `e${c.nextId++}`, status: "here", grudges: [], thisRound: [], damageTaken: 0, side: "hostile to the party", cond: {} });
  c.enemies.push(e);
  if (!targetEnemy()) c.target = e.id;
  history(`${e.name}, ${aLabel(e.species)}, joined the fight${e.formerAlly ? " against the party" : ""}.`);
}

async function encounter(group = makeGroup(), opts = {}) {
  sfx.play(opts.boss ? "boss" : "encounter");
  music.setMood("battle");
  G.combat = { enemies: [], nextId: 0, target: null, round: 0, conversation: [], history: [], rounds: {}, spoken: new Set(), vowed: false, kills: 0, recruits: [], boss: !!opts.boss };
  G.mode = "combat";
  G.graceSteps = 5;
  for (const e of group) {
    addEnemy(e);
    const sp = SPECIES[e.species];
    const article = /^[aeiou]/.test(sp.label) ? "AN" : "A";
    if (e.boss) say(`${UP(e.name)}, CHAMPION OF ${floorName(G.floor)}! ${e.maxHp} HEALTH, ARMOR ${e.ac}, TWO ATTACKS A TURN.`, "big", BOSS_COLOR);
    else
      say(
        e.formerAlly ? `${UP(e.name)} TURNS ON YOU!` : e.shiny ? `A SHINY ${UP(sp.label)} APPEARS! IT GLITTERS GOLD!` : `${e.elite ? "A VETERAN" : article} ${UP(sp.label)} APPEARS!`,
        "big",
        colorOf(e),
      );
    if (!e.formerAlly && !e.boss) say(`IT IS ${UP(e.name)}, ${UP(e.traits.slice(0, 2).join(" and "))}. ARMOR ${e.ac}.`, "dim");
  }
  G.combat.target = G.combat.enemies[0].id;
  G.combat.history = G.combat.history.map((h) => h.replace("joined the fight", "was met by the party"));
  applyOpeningBuffs();
  // Initiative: the party's quickest member against the quickest monster
  const pDex = Math.max(...conscious().map((m) => m.abil?.dex ?? 1));
  const mDex = Math.max(...present().map((e) => MONSTER_STATS[e.species].dex + (e.boss ? 2 : 0)), -5);
  const pd = d20();
  const md = d20();
  const pr = pd.roll + pDex;
  const mr = md.roll + mDex;
  const first = pr >= mr;
  rollFx(pd, { x: 112, y: 226 }, { label: `PARTY ${pr}` });
  rollFx(md, { x: 336, y: 226 }, { label: `FOES ${mr}` });
  say(`WHO MOVES FIRST: PARTY ROLLED ${pr}, MONSTERS ${mr}. ${first ? "YOU ACT FIRST!" : "THEY ACT FIRST!"}`, first ? "" : "warn");
  hint("combat");
  if (present().length > 1) hint("target");
  render();
  if (!present().length) return endCombat();
  if (first) {
    G.combat.opening = "The party just came face to face with you in a dungeon corridor, and moved before you could.";
    return beginPartyTurn();
  }
  await monstersTurn({ type: "start" }, ["The party just came face to face with you in a dungeon corridor."], {});
}

// Buffs earned by talking to allies: they fire on the next fight, then they're spent.
function applyOpeningBuffs() {
  const c = G.combat;
  c.pumped = new Set();
  for (const a of allies()) {
    if (!a.buff) continue;
    const color = colorOf(a);
    const scaled = (dice) => Math.round(rollDice(dice) * dmgScale(G.floor) * (a.mods?.dmg ?? 1));
    if (a.buff.id === "STORMING") {
      say(`${a.name} OPENS WITH A STORM OF LIGHTNING!`, "big", color);
      sfx.play("fireball");
      for (const e of present()) {
        const dmg = scaled("3d6");
        hitEnemy(e, dmg, `${a.name}'s lightning hit you for ${dmg}.`, "#ffe03a");
        say(`${UP(e.name)} TAKES ${dmg}.`, "", color);
      }
      reapEnemies(a);
    }
    if (a.buff.id === "BOUNCY") {
      c.bouncy = a;
      c.soaks = 1;
      say(`${a.name} BOUNCES IN FRONT OF THE PARTY, READY TO SOAK A BLOW.`, "", color);
    }
    if (a.buff.id === "BULWARK") {
      c.bouncy = a;
      c.soaks = 2;
      say(`${a.name} PLANTS ITSELF IN FRONT OF THE PARTY LIKE A WALL.`, "", color);
    }
    if (a.buff.id === "VENOMOUS") {
      const e = present()[0];
      if (e) {
        const dmg = scaled("2d6+2");
        say(`${a.name} STRIKES FIRST WITH A VENOMOUS BITE! ${UP(e.name)} TAKES ${dmg}.`, "big", color);
        sfx.play("hit");
        hitEnemy(e, dmg, `${a.name}'s venom hit you for ${dmg}.`, "#9ed36b");
        reapEnemies(a);
      }
    }
    if (a.buff.id === "SNEAKY") {
      c.goldBonus = 1.5;
      say(`${a.name} IS ALREADY EYEING THE LOOT. +50% GOLD THIS FIGHT.`, "", color);
    }
    if (a.buff.id === "PUMPED") {
      c.pumped.add(a.id);
      say(`${a.name} IS PUMPED. DOUBLE DAMAGE THIS FIGHT!`, "", color);
    }
    a.buff = null;
  }
}

function history(text) {
  const h = G.combat.history;
  if (h[h.length - 1] !== text) h.push(text);
}

function hitEnemy(e, dmg, note, color = "#ffffff") {
  e.hp -= dmg;
  e.damageTaken = (e.damageTaken ?? 0) + dmg;
  e.thisRound.push(note);
  hurtUntil[e.id] = fxNow() + 300;
  floatOn(e, `-${dmg}`, color, 13);
  if (e.cond.asleep) {
    delete e.cond.asleep;
    if (e.hp > 0) say(`${UP(e.name)} WAKES UP!`, "dim");
  }
}

// Anyone brought to 0 HP by the last action dies now (after the attack lines are logged).
function reapEnemies(killer) {
  for (const e of G.combat?.enemies ?? []) if (e.status === "here" && e.hp <= 0) killEnemy(e, killer);
}

const xpOf = (e) => Math.round(SPECIES[e.species].xp * (1 + 0.25 * (G.floor - 1)) * (e.shiny ? 1.5 : 1) * (e.boss ? 4 : e.elite ? 1.5 : 1));

// An enemy dies. `by` is a party member (or an ally's buff); monster-on-monster kills pass `byMonster`.
function killEnemy(e, by, byMonster) {
  const c = G.combat;
  const sp = SPECIES[e.species];
  e.status = "dead";
  const depth = 1 + 0.3 * (G.floor - 1);
  const bonus = (e.shiny ? 2 : 1) * (e.boss ? 5 : e.elite ? 1.5 : 1) * (c.goldBonus ?? 1) * G.goldMult;
  const gold = Math.round(rnd(...sp.gold) * depth * bonus * (byMonster ? 0.5 : 1));
  const xp = Math.round(xpOf(e) * (byMonster ? 0.5 : 1));
  G.gold += gold;
  sfx.play("kill");
  if (byMonster) {
    say(`${UP(e.name)} IS KILLED BY ${UP(byMonster.name)}! +${xp} EXPERIENCE, +${gold} GOLD.`, "big", colorOf(e));
    history(`${byMonster.name} killed ${e.name}.`);
    for (const o of present()) o.thisRound.push(`${byMonster.name} killed ${e.name}.`);
  } else {
    c.kills++;
    say(`${UP(e.name)} IS SLAIN! +${xp} EXPERIENCE, +${gold} GOLD.`, "big", colorOf(e));
    const last = c.lastLines?.[e.id];
    history(`The party killed ${e.name}, the ${sp.label}, and took ${gold} gold.${last ? ` Its last words were: "${last}"` : ""}`);
    vowEvent("kill", e.species, `The party killed ${e.name}, ${aLabel(e.species)}${last ? `, whose last words were "${last}"` : ""}.`);
    for (const o of present()) o.thisRound.push(`The party killed ${e.name}.`);
  }
  grantXp(xp);
  if (c.target === e.id) c.target = present()[0]?.id ?? null;
}

// ---- dice helpers for the party

// Advantage (+1), disadvantage (-1) or neither (0) when `attacker` attacks monster `e`. Both cancel, as in 5e.
function advVs(e, attacker) {
  const c = e.cond;
  const a = attacker.cond ?? {};
  const adv = c.asleep || c.held || c.exposed || c.lit ? 1 : 0;
  const dis = c.dodging || a.poisoned || a.restrained ? 1 : 0;
  return adv - dis;
}
const effAC = (e) => e.ac - (e.cond.enraged ? 3 : 0);
const moodHit = (m) => (m.mood?.id === "DISTRACTED" ? -2 : m.mood?.id === "STEADY" ? 1 : 0);
function attackBonus(m) {
  if (m.kind === "human") return prof(m.level) + m.abil[CLASSES[m.clsId].weapon.stat] + m.mods.hitBonus;
  return 2 + prof(m.level) + m.mods.hitBonus + moodHit(m);
}
function weaponDamage(m, crit) {
  let dmg;
  if (m.kind === "human") {
    const w = CLASSES[m.clsId].weapon;
    dmg = rollDice(w.dice, { crit }) + m.abil[w.stat];
  } else dmg = rnd(...m.dmg) + (crit ? rnd(...m.dmg) : 0);
  if (G.combat.pumped?.has(m.id)) dmg *= 2;
  return Math.max(1, Math.round(dmg * m.mods.dmg));
}
const attackCount = (m) => (m.clsId === "fighter" && m.level >= 5 ? 2 : 1) * m.mods.hits;
const spellDC = (m) => 8 + prof(m.level) + m.abil[CLASSES[m.clsId].caster];
const spellAttack = (m) => prof(m.level) + m.abil[CLASSES[m.clsId].caster] + m.mods.hitBonus;
const spellDamage = (m, total) => Math.max(1, Math.round(total * m.mods.spell * m.mods.dmg));
function monsterSave(e, stat) {
  const r = d20();
  const total = r.roll + MONSTER_STATS[e.species].saves[stat] + e.saveBonus;
  rollFx(r, spotOf(e), { total });
  return total;
}
// "ROLLED 12, NEEDED 14": a saving throw in the log, without DC jargon
const saveText = (sv, dc) => `ROLLED ${sv}, NEEDED ${dc}`;

function partySave(v, stat) {
  const bless = G.combat?.blessed ? d(4) : 0;
  const r = d20();
  const total = r.roll + bless + (v.kind === "human" ? v.abil[stat] + (CLASSES[v.clsId].saves.includes(stat) ? prof(v.level) : 0) : 2 + Math.floor(v.level / 4));
  rollFx(r, spotOf(v), { total });
  return total;
}

// Bosses can refuse to fail: the first two times a spell would sleep or hold them.
function useLegendary(e) {
  if (!(e.legendary > 0)) return false;
  e.legendary--;
  say(`${UP(e.name)} SHRUGS IT OFF! (LEGENDARY RESISTANCE, ${e.legendary} LEFT)`, "warn", colorOf(e));
  floatOn(e, "RESISTED", colorOf(e), 9);
  return true;
}

// One creature's weapon attacks this turn. Up to three attacks are logged one by one; more get a summary.
async function weaponAttacks(m, attacks) {
  const c = G.combat;
  const color = m.kind === "monster" ? colorOf(m) : undefined;
  const results = [];
  for (let i = 0; i < attacks; i++) {
    const e = targetEnemy();
    if (!e) break;
    if (m.kind === "monster" && m.species === e.species) {
      say(`${m.name} WON'T ATTACK ITS OWN KIND.`, "dim", color);
      return `refused to fight ${e.name}, one of its own kind`;
    }
    const r = d20(advVs(e, m));
    const bonus = attackBonus(m) + (e.cond.weakspot ? 2 : 0) + (c.blessed ? d(4) : 0);
    if (attacks <= 3) rollFx(r, spotOf(e), { total: r.roll + bonus });
    const ac = effAC(e);
    const helpless = e.cond.asleep || e.cond.held;
    const meets = r.roll + bonus >= ac;
    const crit = r.roll !== 1 && (r.roll >= m.mods.critMin || (helpless && meets));
    const hit = r.roll !== 1 && (crit || meets);
    delete e.cond.lit;
    let dmg = 0;
    if (hit) {
      dmg = weaponDamage(m, crit);
      if (m.mods.lifesteal) m.hp = Math.min(m.maxHp, m.hp + Math.ceil(dmg * m.mods.lifesteal));
      hitEnemy(e, dmg, `${m.name} hit you${crit ? " with a critical blow" : ""} for ${dmg}.`, crit ? "#ffe03a" : "#ffffff");
      if (crit) floatOn(e, "CRITICAL!", "#ffe03a", 9);
    } else floatOn(e, r.roll === 1 ? "FUMBLE" : "MISS", "#8a8a8a", 9);
    sfx.play(crit ? "crit" : hit ? "hit" : "miss");
    results.push({ e, hit, crit, dmg });
    if (attacks <= 3) {
      const verdict = !hit ? (r.roll === 1 ? "A 1 ALWAYS MISSES. FUMBLE!" : "MISS.") : `${r.roll === 20 ? "A PERFECT 20! CRITICAL HIT! " : crit ? "CRITICAL HIT! " : "HIT! "}${dmg} DAMAGE.`;
      say(`${m.name} ATTACKS ${UP(e.name)}: ${fmtRoll(r, bonus)} VS ARMOR ${ac}. ${verdict}`, hit ? (crit ? "big" : "") : "dim", color);
      render();
      if (i < attacks - 1) await sleep(240);
    }
  }
  if (attacks > 3 && results.length) {
    const hits = results.filter((x) => x.hit);
    const crits = hits.filter((x) => x.crit).length;
    const total = hits.reduce((t, x) => t + x.dmg, 0);
    say(`${m.name} STRIKES ${attacks} TIMES: ${hits.length} HIT${crits ? ` (${crits} CRITICAL)` : ""} FOR ${total} DAMAGE.`, crits ? "big" : "", color);
  }
  reapEnemies(m);
  const total = results.reduce((t, x) => t + x.dmg, 0);
  const names = [...new Set(results.map((x) => x.e.name))].join(" and ");
  return total ? `hit ${names} for ${total}` : `swung at ${names || "the monsters"} and missed`;
}

async function castSpell(m, key, ally) {
  const s = SPELLS[key];
  const c = G.combat;
  if (s.lvl) m.slots[s.lvl - 1]--;
  const dice = s.cantrip ? `${cantripDice(m.level)}${s.dice.slice(1)}` : s.dice;
  say(`${m.name} CASTS ${s.name}!`, "you");
  sfx.play(s.sfx);
  render();
  await sleep(220);
  const parts = [];
  let note = `cast ${s.name.toLowerCase()}`;
  switch (s.kind) {
    case "attack": {
      for (let i = 0; i < (s.rays ?? 1); i++) {
        const e = targetEnemy();
        if (!e) break;
        const r = d20(advVs(e, m));
        const bonus = spellAttack(m) + (e.cond.weakspot ? 2 : 0) + (c.blessed ? d(4) : 0);
        rollFx(r, spotOf(e), { total: r.roll + bonus });
        const ac = effAC(e);
        const crit = r.roll !== 1 && r.roll >= m.mods.critMin;
        const hit = r.roll !== 1 && (crit || r.roll + bonus >= ac);
        delete e.cond.lit;
        const who = `${UP(e.name)} `;
        if (hit) {
          const dmg = spellDamage(m, rollDice(dice, { crit }));
          hitEnemy(e, dmg, `${m.name}'s ${s.name.toLowerCase()} hit you for ${dmg}.`, crit ? "#ffe03a" : "#ff9a3d");
          if (s.effect === "lit") e.cond.lit = 2;
          parts.push(`${who}${fmtRoll(r, bonus)} VS ARMOR ${ac}: ${crit ? "CRITICAL HIT, " : ""}${dmg} DAMAGE${s.effect === "lit" ? ". IT GLOWS: THE NEXT ATTACK ON IT IS BETTER" : ""}`);
          sfx.play(crit ? "crit" : "hit");
        } else {
          floatOn(e, "MISS", "#8a8a8a", 9);
          parts.push(`${who}${fmtRoll(r, bonus)} VS ARMOR ${ac}: MISS`);
        }
      }
      break;
    }
    case "auto": {
      const tally = {};
      for (let i = 0; i < s.darts; i++) {
        const e = targetEnemy();
        if (!e) break;
        const dmg = spellDamage(m, rollDice(dice));
        hitEnemy(e, dmg, `${m.name}'s magic dart hit you for ${dmg}.`, "#b79cf0");
        (tally[UP(e.name)] ??= []).push(dmg);
        await sleep(90);
      }
      for (const [n, ds] of Object.entries(tally)) parts.push(`${n} TAKES ${ds.join(" + ")} = ${ds.reduce((a, b) => a + b, 0)}`);
      break;
    }
    case "save": {
      const dc = spellDC(m);
      const targets = s.target === "all" ? present() : [targetEnemy()].filter(Boolean);
      for (const e of targets) {
        const sv = monsterSave(e, s.save);
        if (s.effect === "held") {
          if (sv >= dc || useLegendary(e)) parts.push(`${UP(e.name)} RESISTS (${saveText(sv, dc)})`);
          else {
            e.cond.held = 1;
            e.holdDC = dc;
            floatOn(e, "PARALYZED", "#8fd3ff", 9);
            parts.push(`${UP(e.name)} IS PARALYZED (${saveText(sv, dc)})! IT LOSES TURNS AND YOUR HITS ARE CRITICAL`);
          }
          continue;
        }
        const saved = sv >= dc;
        let dmg = spellDamage(m, rollDice(dice));
        if (saved) dmg = s.half ? Math.floor(dmg / 2) : 0;
        if (dmg > 0) hitEnemy(e, dmg, `${m.name}'s ${s.name.toLowerCase()} hit you for ${dmg}.`, "#ff9a3d");
        else floatOn(e, "DODGED", "#8a8a8a", 9);
        parts.push(`${UP(e.name)} ${saved ? (s.half ? "DODGES HALF" : "DODGES IT") : "IS HIT"} (${saveText(sv, dc)}): ${dmg} DAMAGE`);
      }
      break;
    }
    case "sleep": {
      // A pool of hit points: the weakest monsters drop off first. Grows with depth so it stays useful.
      let pool = Math.round(rollDice(dice) * m.mods.spell * hpScale(G.floor) * 0.7);
      parts.push(`SLEEP STRONG ENOUGH FOR ${pool} HEALTH`);
      const slept = [];
      for (const e of [...present()].sort((a, b) => a.hp - b.hp)) {
        if (e.hp > pool) break;
        if (useLegendary(e)) continue;
        pool -= e.hp;
        e.cond.asleep = 10;
        floatOn(e, "ASLEEP", "#8fd3ff", 9);
        slept.push(UP(e.name));
      }
      parts.push(slept.length ? `${slept.join(" AND ")} FALL${slept.length > 1 ? "" : "S"} ASLEEP` : "NO ONE IS WEAK ENOUGH TO SLEEP");
      note = slept.length ? `put ${slept.join(" and ")} to sleep` : "tried to cast a sleep spell";
      break;
    }
    case "heal": {
      for (const x of s.target === "party" ? living() : [ally]) {
        const amt = Math.max(1, Math.round((rollDice(dice) + m.abil.wis) * m.mods.spell));
        heal(x, amt);
        parts.push(`${x.name} +${amt}`);
      }
      note = `healed ${s.target === "party" ? "the party" : ally.name}`;
      break;
    }
    case "bless":
      c.blessed = true;
      parts.push("THE PARTY GETS +1 TO 4 ON ATTACKS AND SAVES THIS FIGHT");
      note = "blessed the party";
      break;
    case "revive":
      revive(ally);
      note = `brought ${ally.name} back from the dead`;
      break;
  }
  if (parts.length) say(`${s.name}: ${parts.join(" · ")}.`, "", "#8fd3ff");
  reapEnemies(m);
  return note;
}

function heal(x, amt) {
  if (x.dead) return;
  if (x.down) {
    x.down = false;
    x.stable = false;
    x.hp = 0;
    say(`${x.name} GETS BACK UP!`, "big");
  }
  x.hp = Math.min(x.maxHp, x.hp + amt);
  floatParty(x, `+${amt}`, "#9ed36b");
}

function revive(x, hp = 1) {
  x.dead = false;
  x.down = false;
  x.stable = false;
  x.cond = {};
  x.hp = hp;
  say(`${x.name} GASPS BACK TO LIFE WITH ${hp} HEALTH!`, "big", "#ffd27a");
  sfx.play("revive");
  if (G.combat) history(`${x.name} was brought back from the dead.`);
}

// ---- the party's turn

// What a member does on QUICK ATTACK: weapons for most, the free Fire Bolt for the wizard.
function defaultPlan(m) {
  if (m.cond?.prone) return { m, act: "prone" };
  if (m.kind === "monster") return { m, act: "ally" };
  if (m.clsId === "wizard") return { m, act: "spell", spell: "fire_bolt" };
  return { m, act: "attack" };
}

// CHOOSE MOVES: pick an action for each adventurer in turn (allies act on their own). ESC cancels the turn.
// Each menu shows the member's spell slots by the title; spells show the slots they'd spend, or FREE.
async function planTurn() {
  const plans = [];
  const orderable = conscious().filter((m) => m.kind === "human" && !m.cond.prone);
  for (const m of conscious()) {
    if (m.kind !== "human" || m.cond.prone) {
      plans.push(defaultPlan(m));
      continue;
    }
    const w = CLASSES[m.clsId].weapon;
    const swings = attackCount(m);
    const opts = [{ label: `ATTACK WITH ${w.name}`, value: { act: "attack" }, hint: `HIT YOUR TARGET WITH THE ${w.name}${swings > 1 ? `, ${swings} TIMES` : ""}. ROLLS TO HIT AGAINST ITS ARMOR` }];
    if (m.uses.second_wind) opts.push({ label: "SECOND WIND", value: { act: "second_wind" }, hint: `HEAL ${diceRange(`1d10+${m.level}`)}, THEN ATTACK. ONCE PER CAMP` });
    if (m.uses.action_surge) opts.push({ label: "ACTION SURGE", value: { act: "action_surge" }, hint: "ATTACK TWICE AS MANY TIMES THIS TURN. ONCE PER CAMP" });
    if (m.slots) {
      for (const k of spellsKnown(m.clsId, m.level)) {
        const s = SPELLS[k];
        if (s.lvl && !(m.slots[s.lvl - 1] > 0)) continue;
        if (s.target === "dead" && !G.party.some((x) => x.dead)) continue;
        if (s.kind === "bless" && G.combat.blessed) continue;
        const cost = s.lvl ? `USES A ${CIRCLE_WORDS[s.lvl - 1]}-CIRCLE SLOT` : "FREE, USES NO SLOT";
        opts.push({ label: s.name, value: { act: "spell", spell: k }, cost: s.lvl, hint: `${spellText(k, m.level)}. ${cost}` });
      }
    }
    const nth = orderable.length > 1 ? ` (${orderable.indexOf(m) + 1} OF ${orderable.length})` : "";
    const choice = await choose(`WHAT WILL ${m.name} DO?${nth}`, opts, { who: m });
    if (!choice) return null;
    const plan = { m, ...choice };
    const s = SPELLS[plan.spell];
    if (s?.target === "ally") {
      const whom = living().map((x) => {
        const st = hpState(x);
        return { label: x.name, value: x, who: x, hint: `${x.name}: ${Math.max(0, x.hp)} OF ${x.maxHp} HEALTH, ${st.word}` };
      });
      plan.ally = await choose(`${s.name}: HEAL WHOM?`, whom);
      if (!plan.ally) return null;
    }
    if (s?.target === "dead") {
      plan.ally = await choose("REVIVIFY: BRING WHOM BACK?", G.party.filter((x) => x.dead).map((x) => ({ label: x.name, value: x })));
      if (!plan.ally) return null;
    }
    plans.push(plan);
  }
  return plans;
}

async function act(p) {
  const { m } = p;
  switch (p.act) {
    case "prone":
      delete m.cond.prone;
      say(`${m.name} STRUGGLES BACK UP AND LOSES THE TURN.`, "dim", m.kind === "monster" ? colorOf(m) : undefined);
      return "got back up after being knocked down";
    case "ally":
      return allyTurn(m);
    case "attack":
      return weaponAttacks(m, attackCount(m));
    case "second_wind": {
      m.uses.second_wind = 0;
      const amt = d(10) + m.level;
      say(`${m.name} CATCHES A SECOND WIND!`, "you");
      sfx.play("heal");
      heal(m, amt);
      return `caught a second wind, then ${await weaponAttacks(m, attackCount(m))}`;
    }
    case "action_surge":
      m.uses.action_surge = 0;
      say(`${m.name} SURGES INTO ACTION!`, "big");
      sfx.play("buff");
      return weaponAttacks(m, attackCount(m) * 2);
    case "spell":
      return castSpell(m, p.spell, p.ally);
  }
  return "";
}

// Monster allies fight on their own: their species' special every few rounds, otherwise their attack.
async function allyTurn(a) {
  const e = targetEnemy();
  if (!e) return "";
  if (a.mood?.id === "SULKING") {
    say(`${a.name} SULKS AND SITS THIS FIGHT OUT.`, "dim", colorOf(a));
    return "sulked and refused to fight";
  }
  a.cooldown = (a.cooldown ?? 0) - 1;
  if (a.cooldown <= 0 && a.species !== e.species && Math.random() < 0.5) {
    a.cooldown = 3;
    const sp = SPECIES[a.species];
    const st = MONSTER_STATS[a.species].special;
    const dc = st.dc + Math.floor((a.level - 1) / 2);
    const targets = sp.special.all ? present().filter((x) => x.species !== a.species) : [e];
    const parts = [];
    sfx.play(a.species === "dragon" ? "fireball" : "crit");
    for (const t of targets) {
      const sv = monsterSave(t, st.save);
      let dmg = Math.max(1, Math.round(rollDice(st.dice) * (1 + 0.15 * (a.level - 1)) * a.mods.dmg));
      if (sv >= dc) dmg = Math.floor(dmg / 2);
      hitEnemy(t, dmg, `${a.name}'s special attack hit you for ${dmg}.`, colorOf(a));
      parts.push(`${UP(t.name)} ${sv >= dc ? "DODGES HALF" : "IS HIT"} (${saveText(sv, dc)}): ${dmg} DAMAGE`);
    }
    say(`${a.name} USES ITS SPECIAL: ${UP(sp.special.desc).replace("ONE PARTY MEMBER", "THE FOE").replace("THE WHOLE PARTY", "THE MONSTERS")}! ${parts.join(" · ")}.`, "big", colorOf(a));
    reapEnemies(a);
    return `used its special attack on ${targets.map((t) => t.name).join(" and ")}`;
  }
  return weaponAttacks(a, a.mods.hits);
}

async function partyTurn(plans) {
  const c = G.combat;
  G.busy = true;
  render();
  const target = targetEnemy();
  const offensive = plans.some((p) => p.act !== "prone" && !(p.spell && ["heal", "bless", "revive"].includes(SPELLS[p.spell].kind)));
  if (offensive && target) {
    if (!c.spoken.has(target.species)) vowEvent("attack_unspoken", target.species, `The party attacked ${target.name} without saying a word to it first.`);
    vowEvent("attack", target.species, `The party attacked ${target.name}, ${aLabel(target.species)}.`);
  }
  const did = {};
  for (const p of plans) {
    if (!present().length) break;
    if (p.m.dead || p.m.down) continue;
    did[p.m.id] = await act(p);
    render();
    await sleep(380);
  }
  // Poison and bindings wear off over a few of your turns
  for (const m of G.party)
    for (const k of ["poisoned", "restrained"])
      if (m.cond?.[k] && --m.cond[k] <= 0) {
        delete m.cond[k];
        say(`${m.name} IS NO LONGER ${CONDITIONS[k].word}.`, "dim");
      }
  const cast = plans.some((p) => p.act === "spell" && !SPELLS[p.spell].cantrip);
  if (target && offensive) {
    c.rounds[target.id] = (c.rounds[target.id] ?? 0) + 1;
    const n = c.rounds[target.id];
    const line = `The party attacked ${target.name}${n > 1 ? ` for ${n} rounds` : ""}.`;
    const at = c.history.findIndex((h) => h.startsWith(`The party attacked ${target.name}`));
    if (at >= 0) c.history[at] = line;
    else history(line);
  }
  const events = Object.entries(did).map(([id, what]) => `${G.party.find((m) => m.id === id)?.name ?? "Someone"} ${what}.`);
  return afterPartyAction({ type: cast ? "cast" : "fight", targetId: target?.id }, events.slice(0, 8), did);
}

// A Charisma check for whoever does the talking. Good delivery makes words land harder, either way.
function charismaCheck() {
  const f = face();
  if (!f) return 1;
  const r = d20();
  const bonus = f.abil.cha + prof(f.level);
  const total = r.roll + bonus;
  const [mult, word] =
    r.roll === 20 ? [2, "AN INSPIRED"] : r.roll === 1 ? [0.5, "A TONGUE-TIED"] : total >= 20 ? [1.5, "A MAGNETIC"] : total >= 15 ? [1.25, "A CONFIDENT"] : total >= 10 ? [1, "A STEADY"] : [0.75, "A SHAKY"];
  rollFx(r, spotOf(f), { total });
  say(`HOW WELL ${f.name} SAYS IT (CHARISMA): ${fmtRoll(r, bonus)}. ${word} DELIVERY: WORDS LAND X${mult}.`, "dim");
  return mult;
}

// Ask the targeted monster to join: a Persuasion roll against a DC set by how it feels about you.
async function recruitAsk() {
  const c = G.combat;
  const e = targetEnemy();
  if (G.party.length >= 6) {
    say("YOUR PARTY IS FULL (6).", "dim");
    return render();
  }
  const f = face();
  if (!f) {
    say("NO ONE IS IN ANY STATE TO TALK.", "dim");
    return render();
  }
  const text = await askText(`ASK ${UP(e.name)} TO JOIN YOU. ADD WORDS, OR JUST PRESS ENTER:`);
  if (text === undefined) return render();
  const need = SPECIES[e.species].joinThreshold + (e.formerAlly ? 15 : 0) + (e.boss ? 20 : 0);
  // Harder when it dislikes or is angry at you; easier once it is losing the fight
  const losing = e.hp / e.maxHp < 0.35 ? 3 : 0;
  const dc = Math.max(5, Math.min(25, 8 + Math.round((need - e.meters.friendliness) / 4) + Math.round(e.meters.anger / 15) - losing));
  const r = d20();
  const bonus = f.abil.cha + prof(f.level);
  const margin = r.roll + bonus - dc;
  const pitch = r.roll === 20 || margin >= 8 ? "great" : r.roll === 1 || margin <= -12 ? "botch" : margin >= 0 ? "success" : margin >= -4 ? "close" : "fail";
  const WORD = { great: "AN IRRESISTIBLE PITCH!", success: "A CONVINCING PITCH.", close: "SO CLOSE...", fail: "A CLUMSY PITCH.", botch: "A DISASTROUS PITCH!" };
  say(text ? `YOU, TO ${UP(e.name)}: "${text}"` : `YOU ASK ${UP(e.name)} TO JOIN YOUR PARTY.`, "you");
  rollFx(r, spotOf(e), { total: r.roll + bonus });
  say(`PERSUASION (${f.name}): ${fmtRoll(r, bonus)}, NEEDED ${dc}. ${WORD[pitch]}`, ["great", "success"].includes(pitch) ? "big" : pitch === "close" ? "" : "warn");
  for (const x of present()) {
    c.spoken.add(x.species);
    vowEvent("talk", x.species, `The party talked to ${x.name}, ${aLabel(x.species)}.`);
  }
  history(`The party asked ${e.name} to join them${text ? `, saying: "${text}"` : ""}.`);
  const delivery = r.roll === 20 ? 2 : pitch === "great" ? 1.5 : pitch === "success" ? 1.25 : pitch === "botch" ? 0.5 : 1;
  return afterPartyAction({ type: "recruit", targetId: e.id, pitch, message: text || null, delivery }, [`The party asked ${e.name} to join them.`], {
    [f.id]: `asked ${e.name} to join the party`,
  });
}

async function command(cmd) {
  const c = G.combat;
  if (!c || G.busy) return;
  const here = present();
  if (/^[1-3]$/.test(cmd)) {
    const e = here[Number(cmd) - 1];
    if (e) c.target = e.id;
    return render();
  }
  const target = targetEnemy();
  if (!target) return;

  if (cmd === "f") return partyTurn(conscious().map(defaultPlan));
  if (cmd === "c") {
    const plans = await planTurn();
    if (!plans) return render();
    return partyTurn(plans);
  }

  if (cmd === "t") {
    const text = await askText(here.length > 1 ? "WHAT DO YOU SAY? (ALL OF THEM HEAR)" : "WHAT DO YOU SAY?");
    if (!text) return render();
    say(`YOU: "${text}"`, "you");
    const delivery = charismaCheck();
    history(`The party said: "${text}"`);
    for (const e of here) {
      c.spoken.add(e.species);
      vowEvent("talk", e.species, `The party talked to ${e.name}, ${aLabel(e.species)}.`);
    }
    return afterPartyAction({ type: "talk", message: text, delivery }, ["The party spoke."], { [leader().id]: "spoke on behalf of the party" });
  }

  if (cmd === "r") return recruitAsk();

  if (cmd === "g") {
    if (G.gold <= 0) {
      say("YOU HAVE NO GOLD.", "dim");
      return render();
    }
    const text = await askText(`GIVE ${UP(target.name)} HOW MUCH GOLD? (HAVE ${G.gold})`, true);
    const gold = Math.min(G.gold, Math.max(0, Math.floor(Number(text) || 0)));
    if (!gold) return render();
    say(`YOU OFFER ${UP(target.name)} ${gold} GOLD.`, "you");
    sfx.play("gold");
    history(`The party offered ${target.name} ${gold} gold.`);
    return afterPartyAction({ type: "give", gold, targetId: target.id }, [`The party offered ${target.name} ${gold} gold.`], { [leader().id]: `held out ${gold} gold to ${target.name}` });
  }

  if (cmd === "v") return makeVow();

  if (cmd === "e") {
    const dex = Math.max(...conscious().map((m) => m.abil?.dex ?? 1));
    const dc = 10 + (here.some((e) => e.boss) ? 5 : 0) + (here.some((e) => e.species === "dragon") ? 3 : 0) + Math.floor(G.floor / 3);
    const r = d20();
    const ok = r.roll + dex >= dc;
    rollFx(r, { x: 224, y: 150 }, { total: r.roll + dex });
    say(`ESCAPE: ${fmtRoll(r, dex)}, NEEDED ${dc}. ${ok ? "YOU FLEE!" : "YOU CAN'T GET AWAY!"}`, ok ? "" : "warn");
    if (ok) {
      sfx.play("flee");
      for (const e of here) {
        history(`The party ran away from ${e.name}.`);
        vowEvent("flee", e.species, `The party ran away from ${e.name}, ${aLabel(e.species)}.`);
      }
      await flushBreaks();
      return endCombat();
    }
    sfx.play("miss");
    return afterPartyAction({ type: "run_failed" }, ["The party tried to run away, but failed."], {});
  }
  tips.ignored(cmd); // not a fight command: nudge the hint rather than swallow the key silently
}

async function afterPartyAction(playerAction, events, did) {
  render();
  await flushBreaks();
  if (!G.combat) return;
  if (!present().length) return endCombat();
  await monstersTurn(playerAction, events, did);
}

// Start of the party's turn: anyone at 0 HP makes a death saving throw.
async function beginPartyTurn() {
  if (!G.combat) return;
  for (const m of G.party) {
    if (!m.down || m.dead || m.stable) continue;
    const dr = d20();
    const r = dr.roll;
    rollFx(dr, spotOf(m));
    if (r === 20) {
      m.down = false;
      m.hp = 1;
      say(`${m.name}'S DEATH SAVE: A PERFECT 20! BACK UP WITH 1 HEALTH!`, "big");
      sfx.play("revive");
    } else if (r >= 10) {
      m.saves.s++;
      say(`${m.name}'S DEATH SAVE: ROLLED ${r}, NEEDED 10. SUCCESS, ${m.saves.s} OF 3.`, "dim");
      sfx.play("save");
      if (m.saves.s >= 3) {
        m.stable = true;
        say(`${m.name} IS STABLE, BUT STILL OUT COLD.`, "dim");
      }
    } else deathFail(m, r === 1 ? 2 : 1, `'S DEATH SAVE: ROLLED ${r}, NEEDED 10${r === 1 ? " (A 1 COUNTS TWICE)" : ""}. FAILURE`);
  }
  if (!humansAlive() || !conscious().length) return gameOver();
  G.busy = false;
  render();
}

function deathFail(m, n, why) {
  m.saves.f += n;
  say(`${m.name}${why} (${Math.min(3, m.saves.f)} OF 3 FAILURES).`, "warn");
  if (m.saves.f >= 3) die(m);
}

function die(m) {
  m.dead = true;
  m.down = false;
  say(`${m.name} DIES.`, "big warn");
  sfx.play("death");
  if (G.combat) history(`${m.name} died.`);
  if (m.kind === "monster") G.party = G.party.filter((x) => x !== m);
}

// A party member takes damage. At 0 HP they fall unconscious and start making death saves;
// hits while down count as failed saves (a critical hit counts as two).
function damage(m, dmg, { crit = false } = {}) {
  if (m.dead) return;
  if (m.down) {
    deathFail(m, crit ? 2 : 1, " IS HIT WHILE DOWN");
    return;
  }
  m.hp = Math.max(0, m.hp - dmg);
  floatParty(m, `-${dmg}`, "#ff5a4a");
  shakeUntil = fxNow() + 220;
  sfx.play("hurt");
  if (m.hp > 0) return;
  if (m.phoenix) {
    m.phoenix = false;
    m.hp = Math.ceil(m.maxHp / 2);
    say(`${m.name} FALLS... AND RISES AGAIN IN A BURST OF PHOENIX FIRE!`, "big", "#ffb347");
    sfx.play("revive");
    return;
  }
  m.down = true;
  m.stable = false;
  m.saves = { s: 0, f: 0 };
  m.cond = {};
  say(`${m.name} FALLS UNCONSCIOUS! HEAL THEM, OR THEY ROLL TO SURVIVE EACH TURN (DEATH SAVES).`, "big warn");
  hint("down");
  sfx.play("down");
  if (G.combat) history(`${m.name} was knocked unconscious.`);
}

// ---- the monsters' turn

// One Jev request for the whole group, then apply each monster's feeling and move in order.
async function monstersTurn(playerAction, events, did) {
  const c = G.combat;
  G.busy = true;
  c.round++;
  if (c.opening) {
    events = [c.opening, ...events];
    c.opening = null;
  }
  render();
  // Sleeping and paralyzed monsters can't act, or listen
  const here = present();
  for (const e of here) {
    if (e.cond.asleep) say(`${UP(e.name)} SNORES.`, "dim", colorOf(e));
    else if (e.cond.held) {
      const sv = monsterSave(e, "wis");
      if (sv >= (e.holdDC ?? 13)) {
        delete e.cond.held;
        e.justFreed = true;
        say(`${UP(e.name)} BREAKS THE HOLD (WISDOM ROLL ${sv})! IT CAN ACT NEXT ROUND.`, "warn", colorOf(e));
      } else say(`${UP(e.name)} STRAINS AGAINST THE MAGIC (WISDOM ROLL ${sv}), STILL PARALYZED.`, "dim", colorOf(e));
    }
  }
  const acting = here.filter((e) => !e.cond.asleep && !e.cond.held && !e.justFreed);
  if (!acting.length) {
    endMonsterRound();
    return beginPartyTurn();
  }
  let out;
  try {
    out = await api("/api/group-turn", {
      monsters: acting.map((e) => ({
        id: e.id,
        species: e.species,
        name: e.name,
        traits: e.traits,
        boss: !!e.boss,
        hp: Math.max(0, e.hp),
        maxHp: e.maxHp,
        meters: e.meters,
        specialReady: e.cooldown <= 0,
        paid: e.paid,
        demanded: e.demanded,
        impressions: e.impressions,
        formerAlly: e.formerAlly,
        grudges: e.grudges,
        thisRound: e.thisRound,
        damageTaken: e.damageTaken,
      })),
      party: G.party.map((m) => ({ id: m.id, name: m.name, kind: m.kind, species: m.species, cls: m.cls, hp: Math.max(0, m.hp), maxHp: m.maxHp, dead: m.dead || m.down, didThisRound: did[m.id] })),
      round: c.round,
      playerAction,
      events,
      conversation: c.conversation,
      partyGold: G.gold,
      vows: G.vows.map((v) => ({ text: v.text.toLowerCase(), toId: v.toId, status: v.status })),
    });
  } catch (err) {
    say(`(JEV UNREACHABLE: ${err.message}. THE MONSTERS HESITATE.)`, "dim");
    endMonsterRound();
    return beginPartyTurn();
  }
  for (const e of acting) {
    e.thisRound = [];
    e.damageTaken = 0;
  }
  if (playerAction.message) c.conversation.push({ speaker: "Party", text: playerAction.message });
  showJev({ kind: "group", out, here: acting });

  const joins = [];
  c.lastLines ??= {};
  for (const r of out.results) {
    const e = c.enemies.find((x) => x.id === r.id);
    if (!e || e.status !== "here" || e.hp <= 0) continue;
    const before = e.side;
    e.meters = r.meters;
    e.impressions = r.impressions;
    e.side = r.side;
    if (r.side === "friendly with the party") hint("recruit");
    // Its reply as the player meets it: how it reacts, what it says, and why it said yes or no to joining
    // A monster's side starts as a placeholder, so only a change after its first reply is news
    const told = groupLog(r, { name: e.name, species: e.species, sideBefore: e.replied ? before : null, debug: DEBUG });
    e.replied = true;
    const answer = told.find((l) => l.kind === "join")?.text;
    c.lastLines[e.id] = r.line;
    c.conversation.push({ speaker: e.name, text: r.spoken === false ? answer ?? r.line : r.line });
    for (const l of told) say(l.text, l.cls, l.kind === "debug" ? undefined : colorOf(e));
    if (r.spoken !== false) speak(e, r.line);
    if (r.emotion) showEmotion(e, r.emotion);
    if (e.cooldown > 0) e.cooldown--;
    // Someone switching sides is news to the rest of the group
    if (before !== r.side && r.side === "friendly with the party")
      for (const o of present())
        if (o !== e) {
          o.thisRound.push(`${e.name} just sided with the party against you.`);
          o.impressions.push(`${e.name} turned traitor and sided with the party.`);
        }
    await applyMonsterAction(e, r, joins);
    render();
    await sleep(340);
    if (!humansAlive() || !conscious().length) break;
  }
  if (!humansAlive() || !conscious().length) return gameOver();
  endMonsterRound();
  G.busy = false;
  render();
  await flushBreaks();
  if (!G.combat) return;
  for (const e of joins) {
    if (e.status !== "here") continue;
    if (G.party.length >= 6) {
      say(`${UP(e.name)} WANTS TO JOIN, BUT YOUR PARTY IS FULL.`, "dim");
      continue;
    }
    const yes = await ask(`${UP(e.name)} WANTS TO JOIN. ACCEPT?`, { yes: "WELCOME IT", no: "TURN IT AWAY" });
    if (yes) recruit(e);
    else {
      e.status = "left";
      say(`YOU TURN ${UP(e.name)} AWAY. IT WANDERS OFF.`);
      history(`${e.name} offered to join, but the party turned it away.`);
      vowEvent("spare", e.species, `The party let ${e.name}, ${aLabel(e.species)}, walk away alive.`);
    }
    await flushBreaks();
    if (!G.combat) return;
  }
  if (!present().length) return endCombat();
  await beginPartyTurn();
}

// Each round of conditions on monsters ticks down after they act (a held monster stays held until it saves).
function endMonsterRound() {
  for (const e of G.combat?.enemies ?? []) {
    delete e.justFreed;
    for (const k of Object.keys(e.cond)) if (k !== "held" && --e.cond[k] <= 0) delete e.cond[k];
  }
}

// What a feeling does once it's been told in the log (groupLog): float, sound, condition, dropped gold.
// Every feeling has teeth.
function showEmotion(e, em) {
  const color = colorOf(e);
  floatOn(e, `${em.label}!`, color, 10);
  hint("feeling");
  sfx.play({ good: "good", bad: "bad", fear: "fear", sad: "sad", odd: "odd" }[em.tone] ?? "good");
  if (em.cond) e.cond[em.cond] = Math.max(e.cond[em.cond] ?? 0, em.rounds);
  if (em.id === "terrified") {
    const gold = Math.max(1, Math.round(rnd(...SPECIES[e.species].gold) * 0.5 * (1 + 0.3 * (G.floor - 1))));
    G.gold += gold;
    say(`${UP(e.name)} DROPS ${gold} GOLD IN ITS PANIC!`, "", color);
    sfx.play("gold");
  }
}

// A blow aimed at the party, soaked by a BOUNCY or BULWARK ally if one is guarding.
function soak(victim, head = "") {
  const c = G.combat;
  if (!c.bouncy || c.bouncy.dead || c.bouncy.down || !(c.soaks > 0)) return false;
  say(`${head} ${c.bouncy.name} ${c.bouncy.species === "rock" ? "TAKES THE BLOW ON ITS STONE HIDE" : "BOUNCES THE BLOW AWAY"} FOR ${victim.name}!`.trim(), "", colorOf(c.bouncy));
  sfx.play("save");
  if (--c.soaks <= 0) c.bouncy = null;
  return true;
}

function monsterAttack(e, t) {
  const adv = e.cond.enraged || t.cond?.restrained || t.cond?.prone ? 1 : 0;
  const dis = e.cond.demoralized || e.cond.frightened ? 1 : 0;
  const r = d20(adv - dis);
  rollFx(r, spotOf(t), { total: r.roll + e.hit });
  const crit = r.roll === 20;
  const hit = r.roll !== 1 && (crit || r.roll + e.hit >= t.ac);
  const head = `${UP(e.name)} ATTACKS ${t.name}: ${fmtRoll(r, e.hit)} VS ARMOR ${t.ac}.`;
  if (!hit) {
    say(`${head} ${r.roll === 1 ? "FUMBLE!" : "MISS."}`, "dim");
    floatParty(t, "MISS", "#8a8a8a");
    sfx.play("miss");
    return;
  }
  const dmg = Math.max(1, Math.round(rollDice(MONSTER_STATS[e.species].dmg, { crit }) * e.dmgMult)) + (e.cond.spiteful ? 2 : 0) + (e.cond.enraged ? 3 : 0);
  if (soak(t, head)) return;
  say(`${head} ${crit ? "CRITICAL HIT! " : "HIT! "}${t.name} TAKES ${dmg}.`, "warn");
  damage(t, dmg, { crit });
}

async function applyMonsterAction(e, r, joins) {
  const c = G.combat;
  const sp = SPECIES[e.species];
  const pickTarget = (preferred) => {
    const up = conscious();
    return up.find((m) => m.id === preferred) ?? pick(up);
  };
  switch (r.action) {
    case "attack":
      for (let i = 0; i < e.multiattack; i++) {
        const t = pickTarget(i === 0 ? r.targetId : null);
        if (!t) break;
        monsterAttack(e, t);
        if (i < e.multiattack - 1) {
          render();
          await sleep(260);
        }
      }
      break;
    case "special": {
      e.cooldown = e.recharge;
      const st = MONSTER_STATS[e.species].special;
      const victims = sp.special.all ? conscious() : [pickTarget(r.targetId)].filter(Boolean);
      const withCond = st.cond && floorRules(G.floor).conditions;
      say(`${UP(e.name)}'S SPECIAL! ROLL ${e.dc}+ ON ${ABILITY_WORDS[st.save]} TO TAKE HALF${withCond ? ` AND NOT BE ${CONDITIONS[st.cond].word}` : ""}.`, "warn", colorOf(e));
      sfx.play(e.species === "dragon" ? "fireball" : "crit");
      for (const v of victims) {
        if (soak(v)) continue;
        const sv = partySave(v, st.save);
        const saved = sv >= e.dc;
        let dmg = Math.max(1, Math.round(rollDice(st.dice) * e.dmgMult));
        if (saved) dmg = Math.floor(dmg / 2);
        say(`${v.name} ${saved ? "MAKES IT" : "FAILS"} (ROLLED ${sv}): ${dmg} DAMAGE${!saved && withCond ? ` AND IS ${CONDITIONS[st.cond].word}` : ""}.`, saved ? "" : "warn");
        if (!saved && withCond) v.cond[st.cond] = st.rounds;
        if (dmg) damage(v, dmg);
      }
      break;
    }
    case "attack_monster": {
      const other = c.enemies.find((x) => x.id === r.monsterTargetId && x.status === "here" && x.hp > 0);
      if (!other) break;
      const roll = d20();
      rollFx(roll, spotOf(other), { total: roll.roll + e.hit });
      const hit = roll.roll !== 1 && (roll.roll === 20 || roll.roll + e.hit >= other.ac);
      if (!other.grudges.includes(e.id)) other.grudges.push(e.id);
      history(`${e.name} attacked ${other.name}.`);
      if (!hit) {
        say(`${UP(e.name)} TURNS ON ${UP(other.name)}: ${fmtRoll(roll, e.hit)} VS ARMOR ${other.ac}. MISS!`, "big", colorOf(e));
        sfx.play("miss");
        other.thisRound.push(`${e.name} attacked you, but missed.`);
        break;
      }
      const dmg = Math.max(1, Math.round(rollDice(MONSTER_STATS[e.species].dmg, { crit: roll.roll === 20 }) * e.dmgMult));
      hitEnemy(other, dmg, `${e.name} attacked you for ${dmg}.`, colorOf(e));
      say(`${UP(e.name)} TURNS ON ${UP(other.name)}: ${fmtRoll(roll, e.hit)} VS ARMOR ${other.ac}. ${dmg} DAMAGE!`, "big", colorOf(e));
      sfx.play("hit");
      if (other.hp <= 0) killEnemy(other, null, e);
      break;
    }
    case "defend":
      e.cond.dodging = 2;
      floatOn(e, "DODGING", colorOf(e), 8);
      break;
    case "demand_tribute":
      e.demanded = true;
      break;
    case "accept_tribute":
      G.gold -= r.offer;
      e.paid = true;
      say(`${UP(e.name)} TAKES ${r.offer} GOLD.`);
      sfx.play("gold");
      history(`The party paid ${e.name} ${r.offer} gold, and it accepted.`);
      vowEvent("give", e.species, `The party gave ${r.offer} gold to ${e.name}, ${aLabel(e.species)}.`);
      break;
    case "refuse_tribute":
      history(`${e.name} refused the party's gold.`);
      break;
    case "flee":
      e.status = "fled";
      say(`${UP(e.name)} FLEES.`);
      sfx.play("flee");
      history(`${e.name} fled from the fight.`);
      for (const o of present()) o.thisRound.push(`${e.name} fled.`);
      break;
    case "leave_peacefully": {
      e.status = "left";
      const xp = Math.round(xpOf(e) / 2);
      say(`${UP(e.name)} LETS YOU PASS. +${xp} EXPERIENCE FOR A PEACEFUL END.`, "", colorOf(e));
      sfx.play("good");
      grantXp(xp);
      history(`${e.name} and the party parted peacefully.`);
      vowEvent("spare", e.species, `The party let ${e.name}, ${aLabel(e.species)}, walk away alive.`);
      break;
    }
    case "join_party":
      joins.push(e);
      break;
  }
}

function recruit(e) {
  const sp = SPECIES[e.species];
  e.status = "joined";
  const ally = {
    id: `m${uid++}`,
    name: UP(e.name),
    kind: "monster",
    species: e.species,
    cls: sp.cls,
    hp: Math.max(1, e.hp),
    maxHp: e.maxHp,
    ac: e.ac,
    dmg: [...e.dmg],
    traits: e.traits,
    shiny: e.shiny,
    boss: e.boss,
    level: Math.max(1, G.floor),
    xp: 0,
    mods: baseMods(),
    cond: {},
    cooldown: 1,
    loyalty: Math.min(80, 50 + Math.round((e.meters.friendliness - sp.joinThreshold) / 2)),
    dead: false,
    down: false,
  };
  G.party.push(ally);
  // Promises made to it mid-fight now belong to the ally
  for (const v of G.vows) if (v.toId === e.id) Object.assign(v, { toId: ally.id, toName: ally.name });
  vowSig = "";
  const xp = Math.round(xpOf(e) / 2);
  say(`${ally.name} JOINS THE PARTY! +${xp} EXPERIENCE FOR WINNING IT OVER.`, "big", colorOf(ally));
  sfx.play("join");
  hint("ally");
  if (e.shiny) {
    G.combat.shinyRolls = (G.combat.shinyRolls ?? 0) + 1;
    say("A SHINY JOINED YOU! FATE OWES YOU A ROLL AFTER THIS FIGHT.", "big", SHINY_COLOR);
  }
  grantXp(xp);
  history(`The party befriended ${e.name}, who joined them.`);
  G.combat.recruits.push(ally.id);
  vowEvent("recruit", e.species, `The party recruited ${e.name}, ${aLabel(e.species)}, into the party.`);
  vowEvent("spare", e.species, `The party let ${e.name}, ${aLabel(e.species)}, live and join them.`);
}

async function endCombat() {
  const c = G.combat;
  if (!c) return;
  G.combat = null;
  G.mode = "explore";
  // Every foe killed, driven off, won over or let go: that's a win, and it sounds like one
  if (c.enemies.length && c.enemies.every((e) => e.status !== "here")) music.sting("victory");
  music.setMood("explore");
  G.busy = false; // the party's turn may have ended the fight mid-action
  // The fallen who still live come to; conditions and talk moods fade
  for (const m of G.party) {
    if (m.down && !m.dead) {
      m.down = false;
      m.stable = false;
      m.hp = Math.max(1, m.hp);
      say(`${m.name} COMES TO WITH ${m.hp} HEALTH.`, "dim");
    }
    m.cond = {};
    m.mood = null;
  }
  // The floor's champion: beaten, won over, or talked down earns a great roll. If it fled, it waits.
  let great = false;
  if (c.boss && G.map.boss) {
    const e = G.map.boss.enemy;
    if (e && ["dead", "joined", "left"].includes(e.status)) {
      G.map.boss.defeated = true;
      great = true;
    } else if (e) say(`${UP(e.name)} STILL HOLDS THE HEART OF THIS FLOOR.`, "dim", BOSS_COLOR);
  }
  if (living().some((m) => m.hp < m.maxHp / 2)) hint("camp");
  render();
  await flushBreaks();
  const traitor = await allyReactionsAfter(c);
  if (great) {
    say("THE CHAMPION IS OVERCOME. FATE OWES YOU A GREAT ROLL.", "big", BOSS_COLOR);
    render();
    await sleep(600);
    await rollOfFate(G.floor, true);
  }
  for (let i = 0; i < (c.shinyRolls ?? 0); i++) {
    render();
    await sleep(500);
    await rollOfFate(G.floor, false, "shiny");
  }
  render();
  if (traitor) setTimeout(() => encounter([enemyFromAlly(traitor, "You traveled with this party and grew to despise how they act. You just turned on them.")]), 700);
}

// After a fight, your monster allies judge what they saw. Returns an ally that turned on you, if any.
async function allyReactionsAfter(c) {
  const watchers = allies().filter((m) => !c.recruits.includes(m.id));
  if (!watchers.length || c.history.length < 2) return null;
  G.busy = true;
  render();
  let r;
  try {
    r = await api("/api/ally-reactions", {
      allies: watchers.map((a) => ({ id: a.id, species: a.species, name: a.name, traits: a.traits, loyalty: a.loyalty })),
      events: c.history,
    });
  } catch (err) {
    say(`(JEV UNREACHABLE: ${err.message})`, "dim");
    G.busy = false;
    return null;
  }
  G.busy = false;
  showJev({ kind: "allies", r, events: c.history });
  let traitor = null;
  for (const x of r.reactions) {
    const m = G.party.find((p) => p.id === x.id);
    if (!m) continue;
    m.loyalty = x.loyalty;
    const color = colorOf(m);
    say(`${m.name}: ${x.line}`, "npc", color);
    speak(m, x.line);
    // What it made of the fight, and the moment that tipped it, so a walk-out never comes out of nowhere
    const felt = allyLine(m.species, m.name, x);
    if (felt) say(felt, "", color);
    dbg(`${m.name} APPROVAL ${x.approval.toFixed(1)}/4, LOYALTY ${x.delta >= 0 ? "+" : ""}${x.delta} → ${x.loyalty}${x.blocked ? `; ${x.blocked}` : ""}`);
    if (x.decision === "leave_party") {
      G.party = G.party.filter((p) => p !== m);
      say(`${m.name} LEAVES THE PARTY.`, "warn", color);
      sfx.play("sad");
    } else if (x.decision === "turn_on_party" && !traitor) {
      G.party = G.party.filter((p) => p !== m);
      traitor = m;
    }
  }
  return traitor;
}

function gameOver() {
  G.mode = "over";
  G.combat = null;
  music.setMood("explore");
  G.busy = false;
  sfx.play("death");
  say(`YOUR PARTY HAS PERISHED ON ${floorName(G.floor)}.`, "big");
  say(`DEEPEST FLOOR EVER REACHED: ${store.get("hallsOfJev.deepest") || G.floor}. PRESS ENTER FOR A NEW RUN.`, "dim");
  render();
}

// ---------------------------------------------------------------- Jev mind panel (debug only)
// The raw decision behind every monster: meters, perception, odds, blocked picks. A developer tool; players read
// monsters through the log instead (narrate.js). Only exists in DEBUG mode.

function bar(v, max = 1) {
  return `<span class="meter"><span style="width:${Math.max(0, Math.min(1, v / max)) * 100}%"></span></span>`;
}
const words = (s) => esc(UP(String(s).replaceAll("_", " ")));

function showJev(x) {
  if (!DEBUG) return;
  const el = $("#jevBody");
  let h = "";
  if (x.kind === "group") {
    const { out, here } = x;
    h += `<p class="meta">${out.questionCount} QUESTIONS · ${out.ms} MS · ${out.inputTokens} TOKENS · ACTIONS ROLLED ON JEV'S ODDS</p>`;
    for (const r of out.results) {
      const e = here.find((m) => m.id === r.id);
      if (!e) continue;
      h += `<h3 style="color:${colorOf(e)}">${esc(UP(e.name))} · ${words(r.side)}</h3><div class="rows">`;
      for (const k of ["friendliness", "anger", "fear"]) h += `<span>${UP(k)}</span>${bar(r.meters[k], 100)}<span>${r.meters[k]}</span>`;
      for (const p of r.perception.filter((p) => p.value >= 0.5 || p.type === "score")) h += `<span>HEARD: ${esc(UP(p.label))}</span>${bar(p.value, p.max ?? 1)}<span>${p.value.toFixed(2)}</span>`;
      for (const p of r.probabilities.slice(0, 4)) h += `<span class="${p.id === r.picked ? "hot" : ""}">${words(p.id)}</span>${bar(p.p)}<span>${Math.round(p.p * 100)}%</span>`;
      for (const p of r.emotionProbabilities ?? []) h += `<span class="${p.id === r.emotion?.id ? "hot" : ""}">FEELS ${words(p.id)}</span>${bar(p.p)}<span>${Math.round(p.p * 100)}%</span>`;
      h += `</div>`;
      if (r.emotion) h += `<p class="meta">FEELING: ${esc(r.emotion.label)} → ${esc(r.emotion.effect)}</p>`;
      if (r.join) h += `<p class="meta">JOIN: ${r.join.accepted ? (r.join.moved ? "ASKS TO COME" : "YES") : "NO"} · REASON ${words(r.join.reason)}</p>`;
      if (r.blocked) h += `<p class="blocked">CODE BLOCKED ${words(r.picked)}: ${esc(r.blocked)} → ${words(r.action)}</p>`;
    }
  } else if (x.kind === "allies") {
    const { r, events } = x;
    h += `<p class="meta">ALLY CHECK · ${r.questionCount} QUESTIONS · ${r.ms} MS</p><h3>WHAT THEY SAW</h3><ul>${events.map((e) => `<li>${esc(e)}</li>`).join("")}</ul>`;
    for (const a of r.reactions) {
      h += `<h3>${esc(a.name)}</h3><div class="rows"><span>APPROVAL 0–4</span>${bar(a.approval, 4)}<span>${a.approval.toFixed(1)}</span><span>LOYALTY ${a.delta >= 0 ? "+" : ""}${a.delta}</span>${bar(a.loyalty, 100)}<span>${a.loyalty}</span></div>`;
      h += `<p class="meta">DECISION: ${words(a.decision)}${a.picked !== "stay" && a.picked !== a.decision ? ` (JEV SAID ${words(a.picked)})` : ""}</p>`;
      if (a.moment) h += `<p class="meta">MOST STRUCK BY: ${esc(a.moment)}</p>`;
      if (a.blocked) h += `<p class="blocked">${esc(a.blocked)}</p>`;
    }
  } else if (x.kind === "talk") {
    const { ally, r } = x;
    h += `<p class="meta">ALLY TALK · ${r.ms} MS</p><h3 style="color:${colorOf(ally)}">${esc(ally.name)}</h3><div class="rows"><span>HOW IT LANDED 0–4</span>${bar(r.resonance, 4)}<span>${r.resonance.toFixed(1)}</span><span>LOYALTY ${r.loyaltyDelta >= 0 ? "+" : ""}${r.loyaltyDelta}</span>${bar(ally.loyalty, 100)}<span>${ally.loyalty}</span></div><p class="meta">RESULT: ${esc([r.outcome?.id, r.buff?.id].filter(Boolean).join(" + ") || "NONE")} (0 SULK · 1 DISTRACTED · 2 STEADY · 3 BUFF · 4 INSPIRED + BUFF)</p>`;
  } else if (x.kind === "vow") {
    const { to, vow, r } = x;
    h += `<p class="meta">VOW · ${r.ms} MS</p><h3 style="color:${colorOf(to)}">${esc(UP(to.name))} HEARS "${esc(vow.text)}"</h3><div class="rows"><span>HOW IT FEELS 0–4</span>${bar(r.liking, 4)}<span>${r.liking.toFixed(1)}</span></div>`;
  } else if (x.kind === "broken") {
    const { ally, v, r } = x;
    h += `<p class="meta">BROKEN VOW · ${r.ms} MS</p><h3 style="color:${colorOf(ally)}">${esc(ally.name)} · "${esc(v.text)}"</h3><div class="rows">`;
    for (const [id, p] of Object.entries(r.probabilities).sort((a, b) => b[1] - a[1])) h += `<span class="${id === r.picked ? "hot" : ""}">${words(id)}</span>${bar(p)}<span>${Math.round(p * 100)}%</span>`;
    h += `</div>`;
    if (r.blocked) h += `<p class="blocked">${esc(r.blocked)}</p>`;
    if (r.response === "steal_gold") h += `<p class="meta">STEAL ROLL (60%): ${r.stolen ? `SUCCESS, ${r.stolen} GOLD` : "CAUGHT"}</p>`;
  }
  el.innerHTML = h;
}

// ---------------------------------------------------------------- input

$("#inputForm").addEventListener("submit", (ev) => {
  ev.preventDefault();
  closeInput($("#text").value.trim().slice(0, 240) || null);
});

function key(k) {
  if (!G) return;
  if (G.waitKey) {
    const r = G.waitKey;
    G.waitKey = null;
    r();
    return;
  }
  if (G.mode === "over") {
    if (k === "enter") newRun();
    else nudgeDock();
    return;
  }
  if (G.prompt) {
    const p = G.prompt;
    const answer = k === "y" || k === "enter" ? true : k === "n" || k === "escape" ? false : null;
    if (answer !== null) {
      G.prompt = null;
      p.resolve(answer);
      return;
    }
    if (p.walkAway && ["fwd", "back", "turnL", "turnR"].includes(k)) {
      G.prompt = null;
      p.resolve(false);
      return key(k);
    }
    nudgeModal();
    return;
  }
  if (G.menu) {
    // Up/down (or W/S) move the highlight, left/right jump columns, Enter picks it; 1-9 and 0 pick directly
    const m = G.menu;
    const n = m.options.length;
    const rows = n > 4 ? Math.ceil(n / 2) : n;
    const move = { fwd: -1, back: 1, turnL: -rows, turnR: rows }[k];
    if (move) {
      const next = Math.abs(move) === 1 ? menuStep(m.sel, move, n) : m.sel + move;
      if (next >= 0 && next < n && next !== m.sel) {
        m.sel = next;
        renderDock();
      } else if (Math.abs(move) !== 1) nudgeDock();
      return;
    }
    if (k === "escape") {
      G.menu = null;
      m.resolve(null);
      return;
    }
    const i = k.startsWith("pick:") ? Number(k.slice(5)) : k === "enter" ? m.sel : k === "0" ? 9 : /^[1-9]$/.test(k) ? Number(k) - 1 : -1;
    if (m.options[i]) {
      G.menu = null;
      m.resolve(m.options[i].value);
    } else nudgeDock();
    return;
  }
  if (G.input) {
    // The talk box lost focus: the dock's buttons still work, and any other key points back at the box
    if (k === "escape") {
      closeInput(undefined);
      return render();
    }
    if (k === "enter") return $("#inputForm").requestSubmit();
    $("#text").focus();
    nudgeDock();
    return;
  }
  if (G.busy) return tips.ignored(k); // the monsters are still moving: nudge the hint, don't drop it
  if (k === "j" && DEBUG) {
    toggleJev();
    return renderBar();
  }
  if (k === "h") return tips.toggle(say), render();
  if (k === "p") return Promise.resolve(music.toggle()).then(() => renderBar());
  if (k === "o") {
    say(`SOUND EFFECTS ${sfx.toggle() ? "ON" : "OFF"}.`, "dim");
    return render();
  }
  if (G.combat) return command(k);
  if (k === "m") {
    $("#map").classList.toggle("hidden");
    return;
  }
  if (k === "c") return camp();
  if (k === "e") return talkToAlly();
  if (k === "v") return makeVow();
  if (k === "b") return listBoons();
  if (k === "fwd") return step(G.dir);
  if (k === "back") return step((G.dir + 2) % 4);
  if (k === "turnL") G.dir = (G.dir + 3) % 4;
  if (k === "turnR") G.dir = (G.dir + 1) % 4;
  else if (k !== "turnL") tips.ignored(k); // not an exploring key: nudge the hint rather than swallow it silently
  render();
}

function toggleJev() {
  const hidden = $("#jev").classList.toggle("hidden");
  store.set("hallsOfJev.jev", hidden ? "0" : "1");
}
// Hidden in the page by default; in debug mode it opens unless the developer closed it last time
if (DEBUG && store.get("hallsOfJev.jev") !== "0") $("#jev").classList.remove("hidden");

const KEYMAP = {
  arrowup: "fwd",
  w: "fwd",
  arrowdown: "back",
  s: "back",
  arrowleft: "turnL",
  a: "turnL",
  arrowright: "turnR",
  d: "turnR",
};

let started = false;
function start() {
  if (started) return;
  started = true;
  sfx.init();
  music.start().catch((err) => console.warn("music:", err));
  newRun();
  // Test runs: open the game with #floor5 (any number) to start that deep, with a party that got there
  const test = /floor(\d+)/.exec(location.hash);
  if (test) testRun(Math.max(2, Math.min(30, Number(test[1]))));
}

// A party as if it had played down to floor n: level n, one boon per floor cleared, some gold, fully rested.
function testRun(n) {
  const sound = sfx.on;
  sfx.on = false;
  for (const m of G.party)
    while (m.level < n) {
      m.xp = xpFor(m.level);
      levelUp(m);
    }
  for (let f = 1; f < n; f++) drawBoon(f);
  for (const m of G.party) {
    m.hp = m.maxHp;
    m.xp = 0;
    if (m.maxSlots) m.slots = [...m.maxSlots];
  }
  G.gold = 30 + 45 * (n - 1);
  enterFloor(n);
  G.log = [];
  sfx.on = sound;
  say(`TEST RUN: STARTING ON ${floorName(n)} WITH A LEVEL ${n} PARTY, ${n - 1} BOONS AND ${G.gold} GOLD.`, "big", G.map.palette.accent);
  for (const b of G.boons) say(`${floorName(b.floor)}: ${b.name}: ${b.text}`, "dim");
  announceFloor(n);
  render();
}

document.addEventListener("keydown", (ev) => {
  if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
  if (ev.target === $("#text")) {
    if (ev.key === "Escape") {
      closeInput(undefined); // undefined = cancelled; an empty submit is null
      render();
    }
    return;
  }
  if (!started) {
    ev.preventDefault();
    return start();
  }
  const k = ev.key.toLowerCase();
  const mapped = KEYMAP[k] ?? k;
  // Stop the key from also typing into the talk box that some commands open
  if (KEYMAP[k] || k.length === 1 || k === "enter" || k === "escape") ev.preventDefault();
  key(mapped);
});

$("#dock").addEventListener("click", (ev) => {
  const b = ev.target.closest("button[data-key]");
  if (!b) return;
  b.blur(); // so Space/Enter later don't re-press a button that kept focus
  key(b.dataset.key);
});
$("#where").addEventListener("click", (ev) => {
  const b = ev.target.closest("button[data-key]");
  if (!b || !G) return;
  b.blur();
  key(b.dataset.key);
});
// Hovering a command shows what it does; hovering a menu option highlights it
$("#dock").addEventListener("mouseover", (ev) => {
  const b = ev.target.closest("button[data-key]");
  if (!b) return;
  if (b.dataset.i !== undefined && G?.menu) {
    G.menu.sel = Number(b.dataset.i);
    for (const o of $("#cmds").querySelectorAll(".opt")) o.classList.toggle("sel", o === b);
    dockHint = b.dataset.hint ?? "";
  }
  $("#hint").textContent = b.dataset.hint || dockHint;
});
$("#dock").addEventListener("mouseout", (ev) => {
  if (ev.target.closest("button[data-key]") && !ev.relatedTarget?.closest?.("button[data-key]")) $("#hint").textContent = dockHint;
});
$("#modal").addEventListener("click", (ev) => {
  const k = ev.target.closest("button")?.dataset.key;
  if (k) key(k);
});
$("#view").addEventListener("click", () => start());

// Title card, then a light animation loop (monsters wobble, the title blinks)
function frame() {
  if (!G) drawTitle(view, performance.now());
  else drawView(performance.now());
  requestAnimationFrame(frame);
}
document.fonts?.ready.then(() => requestAnimationFrame(frame)) ?? requestAnimationFrame(frame);

// Debug: fight this floor's champion (or a fresh one) right where you stand.
function bossEncounterHere() {
  G.map.boss ??= { x: -1, y: -1, species: pickWeighted(floorRules(G.floor).pool), defeated: false, enemy: null };
  return bossEncounter();
}

// Debug hook: open with #debug (or ?debug), then e.g. halls.meet("goblin", "slime") in the console.
if (DEBUG)
  window.halls = {
    hostile: (species) => {
      const e = makeEnemy(species);
      e.meters = { friendliness: 0, anger: 60, fear: 0 };
      return encounter([e]);
    },
    meet: (...species) => encounter(species.reduce((group, s) => [...group, makeEnemy(s, group.map((e) => e.name))], [])),
    state: () => G,
    ally: (species, name) => {
      const sp = SPECIES[species];
      G.party.push({ id: `m${uid++}`, name: UP(name ?? sp.names[0]), kind: "monster", species, cls: sp.cls, hp: sp.hp[1], maxHp: sp.hp[1], ac: MONSTER_STATS[species].ac, dmg: [...sp.dmg], traits: sp.traits.slice(0, 2), loyalty: 60, dead: false, down: false, level: 1, xp: 0, mods: baseMods(), cond: {}, cooldown: 1 });
      render();
    },
    boss: () => bossEncounterHere(),
    floor: (n) => {
      enterFloor(n);
      announceFloor(n);
      render();
    },
    xp: (n) => {
      grantXp(n);
      render();
    },
    music,
    sfx,
    tips, // e.g. halls.tips.reset(), halls.tips.hint("map")
    roll: (great = false, kind) => rollOfFate(G.floor, great, kind),
    shiny: (species = "slime") => {
      let e;
      do e = makeEnemy(species);
      while (!e.shiny);
      e.meters.friendliness = 90;
      return encounter([e]);
    },
    descend: () => descend(),
    ask: (text = `STAIRS DOWN TO ${floorName(G.floor + 1)}. DESCEND?`) => ask(text, { yes: "DESCEND", no: "STAY", walkAway: true }),
  };
