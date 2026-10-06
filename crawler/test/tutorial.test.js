// Tips (crawler/public/tutorial.js): the hint registry and the once-only / queue / off / reset logic. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { HINTS, parseLine, focusOf, createTutorial, SEEN_KEY, OFF_KEY, GRACE_MS, MIN_READ_MS, GAP_MS, TTL_MS, REMIND_COOLDOWN_MS } from "../public/tutorial.js";

// An in-memory stand-in for the game's localStorage wrapper.
function memStore(init = {}) {
  const data = { ...init };
  return { data, get: (k) => (k in data ? data[k] : null), set: (k, v) => void (data[k] = String(v)) };
}

// A tutorial with a fake clock, a settable game context, and a record of what it showed and hid.
function rig({ store = memStore(), ctx = "explore" } = {}) {
  const r = { store, ctx, t: 1000, shown: [], hidden: [], nudged: [] };
  r.tips = createTutorial({
    store,
    context: () => r.ctx,
    now: () => r.t,
    show: (id) => r.shown.push(id),
    hide: (id) => r.hidden.push(id),
    nudge: (id) => r.nudged.push(id),
  });
  r.wait = (ms) => {
    r.t += ms;
    r.tips.tick();
  };
  return r;
}

test("every hint is one or two short lines with a known context", () => {
  for (const [id, h] of Object.entries(HINTS)) {
    assert.ok(["explore", "combat", "any"].includes(h.ctx), `${id}: ctx`);
    assert.ok(h.lines.length >= 1 && h.lines.length <= 2, `${id}: 1-2 lines`);
    for (const line of h.lines) {
      const visible = parseLine(line)
        .map((t) => t.text ?? ` ${t.key} `)
        .join("");
      assert.ok(visible.length <= 46, `${id}: "${visible}" is too long (${visible.length})`);
      assert.equal(line, line.toUpperCase(), `${id}: the UI is all caps`);
    }
  }
});

test("the brief's moments all have a hint", () => {
  for (const id of ["move", "map", "stairs", "combat", "target", "feeling", "recruit", "ally", "camp", "levelup", "down", "boss"]) assert.ok(HINTS[id], id);
  assert.match(HINTS.combat.lines.join(" "), /\{!?T\}.*TALK/, "the first fight teaches that you can talk");
});

test("hints refer to controls by key, never by screen position", () => {
  const all = Object.values(HINTS)
    .flatMap((h) => h.lines)
    .join(" ");
  assert.doesNotMatch(all, /\b(TOP|BOTTOM|LEFT PANEL|RIGHT PANEL|BAR|ABOVE|BELOW|CORNER)\b/);
});

test("parseLine splits keycaps out of the text, with ! marking the hot key", () => {
  assert.deepEqual(parseLine("PRESS {!T} TO TALK"), [{ text: "PRESS " }, { key: "T", hot: true }, { text: " TO TALK" }]);
  assert.deepEqual(parseLine("{1}{2}"), [{ key: "1", hot: false }, { key: "2", hot: false }]);
  assert.deepEqual(parseLine("NO KEYS"), [{ text: "NO KEYS" }]);
});

test("a hint shows once, and stays seen across sessions", () => {
  const store = memStore();
  const a = rig({ store });
  assert.equal(a.tips.hint("move"), true);
  assert.deepEqual(a.shown, ["move"]);
  assert.equal(a.tips.current(), "move");
  assert.equal(a.tips.hint("move"), false, "already showing");
  a.wait(GRACE_MS);
  assert.equal(a.tips.dismiss(), true);
  assert.equal(a.tips.hint("move"), false, "already seen");
  assert.deepEqual(JSON.parse(store.data[SEEN_KEY]), ["move"]);

  const b = rig({ store });
  assert.equal(b.tips.seen("move"), true);
  assert.equal(b.tips.hint("move"), false);
  assert.deepEqual(b.shown, []);
});

test("unknown ids are ignored, and a corrupt store doesn't break anything", () => {
  const r = rig({ store: memStore({ [SEEN_KEY]: "{not json" }) });
  assert.equal(r.tips.hint("nope"), false);
  assert.equal(r.tips.hint("move"), true);
});

test("a key right after a hint appears doesn't dismiss it; a later one does", () => {
  const r = rig();
  r.tips.hint("move");
  r.t += GRACE_MS - 1;
  assert.equal(r.tips.dismiss(), false, "inside the grace period (held key, or the key that triggered it)");
  assert.equal(r.tips.current(), "move");
  r.t += 1;
  assert.equal(r.tips.dismiss(), true);
  assert.equal(r.tips.current(), null);
  assert.deepEqual(r.hidden, ["move"]);
});

test("a forced dismiss (click, menu) works immediately", () => {
  const r = rig();
  r.tips.hint("move");
  assert.equal(r.tips.dismiss({ force: true }), true);
  assert.equal(r.tips.current(), null);
});

