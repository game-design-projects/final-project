// Party status helpers and readable dice text: run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { hpState, condList, loyaltyState, slotGroups, classWord, facingWord, floorName, menuStep, CONDITIONS, ICONS, iconSvg } from "../public/status.js";
import { fmtRoll, diceRange, spellText, SPELLS, SPELL_TEXT } from "../public/dnd.js";

const member = (hp, maxHp, extra = {}) => ({ hp, maxHp, dead: false, down: false, ...extra });

test("health state goes healthy → hurt → critical by share of max health", () => {
  assert.equal(hpState(member(40, 40)).id, "healthy");
  assert.equal(hpState(member(30, 40)).id, "healthy");
  assert.equal(hpState(member(29, 40)).id, "hurt");
  assert.equal(hpState(member(14, 40)).id, "hurt");
  assert.equal(hpState(member(13, 40)).id, "critical");
  assert.equal(hpState(member(1, 40)).id, "critical");
});

test("down, stable and dead beat the health share, and every state has a plain word and a color", () => {
  assert.equal(hpState(member(0, 40, { down: true })).id, "dying");
  assert.equal(hpState(member(0, 40, { down: true, stable: true })).id, "stable");
  assert.equal(hpState(member(12, 40, { dead: true })).id, "dead");
  for (const s of [member(40, 40), member(20, 40), member(2, 40), member(0, 40, { down: true }), member(0, 40, { dead: true })]) {
    const st = hpState(s);
    assert.match(st.word, /^[A-Z ]+$/);
    assert.match(st.color, /^#[0-9a-f]{6}$/i);
    assert.ok(st.pct >= 0 && st.pct <= 1);
  }
});

test("a monster at 0 HP that is not flagged down still reads as down, never as negative health", () => {
  const st = hpState({ hp: -5, maxHp: 20 });
  assert.equal(st.pct, 0);
});

test("conditions come out as plain words with colors, in a stable order, unknown keys dropped", () => {
  const list = condList({ prone: 1, poisoned: 2, nonsense: 3, asleep: 4 });
  assert.deepEqual(list.map((c) => c.word), ["ASLEEP", "POISONED", "KNOCKED DOWN"]);
  for (const c of list) {
    assert.match(c.color, /^#[0-9a-f]{6}$/i);
    assert.ok(c.tip.length > 10);
  }
  assert.deepEqual(condList(undefined), []);
  assert.equal(condList({ held: 1, asleep: 1, lit: 1 }, 2).length, 2);
});

test("no condition word is a cryptic tag", () => {
  for (const c of Object.values(CONDITIONS)) assert.ok(!["ZZZ", "SAD", "BOUND", "POISON", "HELD", "PRONE"].includes(c.word), c.word);
});

test("loyalty reads as a word that gets more urgent as it drops", () => {
  assert.equal(loyaltyState(90).word, "DEVOTED");
  assert.equal(loyaltyState(60).word, "CONTENT");
  assert.equal(loyaltyState(35).word, "UNEASY");
  assert.equal(loyaltyState(20).word, "RESENTFUL");
  assert.equal(loyaltyState(5).word, "MAY LEAVE");
});

test("spell slots become pip groups, one per circle, filled for what is left", () => {
  const g = slotGroups([3, 0, 2], [4, 3, 2]);
  assert.deepEqual(
    g.map((x) => [x.circle, x.left, x.max]),
    [
      [1, 3, 4],
      [2, 0, 3],
      [3, 2, 2],
    ],
  );
  assert.deepEqual(g[0].pips, [true, true, true, false]);
  assert.ok(g.every((x) => /^#[0-9a-f]{6}$/i.test(x.color)));
  assert.notEqual(g[0].color, g[1].color);
  assert.deepEqual(slotGroups(undefined, undefined), []);
});

test("class words are spelled out, and facing and floor are words", () => {
  assert.equal(classWord({ kind: "human", clsId: "fighter" }), "FIGHTER");
  assert.equal(classWord({ kind: "monster", species: "goblin" }), "GOBLIN");
  assert.equal(classWord({ kind: "monster", species: "snake" }), "SNAKE PERSON");
  assert.equal(facingWord(0), "NORTH");
  assert.equal(facingWord(3), "WEST");
  assert.equal(floorName(5), "FLOOR 5");
});

test("roll text says what was rolled, with advantage in words, and the total", () => {
  assert.equal(fmtRoll({ roll: 14, rolls: [14], adv: 0 }, 5), "ROLLED 14 +5 = 19");
  assert.equal(fmtRoll({ roll: 16, rolls: [13, 16], adv: 1 }, 5), "ROLLED 16 (ADVANTAGE) +5 = 21");
  assert.equal(fmtRoll({ roll: 7, rolls: [7, 15], adv: -1 }, -1), "ROLLED 7 (DISADVANTAGE) -1 = 6");
  assert.equal(fmtRoll({ roll: 9, rolls: [9], adv: 0 }, 0), "ROLLED 9");
  assert.ok(!/D20|ADV→|DIS→/.test(fmtRoll({ roll: 3, rolls: [3, 2], adv: 1 }, 2)));
});

test("dice ranges replace dice notation", () => {
  assert.equal(diceRange("1d10"), "1-10");
  assert.equal(diceRange("8d6"), "8-48");
  assert.equal(diceRange("1d4+1"), "2-5");
  assert.equal(diceRange("2d4-1"), "1-7");
});

test("every spell description is free of dice notation and stat abbreviations, and cantrips grow", () => {
  for (const k of Object.keys(SPELLS)) {
    const t = spellText(k, 1);
    assert.ok(t.length > 5, k);
    assert.ok(!/\b\d*D\d+\b|\{|\b(DEX|WIS|STR|CON|INT|CHA|HP|AC|DC)\b/.test(t), `${k}: ${t}`);
  }
  assert.match(spellText("fire_bolt", 1), /1-10/);
  assert.match(spellText("fire_bolt", 5), /2-20/);
  assert.equal(Object.keys(SPELL_TEXT).sort().join(), Object.keys(SPELLS).sort().join());
});

test("every icon is a 7x7 bitmap, and every condition has one", () => {
  for (const [name, rows] of Object.entries(ICONS)) {
    assert.equal(rows.length, 7, name);
    for (const r of rows) assert.match(r, /^[.#]{7}$/, name);
  }
  for (const [k, c] of Object.entries(CONDITIONS)) assert.ok(ICONS[c.icon], `${k} has no icon`);
});

test("an icon renders as one crisp SVG path in its color, and unknown names fall back to a dot", () => {
  const svg = iconSvg("heart", "#ff0000");
  assert.match(svg, /^<svg [^>]*viewBox="0 0 7 7"[^>]*crispEdges/);
  assert.match(svg, /fill="#ff0000"/);
  assert.equal((svg.match(/h1v1h-1z/g) ?? []).length, ICONS.heart.join("").split("#").length - 1);
  assert.equal(iconSvg("nope"), iconSvg("dot"));
});

test("menu highlight wraps around both ways", () => {
  assert.equal(menuStep(0, -1, 5), 4);
  assert.equal(menuStep(4, 1, 5), 0);
  assert.equal(menuStep(2, 1, 5), 3);
  assert.equal(menuStep(undefined, 1, 3), 0);
});

import { PARTY_MAX, allyRoom } from "../public/status.js";

test("the party holds six: allies get whatever seats the adventurers leave", () => {
  const h = (dead = false) => ({ kind: "human", dead });
  const a = () => ({ kind: "monster" });
  assert.equal(PARTY_MAX, 6);
  assert.deepEqual(allyRoom([h(), h(), h()]), { allies: 0, max: 3, full: false });
  assert.deepEqual(allyRoom([h(), h(), h(), a(), a()]), { allies: 2, max: 3, full: false });
  assert.deepEqual(allyRoom([h(), h(), h(), a(), a(), a()]), { allies: 3, max: 3, full: true });
  assert.deepEqual(allyRoom([h(), h(true), h(), a()]), { allies: 1, max: 3, full: false }, "a fallen adventurer keeps their seat");
});
