// An enemy's turn. Code decides what it MAY do; Jev reads the situation (including what the party said) and picks.
//
// One request per round asks, in parallel:
//   - perception of the party's message: threat, insult, kindness, joke, offers gold, asks to join, asks for peace
//   - the action Choice over feasible actions, and a target Choice over living party members
//   - one speculative line Choice per feasible action, so whatever action survives policy already has a line
// Code folds perception into friendliness / anger / fear, gates risky picks, and returns the decision.

import { choice, noul, score } from "./q.js";
import { SPECIES, fill } from "../public/species.js";
import { jev } from "./jev.js";

const DESCRIBE = {
  attack: "Attack one member of the party",
  special: (sp) => `Use its special attack: ${sp.special.desc}`,
  defend: "Hold back and guard itself this round",
  flee: "Run away from the fight",
  converse: "Talk to the party instead of fighting this round",
  demand_tribute: "Demand gold from the party in exchange for not fighting",
  accept_tribute: "Accept the gold the party is offering",
  refuse_tribute: "Refuse the gold the party is offering",
  join_party: "Agree to join the party and travel with them",
  leave_peacefully: "End the encounter peacefully and let the party go on its way",
};

const LABELS = {
  threat: "Threatens it",
  insult: "Insults it",
  kindness: "Kindness (0–3)",
  joke: "Tells a joke",
  offers_gold: "Offers gold",
  asks_to_join: "Asks it to join",
  asks_for_peace: "Asks for peace",
};

const clamp = (v) => Math.round(Math.max(0, Math.min(100, v)));
const bucket = (v, words) => words[Math.min(words.length - 1, Math.floor(v / (100 / words.length)))];
const healthWord = (hp, max) => (hp / max > 0.7 ? "healthy" : hp / max > 0.35 ? "wounded" : "badly wounded");

function context(req) {
  const sp = SPECIES[req.enemy.species];
  const message = req.playerAction.type === "talk" ? req.playerAction.message : null;
  const explicitGold = req.playerAction.type === "give" ? req.playerAction.gold : null;
  return {
    sp,
    message,
    explicitGold,
    speechOfferPossible: !!message && req.partyGold > 0,
    room: req.party.length < 6,
    // Code knows whether the monster likes the party enough to join; Jev is told, then still decides.
    readyToJoin: req.enemy.meters.friendliness >= SPECIES[req.enemy.species].joinThreshold && req.enemy.meters.anger < 30,
    living: req.party.filter((m) => !m.dead),
  };
}

function feasibleActions(req, c) {
  const e = req.enemy;
  const offerPossible = c.explicitGold > 0 || c.speechOfferPossible;
  return {
    attack: c.living.length > 0,
    special: e.specialReady && c.living.length > 0,
    defend: true,
    flee: true,
    converse: true,
    demand_tribute: !e.paid,
    accept_tribute: offerPossible,
    refuse_tribute: offerPossible,
    join_party: !!c.message && c.room && !e.formerAlly,
    leave_peacefully: true,
  };
}

function buildState(req, c) {
  const e = req.enemy;
  const m = e.meters;
  const kin = c.living.filter((p) => p.kind === "monster" && p.species === e.species).map((p) => p.name);
  return {
    monster: {
      name: e.name,
      kind: c.sp.label,
      nature: c.sp.nature,
      traits: e.traits,
      likes: c.sp.likes,
      dislikes: c.sp.dislikes,
      health: healthWord(e.hp, e.maxHp),
      mood: {
        friendliness: bucket(m.friendliness, ["hostile", "unfriendly", "wary", "friendly", "very friendly"]),
        anger: bucket(m.anger, ["calm", "annoyed", "angry", "furious"]),
        fear: bucket(m.fear, ["unafraid", "uneasy", "scared", "terrified"]),
      },
      impressions: e.impressions.length ? e.impressions.slice(-6) : ["No strong impressions of this party yet."],
    },
    situation: {
      round: req.round,
      party_condition: partyCondition(c.living),
      tribute: e.paid ? "the party already paid tribute" : e.demanded ? "demanded, not yet paid" : "not discussed",
      kin_in_party: kin.length ? `${kin.join(" and ")}, ${c.sp.label}${kin.length > 1 ? "s" : ""} like you, travel with this party` : "none",
      was_once_their_ally: e.formerAlly ? "yes; you left this party because of how they acted" : "no",
      ready_to_join_them: e.formerAlly
        ? "never again"
        : c.readyToJoin
          ? `yes: ${e.name} now likes this party enough to join them if they invite it`
          : `not yet: ${e.name} doesn't like or trust this party enough to join them`,
    },
    party: {
      members: c.living.map((p) => `${p.name}: ${describeMember(p)}`),
      this_round: req.events.length ? req.events : ["The party did nothing notable."],
      latest_message: c.message ?? "(the party said nothing this round)",
      offering: c.explicitGold ? `${c.explicitGold} gold, ${offerWords(c.explicitGold, c.sp.minTribute, req.enemy.name)}` : "nothing",
    },
    recent_conversation: req.conversation.length
      ? req.conversation.slice(-8).map((l) => `${l.speaker}: ${l.text}`)
      : ["(no conversation yet)"],
  };
}

