// Genre Halls (genre-halls.html): the rules of the Undertale-style encounter mode, with no DOM, so they can be tested.
// Each faction attacks in its own genre (chess, shadow, rhythm, goo rain) inside one box with one rule: lit squares hurt.
// Here: the factions and their tastes, the floor, the monster's mind (Jev-shaped questions with local answers), how
// typed words are read, and the box's geometry. genre-halls.js draws it all and runs the fight.

import { DIRS } from "./render.js";
import { SPECIES } from "./species.js";
import { EMOTIONS } from "./emotions.js";

export const rnd = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
export const pick = (a) => a[Math.floor(Math.random() * a.length)];
export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
export const sigmoid = (x) => 1 / (1 + Math.exp(-x));

// ---------------------------------------------------------------- factions

export const GENRES = {
  bullet: { name: "GOO RAIN", rule: "WATCH WHERE THE GOO WILL LAND" },
  chess: { name: "CHESS", rule: "ROOK: ROW + COLUMN · BISHOP: DIAGONALS · KNIGHT: L-JUMPS" },
  shadow: { name: "SHADOW", rule: "THE LANTERN FLARES. HIDE IN A PILLAR'S SHADOW" },
  rhythm: { name: "RHYTHM", rule: "IT STOMPS ON THE BEAT. MOVE BETWEEN BEATS" },
};

// ACT options per species. Each one is an intent the monster's mind judges, the same intents the chatbox reads.
export const ACTS = {
  slime: [
    { label: "TELL A JOKE", intent: "joke" },
    { label: "OFFER COMFORT", intent: "kindness" },
    { label: "CALL IT GROSS", intent: "insult" },
  ],
  bandit: [
    { label: "OFFER A FAIR CUT", intent: "gold" },
    { label: "SHOW A CLEVER TRICK", intent: "joke" },
    { label: "SNEER AT IT", intent: "insult" },
  ],
  snake: [
    { label: "PRAISE ITS SCALES", intent: "flattery" },
    { label: "PROPOSE A BARGAIN", intent: "gold" },
    { label: "HURRY IT ALONG", intent: "rush" },
  ],
  rock: [
    { label: "WAIT QUIETLY", intent: "peace" },
    { label: "ADMIRE THE OLD STONE", intent: "flattery" },
    { label: "BANG ON YOUR SHIELD", intent: "noise" },
  ],
  dragon: [
    { label: "FLATTER ITS HOARD", intent: "flattery" },
    { label: "STAND YOUR GROUND", intent: "courage" },
    { label: "OFFER ONE COPPER", intent: "cheap" },
  ],
};

