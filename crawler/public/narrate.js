// How monsters' minds reach the player: body language and short narrated reactions in the log, never meters.
// Shared by the browser (game.js prints these) and the server (a fallback line for older clients). Pure, no DOM.
//
// Every sentence is built so it reads right for "it" and "they" (bandits are people): the monster's name is the
// subject of each verb, and clauses after a pronoun use only modal verbs or the past tense ("it won't", "they'd").

// Body language per species. Each tell is a predicate with the monster's name as subject ("Grak <tell>").
export const VOICE = {
  slime: {
    sub: "it", obj: "it", pos: "its", speak: "burbles",
    warm: "jiggles softly, its blank stare gone gentle",
    wary: "quivers a little",
    cold: "goes stiff, its blank stare turning hard",
    scared: "shrinks into a trembling puddle",
    sad: "sags, its glow dimming",
    laugh: "wobbles all over with silent giggles",
    puzzled: "tilts its whole body sideways",
    proud: "puffs up, glistening",
    curious: "leans in, staring blankly",
    yes: "wobbles closer",
    no: "wobbles from side to side",
  },
  goblin: {
    sub: "it", obj: "it", pos: "its", speak: "grunts",
    warm: "grins, showing crooked teeth",
    wary: "eyes you sideways",
    cold: "bares its teeth and grips its club",
    scared: "backs off a step, eyes darting",
    sad: "lets its big ears droop",
    laugh: "slaps its knee and guffaws",
    puzzled: "scratches its head",
    proud: "thumps its chest",
    curious: "squints, ears perked",
    yes: "shoulders its club",
    no: "shakes its big head",
  },
  dragon: {
    sub: "it", obj: "it", pos: "its", speak: "rumbles",
    warm: "lowers its great head, eyes softening",
    wary: "watches you down its long snout",
    cold: "lets smoke curl from its nostrils",
    scared: "draws its wings in close",
    sad: "lets its crest sink",
    laugh: "rumbles with deep laughter",
    puzzled: "cocks its great head",
    proud: "preens its gleaming scales",
    curious: "narrows its eyes thoughtfully",
    yes: "inclines its head",
    no: "turns its head away",
  },
  snake: {
    sub: "it", obj: "it", pos: "its", speak: "hisses",
    warm: "loosens its coils, tongue flicking lazily",
    wary: "sways, watching you without blinking",
    cold: "flares its hood with a sharp hiss",
    scared: "coils tight, tongue flickering fast",
    sad: "lowers its head",
    laugh: "lets out a dry, hissing chuckle",
    puzzled: "tastes the air, baffled",
    proud: "admires its own scales",
    curious: "sways closer",
    yes: "uncoils slowly",
    no: "sways its head from side to side",
  },
  rock: {
    sub: "it", obj: "it", pos: "its", speak: "grinds out",
    warm: "rumbles, low and warm",
    wary: "keeps its distance",
    cold: "grinds its stones together",
    scared: "pulls its limbs in, cracks flickering",
    sad: "settles heavily, its cracks dimming",
    laugh: "shakes loose a little gravel, chuckling",
    puzzled: "goes still, thinking very slowly",
    proud: "stands a little taller",
    curious: "turns its glowing cracks toward you",
    yes: "rises with a long rumble",
    no: "does not move",
  },
  bandit: {
    sub: "they", obj: "them", pos: "their", speak: "says",
    warm: "cracks a crooked smile",
    wary: "keeps a hand near their knife",
    cold: "narrows their eyes, hand on a blade",
    scared: "glances at the exits",
    sad: "looks away",
    laugh: "snorts a laugh",
    puzzled: "frowns, lost",
    proud: "smirks",
    curious: "raises an eyebrow",
    yes: "sheathes their knife",
    no: "shakes their head",
  },
};
const voice = (species) => VOICE[species] ?? VOICE.slime;

