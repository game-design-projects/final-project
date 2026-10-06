// Music mood switching (explore <-> battle), against a fake Web Audio graph: run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { Ambient, TRACKS, FADES, PACE, STINGS } from "../public/ambient.js";

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

// Timers you advance by hand
function fakeTimer() {
  let now = 0;
  let id = 0;
  const pending = new Map();
  return {
    setTimeout: (fn, ms) => (pending.set(++id, { fn, at: now + ms }), id),
    clearTimeout: (i) => pending.delete(i),
    advance(ms) {
      now += ms;
      for (const [i, t] of [...pending].sort((a, b) => a[1].at - b[1].at))
        if (t.at <= now && pending.has(i)) {
          pending.delete(i);
          t.fn();
        }
    },
    get pending() {
      return [...pending.values()].map((t) => t.at - now);
    },
  };
}

function started() {
  const timer = fakeTimer();
  const music = new Ambient({ timer, random: () => 0.5 });
  music.ctx = new FakeCtx();
  music.master = music.ctx.createGain();
  music.buffers = { explore: { name: "explore" }, battle: { name: "battle" }, fanfare: { name: "fanfare", duration: 3.6 }, victory: { name: "victory", duration: 2.2 } };
  music.exploreIn(4);
  return music;
}
const level = (music, track) => music.voices[track]?.gain.gain.ramps.at(-1)?.[0];

test("a fight fades the battle loop in fast and the ambient out", () => {
  const music = started();
  music.setMood("battle");
  const { battle, explore } = music.voices;
  assert.equal(battle.src.buffer.name, "battle");
  assert.deepEqual(battle.gain.gain.ramps.at(-1), [TRACKS.battle.volume, 10 + FADES.battle.in]);
  assert.deepEqual(explore.gain.gain.ramps.at(-1), [0, 10 + FADES.explore.out]);
  assert.equal(explore.src.stoppedAt, undefined, "the ambient keeps its place under the fight");
});

test("after the fight the battle loop stops, a quiet beat, then the same ambient voice comes back", () => {
  const music = started();
  const ambient = music.voices.explore;
  music.setMood("battle");
  const battle = music.voices.battle;
  music.setMood("explore");
  assert.equal(level(music, "explore"), 0, "not straight back");
  music.timer.advance(PACE.afterFight * 1000);
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

test("the ambient comes and goes: a stretch of music, then a stretch of quiet", () => {
  const music = started();
  assert.equal(level(music, "explore"), TRACKS.explore.volume);
  const play = (PACE.play[0] + PACE.play[1]) / 2;
  const rest = (PACE.rest[0] + PACE.rest[1]) / 2;
  music.timer.advance(play * 1000 - 1);
  assert.equal(level(music, "explore"), TRACKS.explore.volume);
  music.timer.advance(1);
  assert.equal(level(music, "explore"), 0, "rests after playing");
  music.timer.advance(rest * 1000);
  assert.equal(level(music, "explore"), TRACKS.explore.volume, "and comes back");
});

test("a fight cancels the ambient's comings and goings", () => {
  const music = started();
  music.setMood("battle");
  assert.deepEqual(music.timer.pending, []);
});

test("the stairs fanfare silences the ambient and leaves quiet after it", () => {
  const music = started();
  music.sting("fanfare");
  assert.equal(level(music, "explore"), 0);
  const fanfare = music.ctx.sources.at(-1);
  assert.equal(fanfare.buffer.name, "fanfare");
  assert.ok(!fanfare.loop, "a sting plays once");
  assert.deepEqual(music.timer.pending, [(3.6 + PACE.afterSting) * 1000]);
  music.timer.advance((3.6 + PACE.afterSting) * 1000);
  assert.equal(level(music, "explore"), TRACKS.explore.volume);
});

test("winning a fight: the victory sting cuts the battle loop", () => {
  const music = started();
  music.setMood("battle");
  const battle = music.voices.battle;
  music.sting("victory");
  music.setMood("explore");
  assert.ok(battle.src.stoppedAt <= 10 + 0.5, "battle loop gone within half a second");
  assert.equal(music.ctx.sources.at(-1).buffer.name, "victory");
  assert.ok(STINGS.victory.volume > 0);
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
