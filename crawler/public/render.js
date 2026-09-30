// Wizardry-style wireframe view, automap, and title card. All white lines on black.

export const DIRS = [
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
]; // N E S W
export const DIR_NAMES = ["N", "E", "S", "W"];

const INK = "#e8e8e8";
const DEPTH = [1, 0.62, 0.38, 0.23, 0.14];

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

// Draws the corridor from (x,y) facing dir. Returns the cells that were visible (for the automap).
export function drawCorridor(ctx, map, x, y, dir) {
  const { width: W, height: H } = ctx.canvas;
  clear(ctx);
  ctx.strokeStyle = INK;
  ctx.lineWidth = 2;
  const seen = [];
  const [fx, fy] = DIRS[dir];
  const [lx, ly] = DIRS[(dir + 3) % 4];
  const [rx, ry] = DIRS[(dir + 1) % 4];
  const open = (cx, cy) => map.grid[cy]?.[cx] === 1;

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
    }
    line(ctx, far.r, far.t, far.r, far.b);

    if (map.stairs.x === cx && map.stairs.y === cy) drawStairs(ctx, near, far);

    if (!open(cx + fx, cy + fy)) {
      line(ctx, far.l, far.t, far.r, far.t);
      line(ctx, far.l, far.b, far.r, far.b);
      break;
    }
  }
  return seen;
}

// A hole in the floor with steps going down.
function drawStairs(ctx, near, far) {
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
  ctx.font = `20px "Press Start 2P", monospace`;
  ctx.fillText("HALLS OF JEV", W / 2, H * 0.45);
  ctx.font = `9px "Press Start 2P", monospace`;
  ctx.fillText("A DUNGEON WHERE MONSTERS LISTEN", W / 2, H * 0.53);
  if (Math.floor(t / 600) % 2 === 0) ctx.fillText(prompt, W / 2, H * 0.65);
  ctx.textAlign = "left";
}
