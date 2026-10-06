// Donjon: local server. Serves the game and holds the TypeSafe key; the browser runs the dungeon
// and asks the server only for Jev decisions (enemy turns and ally reactions).

import http from "node:http";
import { readFile, writeFile, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

// JEV_MOCK=1: answer Jev from src/mock-jev.js (random but well-formed, no key, no credits) to work on the game
// without spending anything. Monsters then act at random, not sensibly.
const MOCK = process.env.JEV_MOCK === "1";
if (MOCK) {
  const { mockFetch } = await import("./src/mock-jev.js");
  globalThis.fetch = mockFetch({ seed: Number(process.env.JEV_SEED) || Date.now() % 1e6, latency: 150 });
  process.env.TYPESAFE_API_KEY ||= "mock";
  console.log("JEV_MOCK=1: Jev is mocked. Random answers, no credits.");
} else {
  try {
    process.loadEnvFile(new URL("../.env", import.meta.url));
  } catch {}
}
if (!process.env.TYPESAFE_API_KEY && !process.env.OPENROUTER_API_KEY) {
  console.error("Missing TYPESAFE_API_KEY (or OPENROUTER_API_KEY). Put one in the project's .env, or run with JEV_MOCK=1.");
  process.exit(1);
}

const { handleApi } = await import("./src/api.js");
const { INSTRUMENTS, DRUMS, CHORDS, DEFAULT_VOLUMES } = await import("./public/music.js");

const PORT = Number(process.env.PORT) || 5174;
const PUBLIC = fileURLToPath(new URL("./public/", import.meta.url));
const TYPES = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "text/javascript",
  ".json": "application/json",
  ".svg": "image/svg+xml",
};

function send(res, status, body, type = "application/json") {
  res.writeHead(status, { "content-type": `${type}; charset=utf-8`, "cache-control": "no-store" });
  res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

// Adapt Node's request to a Fetch Request and hand it to the shared API handler (same code as the Worker).
async function api(req, res) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 64_000) return send(res, 413, { error: "Request too large" });
  }
  const request = new Request(`http://localhost${req.url}`, {
    method: req.method,
    headers: Object.entries(req.headers).filter(([, v]) => typeof v === "string"),
    body: req.method === "POST" ? raw : undefined,
  });
  const out = await handleApi(request, process.env);
  res.writeHead(out.status, Object.fromEntries(out.headers));
  res.end(await out.text());
}

// Local-only: the beat maker saves your beat as public/song.json, which the game then plays.
// Strictly validated before it touches disk. Not part of the Cloudflare Worker.
const NOTE = /^[A-G][#b]?[1-7]$/;
const LENS = [0, 1, 2, 3, 4, 8];
function validSong(p) {
  const steps = p?.bars * 16;
  const flags = (a) => Array.isArray(a) && a.length === steps && a.every((v) => v === 0 || v === 1);
  const notes = (a) => Array.isArray(a) && a.length === steps && a.every((v) => v === null || (typeof v === "string" && NOTE.test(v)));
  return (
    [1, 2, 4, 8, 16, 24, 32].includes(p?.bars) &&
    Number.isFinite(p.bpm) && p.bpm >= 40 && p.bpm <= 220 &&
    Array.isArray(p.chords) && p.chords.length === p.bars && p.chords.every((c) => Object.hasOwn(CHORDS, c)) &&
    typeof p.pad === "boolean" &&
    ["lead", "keys", "bass", "pad"].every((t) => Object.hasOwn(INSTRUMENTS, p.instruments?.[t])) &&
    Object.keys(DRUMS).every((d) => flags(p.drums?.[d])) &&
    notes(p.lead) && notes(p.keys) && notes(p.bass) &&
    LENS.includes(p.leadLen) && LENS.includes(p.keysLen) && LENS.includes(p.bassLen) &&
    validLayers(p.layers ?? [], steps)
  );
}

// Score layers: exact notes [step, note, length] with an instrument, volume and output.
function validLayers(layers, steps) {
  return (
    Array.isArray(layers) && layers.length <= 12 &&
    layers.every(
      (l) =>
        Object.hasOwn(INSTRUMENTS, l.instrument) &&
        typeof l.volume === "number" && l.volume >= 0 && l.volume <= 1 &&
        ["lead", "keys", "bass", "pad"].includes(l.send) &&
        (l.label === undefined || (typeof l.label === "string" && l.label.length <= 80)) &&
        Array.isArray(l.events) && l.events.length <= 4000 &&
        l.events.every(([st, n, len]) => Number.isInteger(st) && st >= 0 && st < steps && typeof n === "string" && NOTE.test(n) && Number.isInteger(len) && len >= 1 && len <= 128),
    )
  );
}

async function devSong(req, res) {
  const file = path.join(PUBLIC, "song.json");
  if (req.method === "DELETE") {
    await rm(file, { force: true });
    return send(res, 200, { ok: true });
  }
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 32_000) return send(res, 413, { error: "Too large" });
  }
  let p;
  try {
    p = JSON.parse(raw);
  } catch {
    return send(res, 400, { error: "Not JSON" });
  }
  if (!validSong(p)) return send(res, 400, { error: "That doesn't look like a beat" });
  const vols = Object.fromEntries(
    Object.keys(DEFAULT_VOLUMES).map((k) => [k, typeof p.volumes?.[k] === "number" ? Math.max(0, Math.min(1, p.volumes[k])) : DEFAULT_VOLUMES[k]]),
  );
  const clean = {
    bpm: p.bpm, bars: p.bars, chords: p.chords, pad: p.pad,
    instruments: { lead: p.instruments.lead, keys: p.instruments.keys, bass: p.instruments.bass, pad: p.instruments.pad },
    drums: Object.fromEntries(Object.keys(DRUMS).map((d) => [d, p.drums[d]])),
    lead: p.lead, keys: p.keys, bass: p.bass, leadLen: p.leadLen, keysLen: p.keysLen, bassLen: p.bassLen, volumes: vols,
    layers: (p.layers ?? []).map((l) => ({ id: String(l.id ?? "").slice(0, 30), label: l.label, instrument: l.instrument, volume: l.volume, send: l.send, muted: !!l.muted, events: l.events })),
  };
  await writeFile(file, JSON.stringify(clean));
  send(res, 200, { ok: true });
}

const server = http.createServer(async (req, res) => {
  try {
    const { pathname } = new URL(req.url, "http://localhost");
    if (pathname === "/api/dev/song" && (req.method === "POST" || req.method === "DELETE")) return devSong(req, res);
    if (pathname.startsWith("/api/")) return api(req, res);
    if (req.method === "GET") {
      const rel = pathname === "/" ? "index.html" : decodeURIComponent(pathname).replace(/^\/+/, "");
      const file = path.join(PUBLIC, rel);
      if (!file.startsWith(PUBLIC)) return send(res, 403, "Forbidden", "text/plain");
      try {
        return send(res, 200, await readFile(file), TYPES[path.extname(file)] ?? "application/octet-stream");
      } catch {
        return send(res, 404, "Not found", "text/plain");
      }
    }
    send(res, 405, { error: "Method not allowed" });
  } catch (err) {
    console.error(err);
    send(res, err.status ?? 500, { error: `${err.name}: ${err.message}` });
  }
});

server.listen(PORT, "127.0.0.1", () => console.log(`Donjon running at http://localhost:${PORT}`));
