// Tips: a just-in-time tutorial. Each hint is one or two short lines, shown once, at the moment it
// matters, in a framed note over the bottom of the dungeon view. While it's up, the things it talks about
// (the keys' buttons, the automap, the party) are lit up too.
//
// Hints never take input away. The key you press still does its job and also clears the hint; a key the
// game ignores nudges the hint instead of vanishing silently. H turns tips off; H again starts them over.
//
// game.js only calls tips.hint(id) at each trigger point, plus tips.ignored(key) where a key does nothing.
// createTutorial() is the pure part (no DOM, importable in Node for tests); initTutorial() adds the box.

export const SEEN_KEY = "hallsOfJev.tipsSeen";
export const OFF_KEY = "hallsOfJev.tipsOff";
export const GRACE_MS = 900; // keys this soon after a hint appears don't clear it (a held key, or the one that triggered it)
export const MIN_READ_MS = 2500; // a hint pushed aside sooner than this gets another turn
export const GAP_MS = 700; // a breath between one hint and the next
export const TTL_MS = 30000; // a hint nobody clears fades on its own
export const REMIND_WINDOW_MS = 4000; // two ignored keys this close together bring back the reminder
export const REMIND_COOLDOWN_MS = 20000;

// Where the game is. Hints only show while you're exploring or fighting, never over a question or a roll.
const GAMEPLAY = new Set(["explore", "combat"]);
// What to remind a flailing player of, by where they are.
const PRIMER = { explore: "move", combat: "combat" };
// Keys a player means as commands (single characters plus the game's names for the arrows).
const COMMAND_KEYS = new Set(["fwd", "back", "turnL", "turnR", "enter", "escape"]);
const ARROWS = { "↑": "fwd", "↓": "back", "←": "turnL", "→": "turnR" };

// {K} is a keycap, {!K} the one to press (it blinks). ctx: when it may show ("explore", "combat" or "any").
// focus: extra things to light up; keys: false when a keycap's key means something else where the hint shows.
export const HINTS = Object.freeze({
  move: { ctx: "explore", lines: ["{!↑} STEP  {←}{→} TURN  {↓} BACK", "OR WASD. FIND THE STAIRS DOWN."] },
  map: { ctx: "explore", focus: ["#map"], lines: ["YOUR MAP DRAWS ITSELF AS YOU WALK.", "{!M} SHOWS OR HIDES IT."] },
  stairs: { ctx: "explore", focus: ["#map"], lines: ["STAIRS! THEY'RE ON YOUR MAP NOW.", "GOING DOWN EARNS A ROLL OF FATE."] },
  boss: { ctx: "explore", focus: ["#map"], lines: ["THE RED MARK ON YOUR MAP: A CHAMPION.", "OPTIONAL. BRUTAL. CAN BE TALKED DOWN."] },
  combat: { ctx: "combat", lines: ["{F} QUICK ATTACK  {C} CHOOSE MOVES", "{E} ESCAPE, OR {!T} TALK. IT LISTENS."] },
  target: { ctx: "combat", lines: ["{!1}{2}{3} PICK WHICH ONE YOU AIM AT.", "WHEN YOU TALK, THEY ALL HEAR IT."] },
  feeling: { ctx: "combat", focus: ["#log"], lines: ["IT FEELS SOMETHING, AND FEELINGS BITE:", "EACH ONE CHANGES HOW IT FIGHTS."] },
  recruit: { ctx: "combat", lines: ["IT'S WARMING TO YOU. {!R} ASKS IT TO JOIN.", "THE FRIENDLIER IT IS, THE EASIER."] },
  ally: { ctx: "explore", focus: ["#party"], lines: ["YOUR ALLY FIGHTS ON ITS OWN, AND JUDGES", "WHAT YOU DO. {!E} TALKS TO IT."] },
  camp: { ctx: "explore", focus: ["#party"], lines: ["HURT? {!C} MAKES CAMP: HEALTH AND SPELLS", "COME BACK. SOMETHING MAY FIND YOU."] },
  levelup: { ctx: "any", keys: false, focus: ["#party"], lines: ["LEVEL UP! MORE HEALTH. CASTERS MAY LEARN", "SPELLS: {C} CHOOSE MOVES IN A FIGHT."] },
  down: { ctx: "combat", focus: ["#party .dying"], lines: ["DOWN, NOT DEAD: A DEATH SAVE EACH TURN.", "HEAL THEM BEFORE THREE SAVES FAIL."] },
  talkFirst: { ctx: "combat", lines: ["MONSTERS HERE LISTEN. THIS ONE IS SHY.", "{!T} TALK TO IT. SAY SOMETHING KIND."] },
  recruitNow: { ctx: "combat", lines: ["IT HEARD YOU. NOW {!R} RECRUIT:", "ASK IT TO JOIN YOUR PARTY."] },
});

