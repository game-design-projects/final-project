// A round for a group of 1–3 monsters. Code decides what each one MAY do; Jev reads the situation and picks.
//
// One request per round. For every monster (questions are prefixed with its id) it asks, in parallel:
//   - perception of the party's message from that monster's point of view
//   - its action, over the actions code marks feasible (including turning on another monster)
//   - which party member it would attack, and which other monster it would attack
//   - one speculative line per feasible action, from that species' approved lines
// Code folds perception and damage into each monster's friendliness / anger / fear, gates risky picks
// (a monster can only turn on another when they're on opposite sides or one hit the other), and returns.
//
// When the party talks, gives gold, or asks a monster to join, Jev also picks how that monster FEELS
// (public/emotions.js). Every feeling moves its mood and has a mechanical effect, so words always matter.

import { choice, noul, score } from "./q.js";
import { SPECIES, fill } from "../public/species.js";
import { EMOTIONS, PACIFYING, PITCH } from "../public/emotions.js";
import { jev } from "./jev.js";

// Structured, contrastive options: what each action is, and when it fits. Plain one-liners made Jev
// over-pick "defend" in groups.
const DESCRIBE = {
  attack: { what: "Attack one member of the party", when: "It is hostile or angry at the party, or the party just attacked it" },
  special: (sp) => ({ what: `Use its special attack: ${sp.special.desc}`, when: "It is hostile and wants to hit hard" }),
  attack_monster: {
    what: "Turn on another monster in this fight and attack it",
    when: "That monster is on the other side (friendly with the party while it is hostile, or the reverse), or that monster hurt it",
  },
  defend: { what: "Brace and guard itself instead of acting", when: "It is badly hurt or expects a heavy blow and wants to wait it out" },
  flee: { what: "Run away from the fight", when: "It is scared or badly hurt, or the other monsters have turned against it" },
  converse: { what: "Talk instead of fighting this round", when: "It is curious or undecided and wants to answer or chat rather than act" },
  demand_tribute: { what: "Demand gold from the party in exchange for not fighting", when: "It is greedy and sees a chance to get paid" },
  accept_tribute: { what: "Accept the gold the party is offering", when: "The offer satisfies it" },
  refuse_tribute: { what: "Refuse the gold the party is offering", when: "The offer is too small or it doesn't want their gold" },
  join_party: { what: "Agree to join the party and travel with them", when: "It likes the party enough and they invited it" },
  leave_peacefully: {
    what: "End its part in the encounter peacefully and let the party go on its way",
    when: "It has no quarrel with the party and would rather go",
  },
};
const describe = (a, sp) => (typeof DESCRIBE[a] === "function" ? DESCRIBE[a](sp) : DESCRIBE[a]);
const describeShort = (a, sp) => describe(a, sp).what;

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

// Which side a monster is on, from its meters. Code owns this; Jev sees the words.
const FRIENDLY = 55;
const HOSTILE = 40;
function stance(m) {
  if (m.meters.friendliness >= FRIENDLY && m.meters.anger < 40) return "friendly with the party";
  if (m.meters.friendliness < HOSTILE) return "hostile to the party";
  return "undecided about the party";
}

function joinThreshold(m) {
  return SPECIES[m.species].joinThreshold + (m.formerAlly ? 15 : 0) + (m.boss ? 20 : 0);
}

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

// Damage is a plain fact, so code turns it into anger and fear before Jev sees the mood.
function applyDamage(m) {
  const frac = (m.damageTaken ?? 0) / m.maxHp;
  m.meters.anger += frac * 55;
  m.meters.fear += frac * 30 + (m.hp / m.maxHp < 0.35 ? 10 : 0);
  for (const k of Object.keys(m.meters)) m.meters[k] = clamp(m.meters[k]);
}

