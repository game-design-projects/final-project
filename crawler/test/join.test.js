// The recruit flow end to end: the answer to "join us?" agrees with what the log says. Jev is stubbed with canned
// answers (no API calls, no credits). Run with `npm test`.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { resolveJoin, groupTurn } from "../src/enemy.js";
import { configureJev } from "../src/jev.js";
import { groupLog } from "../public/narrate.js";
import { EMOTIONS } from "../public/emotions.js";
import { SPECIES } from "../public/species.js";

const emotion = (id) => ({ ...EMOTIONS[id], id });

test("resolveJoin: eligible and willing says yes, with Jev's reason", () => {
  const r = resolveJoin({ invited: true, meters: { friendliness: 70, anger: 0 }, threshold: 65, willing: 0.8, yesWhy: "gold", noWhy: "pride" });
  assert.deepEqual(r, { asked: true, accepted: true, moved: false, reason: "gold" });
});

test("resolveJoin: eligible but unwilling refuses with Jev's reason (it likes you, but...)", () => {
  const r = resolveJoin({ invited: true, meters: { friendliness: 90, anger: 0 }, threshold: 65, willing: 0.2, yesWhy: "gold", noWhy: "loyal" });
  assert.deepEqual(r, { asked: true, accepted: false, moved: false, reason: "loyal" });
});

test("resolveJoin: under its bar it refuses even if Jev is keen", () => {
  const r = resolveJoin({ invited: true, meters: { friendliness: 50, anger: 0 }, threshold: 65, willing: 0.9, noWhy: "wants_more" });
  assert.equal(r.accepted, false);
  assert.equal(r.reason, "wants_more");
});

test("resolveJoin: an angry or offended refusal gets an angry reason", () => {
  const angry = resolveJoin({ invited: true, meters: { friendliness: 90, anger: 40 }, threshold: 55, willing: 0.9, noWhy: "home" });
  assert.equal(angry.reason, "still_angry");
  const botched = resolveJoin({ invited: true, meters: { friendliness: 76, anger: 47 }, threshold: 55, willing: 0.9, noWhy: "not_yet", pitch: "botch" });
  assert.equal(botched.reason, "bad_pitch");
  // Offended this round: no yes, even with the meters still over the bar
  const offended = resolveJoin({ invited: true, meters: { friendliness: 80, anger: 20 }, threshold: 55, willing: 0.9, emotion: emotion("offended"), noWhy: "pride" });
  assert.deepEqual([offended.accepted, offended.reason], [false, "pride"]);
  const confused = resolveJoin({ invited: true, meters: { friendliness: 80, anger: 0 }, threshold: 55, willing: 0.9, emotion: emotion("confused"), noWhy: "pride" });
  assert.deepEqual([confused.accepted, confused.reason], [false, "confused"]);
});

test("resolveJoin: an invalid or missing reason falls back to one that fits", () => {
  assert.equal(resolveJoin({ invited: true, meters: { friendliness: 10, anger: 0 }, threshold: 55, noWhy: "confused" }).reason, "not_yet");
  assert.equal(resolveJoin({ invited: true, meters: { friendliness: 10, anger: 0 }, threshold: 55 }).reason, "not_yet");
  assert.equal(resolveJoin({ invited: true, meters: { friendliness: 90, anger: 0 }, threshold: 55, willing: 1 }).reason, "likes_you");
});

test("resolveJoin: a near-even answer is tipped by the action roll landing on join", () => {
  const base = { invited: true, meters: { friendliness: 70, anger: 0 }, threshold: 65, willing: 0.4 };
  assert.equal(resolveJoin(base).accepted, false);
  assert.equal(resolveJoin({ ...base, rolledJoin: true }).accepted, true);
  assert.equal(resolveJoin({ ...base, willing: 0.1, rolledJoin: true }).accepted, false);
});

