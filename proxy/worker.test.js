// The Worker end to end with a stubbed upstream (no key, no network, no credits). Run with `node --test proxy/worker.test.js`.
import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker from "./worker.js";

const realFetch = globalThis.fetch;
let upstream;
beforeEach(() => {
  upstream = { calls: [], reply: () => new Response(JSON.stringify({ model: "jev-latest", answers: {}, usage: { input_tokens: 1 } }), { status: 200 }) };
  globalThis.fetch = async (url, init) => {
    upstream.calls.push({ url, init, body: JSON.parse(init.body) });
    return upstream.reply();
  };
});
afterEach(() => (globalThis.fetch = realFetch));

const post = (body, { path = "/api/jev", env = { TYPESAFE_API_KEY: "ts-secret" }, method = "POST" } = {}) =>
  worker.fetch(new Request(`http://local${path}`, { method, body: method === "POST" ? (typeof body === "string" ? body : JSON.stringify(body)) : undefined }), env);
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
  const pre = await worker.fetch(new Request("http://local/api/jev", { method: "OPTIONS" }), {});
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

test("fails closed without a key", async () => {
  const res = await post(GOOD, { env: {} });
  assert.equal(res.status, 503);
  assert.equal(upstream.calls.length, 0);
});

test("refuses requests over 64 KB and ones that are not {state, questions}", async () => {
  assert.equal((await post({ ...GOOD, padding: "x".repeat(70_000) })).status, 413);
  assert.equal((await post("not json")).status, 400);
  assert.equal((await post({ state: {}, questions: [] })).status, 400);
  assert.equal((await post({ state: "x", questions: {} })).status, 400);
  assert.equal((await post({})).status, 400);
  assert.equal(upstream.calls.length, 0);
});

test("an unreachable upstream is a 502, and the key never shows", async () => {
  globalThis.fetch = async () => {
    throw new Error("boom ts-secret");
  };
  const res = await post(GOOD);
  assert.equal(res.status, 502);
  assert.ok(!(await res.text()).includes("ts-secret"));
});
