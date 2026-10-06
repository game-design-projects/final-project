// Calls TypeSafe's System One endpoint directly with fetch, so it runs in Node and in a Cloudflare Worker.
// The API key is configured on the server side only.

let apiKey = null;
export function configureJev(key) {
  apiKey = key;
}

// `trace`: an array to record this call into (debug mode). It gets exactly what went to TypeSafe and what came
// back, never the key.
export async function jev(state, questions, trace = null) {
  if (!apiKey) throw new Error("Jev API key not configured");
  const t0 = Date.now();
  const entry = trace && { model: "jev-latest", state, questions, attempts: 0 };
  if (entry) trace.push(entry);
  for (let attempt = 0; ; attempt++) {
    const res = await fetch("https://api.typesafe.ai/v1/systemone", {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ model: "jev-latest", state, questions }),
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
      throw new Error(`TypeSafe API ${res.status}: ${text.slice(0, 200)}`);
    }
    const out = { ...(await res.json()), ms: Date.now() - t0 };
    if (entry) Object.assign(entry, { status: res.status, ms: out.ms, response: out });
    return out;
  }
}
