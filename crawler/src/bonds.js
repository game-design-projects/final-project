// Social moments outside the combat round: talking to an ally, making a vow, and breaking one.
// Jev judges feelings and picks from approved lines/responses; code owns the numbers and the odds.

import { choice, score } from "./q.js";
import { SPECIES, fill } from "../public/species.js";
import { reactionLineIndex } from "../public/narrate.js";
import { jev } from "./jev.js";

export const BUFFS = {
  slime: { id: "BOUNCY", desc: "absorbs the next hit on anyone in the party" },
  goblin: { id: "PUMPED", desc: "deals double damage next fight" },
  dragon: { id: "STORMING", desc: "opens the next fight with free lightning on every enemy" },
  snake: { id: "VENOMOUS", desc: "opens the next fight with a poisoned bite" },
  rock: { id: "BULWARK", desc: "soaks the next two hits on the party" },
  bandit: { id: "SNEAKY", desc: "brings in 50% more gold from the next fight" },
};
// Every talk does something, good or bad. By how the words landed (0..4): loyalty change and what happens.
const TALK_DELTA = [-15, -6, 3, 8, 14];
const TALK_OUTCOME = [
  { id: "SULKING", desc: "sulks and sits out the next fight" },
  { id: "DISTRACTED", desc: "is distracted: -2 to hit next fight" },
  { id: "STEADY", desc: "feels steady: +1 to hit next fight" },
  null, // its species buff
  { id: "INSPIRED", desc: "is inspired: heals fully and grows a level" },
];
const STEAL_CHANCE = 0.6;
const BREAK_PENALTY = 20;

const loyaltyWord = (v) => (v >= 75 ? "devoted" : v >= 50 ? "content" : v >= 30 ? "uneasy" : v >= 15 ? "resentful" : "on the verge of leaving");

function persona(m) {
  const sp = SPECIES[m.species];
  return { name: m.name, kind: sp.label, personality: [sp.nature, ...(m.traits ?? [])], likes: sp.likes, dislikes: sp.dislikes, values: sp.values };
}

function reactionLines(sp) {
  return [...sp.reactions.approve, ...sp.reactions.neutral, ...sp.reactions.disapprove];
}

function pickLine(answer, lines, name) {
  const i = Number(answer?.choice?.split("_")[1] ?? 0);
  return fill(lines[i] ?? lines[0], { name });
}

// A reaction line that agrees with how the words or promise landed (level 0..4), not just Jev's overall favorite.
function reactionLine(answer, sp, level, name) {
  return fill(reactionLines(sp)[reactionLineIndex(answer?.probabilities, sp.reactions, level)], { name });
}

const lineChoice = (question, lines, name) =>
  choice(question, Object.fromEntries(lines.map((l, i) => [`line_${i}`, fill(l, { name })])));

// The once-per-floor talk with an ally. Lands well → loyalty and a species buff for the next fight.
export async function allyTalk({ ally, message, vows, trace = null }) {
  const sp = SPECIES[ally.species];
  const lines = reactionLines(sp);
  const state = {
    ally: { ...persona(ally), loyalty: loyaltyWord(ally.loyalty) },
    promises_party_made_to_it: (vows ?? []).map((v) => `"${v.text}" (${v.status})`),
    party_says: message,
  };
  const questions = {
    resonance: score(
      { question: "How do the words in `party_says` land with `ally.name`?", judge_by: ["`ally.values`", "`ally.personality`", "`ally.likes`", "`ally.dislikes`"] },
      ["Hurt or offend it", "Leave it cold", "Fine, nothing special", "Please it", "Move it deeply"],
    ),
    line: lineChoice({ question: "What does `ally.name` say or do in reply to `party_says`?", judge_by: "`ally.personality`" }, lines, ally.name),
  };
  const res = await jev(state, questions, trace);
  const a = res.answers;
  const level = Math.max(0, Math.min(4, Math.round(a.resonance.score)));
  return {
    resonance: a.resonance.score,
    level,
    loyaltyDelta: TALK_DELTA[level],
    buff: level >= 3 ? BUFFS[ally.species] : null,
    outcome: TALK_OUTCOME[level],
    line: reactionLine(a.line, sp, level, ally.name),
    ms: res.ms,
  };
}

