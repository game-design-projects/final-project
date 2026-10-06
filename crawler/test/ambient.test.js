// Music mood switching (explore <-> battle), against a fake Web Audio graph: run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { Ambient, TRACKS, FADES } from "../public/ambient.js";

// Just enough of AudioContext to record what the player schedules
class FakeParam {
  constructor() {
    this.value = 0;
    this.ramps = [];
  }
  setValueAtTime(v) {
    this.value = v;
  }
  cancelScheduledValues() {}
  linearRampToValueAtTime(v, at) {
    this.ramps.push([v, at]);
    this.value = v;
  }
}
class FakeCtx {
  constructor() {
    this.currentTime = 10;
    this.sources = [];
    this.destination = {};
  }
  createGain() {
    return { gain: new FakeParam(), connect() {} };
  }
  createBufferSource() {
    const src = { connect() {}, start: (at, offset) => Object.assign(src, { startedAt: at, offset }), stop: (at) => (src.stoppedAt = at) };
    this.sources.push(src);
    return src;
  }
  resume() {
    return Promise.resolve();
  }
  suspend() {}
}

function started() {
  const music = new Ambient();
  music.ctx = new FakeCtx();
  music.master = music.ctx.createGain();
  music.buffers = { explore: { name: "explore" }, battle: { name: "battle" } };
  music.play("explore", 4);
  return music;
}

test("a fight fades the battle loop in fast and the ambient out", () => {
  const music = started();
  music.setMood("battle");
  const { battle, explore } = music.voices;
  assert.equal(battle.src.buffer.name, "battle");
  assert.deepEqual(battle.gain.gain.ramps.at(-1), [TRACKS.battle.volume, 10 + FADES.battle.in]);
  assert.deepEqual(explore.gain.gain.ramps.at(-1), [0, 10 + FADES.explore.out]);
  assert.equal(explore.src.stoppedAt, undefined, "the ambient keeps its place under the fight");
});

test("after the fight the battle loop stops and the same ambient voice comes back", () => {
  const music = started();
  const ambient = music.voices.explore;
  music.setMood("battle");
  const battle = music.voices.battle;
  music.setMood("explore");
  assert.equal(music.voices.explore, ambient);
  assert.deepEqual(ambient.gain.gain.ramps.at(-1), [TRACKS.explore.volume, 10 + FADES.explore.in]);
  assert.ok(battle.src.stoppedAt > 10, "battle loop stops once faded");
  assert.equal(music.voices.battle, undefined);
});

test("each fight starts the battle loop from bar one", () => {
  const music = started();
  music.setMood("battle");
  const first = music.voices.battle.src;
  music.setMood("explore");
  music.setMood("battle");
  assert.notEqual(music.voices.battle.src, first);
  assert.equal(music.voices.battle.src.offset, 0.25);
});

test("mood changes before the music starts are remembered, not played", () => {
  const music = new Ambient();
  music.setMood("battle");
  assert.equal(music.mood, "battle");
  assert.deepEqual(music.voices, {});
});

test("the battle loop length matches the render: 16 bars at 152 BPM", () => {
  assert.ok(Math.abs(TRACKS.battle.loopSeconds - 25.263) < 0.001);
});
