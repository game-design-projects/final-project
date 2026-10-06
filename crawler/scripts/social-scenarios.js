// Group encounters, ally talk and vows. Usage: node crawler/scripts/social-scenarios.js [filter] [--live] [--seed=N]
// By default Jev is mocked (src/mock-jev.js): random but well-formed answers, no key, no credits, repeatable
// with --seed. That checks the plumbing and the game's rules, not Jev's judgement; pass --live for real calls.
const args = process.argv.slice(2);
const live = args.includes("--live");
const seed = Number(args.find((a) => a.startsWith("--seed="))?.slice(7) ?? 1);
const { configureJev } = await import("../src/jev.js");
if (live) {
  try {
    process.loadEnvFile(new URL("../../.env", import.meta.url));
  } catch {}
  configureJev(process.env.TYPESAFE_API_KEY);
  console.log("LIVE Jev: every call is billed.");
} else {
  const { mockFetch } = await import("../src/mock-jev.js");
  globalThis.fetch = mockFetch({ seed });
  configureJev("mock");
  console.log(`MOCK Jev (seed ${seed}): random answers, no credits. Add --live for real calls.`);
}
const { groupTurn } = await import("../src/enemy.js");
const { allyTalk, vowMade, vowBroken } = await import("../src/bonds.js");
const { SPECIES } = await import("../public/species.js");

const PARTY = [
  { id: "h0", name: "HORTENSE", kind: "human", cls: "G-FIG", hp: 14, maxHp: 14 },
  { id: "h1", name: "ROLF", kind: "human", cls: "G-FIG", hp: 13, maxHp: 13 },
  { id: "h2", name: "EUGENE", kind: "human", cls: "N-MAG", hp: 8, maxHp: 8 },
];
const mon = (id, species, name, extra = {}) => {
  const sp = SPECIES[species];
  return { id, species, name, traits: sp.traits.slice(0, 2), hp: sp.hp[1], maxHp: sp.hp[1], meters: { ...sp.start }, specialReady: true, paid: false, demanded: false, impressions: [], formerAlly: false, grudges: [], thisRound: [], ...extra };
};
const only = args.find((a) => !a.startsWith("--"));
const run = async (name, fn) => (!only || name.includes(only) ? fn() : null);

await run("group", async () => {
  console.log("\n━━ goblin + slime: be kind to the slime, insult the goblin ━━");
  let monsters = [mon("e0", "goblin", "Grok"), mon("e1", "slime", "Glop")];
  const conversation = [];
  const turns = [
    { type: "start" },
    { type: "talk", message: "Glop, you sweet little slime, we'd never hurt you. Grok, you smelly brute, back off." },
    { type: "talk", message: "Glop, come with us, you'll be safe in our party. Grok is a bully." },
    { type: "fight", targetId: "e0" },
  ];
  for (const [i, t] of turns.entries()) {
    if (!monsters.length) {
      console.log("  (every monster has left)");
      break;
    }
    const out = await groupTurn({ monsters, party: PARTY, round: i + 1, playerAction: t, events: t.type === "fight" ? ["The party attacked Grok."] : t.type === "talk" ? ["The party spoke."] : [], conversation, partyGold: 30, vows: [] });
    console.log(`> ${t.message ? `“${t.message}”` : `[${t.type}]`}   (${out.ms} ms, ${out.questionCount} q)`);
    for (const r of out.results) {
      const m = monsters.find((x) => x.id === r.id);
      console.log(`  ${m.name} [${r.action}${r.monsterTargetId ? ` → ${r.monsterTargetId}` : ""}] f${r.meters.friendliness} a${r.meters.anger} (${r.side})${r.blocked ? ` BLOCKED ${r.picked}: ${r.blocked}` : ""} — ${r.line}`);
      conversation.push({ speaker: m.name, text: r.line });
      Object.assign(m, { meters: r.meters, impressions: r.impressions, thisRound: [] });
    }
    if (t.message) conversation.push({ speaker: "Party", text: t.message });
    if (t.type === "fight" && monsters[0]) monsters[0].thisRound = ["The party hit it for 6."];
    monsters = monsters.filter((m) => !out.results.find((r) => r.id === m.id && ["flee", "leave_peacefully", "join_party"].includes(r.action)));
  }
});

await run("talk", async () => {
  console.log("\n━━ ally talk ━━");
  for (const [species, name, msg] of [
    ["goblin", "Grok", "Grok, you're the strongest fighter we've got. Next chest we find, you get first pick of the loot."],
    ["slime", "Glop", "Glop, you're slow and you slow us down."],
    ["dragon", "Vexalith", "Mighty Vexalith, we fight beside a legend. Watch us be brave for you."],
  ]) {
    const r = await allyTalk({ ally: { id: "a1", species, name, traits: SPECIES[species].traits.slice(0, 2), loyalty: 55 }, message: msg, vows: [] });
    console.log(`  ${name}: resonance ${r.resonance.toFixed(2)} loyalty ${r.loyaltyDelta >= 0 ? "+" : ""}${r.loyaltyDelta} buff ${r.buff?.id ?? "none"} — ${r.line}`);
  }
});

await run("vow", async () => {
  console.log("\n━━ vows made ━━");
  for (const [species, name, text] of [
    ["slime", "Glop", "I won't kill slimes"],
    ["goblin", "Grok", "I will give gold to goblins"],
    ["goblin", "Grok", "I won't give gold to goblins"],
    ["dragon", "Vexalith", "I won't run from dragons"],
  ]) {
    const r = await vowMade({ monster: { species, name, traits: SPECIES[species].traits.slice(0, 2) }, vow: { text } });
    console.log(`  ${name} hears "${text}": liking ${r.liking.toFixed(2)} — ${r.line}`);
  }
  console.log("\n━━ vows broken ━━");
  for (const [species, name, loyalty, text, how] of [
    ["slime", "Glop", 60, "I won't kill slimes", "The party killed Drip, an orange slime, while it begged for mercy."],
    ["goblin", "Grok", 40, "I won't give gold to goblins", "The party gave 25 gold to Snaggle, another goblin."],
    ["dragon", "Vexalith", 70, "I won't run from dragons", "The party ran away from a yellow dragon."],
  ]) {
    const r = await vowBroken({ monster: { species, name, traits: SPECIES[species].traits.slice(0, 2), loyalty }, vow: { text }, how, gold: 60 });
    const top = Object.entries(r.probabilities).sort((a, b) => b[1] - a[1]).map(([k, p]) => `${k} ${Math.round(p * 100)}%`).join(", ");
    console.log(`  ${name} (loyalty ${loyalty}): ${r.response}${r.blocked ? ` [${r.blocked}]` : ""}${r.stolen ? ` stole ${r.stolen}` : ""}${r.caught ? " CAUGHT" : ""} | ${top} — ${r.line}`);
  }
});
