// The die animation: frame timing, face flicker, shapes, and the pop store. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { DIE_ANIM_MS, DIE_TUMBLE_MS, DIE_LAND_MS, FACE_MS, DicePops, dieFrame, dieShape, dieTier, faceSequence, landPunch, popLifeMs, drawDie } from "../public/dice.js";

// A 2D context that accepts and ignores every call (and remembers property sets).
const fakeCtx = () => new Proxy({}, { get: (t, k) => (k in t ? t[k] : () => {}), set: (t, k, v) => ((t[k] = v), true) });
const seeded = (seed) => () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

test("the whole animation is 200ms: 130ms of tumbling, then a 70ms slam", () => {
  assert.equal(DIE_TUMBLE_MS, 130);
  assert.equal(DIE_LAND_MS, 70);
  assert.equal(DIE_ANIM_MS, 200);
});

test("natural 20 and natural 1 are only special on a d20", () => {
  assert.equal(dieTier(20), "crit");
  assert.equal(dieTier(1), "fumble");
  assert.equal(dieTier(13), null);
  assert.equal(dieTier(20, 20), "crit");
  assert.equal(dieTier(8, 8), null);
  assert.equal(dieTier(1, 6), null);
});

test("face sequence flickers randomly and ends on the real number", () => {
  for (let seed = 1; seed <= 200; seed++) {
    const final = 1 + (seed % 20);
    const faces = faceSequence(final, 20, undefined, seeded(seed));
    assert.equal(faces.length, Math.ceil(DIE_TUMBLE_MS / FACE_MS) + 1);
    assert.equal(faces.at(-1), final);
    assert.notEqual(faces.at(-2), final, "the last flicker must differ so the number visibly lands");
    faces.forEach((f, i) => {
      assert.ok(Number.isInteger(f) && f >= 1 && f <= 20);
      if (i) assert.notEqual(f, faces[i - 1], "no repeated neighbours");
    });
  }
  // other dice stay on their own faces, even a two-sided one
  for (const sides of [4, 6, 8, 10, 12, 2]) assert.ok(faceSequence(1, sides, 6, seeded(sides)).every((f) => f >= 1 && f <= sides));
});

test("a die is hidden before it is thrown, tumbles for 130ms, then lands", () => {
  assert.equal(dieFrame(-1).show, false);
  const start = dieFrame(0);
  assert.ok(start.show && !start.landed && start.alpha === 1);
  assert.ok(!dieFrame(DIE_TUMBLE_MS - 1).landed);
  const slam = dieFrame(DIE_TUMBLE_MS);
  assert.ok(slam.landed);
  assert.ok(slam.scale > 1.2, "the slam punches the scale up");
  assert.ok(slam.flash > 0.9, "and flashes");
  const settled = dieFrame(DIE_ANIM_MS);
  assert.ok(settled.landed && settled.flash === 0 && settled.scale === 1);
});

test("the tumble ends upright and the faces advance through the sequence", () => {
  const end = dieFrame(DIE_TUMBLE_MS - 0.001);
  assert.ok(Math.abs(end.rot / (2 * Math.PI) - Math.round(end.rot / (2 * Math.PI))) < 1e-3, "whole turns");
  const idx = [0, 30, 60, 90, 120].map((t) => dieFrame(t).faceIdx);
  assert.deepEqual(idx, [...idx].sort((a, b) => a - b));
  assert.ok(new Set(idx).size >= 4, "a new face every ~26ms");
  assert.ok(dieFrame(DIE_TUMBLE_MS - 1).faceIdx <= Math.ceil(DIE_TUMBLE_MS / FACE_MS) - 1);
});

test("a natural 20 slams harder and glows; a natural 1 shakes and cracks; both linger longer", () => {
  const normal = dieFrame(DIE_TUMBLE_MS, null);
  const crit = dieFrame(DIE_TUMBLE_MS, "crit");
  const fumble = dieFrame(DIE_TUMBLE_MS, "fumble");
  assert.ok(crit.scale > normal.scale);
  assert.ok(crit.glow > 0 && normal.glow === 0 && fumble.glow === 0);
  assert.ok(fumble.shake > 0 && normal.shake === 0 && crit.shake === 0);
  assert.ok(popLifeMs("crit") > popLifeMs(null) && popLifeMs("fumble") > popLifeMs(null));
  assert.ok(dieFrame(popLifeMs(null) + 1, null).done);
  assert.ok(!dieFrame(popLifeMs(null) + 1, "crit").done, "a crit is still on screen when a normal die has gone");
  assert.ok(dieFrame(popLifeMs(null) - 10).alpha < 0.1, "fades out at the end");
  assert.ok(dieFrame(DIE_ANIM_MS + 100).alpha === 1);
});

