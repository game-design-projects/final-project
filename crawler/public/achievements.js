// Achievements: rewards for the things that make Donjon what it is (talking a monster down, winning one over,
// keeping a vow, a natural 20 when it counts), not for grinding. Earned once, kept forever in localStorage,
// across runs and deaths, with the moment each was earned.
//
// game.js only sends events from one-line hooks, e.g. ach.on("recruit", { species, shiny, boss, allies }).
// createAchievements() is the pure part (no DOM, importable in Node for tests): the list, the rules that turn
// events into unlocks, counters, persistence. initAchievements() adds the unlock toast and the K screen.

import { EMOTIONS } from "./emotions.js";
import { SPECIES } from "./species.js";

export const ACH_KEY = "donjon.achievements";
export const TOAST_MS = 3500; // how long an unlock toast stays up
export const MAX_TOASTS = 2; // more than this at once wait their turn (keeps the middle of the view clear)
const STAGGER_MS = 220; // toasts that unlock together slide in one after another
const JINGLE_GAP_MS = 700; // one jingle for a burst of unlocks

const FEELINGS = Object.keys(EMOTIONS); // EMPATH: see every one
const KINDS = Object.keys(SPECIES); // MENAGERIE: recruit every one

// Groups, in screen order, each with its own color (an earned badge glows in it).
export const GROUPS = Object.freeze({
  words: { label: "WORDS", color: "#ff9de2" },
  friends: { label: "FRIENDS", color: "#6bd36b" },
  vows: { label: "VOWS", color: "#c79cff" },
  dice: { label: "DICE", color: "#ffe03a" },
  depths: { label: "DEPTHS", color: "#ff5a4a" },
  oddities: { label: "ODDITIES", color: "#ffb347" },
});

// 7x7 pixel glyphs, drawn like status.js's icons ("#" is a lit pixel).
export const GLYPHS = Object.freeze({
  trophy: ["#######", "#.###.#", "#.###.#", ".#####.", "..###..", "...#...", ".#####."],
  secret: [".####..", "#....#.", "....#..", "...#...", "...#...", ".......", "...#..."],
  up: ["...#...", "..###..", ".#####.", "#######", "...#...", "...#...", "...#..."],
  down: ["...#...", "...#...", "...#...", "#######", ".#####.", "..###..", "...#..."],
  heart: [".##.##.", "#######", "#######", ".#####.", "..###..", "...#...", "......."],
  smile: [".#####.", "#.....#", "#.#.#.#", "#.....#", "#.#.#.#", "#..#..#", ".#####."],
  peace: [".#####.", "#..#..#", "#..#..#", "#.###.#", "##.#.##", "#..#..#", ".#####."],
  bubble: ["#######", "#.....#", "#.#.#.#", "#.....#", "###.###", "..##...", "..#...."],
  boo: ["#.#.#.#", ".......", "#.....#", "..###..", ".#...#.", "..###..", "#.....#"],
  eye: [".......", "..###..", ".#...#.", "#..#..#", ".#...#.", "..###..", "......."],
  paw: [".#...#.", "...#...", ".#...#.", "..###..", ".#####.", ".#####.", "..#.#.."],
  gem: [".#####.", "#.#.#.#", "#######", ".#####.", "..###..", "...#...", "......."],
  trio: ["#..#..#", ".......", "##.#.##", "##.#.##", ".......", "#######", "#######"],
  crown: [".......", "#..#..#", "##.#.##", "#######", "#######", "#######", "......."],
  globe: [".#####.", "#.#.#.#", "#######", "#.#.#.#", "#######", "#.#.#.#", ".#####."],
  scroll: ["#######", ".#...#.", ".#.#.#.", ".#...#.", ".#.#.#.", ".#...#.", "#######"],
  mended: [".##.##.", "###.###", "####.##", ".##.##.", "..#.#..", "...#...", "......."],
  door: [".#####.", ".#...#.", ".#...#.", ".#..##.", ".#...#.", ".#...#.", ".#####."],
  dagger: ["......#", ".....#.", "....#..", "#..#...", ".##....", ".##....", "#..#..."],
  bag: ["..###..", "...#...", ".#####.", "##.#.##", "#..##.#", "##.#.##", ".#####."],
  d20: ["#######", "#.#.#.#", "#.....#", "#..#..#", "#.....#", "#.#.#.#", "#######"],
  mic: ["..###..", "..###..", "..###..", "#.###.#", "#.....#", ".#####.", "...#..."],
  d1: ["#######", "#.....#", "#.....#", "#..#..#", "#.....#", "#.....#", "#######"],
  plus: ["..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.."],
  rise: ["...#...", "..###..", ".#####.", "...#...", "#.....#", ".#...#.", "..###.."],
  stairs: ["......#", ".....##", "....###", "...####", "..#####", ".######", "#######"],
  pit: ["#.....#", "#.....#", ".#...#.", ".#...#.", "..#.#..", "..#.#..", "...#..."],
  skull: ["..###..", ".#####.", "#..#..#", "#######", ".##.##.", "..#.#..", "..#.#.."],
  wave: [".......", "##...##", "##...##", ".......", "#######", ".#####.", "......."],
  star: ["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", ".#...#."],
  coin: ["..###..", ".#####.", "##.####", "##.####", "##.####", ".#####.", "..###.."],
  mirror: ["..###..", ".#...#.", ".#.#.#.", ".#...#.", "..###..", "...#...", "..###.."],
  swords: ["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", "##...##", "##...##"],
  tomb: [".#####.", "##...##", "#..#..#", "#.###.#", "#..#..#", "#.....#", "#######"],
});

