// The game's music: two pre-rendered loops, crossfaded by mood.
//   explore: ambient.m4a, the dark dungeon ambient (scripts/build-ambient.py)
//   battle:  battle.m4a, a bright, driving 8-bit fight loop (scripts/build-battle.py)
// Each file holds one loop plus a repeat of its first second, so we loop inside it and the
// encoder's padding at the file's edges is never heard.

const LOOP_START = 0.25;
export const TRACKS = {
  // volume evens out the two renders: the battle loop is mastered ~10 dB hotter than the ambient
  explore: { url: "ambient.m4a", loopSeconds: 96, volume: 0.9 },
  battle: { url: "battle.m4a", loopSeconds: (16 * 8 * 30) / 152, volume: 0.35 },
};
// Seconds to fade a track in or out. A fight cuts in fast; the dungeon creeps back slowly.
export const FADES = { battle: { in: 0.35, out: 1.2 }, explore: { in: 3.5, out: 0.5 } };
const FIRST_FADE_IN = 4;

export class Ambient {
  constructor(tracks = TRACKS) {
    this.tracks = tracks;
    this.ctx = null;
    this.on = false;
    this.mood = "explore";
    this.buffers = {};
    this.voices = {}; // mood -> { src, gain } while playing
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
    // Load the ambient first so it starts quickly; the fight track loads behind it
    this.loading ??= this.load("explore").then(() => {
      this.play(this.mood, FIRST_FADE_IN);
      this.load("battle").catch((err) => console.warn("music: battle track", err));
    });
    await Promise.all([this.loading, resumed]);
    if (!this.on) this.ctx.suspend(); // switched off while the track was still downloading
  }

  async load(mood) {
    if (!this.buffers[mood]) {
      const data = await (await fetch(this.tracks[mood].url)).arrayBuffer();
      this.buffers[mood] = await this.ctx.decodeAudioData(data);
    }
    return this.buffers[mood];
  }

  // Switch between "explore" and "battle". Safe to call any time, with music on or off, loaded or not.
  setMood(mood) {
    if (mood === this.mood || !this.tracks[mood]) return;
    const was = this.mood;
    this.mood = mood;
    console.debug(`music: ${was} -> ${mood}`);
    if (!this.ctx) return; // not started yet: start() plays the current mood
    this.fadeOut(was, FADES[was].out);
    if (this.buffers[mood]) this.play(mood, FADES[mood].in);
    else this.load(mood).then(() => this.mood === mood && this.play(mood, FADES[mood].in)).catch((err) => console.warn("music:", err));
  }

  play(mood, fade) {
    const buffer = this.buffers[mood];
    if (!buffer) return;
    const now = this.ctx.currentTime;
    const { volume, loopSeconds } = this.tracks[mood];
    let v = this.voices[mood];
    // The ambient keeps its place under a fight and fades back in from there; a fight always starts at bar one
    if (v && mood === "battle") {
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
      v = this.voices[mood] = { src, gain };
    }
    v.gain.gain.cancelScheduledValues(now);
    v.gain.gain.setValueAtTime(v.gain.gain.value, now);
    v.gain.gain.linearRampToValueAtTime(volume, now + fade);
  }

  fadeOut(mood, fade) {
    const v = this.voices[mood];
    if (!v) return;
    const now = this.ctx.currentTime;
    v.gain.gain.cancelScheduledValues(now);
    v.gain.gain.setValueAtTime(v.gain.gain.value, now);
    v.gain.gain.linearRampToValueAtTime(0, now + fade);
    // The fight track stops once silent; the ambient idles at zero so it can come back where it was
    if (mood === "battle") {
      v.src.stop(now + fade + 0.05);
      delete this.voices[mood];
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
