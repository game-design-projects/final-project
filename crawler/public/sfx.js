// Sound effects, synthesised live with WebAudio (no files): hits, crits, spells, kills, dice, monster voices, the Roll of Fate.
// Every sound is built from a few primitives: pitched tones with envelopes, filtered noise bursts, and a formant "vocal".
import { shoutPlan } from "./shout.js";

const NOTE = (n) => 440 * 2 ** ((n - 69) / 12);

// Vowel formants (F1, F2, F3 in Hz) for a mid-sized throat; `size` scales them.
const VOWELS = {
  ah: [730, 1090, 2440],
  aw: [660, 1000, 2500],
  oh: [570, 840, 2410],
  uh: [520, 1190, 2390],
  eh: [530, 1840, 2480],
  ee: [270, 2290, 3010],
  oo: [300, 870, 2240],
};
const FORMANT_GAIN = [1, 0.6, 0.3];
const VOICE_GAIN = 3; // narrow band-pass filters take most of the buzz out; this puts voices on par with the other effects
const NOISE_VOICE = 4; // ...and white noise loses even more through them

export class Sfx {
  constructor(volume = 0.55) {
    this.volume = volume;
    this.ctx = null;
    this.on = true;
    this.lag = 0; // seconds: sounds played right now wait this long (a die's result lands with the die)
    this.lastShout = new Map();
  }

  // Call from a key press or click (browsers block audio otherwise). A test can pass its own context.
  init(ctx) {
    if (!this.ctx) {
      this.ctx = ctx ?? new AudioContext();
      this.out = this.ctx.createGain();
      this.out.gain.value = this.volume;
      const comp = this.ctx.createDynamicsCompressor();
      comp.threshold.value = -14;
      comp.ratio.value = 4;
      this.out.connect(comp).connect(this.ctx.destination);
      // A short room, so effects sit in the dungeon instead of in your ear
      this.room = this.ctx.createConvolver();
      this.room.buffer = this.impulse(1.1, 3);
      const wet = this.ctx.createGain();
      wet.gain.value = 0.22;
      this.room.connect(wet).connect(this.out);
      const len = this.ctx.sampleRate;
      this.noiseBuf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const ch = this.noiseBuf.getChannelData(0);
      for (let i = 0; i < len; i++) ch[i] = Math.random() * 2 - 1;
    }
    this.ctx.resume().catch(() => {}); // an OfflineAudioContext (tests) refuses
  }

  impulse(seconds, decay) {
    const rate = this.ctx.sampleRate;
    const n = Math.floor(rate * seconds);
    const buf = this.ctx.createBuffer(2, n, rate);
    for (let c = 0; c < 2; c++) {
      const data = buf.getChannelData(c);
      for (let i = 0; i < n; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / n) ** decay;
    }
    return buf;
  }

  play(name, opt = {}) {
    if (!this.on || !this.ctx || this.ctx.state !== "running") return;
    try {
      SOUNDS[name]?.(this, this.ctx.currentTime + 0.01 + (opt.delay ?? this.lag), opt);
    } catch (err) {
      console.warn("sfx", name, err);
    }
  }

  toggle() {
    this.on = !this.on;
    return this.on;
  }

  // A monster speaks: pick a voice from the line's wording (RAAH, *hisses*, blorp...) and the species, and play it.
  // At most one shout per `key` (the monster) every 0.8s, and none while sound is off. Returns the plan played, or null.
  shout(line, species, { key = species, boss = false } = {}) {
    if (!this.on || !this.ctx || this.ctx.state !== "running") return null;
    const plan = shoutPlan(line, species, { boss });
    if (!plan) return null;
    const now = this.ctx.currentTime;
    if (now - (this.lastShout.get(key) ?? -9) < 0.8) return null;
    this.lastShout.set(key, now);
    this.play(`voice_${plan.kind}`, plan);
    return plan;
  }

  // An output node: dry to the mix, plus some into the room.
  bus(at, room = 0.4) {
    const g = this.ctx.createGain();
    g.connect(this.out);
    if (room) {
      const s = this.ctx.createGain();
      s.gain.value = room;
      g.connect(s).connect(this.room);
    }
    return g;
  }

