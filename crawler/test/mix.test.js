// The mixing desk (public/mix.js), the beat scheduler, the music's beat clock (ambient.js) and the effects'
// variation and voice limit (sfx.js), against a fake Web Audio graph. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { Mixer, BeatScheduler, DANGER, IMPACT, RESTING_BPM, cutoffFor, heartEvery } from "../public/mix.js";
import { Ambient, TRACKS } from "../public/ambient.js";
import { Sfx, VARY, POLY, POLY_WINDOW } from "../public/sfx.js";

class Param {
  constructor(v = 0) {
    this.value = v;
    this.events = [];
  }
  setValueAtTime(v, at) {
    this.value = v;
    this.events.push(["set", v, at]);
  }
  setTargetAtTime(v, at, tc) {
    this.events.push(["target", v, at, tc]);
  }
  linearRampToValueAtTime(v, at) {
    this.value = v;
    this.events.push(["ramp", v, at]);
  }
  exponentialRampToValueAtTime(v, at) {
    this.events.push(["exp", v, at]);
  }
  cancelScheduledValues() {}
}
const node = (extra = {}) => ({ connect: (n) => n, ...extra });
class Ctx {
  constructor() {
    this.currentTime = 5;
    this.destination = node();
    this.sources = [];
  }
  createGain() {
    return node({ gain: new Param(1) });
  }
  createBiquadFilter() {
    return node({ frequency: new Param(350), Q: new Param(1), type: "" });
  }
  createDynamicsCompressor() {
    return node({ threshold: new Param(), knee: new Param(), ratio: new Param(), attack: new Param(), release: new Param() });
  }
  createBufferSource() {
    const s = node({ start: (at, off) => Object.assign(s, { at, off }), stop() {} });
    this.sources.push(s);
    return s;
  }
  resume() {
    return Promise.resolve();
  }
  suspend() {
    this.suspended = true;
  }
}

test("danger closes the music's low-pass, from wide open to muffled, in octaves", () => {
  assert.equal(cutoffFor(0), DANGER.openHz);
  assert.ok(Math.abs(cutoffFor(1) - DANGER.closedHz) < 1e-6);
  const mid = cutoffFor(0.5);
  assert.ok(Math.abs(mid - Math.sqrt(DANGER.openHz * DANGER.closedHz)) < 1e-6, "halfway is the geometric middle");
  const mix = new Mixer(new Ctx());
  mix.setDanger(1);
  assert.deepEqual(mix.lowpass.frequency.events.at(-1).slice(0, 2), ["target", cutoffFor(1)]);
  assert.ok(mix.musicBus.gain.events.at(-1)[1] < 1, "the music dips under the heartbeat");
  const n = mix.lowpass.frequency.events.length;
  mix.setDanger(1.004);
  assert.equal(mix.lowpass.frequency.events.length, n, "no rescheduling for a change nobody hears");
});

test("a big hit dips the music and lets it straight back", () => {
  const ctx = new Ctx();
  const mix = new Mixer(ctx);
  mix.impact(IMPACT.crit, 6);
  const [down, up] = mix.impactGain.gain.events;
  assert.deepEqual(down, ["target", 1 - IMPACT.crit, 6, IMPACT.attack]);
  assert.equal(up[1], 1);
  assert.ok(up[2] > 6 && up[2] < 6.2);
});

test("the heart beats every other beat when hurt, every beat when someone is about to die", () => {
  assert.equal(heartEvery(0), null);
  assert.equal(heartEvery(DANGER.heartFrom - 0.01), null);
  assert.equal(heartEvery(DANGER.heartFrom), 2);
  assert.equal(heartEvery(DANGER.heartFast), 1);
  assert.equal(heartEvery(1), 1);
});

test("the scheduler lands every beat exactly on the music's grid, once, a little ahead", () => {
  const ctx = new Ctx();
  const beats = [];
  const grid = { bpm: 120, origin: 4.9 }; // a beat every 0.5 s, one on 4.9
  const s = new BeatScheduler({ ctx, clock: () => grid, onBeat: (at, k) => beats.push([+at.toFixed(6), k]), lookahead: 0.2 });
  for (let t = 5; t < 7; t += 0.05) {
    ctx.currentTime = t;
    s.tick();
  }
  const times = beats.map((b) => b[0]);
  assert.deepEqual(times, [5.4, 5.9, 6.4, 6.9]);
  assert.deepEqual(beats.map((b) => b[1]), [1, 2, 3, 4], "beat numbers count from the grid's origin");
  assert.equal(new Set(times).size, times.length, "never twice");
});

test("the scheduler follows a new grid (a fight's loop starts) and rests at its own pace without one", () => {
  const ctx = new Ctx();
  const beats = [];
  let grid = null;
  const s = new BeatScheduler({ ctx, clock: () => grid, onBeat: (at) => beats.push(+at.toFixed(4)), lookahead: 0.1 });
  for (let t = 5; t < 7; t += 0.02) {
    ctx.currentTime = t;
    s.tick();
  }
  const gaps = beats.slice(1).map((b, i) => +(b - beats[i]).toFixed(4));
  assert.ok(gaps.every((g) => Math.abs(g - 60 / RESTING_BPM) < 1e-3), `resting pace: ${gaps}`);
  beats.length = 0;
  grid = { bpm: 132, origin: 7.013 };
  for (let t = 7; t < 9; t += 0.02) {
    ctx.currentTime = t;
    s.tick();
  }
  for (const b of beats) {
    const k = (b - 7.013) / (60 / 132);
    assert.ok(Math.abs(k - Math.round(k)) < 1e-3, `${b} is on the 132 BPM grid`);
  }
});

