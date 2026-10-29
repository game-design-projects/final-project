// Wizardry-style wireframe view, automap, and title card. Lines on black, tinted per floor.

export const DIRS = [
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
]; // N E S W
export const DIR_NAMES = ["N", "E", "S", "W"];

const INK = "#e8e8e8";
// Camera: the eye sits EYE cells behind the near edge of your cell (about a 44° field of view),
// and you see VIEW cells ahead. Size falls off as 1/distance, like a real corridor.
export const EYE = 1.25;
export const VIEW = 6;
export const scaleAt = (z) => EYE / (EYE + z);
export const DEPTH = Array.from({ length: VIEW + 2 }, (_, d) => scaleAt(d));

// World point -> canvas point. The cell you stand in fills the canvas (less a 4px border) at z = 0.
export function project(W, H, X, z, Y) {
  const s = scaleAt(z);
  return [W / 2 + X * (W - 8) * s, H / 2 + Y * (H - 8) * s];
}

function frame(W, H, d) {
  const f = DEPTH[d];
  const cx = W / 2;
  const cy = H / 2;
  const w = (W - 8) * f;
  const h = (H - 8) * f;
  return { l: Math.round(cx - w / 2), r: Math.round(cx + w / 2), t: Math.round(cy - h / 2), b: Math.round(cy + h / 2) };
}

function line(ctx, x1, y1, x2, y2) {
  ctx.beginPath();
  ctx.moveTo(x1 + 0.5, y1 + 0.5);
  ctx.lineTo(x2 + 0.5, y2 + 0.5);
  ctx.stroke();
}

export function clear(ctx) {
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
}

// Each floor gets its own colors: wall lines and an accent for torch flames and glows.
export const PALETTES = [
  { name: "BONE CRYPT", wall: "#e8e2d0", accent: "#ffb347" },
  { name: "DROWNED HALLS", wall: "#8fd3e8", accent: "#7fffd4" },
  { name: "BLOOD VAULT", wall: "#e07a7a", accent: "#ffcf5a" },
  { name: "MOSS DEEP", wall: "#9ed36b", accent: "#ffe14a" },
  { name: "ASH CHAMBERS", wall: "#b9b0a4", accent: "#ff6b3d" },
  { name: "VIOLET CATACOMB", wall: "#b79cf0", accent: "#ff9de2" },
  { name: "RUST TUNNELS", wall: "#d39a6a", accent: "#ffd27a" },
  { name: "FROST WARRENS", wall: "#cfe8ff", accent: "#9ad0ff" },
];

// Stable pseudo-random number for a wall face, so its decoration never changes as you move or turn.
function hash(...n) {
  let h = 2166136261;
  for (const v of n) h = Math.imul(h ^ (v + 0x9e3779b9), 16777619);
  h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
}

// Wall decorations, sketched in (u, v) face coordinates: u across the face, v from top (0) to bottom (1).
const DECOR = ["torch", "torch", "chains", "banner", "crack", "window", "niche"];