test("hints queue one at a time, with a short breath between them", () => {
  const r = rig();
  r.tips.hint("move");
  r.tips.hint("map");
  assert.deepEqual(r.shown, ["move"]);
  assert.deepEqual(r.tips.pending(), ["map"]);
  r.wait(GRACE_MS);
  r.tips.dismiss();
  r.tips.tick();
  assert.deepEqual(r.shown, ["move"], "not straight away");
  r.wait(GAP_MS);
  assert.deepEqual(r.shown, ["move", "map"]);
});

test("explore hints wait out a fight; combat hints wait out exploring", () => {
  const r = rig({ ctx: "combat" });
  r.tips.hint("ally"); // you recruit mid-fight, but E only talks to allies outside one
  assert.deepEqual(r.shown, []);
  r.ctx = "explore";
  r.wait(GAP_MS);
  assert.deepEqual(r.shown, ["ally"]);
});

test("a combat hint whose fight ended before it got its turn is dropped, and can come back next fight", () => {
  const r = rig({ ctx: "combat" });
  r.tips.hint("combat");
  r.tips.hint("feeling");
  assert.deepEqual(r.tips.pending(), ["feeling"]);
  r.ctx = "explore";
  r.wait(MIN_READ_MS);
  assert.equal(r.tips.current(), null, "the fight hint goes away with the fight");
  assert.deepEqual(r.tips.pending(), [], "its moment passed");
  assert.equal(r.tips.seen("feeling"), false);
  r.ctx = "combat";
  assert.equal(r.tips.hint("feeling"), true);
  r.wait(GAP_MS);
  assert.equal(r.tips.current(), "feeling");
});

test("'any' hints show in both fights and exploring", () => {
  const r = rig({ ctx: "combat" });
  r.tips.hint("levelup");
  assert.equal(r.tips.current(), "levelup");
});

test("nothing shows during a Roll of Fate or game over; a hint cut short comes back after", () => {
  const r = rig();
  r.tips.hint("stairs");
  r.ctx = "roll";
  r.wait(100);
  assert.equal(r.tips.current(), null);
  r.tips.hint("boss");
  r.wait(GAP_MS);
  assert.deepEqual(r.shown, ["stairs"]);
  r.ctx = "explore";
  r.wait(GAP_MS);
  assert.equal(r.tips.current(), "stairs", "shown for only 100ms, so it gets another go");
  r.wait(GRACE_MS);
  r.tips.dismiss();
  r.wait(GAP_MS);
  assert.equal(r.tips.current(), "boss");
});

test("a hint nobody dismisses fades on its own", () => {
  const r = rig();
  r.tips.hint("move");
  r.wait(TTL_MS + 1);
  assert.equal(r.tips.current(), null);
});

test("turning tips off hides the current one, drops the queue and persists", () => {
  const store = memStore();
  const r = rig({ store });
  r.tips.hint("move");
  r.tips.hint("map");
  r.tips.setEnabled(false);
  assert.equal(r.tips.on(), false);
  assert.equal(r.tips.current(), null);
  assert.deepEqual(r.tips.pending(), []);
  assert.equal(r.tips.hint("stairs"), false);
  assert.equal(store.data[OFF_KEY], "1");
  assert.equal(rig({ store }).tips.on(), false, "remembered");
  r.tips.setEnabled(true);
  assert.equal(r.tips.hint("stairs"), true);
  assert.equal(rig({ store }).tips.on(), true);
});

test("reset forgets every seen hint", () => {
  const store = memStore();
  const r = rig({ store });
  r.tips.hint("move");
  r.tips.dismiss({ force: true });
  r.tips.reset();
  assert.equal(r.tips.seen("move"), false);
  assert.deepEqual(JSON.parse(store.data[SEEN_KEY]), []);
  r.wait(GAP_MS);
  assert.equal(r.tips.hint("move"), true);
});

test("H turns tips off; H again turns them back on from the start, with no menu to wait on", () => {
  const r = rig({ ctx: "combat" });
  const said = [];
  const say = (text) => said.push(text);
  r.tips.hint("combat");
  r.tips.hint("feeling");
  assert.equal(r.tips.toggle(say), false);
  assert.equal(r.tips.on(), false);
  assert.equal(r.tips.current(), null);
  assert.match(said.at(-1), /OFF.*H/);

  assert.equal(r.tips.toggle(say), true);
  assert.equal(r.tips.on(), true);
  assert.equal(r.tips.seen("feeling"), false, "back on means from the start");
  assert.equal(r.tips.current(), "combat", "and the reminder for where you are shows right away");
  assert.match(said.at(-1), /FROM THE START/);
});

test("each hint lights up the real thing it talks about: its keys' buttons, the map, the party", () => {
  assert.deepEqual(focusOf("combat"), ['[data-key="f"]', '[data-key="c"]', '[data-key="e"]', '[data-key="t"]']);
  assert.deepEqual(focusOf("move"), ['[data-key="fwd"]', '[data-key="turnL"]', '[data-key="turnR"]', '[data-key="back"]']);
  assert.ok(focusOf("map").includes("#map"));
  assert.ok(focusOf("boss").includes("#map"));
  assert.ok(focusOf("down").some((s) => s.startsWith("#party")));
  assert.ok(!focusOf("levelup").includes('[data-key="c"]'), "C means CAMP outside a fight, so don't light it up there");
  assert.deepEqual(focusOf("nope"), []);
});

