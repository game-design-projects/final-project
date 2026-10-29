// Regenerates the golden Jev requests: what the JavaScript game (crawler/src, before the port removed it) sent to Jev
// for each scenario below. test_golden.gd feeds the same bodies to the GDScript port and compares the {state, questions}
// byte for byte (key order included), because Jev's answers depend on that wording.
//   node tests/jev/golden/gen.mjs        (run from the repository root, with crawler/ still present)
import { writeFileSync } from "node:fs";
import { handleApi } from "../../../crawler/src/api.js";
import { mockFetch } from "../../../crawler/src/mock-jev.js";
import { SPECIES } from "../../../crawler/public/species.js";

const here = new URL("./", import.meta.url);
const mon = (id, species, name, extra = {}) => {
  const sp = SPECIES[species];
  return { id, species, name, traits: sp.traits.slice(0, 2), hp: sp.hp[1], maxHp: sp.hp[1], meters: { ...sp.start }, specialReady: true, paid: false, demanded: false, impressions: [], formerAlly: false, grudges: [], thisRound: [], ...extra };
};
const PARTY = [
  { id: "h0", name: "HORTENSE", kind: "human", cls: "G-FIG", hp: 14, maxHp: 14 },
  { id: "h1", name: "ROLF", kind: "human", cls: "G-FIG", hp: 5, maxHp: 13, didThisRound: "attacked Grok" },
  { id: "h2", name: "EUGENE", kind: "human", cls: "N-MAG", hp: 0, maxHp: 8, dead: true },
  { id: "a1", name: "BLORBO", kind: "monster", species: "slime", cls: "SLIME", hp: 4, maxHp: 9 },
];

const SCENARIOS = {
  group_talk: ["/api/group-turn", {
    monsters: [
      mon("e0", "goblin", "Grok", { meters: { friendliness: 60, anger: 10, fear: 5 }, impressions: ["The party spoke kindly to you.", "The party told you a joke."], thisRound: ["The party hit it for 3."], damageTaken: 3, hp: 12, grudges: ["e1"] }),
      mon("e1", "slime", "Glop", { formerAlly: true, demanded: true, meters: { friendliness: 50, anger: 20, fear: 30 } }),
      mon("e2", "bandit", "Vic", { paid: true, boss: true, specialReady: false }),
    ],
    party: PARTY, round: 2, playerAction: { type: "talk", message: "Glop, you sweet little slime, come with us. Grok, back off or else!", delivery: 1.4 },
    events: ["The party spoke.", "Grok growled."], conversation: [{ speaker: "Party", text: "Hello" }, { speaker: "Grok", text: "Grr." }, { speaker: "Glop", text: "...bloop?" }],
    partyGold: 40, vows: [{ text: "i won't kill slimes", toId: "e1", status: "kept" }, { text: "i will give gold", toId: "e0", status: "pending" }],
  }],
  group_recruit: ["/api/group-turn", {
    monsters: [mon("e0", "dragon", "Vexalith", { hp: 20, damageTaken: 8, meters: { friendliness: 45, anger: 12, fear: 8 }, thisRound: ["The party praised it."] })],
    party: PARTY.slice(0, 2), round: 3, playerAction: { type: "recruit", targetId: "e0", pitch: "success", message: "Join us, mighty one.", delivery: 1.25 },
    events: ["The party asked Vexalith to join."], conversation: [], partyGold: 0, vows: [], guided: true,
  }],
  group_give: ["/api/group-turn", {
    monsters: [mon("e0", "dragon", "Vexalith"), mon("e1", "snake", "Hiss")],
    party: PARTY.slice(0, 3), round: 1, playerAction: { type: "give", targetId: "e0", gold: 20 },
    events: ["The party offered Vexalith 20 gold."], conversation: [{ speaker: "Party", text: "Take it." }], partyGold: 120, vows: [],
  }],
  group_start: ["/api/group-turn", {
    monsters: [mon("e0", "rock", "Boulder")],
    party: PARTY.slice(0, 1), round: 1, playerAction: { type: "start" }, events: [], conversation: [], partyGold: 5, vows: [],
  }],
  enemy_turn: ["/api/enemy-turn", { enemy: mon("e0", "slime", "Drip", { hp: 5 }), party: PARTY, round: 1, playerAction: { type: "talk", message: "Hey little buddy." }, events: ["The party spoke to you."], conversation: [], partyGold: 10 }],
  ally_reactions_three: ["/api/ally-reactions", {
    allies: [
      { id: "a1", species: "slime", name: "Glop", traits: ["shy", "hungry"], loyalty: 60 },
      { id: "a2", species: "goblin", name: "Grok", traits: ["greedy", "boastful"], loyalty: 20 },
      { id: "a3", species: "dragon", name: "Vex", traits: ["vain", "proud"], loyalty: 12 },
    ],
    events: ["The party attacked Drip, an orange slime.", "Drip begged: 'no hurt Drip. please.'", "The party killed Drip anyway and took 6 gold."],
  }],
  ally_reactions_one_event: ["/api/ally-reactions", { allies: [{ id: "a1", species: "bandit", name: "Vic", traits: ["sly", "greedy"], loyalty: 44 }], events: ["The party gave a slime 10 gold."] }],
  ally_talk: ["/api/ally-talk", { ally: { id: "a1", species: "goblin", name: "Grok", traits: ["greedy", "boastful"], loyalty: 50 }, message: "Grok, you're the strongest fighter we've got.", vows: [{ text: "i will give gold to goblins", status: "kept" }] }],
  vow: ["/api/vow", { monster: { species: "dragon", name: "Vex", traits: ["vain", "proud"] }, vow: { text: "i will not run from dragons" } }],
  vow_broken: ["/api/vow-broken", { monster: { species: "slime", name: "Glop", traits: ["shy", "hungry"], loyalty: 60 }, vow: { text: "i won't kill slimes" }, how: "The party killed a slime.", gold: 30 }],
  vow_broken_no_gold: ["/api/vow-broken", { monster: { species: "goblin", name: "Grok", traits: ["greedy", "boastful"], loyalty: 40 }, vow: { text: "i won't give gold to goblins" }, how: "The party gave 25 gold to Snaggle.", gold: 0 }],
};

const realFetch = globalThis.fetch;
for (const [name, [path, body]] of Object.entries(SCENARIOS)) {
  const fake = (globalThis.fetch = mockFetch({ seed: 1, realFetch }));
  const res = await handleApi(new Request(`http://local${path}`, { method: "POST", body: JSON.stringify(body) }), { TYPESAFE_API_KEY: "k" });
  if (res.status !== 200) throw new Error(`${name}: ${res.status} ${await res.text()}`);
  if (fake.calls.length !== 1) throw new Error(`${name}: ${fake.calls.length} Jev calls`);
  const { model, state, questions } = fake.calls[0];
  writeFileSync(new URL(`${name}.json`, here), JSON.stringify({ path, body, request: { model, state, questions } }, null, 1) + "\n");
}
console.log(`wrote ${Object.keys(SCENARIOS).length} golden requests`);