// The guided first fight: a new player's first fight is a lone shy slime, and it teaches the game's heart by
// doing it. Only one key works at each step (TALK, then RECRUIT); every other fight key waits, and pressing
// one nudges the dock instead of doing nothing. The invitation is a sure yes (the server is told `guided`).
export const GUIDE = Object.freeze({
  talk: { key: "t", hint: "talkFirst", next: "recruit", say: "YOUR FIRST FIGHT: TALK TO IT FIRST. MONSTERS HERE LISTEN" },
  recruit: { key: "r", hint: "recruitNow", next: null, say: "IT HEARD YOU. NOW ASK IT TO JOIN YOUR PARTY" },
});

export const guideAllows = (step, k) => !GUIDE[step] || GUIDE[step].key === k;

// Guided once: floor 1, tips on, and the lesson's first tip never shown (H starts tips over, and the lesson too)
export const shouldGuide = ({ floor, tipsOn, seen }) => floor === 1 && tipsOn && !seen(GUIDE.talk.hint);

// "PRESS {!T} NOW" -> [{ text: "PRESS " }, { key: "T", hot: true }, { text: " NOW" }]
export function parseLine(line) {
  const out = [];
  let last = 0;
  for (const m of line.matchAll(/\{(!?)([^}]+)\}/g)) {
    if (m.index > last) out.push({ text: line.slice(last, m.index) });
    out.push({ key: m[2], hot: m[1] === "!" });
    last = m.index + m[0].length;
  }
  if (last < line.length) out.push({ text: line.slice(last) });
  return out;
}

// CSS selectors for everything a hint should light up: its keys' buttons (anything with that data-key,
// so it follows the buttons wherever the layout puts them) and the hint's own extras.
export function focusOf(id) {
  const h = HINTS[id];
  if (!h) return [];
  const keys =
    h.keys === false
      ? []
      : h.lines
          .flatMap(parseLine)
          .filter((t) => t.key)
          .map((t) => `[data-key="${ARROWS[t.key] ?? t.key.toLowerCase()}"]`);
  return [...new Set([...keys, ...(h.focus ?? [])])];
}

const fits = (h, ctx) => GAMEPLAY.has(ctx) && (h.ctx === "any" || h.ctx === ctx);

