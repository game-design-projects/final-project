// DONJON: Genre Halls (genre-halls.html). Exploration is DONJON's wireframe maze; encounters switch into an
// Undertale-style box where each faction attacks in its own genre (chess, shadow, rhythm, goo rain), all with one rule:
// lit squares hurt. FIGHT / ACT / SPARE / FLEE. The monster's mind answers Jev-shaped questions (choice / score / yes-no
// with probabilities); here a local stand-in answers them. The rules live in genre-rules.js; this file draws and plays.

import { DIRS, PALETTES, drawCorridor, drawMap, drawTitle, clear, scaleAt, VIEW } from "./render.js";
import { drawMonster, BOSS_COLOR } from "./art.js";
import { SPECIES, fill } from "./species.js";
import { EMOTIONS, PACIFYING } from "./emotions.js";
import { Sfx } from "./sfx.js";
import {
  rnd, pick, clamp, sigmoid, GENRES, ACTS, AFF, APPROVE, CHARMS, BOSS, INTENT_WORDS, genFloor, aff,
  rollOdds, askFeeling, askMercy, askPressure, applyFeeling, readWords,
  W, H, COLS, ROWS, CELL, BX, BY, idx, inBox, rookCells, bishopCells, KNIGHT, knightCells, STOMPS, PILLARS, lanternAt, shaded,
} from "./genre-rules.js";

const view = document.getElementById("view").getContext("2d");
const mapCtx = document.getElementById("map").getContext("2d");
const $ = (id) => document.getElementById(id);
const PIX = '"Press Start 2P", monospace';

const sfx = new Sfx(0.5);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// ---------------------------------------------------------------- state

const G = {
  mode: "title",
  map: null,
  x: 1,
  y: 1,
  dir: 1,
  seen: new Set(),
  visited: new Set(),
  hp: 20,
  maxHp: 20,
  foe: null,
  menu: [],
  sel: 0,
  tally: { spared: 0, slain: 0, fled: 0, recruited: 0, left: 0 },
  allies: [],
  shake: 0,
};

function newRun() {
  G.map = genFloor();
  G.map.palette = pick(PALETTES);
  G.map.seed = Math.floor(Math.random() * 1e9);
  G.x = 1;
  G.y = 1;
  G.dir = DIRS.findIndex(([dx, dy]) => G.map.grid[1 + dy]?.[1 + dx] === 1);
  G.seen = new Set();
  G.visited = new Set([G.map.n + 1]);
  G.hp = G.maxHp;
  G.tally = { spared: 0, slain: 0, fled: 0, recruited: 0, left: 0 };
  G.allies = [];
  renderParty();
  G.foe = null;
  explore(
    `<span class="sys">B1F. Four kinds of monster hold this floor, and each one fights by its own rules. Lit squares hurt. You can fight them, talk them down, or spare them, and a spared monster may join you.</span>`,
  );
}

// ---------------------------------------------------------------- the mind (Jev-shaped questions, local answers)

let lastMind = { m: null, answers: [] };
function renderMindAppend(m, rows) {
  renderMind(m, [...(lastMind.m === m ? lastMind.answers : []), ...rows]);
}
function renderMind(m, answers) {
  lastMind = { m, answers };
  $("mind-who").textContent = m ? `${m.name} · ${SPECIES[m.species].label.toUpperCase()}` : "NOBODY YET";
  if (!m) return;
  const traits = m.traits?.length ? `<p class="note">Seems ${esc(m.traits.join(" and "))}.</p>` : "";
  const meters = traits + `<div class="meters"><span>FRIENDLY<b>${Math.round(m.meters.friendliness)}</b></span><span>ANGER<b>${Math.round(m.meters.anger)}</b></span><span>FEAR<b>${Math.round(m.meters.fear)}</b></span></div>`;
  const rows = answers
    .map(({ id, label, a }) => {
      let body = "";
      if (a.type === "choice") {
        const top = Object.entries(a.probabilities).sort((x, y) => y[1] - x[1]).slice(0, 5);
        body = top
          .map(([k, p]) => `<div class="${k === a.choice ? "pick" : ""}"><span>${EMOTIONS[k]?.label ?? k.toUpperCase()}</span><span class="track"><span class="fill" style="width:${(p * 100).toFixed(1)}%"></span></span><em>${Math.round(p * 100)}%</em></div>`)
          .join("");
      } else if (a.type === "noul") {
        body = `<div class="pick"><span>YES${a.yes === undefined ? "" : a.yes ? " \u2192 YES" : " \u2192 NO"}</span><span class="track"><span class="fill" style="width:${(a.noul * 100).toFixed(1)}%"></span></span><em>${Math.round(a.noul * 100)}%</em></div>`;
      } else {
        body = Object.entries(a.probabilities)
          .map(([k, p]) => `<div class="${Math.round(a.score) === Number(k) ? "pick" : ""}"><span>LEVEL ${k}</span><span class="track"><span class="fill" style="width:${(p * 100).toFixed(1)}%"></span></span><em>${Math.round(p * 100)}%</em></div>`)
          .join("");
      }
      return `<div class="q"><div class="head"><span>${esc(label)}</span><code>${a.type}</code></div><div class="bars">${body}</div></div>`;
    })
    .join("");
  $("mind").innerHTML = meters + rows;
}

// ---------------------------------------------------------------- dock (text + menu)

function say(html) {
  $("say").innerHTML = html;
}
function line(m, kind) {
  const sp = SPECIES[m.species];
  const pool = sp.lines?.[kind];
  if (!pool?.length) return "";
  const text = fill(pick(pool), { name: m.name[0] + m.name.slice(1).toLowerCase(), target: "you" });
  sfx.shout(text, m.species, { boss: m.boss });
  return `<span class="who">${esc(m.name)}:</span> ${esc(text)}`;
}