// How much each species likes each kind of words or deeds (-2..2), from its likes and dislikes in species.js
export const AFF = {
  slime: { kindness: 2, joke: 2, flattery: 0.5, gold: 0.5, threat: -1.5, insult: -2, peace: 1.5, join: 1, question: 0.5, gibberish: 1, courage: 0, cheap: 0, noise: -1, rush: -0.5 },
  bandit: { kindness: 0, joke: 1.5, flattery: 1, gold: 2, threat: -1, insult: -2, peace: 0, join: 0.5, question: 0.5, gibberish: -1, courage: 0.5, cheap: -1.5, noise: -0.5, rush: 0 },
  snake: { kindness: 0.5, joke: 0, flattery: 2, gold: 1.5, threat: -1.5, insult: -2, peace: 1, join: 0.5, question: 1, gibberish: -1.5, courage: 0, cheap: -1, noise: -1.5, rush: -2 },
  rock: { kindness: 1, joke: -0.5, flattery: 1.5, gold: -1, threat: -1, insult: -1, peace: 2, join: 0.5, question: 1, gibberish: -1, courage: 0, cheap: -0.5, noise: -2, rush: -1.5 },
  dragon: { kindness: 0, joke: 1, flattery: 2, gold: 1, threat: 0, insult: -2, peace: 0, join: 0, question: 0.5, gibberish: -1.5, courage: 1, cheap: -2, noise: -1, rush: -1 },
};
// Traits shift those tastes, so two slimes don't want the same thing
const TRAIT_TASTE = {
  "easily startled": { threat: -1.5, noise: -1 }, ticklish: { joke: 1 }, lonely: { join: 1.5, kindness: 0.5 }, hungry: { gold: 1 },
  curious: { question: 1 }, sleepy: { peace: 1, joke: -1 }, shy: { flattery: -1, kindness: 0.5 },
  greedy: { gold: 1 }, charming: { flattery: 1 }, jumpy: { threat: -1.5, noise: -1 }, "owes money to someone": { gold: 1.5 },
  "quick-fingered": { joke: 0.5 }, "surprisingly honest about being dishonest": { insult: 0.5, flattery: -0.5 },
  patient: { peace: 1, rush: -0.5 }, secretive: { question: -1.5 }, "vain about its scales": { flattery: 1 },
  "always bargaining": { gold: 1 }, "holds grudges": { insult: -1, threat: -0.5 }, "curious about humans": { question: 1, kindness: 0.5 },
  "cold-blooded": { kindness: -1 }, "half asleep": { gibberish: 0.5, noise: -1 }, "slow to anger": { threat: 1, insult: 0.5 },
  "remembers everything": { question: 1.5 }, ancient: { flattery: 0.5 }, "covered in moss": { kindness: 0.5 },
  vain: { flattery: 1 }, bored: { joke: 1, peace: -1 }, "loves riddles": { question: 1, joke: 0.5 }, "hoards gold coins": { gold: 1 },
  "old battle scars": { courage: 1, threat: 0.5 },
};
export const POS = {
  kindness: ["touched", "delighted"], joke: ["amused", "delighted"], flattery: ["flattered", "delighted"], gold: ["delighted", "intrigued"],
  peace: ["touched", "delighted"], join: ["touched", "delighted"], question: ["intrigued"], courage: ["intrigued", "touched"],
  gibberish: ["amused", "confused"], threat: ["intrigued"], cheap: ["confused"], noise: ["confused"], rush: ["confused"], insult: ["confused"],
};
export const NEG = {
  kindness: ["confused"], joke: ["confused", "offended"], flattery: ["confused", "offended"], gold: ["offended"], peace: ["confused"],
  join: ["offended"], question: ["offended"], courage: ["enraged"], threat: ["terrified", "enraged"], insult: ["offended", "enraged"],
  cheap: ["offended", "enraged"], noise: ["enraged", "confused"], rush: ["offended"], gibberish: ["offended"],
};
// Nonsense makes each kind mad or sad in its own way
export const GIBBERISH_NEG = { bandit: ["offended"], snake: ["offended", "enraged"], rock: ["confused", "sad"], dragon: ["enraged"], slime: ["confused"] };

// What allies think of what you do. Recruits are passive charms; cross their values and they walk.
export const APPROVE = {
  slime: { slay: -2, slay_begging: -3, spare: 1.5, flee: 0, insult: -1, threat: -1, kindness: 0.5, joke: 0.5, noise: -0.5 },
  bandit: { slay: 1, slay_begging: 0.5, spare: -0.5, flee: -1, gold: -1.5, cheap: 1, insult: 0.5 },
  snake: { slay: -0.5, slay_begging: -2, spare: 1, flee: 0, gold: 1, rush: -1, noise: -1.5, threat: -1 },
  rock: { slay: -1, slay_begging: -1.5, spare: 1, flee: -1.5, noise: -2, rush: -1, gold: -1, peace: 1 },
  dragon: { slay: 1, slay_begging: 0, spare: -0.5, flee: -2.5, cheap: -1, courage: 1.5, insult: 0.5 },
};
export const CHARMS = {
  slime: { name: "BOUNCY", text: "absorbs the first hit of every fight" },
  bandit: { name: "KEEN EYE", text: "warnings stay lit longer" },
  snake: { name: "SLIPPERY", text: "longer safety after you get hit" },
  rock: { name: "STEADY", text: "the strike bar moves slower" },
  dragon: { name: "HOARD-FIRE", text: "+4 damage on every strike" },
};

export const ROSTER = [
  { species: "slime", genre: "bullet", hp: 18 },
  { species: "bandit", genre: "chess", hp: 24 },
  { species: "snake", genre: "shadow", hp: 22 },
  { species: "rock", genre: "rhythm", hp: 30 },
];
export const BOSS = { species: "dragon", genres: ["chess", "shadow", "rhythm", "bullet"], hp: 56 };

// ---------------------------------------------------------------- floor (DONJON's maze carver, smaller)

