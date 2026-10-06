// The game's music. Two pre-rendered loops crossfaded by mood, plus one-shot stings for good moments.
//   explore: ambient.m4a, the dark dungeon ambient (scripts/build-ambient.py). It does not play nonstop:
//            a stretch of music, then a stretch of quiet, like a mood that comes and goes.
//   battle:  battle-*.m4a, four bright 8-bit fight loops on the game's melody in different keys, tempos and
//            grooves (scripts/build-battle.py). A fight picks one at random (never the last one), and after
//            two times round it crossfades into another, so no single tune wears out.
//   stings:  fanfare.m4a when you go down the stairs, victory.m4a when you win a fight (scripts/build-stings.py)
// Each loop file holds one loop plus a repeat of its first second, so we loop inside it and the
// encoder's padding at the file's edges is never heard.

const LOOP_START = 0.25;
export const TRACKS = {
  // volume evens out the renders: the 8-bit cues are mastered ~10 dB hotter than the ambient
  explore: { url: "ambient.m4a", loopSeconds: 96, volume: 0.9 },
  battle: {
    volume: 0.35,
    // 16 bars of 8 eighths at each tempo
    variants: [
      { name: "heroic", url: "battle-heroic.m4a", loopSeconds: 3840 / 124 },
      { name: "fury", url: "battle-fury.m4a", loopSeconds: 3840 / 132 },
      { name: "march", url: "battle-march.m4a", loopSeconds: 3840 / 112 },
      { name: "gallop", url: "battle-gallop.m4a", loopSeconds: 3840 / 120 },
    ],
  },
};
// How many times a battle loop goes round before the fight moves on to another
export const BATTLE_LOOPS = 2;
const BATTLE_SWAP_FADE = 1.5;
export const STINGS = {
  fanfare: { url: "fanfare.m4a", volume: 0.4 },
  victory: { url: "victory.m4a", volume: 0.35 },
};
// Seconds to fade a track in or out. A fight cuts in fast and the ambient gets out of its way just as fast
// (underFight), so the two never play together; between stretches of exploring the ambient fades out slowly.
export const FADES = { battle: { in: 0.35, out: 1.2 }, explore: { in: 2, out: 5, underFight: 0.4 } };
// The ambient's rhythm while exploring, in seconds: play a while, rest a while
export const PACE = {
  play: [80, 110],
  rest: [60, 120],
  afterFight: 2, // a breath after a fight before the ambient returns
  afterSting: 4, // let the good news ring a moment
};
const FIRST_FADE_IN = 1.5;

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
    this.next = null; // the pending explore play/rest switch, or battle loop change
    this.battle = null; // the battle variant playing (or about to)
    this.lastBattle = null;
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
      else this.battleIn(FADES.battle.in);
      const rest = [...this.tracks.battle.variants.map((v) => `battle:${v.name}`), ...Object.keys(this.stings)];
      for (const name of rest) this.load(name).catch((err) => console.warn(`music: ${name}`, err));
    });
    await Promise.all([this.loading, resumed]);
    if (!this.on) this.ctx.suspend(); // switched off while the track was still downloading
  }

  // name: "explore", "battle:<variant>", or a sting
  async load(name) {
    if (!this.buffers[name]) {
      const variant = name.startsWith("battle:") && this.tracks.battle.variants.find((v) => `battle:${v.name}` === name);
      const url = (variant || this.tracks[name] || this.stings[name]).url;
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
    this.fadeOut(was, mood === "battle" ? FADES.explore.underFight : FADES[was].out);
    if (mood === "explore") return this.restFor(PACE.afterFight);
    this.cancelNext();
    this.battleIn(FADES.battle.in);
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

  // ---- battle: a random loop per fight, moving on to another after BATTLE_LOOPS times round

  pickBattle() {
    const all = this.tracks.battle.variants;
    const fresh = all.filter((v) => v !== this.lastBattle);
    // Prefer one that's already loaded, so the fight's music starts at once
    const ready = fresh.filter((v) => this.buffers[`battle:${v.name}`]);
    const pool = ready.length ? ready : fresh.length ? fresh : all;
    return pool[Math.floor(this.random() * pool.length)];
  }

  battleIn(fade, v = this.pickBattle()) {
    this.battle = this.lastBattle = v;
    const key = `battle:${v.name}`;
    if (!this.buffers[key]) {
      this.load(key)
        .then(() => this.mood === "battle" && this.battle === v && this.battleIn(fade, v))
        .catch((err) => console.warn("music:", err));
      return;
    }
    console.debug(`music: battle loop ${v.name}`);
    this.fadeOut("battle", fade); // the loop it replaces, if any
    this.startLoop("battle", this.buffers[key], v.loopSeconds, this.tracks.battle.volume, fade);
    this.schedule(v.loopSeconds * BATTLE_LOOPS, () => this.mood === "battle" && this.battleIn(BATTLE_SWAP_FADE));
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

  // The ambient keeps its place while silent and comes back from there
  play(track, fade) {
    if (!this.buffers[track]) return;
    const { volume, loopSeconds } = this.tracks[track];
    this.startLoop(track, this.buffers[track], loopSeconds, volume, fade);
  }

  startLoop(track, buffer, loopSeconds, volume, fade) {
    const now = this.ctx.currentTime;
    let v = this.voices[track];
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
    // A battle loop stops once silent (each fight starts a loop from bar one); the ambient idles at zero
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
