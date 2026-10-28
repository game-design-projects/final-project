// Genre Halls (genre-halls.html), the Undertale-style encounter mode: its rules, with no DOM. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { SPECIES } from "../public/species.js";
import { EMOTIONS } from "../public/emotions.js";
import { DIRS } from "../public/render.js";
import {
  GENRES, ACTS, AFF, POS, NEG, GIBBERISH_NEG, APPROVE, CHARMS, ROSTER, BOSS, INTENT_WORDS,
  genFloor, rollOdds, softmax, askFeeling, askMercy, askPressure, readWords, gibberishOdds,
  COLS, ROWS, idx, inBox, rookCells, bishopCells, knightCells, STOMPS, PILLARS, lanternAt, shaded,
} from "../public/genre-rules.js";

const ALL = COLS * ROWS;
const KINDS = [...ROSTER.map((r) => r.species), BOSS.species];
const monster = (species, meters = {}) => ({
  species, hp: 20, maxHp: 20, threshold: SPECIES[species].joinThreshold, taste: {},
  meters: { friendliness: 40, anger: 20, fear: 10, ...meters },
});

test("every faction has its genre, acts, tastes, charm and values, and every feeling named exists", () => {
  for (const r of ROSTER) assert.ok(GENRES[r.genre], r.genre);
  for (const g of BOSS.genres) assert.ok(GENRES[g], g);
  for (const s of KINDS) {
    assert.ok(SPECIES[s], s);
    assert.ok(SPECIES[s].lines?.converse?.length && SPECIES[s].lines?.attack?.length, `${s} lines`);
    assert.ok(CHARMS[s] && APPROVE[s] && GIBBERISH_NEG[s], s);
    for (const a of ACTS[s]) assert.ok(a.intent in AFF[s], `${s}: ${a.intent}`);
  }
  for (const intent of Object.keys(AFF.slime)) assert.ok(INTENT_WORDS[intent], intent);
  const named = [...Object.values(POS), ...Object.values(NEG), ...Object.values(GIBBERISH_NEG)].flat();
  for (const f of named) assert.ok(EMOTIONS[f], f);
});

test("a floor puts the stairs and every monster within reach, apart, and the champion in its hall", () => {
  for (let run = 0; run < 200; run++) {
    const map = genFloor();
    const reach = new Set(["1,1"]);
    const q = [[1, 1]];
    while (q.length) {
      const [x, y] = q.shift();
      for (const [dx, dy] of DIRS) {
        const k = `${x + dx},${y + dy}`;
        if (map.grid[y + dy]?.[x + dx] === 1 && !reach.has(k)) reach.add(k) && q.push([x + dx, y + dy]);
      }
    }
    assert.ok(reach.has(`${map.stairs.x},${map.stairs.y}`), "stairs reachable");
    assert.equal(map.monsters.length, ROSTER.length + 1);
    const at = new Set(map.monsters.map((m) => `${m.x},${m.y}`));
    assert.equal(at.size, map.monsters.length, "one monster per cell");
    assert.ok(!at.has("1,1") && !at.has(`${map.stairs.x},${map.stairs.y}`), "nobody on the start or the stairs");
    for (const m of map.monsters) assert.ok(reach.has(`${m.x},${m.y}`), `${m.species} reachable`);
    const boss = map.monsters.find((m) => m.boss);
    const c = Math.floor(map.n / 2);
    assert.deepEqual([boss.x, boss.y, boss.species], [c, c, BOSS.species]);
    for (const m of map.monsters.filter((m) => !m.boss)) assert.ok(Math.max(Math.abs(m.x - c), Math.abs(m.y - c)) > 2, "outside the hall");
  }
});

test("rollOdds only picks answers at 15% or more, falling back to the likeliest", () => {
  for (let i = 0; i < 300; i++) {
    const p = softmax({ a: Math.random() * 4, b: Math.random() * 4, c: Math.random() * 4, d: -3 });
    assert.ok(p[rollOdds(p)] >= 0.15);
  }
  assert.equal(rollOdds({ a: 0.1, b: 0.12, c: 0.14 }), "c");
});