function setMenu(items, keys) {
  G.menu = items;
  G.sel = clamp(G.sel, 0, Math.max(0, items.length - 1));
  $("menu").innerHTML = items
    .map((it, i) => `<button type="button" id="cmd-${i}" class="${i === G.sel ? "on" : ""}" data-i="${i}"><span class="k">${i + 1}</span>${esc(it.label)}${it.sub ? `<span class="sub">${esc(it.sub)}</span>` : ""}</button>`)
    .join("");
  $("keys").innerHTML = keys ?? "";
}
$("menu").addEventListener("click", (e) => {
  const b = e.target.closest("button[data-i]");
  if (!b) return;
  sfx.init();
  G.sel = Number(b.dataset.i);
  G.menu[G.sel]?.run();
});
function moveSel(d) {
  if (!G.menu.length) return;
  G.sel = (G.sel + d + G.menu.length) % G.menu.length;
  [...$("menu").children].forEach((b, i) => b.classList.toggle("on", i === G.sel));
  sfx.play("tick");
}

function hud() {
  $("hp").textContent = `${Math.max(0, G.hp)}/${G.maxHp}`;
  const { spared, slain } = G.tally;
  $("route").textContent = spared + slain === 0 ? "UNWRITTEN" : `${spared} SPARED · ${slain} SLAIN`;
  $("where").textContent = G.foe ? `${GENRES[foeGenre()].name} ENCOUNTER` : "THE GENRE HALLS";
}

// ---------------------------------------------------------------- exploring

function explore(msg) {
  G.mode = "explore";
  G.foe = null;
  if (msg) say(msg);
  setMenu([], `<kbd>&uarr;</kbd><kbd>&darr;</kbd> WALK &nbsp;<kbd>&larr;</kbd><kbd>&rarr;</kbd> TURN &nbsp;· FIND THE STAIRS. MONSTERS SHOW ON THE MAP WHEN SEEN`);
  hud();
}

function monsterAt(x, y) {
  return G.map.monsters.find((m) => !m.gone && m.x === x && m.y === y);
}

function step(sign) {
  const [dx, dy] = DIRS[sign > 0 ? G.dir : (G.dir + 2) % 4];
  const nx = G.x + dx;
  const ny = G.y + dy;
  if (G.map.grid[ny]?.[nx] !== 1) {
    sfx.play("bump");
    G.shake = performance.now() + 160;
    return;
  }
  const m = monsterAt(nx, ny);
  if (m) return startEncounter(m);
  G.x = nx;
  G.y = ny;
  G.visited.add(ny * G.map.n + nx);
  if (nx === G.map.stairs.x && ny === G.map.stairs.y) ending();
}

// The monster standing straight ahead, if nothing blocks the view
function monsterAhead() {
  const [dx, dy] = DIRS[G.dir];
  for (let d = 1; d <= VIEW - 1; d++) {
    const cx = G.x + dx * d;
    const cy = G.y + dy * d;
    if (G.map.grid[cy]?.[cx] !== 1) return null;
    const m = monsterAt(cx, cy);
    if (m) return { m, d };
  }
  return null;
}

// ---------------------------------------------------------------- encounters

const foeGenre = () => (G.foe.boss ? BOSS.genres[G.foe.turn % BOSS.genres.length] : G.foe.genre);

function startEncounter(m) {
  G.foe = m;
  G.mode = "intro";
  G.sel = 0;
  sfx.play(m.boss ? "boss" : "encounter");
  introUntil = performance.now() + 700;
  renderMind(m, [{ id: "mercy", label: "WILL IT ACCEPT MERCY?", a: askMercy(m) }]);
  say(`${line(m, "converse")}<br><span class="sys">${m.boss ? "The champion shifts its rules every turn: chess, shadow, rhythm, goo." : `It fights in ${GENRES[m.genre].name}. ${GENRES[m.genre].rule}.`}</span>`);
  hud();
  setTimeout(() => G.mode === "intro" && G.foe === m && mainMenu(), 700);
}

function spareable(m) {
  return askMercy(m).noul >= 0.5;
}

function mainMenu(msg) {
  G.mode = "menu";
  if (msg) say(msg);
  const m = G.foe;
  const mercy = askMercy(m).noul;
  setMenu(
    [
      { label: "FIGHT", sub: "Time the strike", run: () => fightBar() },
      { label: "ACT", sub: "Say or do something", run: () => actMenu() },
      { label: "SPARE", sub: mercy >= 0.5 ? "It looks ready to stop" : "It isn't ready yet", run: () => spare() },
      { label: "FLEE", sub: m.boss ? "Champions block the way" : "Back away", run: () => flee() },
    ],
    `<kbd>&uarr;</kbd><kbd>&darr;</kbd> CHOOSE <kbd>ENTER</kbd> PICK <kbd>1</kbd>-<kbd>4</kbd>`,
  );
  hud();
}

function actMenu() {
  const m = G.foe;
  G.mode = "act";
  G.sel = 0;
  const acts = ACTS[m.species];
  setMenu(
    [
      { label: "CHECK", sub: "Free: read it", run: () => check() },
      ...acts.map((a) => ({ label: a.label, run: () => doAct(a) })),
      m.spoke
        ? { label: "SAY SOMETHING", sub: "Already spoke this fight", run: () => mainMenu(`<span class="sys">You've had your say this fight.</span>`) }
        : { label: "SAY SOMETHING", sub: "Optional: type once per fight", run: () => openTalk() },
    ],
    `<kbd>ENTER</kbd> PICK <kbd>ESC</kbd> BACK`,
  );
}

function check() {
  const m = G.foe;
  const sp = SPECIES[m.species];
  mainMenu(`<span class="sys">${esc(m.name)} seems <b>${esc(m.traits.join("</b> and <b>"))}</b>. Its kind likes ${esc(sp.likes.slice(0, 2).join(", "))} and hates ${esc(sp.dislikes[0])}. This one may differ.</span>`);
}