test("the key that acts also clears the hint; a key the game ignores nudges it instead", () => {
  const r = rig({ ctx: "combat" });
  r.tips.hint("combat");
  r.wait(GRACE_MS);
  r.tips.ignored("fwd"); // trying to walk away mid-fight does nothing
  r.tips.keyed();
  assert.equal(r.tips.current(), "combat", "still there");
  assert.deepEqual(r.nudged, ["combat"]);
  r.tips.keyed(); // a key the game used
  assert.equal(r.tips.current(), null);
});

test("modifier and other non-command keys are never treated as ignored commands", () => {
  const r = rig();
  r.tips.hint("move");
  for (const k of ["shift", "capslock", "tab", "meta"]) r.tips.ignored(k);
  assert.deepEqual(r.nudged, []);
});

test("flailing with no hint up brings back the reminder for where you are, but not too often", () => {
  const r = rig({ ctx: "combat" });
  r.tips.hint("combat");
  r.tips.dismiss({ force: true });
  r.wait(GAP_MS);
  r.tips.ignored("w");
  assert.equal(r.tips.current(), null, "one stray key is fine");
  r.t += 500;
  r.tips.ignored("w");
  assert.equal(r.tips.current(), "combat", "two in a row: here's how fighting works again");
  r.tips.dismiss({ force: true });
  r.wait(GAP_MS);
  r.tips.ignored("x");
  r.tips.ignored("x");
  assert.equal(r.tips.current(), null, "cooling down");
  r.wait(REMIND_COOLDOWN_MS);
  r.tips.ignored("x");
  r.tips.ignored("x");
  assert.equal(r.tips.current(), "combat");
});

test("no reminders when tips are off", () => {
  const r = rig();
  r.tips.setEnabled(false);
  r.tips.ignored("t");
  r.tips.ignored("t");
  assert.equal(r.tips.current(), null);
});

test("hints step aside while a yes/no question is up, and come back after", () => {
  const r = rig();
  r.tips.hint("stairs");
  r.ctx = "prompt";
  r.wait(100);
  assert.equal(r.tips.current(), null);
  r.ctx = "explore";
  r.wait(GAP_MS);
  assert.equal(r.tips.current(), "stairs");
});

test("importing the module touches no DOM (works in Node)", async () => {
  const mod = await import("../public/tutorial.js");
  assert.equal(typeof mod.initTutorial, "function");
  assert.equal(typeof globalThis.document, "undefined");
});

// ---- the guided first fight
import { GUIDE, guideAllows, shouldGuide } from "../public/tutorial.js";

test("the first fight is a lesson: T first, then R, and every other fight key waits", () => {
  assert.equal(guideAllows("talk", "t"), true);
  for (const k of ["f", "c", "r", "g", "v", "e", "1"]) assert.equal(guideAllows("talk", k), false, k);
  assert.equal(guideAllows("recruit", "r"), true);
  for (const k of ["f", "c", "t", "g", "v", "e"]) assert.equal(guideAllows("recruit", k), false, k);
  assert.equal(guideAllows(null, "f"), true, "no lesson, no lock");
  assert.equal(GUIDE.talk.next, "recruit");
  assert.equal(GUIDE.recruit.next, null);
  for (const step of Object.values(GUIDE)) {
    assert.ok(HINTS[step.hint], step.hint);
    assert.deepEqual(focusOf(step.hint), [`[data-key="${step.key}"]`], "the tip lights up only the key to press");
  }
});

test("only a new player's first ordinary fight on the first floor is guided", () => {
  const base = { floor: 1, tipsOn: true, seen: () => false };
  assert.equal(shouldGuide(base), true);
  assert.equal(shouldGuide({ ...base, floor: 2 }), false);
  assert.equal(shouldGuide({ ...base, tipsOn: false }), false, "tips off (H): no lesson");
  assert.equal(shouldGuide({ ...base, seen: (id) => id === GUIDE.talk.hint }), false, "learned it already");
});

test("a key held back by the lesson keeps its tip up, or brings it back, never the generic reminder", () => {
  const r = rig({ ctx: "combat" });
  r.tips.hint("talkFirst");
  assert.equal(r.tips.current(), "talkFirst");
  r.wait(GRACE_MS + 10);
  r.tips.insist("talkFirst"); // F pressed: locked
  assert.equal(r.tips.keyed(), false, "the locked key doesn't clear the tip");
  assert.deepEqual(r.nudged, ["talkFirst"]);
  r.tips.dismiss({ force: true });
  r.wait(GAP_MS + 10);
  r.tips.insist("talkFirst");
  r.tips.insist("talkFirst");
  assert.equal(r.tips.current(), "talkFirst", "back up after being clicked away");
  assert.ok(!r.shown.includes("combat"), "not the F-QUICK-ATTACK reminder");
});