export function genFloor() {
  const N = 13;
  const grid = Array.from({ length: N }, () => Array(N).fill(0));
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
  for (let i = 0; i < 12; i++) {
    const x = rnd(1, N - 2);
    const y = rnd(1, N - 2);
    if (grid[y][x]) continue;
    if ((grid[y][x - 1] && grid[y][x + 1]) || (grid[y - 1][x] && grid[y + 1][x])) grid[y][x] = 1;
  }
  // The champion's 5x5 hall at the heart of the floor
  const c = Math.floor(N / 2);
  for (let yy = c - 2; yy <= c + 2; yy++) for (let xx = c - 2; xx <= c + 2; xx++) grid[yy][xx] = 1;
  const inHall = (x, y) => Math.abs(x - c) <= 2 && Math.abs(y - c) <= 2;
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
  // Monsters spread out along the way, nearest first, in roster order
  const cells = [...dist.entries()]
    .map(([k, d]) => [...k.split(",").map(Number), d])
    .filter(([x, y, d]) => d >= 3 && !inHall(x, y) && !(x === far[0] && y === far[1]))
    .sort((a, b) => a[2] - b[2]);
  const monsters = [];
  const used = [];
  ROSTER.forEach((r, i) => {
    const target = Math.floor(((i + 1) / (ROSTER.length + 1)) * cells.length);
    let best = null;
    for (let j = 0; j < cells.length; j++) {
      const [x, y] = cells[(target + j) % cells.length];
      if (used.every(([ux, uy]) => Math.abs(ux - x) + Math.abs(uy - y) > 2)) {
        best = [x, y];
        break;
      }
    }
    best ??= cells[target];
    used.push(best);
    monsters.push(rollTaste(makeMonster(r, best[0], best[1])));
  });
  monsters.push(rollTaste(makeMonster({ species: BOSS.species, genre: BOSS.genres[0], hp: BOSS.hp, boss: true }, c, c)));
  return { grid, n: N, stairs: { x: far[0], y: far[1] }, monsters, boss: { x: c, y: c, defeated: false } };
}

export function makeMonster(r, x, y) {
  const sp = SPECIES[r.species];
  return {
    species: r.species,
    genre: r.genre,
    boss: !!r.boss,
    name: r.boss ? "VEXALITH" : pick(sp.names).toUpperCase(),
    x,
    y,
    hp: r.hp,
    maxHp: r.hp,
    meters: { ...sp.start, friendliness: clamp(sp.start.friendliness + rnd(-10, 10), 0, 100), anger: clamp(sp.start.anger + rnd(-5, 10), 0, 100) },
    traits: [...sp.traits].sort(() => Math.random() - 0.5).slice(0, 2),
    taste: {},
    spoke: false,
    threshold: r.boss ? sp.joinThreshold + 5 : sp.joinThreshold,
    turn: 0,
    gone: null, // "spared" | "slain"
  };
}
export function rollTaste(m) {
  for (const k of Object.keys(AFF[m.species])) m.taste[k] = (Math.random() - 0.5) * 1.2;
  for (const t of m.traits) for (const [k, v] of Object.entries(TRAIT_TASTE[t] ?? {})) m.taste[k] = (m.taste[k] ?? 0) + v;
  return m;
}
export const aff = (m, intent) => (AFF[m.species][intent] ?? 0) + (m.taste[intent] ?? 0);

// ---------------------------------------------------------------- the mind (Jev-shaped questions, local answers)

const FEELINGS = Object.keys(EMOTIONS);

export function softmax(logits) {
  const m = Math.max(...Object.values(logits));
  const e = Object.fromEntries(Object.entries(logits).map(([k, v]) => [k, Math.exp(v - m)]));
  const s = Object.values(e).reduce((a, b) => a + b, 0);
  return Object.fromEntries(Object.entries(e).map(([k, v]) => [k, v / s]));
}

// DONJON's rule: any answer at 15% or more can happen, in proportion to its probability.
export function rollOdds(probs) {
  const live = Object.entries(probs).filter(([, p]) => p >= 0.15);
  const pool = live.length ? live : [Object.entries(probs).sort((a, b) => b[1] - a[1])[0]];
  const total = pool.reduce((s, [, p]) => s + p, 0);
  let r = Math.random() * total;
  for (const [k, p] of pool) if ((r -= p) <= 0) return k;
  return pool[pool.length - 1][0];
}

