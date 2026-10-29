// Cloudflare Worker for the web build: holds the Jev key so it never ships in the game, and forwards the game's
// Jev requests, nothing else. The rules (what to ask, what the answers mean) run inside the game.
//   POST /api/jev   { state, questions }  ->  Jev's reply, status and body untouched
// Secret (set with `npx wrangler secret put`): TYPESAFE_API_KEY, or OPENROUTER_API_KEY to reach Jev via OpenRouter
// (preferred when both are set). Local: `node proxy/dev.js`. The game side is src/jev/jev.gd, provider "proxy".

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};
const UPSTREAM = {
  typesafe: { url: "https://api.typesafe.ai/v1/systemone", model: "jev-latest", headers: {} },
  openrouter: { url: "https://openrouter.ai/api/alpha/decisions", model: "~typesafe/jev-latest", headers: { "x-title": "Donjon" } },
};

const reply = (body, status = 200) =>
  new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS } });
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (request.method !== "POST" || new URL(request.url).pathname !== "/api/jev") return reply({ error: "Not found" }, 404);
    // Fail closed: without a key configured, answer nothing.
    const key = env.OPENROUTER_API_KEY || env.TYPESAFE_API_KEY;
    if (!key) return reply({ error: "Server not configured" }, 503);

    const raw = await request.text();
    if (raw.length > 64_000) return reply({ error: "Request too large" }, 413);
    let body;
    try {
      body = JSON.parse(raw);
    } catch {}
    if (!isObject(body?.state) || !isObject(body?.questions)) return reply({ error: "Bad request" }, 400);

    // The model is pinned here, whatever the client sent: it spends this Worker's key
    const up = env.OPENROUTER_API_KEY ? UPSTREAM.openrouter : UPSTREAM.typesafe;
    try {
      const res = await fetch(up.url, {
        method: "POST",
        headers: { authorization: `Bearer ${key}`, "content-type": "application/json", ...up.headers },
        body: JSON.stringify({ model: up.model, state: body.state, questions: body.questions }),
        signal: AbortSignal.timeout(10_000),
      });
      // Status and body pass through, so the game sees the 429/529 it backs off on and the errors it reports
      return reply(await res.text(), res.status);
    } catch {
      return reply({ error: "Jev unreachable" }, 502);
    }
  },
};
