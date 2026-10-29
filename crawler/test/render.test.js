// Perspective of the corridor view: run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { EYE, VIEW, scaleAt, project, corridorFaces, visibleCells, faceMapper } from "../public/render.js";

// Builds a map from rows of "#" (wall) and "." (floor).
const mapOf = (...rows) => ({ grid: rows.map((r) => [...r].map((c) => (c === "." ? 1 : 0))), stairs: { x: -1, y: -1 } });
const N = 0; // facing north: forward is -y, left is -x

test("scale is a true 1/z perspective, not a geometric series", () => {
  for (let z = 0; z <= VIEW; z += 0.5) assert.ok(Math.abs(scaleAt(z) * (EYE + z) - EYE) < 1e-9);
  assert.equal(scaleAt(0), 1);
});

test("project puts the near frame on the canvas edge and converges on the center", () => {
  const [x0, y0] = project(448, 288, -0.5, 0, -0.5);
  assert.deepEqual([x0, y0], [4, 4]);
  const [xf, yf] = project(448, 288, 0, 1e6, 0.5);
  assert.ok(Math.abs(xf - 224) < 1e-3 && Math.abs(yf - 144) < 1e-3);
});

test("a dead end straight ahead is one front face plus the two side walls", () => {
  const map = mapOf(
    "###", //
    "#.#",
    "#.#",
    "###",
  );
  const faces = corridorFaces(map, 1, 2, N);
  const front = faces.filter((f) => f.type === "front");
  assert.deepEqual(front.map((f) => [f.d, f.k]), [[2, 0]]);
  const sides = faces.filter((f) => f.type === "side").map((f) => `${f.d},${f.k}`).sort();
  assert.deepEqual(sides, ["0,-1", "0,1", "1,-1", "1,1"]);
});

test("no phantom wall across a side opening that leads into a room", () => {
  // Standing at the bottom of a 3-wide room: the old renderer drew a wall face at the far side of the
  // left opening even though the cell beyond it is open floor.
  const map = mapOf(
    "#####",
    "#...#",
    "#...#",
    "#...#",
    "#####",
  );
  const faces = corridorFaces(map, 2, 3, N);
  for (const f of faces) {
    if (f.type === "stairs") continue;
    const [wx, wy] = f.wall;
    assert.equal(map.grid[wy][wx], 0, `face ${f.type} at d=${f.d} k=${f.k} is drawn on open floor`);
  }
  // The room's left and right walls are seen side-on, at k = ±2
  assert.ok(faces.some((f) => f.type === "side" && f.k === -2 && f.d === 0));
  assert.ok(faces.some((f) => f.type === "side" && f.k === 2 && f.d === 2));
});

test("faces come far to near, outer to inner, so nearer walls paint over farther ones", () => {
  const map = mapOf(
    "#######",
    "#.....#",
    "#.#.#.#",
    "#.....#",
    "###.###",
    "###.###",
    "#######",
  );
  const faces = corridorFaces(map, 3, 5, N).filter((f) => f.type !== "stairs");
  for (let i = 1; i < faces.length; i++) {
    const a = faces[i - 1];
    const b = faces[i];
    assert.ok(a.d > b.d || (a.d === b.d && Math.abs(a.k) >= Math.abs(b.k)), `order broken at ${i}`);
  }
});

test("only floor you could actually see goes on the automap", () => {
  const map = mapOf(
    "#######",
    "#.#...#",
    "#.#.#.#",
    "#.....#",
    "###.###",
    "#######",
  );
  const seen = new Set(visibleCells(map, 3, 4, N).map(([x, y]) => `${x},${y}`));
  assert.ok(seen.has("3,4") && seen.has("3,3") && seen.has("3,2") && seen.has("3,1"));
  assert.ok(seen.has("2,3") && seen.has("4,3")); // the cross corridor, where it shows through the gap
  assert.ok(!seen.has("1,3"), "two cells to the side, one ahead: outside the field of view");
  assert.ok(!seen.has("1,1"), "around the corner behind a wall");
  for (const k of seen) {
    const [x, y] = k.split(",").map(Number);
    assert.equal(map.grid[y][x], 1);
  }
});

