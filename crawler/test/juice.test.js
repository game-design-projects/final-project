// Game feel (public/juice.js): the event bus, shake, hit-stop, danger and view transitions. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createBus, FX_EVENTS, Shake, traumaFor, HitStop, HITSTOP_MS, dangerOf, approach, transitionAt, TRANSITION_MS } from "../public/juice.js";

test("the bus delivers typed events and refuses unknown names or missing fields", () => {
  const bus = createBus();
  const got = [];
  const off = bus.on("enemy:hit", (p) => got.push(p.dmg));
  bus.emit("enemy:hit", { dmg: 4, maxHp: 10, crit: false });
  off();
  bus.emit("enemy:hit", { dmg: 9, maxHp: 10, crit: true });
  assert.deepEqual(got, [4]);
  assert.throws(() => bus.emit("enemy:hti", {}), /no such event/);
  assert.throws(() => bus.emit("enemy:hit", { dmg: 1 }), /needs maxHp, crit/);
  assert.throws(() => bus.on("nope", () => {}), /no such event/);
});

test("a listener that throws never stops the others, or the game", () => {
  const bus = createBus();
  const got = [];
  const warn = console.warn;
  console.warn = () => {};
  bus.on("view:bump", () => {
    throw new Error("broken effect");
  });
  bus.on("view:bump", () => got.push("ok"));
  bus.emit("view:bump");
  console.warn = warn;
  assert.deepEqual(got, ["ok"]);
});

test("every event in the catalog lists its fields as an array", () => {
  for (const [name, fields] of Object.entries(FX_EVENTS)) assert.ok(Array.isArray(fields) && /^[a-z]+:[a-z]+$/.test(name), name);
});

test("shake: no trauma, no motion; a hit shakes, then settles within a second", () => {
  const s = new Shake();
  assert.deepEqual(s.offset(0), [0, 0]);
  s.add(0.6);
  const moves = [];
  for (let t = 16; t <= 300; t += 16) moves.push(Math.hypot(...s.offset(t)));
  assert.ok(Math.max(...moves) > 1, "it moves");
  assert.ok(Math.max(...moves) <= 10, "never past the cap");
  assert.deepEqual(s.offset(1000), [0, 0], "settled after the trauma drains");
});

test("shake grows with the square of trauma, so small hits barely nudge", () => {
  const peak = (amount) => {
    const s = new Shake();
    s.offset(0);
    s.add(amount);
    let m = 0;
    for (let t = 1; t <= 120; t += 1) m = Math.max(m, Math.hypot(...s.offset(t)));
    return m;
  };
  assert.ok(peak(0.8) > 3 * peak(0.3));
});

test("shake: a kick dated in the future waits for its die to land", () => {
  const s = new Shake();
  s.offset(0);
  s.add(0.5, 200);
  assert.deepEqual(s.offset(100), [0, 0], "not yet");
  s.offset(210);
  assert.ok(s.trauma > 0.4, "landed");
});

test("trauma: party damage scales with the share of health taken, crits and kills hit harder", () => {
  assert.ok(traumaFor("party:hurt", { dmg: 9, maxHp: 10 }) > traumaFor("party:hurt", { dmg: 1, maxHp: 10 }));
  assert.ok(traumaFor("enemy:hit", { dmg: 3, maxHp: 10, crit: true }) > traumaFor("enemy:hit", { dmg: 3, maxHp: 10, crit: false }));
  assert.ok(traumaFor("enemy:kill", { boss: true }) > traumaFor("enemy:kill", { boss: false }));
  assert.equal(traumaFor("combat:start", { boss: false }), 0);
  for (const n of Object.keys(FX_EVENTS)) assert.ok(traumaFor(n, { dmg: 99, maxHp: 1, crit: true, boss: true }) <= 1, n);
});

test("hit-stop: the animation clock stands still during a freeze, then carries on without a jump", () => {
  const h = new HitStop();
  assert.equal(h.clock(100), 100);
  h.freeze(100, HITSTOP_MS.crit);
  assert.equal(h.clock(120), 100, "frozen");
  assert.equal(h.clock(180), 100, "still frozen");
  assert.equal(h.clock(200), 200 - HITSTOP_MS.crit, "carries on from where it stopped");
  assert.equal(h.clock(300), 300 - HITSTOP_MS.crit);
  h.freeze(300, 50);
  h.freeze(310, 100); // a second blow during the freeze extends it
  assert.equal(h.clock(400), 300 - HITSTOP_MS.crit);
  assert.equal(h.clock(500), 500 - HITSTOP_MS.crit - 110);
});

test("danger: none at half health or more, rising as health runs out, high while someone is dying", () => {
  const m = (hp, maxHp = 10, extra = {}) => ({ hp, maxHp, dead: false, down: false, ...extra });
  assert.equal(dangerOf([m(10), m(10), m(10)]), 0);
  assert.equal(dangerOf([m(5), m(5)]), 0);
  assert.ok(dangerOf([m(3), m(3)]) > 0 && dangerOf([m(3), m(3)]) < 1);
  assert.equal(dangerOf([m(1), m(1), m(1, 20)]), 1);
  assert.ok(dangerOf([m(10), m(10), m(0, 10, { down: true })]) >= 0.6, "someone rolling death saves");
  assert.equal(dangerOf([m(10), m(10), m(0, 10, { down: true, stable: true })]) < 0.6, true, "stable is not dying");
  assert.equal(dangerOf([m(0, 10, { dead: true })]), 1, "everyone dead");
  assert.equal(dangerOf([m(10), m(0, 10, { dead: true })]), 0, "the dead don't count against the living");
});

test("approach eases toward the target at the same speed whatever the frame rate", () => {
  let a = 0;
  for (let i = 0; i < 4; i++) a = approach(a, 1, 62.5, 250);
  const b = approach(0, 1, 250, 250);
  assert.ok(Math.abs(a - b) < 1e-9);
  assert.ok(Math.abs(b - 0.5) < 1e-9);
});

test("view transitions: a step forward grows the old frame and fades it, a turn pans, both end on time", () => {
  const step = transitionAt({ kind: "step", dir: 1, t0: 0 }, TRANSITION_MS.step / 2);
  assert.ok(step.scale > 1 && step.alpha > 0 && step.alpha < 1);
  assert.ok(transitionAt({ kind: "step", dir: -1, t0: 0 }, 50).scale < 1, "stepping back shrinks it");
  const left = transitionAt({ kind: "turn", dir: -1, t0: 0 }, 80);
  assert.ok(left.shift > 0, "turning left slides the old view off to the right");
  assert.ok(transitionAt({ kind: "turn", dir: 1, t0: 0 }, 80).shift < 0);
  for (const kind of Object.keys(TRANSITION_MS)) assert.equal(transitionAt({ kind, dir: 1, t0: 0 }, TRANSITION_MS[kind]), null, kind);
  assert.equal(transitionAt(null, 0), null);
});