  // A pitched tone gliding from f0 to f1, with a fast attack and exponential release.
  tone(at, { type = "sine", f0, f1 = f0, dur = 0.2, vol = 0.3, attack = 0.004, lp, room = 0.4, vibrato }) {
    const c = this.ctx;
    const o = c.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(f0, at);
    if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), at + dur);
    if (vibrato) {
      const lfo = c.createOscillator();
      const depth = c.createGain();
      lfo.frequency.value = vibrato.rate;
      depth.gain.value = vibrato.depth;
      lfo.connect(depth).connect(o.frequency);
      lfo.start(at);
      lfo.stop(at + dur + 0.05);
    }
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(vol, at + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    let node = o.connect(g);
    if (lp) {
      const f = c.createBiquadFilter();
      f.type = "lowpass";
      f.frequency.setValueAtTime(lp[0], at);
      if (lp[1]) f.frequency.exponentialRampToValueAtTime(lp[1], at + dur);
      node = node.connect(f);
    }
    node.connect(this.bus(at, room));
    o.start(at);
    o.stop(at + dur + 0.05);
  }

  // Filtered noise: hits, whooshes, fire, crackle.
  noise(at, { dur = 0.15, vol = 0.3, type = "bandpass", f0 = 1000, f1 = f0, q = 1, attack = 0.002, room = 0.4 }) {
    const c = this.ctx;
    const src = c.createBufferSource();
    src.buffer = this.noiseBuf;
    src.loop = true;
    const f = c.createBiquadFilter();
    f.type = type;
    f.Q.value = q;
    f.frequency.setValueAtTime(f0, at);
    if (f1 !== f0) f.frequency.exponentialRampToValueAtTime(Math.max(20, f1), at + dur);
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(vol, at + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    src.connect(f).connect(g).connect(this.bus(at, room));
    src.start(at, Math.random() * 0.5);
    src.stop(at + dur + 0.05);
  }

  // A voice: a buzzing (and, with `rasp`, breathy) source pushed through three vowel-formant filters.
  // vowel: one name, or [from, to] to glide between two; size: <1 = bigger throat (formants drop); rasp 0..1 = noise mix.
  vocal(at, { f0, f1 = f0, dur = 0.3, vol = 0.3, vowel = ["ah"], size = 1, rasp = 0.2, attack = 0.02, vibrato, tremolo, room = 0.3, q = 8 }) {
    const c = this.ctx;
    const [va, vb = va] = [].concat(vowel).map((v) => VOWELS[v] ?? VOWELS.ah);
    const src = c.createGain();
    if (rasp < 1) {
      const o = c.createOscillator();
      o.type = "sawtooth";
      o.frequency.setValueAtTime(f0, at);
      if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), at + dur);
      if (vibrato) {
        const lfo = c.createOscillator();
        const depth = c.createGain();
        lfo.frequency.value = vibrato.rate;
        depth.gain.value = vibrato.depth;
        lfo.connect(depth).connect(o.frequency);
        lfo.start(at);
        lfo.stop(at + dur + 0.05);
      }
      const g = c.createGain();
      g.gain.value = 1 - rasp * 0.7;
      o.connect(g).connect(src);
      o.start(at);
      o.stop(at + dur + 0.05);
    }
    if (rasp > 0) {
      const n = c.createBufferSource();
      n.buffer = this.noiseBuf;
      n.loop = true;
      const g = c.createGain();
      g.gain.value = rasp * NOISE_VOICE;
      n.connect(g).connect(src);
      n.start(at, Math.random() * 0.5);
      n.stop(at + dur + 0.05);
    }
    const sum = c.createGain();
    va.forEach((fa, i) => {
      const f = c.createBiquadFilter();
      f.type = "bandpass";
      f.Q.value = q;
      f.frequency.setValueAtTime(fa * size, at);
      if (vb[i] !== fa) f.frequency.exponentialRampToValueAtTime(vb[i] * size, at + dur);
      const g = c.createGain();
      g.gain.value = FORMANT_GAIN[i];
      src.connect(f).connect(g).connect(sum);
    });
    const env = c.createGain();
    env.gain.setValueAtTime(0.0001, at);
    env.gain.exponentialRampToValueAtTime(vol * VOICE_GAIN, at + attack);
    env.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    sum.connect(env);
    let out = env;
    if (tremolo) {
      const am = c.createGain();
      am.gain.value = 1 - tremolo.depth / 2;
      const lfo = c.createOscillator();
      const depth = c.createGain();
      lfo.frequency.value = tremolo.rate;
      depth.gain.value = tremolo.depth / 2;
      lfo.connect(depth).connect(am.gain);
      lfo.start(at);
      lfo.stop(at + dur + 0.05);
      env.connect(am);
      out = am;
    }
    out.connect(this.bus(at, room));
  }

  // A quick run of notes (MIDI numbers)
  arp(at, notes, { step = 0.07, type = "triangle", dur = 0.35, vol = 0.18, room = 0.6 } = {}) {
    notes.forEach((n, i) => this.tone(at + i * step, { type, f0: NOTE(n), dur, vol, room }));
  }
}

