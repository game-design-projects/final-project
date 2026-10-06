// Narration helpers: what the player reads instead of the Jev panel. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  VOICE,
  JOIN_NO,
  JOIN_YES,
  reasonOptions,
  moodOf,
  feelingLine,
  joinLine,
  sideLine,
  tributeLine,
  secondPerson,
  allyLine,
  reactionTell,
  reactionLineIndex,
  groupLog,
  nice,
} from "../public/narrate.js";
import { EMOTIONS } from "../public/emotions.js";
import { SPECIES } from "../public/species.js";

const WARM = { friendliness: 80, anger: 0, fear: 0 };
const WARY = { friendliness: 50, anger: 10, fear: 20 };

test("every species has a voice with every tell", () => {
  const keys = Object.keys(VOICE.slime);
  for (const sp of Object.keys(SPECIES)) {
    assert.ok(VOICE[sp], `${sp} has a voice`);
    assert.deepEqual(Object.keys(VOICE[sp]).sort(), [...keys].sort(), `${sp} has the same tells as the slime`);
  }
});

test("reason options: situational reasons only when they can be true, code-only reasons never", () => {
  const bare = reasonOptions(JOIN_NO, {});
  assert.ok(!("loyal" in bare) && !("burned" in bare) && !("confused" in bare));
  assert.ok("not_yet" in bare && "pride" in bare);
  const full = reasonOptions(JOIN_NO, { others: ["Snag"], formerAlly: true });
  assert.ok("loyal" in full && "burned" in full && !("confused" in full));
  assert.ok(!("kin" in reasonOptions(JOIN_YES, { kin: [] })));
  assert.ok("kin" in reasonOptions(JOIN_YES, { kin: ["GLOP"] }));
  for (const v of Object.values(full)) assert.equal(typeof v, "string");
});

test("mood: a feeling's tone wins, otherwise the meters", () => {
  assert.equal(moodOf(WARY, EMOTIONS.touched), "warm");
  assert.equal(moodOf(WARM, EMOTIONS.offended), "cold");
  assert.equal(moodOf(WARM, null), "warm");
  assert.equal(moodOf(WARY, null), "wary");
  assert.equal(moodOf({ friendliness: 10, anger: 0, fear: 0 }), "cold");
  assert.equal(moodOf({ friendliness: 50, anger: 0, fear: 80 }), "scared");
});

test("friendly but refuses: shows the warmth, then the reason, naming who it won't leave", () => {
  const s = joinLine("goblin", "GRAK", { asked: true, accepted: false, reason: "loyal", others: ["SNAG"] }, { meters: WARM });
  assert.equal(s, "Grak grins, showing crooked teeth, but grunts that it won't leave Snag.");
});

test("wary but accepts: says it still looks wary, then why it comes anyway", () => {
  const s = joinLine("slime", "GLOP", { asked: true, accepted: true, reason: "company" }, { meters: WARY });
  assert.equal(s, "Glop still quivers a little, but burbles that it won't be alone down here anymore.");
});

test("after a feeling line the answer leads with a gesture, and still flags the contrast", () => {
  const no = joinLine("goblin", "GRAK", { asked: true, accepted: false, reason: "pride" }, { meters: WARM, emotion: EMOTIONS.delighted, afterFeeling: true });
  assert.equal(no, "Still, Grak shakes its big head and grunts that it'll follow no one.");
  const yes = joinLine("snake", "SSITH", { asked: true, accepted: true, reason: "gold" }, { meters: WARY, emotion: EMOTIONS.intrigued, afterFeeling: true });
  assert.equal(yes, "Even so, Ssith uncoils slowly and hisses that it'll take a share of your gold and loot.");
});

test("plain yes and plain no read without a contrast", () => {
  assert.equal(
    joinLine("dragon", "VEXALITH", { asked: true, accepted: true, reason: "strength" }, { meters: WARM }),
    "Vexalith inclines its head and rumbles that it'll follow strength like yours.",
  );
  assert.equal(
    joinLine("rock", "BOULDER", { asked: true, accepted: false, reason: "still_angry" }, { meters: { friendliness: 20, anger: 50, fear: 0 } }),
    "Boulder does not move and grinds out that it can't forgive what you did. Not yet.",
  );
});