test("a feeling is a full distribution over the ten feelings, for deeds and for words", () => {
  for (const act of ["fight", [{ intent: "joke", w: 1 }], [{ intent: "insult", w: 0.6 }, { intent: "gibberish", w: 0.4 }]]) {
    const a = askFeeling(monster("slime"), act);
    assert.equal(a.type, "choice");
    assert.deepEqual(Object.keys(a.probabilities).sort(), Object.keys(EMOTIONS).sort());
    assert.ok(Math.abs(Object.values(a.probabilities).reduce((s, p) => s + p, 0) - 1) < 1e-9);
    assert.ok(EMOTIONS[a.choice]);
  }
  // A slime loves a joke and hates an insult
  const joke = askFeeling(monster("slime"), [{ intent: "joke", w: 1 }]).probabilities;
  const insult = askFeeling(monster("slime"), [{ intent: "insult", w: 1 }]).probabilities;
  assert.ok(joke.amused + joke.delighted > insult.amused + insult.delighted);
  assert.ok(insult.offended + insult.enraged > joke.offended + joke.enraged);
});

test("mercy grows with friendliness and shrinks with anger; pressure is a 0-3 level", () => {
  const mercy = (meters) => askMercy(monster("rock", meters)).noul;
  assert.ok(mercy({ friendliness: 80 }) > mercy({ friendliness: 40 }));
  assert.ok(mercy({ anger: 80 }) < mercy({ anger: 10 }));
  for (const meters of [{ anger: 0, friendliness: 100 }, { anger: 100, friendliness: 0 }, {}]) {
    const p = askPressure(monster("dragon", meters));
    assert.ok(p.score >= 0 && p.score <= 3);
    assert.ok(Math.abs(Object.values(p.probabilities).reduce((s, x) => s + x, 0) - 1) < 1e-9);
  }
  assert.ok(askPressure(monster("dragon", { anger: 100, friendliness: 0 })).score > askPressure(monster("dragon", { anger: 0, friendliness: 100 })).score);
});

test("typed words are read by intent, and a keyboard mash is nonsense", () => {
  assert.equal(readWords("you are so beautiful and strong").choice, "flattery");
  assert.equal(readWords("I can offer gold, a fair share of the loot").choice, "gold");
  assert.equal(readWords("where are the stairs?").choice, "question");
  assert.equal(readWords("asdfgh qwrtzp").choice, "gibberish");
  assert.ok(gibberishOdds("hello friend") < 0.2);
  const p = readWords("knock knock, a joke for you").probabilities;
  assert.ok(Math.abs(Object.values(p).reduce((s, x) => s + x, 0) - 1) < 1e-9);
});

test("every chess piece and every stomp leaves a safe square, wherever you stand", () => {
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++) {
      const o = { c, r };
      for (const cells of [rookCells(o), bishopCells(o), knightCells(o)]) {
        assert.ok(cells.every((k) => k >= 0 && k < ALL), "inside the box");
        assert.ok(new Set(cells).size < ALL);
      }
      STOMPS.forEach((stomp, i) => assert.ok(new Set(stomp(o)).size < ALL, `stomp ${i}`));
    }
  // Pieces hit what they should: a rook its row and column, a knight its L-jumps and its own square
  assert.equal(new Set(rookCells({ c: 0, r: 3 })).size, COLS + ROWS - 1);
  assert.ok(knightCells({ c: 3, r: 3 }).includes(idx(4, 5)) && knightCells({ c: 3, r: 3 }).includes(idx(3, 3)));
  assert.ok(bishopCells({ c: 0, r: 0 }).includes(idx(6, 6)));
  assert.ok(!inBox(-1, 0) && !inBox(COLS, 0) && inBox(0, ROWS - 1));
});

test("wherever the lantern swings, some pillar's shadow is there to hide in", () => {
  const blocked = new Set(PILLARS);
  for (const intensity of [0.8, 1, 1.4, 1.8])
    for (let ms = 0; ms <= 8000; ms += 40) {
      const L = lanternAt(ms, intensity);
      let hide = 0;
      for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) if (!blocked.has(idx(c, r)) && shaded(L, c, r, blocked)) hide++;
      assert.ok(hide > 0, `no shadow at ${ms} ms, intensity ${intensity}`);
    }
});