function decide(m, act, actLabel, words = null) {
  const feeling = askFeeling(m, act);
  const em = applyFeeling(m, feeling.choice);
  const mercy = askMercy(m);
  const pressure = askPressure(m);
  renderMind(m, [
    ...(words ? [{ id: "words", label: "WHAT DID YOUR WORDS MEAN?", a: words }] : []),
    { id: "feeling", label: `HOW DOES IT FEEL? (${actLabel})`, a: feeling },
    { id: "mercy", label: "WILL IT ACCEPT MERCY?", a: mercy },
    { id: "pressure", label: "HOW HARD DOES IT ATTACK?", a: pressure },
  ]);
  return { em, id: feeling.choice, pressure: pressure.score, pacified: PACIFYING.has(em.cond) };
}

function doAct(act) {
  const m = G.foe;
  const r = decide(m, [{ intent: act.intent, w: 1 }], act.label);
  judge(act.intent);
  sfx.play(r.em.tone === "good" ? "good" : r.em.tone === "bad" ? "bad" : "odd");
  afterPlayer(`<span class="sys">You ${esc(act.label.toLowerCase())}.</span> ${esc(m.name)} is <b>${r.em.label}</b>: ${esc(r.em.effect.toLowerCase())}.`, r);
}

// ---------------------------------------------------------------- talking (optional, once per fight)

function openTalk() {
  G.mode = "talk";
  $("talk").hidden = false;
  $("talk-in").value = "";
  setMenu([], `TYPE ANYTHING <kbd>ENTER</kbd> SAY IT <kbd>ESC</kbd> NEVER MIND · NONSENSE COUNTS TOO`);
  setTimeout(() => $("talk-in").focus(), 0);
}
function closeTalk() {
  $("talk").hidden = true;
  $("talk-in").blur();
}
$("talk").addEventListener("submit", (e) => {
  e.preventDefault();
  const text = $("talk-in").value.trim().slice(0, 140);
  closeTalk();
  if (!text) return actMenu();
  say$(text);
});
$("talk-in").addEventListener("keydown", (e) => {
  e.stopPropagation();
  if (e.key === "Escape") {
    closeTalk();
    actMenu();
  }
});

function say$(text) {
  const m = G.foe;
  m.spoke = true;
  const words = readWords(text);
  const parts = Object.entries(words.probabilities)
    .filter(([k, p]) => k !== "other" && p >= 0.12)
    .map(([intent, w]) => ({ intent, w }));
  const r = decide(m, parts.length ? parts : [{ intent: "question", w: 0.3 }], "YOUR WORDS", words);
  const top = words.choice;
  judge(top === "other" ? null : top);
  let extra = "";
  if (top === "gibberish") extra = `<br><span class="sys">It didn't understand a word of that.</span>`;
  else if (words.probabilities.question >= 0.25 && r.em.tone !== "bad") extra = `<br><span class="who">${esc(m.name)}:</span> ${esc(hintFor(m))}`;
  afterPlayer(`<span class="sys">You say "${esc(text)}".</span> ${esc(m.name)} is <b>${r.em.label}</b>: ${esc(r.em.effect.toLowerCase())}.${extra}`, r);
}

// Talking can pay off in information: where the stairs are, or what another monster can't stand
function hintFor(m) {
  const others = G.map.monsters.filter((x) => !x.gone && x !== m);
  const s = G.map.stairs;
  const dir = Math.abs(s.x - m.x) > Math.abs(s.y - m.y) ? (s.x > m.x ? "east" : "west") : s.y > m.y ? "south" : "north";
  const pool = [`...the way down is to the ${dir}.`];
  for (const o of others) {
    const worst = Object.keys(AFF[o.species]).sort((a, b) => aff(o, a) - aff(o, b))[0];
    const best = Object.keys(AFF[o.species]).sort((a, b) => aff(o, b) - aff(o, a))[0];
    pool.push(`...${o.name[0] + o.name.slice(1).toLowerCase()} the ${SPECIES[o.species].label}? it hates ${INTENT_WORDS[worst]}. loves ${INTENT_WORDS[best]}.`);
  }
  return pick(pool);
}

// ---------------------------------------------------------------- allies: passive charms that judge you

const hasAlly = (species) => G.allies.some((a) => a.species === species);

function judge(event) {
  if (!event || !G.allies.length) return;
  const rows = [];
  const notes = [];
  for (const a of [...G.allies]) {
    const v = APPROVE[a.species][event];
    if (v === undefined) continue;
    const mean = clamp(2 + v, 0, 4);
    const levels = [0, 1, 2, 3, 4].map((i) => Math.exp(-((i - mean) ** 2) * 0.9));
    const sum = levels.reduce((x, y) => x + y, 0);
    const probs = Object.fromEntries(levels.map((x, i) => [String(i), x / sum]));
    const score = Number(rollOdds(probs));
    a.loyalty = clamp(a.loyalty + (score - 2) * 10, 0, 100);
    rows.push({ id: `judge-${a.name}`, label: `${a.name} JUDGES IT (0 HATES - 4 LOVES)`, a: { type: "score", score, probabilities: probs } });
    const sp = SPECIES[a.species];
    const kind = score <= 1 ? "disapprove" : score >= 3 ? "approve" : null;
    if (kind) notes.push(`<span class="who">${esc(a.name)}:</span> ${esc(fill(pick(sp.reactions[kind]), { name: a.name, target: "you" }))}`);
    if (a.loyalty < 30) {
      const p = sigmoid((30 - a.loyalty) / 6 - 0.5);
      const leaves = Math.random() < p;
      rows.push({ id: `leave-${a.name}`, label: `DOES ${a.name} LEAVE?`, a: { type: "noul", noul: p, yes: leaves } });
      if (leaves) {
        G.allies = G.allies.filter((x) => x !== a);
        G.tally.left++;
        sfx.play("sad");
        notes.push(`<span class="who">${esc(a.name)}:</span> ${esc(fill(pick(sp.reactions.leave), { name: a.name }))} <span class="sys">(${CHARMS[a.species].name} is gone)</span>`);
      }
    }
  }
  if (rows.length) pendingJudgement = { rows, notes };
  renderParty();
}
let pendingJudgement = null;