test("bandits are people: they, not it", () => {
  const s = joinLine("bandit", "ROOK", { asked: true, accepted: false, reason: "home" }, { meters: WARY });
  assert.equal(s, "Rook shakes their head and says that they won't leave their home on this floor.");
  assert.match(sideLine("bandit", "ROOK", "friendly with the party"), /out of them\.$/);
});

test("a monster moved to ask on its own says so", () => {
  const s = joinLine("slime", "GLOP", { asked: true, accepted: true, moved: true, reason: "likes_you" }, { meters: WARM });
  assert.equal(s, "Glop wobbles closer and asks to come with you. It can't help liking you.");
});

test("every join sentence is complete for every species, reason and mood", () => {
  for (const sp of Object.keys(SPECIES))
    for (const [table, accepted] of [[JOIN_YES, true], [JOIN_NO, false]])
      for (const reason of Object.keys(table))
        for (const meters of [WARM, WARY, { friendliness: 10, anger: 60, fear: 0 }])
          for (const afterFeeling of [false, true]) {
            const s = joinLine(sp, "NAME", { asked: true, accepted, reason, others: ["A", "B"], kin: ["C"] }, { meters, afterFeeling });
            assert.ok(s && !/[{}]|undefined|null/.test(s), `${sp}/${reason}: ${s}`);
            assert.match(s, /[.]$/);
          }
  assert.equal(joinLine("slime", "X", null), null);
  assert.equal(joinLine("slime", "X", { asked: false }), null);
});

