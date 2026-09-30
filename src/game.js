// Turn orchestration: apply the player's action with plain rules, then give Jimbo his turn.

import { decide, makeOffer, clampMeters, remember } from "./brain.js";
import { ITEMS, MAP, SIGHT, HEARING, dist, has, movePlayer, guardPatrol, openGate, roll, newWorld } from "./world.js";

export function newGame() {
  const w = newWorld();
  w.log.push({
    kind: "story",
    text: "Dusk at the south gate of Ashvale. Captain Jimbo stands watch. Find a way into the city.",
  });
  return w;
}

function endingFor(w) {
  if (w.guard.yielded)
    return ["Forced your way in", "You step past the dropped sword and into Ashvale. Not your proudest entrance."];
  if (w.tollPaid) return ["Paid your way in", "Ten gold lighter, you walk into Ashvale's lantern-lit streets."];
  if (w.writ === "accepted")
    return ["Entered as Tomas Reed", "The Harbor Office seal carries you through. Best not run into the real Tomas."];
  return ["Talked your way in", "No toll, no papers. Just a guard who decided he liked you."];
}

function applyPlayerAction(w, action) {
  const { player: p, guard: g } = w;
  const turn = w.turn + 1;
  const events = [];
  let message = null;
  const near = dist(p, g) <= 2;

  switch (action?.type) {
    case "move": {
      const before = dist(p, g);
      const r = movePlayer(w, action.dir);
      if (!r.ok) return { ok: false, notice: r.notice };
      const after = dist(p, g);
      events.push(after < before ? "The traveler stepped closer." : after > before ? "The traveler stepped away." : "The traveler moved.");
      if (r.picked) {
        const it = ITEMS[r.picked];
        w.log.push({ kind: "event", text: it.gold ? `You find ${it.gold} gold in a ${it.name}.` : `You pick up the ${it.name}.` });
        events.push(`The traveler picked up a ${it.name} from the ground.`);
      }
      if (p.y <= 1) {
        const [title, text] = endingFor(w);
        w.over = { kind: "win", title, text };
      }
      break;
    }
    case "say": {
      const text = String(action.text ?? "").replace(/\s+/g, " ").trim().slice(0, 280);
      if (!text) return { ok: false, notice: "Type something to say." };
      w.log.push({ kind: "player", text });
      if (dist(p, g) <= HEARING && !g.yielded) {
        message = text;
        events.push("The traveler spoke to you.");
      } else {
        w.log.push({ kind: "note", text: "Jimbo is too far away to hear you." });
      }
      break;
    }
    case "wait":
      events.push("The traveler waited.");
      break;
    case "sword": {
      if (!has(w, "sword")) return { ok: false, notice: "You don't have a sword." };
      p.swordDrawn = !p.swordDrawn;
      events.push(p.swordDrawn ? "The traveler drew a rusty sword." : "The traveler sheathed their sword.");
      w.log.push({ kind: "event", text: p.swordDrawn ? "You draw the rusty sword." : "You sheathe the sword." });
      break;
    }
    case "attack": {
      if (g.yielded) return { ok: false, notice: "He has already yielded." };
      if (dist(p, g) > 1) return { ok: false, notice: "Jimbo is out of reach." };
      const armed = has(w, "sword");
      if (armed) p.swordDrawn = true;
      const dmg = armed ? roll(3, 5) : 1;
      g.hp = Math.max(0, g.hp - dmg);
      p.lastAttackTurn = turn;
      g.anger += 60;
      g.suspicion += 25;
      g.trust -= 40;
      clampMeters(g);
      remember(g, "The traveler attacked you!");
      events.push(armed ? `The traveler attacked you with a sword (you lost ${dmg} health).` : "The traveler punched you.");
      w.log.push({ kind: "combat", text: armed ? `You slash at Jimbo for ${dmg}.` : "You punch Jimbo. It barely registers." });
      if (g.hp <= 4) {
        g.yielded = true;
        openGate(w);
        w.log.push({ kind: "npc", text: "*staggers back and drops his sword* Enough! Go on, then. Take the gate." });
        w.log.push({ kind: "event", text: "Jimbo yields. The gate is open." });
      }
      break;
    }
    case "offer": {
      const item = action.item;
      const owned = item === "gold" ? p.gold > 0 : ["flowers", "ring"].includes(item) && has(w, item);
      if (!owned) return { ok: false, notice: "You don't have that to offer." };
      if (!near) return { ok: false, notice: "Get closer to hand him something." };
      w.pendingOffer = makeOffer(w, item);
      events.push(`The traveler is holding out ${w.pendingOffer.label} for you to take.`);
      w.log.push({ kind: "event", text: `You hold out the ${w.pendingOffer.label}.` });
      break;
    }
    case "show_writ": {
      if (!has(w, "writ")) return { ok: false, notice: "You don't have any papers." };
      if (!near) return { ok: false, notice: "Get closer to show him the writ." };
      if (w.writ === "none") w.writ = "presented";
      events.push("The traveler showed you a travel writ.");
      w.log.push({ kind: "event", text: "You show Jimbo the travel writ." });
      break;
    }
    default:
      return { ok: false, notice: "Unknown action." };
  }
  w.turn = turn;
  return { ok: true, message, events };
}