function decorate(ctx, face, kind, t, palette, seed) {
  const P = (u, v) => face(u, v);
  const poly = (pts, close) => {
    ctx.beginPath();
    pts.forEach(([u, v], i) => {
      const [x, y] = P(u, v);
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    });
    if (close) ctx.closePath();
    ctx.stroke();
  };
  const ring = (cu, cv, ru, rv, n = 10) => poly(Array.from({ length: n }, (_, i) => [cu + ru * Math.cos((i / n) * 6.283), cv + rv * Math.sin((i / n) * 6.283)]), true);
  ctx.save();
  if (kind === "torch") {
    const f = Math.sin(t / 90 + seed * 40) * 0.012 + Math.sin(t / 37 + seed * 17) * 0.008;
    const [gx, gy] = P(0.5, 0.36);
    // Glow sized by the face's height where the torch hangs, which shrinks properly with distance
    const [, top] = P(0.5, 0);
    const [, bottom] = P(0.5, 1);
    const glowR = Math.max(6, Math.abs(bottom - top) * 0.6);
    const glow = ctx.createRadialGradient(gx, gy, 0, gx, gy, glowR);
    glow.addColorStop(0, palette.accent + "55");
    glow.addColorStop(1, palette.accent + "00");
    ctx.fillStyle = glow;
    ctx.fillRect(gx - glowR, gy - glowR, glowR * 2, glowR * 2);
    poly([[0.44, 0.58], [0.56, 0.58]]); // bracket
    poly([[0.5, 0.58], [0.5, 0.44]]); // handle
    ctx.strokeStyle = palette.accent;
    poly([[0.45, 0.44], [0.47 + f, 0.36], [0.5 - f, 0.26 + f], [0.53 + f, 0.36], [0.55, 0.44]], true); // flame
    poly([[0.49, 0.42], [0.5 + f, 0.35], [0.51, 0.42]]);
  } else if (kind === "chains") {
    for (const [u, len] of [[0.38, 0.5], [0.6, 0.36]]) {
      poly([[u, 0], [u, len]]);
      for (let v = 0.06; v < len; v += 0.08) ring(u, v, 0.025, 0.03, 6);
      poly([[u - 0.04, len], [u, len + 0.06], [u + 0.04, len]]); // hook
    }
  } else if (kind === "banner") {
    poly([[0.3, 0.06], [0.7, 0.06]]);
    poly([[0.34, 0.06], [0.34, 0.56], [0.42, 0.5], [0.5, 0.58], [0.58, 0.5], [0.66, 0.56], [0.66, 0.06]]);
    ring(0.5, 0.26, 0.07, 0.08, 8);
    poly([[0.5, 0.18], [0.5, 0.34]]);
  } else if (kind === "crack") {
    poly([[0.3, 0.18], [0.38, 0.34], [0.34, 0.46], [0.46, 0.6], [0.42, 0.72], [0.52, 0.86]]);
    poly([[0.38, 0.34], [0.48, 0.38]]);
    poly([[0.46, 0.6], [0.58, 0.62]]);
  } else if (kind === "window") {
    poly([[0.36, 0.24], [0.64, 0.24], [0.64, 0.46], [0.36, 0.46]], true);
    for (const u of [0.43, 0.5, 0.57]) poly([[u, 0.24], [u, 0.46]]);
  } else if (kind === "niche") {
    poly([[0.36, 0.78], [0.36, 0.58], [0.42, 0.5], [0.5, 0.47], [0.58, 0.5], [0.64, 0.58], [0.64, 0.78]], true);
    ring(0.5, 0.64, 0.06, 0.06, 8); // skull
    ctx.fillStyle = ctx.strokeStyle;
    for (const u of [0.48, 0.52]) {
      const [x, y] = P(u, 0.63);
      ctx.fillRect(x - 1, y - 1, 2, 2);
    }
    poly([[0.47, 0.71], [0.53, 0.71]]);
  }
  ctx.restore();
}

// ---------------------------------------------------------------- 3D corridor
// The view is a real perspective projection of the grid. World coordinates, relative to you:
//   X across (cells, 0 = the middle of your cell, + = right), z ahead (0 = the near edge of your cell),
//   Y down (-0.5 = ceiling, +0.5 = floor). The eye sits EYE cells behind z = 0.
// Walls are painted far to near as black-filled faces, so nearer walls hide what is behind them.

// The surrounding cells, relative to you: d steps ahead, k steps to the right.
const cellAt = (x, y, dir, d, k) => {
  const [fx, fy] = DIRS[dir];
  const [rx, ry] = DIRS[(dir + 1) % 4];
  return [x + fx * d + rx * k, y + fy * d + ry * k];
};
const isOpen = (map, [cx, cy]) => map.grid[cy]?.[cx] === 1;
// How many cells to each side can fall inside the view at the far end
const REACH = Math.ceil((0.5 * (EYE + VIEW + 1)) / EYE);
// Outer columns first, then inward: within one row, an inner wall may overlap an outer one, never the reverse
const COLUMNS = [...Array.from({ length: REACH }, (_, i) => [-(REACH - i), REACH - i]).flat(), 0];

// Every face to draw, in painting order (far to near). Pure: no canvas, so it can be tested.
// front: the wall cell's face toward you, at z = d. side: its face toward your column, from z = d to d + 1.
// `wall` is the wall cell and `from` the floor cell it is seen from (the pair keys its decoration).
export function corridorFaces(map, x, y, dir) {
  const faces = [];
  for (let d = VIEW; d >= 0; d--) {
    for (const k of COLUMNS) {
      const here = cellAt(x, y, dir, d, k);
      if (isOpen(map, here)) {
        if (map.stairs.x === here[0] && map.stairs.y === here[1]) faces.push({ type: "stairs", d, k, wall: here, from: here });
        continue;
      }
      const inner = k < 0 ? k + 1 : k - 1;
      if (k !== 0) {
        const beside = cellAt(x, y, dir, d, inner);
        if (isOpen(map, beside)) faces.push({ type: "side", d, k, wall: here, from: beside });
      }
      if (d > 0) {
        const before = cellAt(x, y, dir, d - 1, k);
        if (isOpen(map, before)) faces.push({ type: "front", d, k, wall: here, from: before });
      }
    }
  }
  return faces;
}