test("decorations on a side wall are foreshortened: the middle of the wall sits past the screen midpoint", () => {
  const P = faceMapper(448, 288, { type: "side", d: 0, k: -1 });
  const [xNear] = P(0, 0.5);
  const [xMid] = P(0.5, 0.5);
  const [xFar] = P(1, 0.5);
  assert.ok(xNear < xMid && xMid < xFar);
  assert.ok(xMid - xNear > xFar - xMid, "the near half of the wall should look wider than the far half");
});

test("automap walls: an edge for every side of seen floor that faces a wall, none toward unseen floor", async () => {
  const { wallEdges } = await import("../public/render.js");
  const map = mapOf(
    "#####",
    "#...#",
    "#.#.#",
    "#####",
  );
  const at = (x, y) => y * 5 + x; // cells are keyed y * width + x, as in the game
  // Seen: the top row of floor only
  const seen = new Set([at(1, 1), at(2, 1), at(3, 1)]);
  const edges = wallEdges(map, seen).map((e) => e.join(",")).sort();
  // (x, y, side) with side 0..3 = N E S W
  assert.deepEqual(edges, ["1,1,0", "1,1,3", "2,1,0", "2,1,2", "3,1,0", "3,1,1"].sort());
});

test("the corridor layer's key: unchanged while you stand still, ticking at the flame rate only with a torch in sight", async () => {
  const { layerKey, FLAME_FPS } = await import("../public/render.js");
  const frame = 1000 / FLAME_FPS;
  assert.equal(layerKey("1,2,0", false, 0), layerKey("1,2,0", false, 99999), "no torch: one paint per position");
  assert.equal(layerKey("1,2,0", true, 1), layerKey("1,2,0", true, frame - 1), "within one flame frame");
  assert.notEqual(layerKey("1,2,0", true, 1), layerKey("1,2,0", true, frame + 1), "the next flame frame repaints");
  assert.notEqual(layerKey("1,2,0", false, 0), layerKey("1,2,1", false, 0), "turning repaints");
});

test("what you see from a spot is worked out once: faces with their decorations, and whether a torch is lit", async () => {
  const { corridorView } = await import("../public/render.js");
  const map = { ...mapOf("#####", "#...#", "#...#", "#...#", "#####"), seed: 11 };
  const v = corridorView(map, 2, 3, N);
  assert.equal(v.decor.length, v.faces.length);
  v.faces.forEach((f, i) => f.type === "stairs" && assert.equal(v.decor[i], null));
  assert.equal(v.torches, v.decor.some((d) => d?.kind === "torch"));
  assert.ok(v.cells.length > 0);
});

test("with nowhere to cache (no canvas in this runtime) the corridor paints straight into the view", async () => {
  const { drawCorridor } = await import("../public/render.js");
  globalThis.Path2D ??= class {
    moveTo() {}
    lineTo() {}
    closePath() {}
  };
  const ops = [];
  const ctx = new Proxy(
    { canvas: { width: 448, height: 288 } },
    { get: (o, k) => (k in o ? o[k] : k === "createLinearGradient" || k === "createRadialGradient" ? () => ({ addColorStop() {} }) : (...a) => ops.push(k)), set: (o, k, v) => ((o[k] = v), true) },
  );
  const map = { ...mapOf("###", "#.#", "#.#", "###"), seed: 1 };
  const cells = drawCorridor(ctx, map, 1, 2, N, 0);
  assert.ok(ops.includes("fillRect") && ops.includes("stroke"), "it drew");
  assert.ok(!ops.includes("drawImage"), "no layer to copy");
  assert.deepEqual(cells.map(String).sort(), ["1,1", "1,2"]);
});
