// Calls TypeSafe's System One endpoint directly with fetch, so it runs in Node and in a Cloudflare Worker.
// The API key is configured on the server side only.

let apiKey = null;
export function configureJev(key) {
  apiKey = key;
}

export async function jev(state, questions) {
  if (!apiKey) throw new Error("Jev API key not configured");
  const t0 = Date.now();
  for (let attempt = 0; ; attempt++) {
    const res = await fetch("https://api.typesafe.ai/v1/systemone", {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ model: "jev-latest", state, questions }),
      signal: AbortSignal.timeout(10_000),
    });
    // Back off and retry when rate-limited or overloaded, as the API docs recommend
    if ((res.status === 429 || res.status === 529) && attempt < 3) {
      await new Promise((r) => setTimeout(r, 400 * 2 ** attempt));
      continue;
    }
    if (!res.ok) throw new Error(`TypeSafe API ${res.status}: ${(await res.text()).slice(0, 200)}`);
    return { ...(await res.json()), ms: Date.now() - t0 };
  }
}
