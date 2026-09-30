import { SPECIES } from "./species.js";
import { DIRS, DIR_NAMES, drawCorridor, drawMap, drawTitle, clear } from "./render.js";
import { drawMonster } from "./art.js";
import { Music } from "./music.js";

const $ = (s) => document.querySelector(s);
const view = $("#view").getContext("2d");
const mapCtx = $("#map").getContext("2d");
const music = new Music();

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

// ---------------------------------------------------------------- state

let G;
let uid = 0;

function newRun() {
  G = {
    mode: "explore",
    floor: 1,
    party: [
      human("ARNOLD", "G-FIG", 14, 8, [2, 7]),
      human("ROLF", "G-FIG", 13, 8, [2, 7]),
      { ...human("HOUDINI", "N-MAG", 8, 10, [1, 3]), mp: 3, maxMp: 3 },
    ],
    gold: 30,
    xp: 0,
    level: 1,
    combat: null,
    prompt: null,
    input: null,
    graceSteps: 4,
    log: [],
  };
  enterFloor(1);
  say("You descend into the Halls of Jev. The monsters here listen, if you talk to them.", "dim");
  say("MOVE: ARROWS/WASD  C: CAMP  M: MAP  J: JEV MIND  P: MUSIC", "dim");
  render();
}

function human(name, cls, hp, ac, dmg) {
  return { id: `h${uid++}`, name, kind: "human", cls, hp, maxHp: hp, ac, dmg, dead: false };
}

// ---------------------------------------------------------------- dungeon generation

function genFloor(floor) {
  const N = 21;
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
  for (let i = 0; i < 28; i++) {
    const x = rnd(1, N - 2);
    const y = rnd(1, N - 2);
    if (grid[y][x]) continue;
    if ((grid[y][x - 1] && grid[y][x + 1]) || (grid[y - 1][x] && grid[y + 1][x])) grid[y][x] = 1;
  }
  for (let r = 0; r < 3; r++) {
    const x = rnd(1, N - 5) | 1;
    const y = rnd(1, N - 5) | 1;
    for (let yy = y; yy < y + 3; yy++) for (let xx = x; xx < x + 3; xx++) grid[yy][xx] = 1;
  }
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
        if (dist.get(k) > dist.get(`${far[0]},${far[1]}`)) far = [x + dx, y + dy];
      }
    }
  }
  const floors = [...dist.keys()].map((k) => k.split(",").map(Number));
  const gold = new Set();
  while (gold.size < 5) {
    const [x, y] = pick(floors);
    if ((x !== 1 || y !== 1) && (x !== far[0] || y !== far[1])) gold.add(y * N + x);
  }
  return { grid, stairs: { x: far[0], y: far[1] }, gold, floor };
}

function enterFloor(n) {
  G.floor = n;
  G.map = genFloor(n);
  G.x = 1;
  G.y = 1;
  G.dir = DIRS.findIndex(([dx, dy]) => G.map.grid[1 + dy]?.[1 + dx] === 1);
  G.seen = new Set();
  G.visited = new Set([1 * 21 + 1]);
  const best = Number(store.get("hallsOfJev.deepest") || 0);
  if (n > best) store.set("hallsOfJev.deepest", String(n));
}

// ---------------------------------------------------------------- log + rendering

function say(text, cls = "", color) {
  G.log.push({ text, cls, color });
  if (G.log.length > 120) G.log.shift();
}

const living = () => G.party.filter((m) => !m.dead);
const humansAlive = () => G.party.some((m) => m.kind === "human" && !m.dead);

let hurtUntil = 0;
function render() {
  if (!G) return;
  const t = performance.now();
  if (G.combat) {
    clear(view);
    drawMonster(view, G.combat.enemy.species, t, t < hurtUntil ? 1 : 0);
  } else {
    const seen = drawCorridor(view, G.map, G.x, G.y, G.dir);
    for (const [x, y] of seen) G.seen.add(y * 21 + x);
  }
  drawMap(mapCtx, G.map, G.seen, G.visited, G.x, G.y, G.dir);
  renderBar();
  renderLog();
  renderParty();
  renderButtons();
}