// The list. `goal` makes it a counter; `secret` hides its name and line until it's earned.
// Each line says what to do in the game's own words; the trigger is noted beside it (event → condition).
export const ACHIEVEMENTS = Object.freeze(
  [
    // WORDS: talking always matters
    { id: "charmed", group: "words", icon: "heart", name: "CHARMER", desc: "SAY SOMETHING THAT LEAVES A MONSTER DELIGHTED." }, // feel delighted
    { id: "stitches", group: "words", icon: "smile", name: "OPEN MIC NIGHT", desc: "LEAVE A MONSTER IN STITCHES, TOO BUSY LAUGHING TO FIGHT." }, // feel amused
    { id: "peacemaker", group: "words", icon: "peace", name: "PEACEMAKER", desc: "TALK A MONSTER INTO LETTING YOU PASS IN PEACE." }, // peace
    { id: "all_talk", group: "words", icon: "bubble", name: "ALL TALK", desc: "WIN A FIGHT WITHOUT A SINGLE ATTACK." }, // fight-end: won, no attack, no kill
    { id: "boo", group: "words", icon: "boo", name: "BOO!", desc: "SCARE A MONSTER SO BADLY IT DROPS ITS GOLD." }, // feel terrified
    { id: "empath", group: "words", icon: "eye", name: "EMPATH", desc: "SEE MONSTERS FEEL ALL 10 FEELINGS, OVER ALL YOUR RUNS.", goal: FEELINGS.length, values: FEELINGS }, // feel *
    // FRIENDS: recruiting
    { id: "first_friend", group: "friends", icon: "paw", name: "FIRST FRIEND", desc: "WIN A MONSTER OVER TO YOUR PARTY." }, // recruit
    { id: "shiny", group: "friends", icon: "gem", name: "ALL THAT GLITTERS", desc: "RECRUIT A SHINY. FATE OWES YOU A ROLL." }, // recruit shiny
    { id: "mash", group: "friends", icon: "trio", name: "MONSTER MASH", desc: "TRAVEL WITH THREE MONSTER ALLIES AT ONCE." }, // recruit, allies >= 3
    { id: "red_carpet", group: "friends", icon: "crown", name: "RED CARPET", desc: "WIN A RED CHAMPION OVER TO YOUR SIDE." }, // recruit boss
    { id: "menagerie", group: "friends", icon: "globe", name: "MENAGERIE", desc: "RECRUIT EVERY KIND OF MONSTER, OVER ALL YOUR RUNS.", goal: KINDS.length, values: KINDS }, // recruit *
    // VOWS
    { id: "word_is_bond", group: "vows", icon: "scroll", name: "WORD IS BOND", desc: "TAKE THE STAIRS WITH A VOW TO AN ALLY UNBROKEN." }, // descend, keptVows > 0
    { id: "second_chance", group: "vows", icon: "mended", name: "SECOND CHANCES", desc: "BREAK A VOW TO AN ALLY, AND BE FORGIVEN." }, // vow-broken forgive
    { id: "walked_out", group: "vows", icon: "door", name: "IT'S YOU, NOT ME", desc: "HAVE AN ALLY WALK OUT ON THE PARTY." }, // vow-broken leave / ally-decision leave
    { id: "betrayed", group: "vows", icon: "dagger", name: "ET TU?", desc: "HAVE AN ALLY TURN ON YOU.", secret: true }, // vow-broken attack / ally-decision turn_on_party
    { id: "robbed", group: "vows", icon: "bag", name: "LIGHT FINGERS", desc: "HAVE AN ALLY RUN OFF WITH YOUR GOLD.", secret: true }, // vow-broken steal_gold, got away
    // DICE
    { id: "crit_happens", group: "dice", icon: "d20", name: "CRIT HAPPENS", desc: "ROLL A NATURAL 20 ON AN ATTACK." }, // attack-roll 20
    { id: "mic_drop", group: "dice", icon: "mic", name: "MIC DROP", desc: "ROLL A NATURAL 20 WHILE TALKING. WORDS LAND DOUBLE." }, // talk-roll 20
    { id: "fail_forward", group: "dice", icon: "d1", name: "FAIL FORWARD", desc: "FUMBLE YOUR WORDS ON A 1, THEN WIN THEM OVER ANYWAY." }, // talk-roll 1, then recruit/peace in that fight
    { id: "still_breathing", group: "dice", icon: "plus", name: "STILL BREATHING", desc: "PULL THROUGH THREE DEATH SAVES AND STABILIZE." }, // death-save stable
    { id: "not_today", group: "dice", icon: "rise", name: "NOT TODAY", desc: "ROLL A 20 ON A DEATH SAVE AND GET BACK UP." }, // death-save 20
    // DEPTHS: progression
    { id: "deep5", group: "depths", icon: "stairs", name: "INTO THE DARK", desc: "REACH FLOOR 5." }, // descend floor >= 5
    { id: "deep10", group: "depths", icon: "pit", name: "ABYSS GAZER", desc: "REACH FLOOR 10. IT GAZES BACK." }, // descend floor >= 10
    { id: "seeing_red", group: "depths", icon: "skull", name: "SEEING RED", desc: "SLAY A RED CHAMPION." }, // fight-end boss dead
    { id: "stand_down", group: "depths", icon: "wave", name: "STAND DOWN", desc: "TALK A RED CHAMPION INTO LETTING YOU PASS." }, // peace boss
    { id: "legendary", group: "depths", icon: "star", name: "LEGENDARY", desc: "LAND A LEGENDARY BOON ON A GREAT ROLL OF FATE." }, // boon legendary
    // ODDITIES
    { id: "goblin_tax", group: "oddities", icon: "coin", name: "GOBLIN TAX", desc: "PAY A GOBLIN. IT TAKES THE GOLD, OBVIOUSLY.", secret: true }, // paid goblin
    { id: "so_vain", group: "oddities", icon: "mirror", name: "SO VAIN", desc: "FLATTER A DRAGON. IT AGREES WITH EVERY WORD.", secret: true }, // feel flattered, dragon
    { id: "mutiny", group: "oddities", icon: "swords", name: "MUTINY", desc: "SEE A MONSTER TURN ON ITS OWN GROUP.", secret: true }, // mutiny
    { id: "permadeath", group: "oddities", icon: "tomb", name: "PERMADEATH", desc: "LOSE A WHOLE PARTY. IT HAPPENS TO THE BEST." }, // wipe
  ].map((a) => Object.freeze(a)),
);

