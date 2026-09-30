// Deterministic world rules: map, movement, items, combat. No AI in here.

// . grass  = road  , city street  # wall  G gate  T tree  ~ water  H house
export const MAP = [
  "HH,HH,,,,,HH,HH",
  ",,,,,,,,,,,,,,,",
  "#######G#######",
  "..T....=.......",
  ".......=....T..",
  "~~.....=.......",
  "~~~..T.=.......",
  "~~.....=...T...",
  ".......=.......",
  "..T....=.....T.",
  ".......=.......",
];
export const W = MAP[0].length;
export const H = MAP.length;

export const GATE = { x: 7, y: 2 };
export const POST = { x: 6, y: 3 };
export const PATROL = [{ x: 3, y: 3 }, { x: 11, y: 3 }];
export const TOLL = 10;
export const SIGHT = 6; // Jimbo notices you within this many steps
export const HEARING = 5; // and hears you within this many

export const ITEMS = {
  pouch: { name: "coin pouch", emoji: "💰", desc: "A small leather pouch with 12 gold coins inside.", gold: 12 },
  sword: { name: "rusty sword", emoji: "🗡️", desc: "Pitted with rust, but it would still hurt." },
  writ: {
    name: "travel writ",
    emoji: "📜",
    desc: "“Let the bearer, TOMAS REED, spice merchant of Low Harrow, pass freely into Ashvale.” Sealed by the Harbor Office.",
    bearer: "Tomas Reed, spice merchant of Low Harrow",
  },
  flowers: { name: "wildflowers", emoji: "💐", desc: "Blue cornflowers and yellow tansy, freshly picked." },
  ring: { name: "silver ring", emoji: "💍", desc: "Heavy silver. Worth well more than ten gold." },
};

export function newWorld() {
  return {
    turn: 0,
    gateOpen: false,
    tollPaid: false,
    writ: "none", // none | presented | accepted | rejected
    alarm: null, // turns until the watch arrives
    over: null,
    player: { x: 7, y: 10, hp: 10, maxHp: 10, gold: 3, inventory: [], swordDrawn: false, lastAttackTurn: -99 },
    guard: {
      x: POST.x,
      y: POST.y,
      hp: 14,
      maxHp: 14,
      patrolIndex: 1,
      trust: 20,
      suspicion: 15,
      anger: 0,
      impressions: [],
      warnings: 0,
      lastAction: null,
      yielded: false,
    },
    ground: [
      { id: "pouch", x: 1, y: 8 },
      { id: "sword", x: 13, y: 6 },
      { id: "writ", x: 3, y: 9 },
      { id: "flowers", x: 1, y: 3 },
      { id: "ring", x: 11, y: 8 },
    ],
    pendingOffer: null,
    conversation: [], // { speaker: "Traveler" | "Jimbo", text }
    log: [], // { kind, text } shown to the player
  };
}

export const tileAt = (x, y) => MAP[y]?.[x];
export const dist = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
export const has = (world, id) => world.player.inventory.includes(id);

export function walkable(world, x, y) {
  const t = tileAt(x, y);
  if (t === "." || t === "=" || t === ",") return true;
  if (t === "G") return world.gateOpen;
  return false;
}

// Jimbo never leaves the outside of the wall.
function guardWalkable(world, x, y) {
  return y >= 3 && walkable(world, x, y) && !(x === world.player.x && y === world.player.y);
}

const DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };

export function movePlayer(world, dir) {
  const d = DIRS[dir];
  if (!d) return { ok: false, notice: "Unknown direction." };
  const p = world.player;
  const nx = p.x + d[0];
  const ny = p.y + d[1];
  if (nx === world.guard.x && ny === world.guard.y) return { ok: false, notice: "Captain Jimbo is in the way." };
  if (tileAt(nx, ny) === "G" && !world.gateOpen) return { ok: false, notice: "The gate is shut." };
  if (!walkable(world, nx, ny)) return { ok: false, notice: "You can't go that way." };
  p.x = nx;
  p.y = ny;
  return { ok: true, picked: pickUp(world) };
}

