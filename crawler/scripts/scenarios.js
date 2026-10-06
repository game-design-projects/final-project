// Scripted encounters against the live Jev API. Usage: node crawler/scripts/scenarios.js [filter]
try {
  process.loadEnvFile(new URL("../../.env", import.meta.url));
} catch {}
const { configureJev } = await import("../src/jev.js");
configureJev(process.env.TYPESAFE_API_KEY);
const { enemyTurn } = await import("../src/enemy.js");
const { allyReactions } = await import("../src/allies.js");
const { SPECIES } = await import("../public/species.js");

const PARTY = [
  { id: "p0", name: "HORTENSE", kind: "human", cls: "G-FIG", hp: 14, maxHp: 14 },
  { id: "p1", name: "ROLF", kind: "human", cls: "G-FIG", hp: 13, maxHp: 13 },
  { id: "p2", name: "EUGENE", kind: "human", cls: "N-MAG", hp: 8, maxHp: 8 },
];

function enemy(species, name, extra = {}) {
  const sp = SPECIES[species];
  return { species, name, traits: [sp.traits[0], sp.traits[1]], hp: sp.hp[1], maxHp: sp.hp[1], meters: { ...sp.start }, specialReady: true, paid: false, demanded: false, impressions: [], formerAlly: false, ...extra };
}

async function encounter(title, e, turns, partyGold = 40) {
  console.log(`\n━━ ${title} ━━`);
  const conversation = [];
  for (const [i, t] of turns.entries()) {
    const events = t.type === "talk" ? ["The party spoke to you."] : t.type === "give" ? [`The party offered you ${t.gold} gold.`] : t.type === "fight" ? ["The whole party attacked you."] : [];
    const r = await enemyTurn({ enemy: e, party: PARTY, round: i + 1, playerAction: t, events, conversation, partyGold });
    if (t.message) conversation.push({ speaker: "Party", text: t.message });
    conversation.push({ speaker: e.name, text: r.line });
    Object.assign(e, { meters: r.meters, impressions: r.impressions });
    if (r.action === "accept_tribute") e.paid = true;
    if (r.action === "demand_tribute") e.demanded = true;
    const top = r.probabilities.slice(0, 3).map((x) => `${x.id} ${Math.round(x.p * 100)}%`).join(", ");
    console.log(`> ${t.message ? `“${t.message}”` : `[${t.type}${t.gold ? " " + t.gold : ""}]`}`);
    console.log(`  jev: ${top}${r.blocked ? `  | BLOCKED ${r.picked}: ${r.blocked}` : ""}`);
    console.log(`  ${e.name} [${r.action}${r.targetId ? " → " + r.targetId : ""}]: ${r.line}`);
    console.log(`  mood f${r.meters.friendliness} a${r.meters.anger} fear${r.meters.fear} | ${r.ms}ms ${r.questionCount}q`);
    if (["join_party", "flee", "leave_peacefully"].includes(r.action)) break;
  }
}

async function reactions(title, allies, events) {
  console.log(`\n━━ ${title} ━━`);
  events.forEach((e) => console.log(`  event: ${e}`));
  const r = await allyReactions({ allies, events });
  for (const x of r.reactions)
    console.log(`  ${x.name}: approval ${x.approval.toFixed(2)} loyalty ${x.loyalty} (${x.delta >= 0 ? "+" : ""}${x.delta}) ${x.decision}${x.blocked ? ` [${x.blocked}]` : ""} — ${x.line}`);
  console.log(`  ${r.ms}ms ${r.questionCount}q`);
}

const talk = (message) => ({ type: "talk", message });
const only = process.argv[2];
const run = (name, fn) => (!only || name.includes(only) ? fn() : null);

await run("slime_friend", () =>
  encounter("befriend a slime", enemy("slime", "Glop"), [
    { type: "start" },
    talk("Hey little buddy, we won't hurt you. What's your name?"),
    talk("Why did the slime cross the road? To get to the other slide!"),
    talk("You're great, Glop. Want to come adventure with us?"),
  ]),
);
await run("slime_shy_retry", () =>
  encounter("shy slime: invite too early, then again", enemy("slime", "Squish", { traits: ["hungry", "shy"] }), [
    { type: "start" },
    talk("Hello friend! Why did the slime blush? It saw the dungeon's dressing! Hehe."),
    talk("You're wonderful. Come adventure with us, we'll keep you safe and fed."),
    talk("It's okay to be shy. We really like you, Squish. Please join us?"),
  ]),
);
await run("goblin_rude", () =>
  encounter("insult a goblin", enemy("goblin", "Grok"), [
    { type: "start" },
    talk("Out of the way, you stinking brainless lump."),
    { type: "fight" },
  ]),
);
await run("dragon_tribute", () =>
  encounter("flatter and pay a dragon", enemy("dragon", "Vexalith"), [
    { type: "start" },
    talk("Mighty Vexalith, your scales outshine the sun. We mean no disrespect."),
    { type: "give", gold: 20 },
    { type: "give", gold: 80 },
    talk("Might we pass, great one?"),
  ], 120),
);
await run("allies_cruel", () =>
  reactions(
    "slime + goblin allies watch the party kill a begging slime",
    [
      { id: "a1", species: "slime", name: "Glop", traits: ["shy", "hungry"], loyalty: 60 },
      { id: "a2", species: "goblin", name: "Grok", traits: ["greedy", "boastful"], loyalty: 60 },
    ],
    ["The party attacked Drip, an orange slime.", "Drip begged: 'no hurt Drip. please.'", "The party killed Drip anyway and took 6 gold."],
  ),
);
await run("allies_generous", () =>
  reactions(
    "allies watch the party pay a goblin to go away",
    [
      { id: "a1", species: "slime", name: "Glop", traits: ["shy", "hungry"], loyalty: 40 },
      { id: "a2", species: "goblin", name: "Grok", traits: ["greedy", "short-tempered"], loyalty: 20 },
    ],
    ["The party met Snaggle, a huge brown goblin.", "The party gave Snaggle 25 gold.", "Snaggle left peacefully."],
  ),
);
await run("allies_betray", () =>
  reactions(
    "a resentful goblin watches the party flee and give away gold again",
    [{ id: "a2", species: "goblin", name: "Grok", traits: ["greedy", "short-tempered"], loyalty: 12 }],
    ["The party gave a slime 10 gold.", "The party ran away from a yellow dragon."],
  ),
);