function renderBar() {
  let cmds;
  if (G.mode === "over") cmds = "ENTER) NEW RUN";
  else if (G.prompt) cmds = `${G.prompt.text}  Y)ES  N)O`;
  else if (G.input) cmds = G.input.label;
  else if (G.combat) cmds = G.combat.busy ? "..." : `F)IGHT C)AST T)ALK G)IVE R)UN`;
  else cmds = "C)AMP M)AP J)EV P)MUSIC";
  $("#cmds").textContent = cmds;
  $("#where").textContent = `B${G.floor}F  ${DIR_NAMES[G.dir]}  GOLD ${G.gold}`;
}

function renderLog() {
  const el = $("#log");
  el.innerHTML = G.log
    .slice(-40)
    .map((l) => `<p class="${l.cls}"${l.color ? ` style="color:${l.color}"` : ""}>${esc(l.text)}</p>`)
    .join("");
  el.scrollTop = el.scrollHeight;
}

function moodWord(m) {
  if (m.kind === "human") return m.dead ? "DEAD" : "OK";
  const l = m.loyalty;
  return l >= 75 ? "DEVOTED" : l >= 50 ? "CONTENT" : l >= 30 ? "UNEASY" : l >= 15 ? "RESENTS" : "LEAVING?";
}

function renderParty() {
  $("#party tbody").innerHTML = G.party
    .map(
      (m, i) =>
        `<tr class="${m.dead ? "dead" : ""}"${m.kind === "monster" ? ` style="color:${SPECIES[m.species].color}"` : ""}><td>${i + 1}</td><td>${esc(m.name)}</td><td>${m.cls}</td><td>${m.ac}</td><td>${m.hp}/${m.maxHp}</td><td>${moodWord(m)}${m.mp !== undefined ? ` MP${m.mp}` : ""}</td></tr>`,
    )
    .join("");
  $("#lvl").textContent = `LVL ${G.level}  XP ${G.xp}/${xpNeeded()}`;
}

const BUTTONS = {
  explore: [["↰", "turnL"], ["↑", "fwd"], ["↱", "turnR"], ["↓", "back"], ["CAMP", "c"], ["MAP", "m"], ["♪", "p"]],
  combat: [["FIGHT", "f"], ["CAST", "c"], ["TALK", "t"], ["GIVE", "g"], ["RUN", "r"]],
  prompt: [["YES", "y"], ["NO", "n"]],
  over: [["NEW RUN", "enter"]],
};
function renderButtons() {
  const set = G.mode === "over" ? "over" : G.prompt ? "prompt" : G.input ? null : G.combat ? "combat" : "explore";
  $("#buttons").innerHTML = set ? BUTTONS[set].map(([l, k]) => `<button data-key="${k}">${l}</button>`).join("") : "";
}

// ---------------------------------------------------------------- exploring

function step(dir) {
  const [dx, dy] = DIRS[dir];
  const nx = G.x + dx;
  const ny = G.y + dy;
  if (G.map.grid[ny]?.[nx] !== 1) {
    say("OUCH! A WALL.", "dim");
    return render();
  }
  G.x = nx;
  G.y = ny;
  const k = ny * 21 + nx;
  G.visited.add(k);
  if (G.map.gold.delete(k)) {
    const g = rnd(3, 10) * G.floor;
    G.gold += g;
    say(`YOU FIND ${g} GOLD.`);
  }
  if (nx === G.map.stairs.x && ny === G.map.stairs.y) {
    G.prompt = { text: "STAIRS DOWN. DESCEND?", yes: descend, no: () => render() };
    return render();
  }
  if (--G.graceSteps <= 0 && Math.random() < 0.07 + G.floor * 0.012) return encounter();
  render();
}

function descend() {
  enterFloor(G.floor + 1);
  G.graceSteps = 4;
  say(`YOU DESCEND TO B${G.floor}F. IT GROWS COLDER.`);
  render();
}

function camp() {
  for (const m of living()) m.hp = Math.min(m.maxHp, m.hp + Math.ceil(m.maxHp / 2));
  for (const m of G.party) if (m.maxMp && !m.dead) m.mp = m.maxMp;
  say("THE PARTY RESTS. WOUNDS CLOSE, HOUDINI'S MIND CLEARS.");
  if (Math.random() < 0.25) {
    say("...SOMETHING FINDS YOUR CAMP!", "warn");
    return encounter();
  }
  render();
}

// ---------------------------------------------------------------- encounters & combat

