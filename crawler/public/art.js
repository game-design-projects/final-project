// Monochrome line-art monsters, drawn on a 448x288 canvas. One color each, no fills.

import { SPECIES } from "./species.js";

function path(ctx, pts, close = false) {
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (const [x, y] of pts.slice(1)) ctx.lineTo(x, y);
  if (close) ctx.closePath();
  ctx.stroke();
}

function circle(ctx, x, y, r) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.stroke();
}

function dot(ctx, x, y, r = 2) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}

// Orange slime: a wobbling dome with a blank, unblinking stare.
function slime(ctx, t) {
  const wob = Math.sin(t / 380) * 4;
  ctx.save();
  ctx.translate(224, 236);
  ctx.scale(1 + wob / 200, 1 - wob / 160);
  ctx.translate(-224, -236);
  ctx.beginPath();
  ctx.moveTo(136, 236);
  ctx.bezierCurveTo(128, 160, 172, 96, 224, 96);
  ctx.bezierCurveTo(276, 96, 320, 160, 312, 236);
  ctx.bezierCurveTo(292, 244, 272, 230, 252, 240);
  ctx.bezierCurveTo(232, 250, 212, 232, 192, 240);
  ctx.bezierCurveTo(172, 248, 154, 238, 136, 236);
  ctx.stroke();
  // shine
  ctx.beginPath();
  ctx.arc(224, 190, 76, Math.PI * 1.18, Math.PI * 1.36);
  ctx.stroke();
  // drips
  path(ctx, [[170, 243], [170, 256]]);
  circle(ctx, 170, 260, 3);
  path(ctx, [[262, 238], [262, 250]]);
  circle(ctx, 262, 254, 2.5);
  // the blank stare: big empty eyes with pinprick pupils dead center
  circle(ctx, 196, 162, 14);
  circle(ctx, 252, 162, 14);
  dot(ctx, 196, 162, 1.8);
  dot(ctx, 252, 162, 1.8);
  path(ctx, [[214, 200], [234, 200]]);
  ctx.restore();
  // puddle
  ctx.beginPath();
  ctx.ellipse(224, 252, 104, 9, 0, 0, Math.PI * 2);
  ctx.stroke();
}

