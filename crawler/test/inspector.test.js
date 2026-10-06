// The debug request inspector's summaries and copy lookups. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { summarize, requestsHtml, requestDetail, copyValue } from "../public/inspector.js";

const call = (q, tokens) => ({ state: { a: 1 }, questions: Object.fromEntries(Array.from({ length: q }, (_, i) => [`q${i}`, {}])), status: 200, ms: 120, response: { answers: { q0: { noul: 0.4 } }, usage: { input_tokens: tokens } } });
const entry = (over = {}) => ({ n: 3, path: "/api/group-turn", at: new Date(2026, 9, 5, 23, 41, 5), request: { x: "<hi>" }, status: 200, ms: 240, response: { results: [] }, jev: [call(12, 900), call(4, 300)], ...over });

test("a request is summed up by name, status, time and what Jev was asked", () => {
  assert.deepEqual(summarize(entry()), { name: "GROUP TURN", state: "ok", status: "200", ms: 240, calls: 2, questions: 16, tokens: 1200, traced: true });
});

test("failed, pending and untraced requests read as such", () => {
  assert.equal(summarize(entry({ status: 503 })).state, "bad");
  assert.equal(summarize(entry({ status: "FAILED" })).state, "bad");
  assert.equal(summarize(entry({ status: null })).state, "pending");
  const s = summarize(entry({ jev: null }));
  assert.equal(s.traced, false);
  assert.equal(s.calls, 0);
});

test("the list keeps open requests open and only builds their bodies", () => {
  const log = [entry(), entry({ n: 2 })];
  const html = requestsHtml(log, new Set([2]));
  assert.ok(html.includes('data-n="2" open'));
  assert.ok(!html.includes('data-n="3" open'));
  assert.equal((html.match(/JEV CALL 1/g) ?? []).length, 1, "only the open one has its detail built");
  assert.ok(requestsHtml([], new Set()).includes("NO REQUESTS YET"));
});

test("details escape what was sent and explain a server that sends no Jev details", () => {
  assert.ok(requestDetail(entry()).includes("&lt;hi&gt;"));
  assert.ok(requestDetail(entry({ jev: null })).includes("NO JEV DETAILS"));
});

test("copy buttons find the right piece", () => {
  const log = [entry()];
  assert.deepEqual(copyValue(log, "3:request"), { x: "<hi>" });
  assert.deepEqual(copyValue(log, "3:1:questions"), call(4, 300).questions);
  assert.deepEqual(copyValue(log, "3:0:answers"), { q0: { noul: 0.4 } });
  assert.equal(copyValue(log, "3").n, 3);
  assert.equal(copyValue(log, "9:request"), null);
});

test("JSON is colored by token kind: keys, strings, numbers, true/false/null", async () => {
  const { highlightJson } = await import("../public/inspector.js");
  const h = highlightJson({ name: "Drip <3", hp: -7, p: 0.25, ok: true, none: null, id: "e0" });
  assert.ok(h.includes('<i class="k">&quot;name&quot;</i>:'));
  assert.ok(h.includes('<i class="s">&quot;Drip &lt;3&quot;</i>'));
  assert.ok(h.includes('<i class="n">-7</i>') && h.includes('<i class="n">0.25</i>'));
  assert.ok(h.includes('<i class="b">true</i>') && h.includes('<i class="b">null</i>'));
  assert.ok(h.includes('<i class="s">&quot;e0&quot;</i>'), "digits inside strings stay part of the string");
  // Stripping the markup gives back exactly the pretty JSON
  const plain = h.replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&");
  assert.equal(plain, JSON.stringify({ name: "Drip <3", hp: -7, p: 0.25, ok: true, none: null, id: "e0" }, null, 2));
});