function speciesForFloor(f) {
  const table = f === 1 ? { slime: 65, goblin: 35 } : f === 2 ? { slime: 45, goblin: 43, dragon: 12 } : { slime: 30, goblin: 45, dragon: 25 };
  let r = Math.random() * 100;
  for (const [s, w] of Object.entries(table)) if ((r -= w) < 0) return s;
  return "slime";
}

function makeEnemy(species) {
  const sp = SPECIES[species];
  const scale = 1 + 0.2 * (G.floor - 1);
  const hp = Math.round(rnd(...sp.hp) * scale);
  const kin = living().some((m) => m.kind === "monster" && m.species === species);
  const traits = [...sp.traits].sort(() => Math.random() - 0.5).slice(0, 2);
  return {
    species,
    name: pick(sp.names),
    traits,
    hp,
    maxHp: hp,
    ac: sp.ac,
    dmg: sp.dmg.map((d) => Math.round(d * scale)),
    meters: { ...sp.start, friendliness: sp.start.friendliness + (kin ? 15 : 0) },
    specialReady: true,
    cooldown: 0,
    paid: false,
    demanded: false,
    impressions: kin ? ["One of your own kind travels with this party."] : [],
    formerAlly: false,
  };
}

function encounter(enemy = makeEnemy(speciesForFloor(G.floor))) {
  const sp = SPECIES[enemy.species];
  G.combat = { enemy, round: 0, conversation: [], busy: false, history: [], rounds: 0, lastLine: "", lastAction: "" };
  G.mode = "combat";
  G.graceSteps = 5;
  const article = /^[aeiou]/.test(sp.label) ? "AN" : "A";
  say(enemy.formerAlly ? `${enemy.name} TURNS ON YOU!` : `${article} ${sp.label.toUpperCase()} APPEARS!`, "big", sp.color);
  if (!enemy.formerAlly) say(`IT IS ${enemy.name.toUpperCase()}, ${enemy.traits.join(" AND ").toUpperCase()}.`, "dim");
  history(`The party met ${enemy.name}, a ${sp.label}${enemy.formerAlly ? " who had just turned on them" : ""}.`);
  render();
  enemyTurn({ type: "start" }, ["The party just came face to face with you in a dungeon corridor."], {});
}

function history(text) {
  const h = G.combat.history;
  if (h[h.length - 1] !== text) h.push(text);
}

function hitChance(ac, bonus = 0) {
  return Math.min(0.95, Math.max(0.15, 0.5 + (ac - 5) * 0.05 + bonus));
}

// The party swings (and HOUDINI casts if asked). Returns per-member notes for the enemy's view.
function partyAttack(cast) {
  const e = G.combat.enemy;
  const did = {};
  const out = [];
  for (const m of living()) {
    if (m.kind === "monster" && m.species === e.species) {
      did[m.id] = "refused to fight one of its own kind";
      out.push(`${m.name} WON'T ATTACK ITS OWN KIND.`);
      continue;
    }
    if (cast && m.cls === "N-MAG" && m.mp > 0) {
      m.mp--;
      const d = rnd(3, 9) + G.level;
      e.hp -= d;
      did[m.id] = `cast a fire spell on you for ${d} damage`;
      out.push(`${m.name} CASTS HALITO! ${d} DAMAGE.`);
      continue;
    }
    if (Math.random() < hitChance(e.ac, G.level * 0.02)) {
      let d = rnd(...m.dmg) + (m.kind === "human" ? G.level - 1 : 0);
      if (e.defending) d = Math.max(1, Math.floor(d / 2));
      e.hp -= d;
      did[m.id] = `hit you for ${d}`;
      out.push(`${m.name} HITS FOR ${d}.`);
    } else {
      did[m.id] = "swung at you and missed";
      out.push(`${m.name} MISSES.`);
    }
  }
  e.defending = false;
  if (out.length) say(out.join(" "));
  hurtUntil = performance.now() + 300;
  return did;
}