// Huge brown goblin: fills the corridor, club raised.
function goblin(ctx, t) {
  const sway = Math.sin(t / 700) * 2;
  ctx.save();
  ctx.translate(sway, 0);
  // head
  path(ctx, [[176, 64], [200, 44], [248, 44], [272, 64], [282, 100], [276, 134], [258, 158], [224, 168], [190, 158], [172, 134], [166, 100]], true);
  // ears
  path(ctx, [[168, 86], [94, 58], [170, 118]]);
  path(ctx, [[280, 86], [354, 58], [278, 118]]);
  path(ctx, [[150, 82], [120, 72]]);
  path(ctx, [[298, 82], [328, 72]]);
  // brow and beady eyes
  path(ctx, [[184, 88], [214, 98]]);
  path(ctx, [[234, 98], [264, 88]]);
  circle(ctx, 202, 106, 5);
  circle(ctx, 246, 106, 5);
  dot(ctx, 202, 106, 2);
  dot(ctx, 246, 106, 2);
  // hooked nose
  path(ctx, [[224, 106], [214, 128], [232, 130]]);
  // grin with jagged teeth
  path(ctx, [[184, 138], [206, 148], [242, 148], [264, 138]]);
  path(ctx, [[192, 141], [197, 132], [202, 145], [210, 134], [216, 148], [224, 136], [232, 148], [238, 134], [246, 145], [251, 132], [256, 141]]);
  // shoulders and body
  path(ctx, [[196, 162], [150, 172], [62, 196], [34, 288]]);
  path(ctx, [[252, 162], [298, 172], [376, 190], [398, 214]]);
  path(ctx, [[120, 288], [132, 226], [150, 206]]);
  path(ctx, [[328, 288], [316, 226], [300, 208]]);
  // potato-sack tunic: gathered drawstring neck, rope belt, patches, frayed hem
  path(ctx, [[176, 180], [186, 186], [196, 179], [206, 187], [216, 179], [226, 187], [236, 179], [246, 187], [256, 179], [266, 186], [274, 180]]);
  path(ctx, [[176, 180], [158, 212], [148, 266]]);
  path(ctx, [[274, 180], [292, 212], [302, 266]]);
  path(ctx, [[148, 266], [156, 276], [166, 266], [176, 278], [188, 266], [200, 277], [212, 266], [224, 278], [236, 266], [248, 277], [260, 266], [272, 278], [284, 266], [294, 276], [302, 266]]);
  path(ctx, [[188, 196], [262, 196]]); // printed stripes
  path(ctx, [[184, 208], [266, 208]]);
  path(ctx, [[152, 232], [224, 238], [298, 232]]); // rope belt
  path(ctx, [[151, 240], [224, 246], [299, 240]]);
  circle(ctx, 224, 242, 6);
  path(ctx, [[220, 248], [214, 262]]);
  path(ctx, [[228, 248], [234, 262]]);
  path(ctx, [[176, 248], [198, 248], [198, 262], [176, 262]], true); // patch
  path(ctx, [[180, 245], [180, 251]]);
  path(ctx, [[194, 245], [194, 251]]);
  path(ctx, [[252, 208], [270, 208], [270, 222], [252, 222]], true); // patch
  path(ctx, [[256, 205], [256, 211]]);
  path(ctx, [[266, 205], [266, 211]]);
  // right arm raised with a knotted club
  path(ctx, [[398, 214], [414, 162], [408, 132]]);
  path(ctx, [[376, 190], [392, 158], [390, 134]]);
  circle(ctx, 400, 126, 13);
  path(ctx, [[392, 118], [384, 44], [398, 14], [428, 18], [440, 50], [410, 118]], true);
  circle(ctx, 404, 50, 5);
  circle(ctx, 424, 34, 4);
  circle(ctx, 402, 88, 4);
  // left fist
  circle(ctx, 42, 276, 14);
  ctx.restore();
}

// Yellow dragon: wings spread, horned head, coiled tail.
function dragon(ctx, t) {
  const flap = Math.sin(t / 600) * 6;
  // wings
  path(ctx, [[196, 160], [140, 90 - flap], [60, 40 - flap], [72, 110], [30, 150], [88, 144], [70, 190], [124, 168], [118, 210], [170, 182]]);
  path(ctx, [[140, 90 - flap], [88, 144]]);
  path(ctx, [[140, 90 - flap], [124, 168]]);
  path(ctx, [[252, 160], [308, 90 - flap], [388, 40 - flap], [376, 110], [418, 150], [360, 144], [378, 190], [324, 168], [330, 210], [278, 182]]);
  path(ctx, [[308, 90 - flap], [360, 144]]);
  path(ctx, [[308, 90 - flap], [324, 168]]);
  // body
  ctx.beginPath();
  ctx.ellipse(224, 212, 66, 44, 0, 0, Math.PI * 2);
  ctx.stroke();
  path(ctx, [[196, 190], [206, 226], [224, 236], [242, 226], [252, 190]]); // belly plates
  path(ctx, [[204, 206], [244, 206]]);
  path(ctx, [[210, 222], [238, 222]]);
  // neck
  path(ctx, [[204, 176], [210, 140], [214, 114]]);
  path(ctx, [[244, 176], [238, 140], [234, 114]]);
  // head
  path(ctx, [[208, 112], [198, 84], [210, 66], [238, 66], [250, 84], [240, 112], [232, 126], [216, 126]], true);
  path(ctx, [[206, 70], [182, 30], [214, 64]]); // horns
  path(ctx, [[242, 70], [266, 30], [234, 64]]);
  path(ctx, [[208, 86], [218, 84]]); // slit eyes
  path(ctx, [[230, 84], [240, 86]]);
  dot(ctx, 218, 118, 1.8);
  dot(ctx, 230, 118, 1.8);
  path(ctx, [[212, 112], [216, 106], [220, 112], [224, 106], [228, 112], [232, 106], [236, 112]]); // teeth
  // legs and claws
  path(ctx, [[180, 240], [170, 262], [160, 270]]);
  path(ctx, [[170, 262], [170, 274]]);
  path(ctx, [[170, 262], [182, 272]]);
  path(ctx, [[268, 240], [278, 262], [288, 270]]);
  path(ctx, [[278, 262], [278, 274]]);
  path(ctx, [[278, 262], [266, 272]]);
  // tail
  ctx.beginPath();
  ctx.moveTo(284, 228);
  ctx.bezierCurveTo(350, 262, 404, 262, 414, 226);
  ctx.stroke();
  path(ctx, [[406, 232], [428, 214], [418, 240]], true);
}

