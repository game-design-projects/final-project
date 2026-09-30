// The dungeon theme: soundfont pad + synth bass + sawtooth lead, with synthesized kick "thumps".
//
// Your guide melody was A B C D D D E D E D C C C D D D. It's kept note for note, set in A minor over
// Am | F | Dm | E, given a rhythm (in eighth notes), and each 4-bar phrase gets an ending that leads home to A.
// Edit SONG freely: notes are scientific pitch names, durations are eighth notes (8 per bar).

export const SONG = {
  bpm: 88,
  intro: 4, // bars of just pad + bass + thumps before the melody comes in
  chords: ["Am", "F", "Dm", "E", "Am", "F", "G", "E"],
  melody: [
    // phrase 1: A B C D D D | E D E D | C C C D D D | E D C B
    ["A4", 1], ["B4", 1], ["C5", 2], ["D5", 1], ["D5", 1], ["D5", 2],
    ["E5", 3], ["D5", 1], ["E5", 2], ["D5", 2],
    ["C5", 1], ["C5", 1], ["C5", 2], ["D5", 1], ["D5", 1], ["D5", 2],
    ["E5", 2], ["D5", 1], ["C5", 1], ["B4", 4],
    // phrase 2: same opening, lifts to F, then falls to G# so the loop resolves back onto A
    ["A4", 1], ["B4", 1], ["C5", 2], ["D5", 1], ["D5", 1], ["D5", 2],
    ["E5", 3], ["D5", 1], ["E5", 2], ["F5", 2],
    ["C5", 1], ["C5", 1], ["C5", 2], ["D5", 1], ["D5", 1], ["D5", 2],
    ["E5", 2], ["D5", 1], ["C5", 1], ["B4", 2], ["G#4", 2],
  ],
  // bass hits per bar (eighth-note positions); octave-2 root, octave-3 on the pickup
  bass: [[0, 2], [3, 2], [4, 2], [6, 3]],
  // kick "thumps" per bar: [position, volume]
  kick: [[0, 1], [2, 0.55], [4, 0.9], [6, 0.55], [7, 0.3]],
};

const CHORDS = {
  Am: ["A", ["A3", "C4", "E4"]],
  F: ["F", ["F3", "A3", "C4"]],
  Dm: ["D", ["D3", "F3", "A3"]],
  E: ["E", ["E3", "G#3", "B3"]],
  G: ["G", ["G3", "B3", "D4"]],
  C: ["C", ["C3", "E3", "G3"]],
};

const INSTRUMENTS = { pad: "pad_2_warm", bass: "synth_bass_1", lead: "lead_2_sawtooth" };
const PITCH = { C: 0, "C#": 1, Db: 1, D: 2, "D#": 3, Eb: 3, E: 4, F: 5, "F#": 6, Gb: 6, G: 7, "G#": 8, Ab: 8, A: 9, "A#": 10, Bb: 10, B: 11 };
const SF_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