test("resolveJoin: uninvited, only a touched or delighted monster over its bar asks to come", () => {
  const m = { friendliness: 80, anger: 0 };
  assert.equal(resolveJoin({ invited: false, meters: m, threshold: 55, willing: 0.9, emotion: emotion("amused") }), null);
  assert.deepEqual(resolveJoin({ invited: false, meters: m, threshold: 55, willing: 0.9, emotion: emotion("touched"), yesWhy: "grateful" }), {
    asked: true,
    accepted: true,
    moved: true,
    reason: "grateful",
  });
  assert.equal(resolveJoin({ invited: false, meters: { friendliness: 40, anger: 0 }, threshold: 55, willing: 0.9, emotion: emotion("touched") }), null);
  assert.equal(resolveJoin({ invited: true, meters: m, threshold: 55, willing: 1, room: false }), null);
});

// ---- groupTurn with a stubbed Jev

// Answers every question in the request: defaults that keep things calm, plus per-question overrides by suffix.
function fakeJev(overrides) {
  return async (url, init) => {
    const { questions } = JSON.parse(init.body);
    const answers = {};
    for (const [key, q] of Object.entries(questions)) {
      const suffix = key.split("__").slice(1).join("__");
      const keys = q.type === "score" ? null : Object.keys(q.criteria ?? {});
      let a;
      if (q.type === "noul") a = { noul: 0 };
      else if (q.type === "score") a = { score: 1 };
      else a = { choice: keys[0], probabilities: Object.fromEntries(keys.map((k, i) => [k, i === 0 ? 1 : 0])) };
      const o = overrides[suffix];
      if (o !== undefined) {
        if (q.type === "noul") a = { noul: o };
        else if (q.type === "score") a = { score: o };
        else if (typeof o === "string") a = { choice: o, probabilities: Object.fromEntries(keys.map((k) => [k, k === o ? 1 : 0])) };
        else a = { choice: Object.entries(o).sort((x, y) => y[1] - x[1])[0][0], probabilities: o };
      }
      answers[key] = { type: q.type, ...a, confidence: 0.9 };
    }
    globalThis.lastQuestions = questions;
    return new Response(JSON.stringify({ answers, usage: { input_tokens: 1 }, model: "fake" }), { status: 200 });
  };
}

const realFetch = globalThis.fetch;
beforeEach(() => configureJev("test-key"));
afterEach(() => {
  globalThis.fetch = realFetch;
});

const PARTY = [{ id: "h0", name: "HORTENSE", kind: "human", cls: "G-FIG", hp: 14, maxHp: 14 }];
const mon = (id, species, name, meters, extra = {}) => ({
  id, species, name, traits: SPECIES[species].traits.slice(0, 2), hp: 20, maxHp: 20, meters, specialReady: false,
  paid: false, demanded: false, impressions: [], formerAlly: false, grudges: [], thisRound: [], ...extra,
});
const recruit = (targetId, pitch) => ({ type: "recruit", targetId, pitch, message: null, delivery: 1.25 });
const turn = (monsters, playerAction) => groupTurn({ monsters, party: PARTY, round: 1, playerAction, events: [], conversation: [], partyGold: 30, vows: [] });

test("a convincing pitch brings it up to its bar, so the answer is its own choice", async () => {
  globalThis.fetch = fakeJev({ emotion: "intrigued", would_join: 0.9, join_yes: "strength", action: "converse" });
  const out = await turn([mon("e0", "goblin", "Grok", { friendliness: 40, anger: 10, fear: 5 })], recruit("e0", "success"));
  const r = out.results[0];
  assert.ok(globalThis.lastQuestions.e0__join_yes && globalThis.lastQuestions.e0__join_no, "reasons asked both ways");
  assert.equal(r.action, "join_party");
  assert.deepEqual([r.join.accepted, r.join.reason], [true, "strength"]);
  const log = groupLog(r, { name: "Grok", species: "goblin" });
  assert.ok(log.some((l) => l.text === "GROK: " + r.line));
  assert.ok(log.some((l) => /follow strength like yours/.test(l.text)));
});