// The party asked this monster to join. The Charisma roll (made in the browser) decides how the pitch
// landed; code applies that to its mood before Jev sees it.
function applyPitch(req, m) {
  const pa = req.playerAction;
  if (pa.type !== "recruit" || pa.targetId !== m.id || !PITCH[pa.pitch]) return;
  const p = PITCH[pa.pitch];
  m.meters.friendliness += p.friendliness;
  m.meters.anger += p.anger;
  for (const k of Object.keys(m.meters)) m.meters[k] = clamp(m.meters[k]);
  m.thisRound = [...(m.thisRound ?? []), `The party asked you to join them, with ${p.words}.`];
}

function context(req, m, monsters) {
  const sp = SPECIES[m.species];
  const pa = req.playerAction;
  const message = (pa.type === "talk" || pa.type === "recruit") && pa.message ? pa.message : null;
  const explicitGold = pa.type === "give" && pa.targetId === m.id ? pa.gold : null;
  const recruitMe = pa.type === "recruit" && pa.targetId === m.id;
  return {
    m,
    sp,
    message,
    explicitGold,
    recruitMe,
    // Feelings are asked whenever the party's action was aimed at this monster's heart
    feels: !!message || recruitMe || explicitGold > 0,
    delivery: Math.max(0.5, Math.min(2, Number(pa.delivery) || 1)),
    speechOfferPossible: !!message && req.partyGold > 0,
    room: req.party.length < 6,
    readyToJoin: m.meters.friendliness >= joinThreshold(m) && m.meters.anger < 30,
    living: req.party.filter((p) => !p.dead),
    others: monsters.filter((o) => o.id !== m.id),
  };
}

function feasibleActions(c) {
  const { m } = c;
  const offerPossible = c.explicitGold > 0 || c.speechOfferPossible;
  return {
    attack: c.living.length > 0,
    special: m.specialReady && c.living.length > 0,
    attack_monster: c.others.length > 0,
    defend: true,
    flee: true,
    converse: true,
    demand_tribute: !m.paid,
    accept_tribute: offerPossible,
    refuse_tribute: offerPossible,
    join_party: c.room && (!!c.message || c.recruitMe || c.readyToJoin),
    leave_peacefully: true,
  };
}

function monsterState(req, c) {
  const { m, sp } = c;
  const kin = c.living.filter((p) => p.kind === "monster" && p.species === m.species).map((p) => p.name);
  return {
    name: m.name,
    kind: sp.label,
    nature: sp.nature,
    traits: m.traits,
    likes: sp.likes,
    dislikes: sp.dislikes,
    health: healthWord(m.hp, m.maxHp),
    ...(m.boss ? { rank: "the champion of this floor: proud, powerful, and hard to impress" } : {}),
    mood: {
      friendliness: bucket(m.meters.friendliness, ["hostile", "unfriendly", "wary", "friendly", "very friendly"]),
      anger: bucket(m.meters.anger, ["calm", "annoyed", "angry", "furious"]),
      fear: bucket(m.meters.fear, ["unafraid", "uneasy", "scared", "terrified"]),
    },
    side: stance(m),
    impressions: m.impressions.length ? m.impressions.slice(-6) : ["No strong impressions of this party yet."],
    this_round: m.thisRound?.length ? m.thisRound : ["Nothing happened to it directly."],
    tribute: m.paid ? "the party already paid it tribute" : m.demanded ? "it demanded tribute, not yet paid" : "not discussed",
    kin_in_party: kin.length ? `${kin.join(" and ")}, ${kin.length > 1 ? sp.plural : `a ${sp.label}`} like it, travel${kin.length > 1 ? "" : "s"} with this party` : "none",
    ready_to_join_party: c.readyToJoin
      ? `yes: ${m.name} now likes this party enough to join them if they invite it`
      : m.formerAlly
        ? `not yet: ${m.name} left this party once, and it would take a lot to win it back`
        : `not yet: ${m.name} doesn't like or trust this party enough to join them`,
    promises_party_made_to_it: (req.vows ?? []).filter((v) => v.toId === m.id).map((v) => `"${v.text}" (${v.status})`),
    grudges: (m.grudges ?? []).map((id) => c.others.find((o) => o.id === id)?.name).filter(Boolean),
  };
}