function command(cmd) {
  const c = G.combat;
  if (!c || c.busy) return;
  if (cmd === "f" || cmd === "c") {
    const cast = cmd === "c";
    if (cast && !living().some((m) => m.cls === "N-MAG" && m.mp > 0)) {
      say("NO ONE CAN CAST RIGHT NOW.", "dim");
      return render();
    }
    const did = partyAttack(cast);
    c.rounds++;
    // One running line for the fight, not one per round
    const line = `The party attacked ${c.enemy.name}${c.rounds > 1 ? ` for ${c.rounds} rounds` : ""}.`;
    const at = c.history.findIndex((h) => h.startsWith(`The party attacked ${c.enemy.name}`));
    if (at >= 0) c.history[at] = line;
    else history(line);
    if (c.enemy.hp <= 0) return victory();
    return enemyTurn({ type: cast ? "cast" : "fight" }, [cast ? "The party attacked you, and their mage cast a fire spell." : "The whole party attacked you."], did);
  }
  if (cmd === "t") {
    G.input = {
      label: "WHAT DO YOU SAY?",
      submit: (text) => {
        say(`YOU: "${text}"`, "you");
        history(`The party said to ${c.enemy.name}: "${text}"`);
        enemyTurn({ type: "talk", message: text }, ["The party spoke to you."], { [leader().id]: "spoke to you on behalf of the party" });
      },
    };
    return openInput();
  }
  if (cmd === "g") {
    if (G.gold <= 0) {
      say("YOU HAVE NO GOLD.", "dim");
      return render();
    }
    G.input = {
      label: `GIVE HOW MUCH GOLD? (HAVE ${G.gold})`,
      numeric: true,
      submit: (text) => {
        const gold = Math.min(G.gold, Math.max(0, Math.floor(Number(text) || 0)));
        if (!gold) return render();
        say(`YOU OFFER ${gold} GOLD.`, "you");
        history(`The party offered ${c.enemy.name} ${gold} gold.`);
        enemyTurn({ type: "give", gold }, [`The party offered you ${gold} gold.`], { [leader().id]: `held out ${gold} gold to you` });
      },
    };
    return openInput();
  }
  if (cmd === "r") {
    const chance = c.enemy.species === "dragon" ? 0.4 : 0.6;
    if (Math.random() < chance) {
      say("YOU FLEE!");
      history(`The party ran away from ${c.enemy.name}.`);
      return endCombat();
    }
    say("YOU CAN'T GET AWAY!", "warn");
    return enemyTurn({ type: "run_failed" }, ["The party tried to run away from you, but failed."], {});
  }
}

const leader = () => living().find((m) => m.kind === "human") ?? living()[0];

async function enemyTurn(playerAction, events, did) {
  const c = G.combat;
  const e = c.enemy;
  c.busy = true;
  c.round++;
  render();
  const body = {
    enemy: {
      species: e.species,
      name: e.name,
      traits: e.traits,
      hp: Math.max(0, e.hp),
      maxHp: e.maxHp,
      meters: e.meters,
      specialReady: e.cooldown <= 0,
      paid: e.paid,
      demanded: e.demanded,
      impressions: e.impressions,
      formerAlly: e.formerAlly,
    },
    party: G.party.map((m) => ({
      id: m.id,
      name: m.name,
      kind: m.kind,
      species: m.species,
      cls: m.cls,
      hp: m.hp,
      maxHp: m.maxHp,
      dead: m.dead,
      didThisRound: did[m.id],
    })),
    round: c.round,
    playerAction,
    events,
    conversation: c.conversation,
    partyGold: G.gold,
  };
  let r;
  try {
    r = await api("/api/enemy-turn", body);
  } catch (err) {
    say(`(JEV UNREACHABLE: ${err.message}. ${e.name} HESITATES.)`, "dim");
    c.busy = false;
    return render();
  }
  if (playerAction.message) c.conversation.push({ speaker: "Party", text: playerAction.message });
  c.conversation.push({ speaker: e.name, text: r.line });
  e.meters = r.meters;
  e.impressions = r.impressions;
  c.lastLine = r.line;
  c.lastAction = r.action;
  showJev({ kind: "enemy", enemy: e, r });
  const color = SPECIES[e.species].color;
  say(`${e.name.toUpperCase()}: ${r.line}`, "npc", color);
  if (e.cooldown > 0) e.cooldown--;
  c.busy = false;
  applyEnemyAction(r);
}

function damage(m, d) {
  m.hp = Math.max(0, m.hp - d);
  if (m.hp === 0) {
    m.dead = true;
    say(`${m.name} ${m.kind === "human" ? "IS KILLED!" : "COLLAPSES!"}`, "warn");
    history(`${m.name} died.`);
    if (m.kind === "monster") G.party = G.party.filter((x) => x !== m);
  }
}

