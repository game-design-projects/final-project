// Music mood switching (explore <-> battle), against a fake Web Audio graph: run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { Ambient, TRACKS, FADES, PACE, STINGS, DUCK } from "../public/ambient.js";

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

function started({ random = () => 0.5 } = {}) {
  const timer = fakeTimer();
  const music = new Ambient({ timer, random });
  music.ctx = new FakeCtx();
  music.master = music.ctx.createGain();
  music.buffers = { explore: { name: "explore" }, fanfare: { name: "fanfare", duration: 3.6 }, victory: { name: "victory", duration: 2.2 } };
  for (const v of TRACKS.battle.variants) music.buffers[`battle:${v.name}`] = { name: `battle:${v.name}` };
  music.exploreIn(4);
  return music;
}
const level = (music, track) => music.voices[track]?.gain.gain.ramps.at(-1)?.[0];

test("a fight fades the battle loop in fast and the ambient out", () => {
  const music = started();
  music.setMood("battle");
  const { battle, explore } = music.voices;
  assert.match(battle.src.buffer.name, /^battle:/);
  assert.deepEqual(battle.gain.gain.ramps.at(-1), [TRACKS.battle.volume, 10 + FADES.battle.in]);
  assert.deepEqual(explore.gain.gain.ramps.at(-1), [0, 10 + FADES.explore.underFight]);
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

test("a fight silences the ambient almost at once, so the two never play together", () => {
  const music = started();
  music.setMood("battle");
  const [to, at] = music.voices.explore.gain.gain.ramps.at(-1);
  assert.equal(to, 0);
  assert.ok(at - 10 <= 0.5, `ambient still audible ${at - 10}s into the fight`);
});

test("between stretches of exploring the ambient still fades out slowly", () => {
  const music = started();
  music.timer.advance(((PACE.play[0] + PACE.play[1]) / 2) * 1000);
  const [to, at] = music.voices.explore.gain.gain.ramps.at(-1);
  assert.equal(to, 0);
  assert.equal(at - 10, FADES.explore.out);
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

test("a fight cancels the ambient's comings and goings; nothing else is pending", () => {
  const music = started();
  music.setMood("battle");
  assert.deepEqual(music.timer.pending, []);
});

test("each fight picks a battle loop at random, never the same one twice in a row", () => {
  let r = 0;
  const seq = [0.1, 0.1, 0.9, 0.5, 0.5, 0.3, 0.7, 0.2];
  const music = started({ random: () => seq[r++ % seq.length] });
  const heard = [];
  for (let i = 0; i < 8; i++) {
    music.setMood("battle");
    heard.push(music.battle.name);
    music.setMood("explore");
  }
  for (let i = 1; i < heard.length; i++) assert.notEqual(heard[i], heard[i - 1], `fight ${i} repeated ${heard[i]}`);
  assert.ok(new Set(heard).size >= 3, `only heard ${[...new Set(heard)]}`);
});

test("a long fight keeps its one loop: the tune never changes mid-fight", () => {
  const music = started();
  music.setMood("battle");
  const first = music.battle;
  const voice = music.voices.battle;
  music.timer.advance(10 * 60 * 1000);
  assert.equal(music.battle, first);
  assert.equal(music.voices.battle, voice);
  assert.equal(voice.src.stoppedAt, undefined, "still playing");
  assert.equal(voice.src.loop, true);
  assert.equal(level(music, "battle"), TRACKS.battle.volume, "never faded out");
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

test("no battle loop runs faster than 132 BPM", () => {
  for (const v of TRACKS.battle.variants) assert.ok(3840 / v.loopSeconds <= 132 + 1e-9, `${v.name} is ${(3840 / v.loopSeconds).toFixed(1)} BPM`);
});

test("battle loop lengths match the renders: 16 bars of 4/4 at each tempo", () => {
  // scripts/build-battle.py: toccata 132, charge 126, crusade 112, gallop 120 BPM
  const want = { toccata: 29.091, charge: 30.476, crusade: 34.286, gallop: 32 };
  assert.deepEqual(TRACKS.battle.variants.map((v) => v.name).sort(), Object.keys(want).sort());
  for (const v of TRACKS.battle.variants) assert.ok(Math.abs(v.loopSeconds - want[v.name]) < 0.001, v.name);
});

test("ducking pulls the music down under speech and brings it back", () => {
  const music = started();
  music.duck(true);
  assert.equal(music.master.gain.ramps.at(-1)[0], DUCK.level);
  music.duck(false);
  assert.equal(music.master.gain.ramps.at(-1)[0], 1);
});

test("the explore loop length matches the render: 40 bars of 3/4 at 64 BPM", () => {
  assert.equal(TRACKS.explore.loopSeconds, 112.5);
});

test("explore sits a little under the fights, and stings match the fights", () => {
  // The renders are mastered to -19 dBFS RMS (explore) and -17 dBFS RMS (fights and stings): scripts/sampler.py
  const db = (rms, volume) => rms + 20 * Math.log10(volume);
  const explore = db(-19, TRACKS.explore.volume);
  const battle = db(-17, TRACKS.battle.volume);
  assert.ok(battle - explore >= 1.5 && battle - explore <= 4, `explore is ${(battle - explore).toFixed(1)} dB under battle`);
  for (const s of Object.values(STINGS)) assert.equal(s.volume, TRACKS.battle.volume);
});
