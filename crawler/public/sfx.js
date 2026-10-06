// Sound effects, synthesised live with WebAudio (no files): hits, crits, spells, kills, dice, the Roll of Fate.
// Every sound is built from a few primitives: pitched tones with envelopes, and filtered noise bursts.

const NOTE = (n) => 440 * 2 ** ((n - 69) / 12);

export class Sfx {
  constructor(volume = 0.55) {
    this.volume = volume;
    this.ctx = null;
    this.on = true;
  }

  // Call from a key press or click (browsers block audio otherwise).
  init() {
    if (!this.ctx) {
      this.ctx = new AudioContext();
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
    this.ctx.resume();
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
      SOUNDS[name]?.(this, this.ctx.currentTime + 0.01, opt);
    } catch (err) {
      console.warn("sfx", name, err);
    }
  }

  toggle() {
    this.on = !this.on;
    return this.on;
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
  dice(s, t) {
    for (let i = 0; i < 4; i++) s.noise(t + i * 0.055 + Math.random() * 0.02, { dur: 0.03, vol: 0.25 - i * 0.04, type: "highpass", f0: 2500 + Math.random() * 2000, room: 0.2 });
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
