// Builds the itch.io upload. Two ways for the game to reach Jev:
//   Worker:     npm run crawler:itch -- https://halls-of-jev-api.<you>.workers.dev
//               The static game calls your Cloudflare Worker, which holds the key. The zip has no secrets.
//   OpenRouter: OPENROUTER_API_KEY=... npm run crawler:itch -- --openrouter
//               No server at all: the game's rules (crawler/src) ship in the zip as server/, and the browser calls
//               Jev on OpenRouter directly WITH THAT KEY IN THE PAGE. Anyone can read it, so use a key with a small
//               credit limit (set one on openrouter.ai/settings/keys). The key is only written into dist/, never
//               committed; CI passes it from a repository secret.
import { cpSync, mkdirSync, rmSync, writeFileSync, readFileSync, readdirSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const direct = args.includes("--openrouter");
const apiBase = (args.find((a) => !a.startsWith("--")) ?? "").replace(/\/+$/, "");
const key = direct ? (process.env.OPENROUTER_API_KEY ?? "").trim() : "";
if (direct && !/^sk-or-/.test(key)) {
  console.error("--openrouter needs OPENROUTER_API_KEY (an OpenRouter key, sk-or-...) in the environment.");
  process.exit(1);
}
if (!direct && !/^https:\/\/|^http:\/\/localhost(:\d+)?$/.test(apiBase)) {
  console.error("Pass your Worker URL, e.g.  npm run crawler:itch -- https://halls-of-jev-api.you.workers.dev\nor build with OpenRouter:  OPENROUTER_API_KEY=... npm run crawler:itch -- --openrouter");
  process.exit(1);
}

const root = fileURLToPath(new URL("../../", import.meta.url));
const stage = `${root}dist/donjon`;
const zip = `${root}dist/donjon-itch.zip`;
rmSync(stage, { recursive: true, force: true });
rmSync(zip, { force: true });
mkdirSync(stage, { recursive: true });
// Dev-only pages (beat maker, art gallery, cover) stay out of the upload, and so does everything only the
// beat maker uses (its synth engine, soundfonts and songs). The game itself plays the pre-rendered m4a files.
const DEV_ONLY = ["beatmaker.html", "beatmaker.js", "gallery.html", "cover.html", "music.js", "theme.json", "song.json", "soundfonts"];
cpSync(`${root}crawler/public`, stage, { recursive: true, filter: (src) => !src.endsWith(".DS_Store") && !DEV_ONLY.some((f) => src.endsWith(`/${f}`)) });

if (direct) {
  // The rules the server would run, for the browser: crawler/src/*.js as server/*.js, with their imports of
  // ../public/x.js pointed at ../x.js (the public files sit at the zip's root). The mock is dev-only.
  mkdirSync(`${stage}/server`);
  for (const f of readdirSync(`${root}crawler/src`).filter((f) => f.endsWith(".js") && f !== "mock-jev.js")) {
    const code = readFileSync(`${root}crawler/src/${f}`, "utf8").replaceAll('"../public/', '"../');
    writeFileSync(`${stage}/server/${f}`, code);
  }
}

// Debug mode is on by default on itch.io, so players can open the Jev mind panel (J); ?nodebug turns it off.
const config = direct
  ? `// itch.io build: the browser runs the game's rules (server/) and calls Jev on OpenRouter itself, with this\n// low-limit key. Debug mode on by default.\nwindow.HALLS_CONFIG = { apiBase: "", openrouterKey: ${JSON.stringify(key)}, debug: true };\n`
  : `// itch.io build: the Jev API is the Cloudflare Worker, which holds the key. Debug mode on by default.\nwindow.HALLS_CONFIG = { apiBase: ${JSON.stringify(apiBase)}, debug: true };\n`;
writeFileSync(`${stage}/config.js`, config);

// index.html must sit at the top level of the zip for itch.io
execFileSync("zip", ["-r", "-X", "-q", zip, "."], { cwd: stage });
console.log(`Built ${zip} (${(statSync(zip).size / 1e6).toFixed(1)} MB) → ${direct ? "Jev via OpenRouter, from the browser" : `API ${apiBase}`}`);