const BY_ID = Object.fromEntries(ACHIEVEMENTS.map((a) => [a.id, a]));

// What each game event earns. `s` is the instance: s.unlock(id), s.count(id, value), s.fight (this fight's notes).
const RULES = {
  "fight-start": (s) => {
    s.fight = { attacked: false, fumbled: false };
  },
  attack: (s) => {
    if (s.fight) s.fight.attacked = true;
  },
  "fight-end": (s, { won, kills, boss } = {}) => {
    if (s.fight && won && !kills && !s.fight.attacked) s.unlock("all_talk");
    if (boss === "dead") s.unlock("seeing_red");
    s.fight = null;
  },
  feel: (s, { feeling, species } = {}) => {
    if (feeling === "delighted") s.unlock("charmed");
    if (feeling === "amused") s.unlock("stitches");
    if (feeling === "terrified") s.unlock("boo");
    if (feeling === "flattered" && species === "dragon") s.unlock("so_vain");
    s.count("empath", feeling);
  },
  "talk-roll": (s, { roll } = {}) => {
    if (roll === 20) s.unlock("mic_drop");
    if (roll === 1 && s.fight) s.fight.fumbled = true;
  },
  "attack-roll": (s, { roll } = {}) => {
    if (roll === 20) s.unlock("crit_happens");
  },
  recruit: (s, { species, shiny, boss, allies = 0 } = {}) => {
    s.unlock("first_friend");
    if (shiny) s.unlock("shiny");
    if (boss) s.unlock("red_carpet");
    if (allies >= 3) s.unlock("mash");
    if (s.fight?.fumbled) s.unlock("fail_forward");
    s.count("menagerie", species);
  },
  peace: (s, { boss } = {}) => {
    s.unlock("peacemaker");
    if (boss) s.unlock("stand_down");
    if (s.fight?.fumbled) s.unlock("fail_forward");
  },
  "death-save": (s, { roll, stable } = {}) => {
    if (stable) s.unlock("still_breathing");
    if (roll === 20) s.unlock("not_today");
  },
  descend: (s, { floor = 0, keptVows = 0 } = {}) => {
    if (floor >= 5) s.unlock("deep5");
    if (floor >= 10) s.unlock("deep10");
    if (keptVows > 0) s.unlock("word_is_bond");
  },
  boon: (s, { legendary } = {}) => {
    if (legendary) s.unlock("legendary");
  },
  "vow-broken": (s, { response, stolen } = {}) => {
    if (response === "forgive") s.unlock("second_chance");
    if (response === "leave_party") s.unlock("walked_out");
    if (response === "attack_party") s.unlock("betrayed");
    if (response === "steal_gold" && stolen) s.unlock("robbed");
  },
  "ally-decision": (s, { decision } = {}) => {
    if (decision === "leave_party") s.unlock("walked_out");
    if (decision === "turn_on_party") s.unlock("betrayed");
  },
  paid: (s, { species } = {}) => {
    if (species === "goblin") s.unlock("goblin_tax");
  },
  mutiny: (s) => s.unlock("mutiny"),
  wipe: (s) => s.unlock("permadeath"),
};

