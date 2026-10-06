// Monsters read their lines aloud with the browser's built-in text to speech (speechSynthesis: Chrome, Edge,
// Safari). Off by default, and on by itself once you've talked to the game with your voice (hold Space):
// someone speaking to the monsters wants to hear them answer. L turns it on or off for good.
// No DOM access at import time; the pure parts are tested in Node.

// What's worth saying out loud: the words, not the *stage directions* or {placeholders}
export function speakable(line) {
  return String(line ?? "")
    .replace(/\*[^*]*\*/g, " ")
    .replace(/\{[^}]*\}/g, " ")
    .replace(/\.{2,}|…/g, ", ")
    .replace(/\s+([,.!?])/g, "$1")
    .replace(/^[\s,]+|[\s,]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

// Each kind of monster sounds like itself: pitch 0..2 and rate 0.1..10 as speechSynthesis takes them
export const VOICES = {
  dragon: { pitch: 0.3, rate: 0.8 },
  rock: { pitch: 0.2, rate: 0.7 },
  goblin: { pitch: 0.7, rate: 1.05 },
  bandit: { pitch: 0.9, rate: 1.0 },
  snake: { pitch: 1.2, rate: 0.85 },
  slime: { pitch: 1.8, rate: 1.15 },
};
const DEFAULT_VOICE = { pitch: 1, rate: 1 };

// Monster lines are English: pick an English voice, preferring local ones (no network) and the better
// engines' voices; species with a deep voice prefer a male-sounding name when the browser offers one
export function pickVoice(voices, species) {
  const en = voices.filter((v) => /^en(-|_|$)/i.test(v.lang));
  if (!en.length) return null;
  const score = (v) =>
    (v.localService ? 4 : 0) +
    (/google|natural|enhanced|premium/i.test(v.name) ? 2 : 0) +
    (/en[-_]?(us|gb)/i.test(v.lang) ? 1 : 0) +
    (["dragon", "rock", "goblin"].includes(species) && /male|daniel|fred|alex|david|george|guy/i.test(v.name) && !/female/i.test(v.name) ? 3 : 0);
  return [...en].sort((a, b) => score(b) - score(a))[0];
}

// Whether lines are read aloud: an explicit choice wins; otherwise on once the player has used their voice
export function ttsOn({ choice = null, usedVoice = false } = {}) {
  if (choice === "on") return true;
  if (choice === "off") return false;
  return !!usedVoice;
}

const MAX_QUEUE = 2; // more than this waiting and the oldest are dropped, so speech keeps up with the fight

export class Narrator {
  constructor({ synth = globalThis.speechSynthesis, Utterance = globalThis.SpeechSynthesisUtterance, store } = {}) {
    this.synth = synth;
    this.Utterance = Utterance;
    this.store = store;
    this.queued = 0;
  }

  get supported() {
    return !!(this.synth && this.Utterance);
  }

  get on() {
    if (!this.supported) return false;
    return ttsOn({ choice: this.store?.get("donjon.tts"), usedVoice: this.store?.get("donjon.usedVoice") === "1" });
  }

  // The player just spoke to the game: from now on (unless they said otherwise) monsters answer aloud
  heardPlayer() {
    this.store?.set("donjon.usedVoice", "1");
  }

  toggle() {
    const next = this.on ? "off" : "on";
    this.store?.set("donjon.tts", next);
    if (next === "off") this.hush();
    return next === "on";
  }

  say(text, species) {
    const words = speakable(text);
    if (!this.on || !words) return null;
    if (this.queued >= MAX_QUEUE) this.hush();
    const u = new this.Utterance(words);
    const voice = pickVoice(this.synth.getVoices?.() ?? [], species);
    if (voice) u.voice = voice;
    u.lang = voice?.lang ?? "en-US";
    Object.assign(u, VOICES[species] ?? DEFAULT_VOICE);
    this.queued++;
    u.onend = u.onerror = () => (this.queued = Math.max(0, this.queued - 1));
    this.synth.speak(u);
    console.debug(`tts: ${species ?? "?"} "${words}"`);
    return u;
  }

  // Stop at once (e.g. while the microphone listens, so the game doesn't hear itself)
  hush() {
    this.synth?.cancel();
    this.queued = 0;
  }
}
