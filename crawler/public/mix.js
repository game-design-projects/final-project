// The mixing desk: one AudioContext for the music and the effects, so they share a clock (a heartbeat lands on
// the music's beat) and can react to each other (big hits punch through the music).
//
//   music (ambient.js) ─▶ impact duck ─▶ danger low-pass ─▶ music bus ─┐
//   effects (sfx.js)   ─────────────────────────────────▶ sfx bus  ───┼─▶ limiter ─▶ speakers
//   heartbeat (here)   ─────────────────────────────────▶ sfx bus  ───┘
//
// Danger (juice.js dangerOf) closes the music's low-pass and starts a heartbeat on the music's beat grid:
// on every other beat while the party is hurt, on every beat when someone is about to die.

export const DANGER = {
  openHz: 20000, // the music's low-pass with the party healthy: wide open
  closedHz: 650, // ...and with the party about to fall: muffled, as if heard through your own pulse
  musicDip: 0.3, // the music also drops by this share at full danger, so the heartbeat sits on top
  heartFrom: 0.35, // the heartbeat starts at this danger...
  heartFast: 0.75, // ...and doubles its pace from here
  lag: 0.25, // seconds for the filter to follow (setTargetAtTime time constant)
};
// A big hit dips the music this far for a moment, then lets it back
export const IMPACT = { crit: 0.45, kill: 0.4, bossKill: 0.6, hurt: 0.3, attack: 0.012, release: 0.35 };
export const RESTING_BPM = 64; // the heartbeat's pace when no loop is playing (the explore loop's tempo)

export class Mixer {
  constructor(ctx) {
    this.ctx = ctx;
    const now = ctx.currentTime;
    this.limiter = ctx.createDynamicsCompressor();
    this.limiter.threshold.setValueAtTime(-6, now);
    this.limiter.knee.setValueAtTime(4, now);
    this.limiter.ratio.setValueAtTime(12, now);
    this.limiter.attack.setValueAtTime(0.003, now);
    this.limiter.release.setValueAtTime(0.2, now);
    this.limiter.connect(ctx.destination);
    this.musicBus = ctx.createGain();
    this.musicBus.connect(this.limiter);
    this.lowpass = ctx.createBiquadFilter();
    this.lowpass.type = "lowpass";
    this.lowpass.frequency.setValueAtTime(DANGER.openHz, now);
    this.lowpass.Q.setValueAtTime(0.9, now);
    this.lowpass.connect(this.musicBus);
    this.impactGain = ctx.createGain();
    this.impactGain.connect(this.lowpass);
    this.music = this.impactGain; // where the music plugs in
    this.sfx = ctx.createGain(); // where the effects plug in
    this.sfx.connect(this.limiter);
    this.danger = 0;
  }

  // 0..1. Cheap to call every frame: only a real change reschedules anything.
  setDanger(x) {
    const d = Math.max(0, Math.min(1, x));
    if (Math.abs(d - this.danger) < 0.01) return;
    this.danger = d;
    const now = this.ctx.currentTime;
    this.lowpass.frequency.setTargetAtTime(cutoffFor(d), now, DANGER.lag);
    this.musicBus.gain.setTargetAtTime(1 - DANGER.musicDip * d, now, DANGER.lag);
  }

  // Dip the music under a big moment so it punches through. `depth` 0..1 is the share taken away.
  impact(depth, at = this.ctx.currentTime) {
    const g = this.impactGain.gain;
    g.cancelScheduledValues(at);
    g.setTargetAtTime(1 - depth, at, IMPACT.attack);
    g.setTargetAtTime(1, at + 0.09, IMPACT.release);
  }
}

// Exponential, as the ear hears pitch: halfway in danger is halfway in octaves
export const cutoffFor = (d) => DANGER.openHz * (DANGER.closedHz / DANGER.openHz) ** d;

// How often the heart beats against the music: null (it doesn't), 2 (every other beat) or 1 (every beat)
export function heartEvery(danger) {
  if (danger >= DANGER.heartFast) return 1;
  if (danger >= DANGER.heartFrom) return 2;
  return null;
}

// Schedules beats a little ahead on the audio clock (the Web Audio lookahead pattern: a coarse timer, exact
// sample times). clock() returns { bpm, origin } (origin = an audio time on which a beat falls) or null to
// use the resting pace. Each beat k fires onBeat(at, k) exactly once.
export class BeatScheduler {
  constructor({ ctx, clock, onBeat, lookahead = 0.2 }) {
    Object.assign(this, { ctx, clock, onBeat, lookahead });
    this.next = null; // the audio time of the next beat to schedule
    this.grid = null;
    this.restOrigin = null;
  }

  tick() {
    const now = this.ctx.currentTime;
    const g = this.clock() ?? { bpm: RESTING_BPM, origin: (this.restOrigin ??= now) };
    const beat = 60 / g.bpm;
    // A new grid (a fight's loop started, or ended): resume from its first beat after now
    if (!this.grid || this.grid.bpm !== g.bpm || Math.abs(this.grid.origin - g.origin) > 1e-6) {
      this.grid = g;
      this.next = g.origin + Math.ceil((now - g.origin) / beat - 1e-9) * beat;
    }
    while (this.next < now + this.lookahead) {
      const k = Math.round((this.next - g.origin) / beat);
      if (this.next >= now - 0.005) this.onBeat(this.next, k);
      this.next += beat;
    }
  }
}
