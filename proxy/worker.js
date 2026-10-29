// Cloudflare Worker (donjon-api) that holds the Jev key, so no build ships it, and forwards the game's Jev requests,
// nothing else. The rules (what to ask, what the answers mean) run inside the game (src/jev/, provider "proxy").
//   POST /api/jev   { state, questions }  ->  Jev's reply, status and body untouched
// Secret (set with `npx wrangler secret put`): OPENROUTER_API_KEY (a key with a credit limit; preferred when both are
// set), or TYPESAFE_API_KEY. CI deploys it from .github/workflows/worker.yml with a token scoped to this one Worker.
// Local: `node proxy/dev.js`.

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};
// The same two front doors as the game's providers (src/jev/jev.gd); a test checks they agree.
export const UPSTREAM = {
  typesafe: { url: "https://api.typesafe.ai/v1/systemone", model: "jev-latest", headers: {} },
  openrouter: { url: "https://openrouter.ai/api/alpha/decisions", model: "~typesafe/jev-latest", headers: { "x-title": "Donjon" } },
};
// What a game request can hold. The biggest the game sends is a three-monster talk round (~75 questions, ~35 KB).
export const LIMITS = { bytes: 64_000, questions: 120, types: ["noul", "choice", "score"] };

// Outbound requests may only reach Jev's two front doors, over https, so nothing can send the key anywhere else.
// A new provider host has to be added here on purpose; a test checks every upstream is listed.
export const ALLOWED_HOSTS = new Set(["api.typesafe.ai", "openrouter.ai"]);
const nativeFetch = globalThis.fetch.bind(globalThis);
globalThis.fetch = (input, init) => {
  const { protocol, hostname } = new URL(input instanceof Request ? input.url : input);
  if (protocol !== "https:" || !ALLOWED_HOSTS.has(hostname)) {
    console.error(`Outbound request blocked: ${protocol}//${hostname}`);
    return Promise.reject(new Error(`Outbound request blocked: ${protocol}//${hostname}`));
  }
  return nativeFetch(input, init);
};

const reply = (body, status = 200, headers = {}) =>
  new Response(typeof body === "string" ? body : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS, ...headers },
  });
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

// Only the question shapes the game asks, so the key can't be spent on anything else
function validQuestions(questions) {
  const all = Object.values(questions);
  return all.length > 0 && all.length <= LIMITS.questions && all.every((q) => isObject(q) && LIMITS.types.includes(q.type) && (typeof q.instructions === "string" || isObject(q.instructions)));
}

export default {
  async fetch(request, env) {
    // Fail closed: without the key configured, answer nothing.
    const key = env.OPENROUTER_API_KEY || env.TYPESAFE_API_KEY;
    if (!key) return reply({ error: "Server not configured" }, 503);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    // Per-IP cap (LIMITER in wrangler.jsonc), so one script can't drain the key's credits. Preflights are free.
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: request.headers.get("cf-connecting-ip") ?? "unknown" });
      if (!success) {
        console.warn(`Rate limited: ${request.method} ${new URL(request.url).pathname}`);
        return reply({ error: "Too many requests to the monsters, wait a minute" }, 429, { "retry-after": "60" });
      }
    }
    if (request.method !== "POST" || new URL(request.url).pathname !== "/api/jev") return reply({ error: "Not found" }, 404);

    const raw = await request.text();
    if (raw.length > LIMITS.bytes) return reply({ error: "Request too large" }, 413);
    let body;
    try {
      body = JSON.parse(raw);
    } catch {}
    if (!isObject(body?.state) || !isObject(body?.questions) || !validQuestions(body.questions)) return reply({ error: "Bad request" }, 400);

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
    } catch (err) {
      console.error(`Jev unreachable: ${err?.message ?? err}`);
      return reply({ error: "Jev unreachable" }, 502);
    }
  },
};