function renderParty() {
  const el = $("party");
  if (!G.allies.length) {
    el.innerHTML = `<p class="empty">Spare a monster and it may ask to join. Allies ride along as passive charms, and they leave if you cross their values.</p>`;
    return;
  }
  el.innerHTML = G.allies
    .map((a) => {
      const c = CHARMS[a.species];
      const mood = a.loyalty >= 70 ? "DEVOTED" : a.loyalty >= 45 ? "CONTENT" : a.loyalty >= 30 ? "UNEASY" : "MAY LEAVE";
      return `<div class="ally"><div class="head"><span><i style="background:${SPECIES[a.species].color}"></i>${esc(a.name)}</span><em class="${a.loyalty < 30 ? "warn" : ""}">${mood}</em></div><div class="bars"><div><span>${c.name}</span><span class="track"><span class="fill" style="width:${a.loyalty}%"></span></span><em>${Math.round(a.loyalty)}</em></div></div><p class="note">${esc(c.text)}. Cares about: ${esc(SPECIES[a.species].values.split(".")[0].toLowerCase())}.</p></div>`;
    })
    .join("");
}

// FIGHT: a timing bar. Press OK near the middle.
let bar = null;
function fightBar() {
  G.mode = "fightbar";
  setMenu([], `<kbd>ENTER</kbd> STRIKE WHEN THE LINE CROSSES THE MIDDLE`);
  bar = { t0: performance.now(), dur: hasAlly("rock") ? 1500 : 1100 };
}
function strike(now) {
  const m = G.foe;
  const x = clamp((now - bar.t0) / bar.dur, 0, 1);
  bar = null;
  const off = Math.abs(x - 0.5) * 2;
  if (off > 0.92) {
    sfx.play("miss");
    const r = decide(m, "fight", "YOU SWUNG");
    return afterPlayer(`<span class="sys">You swing wide and miss.</span> ${esc(m.name)} is <b>${r.em.label}</b>.`, r);
  }
  const crit = off < 0.08;
  const dmg = Math.round((crit ? 14 : 4 + 8 * (1 - off) ** 1.2) * (m.boss ? 0.8 : 1)) + (hasAlly("dragon") ? 4 : 0);
  m.hp = Math.max(0, m.hp - dmg);
  sfx.play(crit ? "crit" : "hit");
  hurtUntil = now + 300;
  m.meters.friendliness = clamp(m.meters.friendliness - 8, 0, 100);
  m.meters.anger = clamp(m.meters.anger + 10, 0, 100);
  m.meters.fear = clamp(m.meters.fear + 8, 0, 100);
  if (m.hp <= 0) {
    judge(spareable(m) ? "slay_begging" : "slay");
    return defeat(m, "slain");
  }
  const begging = spareable(m);
  const r = decide(m, "fight", "YOU HIT IT");
  if (begging) judge("slay_begging");
  afterPlayer(`<span class="sys">${crit ? "A perfect strike! " : ""}${dmg} damage.</span> ${esc(m.name)} is <b>${r.em.label}</b>: ${esc(r.em.effect.toLowerCase())}.`, r);
}

function spare() {
  const m = G.foe;
  const mercy = askMercy(m);
  const yes = Math.random() < mercy.noul;
  renderMind(m, [{ id: "mercy", label: "WILL IT ACCEPT MERCY?", a: { ...mercy, yes } }]);
  if (yes) {
    judge("spare");
    return defeat(m, "spared");
  }
  sfx.play("bad");
  const r = { pressure: askPressure(m).score, pacified: false };
  m.meters.anger = clamp(m.meters.anger + 4, 0, 100);
  afterPlayer(`<span class="sys">You offer mercy.</span> ${esc(m.name)} isn't ready to stop. (${Math.round(mercy.noul * 100)}% it would have)`, r);
}

function flee() {
  const m = G.foe;
  if (m.boss) return mainMenu(`<span class="sys">The champion's tail blocks the way back.</span>`);
  G.tally.fled++;
  sfx.play("flee");
  judge("flee");
  m.hp = m.maxHp;
  const notes = pendingJudgement?.notes?.length ? `<br>${pendingJudgement.notes.join("<br>")}` : "";
  if (pendingJudgement) renderMind(m, pendingJudgement.rows);
  pendingJudgement = null;
  explore(`<span class="sys">You back away. ${esc(m.name)} stays where it is.</span>${notes}`);
}

