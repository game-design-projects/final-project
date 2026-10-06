// Achievements (crawler/public/achievements.js): the list, once-only unlocks, persistence, counters, secret display,
// a broken localStorage, and that every game event the hooks send unlocks the right one. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ACHIEVEMENTS, GROUPS, GLYPHS, ACH_KEY, createAchievements, badgeSvg, toastHtml, screenHtml, fmtDate } from "../public/achievements.js";
import { EMOTIONS } from "../public/emotions.js";
import { SPECIES } from "../public/species.js";

function memStore(init = {}) {
  const data = { ...init };
  return { data, get: (k) => (k in data ? data[k] : null), set: (k, v) => void (data[k] = String(v)) };
}

// An achievements instance with a fake clock and a record of what it unlocked.
function rig(store = memStore()) {
  const r = { store, t: Date.UTC(2026, 9, 5, 12), unlocked: [] };
  r.ach = createAchievements({ store, now: () => r.t, onUnlock: (a) => r.unlocked.push(a.id) });
  return r;
}

const byId = Object.fromEntries(ACHIEVEMENTS.map((a) => [a.id, a]));

test("20 to 30 achievements, each with a unique id, a short all-caps name and line, a known glyph and group", () => {
  assert.ok(ACHIEVEMENTS.length >= 20 && ACHIEVEMENTS.length <= 30, `${ACHIEVEMENTS.length}`);
  assert.equal(new Set(ACHIEVEMENTS.map((a) => a.id)).size, ACHIEVEMENTS.length);
  for (const a of ACHIEVEMENTS) {
    assert.match(a.id, /^[a-z0-9_]+$/, a.id);
    assert.equal(a.name, a.name.toUpperCase(), `${a.id}: name is all caps`);
    assert.equal(a.desc, a.desc.toUpperCase(), `${a.id}: line is all caps`);
    assert.ok(a.name.length <= 17, `${a.id}: name "${a.name}" is too long`);
    assert.ok(a.desc.length <= 64, `${a.id}: line "${a.desc}" is too long (${a.desc.length})`);
    assert.ok(GLYPHS[a.icon], `${a.id}: glyph ${a.icon}`);
    assert.ok(GROUPS[a.group], `${a.id}: group ${a.group}`);
  }
  for (const g of Object.values(GLYPHS)) {
    assert.equal(g.length, 7);
    for (const row of g) assert.match(row, /^[#.]{7}$/);
  }
});

test("the brief's moments are all covered", () => {
  for (const id of ["charmed", "stitches", "peacemaker", "all_talk", "first_friend", "shiny", "mash", "red_carpet", "word_is_bond", "second_chance", "walked_out", "betrayed", "crit_happens", "fail_forward", "still_breathing", "not_today", "deep5", "deep10", "seeing_red", "stand_down", "legendary", "goblin_tax", "so_vain"])
    assert.ok(byId[id], id);
  assert.ok(ACHIEVEMENTS.some((a) => a.secret), "some are secret");
  assert.ok(ACHIEVEMENTS.some((a) => a.goal), "some count up");
});

test("an achievement unlocks once, with the time it was earned", () => {
  const r = rig();
  assert.equal(r.ach.unlock("charmed"), true);
  assert.equal(r.ach.unlock("charmed"), false);
  r.ach.on("feel", { feeling: "delighted", species: "slime" });
  assert.deepEqual(r.unlocked, ["charmed"]);
  assert.equal(r.ach.has("charmed"), true);
  assert.equal(r.ach.earnedAt("charmed"), r.t);
  assert.equal(r.ach.unlock("nope"), false, "unknown ids are ignored");
});

test("unlocks survive a reload (same store), and a new run doesn't forget them", () => {
  const store = memStore();
  const a = rig(store);
  a.ach.unlock("first_friend");
  const saved = JSON.parse(store.data[ACH_KEY]);
  assert.equal(saved.earned.first_friend, a.t);
  const b = rig(store);
  assert.equal(b.ach.has("first_friend"), true);
  assert.equal(b.ach.earnedAt("first_friend"), a.t);
  assert.equal(b.ach.unlock("first_friend"), false);
  assert.deepEqual(b.unlocked, []);
  assert.deepEqual(b.ach.count(), { earned: 1, total: ACHIEVEMENTS.length });
});

test("counters count each distinct thing once, persist, and unlock at the goal", () => {
  const store = memStore();
  const a = rig(store);
  const feelings = Object.keys(EMOTIONS);
  assert.equal(byId.empath.goal, feelings.length);
  a.ach.on("feel", { feeling: "confused", species: "slime" });
  a.ach.on("feel", { feeling: "confused", species: "goblin" });
  a.ach.on("feel", { feeling: "bogus", species: "goblin" });
  assert.deepEqual(a.ach.progress("empath"), { n: 1, goal: feelings.length });
  const b = rig(store);
  assert.deepEqual(b.ach.progress("empath"), { n: 1, goal: feelings.length }, "kept across reloads");
  for (const f of feelings) b.ach.on("feel", { feeling: f, species: "rock" });
  assert.equal(b.ach.has("empath"), true);
  assert.deepEqual(b.ach.progress("empath"), { n: feelings.length, goal: feelings.length });

  const species = Object.keys(SPECIES);
  assert.equal(byId.menagerie.goal, species.length);
  for (const s of species.slice(0, -1)) b.ach.on("recruit", { species: s, allies: 1 });
  assert.equal(b.ach.has("menagerie"), false);
  b.ach.on("recruit", { species: species.at(-1), allies: 1 });
  assert.equal(b.ach.has("menagerie"), true);
  assert.equal(b.ach.progress("charmed"), null, "a one-off has no counter");
});

test("secret achievements read ??? until earned; the rest show their line while locked", () => {
  const r = rig();
  const shown = (id) => r.ach.list().find((x) => x.id === id);
  assert.ok(byId.so_vain.secret);
  assert.equal(shown("so_vain").name, "???");
  assert.equal(shown("so_vain").desc, "???");
  assert.equal(shown("so_vain").earned, false);
  assert.equal(shown("charmed").name, byId.charmed.name, "not secret: readable while locked");
  r.ach.on("feel", { feeling: "flattered", species: "dragon" });
  assert.equal(shown("so_vain").name, byId.so_vain.name);
  assert.equal(shown("so_vain").desc, byId.so_vain.desc);
  assert.equal(shown("so_vain").at, r.t);
  r.ach.on("feel", { feeling: "flattered", species: "goblin" });
  assert.deepEqual(r.unlocked, ["so_vain"], "only a dragon counts");
});

test("a corrupt or foreign localStorage value never breaks it", () => {
  for (const raw of ["{not json", "[]", "null", "42", '"x"', JSON.stringify({ earned: { nope: 1, charmed: "yesterday", stitches: 5 }, progress: { empath: "all", menagerie: ["slime", "slime", "kraken"] } })]) {
    const store = memStore({ [ACH_KEY]: raw });
    const r = rig(store);
    assert.equal(r.ach.has("nope"), false, raw);
    assert.equal(r.ach.has("charmed"), false, `${raw}: a non-numeric date is dropped`);
    assert.ok(r.ach.count().earned <= 1, raw);
    assert.ok(r.ach.progress("empath").n === 0, raw);
    assert.ok(r.ach.progress("menagerie").n <= 1, `${raw}: duplicates and unknown species are dropped`);
    assert.equal(r.ach.unlock("charmed"), true, raw);
    assert.equal(JSON.parse(store.data[ACH_KEY]).earned.charmed, r.t, `${raw}: rewritten cleanly`);
  }
  const kept = rig(memStore({ [ACH_KEY]: JSON.stringify({ earned: { stitches: 5 } }) }));
  assert.equal(kept.ach.has("stitches"), true, "good entries survive next to bad ones");
});

test("a store that throws is survivable", () => {
  const store = { get: () => { throw new Error("blocked"); }, set: () => { throw new Error("blocked"); } };
  const ach = createAchievements({ store });
  assert.equal(ach.unlock("charmed"), true);
  assert.equal(ach.has("charmed"), true, "still earned for this session");
});

test("unknown events and events outside a fight are ignored", () => {
  const r = rig();
  r.ach.on("nonsense", { a: 1 });
  r.ach.on("attack");
  r.ach.on("fight-end", { won: true, kills: 0 });
  r.ach.on("feel");
  assert.deepEqual(r.unlocked, []);
});

test("talking: delighted, in stitches, terrified, a peaceful exit", () => {
  const r = rig();
  r.ach.on("feel", { feeling: "delighted", species: "slime" });
  r.ach.on("feel", { feeling: "amused", species: "goblin" });
  r.ach.on("feel", { feeling: "terrified", species: "bandit" });
  r.ach.on("peace", { species: "snake" });
  assert.deepEqual(r.unlocked, ["charmed", "stitches", "boo", "peacemaker"]);
});

test("ALL TALK: a fight won with no attack and no kill; an attack, a kill or running away spoils it", () => {
  const r = rig();
  r.ach.on("fight-start");
  r.ach.on("attack");
  r.ach.on("fight-end", { won: true, kills: 0 });
  r.ach.on("fight-start");
  r.ach.on("fight-end", { won: true, kills: 1 }); // an ally's opening lightning killed it
  r.ach.on("fight-start");
  r.ach.on("fight-end", { won: false, kills: 0 }); // fled
  assert.deepEqual(r.unlocked, []);
  r.ach.on("fight-start");
  r.ach.on("fight-end", { won: true, kills: 0 });
  assert.deepEqual(r.unlocked, ["all_talk"]);
});

test("recruiting: first friend, a shiny, a champion, three monster allies at once", () => {
  const r = rig();
  r.ach.on("recruit", { species: "slime", shiny: false, boss: false, allies: 1 });
  assert.deepEqual(r.unlocked, ["first_friend"]);
  r.ach.on("recruit", { species: "goblin", shiny: true, boss: false, allies: 2 });
  r.ach.on("recruit", { species: "dragon", shiny: false, boss: true, allies: 3 });
  assert.deepEqual(r.unlocked, ["first_friend", "shiny", "red_carpet", "mash"]);
});

test("FAIL FORWARD: a 1 while talking, then a monster joins or lets you pass in that same fight", () => {
  const r = rig();
  r.ach.on("fight-start");
  r.ach.on("recruit", { species: "slime", allies: 1 });
  r.ach.on("talk-roll", { roll: 1 });
  r.ach.on("fight-start"); // a new fight forgets the fumble
  r.ach.on("peace", { species: "slime" });
  assert.ok(!r.unlocked.includes("fail_forward"));
  r.ach.on("talk-roll", { roll: 1 });
  r.ach.on("peace", { species: "rock" });
  assert.ok(r.unlocked.includes("fail_forward"));
});

test("dice: a natural 20 on an attack, a natural 20 while talking, death saves", () => {
  const r = rig();
  r.ach.on("attack-roll", { roll: 19 });
  r.ach.on("talk-roll", { roll: 19 });
  r.ach.on("death-save", { roll: 15, stable: false });
  assert.deepEqual(r.unlocked, []);
  r.ach.on("attack-roll", { roll: 20 });
  r.ach.on("talk-roll", { roll: 20 });
  r.ach.on("death-save", { roll: 12, stable: true });
  r.ach.on("death-save", { roll: 20, stable: false });
  assert.deepEqual(r.unlocked, ["crit_happens", "mic_drop", "still_breathing", "not_today"]);
});

test("descending: floors 5 and 10, and a vow carried down the stairs", () => {
  const r = rig();
  r.ach.on("descend", { floor: 2, keptVows: 0 });
  assert.deepEqual(r.unlocked, []);
  r.ach.on("descend", { floor: 5, keptVows: 1 });
  assert.deepEqual(r.unlocked, ["deep5", "word_is_bond"]);
  r.ach.on("descend", { floor: 10, keptVows: 0 });
  assert.deepEqual(r.unlocked, ["deep5", "word_is_bond", "deep10"]);
});

test("champions and fate: slain, talked down, a legendary boon", () => {
  const r = rig();
  r.ach.on("fight-start");
  r.ach.on("attack");
  r.ach.on("fight-end", { won: true, kills: 1, boss: "dead" });
  r.ach.on("peace", { species: "goblin", boss: true });
  r.ach.on("boon", { name: "WHETSTONE", great: true, legendary: false });
  r.ach.on("boon", { name: "PHOENIX FEATHER", great: true, legendary: true });
  assert.deepEqual(r.unlocked, ["seeing_red", "peacemaker", "stand_down", "legendary"]);
});

test("broken vows and unhappy allies: forgiven, walked out, betrayed, robbed", () => {
  const r = rig();
  r.ach.on("vow-broken", { response: "forgive" });
  r.ach.on("vow-broken", { response: "steal_gold", stolen: false }); // caught it: it stays
  assert.deepEqual(r.unlocked, ["second_chance"]);
  r.ach.on("vow-broken", { response: "steal_gold", stolen: true });
  r.ach.on("ally-decision", { decision: "stay" });
  r.ach.on("ally-decision", { decision: "leave_party" });
  r.ach.on("vow-broken", { response: "attack_party" });
  assert.deepEqual(r.unlocked, ["second_chance", "robbed", "walked_out", "betrayed"]);
  const b = rig();
  b.ach.on("ally-decision", { decision: "turn_on_party" });
  b.ach.on("vow-broken", { response: "leave_party" });
  assert.deepEqual(b.unlocked, ["betrayed", "walked_out"]);
});

test("oddities: paying a goblin (not a bandit), a mutiny, losing the party", () => {
  const r = rig();
  r.ach.on("paid", { species: "bandit", gold: 20 });
  assert.deepEqual(r.unlocked, []);
  r.ach.on("paid", { species: "goblin", gold: 20 });
  r.ach.on("mutiny", { species: "goblin" });
  r.ach.on("wipe", { floor: 3 });
  assert.deepEqual(r.unlocked, ["goblin_tax", "mutiny", "permadeath"]);
});

test("every achievement can be earned through the hooks' events", () => {
  const r = rig();
  const events = [
    ["fight-start"], ["talk-roll", { roll: 1 }], ["talk-roll", { roll: 20 }], ["attack-roll", { roll: 20 }],
    ...Object.keys(EMOTIONS).map((f) => ["feel", { feeling: f, species: "dragon" }]),
    ["peace", { species: "rock", boss: true }],
    ...Object.keys(SPECIES).map((s, i) => ["recruit", { species: s, shiny: i === 0, boss: i === 1, allies: Math.min(3, i + 1) }]),
    ["fight-end", { won: true, kills: 0, boss: "dead" }],
    ["death-save", { roll: 20, stable: false }], ["death-save", { roll: 10, stable: true }],
    ["descend", { floor: 10, keptVows: 1 }], ["boon", { legendary: true }],
    ["vow-broken", { response: "forgive" }], ["vow-broken", { response: "steal_gold", stolen: true }],
    ["ally-decision", { decision: "leave_party" }], ["ally-decision", { decision: "turn_on_party" }],
    ["paid", { species: "goblin" }], ["mutiny", {}], ["wipe", {}],
  ];
  for (const [ev, data] of events) r.ach.on(ev, data);
  const missing = ACHIEVEMENTS.filter((a) => !r.ach.has(a.id)).map((a) => a.id);
  assert.deepEqual(missing, []);
  assert.equal(new Set(r.unlocked).size, r.unlocked.length, "each fired once");
});

test("reset forgets everything", () => {
  const store = memStore();
  const r = rig(store);
  r.ach.unlock("charmed");
  r.ach.on("feel", { feeling: "sad", species: "slime" });
  r.ach.reset();
  assert.deepEqual(r.ach.count(), { earned: 0, total: ACHIEVEMENTS.length });
  assert.equal(r.ach.progress("empath").n, 0);
  assert.equal(rig(store).ach.has("charmed"), false);
});

test("the toast and the screen: escaped, secret-safe, with the total", () => {
  const r = rig();
  r.ach.unlock("charmed");
  r.ach.on("feel", { feeling: "sad", species: "slime" });
  const toast = toastHtml(r.ach.list().find((a) => a.id === "charmed"), r.ach.count());
  assert.match(toast, /CHARMER/);
  assert.match(toast, /1\/\d+/);
  const text = screenHtml(r.ach.list(), r.ach.count()).replace(/<[^>]+>/g, ""); // what the player reads
  const has = (s) => text.includes(s);
  assert.ok(has(`1/${ACHIEVEMENTS.length}`), "the total");
  assert.ok(has("???"), "locked secrets");
  assert.ok(!has(byId.so_vain.name) && !has(byId.so_vain.desc), "a locked secret never leaks its name or line");
  assert.ok(has("1/10"), "counter progress shows");
  assert.ok(has("EARNED OCT 5 2026"), "earned ones show the date");
  assert.match(badgeSvg("trophy", "#fff"), /^<svg/);
  assert.equal(fmtDate(Date.UTC(2026, 0, 31, 12)), "JAN 31 2026");
});

test("importing the module touches no DOM (works in Node)", async () => {
  const mod = await import("../public/achievements.js");
  assert.equal(typeof mod.initAchievements, "function");
  assert.equal(typeof globalThis.document, "undefined");
});