test("friendly but refuses: no join, no attack, and the log says it won't leave its brother", async () => {
  globalThis.fetch = fakeJev({ emotion: "delighted", would_join: 0.1, join_no: "loyal", action: { join_party: 0.6, attack: 0.4 } });
  const out = await turn(
    [mon("e0", "goblin", "Grak", { friendliness: 62, anger: 5, fear: 5 }), mon("e1", "goblin", "Snag", { friendliness: 25, anger: 15, fear: 5 })],
    recruit("e0", "success"),
  );
  const r = out.results.find((x) => x.id === "e0");
  assert.equal(r.action, "converse");
  assert.equal(r.side, "friendly with the party");
  assert.deepEqual([r.join.accepted, r.join.reason, r.join.others], [false, "loyal", ["Snag"]]);
  assert.equal(r.spoken, false, "no cheerful small talk after a refusal");
  const log = groupLog(r, { name: "Grak", species: "goblin", sideBefore: "friendly with the party" });
  assert.ok(!log.some((l) => l.kind === "line"));
  assert.equal(log.find((l) => l.kind === "join").text, "Still, Grak shakes its big head and grunts that it won't leave Snag.");
});

test("a refusal in its own words uses the species' 'not yet' line", async () => {
  globalThis.fetch = fakeJev({ would_join: 0.1, join_no: "wants_more", action: "converse" });
  const out = await turn([mon("e0", "goblin", "Grok", { friendliness: 20, anger: 10, fear: 5 })], recruit("e0", "close"));
  const r = out.results[0];
  assert.deepEqual([r.action, r.spoken, r.line], ["converse", true, "Join you? Hmm. What's in it for Grok?"]);
});

test("wary but accepts: the slime joins and the log says it's still unsure, and why it comes", async () => {
  globalThis.fetch = fakeJev({ emotion: "intrigued", would_join: 0.7, join_yes: "company", action: "converse" });
  const out = await turn([mon("e0", "slime", "Glop", { friendliness: 45, anger: 0, fear: 30 })], recruit("e0", "close"));
  const r = out.results[0];
  assert.equal(r.meters.friendliness, 59); // 45, +6 for a near miss, +8 intrigued: over the slime's 55, still "wary"
  assert.equal(r.action, "join_party");
  const log = groupLog(r, { name: "Glop", species: "slime" });
  assert.equal(log.find((l) => l.kind === "join").text, "Even so, Glop wobbles closer and burbles that it won't be alone down here anymore.");
  assert.equal(groupLog({ ...r, emotion: null }, { name: "Glop", species: "slime" }).find((l) => l.kind === "join").text,
    "Glop still quivers a little, but burbles that it won't be alone down here anymore.");
});

test("a disastrous pitch to a friend: it refuses, and says it was the asking", async () => {
  globalThis.fetch = fakeJev({ emotion: "offended", would_join: 0.9, join_no: "not_yet", action: "join_party" });
  const out = await turn([mon("e0", "slime", "Drip", { friendliness: 90, anger: 0, fear: 10 })], recruit("e0", "botch"));
  const r = out.results[0];
  assert.equal(r.action, "converse");
  assert.deepEqual([r.join.accepted, r.join.reason], [false, "bad_pitch"]);
  const log = groupLog(r, { name: "Drip", species: "slime" });
  assert.deepEqual(
    log.map((l) => l.kind),
    ["feeling", "emotion", "join"],
  );
  assert.match(log.at(-1).text, /didn't like how you asked/);
});

test("touched monsters don't attack in the same breath", async () => {
  globalThis.fetch = fakeJev({ emotion: "touched", kindness: 3, action: "attack" });
  const out = await groupTurn({
    monsters: [mon("e0", "goblin", "Grak", { friendliness: 10, anger: 20, fear: 0 })],
    party: PARTY, round: 1, playerAction: { type: "talk", message: "We're sorry about your brother.", delivery: 1 }, events: [], conversation: [], partyGold: 0, vows: [],
  });
  assert.equal(out.results[0].action, "converse");
});

test("a tribute refusal carries its reason", async () => {
  globalThis.fetch = fakeJev({ action: "accept_tribute" });
  const out = await groupTurn({
    monsters: [mon("e0", "goblin", "Grok", { friendliness: 30, anger: 10, fear: 0 })],
    party: PARTY, round: 1, playerAction: { type: "give", gold: 3, targetId: "e0" }, events: [], conversation: [], partyGold: 30, vows: [],
  });
  assert.deepEqual([out.results[0].action, out.results[0].tributeRefusal], ["refuse_tribute", "too_little"]);
});