function defeat(m, how) {
  m.gone = how;
  G.tally[how]++;
  if (m.boss) G.map.boss.defeated = true;
  sfx.play(how === "spared" ? "good" : "kill");
  let text = `<span class="sys">${esc(m.name)} falls.</span>`;
  let joined = false;
  if (how === "spared") {
    const f = m.meters.friendliness;
    const room = G.allies.length < 3;
    const p = room ? sigmoid((f - m.threshold - 4) / 7 + aff(m, "join") * 0.4) : 0;
    joined = Math.random() < p;
    const rows = [{ id: "join", label: room ? "DOES IT WANT TO COME ALONG?" : "DOES IT WANT TO COME ALONG? (PARTY FULL)", a: { type: "noul", noul: p, yes: joined } }];
    renderMind(m, pendingJudgement ? [...rows, ...pendingJudgement.rows] : rows);
    if (joined) {
      G.allies.push({ species: m.species, name: m.name, loyalty: 60 + rnd(0, 20) });
      G.tally.recruited++;
      sfx.play("join");
      renderParty();
    }
    text = line(m, joined ? "join_party" : "leave_peacefully");
  } else if (pendingJudgement) renderMind(m, pendingJudgement.rows);
  const notes = pendingJudgement?.notes?.length ? `<br>${pendingJudgement.notes.join("<br>")}` : "";
  pendingJudgement = null;
  G.mode = "result";
  hud();
  say(`${text}<br><span class="sys">${how === "spared" ? (joined ? `SPARED. It joins you: ${CHARMS[m.species].name}, ${CHARMS[m.species].text}.` : "SPARED. It goes its own way.") : "SLAIN."}</span>${notes}`);
  setMenu([{ label: "CONTINUE", run: () => explore() }], `<kbd>ENTER</kbd> CONTINUE`);
}

function afterPlayer(msg, r) {
  const m = G.foe;
  if (pendingJudgement) {
    msg += `<br>${pendingJudgement.notes.join("<br>")}`;
    renderMindAppend(m, pendingJudgement.rows);
    pendingJudgement = null;
  }
  if (r.pacified) return mainMenu(`${msg}<br><span class="sys">It doesn't attack this turn.</span>`);
  say(`${msg}<br>${line(m, "attack")}`);
  G.mode = "wait";
  setMenu([], "");
  setTimeout(() => G.foe === m && startDodge(r.pressure), 650);
}

// ---------------------------------------------------------------- the box: one grid, one rule (lit squares hurt)

let D = null; // the dodge phase
let hurtUntil = 0;
let introUntil = 0;

function startDodge(pressure) {
  const m = G.foe;
  const genre = foeGenre();
  const intensity = (0.8 + 0.25 * pressure) * (m.boss ? 1.2 : 1);
  const now = performance.now();
  D = {
    genre,
    intensity,
    t0: now,
    end: now + (m.boss ? 6200 : 5400),
    soul: { c: 3, r: 3 },
    hazards: [],
    next: now + 300,
    beat: -1,
    blocked: new Set(),
    iframes: 0,
    shield: hasAlly("slime"),
    hitFlash: 0,
  };
  if (genre === "shadow") PILLARS.forEach((k) => D.blocked.add(k));
  G.mode = "dodge";
  setMenu([], `<kbd>&uarr;</kbd><kbd>&darr;</kbd><kbd>&larr;</kbd><kbd>&rarr;</kbd> MOVE · ${GENRES[genre].rule}`);
  hud();
}

function hazard(cells, warnMs, hitMs, kind, extra = {}) {
  const now = performance.now();
  if (kind !== "stomp" && hasAlly("bandit")) warnMs *= 1.3;
  D.hazards.push({ cells: new Set([...cells].filter((k) => !D.blocked.has(k))), warn: now, hit: now + warnMs, end: now + warnMs + hitMs, kind, ...extra });
}

const SPAWN = {
  chess(now) {
    if (now < D.next) return;
    D.next = now + 760 / D.intensity;
    const { c, r } = D.soul;
    const kind = pick(["rook", "rook", "bishop", "bishop", "knight"]);
    if (kind === "rook") {
      const o = Math.random() < 0.5 ? { c: pick([0, COLS - 1]), r } : { c, r: pick([0, ROWS - 1]) };
      hazard(rookCells(o), 950, 320, "chess", { glyph: "R", at: idx(o.c, o.r) });
    } else if (kind === "bishop") {
      const [dx, dy] = pick([[1, 1], [1, -1], [-1, 1], [-1, -1]]);
      let k = rnd(1, 3);
      while (k > 0 && !inBox(c + dx * k, r + dy * k)) k--;
      const o = { c: c + dx * k, r: r + dy * k };
      hazard(bishopCells(o), 950, 320, "chess", { glyph: "B", at: idx(o.c, o.r) });
    } else {
      const o = pick(KNIGHT.map(([dx, dy]) => ({ c: c + dx, r: r + dy })).filter((o) => inBox(o.c, o.r)));
      hazard(knightCells(o), 900, 320, "chess", { glyph: "N", at: idx(o.c, o.r) });
    }
  },
  bullet(now) {
    if (now < D.next) return;
    D.next = now + 330 / D.intensity;
    const aim = Math.random() < 0.4;
    const c = aim ? D.soul.c : rnd(0, COLS - 1);
    const r = aim ? D.soul.r : rnd(0, ROWS - 1);
    const cells = [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => [c + dx, r + dy]).filter(([x, y]) => inBox(x, y)).map(([x, y]) => idx(x, y));
    hazard(cells, 820, 260, "goo", { at: idx(c, r) });
  },
  rhythm(now) {
    const beatMs = 600 / Math.sqrt(D.intensity);
    const b = Math.floor((now - D.t0) / beatMs);
    if (b <= D.beat) return;
    D.beat = b;
    sfx.play("tick");
    D.pulse = now;
    if (b % 2 === 1) return; // a new stomp every other beat, telegraphed for two beats
    const p = (b * 5 + (G.foe.turn % 3)) % STOMPS.length;
    // Telegraphed two beats ahead, lands on the beat
    hazard(STOMPS[p](D.soul), beatMs * 2, 240, "stomp", { beatHit: true });
  },
  shadow(now) {
    if (now < D.next) return;
    D.next = now + 1250 / D.intensity;
    const warn = 900;
    const L = lanternAt(now + warn - D.t0, D.intensity);
    const cells = [];
    for (let r = 0; r < ROWS; r++)
      for (let c = 0; c < COLS; c++) {
        const k = idx(c, r);
        if (!D.blocked.has(k) && !shaded(L, c, r, D.blocked)) cells.push(k);
      }
    hazard(cells, warn, 300, "light", { L });
  },
};