function ellipse(ctx, x, y, rx, ry) {
  ctx.beginPath();
  ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2);
  ctx.stroke();
}

// Green snake person: a hooded serpent torso rising from its coils, tongue flicking.
function snake(ctx, t) {
  const sway = Math.sin(t / 500) * 4;
  ellipse(ctx, 224, 252, 112, 18);
  ellipse(ctx, 224, 236, 90, 15);
  ellipse(ctx, 230, 222, 66, 12);
  path(ctx, [[322, 254], [354, 248], [374, 236], [380, 222], [370, 214]]); // tail tip
  ctx.save();
  ctx.translate(sway, 0);
  path(ctx, [[202, 222], [196, 190], [204, 160], [212, 140]]); // body rising
  path(ctx, [[254, 222], [252, 190], [244, 160], [236, 140]]);
  for (const y of [208, 192, 176, 160]) path(ctx, [[204, y], [224, y + 6], [248, y]]); // belly scales
  path(ctx, [[212, 140], [184, 132], [170, 140]]); // shoulders
  path(ctx, [[236, 140], [264, 132], [278, 140]]);
  path(ctx, [[172, 140], [150, 170], [156, 196]]); // clawed arms
  path(ctx, [[156, 196], [148, 206]]);
  path(ctx, [[156, 196], [156, 208]]);
  path(ctx, [[156, 196], [164, 206]]);
  path(ctx, [[276, 140], [300, 166], [294, 194]]);
  path(ctx, [[294, 194], [286, 204]]);
  path(ctx, [[294, 194], [294, 206]]);
  path(ctx, [[294, 194], [302, 204]]);
  path(ctx, [[214, 132], [216, 118]]); // neck
  path(ctx, [[234, 132], [232, 118]]);
  path(ctx, [[216, 118], [190, 104], [180, 80], [194, 56], [224, 46], [254, 56], [268, 80], [258, 104], [232, 118]]); // cobra hood
  path(ctx, [[196, 70], [206, 86]]); // hood markings
  path(ctx, [[252, 70], [242, 86]]);
  path(ctx, [[210, 96], [210, 74], [224, 64], [238, 74], [238, 96], [224, 106]], true); // head
  path(ctx, [[213, 82], [221, 84]]); // slit eyes
  path(ctx, [[227, 84], [235, 82]]);
  dot(ctx, 217, 83, 1.6);
  dot(ctx, 231, 83, 1.6);
  if (Math.sin(t / 220) > 0.2) {
    path(ctx, [[224, 106], [224, 118], [218, 124]]); // forked tongue
    path(ctx, [[224, 118], [230, 124]]);
  }
  ctx.restore();
}

