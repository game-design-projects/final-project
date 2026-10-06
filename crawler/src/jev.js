// Calls Jev with fetch, so it runs in Node, in a Cloudflare Worker and in a browser. Two ways in, same model and
// same request/answer shapes: TypeSafe's own System One endpoint, or OpenRouter's decisions API (which serves
// TypeSafe's Jev). The key is whatever the caller configures: a server's secret, or, in the itch.io build, an
// OpenRouter key with a small credit limit shipped in the page (see scripts/build-itch.js).

export const PROVIDERS = {
  typesafe: { url: "https://api.typesafe.ai/v1/systemone", model: "jev-latest", headers: {} },
  openrouter: { url: "https://openrouter.ai/api/alpha/decisions", model: "~typesafe/jev-latest", headers: { "x-title": "Donjon" } },
};

let apiKey = null;
let provider = PROVIDERS.typesafe;
export function configureJev(key, { via = "typesafe" } = {}) {
  apiKey = key;
  provider = PROVIDERS[via] ?? PROVIDERS.typesafe;
}

// `trace`: an array to record this call into (debug mode). It gets exactly what went to TypeSafe and what came
// back, never the key.
export async function jev(state, questions, trace = null) {
  if (!apiKey) throw new Error("Jev API key not configured");
  const t0 = Date.now();
  const entry = trace && { via: provider === PROVIDERS.openrouter ? "openrouter" : "typesafe", model: provider.model, state, questions, attempts: 0 };
  if (entry) trace.push(entry);
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(provider.url, {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json", ...provider.headers },
      body: JSON.stringify({ model: provider.model, state, questions }),
      signal: AbortSignal.timeout(10_000),
    });
    if (entry) entry.attempts = attempt + 1;
    // Back off and retry when rate-limited or overloaded, as the API docs recommend
    if ((res.status === 429 || res.status === 529) && attempt < 3) {
      await new Promise((r) => setTimeout(r, 400 * 2 ** attempt));
      continue;
    }
    if (!res.ok) {
      const text = (await res.text()).slice(0, 2000);
      if (entry) Object.assign(entry, { status: res.status, ms: Date.now() - t0, error: text });
      throw new Error(`Jev (${provider === PROVIDERS.openrouter ? "OpenRouter" : "TypeSafe"}) ${res.status}: ${text.slice(0, 200)}`);
    }
    const out = { ...(await res.json()), ms: Date.now() - t0 };
    if (entry) Object.assign(entry, { status: res.status, ms: out.ms, response: out });
    return out;
  }
}