// What Jev is offered as the reason behind its answer to "join us?". `when` limits a reason to situations where
// it can be true; code passes the context. The narration clause follows the subject pronoun ("it" / "they").
export const JOIN_NO = {
  not_yet: { what: "It doesn't know or trust the party well enough yet", clause: "'d need to know you better first" },
  wants_more: { what: "It wants something more first: gold, proof, or a better offer", clause: "'ll want more than words first" },
  still_angry: { what: "It is still angry or hurt about what the party did to it", clause: "can't forgive what you did. Not yet" },
  bad_pitch: { what: "It didn't like the way the party asked", clause: "didn't like how you asked" },
  loyal: { what: "It won't abandon the other monsters here with it", clause: "won't leave {others}", when: (x) => x.others?.length > 0 },
  pride: { what: "It is too proud to follow anyone", clause: "'ll follow no one" },
  home: { what: "It won't leave its home on this floor", clause: "won't leave {pos} home on this floor" },
  afraid: { what: "It is afraid of the dangers deeper in the dungeon", clause: "won't go any deeper. Too scared" },
  burned: { what: "It traveled with this party before, and they let it down", clause: "won't be let down by you twice", when: (x) => x.formerAlly },
  // Never offered to Jev: code uses it when the monster was too baffled to follow the question
  confused: { clause: "can't make sense of what you're asking", code: true },
};
export const JOIN_YES = {
  likes_you: { what: "It likes and trusts the party", clause: "can't help liking you" },
  strength: { what: "It respects the party's strength", clause: "'ll follow strength like yours" },
  gold: { what: "It expects a share of gold and loot", clause: "'ll take a share of your gold and loot" },
  company: { what: "It is lonely and wants companions", clause: "won't be alone down here anymore" },
  kin: { what: "Its own kind already travels with the party", clause: "won't be parted from {kin}", when: (x) => x.kin?.length > 0 },
  safety: { what: "It feels safer with the party than against it", clause: "'d rather be on your side than in your way" },
  curious: { what: "It is curious about the adventure ahead", clause: "can't resist seeing where you're going" },
  grateful: { what: "It is grateful for the party's kindness or mercy", clause: "won't forget your kindness" },
};

// The reasons Jev may pick from in this situation, as Jev criteria ({id: description}).
export function reasonOptions(table, ctx = {}) {
  return Object.fromEntries(
    Object.entries(table)
      .filter(([, r]) => !r.code && (!r.when || r.when(ctx)))
      .map(([id, r]) => [id, r.what]),
  );
}