// Floor cells you can actually see from here (for the automap): a ray from the eye must reach some
// part of the cell through open floor only, and the cell must be inside the view.
export function visibleCells(map, x, y, dir) {
  const out = [];
  const openRel = (X, z) => isOpen(map, cellAt(x, y, dir, Math.floor(z), Math.round(X)));
  const sees = (tx, tz) => {
    if (Math.abs(tx) > (0.5 * (EYE + tz)) / EYE) return false; // off the side of the screen
    const steps = Math.ceil(tz / 0.08);
    for (let i = 0; i < steps; i++) {
      const z = (tz * i) / steps;
      const X = (tx * (EYE + z)) / (EYE + tz);
      if (!openRel(X, z)) return false;
    }
    return true;
  };
  for (let d = 0; d <= VIEW; d++) {
    for (let k = -REACH; k <= REACH; k++) {
      const c = cellAt(x, y, dir, d, k);
      if (!isOpen(map, c)) continue;
      const samples = [[k, d + 0.5], [k - 0.4, d + 0.1], [k + 0.4, d + 0.1], [k - 0.4, d + 0.9], [k + 0.4, d + 0.9]];
      if ((d === 0 && k === 0) || samples.some(([sx, sz]) => sees(sx, sz))) out.push(c);
    }
  }
  return out;
}

// A face's (u, v) -> screen mapper, perspective-correct: u runs left to right as you see the face,
// v from its top (0) to its bottom (1).
export function faceMapper(W, H, face) {
  const { d, k } = face;
  if (face.type === "front") return (u, v) => project(W, H, k - 0.5 + u, d, v - 0.5);
  const X = k < 0 ? k + 0.5 : k - 0.5;
  // A wall on your left reads near-to-far left to right; one on your right, far-to-near
  return (u, v) => project(W, H, X, k < 0 ? d + u : d + 1 - u, v - 0.5);
}

// Lines fade with distance, like torchlight that doesn't reach far
const fog = (z) => Math.max(0.15, Math.min(1, 1.15 - z * 0.16));
const alpha = (hex, a) => hex + Math.round(a * 255).toString(16).padStart(2, "0");

function paintFace(ctx, W, H, face, palette) {
  const P = faceMapper(W, H, face);
  const pts = [P(0, 0), P(1, 0), P(1, 1), P(0, 1)];
  const outline = new Path2D();
  pts.forEach(([px, py], i) => (i ? outline.lineTo(px, py) : outline.moveTo(px, py)));
  outline.closePath();
  P.outline = outline;
  ctx.fillStyle = "#000";
  ctx.fill(outline);
  if (face.type === "front") ctx.strokeStyle = alpha(palette.wall, fog(face.d));
  else {
    // A side wall spans a whole cell of depth, so its lines fade along it
    const zl = face.k < 0 ? face.d : face.d + 1;
    const zr = face.k < 0 ? face.d + 1 : face.d;
    const g = ctx.createLinearGradient(pts[0][0], 0, pts[1][0], 0);
    g.addColorStop(0, alpha(palette.wall, fog(zl)));
    g.addColorStop(1, alpha(palette.wall, fog(zr)));
    ctx.strokeStyle = g;
  }
  ctx.lineWidth = face.d >= 3 ? 1.5 : 2;
  ctx.stroke(outline);
  return P;
}

// Stairs down: a hole in the floor, steps dropping away inside it.
function paintStairs(ctx, W, H, { d, k }, palette) {
  const at = (X, z, Y = 0.5) => project(W, H, X, z, Y);
  const [x0, x1, z0, z1] = [k - 0.38, k + 0.38, d + 0.08, d + 0.92];
  const rim = [at(x0, z0), at(x1, z0), at(x1, z1), at(x0, z1)];
  ctx.save();
  ctx.strokeStyle = alpha(palette.wall, fog(d + 0.5));
  ctx.lineWidth = d >= 3 ? 1 : 1.5;
  ctx.beginPath();
  rim.forEach(([px, py], i) => (i ? ctx.lineTo(px, py) : ctx.moveTo(px, py)));
  ctx.closePath();
  ctx.fillStyle = "#000";
  ctx.fill();
  ctx.stroke();
  ctx.clip();
  // Each step a little lower and a little narrower than the one before, so the hole reads as going down.
  // Steps in the accent color: from the floor at a grazing angle the hole is thin, and it has to stand out.
  ctx.strokeStyle = alpha(palette.accent, fog(d + 0.5));
  for (let i = 1; i <= 4; i++) {
    const z = z1 - (i / 5) * (z1 - z0);
    const inset = i * 0.02;
    const [ax, ay] = at(x0 + inset, z, 0.5 + i * 0.012);
    const [bx, by] = at(x1 - inset, z, 0.5 + i * 0.012);
    line(ctx, ax, ay, bx, by);
  }
  ctx.restore();
}