// Jev compares words better than numbers, so code says how an amount compares to what this monster expects.
function offerWords(gold, expected, name) {
  const r = gold / expected;
  if (r < 0.5) return `far less than ${name} expects as tribute`;
  if (r < 0.9) return `a bit less than ${name} expects as tribute`;
  if (r < 1.3) return `about the tribute ${name} expects`;
  return `more than the tribute ${name} expects: a generous offer`;
}

function partyCondition(living) {
  const hp = living.reduce((s, p) => s + p.hp, 0);
  const max = living.reduce((s, p) => s + p.maxHp, 0) || 1;
  const size = living.length >= 4 ? "a large group" : living.length >= 2 ? "a small group" : "a lone adventurer";
  return `${size}, ${hp / max > 0.7 ? "fresh" : hp / max > 0.35 ? "battered" : "nearly dead"}`;
}

function describeMember(p) {
  const who = p.kind === "monster" ? `a ${SPECIES[p.species].label} ally` : `a human ${p.cls === "N-MAG" ? "mage" : "fighter"}`;
  return `${who}, ${healthWord(p.hp, p.maxHp)}${p.didThisRound ? `; this round: ${p.didThisRound}` : ""}`;
}

function buildQuestions(req, c, feasible) {
  const q = {};
  const name = req.enemy.name;
  if (c.message) {
    q.threat = noul(`Does \`party.latest_message\` threaten to hurt or kill ${name}?`, {
      true: "An explicit or implied threat of violence",
      false: "No threat of violence (rudeness alone does not count)",
    });
    q.insult = noul(`Does \`party.latest_message\` insult, mock, or belittle ${name}?`);
    q.kindness = score(`How kind, friendly, or flattering is \`party.latest_message\` toward ${name}?`, [
      "Hostile or contemptuous",
      "Cold or purely businesslike",
      "Polite and friendly",
      "Warm, kind, or openly complimentary",
    ]);
    q.joke = noul("Does `party.latest_message` contain a joke, pun, or deliberately silly remark?");
    q.asks_to_join = noul(`In \`party.latest_message\`, does the party invite ${name} to join them or travel with them?`);
    q.asks_for_peace = noul(
      `In \`party.latest_message\`, does the party ask to stop fighting, make peace, or pass by without a fight?`,
    );
    if (c.speechOfferPossible)
      q.offers_gold = noul(`In \`party.latest_message\`, is the party offering gold or money to ${name} right now?`);
  }

  const options = Object.keys(feasible).filter((a) => feasible[a]);
  q.action = choice(
    {
      question: `What does ${name} do this round?`,
      consider: [
        "Its nature, traits, likes and dislikes in `monster`",
        "Its mood and impressions in `monster.mood` and `monster.impressions`",
        "What the party did and said in `party`",
        "The circumstances in `situation`",
      ],
    },
    Object.fromEntries(options.map((a) => [a, typeof DESCRIBE[a] === "function" ? DESCRIBE[a](c.sp) : DESCRIBE[a]])),
  );

  if ((feasible.attack || (feasible.special && !c.sp.special.all)) && c.living.length > 1) {
    q.target = choice(
      { question: `If ${name} attacks, which party member does it go after?`, consider: "`party.members` and `monster`" },
      Object.fromEntries(c.living.map((p) => [p.id, `${p.name}: ${describeMember(p)}`])),
    );
  }

  for (const a of options) {
    const lines = linesFor(a, c);
    if (lines.length < 2) continue;
    q[`line__${a}`] = choice(
      {
        question: `${name} is about to do what \`planned_action\` describes. Which line fits best right now?`,
        planned_action: typeof DESCRIBE[a] === "function" ? DESCRIBE[a](c.sp) : DESCRIBE[a],
        respond_to: ["`party.latest_message`", "`party.this_round`"],
      },
      Object.fromEntries(lines.map((l, i) => [`line_${i}`, fill(l, { name, target: "the target" })])),
    );
  }
  return { questions: q, options };
}

// Composite scoring with per-species weights: independent judgments become meter changes in code.
function applyPerception(req, c, a, meters, impressions) {
  const w = c.sp.weights;
  const n = (id) => a[id]?.noul ?? 0;
  const note = (t) => {
    if (!impressions.includes(t)) impressions.push(t);
  };
  if (!c.message) return;
  const kind = a.kindness.score / 3;
  meters.friendliness +=
    w.kindness * (kind - 0.35) + w.joke * n("joke") + w.peace * n("asks_for_peace") - w.insult * n("insult") - 10 * n("threat");
  meters.anger += w.insult * n("insult") + w.threatAnger * n("threat") - 8 * kind - 5 * n("asks_for_peace");
  meters.fear += w.threatFear * n("threat");
  if (n("threat") >= 0.7) note("The party threatened you.");
  if (n("insult") >= 0.7) note("The party insulted you.");
  if (n("joke") >= 0.7) note("The party told you a joke.");
  if (a.kindness.score >= 2.5) note("The party spoke kindly to you.");
  if (n("asks_for_peace") >= 0.7) note("The party asked for peace.");
}

