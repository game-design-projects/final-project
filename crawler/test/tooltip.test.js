// Pixel tooltips: how a title's text is laid out. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { tipModel, tipHtml } from "../public/tooltip.js";

test("each ' · ' part of a title gets its own line", () => {
  assert.deepEqual(tipModel("LEVEL 2 · EXPERIENCE 57 OF 91 TO THE NEXT LEVEL · DAMAGE X1.00").lines, [
    "LEVEL 2",
    "EXPERIENCE 57 OF 91 TO THE NEXT LEVEL",
    "DAMAGE X1.00",
  ]);
});

test("a run of ability scores becomes a table, in order, with signs as numbers", () => {
  const m = tipModel("LEVEL 2 · STRENGTH -1 DEXTERITY +2 CONSTITUTION +1 INTELLIGENCE +3 WISDOM +1 CHARISMA +1 · WILL CHEAT DEATH ONCE");
  assert.deepEqual(m.lines, ["LEVEL 2", "WILL CHEAT DEATH ONCE"]);
  assert.deepEqual(m.stats, [["STRENGTH", -1], ["DEXTERITY", 2], ["CONSTITUTION", 1], ["INTELLIGENCE", 3], ["WISDOM", 1], ["CHARISMA", 1]]);
});

test("a sentence that merely mentions an ability stays a line", () => {
  const m = tipModel("ROLL 12+ ON STRENGTH +2 TO TAKE HALF");
  assert.deepEqual(m.stats, []);
  assert.equal(m.lines.length, 1);
});

test("plain titles and empty input", () => {
  assert.deepEqual(tipModel("ARMOR 16"), { lines: ["ARMOR 16"], stats: [] });
  assert.deepEqual(tipModel(""), { lines: [], stats: [] });
  assert.deepEqual(tipModel(undefined), { lines: [], stats: [] });
});

test("html escapes text, marks the first of several lines as the heading, colors stat signs", () => {
  const h = tipHtml(tipModel("<B> · DEXTERITY +2 WISDOM -1 · C"));
  assert.ok(h.includes("&lt;B&gt;"));
  assert.ok(h.includes('class="head"'));
  assert.ok(h.includes('class="up">+2') && h.includes('class="down">-1'));
});
