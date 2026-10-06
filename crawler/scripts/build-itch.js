// Builds the itch.io upload: the static game, pointed at your deployed Worker. Contains no secrets.
// Usage: npm run crawler:itch -- https://halls-of-jev-api.<you>.workers.dev
import { cpSync, mkdirSync, rmSync, writeFileSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const apiBase = (process.argv[2] ?? "").replace(/\/+$/, "");
if (!/^https:\/\/|^http:\/\/localhost(:\d+)?$/.test(apiBase)) {
  console.error("Pass your Worker URL, e.g.  npm run crawler:itch -- https://halls-of-jev-api.you.workers.dev");
  process.exit(1);
}

const root = fileURLToPath(new URL("../../", import.meta.url));
const stage = `${root}dist/donjon`;
const zip = `${root}dist/donjon-itch.zip`;
rmSync(stage, { recursive: true, force: true });
rmSync(zip, { force: true });
mkdirSync(stage, { recursive: true });
// Dev-only pages (beat maker, art gallery, cover) stay out of the upload, and so does everything only the
// beat maker uses (its synth engine, soundfonts and songs). The game itself plays ambient.m4a.
const DEV_ONLY = ["beatmaker.html", "beatmaker.js", "gallery.html", "cover.html", "music.js", "theme.json", "song.json", "soundfonts"];
cpSync(`${root}crawler/public`, stage, { recursive: true, filter: (src) => !src.endsWith(".DS_Store") && !DEV_ONLY.some((f) => src.endsWith(`/${f}`)) });
// Debug mode is on by default on itch.io, so players can open the Jev mind panel (J); ?nodebug turns it off.
writeFileSync(`${stage}/config.js`, `// itch.io build: the Jev API is the Cloudflare Worker, which holds the key. Debug mode on by default.\nwindow.HALLS_CONFIG = { apiBase: ${JSON.stringify(apiBase)}, debug: true };\n`);

// index.html must sit at the top level of the zip for itch.io
execFileSync("zip", ["-r", "-X", "-q", zip, "."], { cwd: stage });
console.log(`Built ${zip} (${(statSync(zip).size / 1e6).toFixed(1)} MB) → API ${apiBase}`);
