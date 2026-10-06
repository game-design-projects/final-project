// Arranges the game's theme from a public-domain score: Beethoven, Symphony No. 7, 2nd movement (Allegretto),
// MIDI from the Mutopia Project (Public Domain). Writes public/theme.json.
// Usage: node crawler/scripts/build-theme.js
//
// Bars 3–50: the hypnotic repeated-E theme in the low strings, then the singing counter-melody over it.
// Every note is Beethoven's. The "darkening" is the extra layers and instruments chosen below.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const FROM_BAR = 3;
const TO_BAR = 50; // inclusive; 2/4 time, so each score bar is 8 sixteenth-steps
const BPM = 70; // original is about 76; a little slower for menace

// Score part (MIDI track) -> layers. A part can feed several layers (same notes, other instrument).
const ARRANGEMENT = [
  { part: 10, id: "violas", label: "VIOLAS (THEME, THEN COUNTER-MELODY)", instrument: "mk_string_ensemble_1", volume: 0.62, send: "lead" },
  { part: 10, id: "choir", label: "CHOIR DOUBLING THE VIOLAS", instrument: "mk_choir_aahs", volume: 0.22, send: "pad" },
  { part: 9, id: "violins", label: "2ND VIOLINS (THEME, FROM BAR 27)", instrument: "mk_string_ensemble_1", volume: 0.5, send: "keys" },
  { part: 11, id: "cellos", label: "CELLOS", instrument: "mk_string_ensemble_1", volume: 0.52, send: "keys" },
  { part: 11, id: "darkpad", label: "DARK SYNTH UNDER THE CELLOS", instrument: "syn_dark_pad", volume: 0.14, send: "pad" },
  { part: 12, id: "basses", label: "DOUBLE BASSES", instrument: "mk_string_ensemble_1", volume: 0.42, send: "bass" },
  { part: 12, id: "sub", label: "SUB BASS AN OCTAVE BELOW THE BASSES", instrument: "syn_sub_bass", volume: 0.16, send: "bass", transpose: -12 },
];

// --- minimal MIDI reader
function parseMidi(path) {
  const b = readFileSync(path);
  let i = 8;
  const u16 = () => (b[i++] << 8) | b[i++];
  const u32 = () => ((b[i++] << 24) | (b[i++] << 16) | (b[i++] << 8) | b[i++]) >>> 0;
  const vlq = () => {
    let v = 0;
    let c;
    do {
      c = b[i++];
      v = (v << 7) | (c & 0x7f);
    } while (c & 0x80);
    return v;
  };
  u16();
  const ntrk = u16();
  const division = u16();
  const tracks = [];
  for (let t = 0; t < ntrk; t++) {
    while (b.toString("ascii", i, i + 4) !== "MTrk") i++;
    i += 4;
    const length = u32();
    const end = i + length;
    let tick = 0;
    let status = 0;
    const open = {};
    const notes = [];
    while (i < end) {
      tick += vlq();
      let st = b[i];
      if (st & 0x80) {
        i++;
        status = st;
      } else st = status;
      // Read the length first: `i += vlq()` would use the old i, before vlq() advances it.
      if (st === 0xff) {
        i++;
        const skip = vlq();
        i += skip;
      } else if (st === 0xf0 || st === 0xf7) {
        const skip = vlq();
        i += skip;
      }
      else {
        const kind = st & 0xf0;
        const a = b[i++];
        const c = kind === 0xc0 || kind === 0xd0 ? 0 : b[i++];
        if (kind === 0x90 && c > 0) open[a] = tick;
        else if ((kind === 0x80 || kind === 0x90) && open[a] !== undefined) {
          notes.push({ pitch: a, start: open[a], end: tick });
          delete open[a];
        }
      }
    }
    i = end;
    tracks.push(notes);
  }
  return { division, tracks };
}

const NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"];
const nameOf = (p) => `${NAMES[p % 12]}${Math.floor(p / 12) - 1}`;

const { division, tracks } = parseMidi(here("../assets/beethoven7-allegretto.mid"));
const sixteenth = division / 4;
const bar = division * 2;
const startTick = (FROM_BAR - 1) * bar;
const endTick = TO_BAR * bar;
const steps = ((TO_BAR - FROM_BAR + 1) * bar) / sixteenth;

const layers = ARRANGEMENT.map(({ part, transpose = 0, ...layer }) => ({
  ...layer,
  events: tracks[part]
    .filter((n) => n.start >= startTick && n.start < endTick)
    .map((n) => [Math.round((n.start - startTick) / sixteenth), nameOf(n.pitch + transpose), Math.max(1, Math.round((n.end - n.start) / sixteenth))]),
}));

// Darkening percussion: a soft heartbeat kick on every score bar, a low tom opening each 8-bar phrase.
const drums = { kick: Array(steps).fill(0), tomlow: Array(steps).fill(0) };
for (let s = 0; s < steps; s += 8) drums.kick[s] = 1;
for (let s = 0; s < steps; s += 64) drums.tomlow[s] = 1;

const theme = {
  title: "Beethoven, Symphony No. 7: Allegretto (bars 3–50), darkened",
  bpm: BPM,
  bars: steps / 16,
  pad: false,
  chords: Array(steps / 16).fill("Am"),
  drums,
  layers,
  volumes: { kick: 0.32, tomlow: 0.4 },
};
writeFileSync(here("../public/theme.json"), JSON.stringify(theme));
console.log(`theme.json: ${theme.bars} grid bars (${TO_BAR - FROM_BAR + 1} score bars), ${layers.map((l) => `${l.id}:${l.events.length}`).join(" ")}`);
