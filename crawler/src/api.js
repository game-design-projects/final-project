// The game's API, written against the standard Fetch Request/Response so the same code runs in the
// local Node server and in a Cloudflare Worker. `env` supplies TYPESAFE_API_KEY, which never leaves here.

import { enemyTurn, groupTurn } from "./enemy.js";
import { allyTalk, vowMade, vowBroken } from "./bonds.js";
import { allyReactions } from "./allies.js";
import { configureJev } from "./jev.js";
import { SPECIES } from "../public/species.js";
import { PITCH } from "../public/emotions.js";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
  "access-control-max-age": "86400",
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS } });

// Keep player-controlled text small before it reaches the model.
function sanitizeEnemy(b) {
  if (!SPECIES[b.enemy?.species]) throw Object.assign(new Error("Unknown monster"), { status: 400 });
  if (b.playerAction?.message) b.playerAction.message = String(b.playerAction.message).slice(0, 240);
  b.conversation = (b.conversation ?? []).slice(-10).map((l) => ({ speaker: String(l.speaker), text: String(l.text).slice(0, 240) }));
  b.events = (b.events ?? []).slice(0, 12).map((e) => String(e).slice(0, 200));
  b.party = (b.party ?? []).slice(0, 6);
  return b;
}

const short = (v, n = 240) => String(v ?? "").slice(0, n);
const okSpecies = (m) => {
  if (!SPECIES[m?.species]) throw Object.assign(new Error("Unknown monster"), { status: 400 });
  return m;
};

function sanitizeGroup(b) {
  b.monsters = (b.monsters ?? []).slice(0, 3).map(okSpecies);
  if (!b.monsters.length) throw Object.assign(new Error("No monsters"), { status: 400 });
  b.monsters.forEach((m) => {
    m.thisRound = (m.thisRound ?? []).slice(0, 6).map((t) => short(t, 160));
    m.impressions = (m.impressions ?? []).slice(-8).map((t) => short(t, 160));
  });
  const pa = b.playerAction ?? {};
  b.playerAction = {
    type: short(pa.type, 20),
    message: pa.message ? short(pa.message) : null,
    gold: Math.max(0, Number(pa.gold) || 0),
    targetId: short(pa.targetId, 20),
    delivery: Math.max(0.5, Math.min(2, Number(pa.delivery) || 1)),
    pitch: PITCH[pa.pitch] ? pa.pitch : null,
  };
  b.conversation = (b.conversation ?? []).slice(-10).map((l) => ({ speaker: short(l.speaker, 40), text: short(l.text) }));
  b.events = (b.events ?? []).slice(0, 12).map((e) => short(e, 200));
  b.party = (b.party ?? []).slice(0, 6);
  b.vows = (b.vows ?? []).slice(0, 12).map((v) => ({ text: short(v.text, 80), toId: short(v.toId, 20), status: short(v.status, 10) }));
  return b;
}

function sanitizeAllies(b) {
  b.allies = (b.allies ?? []).slice(0, 5).filter((a) => SPECIES[a.species]);
  b.events = (b.events ?? []).slice(0, 16).map((e) => String(e).slice(0, 200));
  return b;
}

export async function handleApi(request, env) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const { pathname } = new URL(request.url);
  if (request.method !== "POST" || !pathname.startsWith("/api/")) return json({ error: "Not found" }, 404);

  try {
    const raw = await request.text();
    if (raw.length > 64_000) return json({ error: "Request too large" }, 413);
    const body = JSON.parse(raw || "{}");
    configureJev(env.TYPESAFE_API_KEY);
    if (pathname === "/api/enemy-turn") return json(await enemyTurn(sanitizeEnemy(body)));
    if (pathname === "/api/ally-reactions") return json(await allyReactions(sanitizeAllies(body)));
    if (pathname === "/api/group-turn") return json(await groupTurn(sanitizeGroup(body)));
    if (pathname === "/api/ally-talk")
      return json(await allyTalk({ ally: okSpecies(body.ally), message: short(body.message), vows: (body.vows ?? []).slice(0, 12) }));
    if (pathname === "/api/vow") return json(await vowMade({ monster: okSpecies(body.monster), vow: { text: short(body.vow?.text, 80) } }));
    if (pathname === "/api/vow-broken")
      return json(await vowBroken({ monster: okSpecies(body.monster), vow: { text: short(body.vow?.text, 80) }, how: short(body.how, 200), gold: Number(body.gold) || 0 }));
    return json({ error: "Not found" }, 404);
  } catch (err) {
    console.error(err);
    return json({ error: err.status ? err.message : "Server error" }, err.status ?? 500);
  }
}