// Read the saved state, keeping only what still makes sense (known ids, numeric dates, known counter values).
function load(store) {
  let raw = null;
  try {
    raw = JSON.parse(store?.get(ACH_KEY) ?? "null");
  } catch {}
  const earned = {};
  const progress = {};
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    for (const [id, at] of Object.entries(raw.earned ?? {})) if (BY_ID[id] && Number.isFinite(at)) earned[id] = at;
    for (const [id, vals] of Object.entries(raw.progress ?? {}))
      if (BY_ID[id]?.values && Array.isArray(vals)) progress[id] = [...new Set(vals.filter((v) => BY_ID[id].values.includes(v)))];
  }
  return { earned, progress };
}

export function createAchievements({ store, now = () => Date.now(), onUnlock = () => {}, log = () => {} } = {}) {
  let { earned, progress } = load(store);

  const save = () => {
    try {
      store?.set(ACH_KEY, JSON.stringify({ v: 1, earned, progress }));
    } catch {}
  };

  const view = (a) => {
    const got = a.id in earned;
    const hide = a.secret && !got;
    return {
      ...a,
      name: hide ? "???" : a.name,
      desc: hide ? "???" : a.desc,
      earned: got,
      at: earned[a.id] ?? null,
      progress: a.goal ? { n: (progress[a.id] ?? []).length, goal: a.goal } : null,
    };
  };

  const s = {
    fight: null,
    unlock(id) {
      const a = BY_ID[id];
      if (!a) {
        log("unknown achievement", id);
        return false;
      }
      if (id in earned) return false;
      earned[id] = now();
      save();
      log("unlock", id);
      try {
        onUnlock(view(a));
      } catch (err) {
        log("onUnlock failed", err);
      }
      return true;
    },
    // A counter: one more distinct value seen; unlocks when every value has been seen.
    count(id, value) {
      const a = BY_ID[id];
      if (!a?.values?.includes(value)) return;
      const seen = (progress[id] ??= []);
      if (seen.includes(value)) return;
      seen.push(value);
      save();
      log("progress", id, `${seen.length}/${a.goal}`);
      if (seen.length >= a.goal) s.unlock(id);
    },
  };

  function on(event, data = {}) {
    const rule = RULES[event];
    if (!rule) return log("unknown event", event);
    try {
      rule(s, data ?? {});
    } catch (err) {
      log("rule failed", event, err);
    }
  }

  return {
    on,
    unlock: (id) => s.unlock(id),
    has: (id) => id in earned,
    earnedAt: (id) => earned[id] ?? null,
    progress: (id) => (BY_ID[id]?.goal ? { n: (progress[id] ?? []).length, goal: BY_ID[id].goal } : null),
    count: () => ({ earned: Object.keys(earned).length, total: ACHIEVEMENTS.length }),
    list: () => ACHIEVEMENTS.map(view),
    reset() {
      earned = {};
      progress = {};
      s.fight = null;
      save();
      log("reset");
    },
  };
}