export function askFeeling(m, act) {
  const { friendliness: f, anger, fear } = m.meters;
  const logits = Object.fromEntries(FEELINGS.map((k) => [k, -1.4]));
  logits.confused += 0.4;
  if (act === "fight") {
    logits.terrified += 0.6 + fear / 30 + (m.hp / m.maxHp < 0.4 ? 1.6 : 0);
    logits.enraged += 1.2 + anger / 35;
    logits.sad += 0.4 + f / 60;
    logits.offended += 0.6;
  } else {
    // `act` is a list of intents with weights: one for an ACT button, a spread for typed words
    for (const { intent, w } of act) {
      const a = aff(m, intent);
      const pool = a >= 0 ? POS[intent] : intent === "gibberish" ? GIBBERISH_NEG[m.species] : NEG[intent];
      for (const k of pool ?? []) logits[k] += w * (1.4 + 1.1 * Math.abs(a) + (a >= 0 ? -anger / 50 : anger / 50));
    }
    logits.terrified += fear / 60;
  }
  const probs = softmax(logits);
  return { type: "choice", choice: rollOdds(probs), probabilities: probs };
}

export function askMercy(m) {
  const { friendliness: f, anger, fear } = m.meters;
  const low = m.hp / m.maxHp < 0.4;
  const x = (f - m.threshold) / 9 + ((fear - 40) / 25) * (low ? 1 : 0.3) - anger / 30;
  return { type: "noul", noul: sigmoid(x) };
}

export function askPressure(m) {
  const { friendliness: f, anger, fear } = m.meters;
  const raw = clamp((anger * 1.2 - f * 0.5 - fear * 0.4 + 45) / 30, 0, 3);
  const levels = [0, 1, 2, 3].map((i) => Math.exp(-((i - raw) ** 2) * 1.6));
  const s = levels.reduce((a, b) => a + b, 0);
  return { type: "score", score: raw, probabilities: Object.fromEntries(levels.map((v, i) => [String(i), v / s])) };
}

export function applyFeeling(m, id) {
  const em = EMOTIONS[id];
  for (const [k, v] of Object.entries(em.meters ?? {})) m.meters[k] = clamp(m.meters[k] + v, 0, 100);
  return em;
}

// ---------------------------------------------------------------- reading typed words

