// A stand-in for TypeSafe's Jev endpoint, for tests and `npm run crawler:scenarios` (no API key, no credits).
// It answers every question with a well-formed answer of the right type, from a seeded random source, so a
// run is repeatable: noul -> { noul }, choice -> { choice, probabilities }, score -> { score, probabilities }.
// The answers are random, not sensible: this exercises the game's plumbing and rules, not Jev's judgement.

export const JEV_URL = "https://api.typesafe.ai/v1/systemone";
export const JEV_URLS = [JEV_URL, "https://openrouter.ai/api/alpha/decisions"];

// Small seeded PRNG (mulberry32), so a seed gives the same answers every run
export function seeded(seed = 1) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Random probabilities over labels, summing to 1
function spread(labels, rand) {
  const w = labels.map(() => rand() ** 2 + 0.01);
  const sum = w.reduce((a, b) => a + b, 0);
  return Object.fromEntries(labels.map((l, i) => [l, w[i] / sum]));
}

export function mockAnswer(question, rand) {
  if (question.type === "noul") return { type: "noul", noul: rand() };
  if (question.type === "choice") {
    const probabilities = spread(Object.keys(question.criteria ?? {}), rand);
    const choice = Object.entries(probabilities).sort((a, b) => b[1] - a[1])[0]?.[0];
    return { type: "choice", choice, probabilities };
  }
  if (question.type === "score") {
    const levels = (question.criteria ?? [0, 1]).map((_, i) => String(i));
    const probabilities = spread(levels, rand);
    const score = Object.entries(probabilities).reduce((s, [k, p]) => s + Number(k) * p, 0);
    return { type: "score", score, confidence: 0.5, probabilities };
  }
  throw new Error(`mock Jev: unknown question type ${question.type}`);
}

export function mockSystemOne({ questions }, rand) {
  const answers = Object.fromEntries(Object.entries(questions).map(([name, q]) => [name, mockAnswer(q, rand)]));
  const input_tokens = JSON.stringify(questions).length >> 2;
  return { model: "jev-mock", answers, usage: { input_tokens } };
}

// A fetch that answers the Jev endpoint itself and passes everything else to the real fetch.
// Install with: globalThis.fetch = mockFetch({ seed: 7 })
export function mockFetch({ seed = 1, latency = 0, realFetch = globalThis.fetch } = {}) {
  const rand = seeded(seed);
  const calls = [];
  const fake = async (url, init = {}) => {
    if (!JEV_URLS.includes(String(url))) return realFetch(url, init);
    const body = JSON.parse(init.body);
    calls.push(body);
    if (latency) await new Promise((r) => setTimeout(r, latency));
    return new Response(JSON.stringify(mockSystemOne(body, rand)), { status: 200, headers: { "content-type": "application/json" } });
  };
  fake.calls = calls;
  return fake;
}
