// A die you can see: it tumbles through random faces, then slams onto the real number (~200ms in all).
// Frame maths and shapes are pure (tested in crawler/test/dice.test.js); drawDie / DicePops paint wireframes on a 2D canvas.

export const DIE_TUMBLE_MS = 130; // flickering through random faces, spinning and growing toward the camera
export const DIE_LAND_MS = 70; // the slam: scale punch + flash, number locked in
export const DIE_ANIM_MS = DIE_TUMBLE_MS + DIE_LAND_MS; // 200: the whole roll animation
export const DIE_HOLD_MS = 550; // the result stays readable after it lands (longer on a natural 20 / 1)
export const DIE_FADE_MS = 250;
export const FACE_MS = 26; // a new random face about every 26ms while tumbling

const TAU = Math.PI * 2;
const RED = "#ff4a3a";

export function dieTier(value, sides = 20) {
  if (sides !== 20) return null;
  return value === 20 ? "crit" : value === 1 ? "fumble" : null;
}

const holdFor = (tier) => DIE_HOLD_MS + (tier ? 350 : 0);
export const popLifeMs = (tier) => DIE_ANIM_MS + holdFor(tier) + DIE_FADE_MS;

// Faces to flicker through before the real number: random, never the same twice in a row, and the last
// flicker is never the final value (so the number visibly lands). faces[count - 1] is the final value.
export function faceSequence(final, sides = 20, count = Math.ceil(DIE_TUMBLE_MS / FACE_MS) + 1, rng = Math.random) {
  const faces = [];
  for (let i = 0; i < count - 1; i++) {
    let f;
    let tries = 0;
    do f = 1 + Math.floor(rng() * sides);
    while (tries++ < 20 && sides > 2 && (f === faces[i - 1] || (i === count - 2 && f === final)));
    faces.push(f);
  }
  faces.push(final);
  return faces;
}

const easeOut = (p) => 1 - (1 - p) * (1 - p);

// What a die looks like `age` ms after it was thrown (negative: not thrown yet).
//   rot: radians; hop/scale: px offset and size multiplier; flash 0..1 white at the slam; glow 0..1 (nat 20);
//   shake: px of horizontal jitter (nat 1); faceIdx: index into faceSequence; landed: number is locked in.
export function dieFrame(age, tier = null) {
  const idle = { show: false, faceIdx: 0, rot: 0, hop: 0, scale: 1, flash: 0, glow: 0, shake: 0, alpha: 0, landed: false, done: false };
  if (age < 0) return idle;
  const punch = tier === "crit" ? 0.8 : tier === "fumble" ? 0.35 : 0.5;
  const faces = Math.ceil(DIE_TUMBLE_MS / FACE_MS);
  if (age < DIE_TUMBLE_MS) {
    const p = age / DIE_TUMBLE_MS;
    return {
      ...idle,
      show: true,
      alpha: 1,
      faceIdx: Math.min(Math.floor(age / FACE_MS), faces - 1),
      rot: easeOut(p) * 2 * TAU, // two turns, fast to slow, ending upright
      hop: -Math.sin(Math.PI * p) * 8,
      scale: 0.7 + (1 + punch - 0.7) * p * p, // thrown at the camera...
    };
  }
  const total = popLifeMs(tier);
  if (age >= total) return { ...idle, done: true };
  const q = Math.min(1, (age - DIE_TUMBLE_MS) / DIE_LAND_MS);
  const alpha = age < total - DIE_FADE_MS ? 1 : (total - age) / DIE_FADE_MS;
  const slam = age < DIE_ANIM_MS;
  return {
    ...idle,
    show: true,
    alpha,
    landed: true,
    faceIdx: faces, // the final value
    // ...and slammed down onto the number, dipping a hair below 1 before it settles
    scale: slam ? 1 + punch * (1 - q) ** 2 - 0.1 * Math.sin(Math.PI * q) : 1,
    flash: slam ? 1 - q : 0,
    glow: tier === "crit" ? (slam ? 1 : 0.65 + 0.35 * Math.sin(age / 80)) : 0,
    shake: tier === "fumble" && slam ? 4 * (1 - q) : 0,
  };
}

// ---- shapes: unit-radius wireframes, y down. Closed outline polygon plus inner edges [x1, y1, x2, y2].
const ring = (n, radius = 1, start = -90) => Array.from({ length: n }, (_, k) => [Math.cos(((start + (360 / n) * k) * Math.PI) / 180) * radius, Math.sin(((start + (360 / n) * k) * Math.PI) / 180) * radius]);
const seg = (a, b) => [a[0], a[1], b[0], b[1]];