export function createTutorial({ store, context = () => "explore", show = () => {}, hide = () => {}, nudge = () => {}, now = () => Date.now(), log = () => {} } = {}) {
  let seen = new Set();
  try {
    const saved = JSON.parse(store?.get(SEEN_KEY) ?? "[]");
    if (Array.isArray(saved)) seen = new Set(saved.filter((id) => HINTS[id]));
  } catch {}
  let on = store?.get(OFF_KEY) !== "1";
  let queue = []; // { id, wait }: wait = it was asked for elsewhere and waits for its own context
  let cur = null; // { id, wait, shownAt, reminder }
  let lastHide = -Infinity;
  let ignoredKey = false; // the game ignored the key being handled right now
  let strays = []; // times of recent ignored keys
  let lastRemind = -Infinity;

  const save = () => store?.set(SEEN_KEY, JSON.stringify([...seen]));

  function showEntry(e, reminder = false) {
    cur = { ...e, shownAt: now(), reminder };
    if (!reminder) {
      seen.add(e.id);
      save();
    }
    log(reminder ? "remind" : "show", e.id);
    show(e.id, HINTS[e.id]);
  }

  function hideCur(why) {
    if (!cur) return;
    const id = cur.id;
    log("hide", id, why);
    cur = null;
    lastHide = now();
    hide(id);
  }

  function tick() {
    const ctx = context();
    const t = now();
    if (cur && !fits(HINTS[cur.id], ctx)) {
      const entry = cur;
      const early = t - entry.shownAt < MIN_READ_MS;
      hideCur(`context ${ctx}`);
      if (early && !entry.reminder) {
        // Cut short: it gets another go, unless its moment (a fight) is simply over
        if (entry.wait || !GAMEPLAY.has(ctx)) queue.unshift({ id: entry.id, wait: entry.wait });
        else {
          seen.delete(entry.id);
          save();
        }
      }
    } else if (cur && t - cur.shownAt > TTL_MS) hideCur("timeout");
    if (!GAMEPLAY.has(ctx)) return;
    // Hints asked for in a moment that has passed (a fight that ended first) are dropped; they come back next time
    queue = queue.filter((q) => q.wait || fits(HINTS[q.id], ctx));
    if (cur || t - lastHide < GAP_MS) return;
    const i = queue.findIndex((q) => fits(HINTS[q.id], ctx));
    if (i >= 0) showEntry(queue.splice(i, 1)[0]);
  }

  function hint(id) {
    const h = HINTS[id];
    if (!h) {
      log("unknown hint", id);
      return false;
    }
    if (!on || seen.has(id) || cur?.id === id || queue.some((q) => q.id === id)) return false;
    queue.push({ id, wait: !fits(h, context()) });
    tick();
    return true;
  }

  function dismiss({ force = false } = {}) {
    if (!cur || (!force && now() - cur.shownAt < GRACE_MS)) return false;
    hideCur(force ? "dismissed" : "key");
    return true;
  }

  // After every key: clear the hint, unless the game ignored that key (then ignored() already nudged it).
  function keyed() {
    if (ignoredKey) {
      ignoredKey = false;
      return false;
    }
    return dismiss();
  }

  // The game did nothing with this key. Nudge the hint that's up; if none is and the player keeps
  // pressing keys that do nothing, bring back the reminder for where they are.
  function ignored(k) {
    if (!(String(k).length === 1 || COMMAND_KEYS.has(k))) return;
    ignoredKey = true;
    const t = now();
    if (cur) {
      log("nudge", cur.id, k);
      nudge(cur.id);
      return;
    }
    strays = [...strays.filter((s) => t - s < REMIND_WINDOW_MS), t];
    const primer = PRIMER[context()];
    if (!on || !primer || strays.length < 2 || t - lastRemind < REMIND_COOLDOWN_MS) return;
    strays = [];
    lastRemind = t;
    showEntry({ id: primer, wait: false }, true);
  }

  // A key the game holds back for a lesson (the guided first fight): keep that lesson's tip up and nudge it,
  // or bring it back if it was cleared. Never the generic reminder, which would point at the locked keys.
  function insist(id) {
    if (!HINTS[id]) return;
    ignoredKey = true;
    if (cur?.id === id) {
      log("nudge", id, "insist");
      nudge(id);
      return;
    }
    hideCur("insist");
    queue = queue.filter((q) => q.id !== id);
    showEntry({ id, wait: false }, true);
  }

  function setEnabled(value) {
    on = !!value;
    store?.set(OFF_KEY, on ? "0" : "1");
    log(on ? "tips on" : "tips off");
    if (!on) {
      queue = [];
      hideCur("tips off");
    }
  }

  function reset() {
    seen.clear();
    save();
    queue = [];
    log("reset");
  }

  // H: tips off; H again: back on from the very start (that's the reset). No menu, so nothing waits on you.
  function toggle(say = () => {}) {
    if (on) {
      setEnabled(false);
      say("TIPS OFF. PRESS H TO START THEM OVER.", "dim");
      return false;
    }
    reset();
    setEnabled(true);
    say("TIPS ON, FROM THE START. PRESS H AGAIN TO TURN THEM OFF.", "dim");
    const primer = PRIMER[context()];
    lastHide = -Infinity; // you asked for them: no pause
    if (primer) hint(primer);
    return true;
  }

  return {
    hint,
    tick,
    dismiss,
    keyed,
    ignored,
    insist,
    setEnabled,
    reset,
    toggle,
    on: () => on,
    seen: (id) => seen.has(id),
    current: () => cur?.id ?? null,
    pending: () => queue.map((q) => q.id),
  };
}