function applyEnemyAction(r) {
  const c = G.combat;
  const e = c.enemy;
  const sp = SPECIES[e.species];
  const target = G.party.find((m) => m.id === r.targetId && !m.dead) ?? leader();
  switch (r.action) {
    case "attack":
      if (target && Math.random() < hitChance(target.ac)) {
        const d = rnd(...e.dmg);
        say(`${e.name.toUpperCase()} HITS ${target.name} FOR ${d}.`, "warn");
        damage(target, d);
      } else if (target) say(`${e.name.toUpperCase()} MISSES ${target.name}.`, "dim");
      break;
    case "special": {
      e.cooldown = 3;
      const victims = sp.special.all ? living() : [target];
      for (const v of victims) {
        const d = rnd(...sp.special.dmg.map((x) => Math.round(x * (1 + 0.2 * (G.floor - 1)))));
        say(`${v.name} TAKES ${d}!`, "warn");
        damage(v, d);
      }
      break;
    }
    case "defend":
      e.defending = true;
      break;
    case "demand_tribute":
      e.demanded = true;
      break;
    case "accept_tribute":
      G.gold -= r.offer;
      e.paid = true;
      say(`${e.name.toUpperCase()} TAKES ${r.offer} GOLD.`);
      history(`The party paid ${e.name} ${r.offer} gold, and it accepted.`);
      break;
    case "refuse_tribute":
      history(`${e.name} refused the party's gold.`);
      break;
    case "flee":
      say(`${e.name.toUpperCase()} FLEES.`);
      history(`${e.name} fled from the party.`);
      return endCombat();
    case "leave_peacefully":
      say(`${e.name.toUpperCase()} LETS YOU PASS.`);
      history(`${e.name} and the party parted peacefully.`);
      return endCombat();
    case "join_party":
      if (G.party.length >= 6) {
        say("...BUT YOUR PARTY IS FULL.", "dim");
        break;
      }
      G.prompt = {
        text: `${e.name.toUpperCase()} WANTS TO JOIN. ACCEPT?`,
        yes: () => recruit(e),
        no: () => {
          say(`YOU TURN ${e.name.toUpperCase()} AWAY. IT WANDERS OFF.`);
          history(`${e.name} offered to join, but the party turned it away.`);
          endCombat();
        },
      };
      break;
  }
  if (!humansAlive()) return gameOver();
  render();
}

function recruit(e) {
  const sp = SPECIES[e.species];
  const ally = {
    id: `m${uid++}`,
    name: e.name.toUpperCase(),
    kind: "monster",
    species: e.species,
    cls: sp.cls,
    hp: Math.max(1, e.hp),
    maxHp: e.maxHp,
    ac: e.ac,
    dmg: e.dmg,
    traits: e.traits,
    loyalty: Math.min(80, 50 + Math.round((e.meters.friendliness - sp.joinThreshold) / 2)),
    dead: false,
  };
  G.party.push(ally);
  say(`${ally.name} JOINS THE PARTY!`, "big", sp.color);
  history(`The party befriended ${e.name}, who joined them.`);
  G.combat.recruitId = ally.id;
  endCombat();
}

function xpNeeded() {
  return 60 * G.level;
}

function victory() {
  const c = G.combat;
  const e = c.enemy;
  const sp = SPECIES[e.species];
  const gold = Math.round(rnd(...sp.gold) * (1 + 0.2 * (G.floor - 1)));
  const xp = Math.round(sp.xp * (1 + 0.2 * (G.floor - 1)));
  G.gold += gold;
  G.xp += xp;
  say(`${e.name.toUpperCase()} IS SLAIN! +${xp} XP, +${gold} GOLD.`, "big", sp.color);
  history(`The party killed ${e.name}, the ${sp.label}, and took ${gold} gold.${c.lastLine ? ` Its last words were: "${c.lastLine}"` : ""}`);
  while (G.xp >= xpNeeded()) {
    G.xp -= xpNeeded();
    G.level++;
    for (const m of living()) {
      m.maxHp += m.kind === "human" ? 3 : 2;
      m.hp = m.maxHp;
    }
    say(`THE PARTY REACHES LEVEL ${G.level}!`, "big");
  }
  endCombat();
}

