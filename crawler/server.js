// Halls of Jev: local server. Serves the game and holds the TypeSafe key; the browser runs the dungeon
// and asks the server only for Jev decisions (enemy turns and ally reactions).

import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

try {
  process.loadEnvFile(new URL("../.env", import.meta.url));
} catch {}
if (!process.env.TYPESAFE_API_KEY) {
  console.error("Missing TYPESAFE_API_KEY. Put it in the project's .env.");
  process.exit(1);
}

const { handleApi } = await import("./src/api.js");

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

const server = http.createServer(async (req, res) => {
  try {
    const { pathname } = new URL(req.url, "http://localhost");
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

server.listen(PORT, "127.0.0.1", () => console.log(`Halls of Jev running at http://localhost:${PORT}`));
