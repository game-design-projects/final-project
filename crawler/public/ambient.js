// The dungeon's background music: one pre-rendered ambient track (ambient.m4a), looped seamlessly.
// The file holds one loop plus a repeat of its first second, so we loop inside it and the
// encoder's padding at the file's edges is never heard. Rendered by scripts/build-ambient.py.

const LOOP_START = 0.25;
const LOOP_SECONDS = 96;
const FADE_IN = 4;

export class Ambient {
  constructor(url = "ambient.m4a", volume = 0.9) {
    this.url = url;
    this.volume = volume;
    this.ctx = null;
    this.on = false;
  }

  // Must be called from a user gesture (browsers block audio otherwise).
  async start() {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.gain = this.ctx.createGain();
      this.gain.connect(this.ctx.destination);
    }
    // Resume right away, while still inside the click/keypress (Safari refuses after an await)
    const resumed = this.ctx.resume();
    this.on = true;
    this.loading ??= this.load();
    await Promise.all([this.loading, resumed]);
    if (!this.on) this.ctx.suspend(); // switched off while the track was still downloading
  }

  async load() {
    const data = await (await fetch(this.url)).arrayBuffer();
    const src = this.ctx.createBufferSource();
    src.buffer = await this.ctx.decodeAudioData(data);
    src.loop = true;
    src.loopStart = LOOP_START;
    src.loopEnd = LOOP_START + LOOP_SECONDS;
    src.connect(this.gain);
    const now = this.ctx.currentTime;
    this.gain.gain.setValueAtTime(0, now);
    this.gain.gain.linearRampToValueAtTime(this.volume, now + FADE_IN);
    src.start(now, LOOP_START);
  }

  stop() {
    this.on = false;
    this.ctx?.suspend();
  }

  toggle() {
    return this.on ? (this.stop(), false) : this.start().then(() => true);
  }
}