function updateDodge(now) {
  SPAWN[D.genre](now);
  const here = idx(D.soul.c, D.soul.r);
  for (const h of D.hazards) {
    if (now >= h.hit && !h.sounded) {
      h.sounded = true;
      if (h.kind === "stomp") sfx.play("hit");
      else if (h.kind === "chess") sfx.play("slash");
      else if (h.kind === "light") sfx.play("holy");
    }
    if (now >= h.hit && now < h.end && h.cells.has(here) && now > D.iframes) {
      const safe = hasAlly("snake") ? 1100 : 700;
      if (D.shield) {
        D.shield = false;
        D.iframes = now + safe;
        D.blockFlash = now;
        sfx.play("buff");
        continue;
      }
      const dmg = G.foe.boss ? 4 : 3;
      G.hp -= dmg;
      D.iframes = now + safe;
      D.hitFlash = now;
      G.shake = now + 200;
      sfx.play("hurt");
      hud();
      if (G.hp <= 0) return dead();
    }
  }
  D.hazards = D.hazards.filter((h) => now < h.end);
  if (now >= D.end) {
    D = null;
    G.foe.turn++;
    mainMenu(`<span class="sys">${esc(G.foe.name)} pauses. ${spareable(G.foe) ? "It looks ready to stop." : "What now?"}</span>`);
  }
}

function moveSoul(dc, dr) {
  const c = D.soul.c + dc;
  const r = D.soul.r + dr;
  if (!inBox(c, r) || D.blocked.has(idx(c, r))) return;
  D.soul = { c, r };
}

function dead() {
  D = null;
  G.mode = "dead";
  sfx.play("death");
  say(`<span class="sys">You fall. ${esc(G.foe.name)} watches.</span>`);
  setMenu(
    [
      { label: "TRY THIS FIGHT AGAIN", run: () => { G.hp = G.maxHp; G.foe.hp = G.foe.maxHp; G.foe.turn = 0; G.foe.meters = { ...SPECIES[G.foe.species].start }; startEncounter(G.foe); } },
      { label: "NEW FLOOR", run: () => newRun() },
    ],
    `<kbd>ENTER</kbd> PICK`,
  );
}

function ending() {
  G.mode = "end";
  sfx.play("stairs");
  const { spared, slain, fled, recruited, left } = G.tally;
  const met = spared + slain;
  let route;
  let text;
  if (met === 0) {
    route = "THE GHOST ROUTE";
    text = "You slipped past everything. Nobody down here knows your name yet.";
  } else if (slain === 0) {
    route = "THE QUIET ROUTE";
    text = "Every monster you met is still alive, and some of them are following you down.";
  } else if (spared === 0) {
    route = "THE BLOOD ROUTE";
    text = "The halls go quiet behind you. On the next floor, the monsters will have heard.";
  } else {
    route = "THE TANGLED ROUTE";
    text = "Some you spared, some you didn't. The ones you spared saw what you did to the others.";
  }
  say(`<span class="who">${route}.</span> ${esc(text)}<br><span class="sys">Spared ${spared} · slain ${slain} · fled ${fled} · recruited ${recruited}${left ? ` · ${left} walked out on you` : ""}${G.allies.length ? ` · still with you: ${esc(G.allies.map((a) => a.name).join(", "))}` : ""}. In the full game the route carries into the next floor and the story's three acts.</span>`);
  setMenu([{ label: "NEW FLOOR", run: () => newRun() }], `<kbd>ENTER</kbd> PLAY AGAIN`);
}

// ---------------------------------------------------------------- drawing

function drawMonsterAhead(t) {
  const a = monsterAhead();
  if (!a) return;
  const z = a.d + 0.5;
  const s = scaleAt(z);
  const by = H / 2 + ((H - 8) / 2) * s;
  drawMonster(view, a.m.species, t, 0, { cx: W / 2, s: s * 0.9, by }, 1, { color: a.m.boss ? BOSS_COLOR : undefined });
  view.fillStyle = a.m.boss ? BOSS_COLOR : SPECIES[a.m.species].color;
  view.font = `8px ${PIX}`;
  view.textAlign = "center";
  view.fillText(a.m.boss ? "CHAMPION" : GENRES[a.m.genre].name, W / 2, by - 150 * s - 6);
  view.textAlign = "left";
}

function drawFoe(t, small) {
  const m = G.foe;
  const slot = small ? { cx: W / 2, s: 0.27, by: 76 } : { cx: W / 2, s: 0.85, by: 270 };
  const hurt = t < hurtUntil ? 1 : 0;
  drawMonster(view, m.species, t, hurt, slot, 1, { color: m.boss ? BOSS_COLOR : undefined });
  // name + health
  const spare = !m.gone && spareable(m);
  view.font = `8px ${PIX}`;
  view.fillStyle = spare ? "#ffd27a" : "#e8e8e8";
  view.fillText(m.name + (spare ? "  (SPAREABLE)" : ""), 12, 20);
  view.fillStyle = "#2e2e33";
  view.fillRect(12, 26, 120, 6);
  view.fillStyle = m.hp / m.maxHp < 0.4 ? "#ff5a4a" : "#9ed36b";
  view.fillRect(12, 26, (120 * m.hp) / m.maxHp, 6);
  view.fillStyle = "#8a8a8a";
  view.textAlign = "right";
  view.fillText(G.foe.boss ? `TURN ${m.turn + 1} · ${GENRES[foeGenre()].name}` : GENRES[m.genre].name, W - 12, 20);
  view.textAlign = "left";
}