test("unknown reasons fall back to something that still matches the outcome", () => {
  assert.match(joinLine("goblin", "G", { asked: true, accepted: true, reason: "??" }, { meters: WARM }), /can't help liking you/);
  assert.match(joinLine("goblin", "G", { asked: true, accepted: false, reason: "??" }, { meters: WARY }), /know you better/);
});

test("every feeling has a visible tell", () => {
  for (const id of Object.keys(EMOTIONS)) assert.ok(feelingLine("goblin", "GRAK", id)?.startsWith("Grak "), id);
  assert.equal(feelingLine("slime", "GLOP", "touched"), "Glop jiggles softly, its blank stare gone gentle. Your words reached it.");
  assert.equal(feelingLine("slime", "GLOP", "nope"), null);
});

test("tribute refusals say why", () => {
  assert.match(tributeLine("goblin", "GROK", "too_little"), /far too little/);
  assert.match(tributeLine("goblin", "GROK", "angry"), /no amount of gold/);
  assert.match(tributeLine("bandit", "ROOK", "not_for_sale"), /They can't be bought\.$/);
});

test("history is retold to the player in the second person", () => {
  assert.equal(secondPerson("The party killed Drip, an orange slime, while it begged for mercy."), "you killed Drip, an orange slime, while it begged for mercy");
  assert.equal(secondPerson("The party befriended Glop, who joined them."), "you befriended Glop, who joined you");
  assert.equal(secondPerson("Grak offered to join, but the party turned it away."), "grak offered to join, but you turned it away");
  assert.equal(nice("GRAK"), "Grak");
});

test("ally reactions: a walk-out names the moment, a near walk-out stays grumbling", () => {
  const moment = "The party killed Drip while it begged for mercy.";
  assert.equal(allyLine("slime", "GLOP", { level: 0, decision: "leave_party", picked: "leave_party", moment }), "Glop can't stomach how you killed Drip while it begged for mercy.");
  assert.match(allyLine("slime", "GLOP", { level: 1, decision: "stay", picked: "leave_party", moment }), /but stays\. For now\.$/);
  assert.match(allyLine("goblin", "GRAK", { level: 4, decision: "stay", picked: "stay", moment: "The party attacked Snag." }), /It liked how you attacked Snag\.$/);
  assert.equal(allyLine("goblin", "GRAK", { level: 2, decision: "stay", picked: "stay", moment }), null);
  assert.match(allyLine("rock", "BOULDER", { level: 0, decision: "turn_on_party", moment }), /won't forgive how you killed/);
});

test("talk and vow tells follow the level", () => {
  assert.match(reactionTell("goblin", "GRAK", 0), /bares its teeth/);
  assert.match(reactionTell("goblin", "GRAK", 1), /ears droop/);
  assert.equal(reactionTell("goblin", "GRAK", 2), null);
  assert.match(reactionTell("goblin", "GRAK", 4), /stands a little closer/);
});

test("reaction lines come from the bucket that matches the score", () => {
  const reactions = SPECIES.goblin.reactions; // 3 approve, 2 neutral, 3 disapprove
  // Jev's overall favorite is a happy line, but the score says it hated it
  const probs = { line_0: 0.7, line_1: 0.1, line_5: 0.05, line_6: 0.1, line_7: 0.05 };
  assert.equal(reactionLineIndex(probs, reactions, 0), 6);
  assert.equal(reactionLineIndex(probs, reactions, 4), 0);
  assert.equal(reactionLineIndex({}, reactions, 2), 3); // no odds: first neutral line
  for (let level = 0; level <= 4; level++) {
    const i = reactionLineIndex(probs, reactions, level);
    const bucket = level >= 3 ? reactions.approve : level === 2 ? reactions.neutral : reactions.disapprove;
    assert.ok(bucket.includes([...reactions.approve, ...reactions.neutral, ...reactions.disapprove][i]));
  }
});

const result = (extra) => ({
  action: "converse",
  picked: "converse",
  blocked: null,
  line: "Hur hur.",
  spoken: true,
  join: null,
  emotion: null,
  meters: WARM,
  side: "friendly with the party",
  ...extra,
});

test("group log: a narrated refusal replaces small talk, numbers only in debug", () => {
  const r = result({
    spoken: false,
    line: "unused",
    emotion: { ...EMOTIONS.delighted, id: "delighted", delta: { friendliness: 20 } },
    join: { asked: true, accepted: false, reason: "loyal", others: ["SNAG"] },
    picked: "join_party",
    blocked: "it turned the invitation down (loyal)",
  });
  const log = groupLog(r, { name: "GRAK", species: "goblin", sideBefore: "friendly with the party" });
  assert.deepEqual(log.map((l) => l.kind), ["feeling", "emotion", "join"]);
  assert.equal(log[1].text, "GRAK IS DELIGHTED: WON'T ATTACK THIS ROUND.");
  assert.equal(log[2].text, "Still, Grak shakes its big head and grunts that it won't leave Snag.");
  const dbg = groupLog(r, { name: "GRAK", species: "goblin", debug: true });
  assert.match(dbg.find((l) => l.kind === "emotion").text, /\(FRIENDLY \+20\)$/);
  assert.ok(dbg.some((l) => l.kind === "debug"));
});

test("group log: a joiner speaks, then says why", () => {
  const log = groupLog(result({ action: "join_party", line: "Fine. Grak joins.", join: { asked: true, accepted: true, reason: "gold" } }), { name: "GRAK", species: "goblin" });
  assert.deepEqual(log.map((l) => l.text), ["GRAK: Fine. Grak joins.", "Grak shoulders its club and grunts that it'll take a share of your gold and loot."]);
});

test("group log: a change of side is told, unless its action would contradict it", () => {
  const warmed = groupLog(result({}), { name: "GRAK", species: "goblin", sideBefore: "undecided about the party" });
  assert.match(warmed.at(-1).text, /the fight has gone out of it/);
  const swinging = groupLog(result({ action: "attack" }), { name: "GRAK", species: "goblin", sideBefore: "undecided about the party" });
  assert.ok(!swinging.some((l) => l.kind === "side"));
  const soured = groupLog(result({ side: "hostile to the party", meters: { friendliness: 20, anger: 40, fear: 0 } }), { name: "GRAK", species: "goblin", sideBefore: "undecided about the party" });
  assert.match(soured.at(-1).text, /You've made an enemy/);
  const cooled = groupLog(result({ side: "undecided about the party", meters: WARY }), { name: "GRAK", species: "goblin", sideBefore: "hostile to the party" });
  assert.equal(cooled.at(-1).text, "Grak eyes you sideways, less sure it'd like this fight.");
  const doubting = groupLog(result({ side: "undecided about the party", meters: WARY }), { name: "GRAK", species: "goblin", sideBefore: "friendly with the party" });
  assert.equal(doubting.at(-1).text, "Grak eyes you sideways, no longer sure of you.");
  // First reply: no side to compare with yet
  assert.ok(!groupLog(result({}), { name: "GRAK", species: "goblin", sideBefore: null }).some((l) => l.kind === "side"));
});

test("group log: a refused tribute says why", () => {
  const log = groupLog(result({ action: "refuse_tribute", tributeRefusal: "too_little" }), { name: "GROK", species: "goblin" });
  assert.match(log.at(-1).text, /far too little/);
});