// Keyword cues for each intent. Stand-in for Jev reading the words; the real build asks Jev what they meant.
export const CUES = {
  kindness: /\b(friend|kind|sorry|love|care|safe|hug|please|thank|nice|gentle|help|cute|okay|ok)\b/g,
  joke: /\b(joke|haha+|lol|funny|pun|knock|laugh|silly|boop|blorp|bloop)\b/g,
  flattery: /\b(beautiful|strong|mighty|pretty|shiny|scales?|great|impressive|wise|handsome|magnificent|cool|amazing|majestic|old)\b/g,
  gold: /\b(gold|coins?|pay|money|cut|share|deal|trade|offer|bargain|loot|treasure)\b/g,
  threat: /\b(kill|die|destroy|crush|smash|end you|hurt you|slay)\b/g,
  insult: /\b(stupid|ugly|gross|dumb|idiot|weak|pathetic|slimy|loser|worm|thief|rock-head)\b/g,
  peace: /\b(peace|stop|truce|calm|quiet|rest|wait|no fight|don't fight|leave)\b/g,
  join: /\b(join|come with|team|together|party|follow|with us)\b/g,
  question: /\?|\b(where|what|who|why|how|stairs|way out|exit|tell me|secret)\b/g,
  rush: /\b(hurry|quick|faster|now now|move it)\b/g,
  noise: /\b(loud|bang|scream|yell)\b|!{3,}/g,
};
const COMMON = new Set("a an the i you me my we us it is are am be to of in on at for and or but not no yes do don't can will want like with your our this that here there so just very hi hello hey".split(" "));

export function gibberishOdds(text) {
  const t = text.toLowerCase().trim();
  const words = t.match(/[a-z']+/g) ?? [];
  if (!words.length) return 0.95;
  let bad = 0;
  for (const w of words) {
    if (COMMON.has(w)) continue;
    const vowels = (w.match(/[aeiouy]/g) ?? []).length;
    const run = Math.max(0, ...(w.match(/[^aeiouy']+/g) ?? [""]).map((x) => x.length));
    if (w.length > 2 && (vowels === 0 || run >= 4 || /(.)\1\1/.test(w) || /asdf|qwer|zxcv|jkl|hjk/.test(w) || vowels / w.length < 0.15)) bad++;
  }
  const cues = Object.values(CUES).reduce((n, re) => n + (t.match(re) ?? []).length, 0);
  return clamp(bad / words.length - cues * 0.15 + (words.length === 1 && !cues ? 0.2 : 0), 0.02, 0.97);
}

export function readWords(text) {
  const t = text.toLowerCase();
  const gib = gibberishOdds(text);
  const logits = { other: 0.3 };
  for (const [k, re] of Object.entries(CUES)) logits[k] = Math.min((t.match(re) ?? []).length, 2) * 1.5 - 0.6;
  const p = softmax(logits);
  const probs = Object.fromEntries(Object.entries(p).map(([k, v]) => [k, v * (1 - gib)]));
  probs.gibberish = gib;
  return { type: "choice", choice: Object.entries(probs).sort((a, b) => b[1] - a[1])[0][0], probabilities: probs };
}

export const INTENT_WORDS = {
  kindness: "kindness", joke: "jokes", flattery: "praise", gold: "gold", threat: "threats", insult: "insults", peace: "quiet and peace",
  join: "company", question: "questions", gibberish: "nonsense", courage: "courage", cheap: "cheap offers", noise: "noise", rush: "being rushed",
};

// ---------------------------------------------------------------- the box: one grid, one rule (lit squares hurt)

export const W = 448;
export const H = 288;
export const COLS = 7;
export const ROWS = 7;
export const CELL = 28;
export const BX = (W - COLS * CELL) / 2;
export const BY = 82;
export const idx = (c, r) => r * COLS + c;
export const inBox = (c, r) => c >= 0 && r >= 0 && c < COLS && r < ROWS;
export const rowCells = (r) => Array.from({ length: COLS }, (_, c) => idx(c, r));
export const colCells = (c) => Array.from({ length: ROWS }, (_, r) => idx(c, r));

// Chess: the squares a piece standing on `o` attacks, its own square included
export const rookCells = (o) => [...rowCells(o.r), ...colCells(o.c)];
const DIAGONALS = [[1, 1], [1, -1], [-1, 1], [-1, -1]];
export function bishopCells(o) {
  const cells = [];
  for (const [ex, ey] of DIAGONALS) for (let s = 0; s < 8; s++) if (inBox(o.c + ex * s, o.r + ey * s)) cells.push(idx(o.c + ex * s, o.r + ey * s));
  return cells;
}
export const KNIGHT = [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]];
export const knightCells = (o) => [...KNIGHT.map(([dx, dy]) => [o.c + dx, o.r + dy]).filter(([x, y]) => inBox(x, y)).map(([x, y]) => idx(x, y)), idx(o.c, o.r)];

// Rhythm: the stomp patterns, in the order the beat walks through them. The last one aims at where you stand.
const EVERY = Array.from({ length: COLS * ROWS }, (_, k) => k);
export const STOMPS = [
  () => [0, 2, 4, 6].flatMap(colCells),
  () => [1, 3, 5].flatMap(colCells),
  () => [0, 2, 4, 6].flatMap(rowCells),
  () => [1, 3, 5].flatMap(rowCells),
  () => [...rowCells(0), ...rowCells(6), ...colCells(0), ...colCells(6)],
  () => [...rowCells(3), ...colCells(3)],
  () => EVERY.filter((k) => ((k % COLS) + Math.floor(k / COLS)) % 2 === 0),
  () => EVERY.filter((k) => ((k % COLS) + Math.floor(k / COLS)) % 2 === 1),
  (soul) => [...rowCells(soul.r), ...colCells(soul.c)],
];

// Shadow: three pillars, and a lantern circling the box; `ms` is the time since the dodge began.
export const PILLARS = [idx(2, 2), idx(4, 4), idx(5, 1)];
export function lanternAt(ms, intensity) {
  const a = (ms / 1000) * 0.75 * intensity + 2.4;
  return { x: W / 2 + Math.cos(a) * 168, y: BY + (ROWS * CELL) / 2 + Math.sin(a) * 118 };
}
// A cell is in shadow when the line from the lantern to its center crosses a pillar
export function shaded(L, c, r, blocked) {
  const tx = BX + (c + 0.5) * CELL;
  const ty = BY + (r + 0.5) * CELL;
  for (let i = 1; i < 40; i++) {
    const s = i / 40;
    const x = L.x + (tx - L.x) * s;
    const y = L.y + (ty - L.y) * s;
    const pc = Math.floor((x - BX) / CELL);
    const pr = Math.floor((y - BY) / CELL);
    if (inBox(pc, pr) && blocked.has(idx(pc, pr)) && !(pc === c && pr === r)) return true;
  }
  return false;
}
