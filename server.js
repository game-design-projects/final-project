// Local game server. Holds the TypeSafe API key and the authoritative game state;
// the browser only sends player actions and renders what comes back.

import http from "node:http";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

try {
  process.loadEnvFile(new URL("./.env", import.meta.url));
} catch {}
if (!process.env.TYPESAFE_API_KEY) {
  console.error("Missing TYPESAFE_API_KEY. Put it in .env (see README).");
  process.exit(1);
}

const { newGame, takeTurn, view } = await import("./src/game.js");

const PORT = Number(process.env.PORT) || 5173;
const PUBLIC = fileURLToPath(new URL("./public/", import.meta.url));
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml" };
const MAX_GAMES = 200;
const games = new Map(); // id -> { world, busy }

function send(res, status, body, type = "application/json") {
  res.writeHead(status, { "content-type": `${type}; charset=utf-8`, "cache-control": "no-store" });
  res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

async function readJson(req) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 16_384) throw Object.assign(new Error("Request too large"), { status: 413 });
  }
  return raw ? JSON.parse(raw) : {};
}

const server = http.createServer(async (req, res) => {
  try {
    const { pathname } = new URL(req.url, "http://localhost");

    if (req.method === "POST" && pathname === "/api/new") {
      const id = randomUUID();
      const world = newGame();
      games.set(id, { world, busy: false });
      if (games.size > MAX_GAMES) games.delete(games.keys().next().value);
      return send(res, 200, { id, view: view(world) });
    }

    if (req.method === "POST" && pathname === "/api/turn") {
      const body = await readJson(req);
      const game = games.get(body.id);
      if (!game) return send(res, 404, { error: "Unknown game. Start a new one." });
      if (game.busy) return send(res, 409, { error: "Still resolving the last turn." });
      game.busy = true;
      try {
        const out = await takeTurn(game.world, body.action);
        return send(res, 200, { ...out, view: view(game.world) });
      } finally {
        game.busy = false;
      }
    }

    if (req.method === "GET") {
      const rel = pathname === "/" ? "index.html" : decodeURIComponent(pathname).replace(/^\/+/, "");
      const file = path.join(PUBLIC, rel);
      if (!file.startsWith(PUBLIC)) return send(res, 403, "Forbidden", "text/plain");
      try {
        const data = await readFile(file);
        return send(res, 200, data, TYPES[path.extname(file)] ?? "application/octet-stream");
      } catch {
        return send(res, 404, "Not found", "text/plain");
      }
    }

    send(res, 405, { error: "Method not allowed" });
  } catch (err) {
    console.error(err);
    send(res, err.status ?? 500, { error: err.message });
  }
});

server.listen(PORT, "127.0.0.1", () => console.log(`Jev Game AI running at http://localhost:${PORT}`));
