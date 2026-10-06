// How party members and monsters look at a glance: health states, conditions, loyalty and spell slots
// as plain words plus a color. Pure data and helpers, no DOM, so the party panel and the canvas share them.

export const HP_COLORS = {
  healthy: "#6bd36b",
  hurt: "#ffd23f",
  critical: "#ff5a4a",
  dying: "#ff5a4a",
  stable: "#c08a8a",
  dead: "#5a5a5a",
};

const HP_WORDS = { healthy: "HEALTHY", hurt: "HURT", critical: "CRITICAL", dying: "DYING", stable: "STABLE", dead: "DEAD" };

// Healthy from 75% of max health, hurt from 35%, critical below that. Down members are dying until stable.
export function hpState(m) {
  const pct = m.maxHp > 0 ? Math.max(0, Math.min(1, m.hp / m.maxHp)) : 0;
  const id = m.dead ? "dead" : m.down ? (m.stable ? "stable" : "dying") : pct >= 0.75 ? "healthy" : pct >= 0.35 ? "hurt" : "critical";
  return { id, word: HP_WORDS[id], color: HP_COLORS[id], pct };
}

// Every condition a party member or monster can have, in display order. Party troubles first, then monster states.
export const CONDITIONS = {
  asleep: { word: "ASLEEP", icon: "zzz", color: "#8fd3ff", tip: "ASLEEP: SKIPS ITS TURNS UNTIL HURT. HITS ON IT ARE CRITICAL" },
  held: { word: "PARALYZED", icon: "bolt", color: "#8fd3ff", tip: "PARALYZED: SKIPS ITS TURNS. HITS ON IT ARE CRITICAL" },
  poisoned: { word: "POISONED", icon: "drop", color: "#9ed36b", tip: "POISONED: ROLLS TWICE AND KEEPS THE WORSE ON ATTACKS" },
  restrained: { word: "ENTANGLED", icon: "chain", color: "#d39a6a", tip: "ENTANGLED: WORSE ATTACKS, AND EASIER TO HIT" },
  prone: { word: "KNOCKED DOWN", icon: "down", color: "#ffb347", tip: "KNOCKED DOWN: LOSES ITS NEXT TURN GETTING UP" },
  charmed: { word: "CHARMED", icon: "heart", color: "#ff9de2", tip: "CHARMED: WON'T ATTACK THIS ROUND" },
  laughing: { word: "LAUGHING", icon: "smile", color: "#ffe14a", tip: "LAUGHING: TOO BUSY LAUGHING TO FIGHT" },
  confused: { word: "CONFUSED", icon: "what", color: "#b79cf0", tip: "CONFUSED: LOSES ITS TURN" },
  frightened: { word: "SCARED", icon: "alarm", color: "#cfe8ff", tip: "SCARED: ITS ATTACKS ARE WORSE" },
  demoralized: { word: "SADDENED", icon: "frown", color: "#7f9cff", tip: "SADDENED: ITS ATTACKS ARE WORSE" },
  spiteful: { word: "SPITEFUL", icon: "flame", color: "#ff8a5a", tip: "SPITEFUL: HITS YOU 2 HARDER" },
  enraged: { word: "ENRAGED", icon: "flame", color: "#ff5a4a", tip: "ENRAGED: ATTACKS BETTER AND HITS 3 HARDER, BUT IS EASIER TO HIT" },
  exposed: { word: "OFF GUARD", icon: "target", color: "#ffd27a", tip: "OFF GUARD: YOUR ATTACKS ON IT ARE BETTER" },
  weakspot: { word: "WEAK SPOT", icon: "target", color: "#ffd27a", tip: "WEAK SPOT: +2 TO HIT IT FOR THE REST OF THE FIGHT" },
  lit: { word: "GLOWING", icon: "star", color: "#fff3a0", tip: "GLOWING: THE NEXT ATTACK ON IT IS BETTER" },
  dodging: { word: "DODGING", icon: "dodge", color: "#aaaaaa", tip: "DODGING: YOUR ATTACKS ON IT ARE WORSE THIS ROUND" },
};

// A creature's conditions as [{ id, word, color, tip }], at most `max` of them.
export function condList(cond, max = Infinity) {
  if (!cond) return [];
  return Object.keys(CONDITIONS)
    .filter((k) => cond[k])
    .slice(0, max)
    .map((k) => ({ id: k, ...CONDITIONS[k] }));
}

// How a monster ally feels about staying with you.
export function loyaltyState(l) {
  if (l >= 75) return { word: "DEVOTED", color: "#6bd36b" };
  if (l >= 50) return { word: "CONTENT", color: "#a8d38f" };
  if (l >= 30) return { word: "UNEASY", color: "#ffd23f" };
  if (l >= 15) return { word: "RESENTFUL", color: "#ff9a3d" };
  return { word: "MAY LEAVE", color: "#ff5a4a" };
}

// One color per spell circle, so a circle-3 spell in a menu matches the gold pips in the party panel.
export const CIRCLE_COLORS = ["#8fd3ff", "#c79cff", "#ffd27a"];
export const CIRCLE_WORDS = ["FIRST", "SECOND", "THIRD"];

