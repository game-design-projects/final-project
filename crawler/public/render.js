// Wizardry-style wireframe view, automap, and title card. Lines on black, tinted per floor.

export const DIRS = [
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
]; // N E S W
export const DIR_NAMES = ["N", "E", "S", "W"];

const INK = "#e8e8e8";
export const DEPTH = [1, 0.62, 0.38, 0.23, 0.14];

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
    const [ex] = P(0.62, 0.36);
    const glowR = Math.max(6, Math.abs(ex - gx) * 3.2);
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

const lerp = (a, b, t) => a + (b - a) * t;
// A face as four corners: top-left, top-right, bottom-right, bottom-left -> (u, v) mapper
const faceOf = (tl, tr, br, bl) => (u, v) => {
  const top = [lerp(tl[0], tr[0], u), lerp(tl[1], tr[1], u)];
  const bot = [lerp(bl[0], br[0], u), lerp(bl[1], br[1], u)];
  return [lerp(top[0], bot[0], v), lerp(top[1], bot[1], v)];
};

// Draws the corridor from (x,y) facing dir. Returns the cells that were visible (for the automap).
// `t` animates torch flames.
export function drawCorridor(ctx, map, x, y, dir, t = 0) {
  const { width: W, height: H } = ctx.canvas;
  const palette = map.palette ?? PALETTES[0];
  clear(ctx);
  ctx.strokeStyle = palette.wall;
  ctx.lineWidth = 2;
  const seen = [];
  const [fx, fy] = DIRS[dir];
  const [lx, ly] = DIRS[(dir + 3) % 4];
  const [rx, ry] = DIRS[(dir + 1) % 4];
  const open = (cx, cy) => map.grid[cy]?.[cx] === 1;
  // A decoration, if this wall face (wall cell seen from floor cell) has one
  const decorFor = (wx, wy, cx, cy) => {
    const r = hash(wx, wy, cx, cy, map.seed ?? 0);
    return r < 0.32 ? { kind: DECOR[Math.floor(hash(wy, wx, map.seed ?? 0, 7) * DECOR.length)], seed: r } : null;
  };
  const decor = [];

  const outer = frame(W, H, 0);
  ctx.strokeRect(outer.l + 0.5, outer.t + 0.5, outer.r - outer.l, outer.b - outer.t);

  for (let d = 0; d < 4; d++) {
    const cx = x + fx * d;
    const cy = y + fy * d;
    if (!open(cx, cy)) break;
    seen.push([cx, cy]);
    const near = frame(W, H, d);
    const far = frame(W, H, d + 1);

    // Left side
    if (open(cx + lx, cy + ly)) {
      seen.push([cx + lx, cy + ly]);
      line(ctx, near.l, far.t, far.l, far.t);
      line(ctx, near.l, far.b, far.l, far.b);
      if (d > 0) line(ctx, near.l, far.t, near.l, far.b);
    } else {
      line(ctx, near.l, near.t, far.l, far.t);
      line(ctx, near.l, near.b, far.l, far.b);
      const dec = decorFor(cx + lx, cy + ly, cx, cy);
      if (dec) decor.push([faceOf([near.l, near.t], [far.l, far.t], [far.l, far.b], [near.l, near.b]), dec]);
    }
    line(ctx, far.l, far.t, far.l, far.b);

    // Right side
    if (open(cx + rx, cy + ry)) {
      seen.push([cx + rx, cy + ry]);
      line(ctx, near.r, far.t, far.r, far.t);
      line(ctx, near.r, far.b, far.r, far.b);
      if (d > 0) line(ctx, near.r, far.t, near.r, far.b);
    } else {
      line(ctx, near.r, near.t, far.r, far.t);
      line(ctx, near.r, near.b, far.r, far.b);
      const dec = decorFor(cx + rx, cy + ry, cx, cy);
      if (dec) decor.push([faceOf([far.r, far.t], [near.r, near.t], [near.r, near.b], [far.r, far.b]), dec]);
    }
    line(ctx, far.r, far.t, far.r, far.b);

    if (map.stairs.x === cx && map.stairs.y === cy) drawStairs(ctx, near, far);

    if (!open(cx + fx, cy + fy)) {
      line(ctx, far.l, far.t, far.r, far.t);
      line(ctx, far.l, far.b, far.r, far.b);
      const dec = decorFor(cx + fx, cy + fy, cx, cy);
      if (dec) decor.push([faceOf([far.l, far.t], [far.r, far.t], [far.r, far.b], [far.l, far.b]), dec]);
      break;
    }
  }
  // Decorations last, nearest first is fine: they never overlap across faces
  ctx.lineWidth = 1.5;
  for (const [face, dec] of decor) decorate(ctx, face, dec.kind, t, palette, dec.seed);
  ctx.lineWidth = 2;
  return seen;
}

// A hole in the floor with steps going down.
function drawStairs(ctx, near, far) {
  ctx.save();
  ctx.strokeStyle = ctx.strokeStyle;
  const inset = (a, b, t) => a + (b - a) * t;
  const y1 = inset(near.b, far.b, 0.25);
  const y2 = inset(near.b, far.b, 0.8);
  const lx1 = inset(near.l, far.l, 0.25) + (far.r - far.l) * 0.18;
  const rx1 = inset(near.r, far.r, 0.25) - (far.r - far.l) * 0.18;
  const lx2 = inset(near.l, far.l, 0.8) + (far.r - far.l) * 0.2;
  const rx2 = inset(near.r, far.r, 0.8) - (far.r - far.l) * 0.2;
  line(ctx, lx1, y1, rx1, y1);
  line(ctx, lx2, y2, rx2, y2);
  line(ctx, lx1, y1, lx2, y2);
  line(ctx, rx1, y1, rx2, y2);
  for (let i = 1; i < 4; i++) {
    const t = i / 4;
    line(ctx, inset(lx1, lx2, t), inset(y1, y2, t), inset(rx1, rx2, t), inset(y1, y2, t));
  }
  ctx.restore();
}

export function drawMap(ctx, map, seen, visited, x, y, dir) {
  const n = map.grid.length;
  const s = Math.floor(ctx.canvas.width / n);
  clear(ctx);
  for (let cy = 0; cy < n; cy++) {
    for (let cx = 0; cx < n; cx++) {
      const k = cy * n + cx;
      if (!seen.has(k)) continue;
      ctx.fillStyle = visited.has(k) ? "#6a6a6a" : "#2e2e2e";
      ctx.fillRect(cx * s, cy * s, s, s);
    }
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