// Grey rock entity: a living heap of boulders with one glowing crack for an eye.
function rock(ctx, t) {
  const breathe = Math.sin(t / 900) * 2;
  path(ctx, [[96, 264], [352, 264]]); // ground
  path(ctx, [[150, 264], [160, 256], [172, 264]]); // pebbles
  path(ctx, [[272, 264], [284, 255], [296, 264]]);
  ctx.save();
  ctx.translate(0, breathe);
  path(ctx, [[142, 252], [128, 202], [146, 152], [178, 120], [224, 106], [272, 118], [304, 150], [320, 200], [308, 252]], true); // body
  path(ctx, [[200, 142], [212, 168], [204, 190], [218, 214]]); // cracks
  path(ctx, [[278, 152], [264, 178], [272, 202]]);
  path(ctx, [[162, 200], [182, 212], [176, 230]]);
  dot(ctx, 250, 230, 2);
  dot(ctx, 190, 238, 2);
  dot(ctx, 286, 228, 2);
  path(ctx, [[190, 120], [184, 88], [204, 62], [238, 58], [262, 80], [262, 114]], true); // head
  path(ctx, [[198, 90], [210, 84], [218, 92], [230, 82], [242, 90], [252, 86]]); // glowing crack eye
  path(ctx, [[204, 94], [216, 98], [230, 92], [244, 96]]);
  path(ctx, [[134, 160], [104, 168], [92, 202], [112, 216], [132, 202]], true); // left arm
  path(ctx, [[96, 214], [84, 242], [100, 260], [124, 252], [120, 222]], true);
  path(ctx, [[314, 160], [344, 168], [356, 202], [336, 216], [316, 202]], true); // right arm
  path(ctx, [[352, 214], [364, 242], [348, 260], [324, 252], [328, 222]], true);
  ctx.restore();
}

// Red bandit: hooded, masked, a knife in each hand.
function bandit(ctx, t) {
  const shift = Math.sin(t / 450) * 3;
  ctx.save();
  ctx.translate(shift, 0);
  path(ctx, [[224, 38], [190, 66], [176, 106], [184, 138]]); // hood
  path(ctx, [[224, 38], [258, 66], [272, 106], [264, 138]]);
  ellipse(ctx, 224, 98, 26, 32); // face opening
  path(ctx, [[208, 90], [218, 88]]); // narrowed eyes
  path(ctx, [[230, 88], [240, 90]]);
  dot(ctx, 213, 90, 1.8);
  dot(ctx, 235, 90, 1.8);
  path(ctx, [[199, 104], [249, 104]]); // bandana mask
  path(ctx, [[200, 104], [206, 122], [224, 128], [242, 122], [248, 104]]);
  path(ctx, [[249, 106], [268, 112], [262, 122]]); // knot tails
  path(ctx, [[249, 106], [272, 104]]);
  path(ctx, [[184, 138], [150, 150], [130, 190], [124, 262]]); // cloak
  path(ctx, [[264, 138], [298, 150], [318, 190], [324, 262]]);
  path(ctx, [[124, 262], [140, 254], [152, 264], [166, 254], [180, 262]]); // ragged hem
  path(ctx, [[268, 262], [282, 254], [296, 264], [310, 254], [324, 262]]);
  path(ctx, [[198, 140], [224, 170], [250, 140]]); // tunic neck
  path(ctx, [[190, 146], [194, 252]]);
  path(ctx, [[258, 146], [254, 252]]);
  path(ctx, [[188, 204], [260, 204]]); // belt
  path(ctx, [[188, 212], [260, 212]]);
  path(ctx, [[216, 202], [232, 202], [232, 214], [216, 214]], true); // buckle
  path(ctx, [[240, 214], [256, 214], [256, 230], [240, 230]], true); // coin pouch
  path(ctx, [[202, 252], [198, 270]]); // legs
  path(ctx, [[246, 252], [250, 270]]);
  path(ctx, [[150, 150], [140, 190], [158, 212]]); // left arm, knife forward
  circle(ctx, 162, 214, 6);
  path(ctx, [[166, 208], [194, 184]]);
  path(ctx, [[160, 200], [172, 212]]);
  path(ctx, [[298, 150], [322, 128], [332, 100]]); // right arm, knife raised
  circle(ctx, 334, 96, 6);
  path(ctx, [[338, 90], [352, 60]]);
  path(ctx, [[328, 88], [344, 96]]);
  ctx.restore();
}