export function dieShape(sides = 20) {
  switch (sides) {
    case 4:
      return { outline: ring(3), inner: [] };
    case 6: {
      // a cube seen corner-on: hexagon with a Y inside
      const hex = ring(6);
      return { outline: hex, inner: [1, 3, 5].map((i) => seg([0, 0], hex[i])) };
    }
    case 8: {
      const o = ring(4);
      return { outline: o, inner: [seg(o[1], o[3]), seg(o[0], o[2])] };
    }
    case 10: {
      const kite = [[0, -1], [0.85, -0.12], [0, 1], [-0.85, -0.12]];
      return { outline: kite, inner: [seg(kite[0], kite[2]), seg(kite[1], [0, 0.3]), seg(kite[3], [0, 0.3])] };
    }
    case 12: {
      const o = ring(5);
      const i = ring(5, 0.5, 90);
      return { outline: o, inner: [...i.map((p, k) => seg(p, i[(k + 1) % 5])), ...o.map((p) => seg(p, i.reduce((b, q) => (Math.hypot(q[0] - p[0], q[1] - p[1]) < Math.hypot(b[0] - p[0], b[1] - p[1]) ? q : b))))] };
    }
    case 20: {
      // the classic d20 icon: hexagon, inner triangle, every hexagon corner tied to the triangle
      const hex = ring(6);
      const tri = [ring(3, 0.52, 90)[0], ring(3, 0.52, 90)[1], ring(3, 0.52, 90)[2]]; // points down
      const inner = tri.map((p, k) => seg(p, tri[(k + 1) % 3]));
      for (const h of hex) {
        const near = [...tri].sort((a, b) => Math.hypot(a[0] - h[0], a[1] - h[1]) - Math.hypot(b[0] - h[0], b[1] - h[1]));
        inner.push(seg(h, near[0]));
        if (Math.hypot(near[1][0] - h[0], near[1][1] - h[1]) < 0.95) inner.push(seg(h, near[1]));
      }
      return { outline: hex, inner };
    }
    default:
      return { outline: ring(8), inner: [] };
  }
}

// ---- drawing

function path(ctx, pts) {
  ctx.beginPath();
  pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
  ctx.closePath();
}

// One die at (x, y), radius r, already framed by dieFrame. `face` is the number to print.
export function drawDie(ctx, { x, y, r = 16, sides = 20, face, frame, ink = "#e8e8e8", hot = "#ffd27a", tier = null, label = "", dim = false, seed = 0 }) {
  if (!frame.show) return;
  const { outline, inner } = dieShape(sides);
  const line = tier === "crit" ? hot : tier === "fumble" && frame.landed ? RED : ink;
  const jitter = frame.shake ? Math.sin(seed + frame.shake * 40) * frame.shake : 0;
  const k = r * frame.scale * (dim && frame.landed ? 0.8 : 1);
  ctx.save();
  ctx.globalAlpha = frame.alpha * (dim && frame.landed ? 0.4 : 1);
  ctx.translate(Math.round(x + jitter), Math.round(y + frame.hop));
  ctx.rotate(frame.rot);
  ctx.scale(k, k);
  if (frame.glow) {
    ctx.shadowColor = hot;
    ctx.shadowBlur = 14 * frame.glow;
  }
  path(ctx, outline);
  ctx.fillStyle = "rgba(0,0,0,0.88)";
  ctx.fill();
  ctx.lineJoin = "round";
  ctx.lineWidth = 2 / k;
  ctx.strokeStyle = line;
  ctx.stroke();
  ctx.shadowBlur = 0;
  ctx.lineWidth = 1 / k;
  ctx.globalAlpha *= 0.5;
  ctx.beginPath();
  for (const [x1, y1, x2, y2] of inner) {
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
  }
  ctx.stroke();
  ctx.globalAlpha = frame.alpha * (dim && frame.landed ? 0.4 : 1);
  if (frame.flash > 0) {
    path(ctx, outline);
    ctx.fillStyle = tier === "crit" ? hot : "#ffffff";
    ctx.globalAlpha *= 0.7 * frame.flash;
    ctx.fill();
    ctx.globalAlpha = frame.alpha * (dim && frame.landed ? 0.4 : 1);
  }
  // the number (counter-scaled so the font stays crisp)
  ctx.scale(1 / k, 1 / k);
  const shown = String(face);
  ctx.font = `${Math.round(r * (shown.length > 1 ? 0.62 : 0.78))}px "Press Start 2P", monospace`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = "#000";
  ctx.fillText(shown, 1.5, Math.round(r * 0.05) + 1.5);
  ctx.fillStyle = frame.landed && frame.flash > 0.5 ? "#000" : frame.landed && tier ? line : "#ffffff";
  ctx.fillText(shown, 0, Math.round(r * 0.05));
  ctx.scale(k, k);
  if (frame.landed && tier === "fumble") {
    // a crack through the die
    ctx.strokeStyle = RED;
    ctx.lineWidth = 1.6 / k;
    ctx.beginPath();
    [[-0.25, -0.95], [0.1, -0.4], [-0.2, 0.05], [0.22, 0.5], [0, 0.98]].forEach(([cx, cy], i) => (i ? ctx.lineTo(cx, cy) : ctx.moveTo(cx, cy)));
    ctx.stroke();
  }
  if (frame.landed && tier === "crit") {
    // rays burst out of the die as it lands
    const grow = 1.25 + 0.5 * (frame.flash || 0.2);
    ctx.strokeStyle = hot;
    ctx.lineWidth = 1.5 / k;
    ctx.beginPath();
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU + Math.PI / 8;
      ctx.moveTo(Math.cos(a) * 1.25, Math.sin(a) * 1.25);
      ctx.lineTo(Math.cos(a) * grow * 1.35, Math.sin(a) * grow * 1.35);
    }
    ctx.stroke();
  }
  ctx.restore();
  if (label && frame.landed) {
    ctx.save();
    ctx.globalAlpha = frame.alpha * (dim ? 0.4 : 1);
    ctx.font = `7px "Press Start 2P", monospace`;
    ctx.textAlign = "center";
    ctx.fillStyle = "#000";
    ctx.fillText(label, Math.round(x) + 1, Math.round(y + r + 12) + 1);
    ctx.fillStyle = line;
    ctx.fillText(label, Math.round(x), Math.round(y + r + 12));
    ctx.restore();
  }
}