const list = (names) => (names.length <= 1 ? names[0] ?? "" : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`);
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const lc = (s) => s.charAt(0).toLowerCase() + s.slice(1);
// Monster names arrive in caps from the game ("GRAK"); narration reads better as "Grak".
export const nice = (name) => String(name ?? "").toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase());

// "it" + "'ll follow no one" → "it'll follow no one"; "it" + "won't..." → "it won't..."
function clauseWith(sub, clause, ctx, v) {
  const filled = clause
    .replace("{others}", list((ctx.others ?? []).map(nice)) || `${v.pos} own kind`)
    .replace("{kin}", list((ctx.kin ?? []).map(nice)) || `${v.pos} own kind`)
    .replace("{pos}", v.pos);
  return filled.startsWith("'") ? `${sub}${filled}` : `${sub} ${filled}`;
}

// Mood as body language reads it: what a player could see, derived from the meters and this round's feeling.
export function moodOf(meters = {}, emotion = null) {
  const tone = emotion?.tone;
  if (tone === "good") return "warm";
  if (tone === "bad") return "cold";
  if (tone === "fear") return "scared";
  if (tone === "sad") return "sad";
  const f = meters.friendliness ?? 50;
  const a = meters.anger ?? 0;
  if (a >= 45 || f < 25) return "cold";
  if ((meters.fear ?? 0) >= 60) return "scared";
  if (f >= 60 && a < 30) return "warm";
  return "wary";
}

// The visible reaction to a feeling Jev picked (emotions.js). One sentence.
const FEELING_TELL = {
  delighted: ["warm", ""],
  amused: ["laugh", ""],
  touched: ["warm", ". Your words reached {obj}"],
  flattered: ["proud", ""],
  intrigued: ["curious", ""],
  confused: ["puzzled", ""],
  sad: ["sad", ""],
  offended: ["cold", ""],
  enraged: ["cold", ", shaking with rage"],
  terrified: ["scared", ""],
};
export function feelingLine(species, name, emotionId) {
  const t = FEELING_TELL[emotionId];
  if (!t) return null;
  const v = voice(species);
  return `${nice(name)} ${v[t[0]]}${t[1].replace("{obj}", v.obj)}.`;
}

// The answer to "join us?" as one narrated sentence that always agrees with what the monster does.
//   join: { accepted, moved, reason, others, kin }  (from the server)
//   afterFeeling: a feeling line was already printed this round, so lead with a gesture, not a second mood tell
export function joinLine(species, name, join, { meters, emotion, afterFeeling = false } = {}) {
  if (!join?.asked) return null;
  const v = voice(species);
  const N = nice(name);
  const table = join.accepted ? JOIN_YES : JOIN_NO;
  const r = table[join.reason] ?? (join.accepted ? JOIN_YES.likes_you : JOIN_NO.not_yet);
  const said = `${v.speak} that ${clauseWith(v.sub, r.clause, join, v)}`;
  const mood = moodOf(meters, emotion);
  if (join.moved) return `${N} ${v.yes} and asks to come with you. ${cap(clauseWith(v.sub, r.clause, join, v))}.`;
  if (join.accepted) {
    // Joining while it still looks wary: say so, then say why it comes anyway
    if (mood !== "warm") return afterFeeling ? `Even so, ${N} ${v.yes} and ${said}.` : `${N} still ${v.wary}, but ${said}.`;
    return `${N} ${v.yes} and ${said}.`;
  }
  // Refusing while it plainly likes you: show the warmth, then the reason it still says no
  if (mood === "warm") return afterFeeling ? `Still, ${N} ${v.no} and ${said}.` : `${N} ${v.warm}, but ${said}.`;
  return `${N} ${v.no} and ${said}.`;
}

// Which side a monster now takes, told as body language. Only for a change of side (from: the side it left).
export function sideLine(species, name, side, from = null) {
  const v = voice(species);
  const N = nice(name);
  if (side === "friendly with the party") return `${N} ${v.warm}; the fight has gone out of ${v.obj}.`;
  if (side === "hostile to the party") return `${N} ${v.cold}. You've made an enemy.`;
  if (from === "hostile to the party") return `${N} ${v.wary}, less sure ${v.sub}'d like this fight.`;
  return `${N} ${v.wary}, no longer sure of you.`;
}

// Why a monster turned down gold (from the server's tribute refusal reason).
export function tributeLine(species, name, reason) {
  const v = voice(species);
  const N = nice(name);
  if (reason === "too_little") return `${N} looks at the coins and ${v.speak} that it's far too little.`;
  if (reason === "angry") return `${N} ${v.cold}: no amount of gold will fix this.`;
  return `${N} pushes the gold away. ${cap(v.sub)} can't be bought.`;
}