test("the music reports its beat grid: the loop's start, less the bit of the file it skips", () => {
  const ctx = new Ctx();
  const music = new Ambient({ timer: { setTimeout: () => 0, clearTimeout() {} }, random: () => 0 });
  music.attach(ctx, node());
  music.buffers = { explore: {} };
  for (const v of TRACKS.battle.variants) music.buffers[`battle:${v.name}`] = {};
  assert.equal(music.beatClock(), null, "nothing playing");
  music.on = true;
  music.exploreIn(1);
  const ex = music.beatClock();
  assert.equal(ex.bpm, 64);
  assert.ok(Math.abs(ex.origin - (5 - 0.25)) < 1e-9);
  ctx.currentTime = 9;
  music.setMood("battle");
  const b = music.beatClock();
  assert.ok(TRACKS.battle.variants.some((v) => v.bpm === b.bpm && Math.abs(v.loopSeconds - 3840 / v.bpm) < 1e-9));
  assert.ok(Math.abs(b.origin - (9 - 0.25)) < 1e-9);
});

test("with a shared context, music off mutes the music instead of suspending the effects too", () => {
  const ctx = new Ctx();
  const music = new Ambient({ timer: { setTimeout: () => 0, clearTimeout() {} } });
  music.attach(ctx, node());
  music.stop();
  assert.equal(ctx.suspended, undefined, "the context keeps running for the effects");
  assert.equal(music.mute.gain.events.at(-1)[1], 0);
});

// Effects: record what the primitives are asked to play
function recordingSfx(random = () => 0.5) {
  const sfx = new Sfx(0.5, { random });
  sfx.ctx = { state: "running", currentTime: 1 };
  const calls = [];
  // The real primitives apply the variation (rate, gainMul) to what they are given; so do these
  for (const m of ["tone", "noise"])
    sfx[m] = function (at, o) {
      calls.push({ m, at, f0: o.f0 * this.rate, vol: o.vol * this.gainMul });
    };
  sfx.vocal = () => {};
  return { sfx, calls };
}

test("repeated hits never sound the same twice: random detune and volume, within bounds", () => {
  let i = 0;
  const seq = [0, 1, 0.25, 0.75, 0.5, 0.1];
  const { sfx, calls } = recordingSfx(() => seq[i++ % seq.length]);
  for (let n = 0; n < 3; n++) {
    sfx.ctx.currentTime = 1 + n; // far apart: no voice limit
    sfx.play("hit");
  }
  const tones = calls.filter((c) => c.m === "tone").map((c) => c.f0);
  assert.equal(new Set(tones.map((f) => f.toFixed(3))).size, 3, `three different pitches: ${tones}`);
  const cents = (f) => 1200 * Math.log2(f / 150);
  for (const f of tones) assert.ok(Math.abs(cents(f)) <= VARY.hit.cents + 1e-9);
});

test("sounds not on the list keep their exact pitch", () => {
  const { sfx, calls } = recordingSfx(() => 0.9);
  sfx.play("save"); // a fixed musical note
  assert.ok(Math.abs(calls[0].f0 - 440 * 2 ** ((84 - 69) / 12)) < 1e-9);
});

test("voice limit: six hits at once play three, each a little quieter; later ones play again", () => {
  const { sfx, calls } = recordingSfx();
  for (let n = 0; n < 6; n++) sfx.play("hit");
  assert.equal(sfx.stats.played, POLY.hit);
  assert.equal(sfx.stats.dropped, 6 - POLY.hit);
  const vols = calls.filter((c) => c.m === "tone").map((c) => c.vol);
  assert.ok(vols[1] < vols[0] && vols[2] < vols[1], `stacked copies are quieter: ${vols}`);
  sfx.ctx.currentTime += POLY_WINDOW * 2;
  sfx.play("hit");
  assert.equal(sfx.stats.played, POLY.hit + 1);
});

test("the heartbeat is a quiet double thump that scales with danger", () => {
  const { sfx, calls } = recordingSfx();
  sfx.play("heartbeat", { level: 0.5 });
  const loud = calls.filter((c) => c.m === "tone").map((c) => c.vol);
  assert.equal(loud.length, 4, "lub, dub, each with its octave for small speakers");
  calls.length = 0;
  sfx.ctx.currentTime += 1;
  sfx.play("heartbeat", { level: 1 });
  const louder = calls.filter((c) => c.m === "tone").map((c) => c.vol);
  assert.ok(louder[0] > loud[0]);
});

test("effects can play into a shared context's bus", () => {
  const ctx = new Ctx();
  ctx.sampleRate = 8000;
  ctx.createConvolver = () => node();
  ctx.createBuffer = (ch, n) => ({ getChannelData: () => new Float32Array(n) });
  const bus = node();
  let into = null;
  const comp = ctx.createDynamicsCompressor();
  comp.connect = (n) => (into = n);
  ctx.createDynamicsCompressor = () => comp;
  const sfx = new Sfx();
  sfx.init(ctx, bus);
  assert.equal(into, bus);
});