const SOUNDS = {
  // Combat
  hit(s, t) {
    s.tone(t, { f0: 150, f1: 55, dur: 0.16, vol: 0.55, room: 0.2 });
    s.noise(t, { dur: 0.09, vol: 0.4, f0: 1800, f1: 500, q: 0.8, room: 0.2 });
  },
  crit(s, t) {
    s.tone(t, { f0: 180, f1: 45, dur: 0.25, vol: 0.7, room: 0.3 });
    s.noise(t, { dur: 0.14, vol: 0.55, f0: 3000, f1: 400, q: 0.7, room: 0.3 });
    s.tone(t + 0.02, { type: "square", f0: NOTE(88), dur: 0.22, vol: 0.09, lp: [5000, 1500], room: 0.7 });
    s.tone(t + 0.06, { type: "square", f0: NOTE(95), dur: 0.3, vol: 0.07, lp: [5000, 1500], room: 0.8 });
  },
  miss(s, t) {
    s.noise(t, { dur: 0.2, vol: 0.18, f0: 500, f1: 2600, q: 2.5, attack: 0.05, room: 0.2 });
  },
  hurt(s, t) {
    s.tone(t, { f0: 110, f1: 40, dur: 0.22, vol: 0.6, room: 0.2 });
    s.tone(t, { type: "sawtooth", f0: 90, f1: 60, dur: 0.18, vol: 0.12, lp: [900, 200], room: 0.1 });
    s.noise(t, { dur: 0.12, vol: 0.3, type: "lowpass", f0: 900, f1: 200, room: 0.2 });
  },
  kill(s, t) {
    s.tone(t, { type: "square", f0: 440, f1: 50, dur: 0.5, vol: 0.12, lp: [3000, 300], room: 0.6 });
    s.tone(t, { f0: 120, f1: 30, dur: 0.6, vol: 0.6, room: 0.4 });
    s.noise(t, { dur: 0.35, vol: 0.4, type: "lowpass", f0: 2500, f1: 150, room: 0.5 });
  },
  down(s, t) {
    s.arp(t, [62, 58, 53], { step: 0.16, type: "triangle", dur: 0.5, vol: 0.2 });
    s.tone(t, { f0: 90, f1: 45, dur: 0.5, vol: 0.4 });
  },
  death(s, t) {
    s.tone(t, { f0: NOTE(38), dur: 2.2, vol: 0.35, attack: 0.01, room: 1 });
    s.tone(t, { f0: NOTE(50) * 1.003, dur: 1.8, vol: 0.12, room: 1 });
    s.tone(t, { type: "triangle", f0: NOTE(57), f1: NOTE(45), dur: 1.4, vol: 0.12, room: 1 });
  },
  save(s, t) {
    s.tone(t, { type: "triangle", f0: NOTE(84), dur: 0.25, vol: 0.12, room: 0.6 });
  },

  // Spells
  fire(s, t) {
    s.noise(t, { dur: 0.45, vol: 0.45, type: "lowpass", f0: 400, f1: 3500, q: 3, attack: 0.04, room: 0.4 });
    s.noise(t + 0.15, { dur: 0.4, vol: 0.3, type: "lowpass", f0: 3000, f1: 300, q: 2, room: 0.5 });
    s.tone(t, { type: "sawtooth", f0: 70, f1: 120, dur: 0.4, vol: 0.1, lp: [600, 1500], room: 0.3 });
  },
  fireball(s, t) {
    s.noise(t, { dur: 0.3, vol: 0.3, f0: 600, f1: 3000, q: 4, attack: 0.2, room: 0.3 });
    s.tone(t + 0.3, { f0: 90, f1: 28, dur: 1.1, vol: 0.8, room: 0.8 });
    s.noise(t + 0.3, { dur: 1.2, vol: 0.6, type: "lowpass", f0: 4000, f1: 120, q: 0.5, room: 0.8 });
  },
  missile(s, t) {
    for (let i = 0; i < 3; i++) s.tone(t + i * 0.09, { type: "square", f0: 2200, f1: 500, dur: 0.12, vol: 0.08, lp: [6000, 1200], room: 0.6 });
  },
  holy(s, t) {
    [76, 83, 88].forEach((n, i) => s.tone(t + i * 0.03, { f0: NOTE(n), dur: 0.9, vol: 0.12, attack: 0.05, room: 1, vibrato: { rate: 6, depth: 4 } }));
  },
  sleep(s, t) {
    [81, 77, 74, 69].forEach((n, i) => s.tone(t + i * 0.15, { f0: NOTE(n), dur: 0.6, vol: 0.12, attack: 0.04, room: 1 }));
  },
  hold(s, t) {
    s.tone(t, { type: "square", f0: 110, dur: 0.8, vol: 0.08, lp: [700, 300], vibrato: { rate: 12, depth: 20 }, room: 0.6 });
    s.tone(t, { f0: NOTE(83), f1: NOTE(71), dur: 0.8, vol: 0.06, room: 0.8 });
  },
  heal(s, t) {
    s.arp(t, [72, 76, 79, 84, 88], { step: 0.06, type: "sine", dur: 0.6, vol: 0.13 });
  },
  revive(s, t) {
    s.arp(t, [60, 67, 72, 76, 79, 84, 91], { step: 0.09, type: "triangle", dur: 1, vol: 0.13 });
    s.tone(t, { f0: NOTE(48), dur: 1.6, vol: 0.2, attack: 0.2, room: 1 });
  },
  buff(s, t) {
    [72, 79, 84].forEach((n, i) => s.tone(t + i * 0.05, { type: "triangle", f0: NOTE(n), dur: 0.7, vol: 0.1, attack: 0.08, room: 1, vibrato: { rate: 5, depth: 3 } }));
  },

  // Talking and feelings
  // A die in the air: five quick clacks in the ~130ms before it lands
  dice(s, t) {
    for (let i = 0; i < 5; i++) {
      const at = t + i * 0.026 + Math.random() * 0.008;
      s.noise(at, { dur: 0.022, vol: 0.4 - i * 0.04, type: "bandpass", f0: 2200 + Math.random() * 2600, q: 2.5, attack: 0.001, room: 0.15 });
      s.tone(at, { type: "square", f0: 380 + Math.random() * 420, f1: 200, dur: 0.02, vol: 0.1, lp: [2500], attack: 0.001, room: 0.1 });
    }
  },
  // ...and the slam. tier: "crit" (natural 20) rings gold, "fumble" (natural 1) cracks and sinks.
  diceLand(s, t, o = {}) {
    s.tone(t, { f0: 170, f1: 60, dur: 0.09, vol: 0.5, room: 0.2 });
    s.noise(t, { dur: 0.05, vol: 0.3, f0: 2600, f1: 900, q: 1, room: 0.2 });
    if (o.tier === "crit") {
      s.arp(t + 0.02, [84, 91, 96], { step: 0.05, type: "triangle", dur: 0.55, vol: 0.1, room: 0.7 });
      s.noise(t, { dur: 0.3, vol: 0.1, type: "highpass", f0: 6500, q: 0.5, room: 0.5 });
    } else if (o.tier === "fumble") {
      s.tone(t, { type: "sawtooth", f0: 140, f1: 45, dur: 0.35, vol: 0.2, lp: [800, 150], room: 0.3 });
      s.noise(t + 0.02, { dur: 0.15, vol: 0.3, type: "lowpass", f0: 1200, f1: 150, room: 0.3 });
    }
  },

  // Monster voices (see shout.js for which one a line gets). p = { f0, size, rasp, wet, vol, syll }.
  // Big throats (size < 1) hold their sounds longer.
  voice_roar(s, t, p) {
    const dur = 0.42 * Math.min(1.8, 1 / Math.sqrt(p.size));
    s.vocal(t, { f0: p.f0 * 1.2, f1: p.f0 * 0.75, dur, vol: 0.55 * p.vol, vowel: ["uh", "aw"], size: p.size, rasp: Math.min(1, p.rasp + 0.3), attack: 0.035, vibrato: { rate: 24, depth: p.f0 * 0.05 }, tremolo: { rate: 38, depth: 0.45 }, room: 0.5 });
    s.noise(t, { dur: dur * 0.8, vol: 0.14 * p.vol, f0: 900 * p.size, f1: 350 * p.size, q: 0.8, attack: 0.04, room: 0.4 });
    s.tone(t, { f0: Math.max(48, p.f0 * 0.5), f1: Math.max(40, p.f0 * 0.35), dur, vol: 0.18 * p.vol, attack: 0.03, room: 0.4 });
  },
  voice_bark(s, t, p) {
    const n = Math.max(1, Math.min(3, Math.ceil(p.syll / 2)));
    const gap = 0.17 / Math.sqrt(p.size);
    for (let i = 0; i < n; i++)
      s.vocal(t + i * gap, { f0: p.f0 * (1.25 - 0.1 * i), f1: p.f0 * 0.9, dur: 0.14 / Math.sqrt(p.size), vol: (0.75 * p.vol) / Math.sqrt(p.size), vowel: ["eh", "ah"], size: p.size, rasp: p.rasp, attack: 0.012, room: 0.35 });
  },
  voice_grunt(s, t, p) {
    const dur = 0.16 / Math.sqrt(p.size);
    s.vocal(t, { f0: p.f0, f1: p.f0 * 0.72, dur, vol: (0.8 * p.vol) / Math.sqrt(p.size), vowel: ["uh", "oh"], size: p.size, rasp: Math.min(1, p.rasp + 0.3), attack: 0.015, room: 0.3 });
    s.noise(t, { dur: 0.06, vol: 0.1 * p.vol, type: "lowpass", f0: 700, f1: 250, room: 0.2 });
  },
  voice_growl(s, t, p) {
    const dur = 0.7 * Math.min(1.8, 1 / Math.sqrt(p.size));
    s.vocal(t, { f0: p.f0 * 0.95, f1: p.f0 * 0.8, dur, vol: 0.5 * p.vol, vowel: ["oh", "uh"], size: p.size, rasp: Math.min(1, p.rasp + 0.3), attack: 0.08, tremolo: { rate: 28, depth: 0.7 }, vibrato: { rate: 9, depth: p.f0 * 0.03 }, room: 0.4 });
  },
  voice_hiss(s, t, p) {
    const dur = 0.5;
    const top = 0.8 + 0.2 * Math.min(1, p.size); // bigger snakes hiss lower
    s.noise(t, { dur, vol: 0.3 * p.vol, type: "highpass", f0: 3200 * top, f1: 2800 * top, attack: 0.06, room: 0.3 });
    s.noise(t, { dur, vol: 0.2 * p.vol, f0: 5500 * top, f1: 4500 * top, q: 1.5, attack: 0.08, room: 0.3 });
  },
  voice_squelch(s, t, p) {
    const n = p.syll > 3 ? 3 : 2;
    for (let i = 0; i < n; i++)
      s.tone(t + i * 0.085, { f0: p.f0 * (0.8 + 0.5 * i) * (0.9 + Math.random() * 0.2), f1: p.f0 * (1.6 + 0.4 * i), dur: 0.11, vol: 0.34 * p.vol, lp: [1800, 700], vibrato: { rate: 32, depth: p.f0 * 0.12 }, room: 0.3 });
    s.tone(t + n * 0.085, { f0: p.f0 * 1.8, f1: p.f0 * 0.6, dur: 0.11, vol: 0.3 * p.vol, lp: [1500, 500], room: 0.3 });
    s.noise(t, { dur: 0.09, vol: 0.12 * p.vol, type: "lowpass", f0: 900, f1: 300, q: 1, room: 0.2 });
  },
  voice_laugh(s, t, p) {
    const n = p.f0 < 90 ? 3 : 4;
    const gap = 0.115 / Math.sqrt(p.size);
    for (let i = 0; i < n; i++) {
      const at = t + i * gap;
      s.noise(at, { dur: 0.05, vol: 0.08 * p.vol, f0: 2500, q: 0.5, room: 0.2 });
      s.vocal(at, { f0: p.f0 * (1.35 - 0.1 * i) * (p.wet ? 1.4 : 1), f1: p.f0 * (1.15 - 0.1 * i), dur: 0.09 / Math.sqrt(p.size), vol: 0.45 * p.vol * (1 - i * 0.1), vowel: p.wet ? ["ee"] : ["ah"], size: p.size, rasp: p.rasp * 0.6, attack: 0.01, room: 0.4 });
    }
  },
  voice_squeal(s, t, p) {
    s.vocal(t, { f0: p.f0 * 1.9, f1: p.f0 * 2.5, dur: 0.32, vol: 0.7 * p.vol, vowel: ["ee"], size: p.size, rasp: 0.15, attack: 0.02, vibrato: { rate: 14, depth: p.f0 * 0.2 }, room: 0.4 });
    if (p.wet) s.tone(t, { f0: p.f0 * 2, f1: p.f0 * 3, dur: 0.28, vol: 0.14 * p.vol, lp: [2500], vibrato: { rate: 20, depth: p.f0 * 0.2 }, room: 0.4 });
  },
  voice_whimper(s, t, p) {
    [0, 0.3].forEach((d, i) =>
      s.vocal(t + d, { f0: p.f0 * 1.5 * (1 - i * 0.1), f1: p.f0 * 1.05 * (1 - i * 0.1), dur: 0.25, vol: 0.32 * p.vol, vowel: ["oo", "ee"], size: p.size, rasp: 0.1, attack: 0.05, vibrato: { rate: 8, depth: p.f0 * 0.07 }, room: 0.5 }),
    );
  },
  voice_sigh(s, t, p) {
    s.noise(t, { dur: 0.6, vol: 0.3 * p.vol, f0: 1100 * p.size, f1: 500 * p.size, q: 0.6, attack: 0.15, room: 0.4 });
    s.tone(t, { type: "triangle", f0: p.f0 * 1.6, f1: p.f0, dur: 0.6, vol: 0.15 * p.vol, attack: 0.1, lp: [700, 300], room: 0.4 });
  },
  voice_rumble(s, t, p) {
    const dur = 0.75 * Math.min(1.8, 1 / Math.sqrt(p.size));
    s.tone(t, { f0: p.f0 * 1.4, f1: p.f0 * 0.8, dur, vol: 0.5 * p.vol, attack: 0.05, room: 0.6 });
    s.tone(t, { type: "sawtooth", f0: p.f0 * 2, f1: p.f0 * 1.4, dur, vol: 0.12 * p.vol, lp: [250, 120], vibrato: { rate: 14, depth: 6 }, room: 0.5 });
    s.noise(t, { dur, vol: 0.3 * p.vol, type: "lowpass", f0: 220, f1: 90, q: 1.2, attack: 0.08, room: 0.5 });
    for (let i = 0; i < 4; i++) s.noise(t + 0.08 + i * 0.12, { dur: 0.1, vol: 0.14 * p.vol, type: "lowpass", f0: 320, f1: 160, room: 0.4 });
  },
  voice_zap(s, t, p) {
    for (let i = 0; i < 6; i++) s.noise(t + i * 0.045 + Math.random() * 0.02, { dur: 0.03, vol: 0.2 * p.vol, type: "highpass", f0: 3000 + Math.random() * 3000, room: 0.3 });
    s.tone(t, { type: "sawtooth", f0: 380, f1: 90, dur: 0.3, vol: 0.1 * p.vol, lp: [4000, 800], vibrato: { rate: 60, depth: 80 }, room: 0.4 });
  },
  // Plain speech: a few vowel syllables with a falling sentence tune, in the species' voice
  voice_babble(s, t, p) {
    const gap = (p.wet ? 0.085 : 0.1) / Math.min(1.4, Math.sqrt(p.size));
    const vowels = ["ah", "oh", "uh", "eh", "oo", "aw"];
    for (let i = 0; i < p.syll; i++) {
      const at = t + i * gap + Math.random() * 0.015;
      const f = p.f0 * (1.15 - (0.25 * i) / p.syll) * (0.92 + Math.random() * 0.16);
      if (p.wet) s.tone(at, { f0: f * 0.9, f1: f * 1.4, dur: 0.07, vol: 0.24 * p.vol, lp: [1500, 800], vibrato: { rate: 30, depth: f * 0.08 }, room: 0.3 });
      else s.vocal(at, { f0: f, f1: f * 0.93, dur: gap * 0.8, vol: (0.4 * p.vol) / Math.sqrt(p.size), vowel: [vowels[Math.floor(Math.random() * 6)], vowels[Math.floor(Math.random() * 6)]], size: p.size, rasp: p.rasp, attack: 0.01, room: 0.3 });
    }
  },
  good(s, t) {
    s.tone(t, { type: "triangle", f0: NOTE(76), dur: 0.25, vol: 0.16, room: 0.6 });
    s.tone(t + 0.1, { type: "triangle", f0: NOTE(83), dur: 0.45, vol: 0.16, room: 0.7 });
  },
  bad(s, t) {
    s.tone(t, { type: "sawtooth", f0: 75, f1: 62, dur: 0.6, vol: 0.18, lp: [400, 900], vibrato: { rate: 9, depth: 6 }, room: 0.4 });
    s.tone(t, { type: "sawtooth", f0: 106, f1: 88, dur: 0.6, vol: 0.1, lp: [500, 1000], room: 0.4 });
  },
  fear(s, t) {
    s.tone(t, { type: "triangle", f0: NOTE(79), f1: NOTE(67), dur: 0.7, vol: 0.1, vibrato: { rate: 14, depth: 25 }, room: 0.8 });
  },
  sad(s, t) {
    s.tone(t, { type: "triangle", f0: NOTE(70), f1: NOTE(65), dur: 0.8, vol: 0.12, attack: 0.05, room: 0.9 });
  },
  odd(s, t) {
    s.tone(t, { f0: 300, f1: 900, dur: 0.12, vol: 0.15, room: 0.3 });
    s.tone(t + 0.12, { f0: 900, f1: 220, dur: 0.3, vol: 0.13, room: 0.5, vibrato: { rate: 18, depth: 40 } });
  },
  join(s, t) {
    s.arp(t, [67, 71, 74, 79, 83, 86], { step: 0.08, type: "square", dur: 0.3, vol: 0.06 });
    s.arp(t + 0.48, [79, 83, 86, 91], { step: 0, type: "triangle", dur: 0.9, vol: 0.08 });
  },
  gold(s, t) {
    for (let i = 0; i < 3; i++) {
      s.tone(t + i * 0.07, { f0: 2100 + i * 150, dur: 0.18, vol: 0.06, room: 0.5 });
      s.tone(t + i * 0.07, { f0: 3150 + i * 200, dur: 0.12, vol: 0.04, room: 0.5 });
    }
  },
  levelup(s, t) {
    s.arp(t, [60, 64, 67, 72, 76, 79, 84], { step: 0.055, type: "square", dur: 0.25, vol: 0.05 });
    s.tone(t + 0.4, { type: "triangle", f0: NOTE(84), dur: 0.8, vol: 0.12, room: 0.9 });
  },
  // An achievement: a quick 8-bit run up to a bright held chord, with a sparkle on top
  achieve(s, t) {
    s.arp(t, [72, 76, 79, 84], { step: 0.065, type: "square", dur: 0.16, vol: 0.055, room: 0.35 });
    [79, 84, 88].forEach((n) => s.tone(t + 0.28, { type: "square", f0: NOTE(n), dur: 0.75, vol: 0.035, lp: [5000, 1800], room: 0.6 }));
    s.tone(t + 0.28, { type: "triangle", f0: NOTE(96), dur: 0.9, vol: 0.07, room: 0.9, vibrato: { rate: 7, depth: 8 } });
    s.noise(t + 0.28, { dur: 0.5, vol: 0.05, type: "highpass", f0: 7000, q: 0.5, room: 0.6 });
  },
  slash(s, t) {
    s.noise(t, { dur: 0.25, vol: 0.4, f0: 6000, f1: 500, q: 3, attack: 0.01, room: 0.4 });
    s.tone(t + 0.05, { type: "sawtooth", f0: 160, f1: 70, dur: 0.5, vol: 0.12, lp: [1200, 300], room: 0.6 });
  },

  // Exploring
  encounter(s, t) {
    s.tone(t, { type: "sawtooth", f0: NOTE(45), dur: 0.5, vol: 0.12, lp: [2000, 400] });
    s.tone(t, { type: "sawtooth", f0: NOTE(51), dur: 0.5, vol: 0.1, lp: [2000, 400] });
    s.tone(t, { f0: 70, f1: 40, dur: 0.4, vol: 0.4 });
  },
  boss(s, t) {
    s.tone(t, { f0: 55, f1: 41, dur: 2.2, vol: 0.5, attack: 0.02, room: 1 });
    s.noise(t, { dur: 2, vol: 0.25, type: "lowpass", f0: 600, f1: 80, room: 1 });
    [33, 39, 45].forEach((n, i) => s.tone(t + 0.3 + i * 0.25, { type: "sawtooth", f0: NOTE(n + 12), dur: 1.4, vol: 0.08, lp: [300, 1200], attack: 0.2, room: 1 }));
  },
  flee(s, t) {
    s.noise(t, { dur: 0.3, vol: 0.2, f0: 300, f1: 3000, q: 2, attack: 0.05, room: 0.3 });
    s.noise(t + 0.12, { dur: 0.3, vol: 0.15, f0: 400, f1: 3500, q: 2, attack: 0.05, room: 0.3 });
  },
  bump(s, t) {
    s.tone(t, { f0: 90, f1: 60, dur: 0.12, vol: 0.4, room: 0.2 });
  },
  stairs(s, t) {
    for (let i = 0; i < 4; i++) s.tone(t + i * 0.13, { f0: 120 - i * 12, f1: 70 - i * 6, dur: 0.1, vol: 0.3, room: 0.5 });
  },

  // The Roll of Fate
  tick(s, t) {
    s.tone(t, { type: "square", f0: 1400, dur: 0.03, vol: 0.05, lp: [4000], room: 0.2 });
  },
  land(s, t) {
    s.arp(t, [60, 67, 72, 76], { step: 0, type: "sawtooth", dur: 1.2, vol: 0.05 });
    s.arp(t, [72, 76, 79, 84, 88], { step: 0.06, type: "triangle", dur: 0.8, vol: 0.1 });
    s.tone(t, { f0: 65, dur: 0.8, vol: 0.3, room: 0.8 });
  },
  great(s, t) {
    s.tone(t, { f0: 55, f1: 40, dur: 1.5, vol: 0.5, room: 1 });
    const chords = [[57, 64, 69, 72], [53, 60, 65, 69], [55, 62, 67, 71], [57, 64, 69, 73, 76]];
    chords.forEach((ch, i) =>
      ch.forEach((n) => s.tone(t + i * 0.32, { type: "sawtooth", f0: NOTE(n), dur: i === 3 ? 2 : 0.4, vol: 0.045, lp: [800, i === 3 ? 4000 : 1500], attack: 0.02, room: 0.9 })),
    );
    s.arp(t + 0.96, [81, 85, 88, 93], { step: 0.08, type: "triangle", dur: 1.4, vol: 0.09 });
  },
};