const midi = (n) => {
  const [, p, o] = n.match(/^([A-G][#b]?)(-?\d)$/);
  return 12 * (Number(o) + 1) + PITCH[p];
};
const sfName = (m) => `${SF_NAMES[m % 12]}${Math.floor(m / 12) - 1}`;

export class Music {
  constructor() {
    this.ctx = null;
    this.on = false;
    this.samples = {};
    this.ready = null;
  }

  // Must be called from a user gesture (browsers block audio otherwise).
  async start() {
    if (!this.ctx) {
      this.ctx = new AudioContext();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.55;
      const comp = this.ctx.createDynamicsCompressor();
      this.master.connect(comp).connect(this.ctx.destination);
      // Moody echo on the lead
      this.leadBus = this.ctx.createGain();
      const tone = this.ctx.createBiquadFilter();
      tone.type = "lowpass";
      tone.frequency.value = 2600;
      const delay = this.ctx.createDelay(1);
      delay.delayTime.value = (60 / SONG.bpm) * 0.75;
      const fb = this.ctx.createGain();
      fb.gain.value = 0.35;
      this.leadBus.connect(tone).connect(this.master);
      tone.connect(delay).connect(fb).connect(delay);
      delay.connect(this.master);
      this.ready = this.load();
    }
    await this.ctx.resume();
    await this.ready;
    this.on = true;
    if (!this.timer) this.schedule();
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

  async load() {
    const needed = { pad: new Set(), bass: new Set(), lead: new Set() };
    for (const ch of SONG.chords) {
      const [root, voicing] = CHORDS[ch];
      voicing.forEach((n) => needed.pad.add(midi(n)));
      needed.bass.add(midi(`${root}2`));
      needed.bass.add(midi(`${root}3`));
    }
    SONG.melody.forEach(([n]) => needed.lead.add(midi(n)));
    await Promise.all(
      Object.entries(INSTRUMENTS).map(async ([part, file]) => {
        const notes = await (await fetch(`soundfonts/${file}.json`)).json();
        this.samples[part] = {};
        await Promise.all(
          [...needed[part]].map(async (m) => {
            const url = notes[sfName(m)];
            const bytes = Uint8Array.from(atob(url.split(",")[1]), (c) => c.charCodeAt(0));
            this.samples[part][m] = await this.ctx.decodeAudioData(bytes.buffer);
          }),
        );
      }),
    );
  }

  play(part, note, when, dur, vol, out = this.master) {
    const buf = this.samples[part]?.[note];
    if (!buf) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const g = this.ctx.createGain();
    const attack = part === "pad" ? 0.35 : 0.01;
    const release = part === "pad" ? 0.8 : 0.18;
    g.gain.setValueAtTime(0, when);
    g.gain.linearRampToValueAtTime(vol, when + attack);
    g.gain.setValueAtTime(vol, when + Math.max(attack, dur - release));
    g.gain.linearRampToValueAtTime(0, when + dur + release);
    src.connect(g).connect(out);
    src.start(when);
    src.stop(when + dur + release + 0.05);
  }

  // A synthesized kick: a sine that drops fast in pitch. That's the "thump".
  thump(when, vol) {
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.frequency.setValueAtTime(110, when);
    o.frequency.exponentialRampToValueAtTime(38, when + 0.22);
    g.gain.setValueAtTime(0.9 * vol, when);
    g.gain.exponentialRampToValueAtTime(0.001, when + 0.35);
    o.connect(g).connect(this.master);
    o.start(when);
    o.stop(when + 0.4);
  }

  schedule() {
    const eighth = 60 / SONG.bpm / 2;
    const bars = SONG.chords.length;
    // Melody note start positions, in eighths from the top of the 8-bar loop
    const mel = [];
    let pos = 0;
    for (const [n, d] of SONG.melody) {
      mel.push([pos, midi(n), d]);
      pos += d;
    }
    let step = 0;
    let next = this.ctx.currentTime + 0.1;
    this.timer = setInterval(() => {
      while (next < this.ctx.currentTime + 0.25) {
        const bar = Math.floor(step / 8);
        const inBar = step % 8;
        const loopBar = bar % bars;
        const [root, voicing] = CHORDS[SONG.chords[loopBar]];
        if (inBar === 0) voicing.forEach((n) => this.play("pad", midi(n), next, eighth * 8, 0.22));
        for (const [p, oct] of SONG.bass) if (p === inBar) this.play("bass", midi(`${root}${oct}`), next, eighth * 0.9, 0.5);
        for (const [p, v] of SONG.kick) if (p === inBar) this.thump(next, v);
        if (bar >= SONG.intro) {
          const loopPos = (step - SONG.intro * 8) % (bars * 8);
          for (const [p, m, d] of mel) if (p === loopPos) this.play("lead", m, next, eighth * d * 0.95, 0.28, this.leadBus);
        }
        step++;
        next += eighth;
      }
    }, 25);
  }
}
