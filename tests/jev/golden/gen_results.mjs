// Regenerates results.json: a few dozen generated requests, and what the JavaScript game's rules decided for each when
// Jev answered with the scripted answers below. test_golden_results.gd replays them through the GDScript port with the
// same scripted answers and compares the whole reply (meters, actions, blocked reasons, lines, loyalty...).
//   node tests/jev/golden/gen_results.mjs        (run from the repository root, with crawler/ still present)
//
// The scripted Jev is deterministic (a hash of the question name), and its action answers are one-hot (a 0.9 pick and
// a 0.1 runner-up, under the 15% roll floor) so the monsters' dice never matter. What stays random in the JS (the
// leave/betray line, the theft) is left out of the comparison.
import { writeFileSync } from "node:fs";
import { handleApi } from "../../../crawler/src/api.js";
import { seeded } from "../../../crawler/src/mock-jev.js";
import { SPECIES } from "../../../crawler/public/species.js";

console.info = () => {};
console.error = () => {};

export function hash(key, seed) {
  let h = (2166136261 ^ Math.imul(seed, 2654435761)) >>> 0;
  for (const c of key) {
    h ^= c.charCodeAt(0);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}
const NOULS = [0, 0.2, 0.35, 0.55, 0.65, 0.75, 0.95, 1];
const CONFIDENCE = [0.1, 0.2, 0.3, 0.9];
export function scripted(key, q, seed) {
  const h = hash(key, seed);
  if (q.type === "noul") return { type: "noul", noul: NOULS[h % 8] };
  if (q.type === "score") return { type: "score", score: (h % (4 * (q.criteria.length - 1) + 1)) / 4 };
  const keys = Object.keys(q.criteria);
  const pick = keys[h % keys.length];
  const other = keys[(h >>> 8) % keys.length];
  const probabilities = Object.fromEntries(keys.map((k) => [k, 0]));
  probabilities[pick] = other === pick ? 1 : 0.9;
  if (other !== pick) probabilities[other] = 0.1;
  return { type: "choice", choice: pick, probabilities, confidence: CONFIDENCE[(h >>> 16) % 4] };
}

const rand = seeded(20261029);
const int = (a, b) => a + Math.floor(rand() * (b - a + 1));
const pick = (a) => a[Math.floor(rand() * a.length)];
const chance = (p) => rand() < p;
const kinds = Object.keys(SPECIES);
const NAMES = ["Grok", "Glop", "Vex", "Hiss", "Rocky", "Vic", "Snag", "Drip"];
const MESSAGES = [
  "Hello there, friend.", "You're wonderful, come adventure with us!", "Out of the way, you stinking brainless lump.", "We'll pay you well. Take this gold.",
  "Why did the slime cross the road?", "Please, let us pass in peace.", "Join us, we will keep you safe.", "Surrender or die!", "Mighty one, we mean no harm.",
];
const EVENTS = ["The party spoke.", "The party attacked Grok.", "Grok growled.", "The party cast a spell.", "The party hit it for 4.", "Nothing much happened.", "The party offered 20 gold."];

const mon = (id, extra = {}) => {
  const species = pick(kinds);
  const sp = SPECIES[species];
  const maxHp = int(sp.hp[0], sp.hp[1] + 20);
  return {
    id, species, name: pick(NAMES), traits: sp.traits.slice(int(0, 3), int(0, 3) + 2), hp: int(1, maxHp), maxHp,
    meters: { friendliness: int(0, 100), anger: int(0, 100), fear: int(0, 100) },
    specialReady: chance(0.6), paid: chance(0.2), demanded: chance(0.2), formerAlly: chance(0.2), boss: chance(0.15),
    impressions: Array.from({ length: int(0, 3) }, (_, i) => `Impression ${i}`), grudges: [], thisRound: chance(0.5) ? [pick(EVENTS)] : [], damageTaken: chance(0.5) ? int(0, 12) : 0,
    ...extra,
  };
};
const party = () =>
  Array.from({ length: int(1, 5) }, (_, i) =>
    chance(0.25)
      ? { id: `a${i}`, name: pick(NAMES).toUpperCase(), kind: "monster", species: pick(kinds), hp: int(1, 9), maxHp: 9, dead: chance(0.15) }
      : { id: `h${i}`, name: pick(["HORTENSE", "ROLF", "EUGENE", "MARA"]), kind: "human", cls: pick(["G-FIG", "N-MAG"]), hp: int(0, 14), maxHp: 14, dead: chance(0.15), ...(chance(0.3) ? { didThisRound: "attacked" } : {}) },
  );

function groupCase() {
  const monsters = Array.from({ length: int(1, 3) }, (_, i) => mon(`e${i}`));
  monsters.forEach((m, i) => {
    if (monsters.length > 1 && chance(0.4)) m.grudges = [monsters[(i + 1) % monsters.length].id];
  });
  const type = pick(["talk", "talk", "recruit", "give", "start", "fight"]);
  const target = pick(monsters).id;
  const playerAction =
    type === "talk" ? { type, message: pick(MESSAGES), delivery: pick([0.5, 1, 1.25, 2]) }
    : type === "recruit" ? { type, targetId: target, pitch: pick(["great", "success", "close", "fail", "botch"]), message: chance(0.5) ? pick(MESSAGES) : null, delivery: pick([0.75, 1, 1.5]) }
    : type === "give" ? { type, targetId: target, gold: pick([1, 3, 10, 25, 60]) }
    : type === "fight" ? { type, targetId: target }
    : { type };
  return ["/api/group-turn", {
    monsters, party: party(), round: int(1, 6), playerAction, events: Array.from({ length: int(0, 3) }, () => pick(EVENTS)),
    conversation: Array.from({ length: int(0, 4) }, (_, i) => ({ speaker: i % 2 ? "Party" : monsters[0].name, text: pick(MESSAGES) })),
    partyGold: pick([0, 5, 30, 120]), vows: chance(0.3) ? [{ text: "i won't kill slimes", toId: monsters[0].id, status: pick(["kept", "pending"]) }] : [], guided: chance(0.15),
  }];
}
const allyOf = (i) => ({ id: `a${i}`, species: pick(kinds), name: pick(NAMES), traits: ["greedy", "shy"], loyalty: pick([5, 12, 20, 29, 31, 44, 46, 70, 95]) });
const cases = [];
for (let i = 0; i < 90; i++) cases.push(groupCase());
for (let i = 0; i < 3; i++) cases.push(["/api/enemy-turn", { enemy: mon("x"), party: party(), round: 1, playerAction: pick([{ type: "start" }, { type: "talk", message: pick(MESSAGES) }]), events: [], conversation: [], partyGold: 10 }]);
for (let i = 0; i < 16; i++)
  cases.push(["/api/ally-reactions", { allies: Array.from({ length: int(1, 3) }, (_, k) => allyOf(k)), events: Array.from({ length: int(1, 3) }, () => pick(EVENTS)) }]);
for (let i = 0; i < 6; i++) cases.push(["/api/ally-talk", { ally: allyOf(1), message: pick(MESSAGES), vows: chance(0.5) ? [{ text: "i will give gold", status: "kept" }] : [] }]);
for (let i = 0; i < 6; i++) cases.push(["/api/vow", { monster: { species: pick(kinds), name: pick(NAMES), traits: ["vain"] }, vow: { text: pick(["i won't kill slimes", "i will give gold to goblins"]) } }]);
for (let i = 0; i < 16; i++)
  cases.push(["/api/vow-broken", { monster: { species: pick(kinds), name: pick(NAMES), traits: ["vain"], loyalty: pick([10, 40, 56, 80, 100]) }, vow: { text: "i won't kill slimes" }, how: "The party killed a slime.", gold: pick([0, 30, 100]) }]);

const out = [];
for (const [n, [path, body]] of cases.entries()) {
  const seed = 1000 + n;
  globalThis.fetch = async (url, init) => {
    const { questions } = JSON.parse(init.body);
    const answers = Object.fromEntries(Object.entries(questions).map(([k, q]) => [k, scripted(k, q, seed)]));
    return new Response(JSON.stringify({ answers, usage: { input_tokens: 7 }, model: "scripted" }), { status: 200 });
  };
  const res = await handleApi(new Request(`http://local${path}`, { method: "POST", body: JSON.stringify(body) }), { TYPESAFE_API_KEY: "k" });
  out.push({ path, seed, body, status: res.status, expected: await res.json() });
}
writeFileSync(new URL("results.json", import.meta.url), JSON.stringify(out) + "\n");
const tally = {};
for (const c of out) for (const r of c.expected.results ?? c.expected.reactions ?? []) tally[r.action ?? r.decision] = (tally[r.action ?? r.decision] ?? 0) + 1;
for (const c of out) if (c.path === "/api/vow-broken") tally[`broken:${c.expected.response}`] = (tally[`broken:${c.expected.response}`] ?? 0) + 1;
console.log(`wrote ${out.length} cases; decisions:`, tally, "statuses:", [...new Set(out.map((c) => c.status))]);