// ---------------------------------------------------------------- markup (pure strings; the DOM part is below)

const escHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
export const fmtDate = (ms) => {
  const d = new Date(ms);
  return `${MONTHS[d.getMonth()]} ${d.getDate()} ${d.getFullYear()}`;
};

export function badgeSvg(name, color = "currentColor") {
  const rows = GLYPHS[name] ?? GLYPHS.secret;
  let d = "";
  rows.forEach((row, y) => [...row].forEach((c, x) => c === "#" && (d += `M${x} ${y}h1v1h-1z`)));
  return `<svg class="ico" viewBox="0 0 7 7" shape-rendering="crispEdges" aria-hidden="true"><path fill="${color}" d="${d}"/></svg>`;
}

const colorOf = (a) => GROUPS[a.group]?.color ?? "#ffd27a";
const glyphOf = (a) => (a.secret && !a.earned ? "secret" : a.icon);

// The unlock toast: the badge, its name and line, and the new total.
export function toastHtml(a, { earned, total } = {}) {
  return `<span class="ach-ico">${badgeSvg(a.icon, colorOf(a))}</span><span class="ach-txt"><span class="ach-tag">ACHIEVEMENT UNLOCKED</span><b>${escHtml(a.name)}</b><small>${escHtml(a.desc)}</small></span>${
    total ? `<span class="ach-n">${earned}/${total}</span>` : ""
  }`;
}

function badgeHtml(a) {
  const cls = `badge ${a.earned ? "earned" : "locked"}${a.secret && !a.earned ? " secret" : ""}`;
  let meta;
  if (a.earned) meta = `<span class="bdate">EARNED ${fmtDate(a.at)}</span>`;
  else if (a.progress)
    meta = `<span class="bprog"><span class="bbar"><i style="width:${Math.round((a.progress.n / a.progress.goal) * 100)}%"></i></span>${a.progress.n}/${a.progress.goal}</span>`;
  else meta = a.secret ? `<span class="block">SECRET</span>` : "";
  // " · " splits a title into lines for the pixel tooltips (tooltip.js); the first line is the heading
  const tip = a.earned ? `${a.name} · ${a.desc} · EARNED ${fmtDate(a.at)}` : a.secret ? "A SECRET · KEEP PLAYING." : `${a.name} · ${a.desc}${a.progress ? ` · ${a.progress.n} OF ${a.progress.goal} SO FAR` : ""}`;
  return `<div class="${cls}" style="--g:${colorOf(a)}" title="${escHtml(tip)}"><span class="bicon">${badgeSvg(glyphOf(a), a.earned ? colorOf(a) : "#5a5a5a")}</span><span class="btext"><b>${escHtml(a.name)}</b><span class="bdesc">${escHtml(a.desc)}</span>${meta}</span></div>`;
}

// The K screen: the total, then every badge by group.
export function screenHtml(list, { earned, total }) {
  const groups = Object.entries(GROUPS)
    .map(([g, info]) => {
      const items = list.filter((a) => a.group === g);
      if (!items.length) return "";
      const got = items.filter((a) => a.earned).length;
      return `<section class="ach-group" style="--g:${info.color}"><h3>${info.label} <small>${got}/${items.length}</small></h3><div class="ach-grid">${items.map(badgeHtml).join("")}</div></section>`;
    })
    .join("");
  const pct = total ? Math.round((earned / total) * 100) : 0;
  return `<div class="ach-panel" role="dialog" aria-label="Achievements"><header class="ach-head"><h2>${badgeSvg("trophy", "#ffd27a")}ACHIEVEMENTS</h2><span class="ach-total"><b>${earned}</b>/${total}</span><span class="ach-meter" title="${pct}% EARNED"><i style="width:${pct}%"></i></span><span class="ach-keys"><button type="button" class="cmd" data-act="close"><kbd>K</kbd><span class="lbl">CLOSE</span></button><button type="button" class="cmd" data-act="close"><kbd>ESC</kbd></button></span></header><div class="ach-body">${groups}</div><p class="ach-foot">EARNED ONCE, KEPT FOR GOOD: ACROSS EVERY RUN, EVEN AFTER DEATH. <span class="how"><kbd>${badgeSvg("up", "#e8e8e8")}</kbd><kbd>${badgeSvg("down", "#e8e8e8")}</kbd> SCROLL</span></p></div>`;
}