export function slotGroups(slots, maxSlots) {
  if (!maxSlots) return [];
  return maxSlots.map((max, i) => {
    const left = Math.max(0, Math.min(max, slots?.[i] ?? 0));
    return { circle: i + 1, left, max, color: CIRCLE_COLORS[i] ?? "#e8e8e8", pips: Array.from({ length: max }, (_, j) => j < left) };
  });
}

const CLASS_WORDS = { fighter: "FIGHTER", cleric: "CLERIC", wizard: "WIZARD" };
const SPECIES_WORDS = { slime: "SLIME", goblin: "GOBLIN", dragon: "DRAGON", snake: "SNAKE PERSON", rock: "ROCK ENTITY", bandit: "BANDIT" };
export const classWord = (m) => (m.kind === "human" ? (CLASS_WORDS[m.clsId] ?? String(m.clsId).toUpperCase()) : (SPECIES_WORDS[m.species] ?? String(m.species).toUpperCase()));

export const facingWord = (dir) => ["NORTH", "EAST", "SOUTH", "WEST"][dir] ?? "";
export const floorName = (n) => `FLOOR ${n}`;

// 7x7 pixel icons, so states read by shape before you read a word. "#" is a lit pixel.
export const ICONS = {
  // the top bar's toggles: music, sound effects, voices (text to speech), tips, the Jev panel
  note: ["...###.", "...#..#", "...#...", "...#...", ".###...", "####...", ".##...."],
  speaker: ["...#...", "..##.#.", "####..#", "####..#", "####..#", "..##.#.", "...#..."],
  bubble: [".#####.", "#######", "##.#.##", "#######", ".#####.", "..##...", ".#....."],
  question: ["..###..", ".#...#.", ".....#.", "...##..", "...#...", ".......", "...#..."],
  eye: [".......", ".#####.", "#..#..#", "#.###.#", "#..#..#", ".#####.", "......."],
  heart: [".##.##.", "#######", "#######", ".#####.", "..###..", "...#...", "......."],
  skull: ["..###..", ".#####.", "#..#..#", "#######", ".##.##.", "..#.#..", "..#.#.."],
  zzz: ["####...", "..#....", ".#.....", "####...", "....###", ".....#.", "....###"],
  drop: ["...#...", "..###..", ".#####.", ".#####.", "#######", ".#####.", "..###.."],
  chain: [".##....", "#..#...", "#..##..", ".##..#.", "...#..#", "...#..#", "....##."],
  shield: ["#######", "#######", "#######", "#######", ".#####.", "..###..", "...#..."],
  down: ["...#...", "...#...", "...#...", "#######", ".#####.", "..###..", "...#..."],
  up: ["...#...", "..###..", ".#####.", "#######", "...#...", "...#...", "...#..."],
  left: ["...#...", "..##...", ".######", "#######", ".######", "..##...", "...#..."],
  right: ["...#...", "...##..", "######.", "#######", "######.", "...##..", "...#..."],
  coin: ["..###..", ".#####.", "##.####", "##.####", "##.####", ".#####.", "..###.."],
  star: ["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", ".#...#."],
  bolt: ["...###.", "..###..", ".###...", "#######", "...###.", "..###..", ".##...."],
  flame: ["...#...", "..##...", "..###.#", ".#####.", "#######", "#######", ".#####."],
  target: [".#####.", "#.....#", "#.###.#", "#.###.#", "#.###.#", "#.....#", ".#####."],
  smile: [".#####.", "#.....#", "#.#.#.#", "#.....#", "#.#.#.#", "#..#..#", ".#####."],
  frown: [".#####.", "#.....#", "#.#.#.#", "#.....#", "#..#..#", "#.#.#.#", ".#####."],
  what: [".####..", "#....#.", "....#..", "...#...", "...#...", ".......", "...#..."],
  alarm: ["...#...", "...#...", "...#...", "...#...", "...#...", ".......", "...#..."],
  dodge: ["#......", "##.....", "###....", "####...", "###....", "##.....", "#......"],
  dot: [".......", "..###..", ".#####.", ".#####.", ".#####.", "..###..", "......."],
};

// An icon as a crisp inline SVG (scaled by CSS), in the given color.
export function iconSvg(name, color = "currentColor") {
  const rows = ICONS[name] ?? ICONS.dot;
  let d = "";
  rows.forEach((row, y) => [...row].forEach((c, x) => c === "#" && (d += `M${x} ${y}h1v1h-1z`)));
  return `<svg class="ico" viewBox="0 0 7 7" shape-rendering="crispEdges" aria-hidden="true"><path fill="${color}" d="${d}"/></svg>`;
}

// Moving the highlight in a menu: wraps at both ends.
export const menuStep = (sel, delta, count) => (((sel ?? -delta) + delta) % count + count) % count;

// The party holds six. Adventurers keep their seats (even fallen ones); monster allies fill the rest.
export const PARTY_MAX = 6;
export function allyRoom(party) {
  const allies = party.filter((m) => m.kind === "monster").length;
  const max = PARTY_MAX - (party.length - allies);
  return { allies, max, full: party.length >= PARTY_MAX };
}