function policy(action, conf, req, c, a, meters, offer) {
  const e = req.enemy;
  switch (action) {
    case "join_party":
      if (meters.friendliness < c.sp.joinThreshold)
        return { why: `friendliness ${meters.friendliness} < ${c.sp.joinThreshold} needed to join`, fallback: "converse" };
      if (meters.anger >= 30) return { why: `anger ${meters.anger} ≥ 30`, fallback: "converse" };
      if ((a.asks_to_join?.noul ?? 0) < 0.6) return { why: "the party never actually invited it", fallback: "converse" };
      return null;
    case "accept_tribute":
      if (!offer) return { why: "no gold is actually being offered", fallback: "converse" };
      if (offer < c.sp.minTribute && !e.paid)
        return { why: `${offer} gold is below its minimum of ${c.sp.minTribute}`, fallback: "refuse_tribute" };
      return null;
    case "refuse_tribute":
      return offer ? null : { why: "no gold is actually being offered", fallback: "converse" };
    case "leave_peacefully":
      if (meters.anger >= 45) return { why: `anger ${meters.anger} ≥ 45; it won't just walk away`, fallback: "defend" };
      return null;
    case "attack":
    case "special":
      if (meters.friendliness >= 75 && meters.anger < 15 && !req.events.some((ev) => /attack|hit|cast/i.test(ev)))
        return { why: `friendliness ${meters.friendliness} with no provocation`, fallback: "converse" };
      if (conf < 0.25) return { why: `confidence ${conf.toFixed(2)} < 0.25 for an attack`, fallback: "defend" };
      return null;
    default:
      return null;
  }
}

export async function enemyTurn(req) {
  const c = context(req);
  const e = req.enemy;
  const feasible = feasibleActions(req, c);
  const state = buildState(req, c);
  const { questions, options } = buildQuestions(req, c, feasible);
  const res = await jev(state, questions);
  const a = res.answers;

  const meters = { ...e.meters };
  const impressions = [...e.impressions];
  applyPerception(req, c, a, meters, impressions);

  // What's actually on offer: an explicit give, or a spoken offer (Jev noticed it) of what the party can spare.
  let offer = c.explicitGold || 0;
  if (!offer && (a.offers_gold?.noul ?? 0) >= 0.6) offer = Math.min(req.partyGold, Math.max(c.sp.minTribute, 1));

  for (const k of Object.keys(meters)) meters[k] = clamp(meters[k]);

  const picked = a.action.choice;
  const block = policy(picked, a.action.confidence, req, c, a, meters, offer);
  let final = picked;
  if (block) final = options.includes(block.fallback) ? block.fallback : "converse";

  if (final === "accept_tribute") {
    meters.friendliness = clamp(meters.friendliness + c.sp.weights.gold);
    meters.anger = clamp(meters.anger - 25);
    impressions.push(`The party paid you ${offer} gold.`);
  }

  const target = pickTarget(a, c);
  const lineProbs = a[`line__${final}`]?.probabilities ?? {};
  const lines = linesFor(final, c);
  let best = 0;
  lines.forEach((_, i) => {
    if ((lineProbs[`line_${i}`] ?? 0) > (lineProbs[`line_${best}`] ?? 0)) best = i;
  });
  const recent = req.conversation.slice(-2).map((l) => l.text);
  let text = fill(lines[best], { name: e.name, target: target?.name ?? "someone" });
  if (recent.includes(text) && lines.length > 1) {
    const alt = lines.map((_, i) => i).filter((i) => i !== best).sort((x, y) => (lineProbs[`line_${y}`] ?? 0) - (lineProbs[`line_${x}`] ?? 0))[0];
    text = fill(lines[alt], { name: e.name, target: target?.name ?? "someone" });
  }

  return {
    action: final,
    picked,
    blocked: block?.why ?? null,
    confidence: a.action.confidence,
    probabilities: Object.entries(a.action.probabilities)
      .map(([id, p]) => ({ id, p }))
      .sort((x, y) => y.p - x.p),
    targetId: target?.id ?? null,
    line: text,
    offer: final === "accept_tribute" ? offer : 0,
    meters,
    impressions: impressions.slice(-8),
    perception: Object.keys(LABELS)
      .filter((id) => a[id])
      .map((id) =>
        a[id].type === "noul"
          ? { id, label: LABELS[id], type: "noul", value: a[id].noul }
          : { id, label: LABELS[id], type: "score", value: a[id].score, max: 3 },
      ),
    targetProbabilities: a.target?.probabilities ?? null,
    ms: res.ms,
    inputTokens: res.usage.input_tokens,
    questionCount: Object.keys(questions).length,
    model: res.model,
    request: { state, questions },
    answers: a,
  };
}

function linesFor(action, c) {
  const lines = c.sp.lines[action];
  return action === "converse" && c.message && !c.readyToJoin ? [...lines, ...c.sp.lines.not_ready] : lines;
}

function pickTarget(a, c) {
  if (!c.living.length) return null;
  if (!a.target) return c.living[0];
  return c.living.find((p) => p.id === a.target.choice) ?? c.living[0];
}
