// How a monster can feel about what the party just did or said. Jev picks one each time the party talks,
// gives, or asks it to join; code owns what each feeling does, so every word has a visible consequence.
// meters: added to friendliness / anger / fear (scaled by the speaker's Charisma roll when talking).
// cond: a combat condition it gains for `rounds` rounds of its own.

export const EMOTIONS = {
  delighted: {
    label: "DELIGHTED",
    what: "Delighted or charmed by the party",
    when: "The party was warm, generous, or gave it something it loves",
    meters: { friendliness: 20, anger: -12 },
    cond: "charmed",
    rounds: 1,
    effect: "WON'T ATTACK THIS ROUND",
    tone: "good",
  },
  amused: {
    label: "IN STITCHES",
    what: "Bursts out laughing",
    when: "The party said something funny, silly or absurd",
    meters: { friendliness: 14, anger: -8 },
    cond: "laughing",
    rounds: 1,
    effect: "TOO BUSY LAUGHING TO FIGHT",
    tone: "good",
  },
  touched: {
    label: "TOUCHED",
    what: "Moved, touched, or deeply understood",
    when: "The party showed real care, respect, or understanding of what it values",
    meters: { friendliness: 26, anger: -16 },
    effect: "ITS HEART OPENS TO YOU",
    tone: "good",
  },
  flattered: {
    label: "FLATTERED",
    what: "Flattered and puffed up with pride",
    when: "The party praised it, its looks, or its strength",
    meters: { friendliness: 16 },
    cond: "exposed",
    rounds: 2,
    effect: "PRIDE LOWERS ITS GUARD: ADVANTAGE AGAINST IT",
    tone: "good",
  },
  intrigued: {
    label: "INTRIGUED",
    what: "Curious and intrigued; it lets its guard slip while it thinks",
    when: "The party asked it questions or said something surprising or mysterious",
    meters: { friendliness: 8, fear: -6 },
    cond: "weakspot",
    rounds: 99,
    effect: "IT LETS SLIP A WEAK SPOT: +2 TO HIT IT",
    tone: "odd",
  },
  confused: {
    label: "CONFUSED",
    what: "Baffled; it doesn't understand at all",
    when: "The party's words made no sense to it, or were nonsense",
    meters: { anger: 4 },
    cond: "confused",
    rounds: 1,
    effect: "LOSES ITS TURN",
    tone: "odd",
  },
  sad: {
    label: "SADDENED",
    what: "Saddened, guilty, or hurt in its feelings",
    when: "The party said something sad or guilt-inducing, or reminded it of a loss",
    meters: { friendliness: 6, fear: 8, anger: -6 },
    cond: "demoralized",
    rounds: 3,
    effect: "DISADVANTAGE ON ITS ATTACKS",
    tone: "sad",
  },
  offended: {
    label: "OFFENDED",
    what: "Offended and spiteful",
    when: "The party was rude, dismissive, stingy, or went against what it values",
    meters: { anger: 22, friendliness: -14 },
    cond: "spiteful",
    rounds: 3,
    effect: "+2 DAMAGE AGAINST YOU",
    tone: "bad",
  },
  enraged: {
    label: "ENRAGED",
    what: "Flies into a furious rage",
    when: "The party insulted, threatened, or hurt it or its kind badly",
    meters: { anger: 38, friendliness: -22 },
    cond: "enraged",
    rounds: 3,
    effect: "ADVANTAGE AND +3 DAMAGE, BUT RECKLESS: AC -3",
    tone: "bad",
  },
  terrified: {
    label: "TERRIFIED",
    what: "Terrified or intimidated",
    when: "The party threatened it convincingly or showed overwhelming strength",
    meters: { fear: 38, anger: -6 },
    cond: "frightened",
    rounds: 3,
    effect: "DISADVANTAGE ON ATTACKS. IT DROPS SOME GOLD",
    tone: "fear",
  },
};

// Feelings that stop a monster from attacking in the same round.
export const PACIFYING = new Set(["charmed", "laughing", "confused"]);

// How the party's "please join us" landed, from the Charisma (Persuasion) roll. Code applies these.
// reach: a pitch that beats the DC brings the monster at least this far past its join bar (and cools its anger
// below the bar for joining), so "A CONVINCING PITCH" really convinces it; Jev still decides whether it says yes,
// and why. Without this, a passed check often left the monster short of its bar and it refused with no reason.
export const PITCH = {
  great: { friendliness: 30, anger: -10, reach: 10, words: "an irresistible pitch" },
  success: { friendliness: 18, anger: -5, reach: 0, words: "a convincing pitch" },
  close: { friendliness: 6, anger: 0, words: "a pitch that almost convinced it" },
  fail: { friendliness: -6, anger: 12, words: "a clumsy, off-putting pitch" },
  botch: { friendliness: -14, anger: 25, words: "an insulting, disastrous pitch" },
};
