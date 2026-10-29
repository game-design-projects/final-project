// Cloudflare Worker (donjon-api) that answers the game's /api/* calls and holds the Jev key, so no build ships it.
// Secret (set with `npx wrangler secret put`): OPENROUTER_API_KEY (a key with a credit limit), or TYPESAFE_API_KEY.
// CI deploys it from .github/workflows/worker.yml with a token scoped to this one Worker (crawler/README.md).
import { handleApi } from "../src/api.js";

// Outbound requests may only reach Jev's two front doors (PROVIDERS in crawler/src/jev.js), over https, so no
// code in the game can send the key anywhere else. A new provider host has to be added here on purpose; a test
// checks every provider is listed.
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

const refuse = (status, error, headers = {}) =>
  new Response(JSON.stringify({ error }), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", "access-control-allow-origin": "*", ...headers },
  });

export default {
  async fetch(request, env) {
    // Fail closed: without the key configured, answer nothing.
    if (!env.TYPESAFE_API_KEY && !env.OPENROUTER_API_KEY) return refuse(503, "Server not configured");
    // Per-IP cap (LIMITER in wrangler.jsonc), so one script can't drain the key's credits. Preflights are free.
    if (env.LIMITER && request.method !== "OPTIONS") {
      const { success } = await env.LIMITER.limit({ key: request.headers.get("cf-connecting-ip") ?? "unknown" });
      if (!success) {
        console.warn(`Rate limited: ${request.method} ${new URL(request.url).pathname}`);
        return refuse(429, "Too many requests to the monsters, wait a minute", { "retry-after": "60" });
      }
    }
    return handleApi(request, env);
  },
};