// A vow is made to a monster (an enemy mid-fight or an ally). How much does it like the promise?
export async function vowMade({ monster, vow, trace = null }) {
  const sp = SPECIES[monster.species];
  const lines = reactionLines(sp);
  const state = { monster: persona(monster), promise: `The party swears to ${monster.name}: "${vow.text}"` };
  const questions = {
    liking: score(
      { question: "How does `monster.name` feel about the promise in `promise`?", judge_by: ["`monster.values`", "`monster.likes`", "`monster.dislikes`"] },
      ["Hates it", "Dislikes it", "Doesn't care", "Likes it", "Loves it"],
    ),
    line: lineChoice({ question: "How does `monster.name` react to `promise`?", judge_by: "`monster.personality`" }, lines, monster.name),
  };
  const res = await jev(state, questions, trace);
  const level = Math.max(0, Math.min(4, Math.round(res.answers.liking.score)));
  return { liking: res.answers.liking.score, level, line: reactionLine(res.answers.line, sp, level, monster.name), ms: res.ms };
}

const RESPONSES = {
  forgive: "Forgive the party, grudgingly, and stay",
  leave_party: "Leave the party for good",
  attack_party: "Turn on the party and attack them",
  steal_gold: "Steal the party's gold and run off with it",
};

// A vow made to this ally was just broken. Jev picks the response; code applies penalties and the steal odds.
export async function vowBroken({ monster, vow, how, gold, trace = null }) {
  const sp = SPECIES[monster.species];
  const loyalty = Math.max(0, monster.loyalty - BREAK_PENALTY);
  const options = Object.keys(RESPONSES).filter((r) => r !== "steal_gold" || gold > 0);
  const state = {
    monster: { ...persona(monster), loyalty_now: loyaltyWord(loyalty) },
    broken_promise: `The party swore to ${monster.name}: "${vow.text}"`,
    how_it_was_broken: how,
  };
  const questions = {
    response: choice(
      { question: "How does `monster.name` respond to the party breaking `broken_promise`?", consider: ["`how_it_was_broken`", "`monster.values`", "`monster.loyalty_now`", "`monster.personality`"] },
      Object.fromEntries(options.map((r) => [r, RESPONSES[r]])),
    ),
  };
  for (const r of options) {
    questions[`line__${r}`] = lineChoice(
      { question: `\`monster.name\` is about to ${RESPONSES[r].toLowerCase()}. What does it say?`, about: "`how_it_was_broken`" },
      sp.broken[r],
      monster.name,
    );
  }
  const res = await jev(state, questions, trace);
  const a = res.answers;
  const picked = a.response.choice;
  let response = picked;
  let blocked = null;
  // A loyal-enough ally can forgive; a resentful one can't just shrug it off.
  if (response === "forgive" && loyalty < 35) {
    response = "leave_party";
    blocked = `forgiving needs loyalty ≥ 35 after the betrayal (is ${loyalty})`;
  }
  let stolen = 0;
  let caught = false;
  if (response === "steal_gold") {
    if (Math.random() < STEAL_CHANCE) stolen = Math.max(1, Math.round(gold * (0.25 + Math.random() * 0.25)));
    else caught = true;
  }
  return {
    response,
    picked,
    blocked,
    loyalty: response === "forgive" ? loyalty : caught ? Math.max(0, loyalty - 10) : loyalty,
    stolen,
    caught,
    line: pickLine(a[`line__${response}`], sp.broken[response], monster.name),
    probabilities: a.response.probabilities,
    ms: res.ms,
  };
}
