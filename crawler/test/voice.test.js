// Hold-to-talk with the browser's built-in speech recognition: run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { recognizer, Listener, HOLD_MS } from "../public/voice.js";

// A stand-in for SpeechRecognition: the test feeds it results and ends it
class FakeRecognition {
  static last = null;
  constructor() {
    FakeRecognition.last = this;
    this.started = false;
  }
  start() {
    this.started = true;
  }
  stop() {
    this.stopping = true;
  }
  abort() {
    this.aborted = true;
    this.onend?.();
  }
  // results: [[text, isFinal], ...] as the browser reports the whole session so far
  emit(results) {
    const list = results.map(([text, isFinal]) => Object.assign([{ transcript: text }], { isFinal }));
    this.onresult?.({ resultIndex: 0, results: list });
  }
}

test("finds the browser's recognizer, prefixed or not, and copes without one", () => {
  assert.equal(recognizer({ SpeechRecognition: FakeRecognition }), FakeRecognition);
  assert.equal(recognizer({ webkitSpeechRecognition: FakeRecognition }), FakeRecognition);
  assert.equal(recognizer({}), null);
});

test("a hold is long enough to tell apart from a tap", () => {
  assert.ok(HOLD_MS >= 200 && HOLD_MS <= 500);
});

test("words show up as you speak, and the final text comes back when you let go", async () => {
  const heard = [];
  const l = new Listener({ Recognition: FakeRecognition, lang: "en-US", onText: (t) => heard.push(t) });
  const done = l.start();
  const rec = FakeRecognition.last;
  assert.ok(rec.started && rec.interimResults && rec.continuous);
  assert.equal(rec.lang, "en-US");
  rec.emit([["hello", false]]);
  rec.emit([["hello little", false]]);
  rec.emit([["hello little slime", true], [" want to", false]]);
  l.stop();
  rec.emit([["hello little slime", true], [" want to join us", true]]);
  rec.onend();
  assert.equal(await done, "hello little slime want to join us");
  assert.deepEqual(heard.slice(0, 2), ["hello", "hello little"]);
  assert.equal(heard.at(-1), "hello little slime want to join us");
});

test("nothing heard comes back empty, not as an error", async () => {
  const l = new Listener({ Recognition: FakeRecognition });
  const done = l.start();
  FakeRecognition.last.onerror?.({ error: "no-speech" });
  FakeRecognition.last.onend();
  assert.equal(await done, "");
});

test("a blocked microphone is reported so the game can say so", async () => {
  let why = null;
  const l = new Listener({ Recognition: FakeRecognition, onError: (e) => (why = e) });
  const done = l.start();
  FakeRecognition.last.onerror?.({ error: "not-allowed" });
  FakeRecognition.last.onend();
  assert.equal(await done, "");
  assert.equal(why, "not-allowed");
});

test("cancel throws the words away", async () => {
  const l = new Listener({ Recognition: FakeRecognition });
  const done = l.start();
  FakeRecognition.last.emit([["never mind", false]]);
  l.cancel();
  assert.equal(await done, null);
  assert.ok(FakeRecognition.last.aborted);
});

test("without speech support, start resolves to null at once", async () => {
  const l = new Listener({ Recognition: null });
  assert.equal(l.supported, false);
  assert.equal(await l.start(), null);
});

test("holding Space: listen into an empty talk box, or open the right one first", async () => {
  const { spaceHold } = await import("../public/voice.js");
  assert.equal(spaceHold({ inputOpen: true, inputEmpty: true }), "listen");
  assert.equal(spaceHold({ inputOpen: true, inputEmpty: false }), null, "with words in the box, Space types a space");
  assert.equal(spaceHold({ inputOpen: true, numeric: true }), null, "not in the gold box");
  assert.equal(spaceHold({ combat: true }), "talk");
  assert.equal(spaceHold({ combat: true, waiting: true }), null, "not while a menu, question or the monsters' turn waits");
  assert.equal(spaceHold({ allies: 2 }), "ally");
  assert.equal(spaceHold({}), null, "exploring alone: nobody to talk to");
});
