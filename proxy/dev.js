// Runs the Worker locally in Node (same handler): node proxy/dev.js, then set apiBase to http://localhost:5175
import http from "node:http";
try {
  process.loadEnvFile(new URL("../.env", import.meta.url));
} catch {}
const { default: worker } = await import("./worker.js");

http
  .createServer(async (req, res) => {
    let raw = "";
    for await (const chunk of req) raw += chunk;
    const request = new Request(`http://localhost${req.url}`, {
      method: req.method,
      headers: Object.entries(req.headers).filter(([, v]) => typeof v === "string"),
      body: ["GET", "HEAD", "OPTIONS"].includes(req.method) ? undefined : raw,
    });
    const out = await worker.fetch(request, process.env);
    res.writeHead(out.status, Object.fromEntries(out.headers));
    res.end(await out.text());
  })
  .listen(5175, "127.0.0.1", () => console.log("Worker emulation on http://localhost:5175"));