function drawBox(t) {
  const accent = G.foe.boss ? BOSS_COLOR : SPECIES[G.foe.species].color;
  // frame, with the beat pulsing it in rhythm fights
  const pulse = D.pulse ? Math.max(0, 1 - (t - D.pulse) / 180) : 0;
  view.strokeStyle = "#e8e8e8";
  view.lineWidth = 2 + pulse * 3;
  view.strokeRect(BX - 3, BY - 3, COLS * CELL + 6, ROWS * CELL + 6);
  view.lineWidth = 1;
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++) {
      const k = idx(c, r);
      const x = BX + c * CELL;
      const y = BY + r * CELL;
      if (D.blocked.has(k)) {
        view.fillStyle = "#3a3a3a";
        view.fillRect(x + 2, y + 2, CELL - 4, CELL - 4);
        view.strokeStyle = "#a7a39b";
        view.strokeRect(x + 2.5, y + 2.5, CELL - 5, CELL - 5);
        continue;
      }
      view.strokeStyle = "#1c1c20";
      view.strokeRect(x + 0.5, y + 0.5, CELL, CELL);
    }
  // hazards: warning outlines, then filled when they land
  for (const h of D.hazards) {
    const live = t >= h.hit;
    const prog = clamp((t - h.warn) / (h.hit - h.warn), 0, 1);
    const color = h.kind === "light" ? "#fff3b0" : accent;
    for (const k of h.cells) {
      const x = BX + (k % COLS) * CELL;
      const y = BY + Math.floor(k / COLS) * CELL;
      if (live) {
        view.globalAlpha = 0.85;
        view.fillStyle = color;
        view.fillRect(x + 1, y + 1, CELL - 2, CELL - 2);
      } else {
        view.globalAlpha = 0.12 + 0.28 * prog;
        view.fillStyle = color;
        view.fillRect(x + 1, y + 1, CELL - 2, CELL - 2);
        view.globalAlpha = 0.5 + 0.5 * Math.abs(Math.sin(t / 90));
        view.strokeStyle = color;
        view.strokeRect(x + 3.5, y + 3.5, CELL - 7, CELL - 7);
      }
    }
    view.globalAlpha = 1;
    if (h.glyph) {
      const x = BX + (h.at % COLS) * CELL + CELL / 2;
      const y = BY + Math.floor(h.at / COLS) * CELL + CELL / 2;
      view.fillStyle = "#000";
      view.fillRect(x - 11, y - 11, 22, 22);
      view.fillStyle = "#ffffff";
      view.font = `12px ${PIX}`;
      view.textAlign = "center";
      view.textBaseline = "middle";
      view.fillText(h.glyph, x, y + 1);
      view.textAlign = "left";
      view.textBaseline = "alphabetic";
    }
    if (h.kind === "goo" && !live) {
      const x = BX + (h.at % COLS) * CELL + CELL / 2;
      const y0 = BY + Math.floor(h.at / COLS) * CELL + CELL / 2;
      view.fillStyle = accent;
      view.beginPath();
      view.arc(x, y0 - (1 - prog) * 70, 5, 0, 6.283);
      view.fill();
    }
  }
  // the lantern
  if (D.genre === "shadow") {
    const L = lanternAt(t - D.t0, D.intensity);
    const g = view.createRadialGradient(L.x, L.y, 2, L.x, L.y, 40);
    g.addColorStop(0, "rgba(255,243,176,0.9)");
    g.addColorStop(1, "rgba(255,243,176,0)");
    view.fillStyle = g;
    view.beginPath();
    view.arc(L.x, L.y, 40, 0, 6.283);
    view.fill();
    view.fillStyle = "#fff3b0";
    view.fillRect(L.x - 3, L.y - 5, 6, 10);
  }
  // you
  const sx = BX + D.soul.c * CELL + CELL / 2;
  const sy = BY + D.soul.r * CELL + CELL / 2;
  const blink = t < D.iframes && Math.floor(t / 70) % 2 === 0;
  if (!blink) {
    view.fillStyle = "#8fd3ff";
    view.beginPath();
    view.moveTo(sx, sy - 8);
    view.lineTo(sx + 8, sy);
    view.lineTo(sx, sy + 8);
    view.lineTo(sx - 8, sy);
    view.closePath();
    view.fill();
  }
  // your charms
  if (G.allies.length) {
    view.font = `7px ${PIX}`;
    view.fillStyle = "#8a8a8a";
    view.fillText("CHARMS", 12, BY + 8);
    G.allies.forEach((a, i) => {
      const used = a.species === "slime" && !D.shield;
      view.fillStyle = used ? "#3a3a3a" : SPECIES[a.species].color;
      view.fillText(CHARMS[a.species].name, 12, BY + 22 + i * 12);
    });
  }
  // time left
  const left = clamp((D.end - t) / (D.end - D.t0), 0, 1);
  view.fillStyle = "#2e2e33";
  view.fillRect(BX - 3, BY + ROWS * CELL + 8, COLS * CELL + 6, 3);
  view.fillStyle = "#8a8a8a";
  view.fillRect(BX - 3, BY + ROWS * CELL + 8, (COLS * CELL + 6) * left, 3);
}

function drawBar(t) {
  const x0 = 64;
  const w = W - 128;
  const y = 220;
  view.fillStyle = "#000";
  view.fillRect(x0 - 6, y - 16, w + 12, 40);
  view.strokeStyle = "#e8e8e8";
  view.lineWidth = 2;
  view.strokeRect(x0, y - 10, w, 28);
  view.fillStyle = "#3a3a3a";
  view.fillRect(x0 + w / 2 - 14, y - 9, 28, 26);
  view.fillStyle = "#ffd27a";
  view.fillRect(x0 + w / 2 - 2, y - 9, 4, 26);
  if (!bar) return;
  const x = clamp((t - bar.t0) / bar.dur, 0, 1);
  view.fillStyle = "#ffffff";
  view.fillRect(x0 + x * w - 2, y - 14, 4, 36);
  if (x >= 1) strike(t); // too late: a miss
}