// The scale bump for anything that "lands" (the Roll of Fate name): 1 + strength at the slam, settling to 1 in 200ms.
export const landPunch = (age, strength = 0.45) => (age >= 0 && age < DIE_ANIM_MS ? 1 + strength * (1 - age / DIE_ANIM_MS) ** 2 : 1);

// Dice currently on screen. Each pop is one roll: a single d20, or two for advantage / disadvantage.
export class DicePops {
  constructor(max = 10) {
    this.max = max;
    this.pops = [];
  }

  // rolls: every die thrown; kept: the one that counts; label: small text under the die (e.g. "=21").
  add({ x, y, rolls, kept = rolls[0], sides = 20, label = "", now = performance.now(), rng = Math.random }) {
    // Rolls at the same target sit side by side (a round of attacks shows all its dice at once);
    // if there is no room left, the previous result is pushed out.
    const near = this.pops.filter((p) => Math.abs(p.y - y) < 28);
    const free = [0, 52, -52, 104, -104].find((dx) => x + dx > 20 && x + dx < 428 && !near.some((p) => Math.abs(p.x - (x + dx)) < 48));
    if (free !== undefined) x += free;
    else for (const p of near) if (Math.abs(p.x - x) < 48) p.t0 = Math.min(p.t0, now - (DIE_ANIM_MS + holdFor(p.tier)));
    const tier = dieTier(kept, sides);
    const keptIdx = Math.max(0, rolls.indexOf(kept));
    const pop = { x, y, sides, label, t0: now, tier, kept, dice: rolls.map((v, i) => ({ final: v, faces: faceSequence(v, sides, undefined, rng), kept: i === keptIdx })) };
    this.pops.push(pop);
    while (this.pops.length > this.max) this.pops.shift();
    return pop;
  }

  get size() {
    return this.pops.length;
  }

  draw(ctx, t, { ink, hot } = {}) {
    this.pops = this.pops.filter((p) => t - p.t0 < popLifeMs(p.tier));
    for (const p of this.pops) {
      const age = t - p.t0;
      const two = p.dice.length > 1;
      p.dice.forEach((die, i) => {
        const tier = die.kept ? p.tier : dieTier(die.final, p.sides);
        const frame = dieFrame(age, die.kept ? p.tier : null);
        const faces = die.faces;
        drawDie(ctx, {
          x: p.x + (two ? (i ? 19 : -19) : 0),
          y: p.y,
          r: two ? 14 : 17,
          sides: p.sides,
          face: frame.landed ? die.final : faces[Math.min(frame.faceIdx, faces.length - 2)],
          frame,
          ink,
          hot,
          tier: die.kept ? tier : null,
          label: die.kept ? p.label : "",
          dim: two && !die.kept,
          seed: p.t0 + i,
        });
      });
    }
  }
}