function buildState(req, monsters, ctxs) {
  return {
    monsters: Object.fromEntries(ctxs.map((c) => [c.m.id, monsterState(req, c)])),
    group: monsters.map((m) => `${m.name} (${SPECIES[m.species].label}): ${stance(m)}`),
    party: {
      condition: partyCondition(ctxs[0].living),
      members: ctxs[0].living.map((p) => `${p.name}: ${describeMember(p)}`),
      this_round: req.events.length ? req.events : ["The party did nothing notable."],
      latest_message: ctxs[0].message ?? "(the party said nothing this round)",
      offering:
        req.playerAction.type === "give"
          ? (() => {
              const t = monsters.find((m) => m.id === req.playerAction.targetId);
              return t ? `${req.playerAction.gold} gold to ${t.name}, ${offerWords(req.playerAction.gold, SPECIES[t.species].minTribute, t.name)}` : "nothing";
            })()
          : "nothing",
    },
    recent_conversation: req.conversation.length ? req.conversation.slice(-8).map((l) => `${l.speaker}: ${l.text}`) : ["(no conversation yet)"],
  };
}

function linesFor(action, c) {
  const lines = c.sp.lines[action];
  return action === "converse" && c.message && !c.readyToJoin ? [...lines, ...c.sp.lines.not_ready] : lines;
}

// Adds this monster's questions (ids prefixed with its id) to the shared request; returns its feasible actions.
function buildQuestions(c, feasible, q) {
  const { m } = c;
  const name = m.name;
  const k = (id) => `${m.id}__${id}`;
  const me = `\`monsters.${m.id}\``;
  if (c.message) {
    q[k("threat")] = noul(`Does \`party.latest_message\` threaten to hurt or kill ${name}?`, {
      true: "An explicit or implied threat of violence toward it",
      false: "No threat of violence toward it (rudeness alone does not count)",
    });
    q[k("insult")] = noul(`Does \`party.latest_message\` insult, mock, or belittle ${name}?`);
    q[k("kindness")] = score(`How kind, friendly, or flattering is \`party.latest_message\` toward ${name}?`, [
      "Hostile or contemptuous toward it",
      "Cold, businesslike, or not about it",
      "Polite and friendly toward it",
      "Warm, kind, or openly complimentary toward it",
    ]);
    q[k("joke")] = noul("Does `party.latest_message` contain a joke, pun, or deliberately silly remark?");
    q[k("asks_to_join")] = noul(`In \`party.latest_message\`, does the party invite ${name} to join them or travel with them?`);
    q[k("asks_for_peace")] = noul(`In \`party.latest_message\`, does the party ask ${name} to stop fighting, make peace, or let them pass?`);
    if (c.speechOfferPossible) q[k("offers_gold")] = noul(`In \`party.latest_message\`, is the party offering gold or money to ${name} right now?`);
  }
  // Joining is its own narrow judgment: asked only when code says the monster likes the party enough.
  if (feasible.join_party && c.readyToJoin && (c.message || c.recruitMe))
    q[k("would_join")] = noul({
      question: `If the party is inviting ${name} to join them, does ${name} want to say yes?`,
      consider: [`\`monsters.${m.id}.ready_to_join_party\``, `${me}`, "`party.latest_message`", "`party.this_round`"],
    });
  if (c.feels)
    q[k("emotion")] = choice(
      {
        question: `How does ${name} feel about what the party just said or did to it this round?`,
        consider: [`What happened in \`party.this_round\` and \`monsters.${m.id}.this_round\``, "`party.latest_message`", `Its nature, likes, dislikes and mood in ${me}`],
      },
      Object.fromEntries(Object.entries(EMOTIONS).map(([id, e]) => [id, { what: e.what, when: e.when }])),
    );

  const options = Object.keys(feasible).filter((a) => feasible[a]);
  q[k("action")] = choice(
    {
      question: `What does ${name} do this round?`,
      consider: [
        `Its nature, traits, likes, dislikes, mood and impressions in ${me}`,
        `What happened to it this round in \`monsters.${m.id}.this_round\``,
        "Which side the other monsters are on in `group`",
        "What the party did and said in `party`",
      ],
    },
    Object.fromEntries(options.map((a) => [a, describe(a, c.sp)])),
  );

  if ((feasible.attack || (feasible.special && !c.sp.special.all)) && c.living.length > 1) {
    q[k("target")] = choice(
      { question: `If ${name} attacks the party, which member does it go after?`, consider: ["`party.members`", me] },
      Object.fromEntries(c.living.map((p) => [p.id, `${p.name}: ${describeMember(p)}`])),
    );
  }
  if (feasible.attack_monster && c.others.length > 1) {
    q[k("monster_target")] = choice(
      { question: `If ${name} turns on another monster, which one?`, consider: ["`group`", me] },
      Object.fromEntries(c.others.map((o) => [o.id, `${o.name}, ${SPECIES[o.species].label}: ${stance(o)}`])),
    );
  }

  for (const a of options) {
    const lines = linesFor(a, c);
    if (lines.length < 2) continue;
    q[k(`line__${a}`)] = choice(
      {
        question: `${name} is about to do what \`planned_action\` describes. Which line fits best right now?`,
        planned_action: describeShort(a, c.sp),
        respond_to: ["`party.latest_message`", `\`monsters.${m.id}.this_round\``],
      },
      Object.fromEntries(lines.map((l, i) => [`line_${i}`, fill(l, { name, target: "the target" })])),
    );
  }
  return options;
}

