// The game's music. Two pre-rendered loops crossfaded by mood, plus one-shot stings for good moments.
//   explore: ambient.m4a, the dark dungeon ambient (scripts/build-ambient.py). It does not play nonstop:
//            a stretch of music, then a stretch of quiet, like a mood that comes and goes.
//   battle:  battle.m4a, a bright, driving 8-bit fight loop (scripts/build-battle.py)
//   stings:  fanfare.m4a when you go down the stairs, victory.m4a when you win a fight (scripts/build-stings.py)
// Each loop file holds one loop plus a repeat of its first second, so we loop inside it and the
// encoder's padding at the file's edges is never heard.

const LOOP_START = 0.25;
export const TRACKS = {
  // volume evens out the renders: the 8-bit cues are mastered ~10 dB hotter than the ambient
  explore: { url: "ambient.m4a", loopSeconds: 96, volume: 0.9 },
  battle: { url: "battle.m4a", loopSeconds: (16 * 8 * 30) / 152, volume: 0.35 },
};
export const STINGS = {
  fanfare: { url: "fanfare.m4a", volume: 0.4 },
  victory: { url: "victory.m4a", volume: 0.35 },
};
// Seconds to fade a track in or out. A fight cuts in fast; the dungeon creeps back slowly.
export const FADES = { battle: { in: 0.35, out: 1.2 }, explore: { in: 6, out: 6 } };
// The ambient's rhythm while exploring, in seconds: play a while, rest a while
export const PACE = {
  play: [80, 110],
  rest: [60, 120],
  afterFight: 10, // quiet after a fight before the ambient may return
  afterSting: 20, // quiet after a fanfare: let the good news ring
};
const FIRST_FADE_IN = 4;

export class Ambient {
  constructor({ tracks = TRACKS, stings = STINGS, timer = globalThis, random = Math.random } = {}) {
    this.tracks = tracks;
    this.stings = stings;
    this.timer = timer; // setTimeout/clearTimeout, injectable for tests
    this.random = random;
    this.ctx = null;
    this.on = false;
    this.mood = "explore";
    this.buffers = {};
    this.voices = {}; // track -> { src, gain } while playing
    this.next = null; // the pending explore play/rest switch
  }

  // Must be called from a user gesture (browsers block audio otherwise).
  async start() {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.master = this.ctx.createGain();
      this.master.connect(this.ctx.destination);
    }
    // Resume right away, while still inside the click/keypress (Safari refuses after an await)
    const resumed = this.ctx.resume();
    this.on = true;
    // Load the ambient first so it starts quickly; the rest load behind it
    this.loading ??= this.load("explore").then(() => {
      if (this.mood === "explore") this.exploreIn(FIRST_FADE_IN);
      else this.play(this.mood, FADES[this.mood].in);
      for (const name of ["battle", ...Object.keys(this.stings)]) this.load(name).catch((err) => console.warn(`music: ${name}`, err));
    });
    await Promise.all([this.loading, resumed]);
    if (!this.on) this.ctx.suspend(); // switched off while the track was still downloading
  }

  async load(name) {
    if (!this.buffers[name]) {
      const url = (this.tracks[name] ?? this.stings[name]).url;
      const data = await (await fetch(url)).arrayBuffer();
      this.buffers[name] = await this.ctx.decodeAudioData(data);
    }
    return this.buffers[name];
  }

  // Switch between "explore" and "battle". Safe to call any time, with music on or off, loaded or not.
  setMood(mood) {
    if (mood === this.mood || !this.tracks[mood]) return;
    const was = this.mood;
    this.mood = mood;
    console.debug(`music: ${was} -> ${mood}`);
    if (!this.ctx) return; // not started yet: start() plays the current mood
    this.fadeOut(was, FADES[was].out);
    if (mood === "explore") return this.restFor(PACE.afterFight);
    this.cancelNext();
    if (this.buffers[mood]) this.play(mood, FADES[mood].in);
    else this.load(mood).then(() => this.mood === mood && this.play(mood, FADES[mood].in)).catch((err) => console.warn("music:", err));
  }

  // A one-shot cue for good news. Whatever is playing gets out of its way, then quiet for a while.
  sting(name) {
    if (!this.ctx || !this.buffers[name]) return console.debug(`music: sting ${name} skipped (not loaded)`);
    console.debug(`music: sting ${name}`);
    const now = this.ctx.currentTime;
    for (const track of Object.keys(this.voices)) this.fadeOut(track, 0.4);
    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(this.stings[name].volume, now);
    gain.connect(this.master);
    const src = this.ctx.createBufferSource();
    src.buffer = this.buffers[name];
    src.connect(gain);
    src.start(now + 0.15);
    if (this.mood === "explore") this.restFor(this.buffers[name].duration + PACE.afterSting);
  }

  // ---- the explore rhythm: play a stretch, rest a stretch

  exploreIn(fade = FADES.explore.in) {
    if (this.mood !== "explore") return;
    this.play("explore", fade);
    this.schedule(this.between(PACE.play), () => {
      this.fadeOut("explore", FADES.explore.out);
      this.restFor(this.between(PACE.rest));
    });
  }

  restFor(seconds) {
    this.schedule(seconds, () => this.exploreIn());
  }

  schedule(seconds, fn) {
    this.cancelNext();
    this.next = this.timer.setTimeout(() => {
      this.next = null;
      fn();
    }, seconds * 1000);
  }

  cancelNext() {
    if (this.next) this.timer.clearTimeout(this.next);
    this.next = null;
  }

  between([lo, hi]) {
    return lo + (hi - lo) * this.random();
  }

  // ---- voices

  play(track, fade) {
    const buffer = this.buffers[track];
    if (!buffer) return;
    const now = this.ctx.currentTime;
    const { volume, loopSeconds } = this.tracks[track];
    let v = this.voices[track];
    // The ambient keeps its place while silent and comes back from there; a fight always starts at bar one
    if (v && track === "battle") {
      v.src.stop(now + fade);
      v = null;
    }
    if (!v) {
      const gain = this.ctx.createGain();
      gain.gain.setValueAtTime(0, now);
      gain.connect(this.master);
      const src = this.ctx.createBufferSource();
      src.buffer = buffer;
      src.loop = true;
      src.loopStart = LOOP_START;
      src.loopEnd = LOOP_START + loopSeconds;
      src.connect(gain);
      src.start(now, LOOP_START);
      v = this.voices[track] = { src, gain };
    }
    v.gain.gain.cancelScheduledValues(now);
    v.gain.gain.setValueAtTime(v.gain.gain.value, now);
    v.gain.gain.linearRampToValueAtTime(volume, now + fade);
  }

  fadeOut(track, fade) {
    const v = this.voices[track];
    if (!v) return;
    const now = this.ctx.currentTime;
    v.gain.gain.cancelScheduledValues(now);
    v.gain.gain.setValueAtTime(v.gain.gain.value, now);
    v.gain.gain.linearRampToValueAtTime(0, now + fade);
    // The fight track stops once silent; the ambient idles at zero so it can come back where it was
    if (track === "battle") {
      v.src.stop(now + fade + 0.05);
      delete this.voices[track];
    }
  }

  stop() {
    this.on = false;
    this.ctx?.suspend();
  }

  toggle() {
    return this.on ? (this.stop(), false) : this.start().then(() => true);
  }
}
