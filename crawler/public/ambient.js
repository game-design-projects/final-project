// The game's music. Two pre-rendered loops crossfaded by mood, plus one-shot stings for good moments.
// All of it is baroque, played by one sampled band (harpsichord, organ, strings, choir, music box, bells,
// kettle drums) in one stone hall, and all of it is built on the game's own melody.
//   explore: ambient.m4a, a slow passacaglia in D minor (scripts/build-ambient.py). It does not play
//            nonstop: a stretch of music, then a stretch of quiet, like a mood that comes and goes.
//   battle:  battle-*.m4a, four toccata-style fight loops in different keys, tempos, leads and grooves
//            (scripts/build-battle.py). A fight picks one at random (never the last one) and keeps it for
//            the whole fight: changing tune mid-fight was jarring.
//   stings:  fanfare.m4a when you go down the stairs, victory.m4a when you win a fight (scripts/build-stings.py)
// Each loop file holds one loop plus a repeat of its first second, so we loop inside it and the
// encoder's padding at the file's edges is never heard.

const LOOP_START = 0.25;
export const TRACKS = {
  // The renders are mastered to -19 dBFS RMS (explore) and -17 dBFS RMS (fights and stings). These
  // volumes put a fight at about -19.5 dB, as loud against the sound effects as the music it replaced,
  // and the exploring music about 2.6 dB under it.
  explore: { url: "ambient.m4a", bpm: 64, loopSeconds: 112.5, volume: 0.7 }, // 40 bars of 3/4 at 64 BPM
  battle: {
    volume: 0.75,
    // 16 bars of 4/4 at each tempo: 3840 / BPM seconds
    variants: [
      { name: "toccata", url: "battle-toccata.m4a", bpm: 132, loopSeconds: 3840 / 132 },
      { name: "charge", url: "battle-charge.m4a", bpm: 126, loopSeconds: 3840 / 126 },
      { name: "crusade", url: "battle-crusade.m4a", bpm: 112, loopSeconds: 3840 / 112 },
      { name: "gallop", url: "battle-gallop.m4a", bpm: 120, loopSeconds: 3840 / 120 },
    ],
  },
};
// Under a monster's spoken line the music drops to this share of its level, quickly, and comes back slowly
export const DUCK = { level: 0.25, down: 0.15, up: 0.6 };
export const STINGS = {
  fanfare: { url: "fanfare.m4a", volume: 0.75 },
  victory: { url: "victory.m4a", volume: 0.75 },
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

  // Play through a context the effects share (mix.js), into `destination`. Call before start(). The music then
  // switches off by muting itself, since suspending the context would silence the effects too.
  attach(ctx, destination) {
    this.ctx = ctx;
    this.shared = true;
    this.master = ctx.createGain(); // speech ducking (duck)
    this.mute = ctx.createGain(); // the P switch
    this.mute.gain.setValueAtTime(0, ctx.currentTime);
    this.master.connect(this.mute);
    this.mute.connect(destination);
  }

  setMuted(muted) {
    const g = this.mute.gain;
    const now = this.ctx.currentTime;
    g.cancelScheduledValues(now);
    g.setValueAtTime(g.value, now);
    g.linearRampToValueAtTime(muted ? 0 : 1, now + 0.12);
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
    if (this.shared) this.setMuted(false);
    // Load the ambient first so it starts quickly; the rest load behind it
    this.loading ??= this.load("explore").then(() => {
      if (this.mood === "explore") this.exploreIn(FIRST_FADE_IN);
      else this.battleIn(FADES.battle.in);
      const rest = [...this.tracks.battle.variants.map((v) => `battle:${v.name}`), ...Object.keys(this.stings)];
      for (const name of rest) this.load(name).catch((err) => console.warn(`music: ${name}`, err));
    });
    await Promise.all([this.loading, resumed]);
    if (!this.on) this.silence(); // switched off while the track was still downloading
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

  // ---- battle: a random loop per fight, kept for the whole fight

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
    this.fadeOut("battle", fade); // a loop still fading from the last fight, if any
    this.startLoop("battle", this.buffers[key], v.loopSeconds, this.tracks.battle.volume, fade, v.bpm);
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
    const { volume, loopSeconds, bpm } = this.tracks[track];
    this.startLoop(track, this.buffers[track], loopSeconds, volume, fade, bpm);
  }

  startLoop(track, buffer, loopSeconds, volume, fade, bpm) {
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
      // Beat k of the loop sounds at origin + k * 60 / bpm (the loop is whole bars, so the grid survives the wrap)
      v = this.voices[track] = { src, gain, bpm, origin: now - LOOP_START };
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

  // Make room for speech (text to speech can't be turned up, so everything else turns down)
  duck(on) {
    if (!this.master) return;
    const g = this.master.gain;
    const now = this.ctx.currentTime;
    g.cancelScheduledValues(now);
    g.setValueAtTime(g.value, now);
    g.linearRampToValueAtTime(on ? DUCK.level : 1, now + (on ? DUCK.down : DUCK.up));
  }

  // The beat grid of what is playing, for anything that should land on the music's beat (the heartbeat):
  // { bpm, origin } with a beat on `origin`, or null when no loop is running.
  beatClock() {
    const v = this.voices[this.mood === "battle" ? "battle" : "explore"];
    return v?.bpm ? { bpm: v.bpm, origin: v.origin } : null;
  }

  stop() {
    this.on = false;
    this.silence();
  }

  silence() {
    if (this.shared) this.setMuted(true);
    else this.ctx?.suspend();
  }

  toggle() {
    return this.on ? (this.stop(), false) : this.start().then(() => true);
  }
}
