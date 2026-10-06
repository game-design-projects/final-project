// What a monster sounds like when it speaks: a pure line -> sound-plan classifier, no audio and no DOM.
// sfx.js turns a plan into synthesised noise; the keyword table lives here so it can be tested without a browser.
//
// Lines are mostly the approved ones in species.js ("RAAH! *swings a knotted club at {target}*", "*hisses softly*",
// "...bloop?"), but a line can be any free text, so every rule is a loose regex and every path ends in a fallback.

// kind -> what the synth plays
export const KINDS = ["roar", "bark", "grunt", "growl", "hiss", "squelch", "laugh", "squeal", "whimper", "sigh", "rumble", "zap", "babble"];

// Onomatopoeia and emote verbs. The earliest match in the line decides.
// A kind named here is mapped through the species' `remap` before it is played (a slime's "grunt" is a squelch).
export const KEYWORDS = [
  ["roar", /\b(?:r+a+h+|ra+g+h+|r+o+a+r+\w*|a+r+g+h+|gra+h+|wa+gh+|bellow\w*|bawl\w*)\b/i],
  ["growl", /\b(?:g+r{2,}\w*|growl\w*|snarl\w*|rasp\w*)\b/i],
  ["grunt", /\b(?:grunt\w*|hm+ph|hrm+ph?|ugh+|oof|pah+|bah+|huh+|snort\w*|hm+|eh)\b/i],
  ["hiss", /\bhiss\w*|s{3,}/i],
  ["squelch", /\b(?:bl(?:o|oo)rp\w*|bloop\w*|splort\w*|squelch\w*|slorp\w*|slurp\w*|squish\w*|plop\w*|glop\w*|gloop\w*|ooze\w*|gurgl\w*)\b/i],
  ["laugh", /\b(?:laugh\w*|giggl\w*|chuckl\w*|cackl\w*|snicker\w*|titter\w*|(?:m[uw]+a+)?(?:ha){2,}h?|(?:he){2,}h?|hee+hee+|heh|hah?|hur(?: hur)*|ho ho)\b/i],
  ["squeal", /\b(?:squeal\w*|squeak\w*|scream\w*|screech\w*|shriek\w*|yelp\w*|yip\w*|a{3,}h+)\b/i],
  ["whimper", /\b(?:whimper\w*|whine\w*|whining|sobs?|sobbing|cry|cries|crying|trembl\w*|shiver\w*|quiver\w*|sniffl\w*)\b/i],
  ["sigh", /\b(?:sigh\w*|yawn\w*|exhal\w*)\b/i],
  ["rumble", /\b(?:rumbl\w*|groan\w*|grind\w*|crumbl\w*|rockslide|stone rains|thunder\w*|boom\w*|crash\w*)\b/i],
  ["zap", /\b(?:crackl\w*|lightning|zap\w*|spark\w*|sizzl\w*)\b/i],
];

// Pure stage directions that make no sound at all (only used when the line has no spoken words and no keyword).
const SILENT = /\b(?:stares?|staring|studies|watches|scratches|picks|tips|narrows|folds|dust|eyes?|coils?|waves?|ducks|backs off|shrinks|settles|pulls|spreads|departs|vanishes|melts|slips|weighs|hunkers|hardens|closes|tastes|stays)\b/i;

