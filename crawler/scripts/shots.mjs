// Smoke test and screenshots of the game feel, in real Chrome (playwright-core, channel "chrome"), on mock Jev.
//   node crawler/scripts/shots.mjs [--out=dir]
// Walks the title, a corridor, a turn caught mid-pan, a fight, a critical hit and kill, the party in danger, the
// plain-canvas fallback (?nofx) and a phone-sized window; saves a PNG of each and fails on any page error or a
// check that doesn't hold (the shader covers the view, danger closes the music's filter and starts the heartbeat).
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { chromium } from "playwright-core";

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const out = path.resolve(args.out ?? path.join(root, "dist/shots"));
const port = 5600 + Math.floor(Math.random() * 300);

const server = spawn(process.execPath, [path.join(root, "crawler/server.js")], { env: { ...process.env, JEV_MOCK: "1", JEV_SEED: "3", PORT: String(port) }, stdio: ["ignore", "pipe", "inherit"] });
await new Promise((ok) => server.stdout.on("data", (d) => /running at/.test(d) && ok()));
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--autoplay-policy=no-user-gesture-required"] });
const errors = [];

async function open(query = "", viewport = { width: 1280, height: 820 }) {
  const page = await browser.newPage({ viewport, deviceScaleFactor: 2 });
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => m.type() === "error" && !/favicon|fonts\.g/.test(m.text()) && errors.push(m.text()));
  await page.addInitScript(() => {
    localStorage.setItem("hallsOfJev.tipsOff", "1");
    localStorage.setItem("donjon.debug", "1");
    let a = 3;
    Math.random = () => {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = Math.imul(a ^ (a >>> 15), a | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  });
  await page.goto(`http://127.0.0.1:${port}/index.html${query}`);
  await page.waitForFunction(() => document.fonts.status === "loaded");
  return page;
}
const shot = (page, name, clip = true) => page.screenshot({ path: path.join(out, `${name}.png`), ...(clip ? { clip: { x: 0, y: 0, width: 1140, height: 820 } } : {}) });
const feel = (page) => page.evaluate(() => {
  const f = window.halls.feel();
  return { post: !!f.post?.alive, danger: f.danger, mixerDanger: f.mixer?.danger, cutoff: f.mixer?.lowpass.frequency.value, beats: f.post?.beats.length ?? 0, pulse: f.post?.pulseLevel ?? 0 };
});

try {
  const page = await open();
  await page.waitForTimeout(400);
  await shot(page, "1-title");
  await page.keyboard.press("Enter");
  await page.waitForFunction(() => window.halls?.state()?.map);
  // The shader's canvas sits exactly over the view's picture
  const box = await page.evaluate(() => {
    const v = document.querySelector("#view").getBoundingClientRect();
    const p = document.querySelector("canvas.postfx")?.getBoundingClientRect();
    return { v: [v.x, v.y, v.width, v.height], p: p && [p.x, p.y, p.width, p.height] };
  });
  assert.ok(box.p, "the postfx canvas is on the page");
  assert.ok(Math.abs(box.p[0] - (box.v[0] + 2)) < 1 && Math.abs(box.p[2] - (box.v[2] - 4)) < 1, `postfx covers the view inside its border: ${JSON.stringify(box)}`);
  await page.evaluate(() => {
    const G = window.halls.state();
    const D = [[0, -1], [1, 0], [0, 1], [-1, 0]];
    const run = (d) => {
      let n = 0;
      while (G.map.grid[G.y + D[d][1] * (n + 1)]?.[G.x + D[d][0] * (n + 1)] === 1) n++;
      return n;
    };
    G.dir = [0, 1, 2, 3].sort((a, b) => run(b) - run(a))[0];
  });
  await page.waitForTimeout(300);
  await shot(page, "2-explore");
  // A turn, caught mid-pan
  await page.keyboard.press("d");
  await page.waitForTimeout(60);
  await shot(page, "3-turn-midway");
  await page.waitForTimeout(400);

  await page.evaluate(() => window.halls.meet("goblin", "slime"));
  await page.waitForFunction(() => window.halls.state().combat && !window.halls.state().busy, null, { timeout: 15000 });
  await page.waitForTimeout(500);
  await shot(page, "4-combat");
  // A critical hit, then a kill: the flash and the freeze
  await page.evaluate(() => {
    window.halls.fx.emit("enemy:hit", { dmg: 9, maxHp: 10, crit: true });
    window.halls.fx.emit("enemy:kill", { boss: false });
  });
  await page.waitForTimeout(40);
  await shot(page, "5-crit-flash");

  // The party in danger: health low, someone dying
  await page.evaluate(() => {
    const G = window.halls.state();
    G.party.forEach((m, i) => (m.hp = i === 0 ? 0 : Math.max(1, Math.round(m.maxHp * 0.12))));
    Object.assign(G.party[0], { down: true, stable: false, saves: { s: 0, f: 1 } });
    window.halls.fx.emit("party:hurt", { dmg: 7, hp: 1, maxHp: 12 });
  });
  await page.waitForTimeout(2500);
  const f = await feel(page);
  assert.ok(f.post, "postfx alive");
  assert.ok(f.danger > 0.8 && f.mixerDanger > 0.8, `danger rises: ${JSON.stringify(f)}`);
  assert.ok(f.cutoff < 5000, `the music's low-pass closes: ${f.cutoff} Hz`);
  const beats = await page.evaluate(() => window.halls.sfx.stats);
  assert.ok(beats.played > 0, "effects play through the shared context");
  await shot(page, "6-danger");
  await page.close();

  // No shader: the plain canvas, everything else the same
  const plain = await open("?nofx");
  await plain.keyboard.press("Enter");
  await plain.waitForFunction(() => window.halls?.state()?.map);
  assert.equal(await plain.evaluate(() => document.querySelector("canvas.postfx")), null);
  await plain.waitForTimeout(300);
  await shot(plain, "7-nofx");
  await plain.close();

  const phone = await open("", { width: 390, height: 844 });
  await phone.keyboard.press("Enter");
  await phone.waitForFunction(() => window.halls?.state()?.map);
  await phone.waitForTimeout(300);
  const scroll = await phone.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  await shot(phone, "8-phone", false);
  assert.ok(scroll <= 0, `no sideways scroll on a phone: ${scroll}px`);
  await phone.close();
  assert.deepEqual(errors, [], "no page errors");
  console.log(`ok: 8 shots in ${out}`);
} catch (err) {
  console.error(err.message, errors.length ? `\npage errors: ${errors.join("\n")}` : "");
  process.exitCode = 1;
} finally {
  await browser.close();
  server.kill();
}
