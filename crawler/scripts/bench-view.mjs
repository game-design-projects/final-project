// Frame-time and draw-call benchmark for the dungeon view, in real Chrome (playwright-core, channel "chrome").
//   node crawler/scripts/bench-view.mjs                 # this checkout, against mock Jev
//   node crawler/scripts/bench-view.mjs --root=/other/checkout --label=base --cpu=4 --frames=240
// It starts the game server on mock Jev, plays three scenes (standing in a corridor, walking, a three-monster
// fight) and measures every animation frame: script time inside requestAnimationFrame, 2D canvas calls,
// Path2D and gradient allocations, WebGL draws and texture uploads, style recalcs and layouts.
// Prints a table and writes the numbers as JSON (--out=path) so two checkouts can be compared.
import { spawn } from "node:child_process";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(args.root ?? path.join(here, "../.."));
const port = Number(args.port ?? 5190 + Math.floor(Math.random() * 400));
const FRAMES = Number(args.frames ?? 240);
const CPU = Number(args.cpu ?? 4); // CPU slowdown, to stand in for a modest laptop
const label = args.label ?? path.basename(root);

// Installed before the game's scripts: counts canvas and WebGL work per animation frame.
function instrument() {
  const tally = { calls: {}, path2d: 0, gradients: 0, gl: { draws: 0, uploads: 0 } };
  const frames = [];
  let current = null;
  const bump = (k) => (tally.calls[k] = (tally.calls[k] ?? 0) + 1);
  const C2D = CanvasRenderingContext2D.prototype;
  for (const k of ["fill", "stroke", "fillRect", "strokeRect", "clearRect", "fillText", "drawImage", "clip", "save", "restore", "getImageData", "putImageData", "measureText", "beginPath"]) {
    const f = C2D[k];
    C2D[k] = function (...a) {
      bump(k);
      return f.apply(this, a);
    };
  }
  for (const k of ["createLinearGradient", "createRadialGradient"]) {
    const f = C2D[k];
    C2D[k] = function (...a) {
      tally.gradients++;
      return f.apply(this, a);
    };
  }
  const P2D = window.Path2D;
  window.Path2D = class extends P2D {
    constructor(...a) {
      super(...a);
      tally.path2d++;
    }
  };
  for (const GL of [window.WebGLRenderingContext, window.WebGL2RenderingContext].filter(Boolean)) {
    for (const [k, slot] of [["drawArrays", "draws"], ["drawElements", "draws"], ["texImage2D", "uploads"], ["texSubImage2D", "uploads"]]) {
      const f = GL.prototype[k];
      GL.prototype[k] = function (...a) {
        tally.gl[slot]++;
        return f.apply(this, a);
      };
    }
  }
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) =>
    raf((ts) => {
      const before = JSON.stringify(tally);
      const t0 = performance.now();
      cb(ts);
      const ms = performance.now() - t0;
      if (current) {
        const b = JSON.parse(before);
        const calls = Object.fromEntries(Object.entries(tally.calls).map(([k, v]) => [k, v - (b.calls[k] ?? 0)]).filter(([, v]) => v));
        current.push({ ms, calls, path2d: tally.path2d - b.path2d, gradients: tally.gradients - b.gradients, glDraws: tally.gl.draws - b.gl.draws, glUploads: tally.gl.uploads - b.gl.uploads });
      }
    });
  window.__bench = {
    begin: () => (current = []),
    count: () => current?.length ?? 0,
    end: () => {
      const out = current;
      current = null;
      frames.push(out);
      return out;
    },
  };
}