// ---------------------------------------------------------------- toast + screen (browser only)

// Keys a player means as commands: these nudge the open screen; Shift, Tab and the like don't.
const COMMAND_KEYS = new Set(["fwd", "back", "turnL", "turnR", "enter", "escape"]);

// view: the dungeon canvas (toasts go over it); the screen covers the view and the side column (.mid).
// accent(): the floor's accent color, for the screen's lit frame. jingle(): the unlock sound (sfx respects O).
// onUnlock(a): the game's own reaction (a line in the log). onToggle(open): the screen opened or closed.
export function initAchievements({ store, view, accent = () => null, jingle = () => {}, onUnlock = () => {}, onToggle = () => {} } = {}) {
  const log = (...a) => console.debug("[achievements]", ...a);
  if (typeof document === "undefined") return { ...createAchievements({ store, onUnlock, log }), open() {}, close() {}, isOpen: () => false, key: () => false };

  const host = view.closest(".viewport") ?? view.parentElement;
  const stack = document.createElement("div");
  stack.className = "ach-toasts";
  stack.setAttribute("role", "status");
  stack.setAttribute("aria-live", "polite");
  view.after(stack); // before the yes/no modal in the page, so a question always sits on top
  const area = view.closest(".mid") ?? host;
  const screen = document.createElement("div");
  screen.className = "ach-screen";
  screen.hidden = true;
  area.append(screen);

  const queue = [];
  let showing = 0;
  let nextAt = 0;
  let lastJingle = -Infinity;

  function pump() {
    while (queue.length && showing < MAX_TOASTS) {
      const { a, count } = queue.shift();
      const wait = Math.max(0, nextAt - performance.now());
      nextAt = performance.now() + wait + STAGGER_MS;
      showing++;
      setTimeout(() => showToast(a, count), wait);
    }
  }

  function showToast(a, count) {
    const el = document.createElement("div");
    el.className = "ach-toast";
    el.style.setProperty("--g", colorOf(a));
    el.innerHTML = toastHtml(a, count);
    stack.append(el);
    const t = performance.now();
    if (t - lastJingle > JINGLE_GAP_MS) {
      lastJingle = t;
      jingle();
    }
    setTimeout(() => {
      el.classList.add("out");
      setTimeout(() => {
        el.remove();
        showing--;
        pump();
      }, 260);
    }, TOAST_MS);
  }

  const core = createAchievements({
    store,
    log,
    onUnlock(a) {
      queue.push({ a, count: core?.count() });
      pump();
      onUnlock(a);
      if (screen.hidden === false) paint();
    },
  });

  const paint = () => {
    const body = screen.querySelector(".ach-body");
    const top = body?.scrollTop ?? 0;
    screen.innerHTML = screenHtml(core.list(), core.count());
    screen.querySelector(".ach-body").scrollTop = top;
  };

  function open() {
    screen.style.setProperty("--accent", accent() ?? "#ffb347");
    paint();
    screen.hidden = false;
    screen.classList.remove("nudge");
    log("open");
    onToggle(true);
  }
  function close() {
    screen.hidden = true;
    log("close");
    onToggle(false);
  }
  function nudge() {
    screen.classList.remove("nudge");
    void screen.offsetWidth;
    screen.classList.add("nudge");
  }
  // While the screen is open it takes every key: K or Esc closes, up/down scroll, anything else nudges it.
  function key(k) {
    if (screen.hidden) return false;
    if (k === "k" || k === "escape") close();
    else if (k === "fwd" || k === "back") screen.querySelector(".ach-body")?.scrollBy({ top: k === "fwd" ? -90 : 90, behavior: "smooth" });
    else if (String(k).length === 1 || COMMAND_KEYS.has(k)) nudge();
    return true;
  }

  screen.addEventListener("click", (ev) => {
    if (ev.target === screen || ev.target.closest("[data-act=close]")) {
      ev.stopPropagation();
      close();
    }
  });

  return { ...core, open, close, isOpen: () => !screen.hidden, key };
}
