// The game's API end to end against the mock Jev (no key, no credits): every endpoint answers, debug mode
// returns each raw Jev call, and the key never shows. Run with `npm test`.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { handleApi } from "../src/api.js";
import { mockFetch, mockAnswer, seeded } from "../src/mock-jev.js";
import { SPECIES } from "../public/species.js";

const KEY = "test-key-never-shown";
let realFetch;
let fake;
before(() => {
  realFetch = globalThis.fetch;
  fake = globalThis.fetch = mockFetch({ seed: 42 });
});
after(() => (globalThis.fetch = realFetch));

const PARTY = [
  { id: "h0", name: "HORTENSE", kind: "human", hp: 14, maxHp: 14 },
  { id: "h1", name: "ROLF", kind: "human", hp: 13, maxHp: 13 },
];
const mon = (id, species, name) => {
  const sp = SPECIES[species];
  return { id, species, name, traits: sp.traits.slice(0, 2), hp: sp.hp[1], maxHp: sp.hp[1], meters: { ...sp.start }, specialReady: true, impressions: [], grudges: [], thisRound: [] };
};
const call = async (path, body, debug = false) => {
  const headers = { "content-type": "application/json" };
  const url = `http://local${path}${debug ? "?debug=1" : ""}`;
  const res = await handleApi(new Request(url, { method: "POST", headers, body: JSON.stringify(body) }), { TYPESAFE_API_KEY: KEY });
  return { status: res.status, text: await res.text() };
};

const ENDPOINTS = {
  "/api/group-turn": { monsters: [mon("e0", "goblin", "Grok"), mon("e1", "slime", "Glop")], party: PARTY, round: 1, playerAction: { type: "talk", message: "Glop, join us?" }, events: ["The party spoke."], conversation: [], partyGold: 40 },
  "/api/enemy-turn": { enemy: mon("e0", "slime", "Drip"), party: PARTY, round: 1, playerAction: { type: "start" }, events: [], conversation: [], partyGold: 10 },
  "/api/ally-reactions": { allies: [{ id: "a1", species: "slime", name: "Glop", traits: ["shy", "hungry"], loyalty: 60 }], events: ["The party killed a begging slime."] },
  "/api/ally-talk": { ally: { id: "a1", species: "goblin", name: "Grok", traits: ["greedy", "boastful"], loyalty: 50 }, message: "You fought well.", vows: [] },
  "/api/vow": { monster: { species: "dragon", name: "Vex", traits: ["vain", "proud"] }, vow: { text: "i will not run from dragons" } },
  "/api/vow-broken": { monster: { species: "slime", name: "Glop", traits: ["shy", "hungry"] }, vow: { text: "i won't kill slimes" }, how: "The party killed a slime.", gold: 30 },
};

for (const [path, body] of Object.entries(ENDPOINTS)) {
  test(`${path} works against the mock Jev`, async () => {
    const { status, text } = await call(path, structuredClone(body));
    assert.equal(status, 200, text);
    assert.ok(!JSON.parse(text)._debug, "no debug data unless asked");
  });

  test(`${path} in debug mode returns every raw Jev call, and never the key`, async () => {
    const before = fake.calls.length;
    const { status, text } = await call(path, structuredClone(body), true);
    assert.equal(status, 200, text);
    const { _debug } = JSON.parse(text);
    assert.ok(_debug?.jev?.length >= 1);
    assert.equal(_debug.jev.length, fake.calls.length - before, "one trace entry per Jev call");
    for (const c of _debug.jev) {
      assert.ok(c.state && c.questions && c.response?.answers, "request and response both recorded");
      assert.equal(c.status, 200);
      assert.ok(c.ms >= 0);
    }
    assert.ok(!text.includes(KEY), "the API key must never be in a response");
  });
}

test("mock answers have the shape the SDK documents", () => {
  const r = seeded(3);
  const n = mockAnswer({ type: "noul" }, r);
  assert.ok(n.noul >= 0 && n.noul <= 1);
  const c = mockAnswer({ type: "choice", criteria: { a: "x", b: "y", c: "z" } }, r);
  assert.ok(["a", "b", "c"].includes(c.choice));
  assert.ok(Math.abs(Object.values(c.probabilities).reduce((s, p) => s + p, 0) - 1) < 1e-9);
  assert.equal(c.probabilities[c.choice], Math.max(...Object.values(c.probabilities)));
  const s = mockAnswer({ type: "score", criteria: ["no", "some", "lots", "very"] }, r);
  assert.ok(s.score >= 0 && s.score <= 3);
  assert.deepEqual(Object.keys(s.probabilities), ["0", "1", "2", "3"]);
});

test("the same seed gives the same answers", () => {
  const q = { type: "choice", criteria: { a: 1, b: 2, c: 3 } };
  assert.deepEqual(mockAnswer(q, seeded(9)), mockAnswer(q, seeded(9)));
});

test("with an OpenRouter key, Jev is reached through OpenRouter (same answers, model ~typesafe/jev-latest)", async () => {
  const before = fake.calls.length;
  const res = await handleApi(
    new Request("http://local/api/vow?debug=1", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(ENDPOINTS["/api/vow"]) }),
    { OPENROUTER_API_KEY: "or-test-key" },
  );
  assert.equal(res.status, 200);
  const out = await res.json();
  assert.equal(fake.calls.at(-1).model, "~typesafe/jev-latest");
  assert.equal(out._debug.jev[0].via, "openrouter");
  assert.ok(fake.calls.length > before);
  assert.ok(!JSON.stringify(out).includes("or-test-key"));
});