function pickUp(world) {
  const p = world.player;
  const i = world.ground.findIndex((g) => g.x === p.x && g.y === p.y);
  if (i < 0) return null;
  const [{ id }] = world.ground.splice(i, 1);
  if (ITEMS[id].gold) p.gold += ITEMS[id].gold;
  else p.inventory.push(id);
  return id;
}

// Breadth-first first step from Jimbo toward a target (stops when adjacent if `adjacentOk`).
function bfsStep(world, target, adjacentOk) {
  const g = world.guard;
  if (adjacentOk ? dist(g, target) <= 1 : g.x === target.x && g.y === target.y) return false;
  const key = (x, y) => y * W + x;
  const prev = new Map([[key(g.x, g.y), null]]);
  const queue = [[g.x, g.y]];
  while (queue.length) {
    const [x, y] = queue.shift();
    const done = adjacentOk ? dist({ x, y }, target) <= 1 : x === target.x && y === target.y;
    if (done) {
      let k = key(x, y);
      while (prev.get(k) !== key(g.x, g.y)) k = prev.get(k);
      g.x = k % W;
      g.y = Math.floor(k / W);
      return true;
    }
    for (const [dx, dy] of Object.values(DIRS)) {
      const nx = x + dx;
      const ny = y + dy;
      if (!prev.has(key(nx, ny)) && guardWalkable(world, nx, ny)) {
        prev.set(key(nx, ny), key(x, y));
        queue.push([nx, ny]);
      }
    }
  }
  return false;
}

export const guardApproach = (world) => bfsStep(world, world.player, true);
export const guardToPost = (world) => bfsStep(world, POST, false);

export function guardBackOff(world) {
  const g = world.guard;
  let best = null;
  for (const [dx, dy] of Object.values(DIRS)) {
    const c = { x: g.x + dx, y: g.y + dy };
    if (guardWalkable(world, c.x, c.y) && dist(c, world.player) > dist(g, world.player)) {
      if (!best || dist(c, POST) < dist(best, POST)) best = c;
    }
  }
  if (!best) return false;
  Object.assign(g, best);
  return true;
}

export function guardPatrol(world) {
  const g = world.guard;
  if (g.y !== POST.y) return guardToPost(world);
  let target = PATROL[g.patrolIndex];
  if (g.x === target.x && g.y === target.y) {
    g.patrolIndex = 1 - g.patrolIndex;
    target = PATROL[g.patrolIndex];
  }
  return bfsStep(world, target, false);
}

// If Jimbo stands on the only tile in front of the gate, he steps aside when he opens it.
export function openGate(world) {
  world.gateOpen = true;
  const g = world.guard;
  if (g.x === GATE.x && g.y === GATE.y + 1) {
    for (const x of [POST.x, GATE.x + 1]) {
      if (guardWalkable(world, x, POST.y)) {
        g.x = x;
        break;
      }
    }
  }
}

export const roll = (lo, hi) => lo + Math.floor(Math.random() * (hi - lo + 1));

export function describeDistance(d) {
  if (d <= 1) return "adjacent (within arm's reach)";
  if (d <= 3) return "close (2-3 steps away)";
  if (d <= SIGHT) return "nearby (4-6 steps away)";
  return "far away";
}

export function describePlayerSpot(world) {
  const p = world.player;
  if (dist(p, GATE) <= 1) return "right in front of the gate";
  if (p.x === GATE.x) return "on the road south of the gate";
  if (p.y === POST.y) return "walking along the city wall";
  return "in the fields outside the wall";
}

export function describeGuardSpot(world) {
  const g = world.guard;
  if (g.x === POST.x && g.y === POST.y) return "at his post beside the gate";
  if (g.y === POST.y) return "walking along the city wall";
  return "out in the fields, away from his post";
}
