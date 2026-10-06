// The dungeon music engine. Sampled instruments (MusyngKite + FluidR3 soundfonts), live analog-style synths,
// sampled LinnDrum drums, and a cathedral reverb. It plays a PATTERN: a grid of sixteenth-note steps
// (editable in beatmaker.html) plus optional score LAYERS (exact notes with lengths, e.g. an arranged symphony).
// The game plays song.json if you saved one from the beat maker, otherwise theme.json: Beethoven's Seventh,
// Allegretto, darkened (built by crawler/scripts/build-theme.js from a public-domain score).

// ---------------------------------------------------------------- instruments

// Sampled instruments load soundfonts/<id>.json. `synth` instruments are generated live (no files).
// attack/release in seconds. bass: only offered on the bass track.
export const INSTRUMENTS = {
  mk_string_ensemble_1: { label: "STRINGS", attack: 0.18, release: 0.7 },
  mk_choir_aahs: { label: "CHOIR", attack: 0.3, release: 0.9 },
  mk_church_organ: { label: "CHURCH ORGAN", attack: 0.03, release: 0.3 },
  mk_harpsichord: { label: "HARPSICHORD", attack: 0.004, release: 0.35 },
  mk_music_box: { label: "MUSIC BOX", attack: 0.004, release: 0.9 },
  mk_tubular_bells: { label: "TUBULAR BELLS", attack: 0.004, release: 1.4 },
  syn_dark_pad: {
    label: "DARK SYNTH PAD",
    attack: 1.6,
    release: 2.6,
    synth: { osc: [{ type: "sawtooth", detune: -14 }, { type: "sawtooth" }, { type: "sawtooth", detune: 14 }], cutoff: 520, env: 0.5, q: 1.5, filterDecay: 2.5 },
  },
  syn_analog_lead: {
    label: "ANALOG LEAD",
    attack: 0.14,
    release: 1.1,
    synth: {
      osc: [{ type: "sawtooth", detune: -7 }, { type: "sawtooth", detune: 7 }, { type: "square", ratio: 0.5, gain: 0.35 }],
      cutoff: 850,
      env: 1.4,
      q: 7,
      filterDecay: 1.0,
      vibrato: { rate: 4.8, cents: 16, delay: 0.4 },
    },
  },
  syn_echo_pluck: {
    label: "ECHO PLUCK",
    attack: 0.005,
    release: 0.6,
    synth: { osc: [{ type: "square" }, { type: "sawtooth", detune: 5 }], cutoff: 650, env: 3, q: 5, filterDecay: 0.2 },
  },
  pad_2_warm: { label: "WARM PAD (OLD)", attack: 0.35, release: 0.8 },
  lead_2_sawtooth: { label: "SAW LEAD (OLD)", attack: 0.01, release: 0.18 },
  syn_sub_bass: {
    label: "SUB BASS",
    attack: 0.01,
    release: 0.4,
    bass: true,
    synth: { osc: [{ type: "sine" }, { type: "sawtooth", gain: 0.35 }], cutoff: 220, env: 1.2, q: 3, filterDecay: 0.3 },
  },
  mk_fretless_bass: { label: "FRETLESS BASS", attack: 0.01, release: 0.2, bass: true },
  mk_electric_bass_finger: { label: "FINGER BASS", attack: 0.005, release: 0.15, bass: true },
  mk_synth_bass_2: { label: "SYNTH BASS", attack: 0.005, release: 0.15, bass: true },
  synth_bass_1: { label: "SYNTH BASS (OLD)", attack: 0.01, release: 0.18, bass: true },
};

export const DRUMS = {
  kick: { label: "KICK", file: "kick" },
  snare: { label: "SNARE", file: "snare-m" },
  clap: { label: "CLAP", file: "clap" },
  hat: { label: "HAT", file: "hhclosed-short" },
  openhat: { label: "OPEN HAT", file: "hhopen" },
  tom: { label: "TOM", file: "tom-m" },
  tomlow: { label: "LOW TOM", file: "tom-l" },
  crash: { label: "CRASH", file: "crash" },
};