// One voice per species: base pitch (Hz), formant scale (small throat = high formants), how breathy/gravelly,
// whether it is wet (blips instead of vowels), what its loud shout is, and what a wordless emote sounds like.
export const VOICES = {
  slime: { f0: 250, size: 1.15, rasp: 0.05, wet: true, big: "squeal", emote: "squelch", remap: { grunt: "squelch", growl: "squelch", bark: "squeal", roar: "squeal", rumble: "squelch", zap: "squelch" } },
  goblin: { f0: 150, size: 0.95, rasp: 0.55, wet: false, big: "roar", emote: "grunt", remap: {} },
  dragon: { f0: 62, size: 0.55, rasp: 0.35, wet: false, big: "roar", emote: "growl", remap: { squelch: "growl" } },
  snake: { f0: 170, size: 1.0, rasp: 0.8, wet: false, big: "hiss", emote: "hiss", remap: { grunt: "hiss", bark: "hiss", roar: "hiss", squeal: "hiss" } },
  rock: { f0: 48, size: 0.5, rasp: 0.7, wet: false, big: "rumble", emote: "rumble", remap: { grunt: "rumble", bark: "rumble", roar: "rumble", laugh: "rumble", squeal: "rumble", hiss: "rumble", whimper: "sigh", squelch: "rumble" } },
  bandit: { f0: 118, size: 1.0, rasp: 0.15, wet: false, big: "roar", emote: "grunt", remap: {} },
};
export const DEFAULT_VOICE = { f0: 130, size: 1, rasp: 0.3, wet: false, big: "roar", emote: "grunt", remap: {} };

const clean = (line) => (typeof line === "string" ? line : "").replace(/\{[^}]*\}/g, " ").slice(0, 400);

// The loudness of a line: shouted (CAPS or !) beats whispered (leading "..." or a pure emote) beats normal.
function loudness(text, spoken) {
  if (/\b[A-Z]{3,}\b/.test(text) || /!/.test(spoken)) return 1;
  if (/^\s*(?:\.\.\.|\*)/.test(text)) return 0.7;
  return 0.85;
}

// Sounds a creature makes with its throat; they win over everything else in the line (earliest first).
// Effect words (a rockslide, lightning, a yawn) only count when nothing shouted or vocal is in the line.
const EFFECT = new Set(["rumble", "zap", "sigh"]);

// The kind of sound a line makes, before species adjustments, or null for a silent line.
export function classifyKind(line) {
  const text = clean(line);
  if (!/[a-z]/i.test(text)) return null;
  const spoken = text.replace(/\*[^*]*\*/g, " ");
  const earliest = (wanted) => {
    let best = null;
    for (const [kind, re] of KEYWORDS) {
      const m = wanted(kind) && re.exec(text);
      if (m && (!best || m.index < best.index)) best = { kind, index: m.index };
    }
    return best?.kind ?? null;
  };
  const vocal = earliest((k) => !EFFECT.has(k));
  if (vocal) return vocal;
  const capsSpoken = /\b[A-Z]{3,}\b/.test(spoken);
  const capsEmote = /\*[^*]*\b[A-Z]{3,}\b[^*]*\*/.test(text);
  const bang = /!/.test(spoken);
  if (capsEmote || (capsSpoken && bang)) return "big";
  const effect = earliest((k) => EFFECT.has(k));
  if (effect) return effect;
  if (capsSpoken || bang) return "bark";
  if (/[a-z]{2,}/i.test(spoken)) return "babble";
  return SILENT.test(text) ? null : "emote";
}

// A full plan for the synth, or null if the line makes no sound.
// { kind, f0, size, rasp, wet, vol, syll, species } — `kind` is one of KINDS.
export function shoutPlan(line, species, { boss = false } = {}) {
  const raw = classifyKind(line);
  if (!raw) return null;
  const v = VOICES[species] ?? DEFAULT_VOICE;
  const text = clean(line);
  const spoken = text.replace(/\*[^*]*\*/g, " ");
  const kind = raw === "big" ? v.big : raw === "emote" ? v.emote : (v.remap[raw] ?? raw);
  const words = (spoken.match(/[a-z']+/gi) ?? []).length;
  return {
    kind,
    species: VOICES[species] ? species : "other",
    f0: v.f0 * (boss ? 0.85 : 1),
    size: v.size * (boss ? 0.9 : 1),
    rasp: v.rasp,
    wet: v.wet,
    vol: loudness(text, spoken) * (boss ? 1.1 : 1),
    syll: Math.max(2, Math.min(6, Math.ceil(words * 0.6))),
  };
}