test("every die shape is a closed polygon inside the unit circle, with finite inner lines", () => {
  for (const sides of [4, 6, 8, 10, 12, 20, 7]) {
    const { outline, inner } = dieShape(sides);
    assert.ok(outline.length >= 3, `d${sides}`);
    for (const [x, y] of outline) assert.ok(Math.hypot(x, y) <= 1.001);
    for (const e of inner) {
      assert.equal(e.length, 4);
      assert.ok(e.every(Number.isFinite));
    }
  }
  assert.equal(dieShape(20).outline.length, 6, "d20 is drawn as the classic hexagon");
  assert.ok(dieShape(20).inner.length >= 9, "with its inner triangle and spokes");
  assert.equal(dieShape(4).outline.length, 3);
  assert.equal(dieShape(12).outline.length, 5);
});

test("pops are drawn and expire; rolls at the same target sit side by side", () => {
  const pops = new DicePops();
  const ctx = fakeCtx();
  const a = pops.add({ x: 100, y: 100, rolls: [13], now: 0, rng: seeded(1) });
  const b = pops.add({ x: 300, y: 100, rolls: [7, 16], kept: 16, now: 0, rng: seeded(2), label: "=21" });
  assert.equal(pops.size, 2);
  pops.draw(ctx, 50, {});
  pops.draw(ctx, 400, { ink: "#fff", hot: "#ff0" });
  assert.equal(pops.size, 2);
  // a second and third roll at the first one's target: neighbours, not a pile
  const c = pops.add({ x: 104, y: 98, rolls: [20], now: 100, rng: seeded(3) });
  const d = pops.add({ x: 104, y: 98, rolls: [5], now: 100, rng: seeded(4) });
  const xs = [a, c, d].map((p) => p.x).sort((m, n) => m - n);
  assert.ok(xs[1] - xs[0] >= 48 && xs[2] - xs[1] >= 48, `spread out: ${xs}`);
  assert.ok(xs.every((x) => x > 20 && x < 428));
  assert.equal(b.x, 300, "unrelated pops don't move");
  pops.draw(ctx, 100 + popLifeMs("crit") + 1, {});
  assert.equal(pops.size, 0, "everything expires");
});

test("with no room left, a new roll pushes the oldest result at that spot out", () => {
  const pops = new DicePops(20);
  for (let i = 0; i < 5; i++) pops.add({ x: 224, y: 100, rolls: [i + 2], now: 0, rng: seeded(i + 1) });
  const jammed = pops.add({ x: 224, y: 100, rolls: [9], now: 600, rng: seeded(9) });
  assert.equal(jammed.x, 224);
  assert.ok(pops.pops[0].t0 <= 600 - DIE_ANIM_MS - 500, "an old pop at that spot jumped to its fade");
});

test("advantage throws two dice and keeps the right one; the pop count is capped", () => {
  const pops = new DicePops(3);
  const p = pops.add({ x: 50, y: 50, rolls: [4, 18], kept: 18, now: 0, rng: seeded(5) });
  assert.equal(p.dice.length, 2);
  assert.deepEqual(p.dice.map((d) => d.kept), [false, true]);
  assert.equal(p.tier, null);
  for (let i = 0; i < 6; i++) pops.add({ x: 50 + i * 60, y: 50, rolls: [i + 1], now: 0, rng: seeded(i) });
  assert.equal(pops.size, 3);
  const crit = pops.add({ x: 400, y: 50, rolls: [20, 3], kept: 20, now: 0 });
  assert.equal(crit.tier, "crit");
});

test("drawDie paints every phase for every tier without throwing", () => {
  const ctx = fakeCtx();
  for (const tier of [null, "crit", "fumble"])
    for (const age of [0, 40, 129, 130, 165, 199, 300, 900, 1200]) {
      const frame = dieFrame(age, tier);
      drawDie(ctx, { x: 100, y: 100, face: 7, frame, tier, label: "=12", dim: age % 2 === 0 });
    }
});

test("landPunch bumps then settles within 200ms", () => {
  assert.equal(landPunch(-1), 1);
  assert.ok(Math.abs(landPunch(0, 0.5) - 1.5) < 1e-9);
  assert.ok(landPunch(100, 0.5) < 1.5 && landPunch(100, 0.5) > 1);
  assert.equal(landPunch(DIE_ANIM_MS), 1);
});