async function guardTurn(w, r) {
  const { player: p, guard: g } = w;
  if (g.yielded) return { called: false, reason: "Jimbo has yielded; he won't stop you." };

  const d = dist(p, g);
  if (d > SIGHT && !r.message && w.alarm === null) {
    guardPatrol(w);
    return {
      called: false,
      reason: `Jimbo can't see you (${d} steps away; he notices within ${SIGHT}). Plain code walks his patrol, no Jev call needed.`,
    };
  }

  // Deterministic pressure that doesn't need judgment: tempers cool, a drawn blade nearby doesn't.
  g.anger -= 3;
  g.suspicion -= 1;
  if (p.swordDrawn && d <= 3) {
    g.anger += 4;
    g.suspicion += 8;
    remember(g, "The traveler is brandishing a sword near you.");
  }
  clampMeters(g);

  return decide(w, { message: r.message, events: r.events });
}

export async function takeTurn(w, action) {
  if (w.over) return { notice: "This game is over. Start a new one." };
  const r = applyPlayerAction(w, action);
  if (!r.ok) return { notice: r.notice };
  if (w.over) return { trace: { called: false, reason: "The game is over." } };

  const trace = await guardTurn(w, r);

  if (w.alarm !== null && !w.over && !w.gateOpen) {
    w.alarm -= 1;
    if (w.alarm <= 0) {
      w.over = { kind: "lose", title: "The watch arrived", text: "A dozen guards pour out of the gatehouse. You won't be entering Ashvale today." };
    } else {
      w.log.push({ kind: "note", text: `The alarm bell is ringing. The watch arrives in ${w.alarm} turn${w.alarm === 1 ? "" : "s"}.` });
    }
  }
  return { trace };
}

export function view(w) {
  const { player: p, guard: g } = w;
  return {
    map: MAP,
    turn: w.turn,
    gateOpen: w.gateOpen,
    tollPaid: w.tollPaid,
    writ: w.writ,
    alarm: w.alarm,
    over: w.over,
    player: {
      x: p.x,
      y: p.y,
      hp: p.hp,
      maxHp: p.maxHp,
      gold: p.gold,
      swordDrawn: p.swordDrawn,
      inventory: p.inventory.map((id) => ({ id, name: ITEMS[id].name, emoji: ITEMS[id].emoji, desc: ITEMS[id].desc })),
    },
    guard: {
      x: g.x,
      y: g.y,
      hp: g.hp,
      maxHp: g.maxHp,
      trust: g.trust,
      suspicion: g.suspicion,
      anger: g.anger,
      yielded: g.yielded,
      impressions: g.impressions,
      sight: SIGHT,
      hearing: HEARING,
    },
    ground: w.ground.map((it) => ({ ...it, emoji: ITEMS[it.id].emoji, name: ITEMS[it.id].name })),
    log: w.log.slice(-80),
  };
}