// A decoration, if this wall face (wall cell seen from floor cell) has one
function decorFor(map, [wx, wy], [cx, cy]) {
  const r = hash(wx, wy, cx, cy, map.seed ?? 0);
  return r < 0.32 ? { kind: DECOR[Math.floor(hash(wy, wx, map.seed ?? 0, 7) * DECOR.length)], seed: r } : null;
}

// The corridor only changes when you move or turn. In between, only torch flames move, and they flicker at
// FLAME_FPS. So the view is painted into a cached layer once per step (and once per flame frame while a torch is
// in sight), and every other frame just copies that layer: one drawImage instead of every face, gradient and path.
export const FLAME_FPS = 24;
const layers = new WeakMap(); // map -> its layer: { canvas, pos, faces, decor, torches, cells, key }
const newLayer = (W, H) =>
  typeof OffscreenCanvas !== "undefined" ? new OffscreenCanvas(W, H) : typeof document !== "undefined" ? Object.assign(document.createElement("canvas"), { width: W, height: H }) : null;

// The layer's cache key at time t: where you stand, and the flame frame only if a flame is in sight
export const layerKey = (pos, torches, t) => `${pos}|${torches ? Math.floor((t * FLAME_FPS) / 1000) : "-"}`;

// What you see from (x, y) facing dir, worked out once per position: faces in painting order, their
// decorations, whether a torch is among them, and the floor cells in view (for the automap).
export function corridorView(map, x, y, dir) {
  const faces = corridorFaces(map, x, y, dir);
  const decor = faces.map((f) => (f.type === "stairs" ? null : decorFor(map, f.wall, f.from)));
  return { faces, decor, torches: decor.some((d) => d?.kind === "torch"), cells: visibleCells(map, x, y, dir) };
}

function paintCorridor(ctx, map, view, t) {
  const { width: W, height: H } = ctx.canvas;
  const palette = map.palette ?? PALETTES[0];
  clear(ctx);
  ctx.save();
  ctx.beginPath();
  ctx.rect(4, 4, W - 8, H - 8);
  ctx.clip();
  view.faces.forEach((face, i) => {
    if (face.type === "stairs") return paintStairs(ctx, W, H, face, palette);
    const P = paintFace(ctx, W, H, face, palette);
    const dec = view.decor[i];
    if (!dec) return;
    // Decorations go on with their wall, so nearer walls still cover them, and stay inside it (a torch's glow
    // must not leak around the corner of the wall that hides it)
    ctx.save();
    ctx.clip(P.outline);
    ctx.strokeStyle = palette.wall;
    ctx.globalAlpha = fog(face.d + (face.type === "side" ? 0.5 : 0));
    ctx.lineWidth = face.d >= 2 ? 1 : 1.5;
    decorate(ctx, P, dec.kind, t, palette, dec.seed);
    ctx.restore();
  });
  ctx.restore();
  ctx.strokeStyle = palette.wall;
  ctx.lineWidth = 2;
  ctx.strokeRect(4.5, 4.5, W - 8, H - 8);
}

// Draws the view from (x,y) facing dir. Returns the floor cells you can see (for the automap).
// `t` animates torch flames.
export function drawCorridor(ctx, map, x, y, dir, t = 0) {
  const { width: W, height: H } = ctx.canvas;
  let L = layers.get(map);
  if (!L) layers.set(map, (L = { canvas: newLayer(W, H), pos: null, key: null }));
  const pos = `${x},${y},${dir},${W}x${H}`;
  if (L.pos !== pos) Object.assign(L, corridorView(map, x, y, dir), { pos, key: null });
  const key = layerKey(pos, L.torches, t);
  const flameT = (Math.floor((t * FLAME_FPS) / 1000) * 1000) / FLAME_FPS;
  if (!L.canvas) {
    paintCorridor(ctx, map, L, flameT); // nowhere to cache (no canvas support): paint straight in
    return L.cells;
  }
  if (L.key !== key) {
    L.key = key;
    paintCorridor(L.canvas.getContext("2d"), map, L, flameT);
  }
  ctx.drawImage(L.canvas, 0, 0);
  return L.cells;
}