async function endCombat() {
  const c = G.combat;
  G.combat = null;
  G.mode = "explore";
  render();
  const allies = G.party.filter((m) => m.kind === "monster" && !m.dead && m.id !== c.recruitId);
  if (!allies.length || c.history.length < 2) return;
  G.mode = "busy";
  G.combat = null;
  let r;
  try {
    r = await api("/api/ally-reactions", {
      allies: allies.map((a) => ({ id: a.id, species: a.species, name: a.name, traits: a.traits, loyalty: a.loyalty })),
      events: c.history,
    });
  } catch (err) {
    say(`(JEV UNREACHABLE: ${err.message})`, "dim");
    G.mode = "explore";
    return render();
  }
  G.mode = "explore";
  showJev({ kind: "allies", r, events: c.history });
  let traitor = null;
  for (const x of r.reactions) {
    const m = G.party.find((p) => p.id === x.id);
    if (!m) continue;
    m.loyalty = x.loyalty;
    const color = SPECIES[m.species].color;
    say(`${m.name}: ${x.line}`, "npc", color);
    if (x.decision === "leave_party") {
      G.party = G.party.filter((p) => p !== m);
      say(`${m.name} LEAVES THE PARTY.`, "warn", color);
    } else if (x.decision === "turn_on_party" && !traitor) {
      G.party = G.party.filter((p) => p !== m);
      traitor = m;
    }
  }
  render();
  if (traitor) {
    const sp = SPECIES[traitor.species];
    setTimeout(
      () =>
        encounter({
          species: traitor.species,
          name: traitor.name,
          traits: traitor.traits,
          hp: traitor.hp,
          maxHp: traitor.maxHp,
          ac: traitor.ac,
          dmg: traitor.dmg,
          meters: { friendliness: 5, anger: 70, fear: 5 },
          specialReady: true,
          cooldown: 0,
          paid: true,
          demanded: false,
          impressions: [`You traveled with this party and grew to despise how they act. You just turned on them.`],
          formerAlly: true,
          color: sp.color,
        }),
      700,
    );
  }
}

function gameOver() {
  G.mode = "over";
  G.combat = null;
  say(`YOUR PARTY HAS PERISHED ON B${G.floor}F.`, "big");
  say(`DEEPEST FLOOR EVER REACHED: B${store.get("hallsOfJev.deepest") || G.floor}F. PRESS ENTER FOR A NEW RUN.`, "dim");
  render();
}

// ---------------------------------------------------------------- Jev mind panel

function bar(v, max = 1) {
  return `<span class="meter"><span style="width:${Math.max(0, Math.min(1, v / max)) * 100}%"></span></span>`;
}

function showJev(x) {
  const el = $("#jevBody");
  if (x.kind === "enemy") {
    const { enemy: e, r } = x;
    let h = `<p class="meta">${r.questionCount} QUESTIONS · ${r.ms} MS · ${r.inputTokens} TOKENS</p>`;
    h += `<h3 style="color:${SPECIES[e.species].color}">${esc(e.name.toUpperCase())}'S MOOD</h3><div class="rows">`;
    for (const k of ["friendliness", "anger", "fear"]) h += `<span>${k.toUpperCase()}</span>${bar(r.meters[k], 100)}<span>${r.meters[k]}</span>`;
    h += `</div>`;
    if (r.perception.length) {
      h += `<h3>WHAT IT HEARD</h3><div class="rows">`;
      for (const p of r.perception) h += `<span>${esc(p.label.toUpperCase())}</span>${bar(p.value, p.max ?? 1)}<span>${p.value.toFixed(2)}</span>`;
      h += `</div>`;
    }
    h += `<h3>ACTION · CONF ${r.confidence.toFixed(2)}</h3><div class="rows">`;
    for (const p of r.probabilities) h += `<span class="${p.id === r.picked ? "hot" : ""}">${p.id.replaceAll("_", " ").toUpperCase()}</span>${bar(p.p)}<span>${Math.round(p.p * 100)}%</span>`;
    h += `</div>`;
    if (r.blocked) h += `<p class="blocked">CODE BLOCKED ${r.picked.toUpperCase()}: ${esc(r.blocked)} → ${r.action.toUpperCase()}</p>`;
    if (r.targetProbabilities) {
      h += `<h3>TARGET</h3><div class="rows">`;
      for (const [id, p] of Object.entries(r.targetProbabilities).sort((a, b) => b[1] - a[1])) {
        const m = G.party.find((q) => q.id === id);
        h += `<span class="${id === r.targetId ? "hot" : ""}">${esc(m?.name ?? id)}</span>${bar(p)}<span>${Math.round(p * 100)}%</span>`;
      }
      h += `</div>`;
    }
    el.innerHTML = h;
  } else {
    const { r, events } = x;
    let h = `<p class="meta">ALLY CHECK · ${r.questionCount} QUESTIONS · ${r.ms} MS</p><h3>WHAT THEY SAW</h3><ul>${events.map((e) => `<li>${esc(e)}</li>`).join("")}</ul>`;
    for (const a of r.reactions) {
      h += `<h3>${esc(a.name)}</h3><div class="rows"><span>APPROVAL 0–4</span>${bar(a.approval, 4)}<span>${a.approval.toFixed(1)}</span><span>LOYALTY ${a.delta >= 0 ? "+" : ""}${a.delta}</span>${bar(a.loyalty, 100)}<span>${a.loyalty}</span></div>`;
      h += `<p class="meta">DECISION: ${a.decision.replaceAll("_", " ").toUpperCase()}${a.picked !== "stay" && a.picked !== a.decision ? ` (JEV SAID ${a.picked.replaceAll("_", " ").toUpperCase()})` : ""}</p>`;
      if (a.blocked) h += `<p class="blocked">${esc(a.blocked)}</p>`;
    }
    el.innerHTML = h;
  }
}