function summarize(frames) {
  const ms = frames.map((f) => f.ms).sort((a, b) => a - b);
  const mean = (xs) => xs.reduce((a, b) => a + b, 0) / Math.max(1, xs.length);
  const totalCalls = frames.map((f) => Object.values(f.calls).reduce((a, b) => a + b, 0));
  const draws = frames.map((f) => ["fill", "stroke", "fillRect", "strokeRect", "fillText", "drawImage", "putImageData"].reduce((a, k) => a + (f.calls[k] ?? 0), 0) + f.glDraws);
  return {
    frames: frames.length,
    meanMs: +mean(ms).toFixed(3),
    p95Ms: +ms[Math.floor(ms.length * 0.95)]?.toFixed(3),
    maxMs: +ms.at(-1)?.toFixed(3),
    canvasCallsPerFrame: +mean(totalCalls).toFixed(1),
    drawCallsPerFrame: +mean(draws).toFixed(1),
    path2dPerFrame: +mean(frames.map((f) => f.path2d)).toFixed(2),
    gradientsPerFrame: +mean(frames.map((f) => f.gradients)).toFixed(2),
    glUploadsPerFrame: +mean(frames.map((f) => f.glUploads)).toFixed(2),
  };
}

async function main() {
  const server = spawn(process.execPath, [path.join(root, "crawler/server.js")], { env: { ...process.env, JEV_MOCK: "1", JEV_SEED: "7", PORT: String(port) }, stdio: ["ignore", "pipe", "inherit"] });
  await new Promise((ok, fail) => {
    server.stdout.on("data", (d) => /running at/.test(d) && ok());
    server.on("exit", (c) => fail(new Error(`server exited ${c}`)));
  });
  const browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--autoplay-policy=no-user-gesture-required"] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 820 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
  await page.addInitScript(instrument);
  await page.addInitScript(() => {
    localStorage.setItem("hallsOfJev.tipsOff", "1");
    localStorage.setItem("donjon.debug", "1");
  });
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Performance.enable");
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: CPU });
  await page.goto(`http://127.0.0.1:${port}/index.html?seed=7`);
  await page.waitForFunction(() => document.fonts.status === "loaded");
  await page.keyboard.press("Enter");
  await page.waitForFunction(() => window.halls?.state()?.map);
  // Face the longest open corridor from the start, so the view is full of walls and torches
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
  await page.waitForTimeout(500);

  const metrics = async () => Object.fromEntries((await cdp.send("Performance.getMetrics")).metrics.map((m) => [m.name, m.value]));
  const results = {};
  async function scene(name, during) {
    const m0 = await metrics();
    await page.evaluate(() => window.__bench.begin());
    await during();
    await page.waitForFunction((n) => window.__bench.count() >= n, FRAMES, { timeout: 60000 });
    const frames = await page.evaluate(() => window.__bench.end());
    const m1 = await metrics();
    results[name] = {
      ...summarize(frames),
      styleRecalcs: m1.RecalcStyleCount - m0.RecalcStyleCount,
      layouts: m1.LayoutCount - m0.LayoutCount,
      heapDeltaKB: Math.round((m1.JSHeapUsedSize - m0.JSHeapUsedSize) / 1024),
    };
  }

  await scene("explore-idle", async () => {});
  await scene("explore-walk", async () => {
    for (let i = 0; i < 16; i++) {
      await page.keyboard.press(i % 4 === 3 ? "d" : "w");
      await page.waitForTimeout(220);
    }
  });
  await page.evaluate(() => window.halls.meet("slime", "goblin", "bandit"));
  await page.waitForFunction(() => window.halls.state().combat && !window.halls.state().busy, null, { timeout: 15000 });
  await scene("combat-3", async () => {});
  await page.screenshot({ path: args.shot ?? path.join(root, "dist", `bench-${label}.png`) }).catch(() => {});

  await browser.close();
  server.kill();
  const out = { label, root, cpuThrottle: CPU, frames: FRAMES, results, errors };
  if (args.out) await writeFile(args.out, JSON.stringify(out, null, 2));
  console.log(`\n${label} (CPU x${CPU}, ${FRAMES}-frame windows)`);
  console.table(results);
  if (errors.length) console.log("page errors:", errors);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