// The walls you have seen, as edges of seen floor cells: [x, y, side] with side 0..3 = N E S W.
// In the view walls are faces with no thickness, so the map draws them as lines, not as blocks
// (a block would look the same as unexplored dark).
export function wallEdges(map, seen) {
  const w = map.grid[0].length;
  const edges = [];
  for (const k of seen) {
    const cx = k % w;
    const cy = Math.floor(k / w);
    DIRS.forEach(([dx, dy], side) => {
      if (map.grid[cy + dy]?.[cx + dx] !== 1) edges.push([cx, cy, side]);
    });
  }
  return edges;
}

export function drawMap(ctx, map, seen, visited, x, y, dir) {
  const n = map.grid.length;
  const s = Math.floor(ctx.canvas.width / n);
  clear(ctx);
  for (let cy = 0; cy < n; cy++) {
    for (let cx = 0; cx < n; cx++) {
      const k = cy * n + cx;
      if (!seen.has(k)) continue;
      ctx.fillStyle = visited.has(k) ? "#5a5a5a" : "#262626";
      ctx.fillRect(cx * s, cy * s, s, s);
    }
  }
  // Walls: a bright line along each side of seen floor that faces one, in the floor's wall color
  ctx.fillStyle = (map.palette ?? PALETTES[0]).wall;
  for (const [cx, cy, side] of wallEdges(map, seen)) {
    const [px, py] = [cx * s, cy * s];
    if (side === 0) ctx.fillRect(px, py, s, 1);
    else if (side === 1) ctx.fillRect(px + s - 1, py, 1, s);
    else if (side === 2) ctx.fillRect(px, py + s - 1, s, 1);
    else ctx.fillRect(px, py, 1, s);
  }
  const sk = map.stairs.y * n + map.stairs.x;
  if (seen.has(sk)) {
    ctx.fillStyle = INK;
    ctx.fillRect(map.stairs.x * s + 1, map.stairs.y * s + 1, s - 2, s - 2);
    ctx.fillStyle = "#000";
    ctx.fillRect(map.stairs.x * s + 2, map.stairs.y * s + 2, s - 4, s - 4);
  }
  // The floor's red champion, marked from the start so you can choose to hunt it
  if (map.boss && !map.boss.defeated) {
    ctx.fillStyle = "#ff2a2a";
    ctx.fillRect(map.boss.x * s, map.boss.y * s, s, s);
  }
  // You: a small arrow
  const px = x * s + s / 2;
  const py = y * s + s / 2;
  const [dx, dy] = DIRS[dir];
  ctx.fillStyle = "#fff";
  ctx.beginPath();
  ctx.moveTo(px + dx * s * 0.6, py + dy * s * 0.6);
  ctx.lineTo(px - dx * s * 0.4 - dy * s * 0.4, py - dy * s * 0.4 + dx * s * 0.4);
  ctx.lineTo(px - dx * s * 0.4 + dy * s * 0.4, py - dy * s * 0.4 - dx * s * 0.4);
  ctx.closePath();
  ctx.fill();
}

export function drawTitle(ctx, t, prompt = "PRESS ANY KEY") {
  const { width: W, height: H } = ctx.canvas;
  clear(ctx);
  ctx.strokeStyle = INK;
  ctx.lineWidth = 2;
  // A receding corridor behind the title
  for (let d = 0; d < 5; d++) {
    const f = frame(W, H, d);
    ctx.strokeRect(f.l + 0.5, f.t + 0.5, f.r - f.l, f.b - f.t);
  }
  ctx.fillStyle = "#000";
  ctx.fillRect(W * 0.12, H * 0.3, W * 0.76, H * 0.42);
  ctx.strokeRect(W * 0.12 + 0.5, H * 0.3 + 0.5, W * 0.76, H * 0.42);
  ctx.fillStyle = INK;
  ctx.textAlign = "center";
  ctx.font = `28px "Press Start 2P", monospace`;
  ctx.fillText("DONJON", W / 2, H * 0.45);
  ctx.font = `9px "Press Start 2P", monospace`;
  if (Math.floor(t / 600) % 2 === 0) ctx.fillText(prompt, W / 2, H * 0.65);
  ctx.textAlign = "left";
}
