// Game feel, kept apart from the rules: screen shake, hit-stop, the party's danger level, and the event bus
// that carries combat moments from the game's logic to whatever shows or sounds them (game.js wires it).
// Everything here is pure or takes the clock as an argument, so it can be tested without a browser.

// ---------------------------------------------------------------- the event bus
// Every event the presentation listens to, with the fields its payload must carry. emit() refuses an unknown
// event or a missing field, so a typo in game.js fails loudly instead of silently skipping an effect.
export const FX_EVENTS = {
  "party:hurt": ["dmg", "hp", "maxHp"], // an adventurer or ally took damage
  "party:down": [], // someone fell unconscious
  "enemy:hit": ["dmg", "maxHp", "crit"], // a monster took damage
  "enemy:kill": ["boss"], // a monster fell
  "view:step": ["dir"], // you moved: dir 1 forward, -1 back
  "view:turn": ["dir"], // you turned: dir -1 left, 1 right
  "view:bump": [], // you walked into a wall
  "combat:start": ["boss"],
  "combat:end": ["won"],
};

export function createBus(catalog = FX_EVENTS) {
  const subs = new Map();
  return {
    on(name, fn) {
      if (!catalog[name]) throw new Error(`fx: no such event "${name}"`);
      if (!subs.has(name)) subs.set(name, new Set());
      subs.get(name).add(fn);
      return () => subs.get(name).delete(fn);
    },
    emit(name, payload = {}) {
      const fields = catalog[name];
      if (!fields) throw new Error(`fx: no such event "${name}"`);
      const missing = fields.filter((f) => payload[f] === undefined);
      if (missing.length) throw new Error(`fx: "${name}" needs ${missing.join(", ")}`);
      for (const fn of subs.get(name) ?? []) {
        try {
          fn(payload);
        } catch (err) {
          console.warn(`fx: ${name} listener failed`, err); // a broken effect never breaks the game
        }
      }
    },
  };
}

// ---------------------------------------------------------------- screen shake
// Trauma-based shake: hits add trauma (0..1), it drains at a steady rate, and the offset grows with its square,
// so small hits barely nudge and big ones really rattle. The motion is smooth noise (sums of sines with odd
// frequencies), not a new random jump every frame. A kick can be dated in the future (`at`), to land with a die.
export const SHAKE = { maxPx: 10, drainPerSec: 1.8 };

export class Shake {
  constructor({ maxPx = SHAKE.maxPx, drainPerSec = SHAKE.drainPerSec, seed = 0 } = {}) {
    this.maxPx = maxPx;
    this.drain = drainPerSec;
    this.seed = seed;
    this.trauma = 0;
    this.last = null;
    this.pending = [];
  }

  add(amount, at) {
    if (at !== undefined && this.last !== null && at > this.last) this.pending.push({ amount, at });
    else this.trauma = Math.min(1, this.trauma + amount);
  }

  // Advance to `now` (ms) and return the [dx, dy] offset in pixels.
  offset(now) {
    if (this.last !== null) this.trauma = Math.max(0, this.trauma - (this.drain * (now - this.last)) / 1000);
    this.last = now;
    if (this.pending.length) {
      const due = this.pending.filter((p) => p.at <= now);
      this.pending = this.pending.filter((p) => p.at > now);
      for (const p of due) this.trauma = Math.min(1, this.trauma + p.amount);
    }
    if (this.trauma <= 0) return [0, 0];
    const k = this.maxPx * this.trauma * this.trauma;
    const s = now / 1000 + this.seed;
    const n = (a, b, c) => (Math.sin(s * a) + Math.sin(s * b) * 0.6 + Math.sin(s * c) * 0.3) / 1.9;
    return [k * n(41, 67, 103), k * n(53, 79, 97)];
  }
}

// How much trauma each moment adds. Party damage scales with how much of the victim's health it took.
export function traumaFor(name, p = {}) {
  switch (name) {
    case "party:hurt":
      return 0.28 + 0.5 * Math.min(1, p.dmg / Math.max(1, p.maxHp));
    case "party:down":
      return 0.55;
    case "enemy:hit":
      return p.crit ? 0.4 : 0.12 + 0.18 * Math.min(1, p.dmg / Math.max(1, p.maxHp));
    case "enemy:kill":
      return p.boss ? 0.75 : 0.3;
    case "view:bump":
      return 0.16;
    default:
      return 0;
  }
}

// ---------------------------------------------------------------- hit-stop
// A big hit freezes the monsters' animation for a few frames, so the blow reads. clock(now) is the
// animation time: it stands still during a freeze and then carries on without jumping ahead.
export const HITSTOP_MS = { crit: 90, kill: 70, bossKill: 160, down: 110 };

export class HitStop {
  constructor() {
    this.lost = 0; // ms the clock has stood still in total
    this.from = 0;
    this.until = 0;
  }

  freeze(now, ms) {
    if (now >= this.until) {
      this.settle(now);
      this.from = now;
    }
    this.until = Math.max(this.until, now + ms);
  }

  settle(now) {
    if (this.until > this.from && now >= this.until) {
      this.lost += this.until - this.from;
      this.from = this.until;
    }
  }

  clock(now) {
    if (now < this.until && now >= this.from) return this.from - this.lost;
    this.settle(now);
    return now - this.lost;
  }
}

// ---------------------------------------------------------------- danger
// How close the party is to falling, 0 (fine) to 1 (about to wipe): from the share of health left among the
// living, and from anyone lying unconscious and rolling death saves. Drives the music's low-pass, the
// heartbeat and the red edge of the view.
export function dangerOf(party) {
  const living = party.filter((m) => !m.dead);
  if (!living.length) return 1;
  const hp = living.reduce((a, m) => a + Math.max(0, m.hp), 0);
  const max = living.reduce((a, m) => a + m.maxHp, 0);
  const frac = max ? hp / max : 0;
  const fromHealth = Math.min(1, Math.max(0, (0.5 - frac) / 0.35)); // 0 at half health, 1 at 15%
  const dying = living.filter((m) => m.down && !m.stable).length;
  const fromDying = dying ? Math.min(1, 0.6 + 0.2 * (dying - 1)) : 0;
  return Math.max(fromHealth, fromDying);
}

// Ease a value toward its target, frame-rate independent: `halfLife` ms to close half the gap.
export const approach = (value, target, dtMs, halfLife = 250) => target + (value - target) * 0.5 ** (dtMs / halfLife);

// ---------------------------------------------------------------- view transitions
// Moving and turning ease between the old view and the new one: a step dollies (the old frame grows past you
// as it fades), a turn pans. Returns how to draw the old frame at time `now`, or null once it is done.
export const TRANSITION_MS = { step: 150, turn: 170, bump: 140 };
const easeOut = (x) => 1 - (1 - x) ** 3;

export function transitionAt(tr, now) {
  if (!tr) return null;
  const p = (now - tr.t0) / TRANSITION_MS[tr.kind];
  if (p >= 1 || p < 0) return null;
  const e = easeOut(p);
  if (tr.kind === "step") return { kind: "step", scale: tr.dir > 0 ? 1 + 0.45 * e : 1 - 0.3 * e, alpha: 1 - e, shift: 0, p };
  if (tr.kind === "turn") return { kind: "turn", scale: 1, alpha: 1, shift: -tr.dir * e, p }; // shift in view widths
  // bump: the view lunges a little toward the wall and springs back
  return { kind: "bump", scale: 1 + 0.06 * Math.sin(Math.PI * p), alpha: 0, shift: 0, p };
}
