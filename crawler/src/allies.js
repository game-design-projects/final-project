// Recruited monsters judge the party after each encounter. One Jev request covers every ally:
//   - approval Score per ally (how it feels about the events, by its own values)
//   - a reaction line Choice per ally
//   - for allies whose loyalty is already shaky, a speculative Choice: stay, leave, or turn on the party
// Code turns approval into loyalty and decides whether leaving or betrayal is allowed.

import { choice, score } from "./q.js";
import { SPECIES, fill } from "../public/species.js";
import { jev } from "./jev.js";

const LOYALTY_DELTA = [-18, -9, 0, 7, 12]; // by approval level 0..4
const SHAKY = 45; // ask the stay/leave/betray question below this (before the change)
const LEAVE_BELOW = 30;
const BETRAY_BELOW = 15;

const loyaltyWord = (v) => (v >= 75 ? "devoted" : v >= 50 ? "content" : v >= 30 ? "uneasy" : v >= 15 ? "resentful" : "on the verge of leaving");

export async function allyReactions({ allies, events }) {
  const state = {
    events,
    allies: Object.fromEntries(
      allies.map((al) => {
        const sp = SPECIES[al.species];
        return [
          al.id,
          {
            name: al.name,
            kind: sp.label,
            personality: [sp.nature, ...al.traits],
            values: sp.values,
            loyalty: loyaltyWord(al.loyalty),
          },
        ];
      }),
    ),
  };

  const questions = {};
  for (const al of allies) {
    const sp = SPECIES[al.species];
    questions[`approval__${al.id}`] = score(
      {
        question: `How does \`allies.${al.id}.name\` feel about what the party did in \`events\`?`,
        judge_by: [`\`allies.${al.id}.values\``, `\`allies.${al.id}.personality\``],
      },
      ["Strongly disapproves", "Disapproves", "Doesn't care", "Approves", "Strongly approves"],
    );
    const lines = [...sp.reactions.approve, ...sp.reactions.neutral, ...sp.reactions.disapprove];
    questions[`line__${al.id}`] = choice(
      {
        question: `What does \`allies.${al.id}.name\` say or do in reaction to \`events\`?`,
        judge_by: [`\`allies.${al.id}.values\``, `\`allies.${al.id}.personality\``],
      },
      Object.fromEntries(lines.map((l, i) => [`line_${i}`, fill(l, { name: al.name })])),
    );
    if (al.loyalty < SHAKY) {
      questions[`decision__${al.id}`] = choice(
        {
          question: `After \`events\`, what does \`allies.${al.id}.name\` do?`,
          consider: [`\`allies.${al.id}.values\``, `\`allies.${al.id}.loyalty\``, `\`allies.${al.id}.personality\``],
        },
        {
          stay: "Stays with the party, perhaps grumbling",
          leave_party: "Leaves the party and goes its own way",
          turn_on_party: "Turns on the party and attacks them",
        },
      );
    }
  }

  const res = await jev(state, questions);
  const a = res.answers;

  const reactions = allies.map((al) => {
    const sp = SPECIES[al.species];
    const approval = a[`approval__${al.id}`];
    const level = Math.round(approval.score);
    const delta = LOYALTY_DELTA[level];
    const loyalty = Math.max(0, Math.min(100, al.loyalty + delta));

    const picked = a[`decision__${al.id}`]?.choice ?? "stay";
    let decision = "stay";
    let blocked = null;
    if (picked === "turn_on_party") {
      if (loyalty < BETRAY_BELOW) decision = "turn_on_party";
      else if (loyalty < LEAVE_BELOW) {
        decision = "leave_party";
        blocked = `betrayal needs loyalty < ${BETRAY_BELOW} (is ${loyalty}); leaving instead`;
      } else blocked = `betrayal needs loyalty < ${BETRAY_BELOW} (is ${loyalty}); stays`;
    } else if (picked === "leave_party") {
      if (loyalty < LEAVE_BELOW) decision = "leave_party";
      else blocked = `leaving needs loyalty < ${LEAVE_BELOW} (is ${loyalty}); stays`;
    }

    let line;
    if (decision === "stay") {
      const lines = [...sp.reactions.approve, ...sp.reactions.neutral, ...sp.reactions.disapprove];
      line = lines[Number(a[`line__${al.id}`].choice.split("_")[1])];
    } else {
      const bank = decision === "leave_party" ? sp.reactions.leave : sp.reactions.betray;
      line = bank[Math.floor(Math.random() * bank.length)];
    }
    return {
      id: al.id,
      name: al.name,
      approval: approval.score,
      delta,
      loyalty,
      picked,
      decision,
      blocked,
      line: fill(line, { name: al.name }),
    };
  });

  return {
    reactions,
    ms: res.ms,
    inputTokens: res.usage.input_tokens,
    questionCount: Object.keys(questions).length,
    model: res.model,
    request: { state, questions },
    answers: a,
  };
}