function applyPerception(c, a, meters, impressions) {
  if (!c.message) return;
  const w = c.sp.weights;
  const n = (id) => a[`${c.m.id}__${id}`]?.noul ?? 0;
  const note = (t) => {
    if (!impressions.includes(t)) impressions.push(t);
  };
  const kind = a[`${c.m.id}__kindness`].score / 3;
  const x = c.delivery; // how well the words were delivered (the Charisma roll) scales how hard they land
  meters.friendliness += x * (w.kindness * (kind - 0.35) + w.joke * n("joke") + w.peace * n("asks_for_peace") - w.insult * n("insult") - 10 * n("threat"));
  meters.anger += x * (w.insult * n("insult") + w.threatAnger * n("threat") - 8 * kind - 5 * n("asks_for_peace"));
  meters.fear += x * w.threatFear * n("threat");
  if (n("threat") >= 0.7) note("The party threatened you.");
  if (n("insult") >= 0.7) note("The party insulted you.");
  if (n("joke") >= 0.7) note("The party told you a joke.");
  if (a[`${c.m.id}__kindness`].score >= 2.5) note("The party spoke kindly to you.");
  if (n("asks_for_peace") >= 0.7) note("The party asked you for peace.");
}

// The feeling Jev picked moves the mood (scaled by delivery when the party was talking). Code owns the numbers.
function applyEmotion(c, emotionId, meters, impressions) {
  const e = EMOTIONS[emotionId];
  if (!e) return null;
  const x = c.message ? c.delivery : 1;
  const delta = {};
  for (const [k, v] of Object.entries(e.meters)) {
    const before = meters[k];
    meters[k] = clamp(meters[k] + v * x);
    delta[k] = meters[k] - before;
  }
  const t = `The party left you feeling ${e.label.toLowerCase()}.`;
  if (!impressions.includes(t)) impressions.push(t);
  return { id: emotionId, label: e.label, cond: e.cond ?? null, rounds: e.rounds ?? 0, effect: e.effect, tone: e.tone, delta };
}