// Shiny variants twinkle: little four-point glints around the monster.
const GLINTS = [[-120, -40], [118, -70], [-60, -120], [140, 30], [-140, 40], [60, -10]];
function glints(ctx, t) {
  GLINTS.forEach(([dx, dy], i) => {
    const on = Math.sin(t / 260 + i * 1.7);
    if (on < 0.35) return;
    const r = 4 + on * 6;
    const x = 224 + dx;
    const y = 160 + dy;
    path(ctx, [[x - r, y], [x + r, y]]);
    path(ctx, [[x, y - r], [x, y + r]]);
  });
}

export const SHINY_COLOR = "#f5b72a";
export const BOSS_COLOR = "#ff2a2a";

const DRAW = { slime, goblin, dragon, snake, rock, bandit };

// How jagged the monsters look. 1 = smooth vector lines (the game's look); 2–4 = drawn at 1/N resolution
// with no anti-aliasing, then scaled up with hard edges, like the stair-stepped lines of early dungeon crawlers.
export const ART = { pixel: 1 };

function drawVector(ctx, species, t, hurt, slot, lineWidth, look) {
  const color = look.color ?? (look.shiny ? SHINY_COLOR : SPECIES[species].color);
  ctx.save();
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = lineWidth;
  ctx.lineJoin = "round";
  // slot.by moves the monster's feet up from the bottom of the view (to stand further down a corridor)
  ctx.translate(slot.cx - 224 * slot.s, (slot.by ?? 284) - 284 * slot.s);
  ctx.scale(slot.s, slot.s);
  if (hurt > 0) ctx.translate(Math.sin(t / 20) * hurt * 6, 0);
  DRAW[species](ctx, t);
  if (look.shiny) glints(ctx, t);
  ctx.restore();
}

const low = typeof document !== "undefined" ? document.createElement("canvas") : null;

// `slot` places a monster when several share the view: cx is its center, s its scale (bottoms stay aligned).
// `look.shiny` draws the rare gold variant with glints.
export function drawMonster(ctx, species, t, hurt = 0, slot = { cx: 224, s: 1 }, pixel = ART.pixel, look = {}) {
  if (pixel <= 1) return drawVector(ctx, species, t, hurt, slot, 2 / Math.max(slot.s, 0.6), look);
  const { width: W, height: H } = ctx.canvas;
  const w = Math.ceil(W / pixel);
  const h = Math.ceil(H / pixel);
  if (low.width !== w || low.height !== h) Object.assign(low, { width: w, height: h });
  const o = low.getContext("2d", { willReadFrequently: true });
  o.clearRect(0, 0, w, h);
  o.save();
  o.scale(1 / pixel, 1 / pixel);
  // One low-res pixel wide, whatever the slot's scale
  drawVector(o, species, t, hurt, slot, pixel / slot.s, look);
  o.restore();
  // Snap every pixel fully on or off: no anti-aliasing, so diagonals become stair-steps
  const img = o.getImageData(0, 0, w, h);
  const d = img.data;
  const [r, g, b] = hexToRgb(look.color ?? (look.shiny ? SHINY_COLOR : SPECIES[species].color));
  for (let i = 0; i < d.length; i += 4) {
    if (d[i + 3] >= 90) {
      d[i] = r;
      d[i + 1] = g;
      d[i + 2] = b;
      d[i + 3] = 255;
    } else d[i + 3] = 0;
  }
  o.putImageData(img, 0, 0);
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(low, 0, 0, w, h, 0, 0, w * pixel, h * pixel);
  ctx.restore();
}

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export const SLOTS = {
  1: [{ cx: 224, s: 1 }],
  2: [{ cx: 116, s: 0.6 }, { cx: 332, s: 0.6 }],
  3: [{ cx: 76, s: 0.46 }, { cx: 224, s: 0.46 }, { cx: 372, s: 0.46 }],
};
