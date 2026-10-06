// Monsters reading their lines aloud (browser text to speech). Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { speakable, pickVoice, ttsOn, Narrator, VOICES } from "../public/tts.js";

test("only the words are spoken, not the stage directions", () => {
  assert.equal(speakable("RAAH! *swings a knotted club at {target}*"), "RAAH!");
  assert.equal(speakable("*stares blankly* ...hi heehee."), "hi heehee.");
  assert.equal(speakable("You broke your word. Now I break YOU."), "You broke your word. Now I break YOU.");
  assert.equal(speakable("*oozes away*"), "");
  assert.equal(speakable(undefined), "");
});

test("off until the player uses their voice; an explicit choice always wins", () => {
  assert.equal(ttsOn({}), false);
  assert.equal(ttsOn({ usedVoice: true }), true);
  assert.equal(ttsOn({ usedVoice: true, choice: "off" }), false);
  assert.equal(ttsOn({ usedVoice: false, choice: "on" }), true);
});

test("an English voice is picked even when the browser's language isn't English, local first", () => {
  const voices = [
    { name: "Tingting", lang: "zh-CN", localService: true },
    { name: "Google UK English Female", lang: "en-GB", localService: false },
    { name: "Samantha", lang: "en-US", localService: true },
  ];
  assert.equal(pickVoice(voices, "slime").name, "Samantha");
  assert.equal(pickVoice([{ name: "Tingting", lang: "zh-CN" }], "slime"), null);
  const deep = pickVoice([...voices, { name: "Daniel", lang: "en-GB", localService: true }], "dragon");
  assert.equal(deep.name, "Daniel");
});

// A fake speechSynthesis that records what it was asked to say
function fakeSynth() {
  const spoken = [];
  let cancels = 0;
  return {
    spoken,
    get cancels() {
      return cancels;
    },
    getVoices: () => [{ name: "Samantha", lang: "en-US", localService: true }],
    speak: (u) => spoken.push(u),
    cancel: () => (cancels++, spoken.length = 0),
  };
}
class FakeUtterance {
  constructor(text) {
    this.text = text;
  }
}
const memStore = (init = {}) => {
  const m = { ...init };
  return { get: (k) => m[k] ?? null, set: (k, v) => (m[k] = v), m };
};

test("silent by default, speaks once the player has used the microphone", () => {
  const synth = fakeSynth();
  const store = memStore();
  const n = new Narrator({ synth, Utterance: FakeUtterance, store });
  assert.equal(n.say("Hello, tiny.", "goblin"), null);
  n.heardPlayer();
  const u = n.say("Hello, tiny. *grins*", "goblin");
  assert.equal(u.text, "Hello, tiny.");
  assert.equal(u.pitch, VOICES.goblin.pitch);
  assert.equal(u.voice.name, "Samantha");
  assert.equal(store.m["donjon.usedVoice"], "1", "remembered for next time");
});

test("L toggles it for good, and turning it off stops any speech at once", () => {
  const synth = fakeSynth();
  const store = memStore({ "donjon.usedVoice": "1" });
  const n = new Narrator({ synth, Utterance: FakeUtterance, store });
  assert.equal(n.on, true);
  assert.equal(n.toggle(), false);
  assert.equal(store.m["donjon.tts"], "off");
  assert.ok(synth.cancels >= 1);
  assert.equal(n.say("Hi.", "slime"), null);
  assert.equal(n.toggle(), true);
  assert.ok(n.say("Hi.", "slime"));
});

test("a backlog is dropped so speech keeps up with the fight", () => {
  const synth = fakeSynth();
  const n = new Narrator({ synth, Utterance: FakeUtterance, store: memStore({ "donjon.tts": "on" }) });
  n.say("One.", "slime");
  n.say("Two.", "slime");
  n.say("Three.", "slime");
  assert.equal(synth.cancels, 1);
  assert.deepEqual(synth.spoken.map((u) => u.text), ["Three."]);
});

test("without speechSynthesis it is simply off", () => {
  const n = new Narrator({ synth: undefined, Utterance: undefined, store: memStore({ "donjon.tts": "on" }) });
  assert.equal(n.supported, false);
  assert.equal(n.on, false);
  assert.equal(n.say("Hello.", "slime"), null);
});
