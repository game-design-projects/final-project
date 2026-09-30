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
  path(ctx, [[176, 234], [224, 246], [272, 234]]); // belly
  path(ctx, [[150, 272], [224, 284], [298, 272]]);
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

const DRAW = { slime, goblin, dragon };

export function drawMonster(ctx, species, t, hurt = 0) {
  ctx.save();
  ctx.strokeStyle = SPECIES[species].color;
  ctx.fillStyle = SPECIES[species].color;
  ctx.lineWidth = 2;
  ctx.lineJoin = "round";
  if (hurt > 0) ctx.translate(Math.sin(t / 20) * hurt * 6, 0);
  DRAW[species](ctx, t);
  ctx.restore();
}