// An event from the fight's history, retold to the player: "The party killed Drip." → "you killed Drip"
export function secondPerson(event) {
  return lc(
    String(event)
      .trim()
      .replace(/\.$/, "")
      .replace(/\bthe party's\b/gi, "your")
      .replace(/\bjoined them\b/g, "joined you")
      .replace(/\bthe party\b/gi, "you"),
  );
}

// An ally after a fight. level: approval 0..4. decision: stay / leave_party / turn_on_party. picked: what Jev wanted.
// moment: the event it reacted to most (from Jev). Returns a sentence, or null when there's nothing to tell.
export function allyLine(species, name, { level, decision, picked, moment }) {
  const v = voice(species);
  const N = nice(name);
  const why = moment ? secondPerson(moment) : null;
  if (decision === "leave_party") return why ? `${N} can't stomach how ${why}.` : `${N} has had enough of you.`;
  if (decision === "turn_on_party") return why ? `${N} ${v.cold}. ${cap(v.sub)} won't forgive how ${why}.` : `${N} ${v.cold}.`;
  // It wanted out, but it isn't there yet: it stays, and the player should feel how close that was
  if (picked && picked !== "stay") return `${N} ${v.cold}, but stays. For now.`;
  if (level <= 1) return why ? `${N} ${v.sad}, still thinking about how ${why}.` : `${N} ${v.sad}.`;
  if (level >= 3) return why ? `${N} ${v.warm}. ${cap(v.sub)} liked how ${why}.` : `${N} ${v.warm}.`;
  return null;
}

// Reaction lines come as [...approve, ...neutral, ...disapprove] and Jev rates them all at once, in parallel with
// the score. Take Jev's favorite among the lines that match the score (3-4 approve, 2 neutral, 0-1 disapprove), so a
// monster that "strongly disapproves" never says its happy line. Returns an index into that combined list.
export function reactionLineIndex(probabilities = {}, reactions, level) {
  const [a, n, d] = [reactions.approve.length, reactions.neutral.length, reactions.disapprove.length];
  const [start, size] = level >= 3 ? [0, a] : level === 2 ? [a, n] : [a + n, d];
  let best = start;
  for (let i = start; i < start + size; i++) if ((probabilities[`line_${i}`] ?? 0) > (probabilities[`line_${best}`] ?? 0)) best = i;
  return best;
}

// How an ally took a talk (level 0..4) or a vow (level 0..4). A tell, or null for a shrug.
export function reactionTell(species, name, level) {
  const v = voice(species);
  if (level <= 0) return `${nice(name)} ${v.cold}.`;
  if (level === 1) return `${nice(name)} ${v.sad}.`;
  if (level >= 4) return `${nice(name)} ${v.warm}, and stands a little closer to you.`;
  if (level === 3) return `${nice(name)} ${v.warm}.`;
  return null;
}

// A vow broken: Jev wanted it to forgive, but the betrayal cut too deep. Explains a leave the player didn't expect.
export function cantForgiveLine(species, name) {
  const v = voice(species);
  return `${nice(name)} ${v.sad}. ${cap(v.sub)}'d like to forgive you, but not after this.`;
}

// Everything the log says about one monster's reply in a group round, in order, before its action plays out.
// r: a /api/group-turn result. ctx: { name, species, sideBefore, debug }.
// Returns [{ text, cls, kind }]; the caller adds color, sounds and the action itself.
export function groupLog(r, { name, species, sideBefore, debug = false } = {}) {
  const out = [];
  const N = String(name).toUpperCase();
  const em = r.emotion;
  const felt = em ? feelingLine(species, name, em.id) : null;
  if (felt) out.push({ text: felt, cls: "", kind: "feeling" });
  if (em) {
    const NAMES = { friendliness: "FRIENDLY", anger: "ANGER", fear: "FEAR" };
    const delta = Object.entries(em.delta ?? {})
      .filter(([, x]) => x)
      .map(([k, x]) => `${NAMES[k]} ${x > 0 ? "+" : ""}${x}`)
      .join(", ");
    out.push({ text: `${N} IS ${em.label}: ${em.effect}.${debug && delta ? ` (${delta})` : ""}`, cls: "big", kind: "emotion" });
  }
  if (r.line && r.spoken !== false) out.push({ text: `${N}: ${r.line}`, cls: "npc", kind: "line" });
  const answer = joinLine(species, name, r.join, { meters: r.meters, emotion: em, afterFeeling: !!felt });
  if (answer) out.push({ text: answer, cls: "", kind: "join" });
  if (r.action === "refuse_tribute" && r.tributeRefusal) out.push({ text: tributeLine(species, name, r.tributeRefusal), cls: "", kind: "tribute" });
  // A change of side the player hasn't already seen in a feeling or an answer, and that its action won't contradict
  const hostileMove = ["attack", "special"].includes(r.action);
  if (sideBefore && r.side && sideBefore !== r.side && !felt && !answer && r.action !== "join_party") {
    if (!(r.side === "friendly with the party" && hostileMove)) out.push({ text: sideLine(species, name, r.side, sideBefore), cls: "", kind: "side" });
  }
  if (debug && r.blocked) out.push({ text: `[DEBUG] JEV PICKED ${String(r.picked).toUpperCase()}; CODE: ${r.blocked}`, cls: "dim", kind: "debug" });
  return out;
}