let lastMap = 0;
function frame(t) {
  const shaking = t < G.shake;
  view.save();
  if (shaking) view.translate((Math.random() - 0.5) * 6, (Math.random() - 0.5) * 6);
  if (G.mode === "title") {
    drawTitle(view, t, "PRESS ANY KEY");
    view.fillStyle = "#8fd3ff";
    view.font = `8px ${PIX}`;
    view.textAlign = "center";
    view.fillText("GENRE HALLS · PITCH DEMO", W / 2, H * 0.55);
    view.textAlign = "left";
  } else if (G.mode === "explore" || G.mode === "end") {
    const seen = drawCorridor(view, G.map, G.x, G.y, G.dir, t);
    for (const [x, y] of seen) G.seen.add(y * G.map.n + x);
    drawMonsterAhead(t);
  } else if (G.foe) {
    clear(view);
    if (G.mode === "dodge" && D) {
      updateDodge(t);
      if (D) {
        drawFoe(t, true);
        drawBox(t);
      } else drawFoe(t, false);
    } else {
      drawFoe(t, false);
      if (G.mode === "fightbar") drawBar(t);
      if (G.mode === "intro") {
        const a = clamp((introUntil - t) / 700, 0, 1);
        view.fillStyle = `rgba(255,255,255,${a * 0.5})`;
        view.fillRect(0, 0, W, H);
      }
    }
    if (D && t - (D.blockFlash ?? -1e9) < 160) {
      view.fillStyle = "rgba(143,211,255,0.22)";
      view.fillRect(0, 0, W, H);
      view.fillStyle = "#8fd3ff";
      view.font = `8px ${PIX}`;
      view.textAlign = "center";
      view.fillText("BOUNCY! THE SLIME TAKES THE HIT", W / 2, BY - 8);
      view.textAlign = "left";
    }
    if (D && t - D.hitFlash < 120) {
      view.fillStyle = "rgba(255,90,74,0.25)";
      view.fillRect(0, 0, W, H);
    }
  }
  view.restore();
  if (G.map && t - lastMap > 100) {
    lastMap = t;
    drawMap(mapCtx, G.map, G.seen, G.visited, G.x, G.y, G.dir);
    const s = Math.floor(105 / G.map.n);
    for (const m of G.map.monsters) {
      if (m.gone || m.boss || !G.seen.has(m.y * G.map.n + m.x)) continue;
      mapCtx.fillStyle = SPECIES[m.species].color;
      mapCtx.fillRect(m.x * s + 2, m.y * s + 2, s - 4, s - 4);
    }
  }
  requestAnimationFrame(frame);
}

// ---------------------------------------------------------------- input

const KEYMAP = { w: "ArrowUp", s: "ArrowDown", a: "ArrowLeft", d: "ArrowRight", " ": "Enter", z: "Enter", x: "Escape" };
function onKey(key) {
  sfx.init();
  key = KEYMAP[key] ?? KEYMAP[key?.toLowerCase?.()] ?? key;
  const now = performance.now();
  if (G.mode === "title") return newRun();
  if (G.mode === "explore") {
    if (key === "ArrowUp") step(1);
    else if (key === "ArrowDown") step(-1);
    else if (key === "ArrowLeft") G.dir = (G.dir + 3) % 4;
    else if (key === "ArrowRight") G.dir = (G.dir + 1) % 4;
    return;
  }
  if (G.mode === "dodge" && D) {
    if (key === "ArrowUp") moveSoul(0, -1);
    else if (key === "ArrowDown") moveSoul(0, 1);
    else if (key === "ArrowLeft") moveSoul(-1, 0);
    else if (key === "ArrowRight") moveSoul(1, 0);
    return;
  }
  if (G.mode === "fightbar") {
    if (key === "Enter" && bar) strike(now);
    return;
  }
  if (["menu", "act", "result", "dead", "end"].includes(G.mode)) {
    if (key === "ArrowUp" || key === "ArrowLeft") moveSel(-1);
    else if (key === "ArrowDown" || key === "ArrowRight") moveSel(1);
    else if (key === "Enter") G.menu[G.sel]?.run();
    else if (key === "Escape" && G.mode === "act") mainMenu();
    else if (/^[1-9]$/.test(key) && G.menu[Number(key) - 1]) {
      G.sel = Number(key) - 1;
      G.menu[G.sel].run();
    }
  }
}
addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " "].includes(e.key)) e.preventDefault();
  if (e.repeat && G.mode !== "dodge" && G.mode !== "explore") return;
  if (e.target?.id === "talk-in") return;
  if (document.activeElement?.closest?.("#menu") && e.key === "Enter") e.preventDefault();
  onKey(e.key);
});
document.querySelectorAll(".pad button").forEach((b) => b.addEventListener("pointerdown", (e) => {
  e.preventDefault();
  onKey(b.dataset.key);
}));
document.getElementById("view").addEventListener("pointerdown", () => onKey("Enter"));

renderParty();
say(`<span class="sys">DONJON's dungeon, with Undertale-style encounters: every faction attacks in its own genre. Press any key or tap the view to start.</span>`);
setMenu([], `<kbd>ANY KEY</kbd> START`);
document.fonts?.ready.finally(() => requestAnimationFrame(frame));
if (!document.fonts) requestAnimationFrame(frame);

// Console hook for playtesting: genreHalls.meet("rock") jumps straight into that faction's fight.
globalThis.genreHalls = {
  G,
  readWords,
  meet(species = "bandit") {
    if (!G.map) newRun();
    const m = G.map.monsters.find((x) => x.species === species && !x.gone);
    if (m) startEncounter(m);
  },
};