// ---------------------------------------------------------------- the box (browser only)

const escHtml = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
// A pixel arrow, pointing up; the keycap rotates it.
const ARROW_SVG = '<svg viewBox="0 0 7 7" width="8" height="8" aria-hidden="true" shape-rendering="crispEdges"><path fill="currentColor" d="M3 0h1v1h1v1h1v1h1v1H5v3H2V4H0V3h1V2h1V1h1z"/></svg>';
const ARROW_NAME = { "↑": "UP", "↓": "DOWN", "←": "LEFT", "→": "RIGHT" };

function keycap({ key, hot }) {
  const cls = `key${hot ? " hot" : ""}`;
  if (ARROWS[key]) return `<kbd class="${cls} arrow ${ARROW_NAME[key].toLowerCase()}" aria-label="${ARROW_NAME[key]}">${ARROW_SVG}</kbd>`;
  return `<kbd class="${cls}">${escHtml(key)}</kbd>`;
}

export function hintHtml(h) {
  const lines = h.lines.map((l) => `<p>${parseLine(l).map((t) => (t.key ? keycap(t) : escHtml(t.text))).join("")}</p>`).join("");
  return `<span class="tip-tag">TIP</span><span class="tip-opt"><kbd>H</kbd> TIPS</span>${lines}<span class="tip-more" aria-hidden="true"></span>`;
}

// Mounts the box over the dungeon view (inside .viewport, beside the yes/no modal) and wires the keys.
// accent(): the floor's accent color, so tips match the lit-up questions.
export function initTutorial({ store, view, context, accent = () => null, onShow = () => {} }) {
  if (typeof document === "undefined") return createTutorial({ store, context });
  let host = view.closest(".viewport");
  if (!host) {
    host = document.createElement("div");
    host.className = "viewport";
    view.replaceWith(host);
    host.append(view);
  }
  const box = document.createElement("div");
  box.id = "tip";
  box.className = "tip";
  box.hidden = true;
  box.setAttribute("role", "status");
  box.setAttribute("aria-live", "polite");
  box.title = "Click to dismiss. H turns tips off (and back on from the start).";
  host.append(box);
  // The light on the things a hint talks about. A stylesheet, so it survives the game re-rendering them.
  const focusCss = document.createElement("style");
  focusCss.dataset.tips = "focus";
  document.head.append(focusCss);
  let hideTimer = 0;

  const restart = (cls) => {
    box.classList.remove(cls);
    void box.offsetWidth;
    box.classList.add(cls);
  };

  const tips = createTutorial({
    store,
    context,
    log: (...a) => console.debug("[tips]", ...a),
    show(id, h) {
      clearTimeout(hideTimer);
      document.documentElement.style.setProperty("--tip-accent", accent() ?? "#ffb347");
      box.dataset.hint = id;
      box.innerHTML = hintHtml(h);
      box.classList.remove("out", "nudge");
      box.hidden = false;
      const sel = focusOf(id);
      focusCss.textContent = sel.length ? `${sel.join(", ")} { outline: 2px solid var(--tip-accent); outline-offset: 2px; animation: tip-focus 1.2s ease-in-out infinite; }` : "";
      onShow(id);
    },
    hide() {
      focusCss.textContent = "";
      box.classList.add("out");
      hideTimer = setTimeout(() => {
        box.hidden = true;
        box.classList.remove("out");
      }, 200);
    },
    nudge: () => restart("nudge"),
  });

  // Capture phase, deferred: the game handles the key first, so it can say it ignored it.
  document.addEventListener(
    "keydown",
    (ev) => {
      if (ev.repeat || ev.metaKey || ev.ctrlKey || ev.altKey || ev.target?.tagName === "INPUT") return;
      setTimeout(() => tips.keyed(), 0);
    },
    true,
  );
  box.addEventListener("click", (ev) => {
    ev.stopPropagation();
    tips.dismiss({ force: true });
  });
  setInterval(() => tips.tick(), 250);
  return tips;
}