export const CHORDS = {
  Am: ["A3", "C4", "E4"],
  Bb: ["Bb3", "D4", "F4"],
  C: ["C4", "E4", "G4"],
  Dm: ["D3", "F3", "A3"],
  Dm6: ["D3", "F3", "A3", "B3"],
  E: ["E3", "G#3", "B3"],
  E7: ["E3", "G#3", "B3", "D4"],
  Em: ["E3", "G3", "B3"],
  F: ["F3", "A3", "C4"],
  Fmaj7: ["F3", "A3", "C4", "E4"],
  G: ["G3", "B3", "D4"],
  "G#dim": ["G#3", "B3", "D4", "F4"],
};

const PITCH = { C: 0, "C#": 1, Db: 1, D: 2, "D#": 3, Eb: 3, E: 4, F: 5, "F#": 6, Gb: 6, G: 7, "G#": 8, Ab: 8, A: 9, "A#": 10, Bb: 10, B: 11 };
const SF_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
const NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"];
export function midi(n) {
  const [, p, o] = n.match(/^([A-G][#b]?)(-?\d)$/);
  return 12 * (Number(o) + 1) + PITCH[p];
}
const sfName = (m) => `${SF_NAMES[m % 12]}${Math.floor(m / 12) - 1}`;
const nameOf = (m) => `${NAMES[m % 12]}${Math.floor(m / 12) - 1}`;
function chromatic(hi, lo) {
  const out = [];
  for (let m = midi(hi); m >= midi(lo); m--) out.push(nameOf(m));
  return out;
}

// Rows offered in the beat maker, top to bottom. Chromatic, so the eerie in-between notes are there too.
export const TRACKS = {
  lead: { label: "MELODY", rows: () => chromatic("A5", "E4") },
  keys: { label: "ARPEGGIO / COUNTER", rows: () => chromatic("A5", "G3") },
  bass: { label: "BASS", rows: () => chromatic("Bb3", "A1") },
};
// A harmonic minor: the beat maker highlights these rows as "in key"
export const IN_KEY = new Set(["A", "B", "C", "D", "E", "F", "G#"]);

export const DEFAULT_VOLUMES = { pad: 0.2, lead: 0.32, keys: 0.22, bass: 0.55, kick: 0.9, snare: 0.6, clap: 0.5, hat: 0.3, openhat: 0.3, tom: 0.55, tomlow: 0.55, crash: 0.35 };
export const DEFAULT_INSTRUMENTS = { lead: "mk_string_ensemble_1", keys: "mk_choir_aahs", bass: "syn_sub_bass", pad: "syn_dark_pad" };
export const MAX_BARS = 32;

// ---------------------------------------------------------------- patterns

// Pattern: { bpm, bars, chords: [per bar], pad: bool, instruments: {lead, keys, bass, pad},
//   drums: {kick: [0|1 per step], ...}, lead/keys/bass: [note|null per step],
//   leadLen/keysLen/bassLen: sixteenths each note lasts (0 = until the next note), volumes,
//   layers: [{ id, label, instrument, volume, send, muted?, events: [[step, note, lengthInSteps], ...] }] }
export function emptyPattern(bars = 2) {
  const steps = bars * 16;
  return {
    bpm: 70,
    bars,
    chords: Array(bars).fill("Am"),
    pad: true,
    instruments: { ...DEFAULT_INSTRUMENTS },
    drums: Object.fromEntries(Object.keys(DRUMS).map((d) => [d, Array(steps).fill(0)])),
    lead: Array(steps).fill(null),
    keys: Array(steps).fill(null),
    bass: Array(steps).fill(null),
    leadLen: 0,
    keysLen: 2,
    bassLen: 2,
    volumes: { ...DEFAULT_VOLUMES },
    layers: [],
  };
}

// Fills in anything an older or partial pattern is missing, so old saves and theme files keep working.
export function normalize(p) {
  const base = emptyPattern(p.bars);
  const steps = p.bars * 16;
  const out = { ...base, ...p, instruments: { ...base.instruments, ...(p.instruments ?? {}) }, volumes: { ...base.volumes, ...(p.volumes ?? {}) } };
  out.drums = { ...base.drums };
  for (const d of Object.keys(DRUMS)) {
    const src = p.drums?.[d] ?? p[d]; // older saves kept kick/snare/hat at the top level
    if (Array.isArray(src) && src.length === steps) out.drums[d] = src.map((v) => (v ? 1 : 0));
  }
  for (const t of ["lead", "keys", "bass"]) if (!Array.isArray(p[t]) || p[t].length !== steps) out[t] = base[t];
  for (const old of ["kick", "snare", "hat"]) delete out[old];
  if (!Array.isArray(out.chords) || out.chords.length !== p.bars) out.chords = base.chords;
  out.chords = out.chords.map((c) => (CHORDS[c] ? c : "Am"));
  out.layers = (p.layers ?? []).filter((l) => INSTRUMENTS[l.instrument] && Array.isArray(l.events));
  return out;
}

// The game's theme: an arranged public-domain score (see crawler/scripts/build-theme.js).
export async function loadTheme() {
  try {
    const r = await fetch("theme.json", { cache: "no-store" });
    if (r.ok) return normalize(await r.json());
  } catch {}
  return emptyPattern(2);
}

// The game plays your saved beat (song.json) if there is one, otherwise the theme.
export async function loadSavedSong() {
  try {
    const r = await fetch("song.json", { cache: "no-store" });
    if (r.ok) return normalize(await r.json());
  } catch {}
  return loadTheme();
}

// ---------------------------------------------------------------- engine

export class Music {
  constructor() {
    this.ctx = null;
    this.on = false;
    this.samples = {}; // "instrument:midi" -> AudioBuffer
    this.fonts = {};
    this.drumBufs = {};
    this.pattern = null;
    this.layerIndex = new Map();
    this.step = 0;
    this.onStep = null; // the beat maker uses this to light up the playing column
  }

  // Must be called from a user gesture (browsers block audio otherwise).
  async start(pattern) {
    if (!this.ctx) this.build();
    // Resume right away, while still inside the click/keypress (Safari refuses after an await)
    const resumed = this.ctx.resume();
    if (pattern) await this.setPattern(pattern);
    else if (!this.pattern) await this.setPattern(await loadSavedSong());
    await resumed;
    this.on = true;
    if (!this.timer) this.schedule();
  }

  build() {
    this.ctx = new AudioContext();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.9;
    const comp = this.ctx.createDynamicsCompressor();
    this.master.connect(comp).connect(this.ctx.destination);
    // A long, dark cathedral reverb (generated impulse response), fed by the melodic tracks
    this.reverb = this.ctx.createConvolver();
    this.reverb.buffer = this.impulse(3.2, 2.6);
    const wet = this.ctx.createGain();
    wet.gain.value = 0.35;
    const tone = this.ctx.createBiquadFilter();
    tone.type = "lowpass";
    tone.frequency.value = 3800;
    this.reverb.connect(tone).connect(wet).connect(this.master);
    this.sends = {};
    for (const [t, amount] of Object.entries({ lead: 0.45, keys: 0.3, bass: 0.08, pad: 0.6 })) {
      const bus = this.ctx.createGain();
      const send = this.ctx.createGain();
      send.gain.value = amount;
      bus.connect(this.master);
      bus.connect(send).connect(this.reverb);
      this.sends[t] = bus;
    }
    this.drumBus = this.ctx.createGain();
    this.drumBus.connect(this.master);
  }

  impulse(seconds, decay) {
    const rate = this.ctx.sampleRate;
    const len = Math.floor(rate * seconds);
    const buf = this.ctx.createBuffer(2, len, rate);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
    }
    return buf;
  }

  stop() {
    this.on = false;
    clearInterval(this.timer);
    this.timer = null;
    this.ctx?.suspend();
  }

  toggle() {
    return this.on ? (this.stop(), false) : this.start().then(() => true);
  }

  async setPattern(p) {
    const pattern = normalize(p);
    // Index layer notes by step so the scheduler can find them quickly
    const byStep = new Map();
    pattern.layers.forEach((layer, li) => {
      if (layer.muted) return;
      for (const [step, note, len] of layer.events) {
        if (!byStep.has(step)) byStep.set(step, []);
        byStep.get(step).push([li, note, len]);
      }
    });
    await this.ensureSamples(pattern);
    this.layerIndex = byStep;
    this.pattern = pattern;
  }

  // Decode only the notes and drums the pattern actually uses.
  async ensureSamples(p) {
    const need = {};
    const add = (inst, note) => (need[inst] ??= new Set()).add(midi(note));
    if (p.pad) for (const ch of p.chords) CHORDS[ch].forEach((n) => add(p.instruments.pad, n));
    for (const t of ["lead", "keys", "bass"]) p[t].forEach((n) => n && add(p.instruments[t], n));
    for (const layer of p.layers ?? []) if (!layer.muted) for (const [, n] of layer.events) add(layer.instrument, n);
    const jobs = Object.entries(need)
      .filter(([inst]) => !INSTRUMENTS[inst].synth)
      .map(async ([inst, notes]) => {
        const missing = [...notes].filter((m) => !this.samples[`${inst}:${m}`]);
        if (!missing.length) return;
        this.fonts[inst] ??= fetch(`soundfonts/${inst}.json`).then((r) => r.json());
        const font = await this.fonts[inst];
        await Promise.all(
          missing.map(async (m) => {
            const url = font[sfName(m)];
            if (!url) return;
            const bytes = Uint8Array.from(atob(url.split(",")[1]), (c) => c.charCodeAt(0));
            this.samples[`${inst}:${m}`] = await this.ctx.decodeAudioData(bytes.buffer);
          }),
        );
      });
    for (const [d, def] of Object.entries(DRUMS)) {
      if (this.drumBufs[d] || !p.drums[d].some(Boolean)) continue;
      jobs.push(
        fetch(`soundfonts/drums/${def.file}.m4a`)
          .then((r) => r.arrayBuffer())
          .then((b) => this.ctx.decodeAudioData(b))
          .then((buf) => (this.drumBufs[d] = buf)),
      );
    }
    await Promise.all(jobs);
  }

  note(track, inst, m, when, dur, vol) {
    const def = INSTRUMENTS[inst];
    if (def.synth) return this.synth(track, def, m, when, dur, vol);
    const buf = this.samples[`${inst}:${m}`];
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0, when);
    g.gain.linearRampToValueAtTime(vol, when + def.attack);
    g.gain.setValueAtTime(vol, when + Math.max(def.attack, dur));
    g.gain.linearRampToValueAtTime(0, when + dur + def.release);
    src.connect(g).connect(this.sends[track]);
    src.start(when);
    src.stop(when + dur + def.release + 0.05);
  }

  // One analog-style voice: detuned oscillators into a resonant low-pass whose cutoff swells on each note,
  // with an optional slow vibrato that fades in.
  synth(track, inst, m, when, dur, vol) {
    const ctx = this.ctx;
    const { synth: def, attack, release } = inst;
    const f = 440 * Math.pow(2, (m - 69) / 12);
    const end = when + dur + release + 0.05;
    const level = Math.max(vol, 0.0002);
    const filt = ctx.createBiquadFilter();
    filt.type = "lowpass";
    filt.Q.value = def.q;
    filt.frequency.setValueAtTime(def.cutoff, when);
    filt.frequency.linearRampToValueAtTime(def.cutoff * (1 + def.env), when + attack + 0.01);
    filt.frequency.exponentialRampToValueAtTime(def.cutoff, when + attack + def.filterDecay);
    const amp = ctx.createGain();
    amp.gain.setValueAtTime(0.0001, when);
    amp.gain.linearRampToValueAtTime(level, when + attack);
    amp.gain.setValueAtTime(level, when + Math.max(attack, dur));
    amp.gain.exponentialRampToValueAtTime(0.0001, when + dur + release);
    filt.connect(amp).connect(this.sends[track]);
    let depth = null;
    if (def.vibrato) {
      const lfo = ctx.createOscillator();
      lfo.frequency.value = def.vibrato.rate;
      depth = ctx.createGain();
      depth.gain.setValueAtTime(0, when);
      depth.gain.linearRampToValueAtTime(def.vibrato.cents, when + def.vibrato.delay + 0.5);
      lfo.connect(depth);
      lfo.start(when);
      lfo.stop(end);
    }
    for (const o of def.osc) {
      const osc = ctx.createOscillator();
      osc.type = o.type;
      osc.frequency.value = f * (o.ratio ?? 1);
      osc.detune.value = o.detune ?? 0;
      if (depth) depth.connect(osc.detune);
      const g = ctx.createGain();
      g.gain.value = (o.gain ?? 1) / def.osc.length;
      osc.connect(g).connect(filt);
      osc.start(when);
      osc.stop(end);
    }
  }

  drum(d, when, vol) {
    const buf = this.drumBufs[d];
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    g.gain.value = vol;
    src.connect(g).connect(this.drumBus);
    src.start(when);
  }

  // How long a grid note lasts: a fixed length, or until the next note in that track.
  noteSteps(track, s, len, total) {
    if (len > 0) return len;
    let n = 1;
    while (n < 16 && track[(s + n) % total] == null) n++;
    return n;
  }

  schedule() {
    let next = this.ctx.currentTime + 0.1;
    this.step = 0;
    this.timer = setInterval(() => {
      const p = this.pattern;
      if (!p) return;
      const sixteenth = 60 / p.bpm / 4;
      const total = p.bars * 16;
      const v = p.volumes;
      while (next < this.ctx.currentTime + 0.2) {
        const s = this.step % total;
        const bar = Math.floor(s / 16);
        if (s % 16 === 0 && p.pad) for (const n of CHORDS[p.chords[bar]]) this.note("pad", p.instruments.pad, midi(n), next, sixteenth * 16, v.pad);
        for (const d of Object.keys(DRUMS)) if (p.drums[d][s]) this.drum(d, next, v[d]);
        for (const t of ["lead", "keys", "bass"])
          if (p[t][s]) this.note(t, p.instruments[t], midi(p[t][s]), next, sixteenth * this.noteSteps(p[t], s, p[`${t}Len`], total) * 0.95, v[t]);
        for (const [li, n, len] of this.layerIndex.get(s) ?? []) {
          const layer = p.layers[li];
          this.note(layer.send ?? "keys", layer.instrument, midi(n), next, sixteenth * len * 0.97, layer.volume ?? 0.3);
        }
        if (this.onStep) {
          const shown = s;
          setTimeout(() => this.onStep?.(shown), Math.max(0, (next - this.ctx.currentTime) * 1000));
        }
        this.step++;
        next += sixteenth;
      }
    }, 25);
  }

  // Audition one sound right now (beat maker clicks)
  async preview(track, value, instrument) {
    if (!this.ctx) this.build();
    this.ctx.resume();
    if (DRUMS[track]) {
      const p = emptyPattern(1);
      p.pad = false;
      p.drums[track][0] = 1;
      await this.ensureSamples(p);
      return this.drum(track, this.ctx.currentTime + 0.02, 0.8);
    }
    const p = emptyPattern(1);
    p.pad = false;
    p.instruments[track] = instrument;
    p[track][0] = value;
    await this.ensureSamples(p);
    this.note(track, instrument, midi(value), this.ctx.currentTime + 0.02, 0.35, 0.5);
  }
}