// ---------------------------------------------------------------- input

function openInput() {
  const row = $("#inputRow");
  const box = $("#text");
  row.hidden = false;
  $("#inputLabel").textContent = G.input.label;
  box.value = "";
  box.inputMode = G.input.numeric ? "numeric" : "text";
  render();
  box.focus();
}

function closeInput() {
  G.input = null;
  $("#inputRow").hidden = true;
  $("#text").blur();
}

$("#inputForm").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const text = $("#text").value.trim().slice(0, 240);
  const inp = G.input;
  closeInput();
  if (text && inp) inp.submit(text);
  else render();
});

function key(k) {
  if (!G) return;
  if (G.mode === "over") {
    if (k === "enter") newRun();
    return;
  }
  if (G.mode === "busy" || G.input) return;
  if (G.prompt) {
    if (k === "y" || k === "n") {
      const p = G.prompt;
      G.prompt = null;
      (k === "y" ? p.yes : p.no)();
    }
    return;
  }
  if (k === "j") return toggleJev();
  if (k === "p") return music.toggle();
  if (G.combat) return command(k);
  if (k === "m") {
    $("#map").classList.toggle("hidden");
    return;
  }
  if (k === "c") return camp();
  if (k === "fwd") return step(G.dir);
  if (k === "back") return step((G.dir + 2) % 4);
  if (k === "turnL") G.dir = (G.dir + 3) % 4;
  if (k === "turnR") G.dir = (G.dir + 1) % 4;
  render();
}

function toggleJev() {
  const hidden = $("#jev").classList.toggle("hidden");
  store.set("hallsOfJev.jev", hidden ? "0" : "1");
}
if (store.get("hallsOfJev.jev") === "0") $("#jev").classList.add("hidden");

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
  music.start().catch((err) => console.warn("music:", err));
  newRun();
}

document.addEventListener("keydown", (ev) => {
  if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
  if (ev.target === $("#text")) {
    if (ev.key === "Escape") {
      closeInput();
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
  if (KEYMAP[k] || k.length === 1 || k === "enter") ev.preventDefault();
  key(mapped);
});

$("#buttons").addEventListener("click", (ev) => {
  const k = ev.target.closest("button")?.dataset.key;
  if (k) key(k);
});
$("#view").addEventListener("click", () => start());

// Title card, then a light animation loop (monsters wobble, the title blinks)
function frame() {
  if (!G) drawTitle(view, performance.now());
  else if (G?.combat) {
    clear(view);
    drawMonster(view, G.combat.enemy.species, performance.now(), performance.now() < hurtUntil ? 1 : 0);
  }
  requestAnimationFrame(frame);
}
document.fonts?.ready.then(() => requestAnimationFrame(frame)) ?? requestAnimationFrame(frame);

// Debug hook: open with #debug, then e.g. halls.meet("dragon") in the console.
if (location.hash === "#debug") window.halls = { meet: (s) => encounter(makeEnemy(s)), state: () => G, music };