function policy(action, conf, req, c, a, meters, offer, target, emotion) {
  const { m } = c;
  const asks = c.recruitMe ? 1 : (a[`${m.id}__asks_to_join`]?.noul ?? 0);
  if (emotion?.cond && PACIFYING.has(emotion.cond) && ["attack", "special", "attack_monster"].includes(action))
    return { why: `it is ${emotion.label.toLowerCase()}: ${emotion.effect.toLowerCase()}`, fallback: "converse" };
  switch (action) {
    case "join_party":
      if (meters.friendliness < joinThreshold(m))
        return { why: `friendliness ${meters.friendliness} < ${joinThreshold(m)} needed to join`, fallback: "converse" };
      if (meters.anger >= 30) return { why: `anger ${meters.anger} ≥ 30`, fallback: "converse" };
      // Invited, or so moved that it asks to come along on its own
      if (asks < 0.6 && !["touched", "delighted"].includes(emotion?.id)) return { why: "the party never actually invited it", fallback: "converse" };
      return null;
    case "accept_tribute":
      if (!offer) return { why: "no gold is actually being offered to it", fallback: "converse" };
      if (offer < c.sp.minTribute && !m.paid) return { why: `${offer} gold is below its minimum of ${c.sp.minTribute}`, fallback: "refuse_tribute" };
      return null;
    case "refuse_tribute":
      return offer ? null : { why: "no gold is actually being offered to it", fallback: "converse" };
    case "leave_peacefully":
      if (meters.anger >= 45) return { why: `anger ${meters.anger} ≥ 45; it won't just walk away`, fallback: "defend" };
      return null;
    case "attack_monster": {
      // Only turn on another monster when they're on opposite sides, or that monster hit it.
      const opposite =
        (meters.friendliness < HOSTILE && target.meters.friendliness >= FRIENDLY) ||
        (meters.friendliness >= FRIENDLY && target.meters.friendliness < HOSTILE);
      const grudge = (m.grudges ?? []).includes(target.id);
      if (opposite || grudge) return null;
      return {
        why: `${target.name} isn't on the other side and hasn't hit it`,
        fallback: meters.friendliness < HOSTILE ? "attack" : "converse",
      };
    }
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

// Jev's probabilities are calibrated, so monsters roll on them: any action at ≥15% can happen, in proportion
// to its odds. This is what lets a 20% "turn on the traitor" actually occur sometimes.
const ROLL_FLOOR = 0.15;
function roll(probabilities) {
  const live = Object.entries(probabilities).filter(([, p]) => p >= ROLL_FLOOR);
  if (!live.length) return Object.entries(probabilities).sort((x, y) => y[1] - x[1])[0][0];
  let r = Math.random() * live.reduce((t, [, p]) => t + p, 0);
  for (const [act, p] of live) if ((r -= p) <= 0) return act;
  return live[live.length - 1][0];
}

export async function groupTurn(req) {
  const monsters = req.monsters.map((m) => ({ ...m, meters: { ...m.meters }, impressions: [...(m.impressions ?? [])] }));
  monsters.forEach(applyDamage);
  monsters.forEach((m) => applyPitch(req, m));
  const ctxs = monsters.map((m) => context(req, m, monsters));
  const feasible = ctxs.map(feasibleActions);
  const state = buildState(req, monsters, ctxs);
  const questions = {};
  const options = ctxs.map((c, i) => buildQuestions(c, feasible[i], questions));
  const res = await jev(state, questions);
  const a = res.answers;

  const results = ctxs.map((c, i) => {
    const { m } = c;
    const id = (x) => `${m.id}__${x}`;
    const meters = { ...m.meters };
    const impressions = [...m.impressions];
    const before = { ...meters };
    applyPerception(c, a, meters, impressions);
    for (const k of Object.keys(meters)) meters[k] = clamp(meters[k]);
    const emotion = applyEmotion(c, a[id("emotion")]?.choice, meters, impressions);

    let offer = c.explicitGold || 0;
    if (!offer && (a[id("offers_gold")]?.noul ?? 0) >= 0.6) offer = Math.min(req.partyGold, Math.max(c.sp.minTribute, 1));

    const monsterTarget = c.others.find((o) => o.id === a[id("monster_target")]?.choice) ?? c.others[0];
    let picked = roll(a[id("action")].probabilities);
    // A clear invitation to a monster that's ready and wants to come overrides small talk. So does a monster
    // that was so touched or delighted that it now likes the party enough to come along.
    const invited = c.recruitMe || (a[id("asks_to_join")]?.noul ?? 0) >= 0.6;
    const accepts = invited && (a[id("would_join")]?.noul ?? 0) >= 0.55;
    const ready = meters.friendliness >= joinThreshold(m) && meters.anger < 30 && c.room;
    const moved = ready && ["touched", "delighted"].includes(emotion?.id);
    if ((accepts || moved) && ["converse", "defend", "leave_peacefully", "demand_tribute"].includes(picked)) picked = "join_party";
    const block = policy(picked, a[id("action")].confidence, req, c, a, meters, offer, monsterTarget, emotion);
    let final = picked;
    if (block) final = options[i].includes(block.fallback) ? block.fallback : "converse";

    if (final === "accept_tribute") {
      meters.friendliness = clamp(meters.friendliness + c.sp.weights.gold);
      meters.anger = clamp(meters.anger - 25);
      impressions.push(`The party paid you ${offer} gold.`);
    }

    const target = c.living.find((p) => p.id === a[id("target")]?.choice) ?? c.living[0] ?? null;
    const named = final === "attack_monster" ? monsterTarget?.name : target?.name;
    const lines = linesFor(final, c);
    const probs = a[id(`line__${final}`)]?.probabilities ?? {};
    const ranked = lines.map((_, j) => j).sort((x, y) => (probs[`line_${y}`] ?? 0) - (probs[`line_${x}`] ?? 0));
    const recent = req.conversation.slice(-3).map((l) => l.text);
    const fillLine = (j) => fill(lines[j], { name: m.name, target: named ?? "someone" });
    const pick = ranked.find((j) => !recent.includes(fillLine(j))) ?? ranked[0];

    return {
      id: m.id,
      action: final,
      picked,
      blocked: block?.why ?? null,
      confidence: a[id("action")].confidence,
      probabilities: Object.entries(a[id("action")].probabilities)
        .map(([act, p]) => ({ id: act, p }))
        .sort((x, y) => y.p - x.p),
      targetId: target?.id ?? null,
      monsterTargetId: final === "attack_monster" ? monsterTarget?.id : null,
      line: fillLine(pick),
      offer: final === "accept_tribute" ? offer : 0,
      meters,
      moodDelta: Object.fromEntries(Object.keys(meters).map((k) => [k, meters[k] - before[k]])),
      emotion,
      emotionProbabilities: a[id("emotion")]
        ? Object.entries(a[id("emotion")].probabilities)
            .map(([e, p]) => ({ id: e, p }))
            .sort((x, y) => y.p - x.p)
            .slice(0, 3)
        : null,
      side: stance({ meters }),
      impressions: impressions.slice(-8),
      perception: Object.keys(LABELS)
        .filter((p) => a[id(p)])
        .map((p) =>
          a[id(p)].type === "noul"
            ? { id: p, label: LABELS[p], type: "noul", value: a[id(p)].noul }
            : { id: p, label: LABELS[p], type: "score", value: a[id(p)].score, max: 3 },
        ),
    };
  });

  return { results, ms: res.ms, inputTokens: res.usage.input_tokens, questionCount: Object.keys(questions).length, model: res.model };
}

// Kept for builds that still call the single-monster endpoint (e.g. an already-uploaded itch.io zip).
export async function enemyTurn(req) {
  const m = { ...req.enemy, id: "e0", grudges: [], thisRound: [] };
  const out = await groupTurn({ ...req, monsters: [m], vows: [] });
  const r = out.results[0];
  return { ...r, targetProbabilities: null, ms: out.ms, inputTokens: out.inputTokens, questionCount: out.questionCount, model: out.model };
}
