// Monster voices: which sound a spoken line gets. Run with `npm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { SPECIES } from "../public/species.js";
import { KINDS, VOICES, classifyKind, shoutPlan } from "../public/shout.js";
import { Sfx } from "../public/sfx.js";

// Every string in a species' line banks, with where it came from.
function allLines(id) {
  const out = [];
  const walk = (o, p) => {
    if (Array.isArray(o)) o.forEach((l) => typeof l === "string" && out.push({ path: p, line: l }));
    else if (o && typeof o === "object") for (const [k, v] of Object.entries(o)) walk(v, p ? `${p}.${k}` : k);
  };
  const sp = SPECIES[id];
  walk(sp.lines, "lines");
  walk(sp.broken, "broken");
  walk(sp.reactions, "reactions");
  return out;
}
const kindOf = (id, line) => shoutPlan(line, id)?.kind ?? null;

test("the signature lines get the sound you would expect", () => {
  const cases = [
    ["goblin", "RAAH! *swings a knotted club at {target}*", "roar"],
    ["goblin", "*grunts and punches {target}*", "grunt"],
    ["goblin", "*lifts the club high and SMASHES {target}*", "roar"],
    ["goblin", "LIAR! {name} SMASH!", "roar"],
    ["goblin", "Hur hur. Talky one, eh?", "laugh"],
    ["goblin", "Hmph.", "grunt"],
    ["goblin", "Smash the smart creature! *swings at {target}*", "bark"],
    ["goblin", "What you want, tiny?", "babble"],
    ["dragon", "BURN IN MY STORM! *lightning floods the corridor*", "roar"],
    ["dragon", "*snaps its great jaws at {target}*", "growl"],
    ["dragon", "*inhales, then unleashes crackling yellow lightning over the whole party*", "zap"],
    ["dragon", "*yawns, curls up, and ignores you entirely*", "sigh"],
    ["dragon", "Ha! Wit, from a mortal. How rare.", "laugh"],
    ["snake", "*raises its hood and hisses a warning*", "hiss"],
    ["snake", "Hold ssstill, little one. *bites {target}*", "hiss"],
    ["snake", "Clever. Very clever.", "babble"],
    ["slime", "...bloop?", "squelch"],
    ["slime", "*splorts orange goo all over {target}*", "squelch"],
    ["slime", "*jiggles* ...hehe. funny.", "laugh"],
    ["slime", "LIAR! *lunges at the party*", "squeal"],
    ["slime", "*trembles* ...no like.", "whimper"],
    ["rock", "*the ceiling groans... and a rockslide pours down on the party*", "rumble"],
    ["rock", "...MOVE. *slams into {target}*", "rumble"],
    ["rock", "...hmm.", "rumble"],
    ["bandit", "Nothin' personal! *slashes at {target}*", "bark"],
    ["bandit", "*darts in with a knife at {target}*", "grunt"],
    ["bandit", "Ha! Nice work!", "laugh"],
  ];
  for (const [id, line, want] of cases) assert.equal(kindOf(id, line), want, `${id}: ${line}`);
});

test("every attack, special and fight line in species.js makes a sound", () => {
  for (const id of Object.keys(SPECIES))
    for (const { path, line } of allLines(id))
      if (/^lines\.(attack|special|attack_monster)$|^broken\.attack_party$|^reactions\.betray$/.test(path)) assert.ok(kindOf(id, line), `${id} ${path}: ${line}`);
});

test("every line classifies to a known kind, and only a wordless stage direction is silent", () => {
  let sounds = 0;
  let total = 0;
  for (const id of Object.keys(SPECIES))
    for (const { path, line } of allLines(id)) {
      const plan = shoutPlan(line, id);
      total++;
      if (plan) {
        sounds++;
        assert.ok(KINDS.includes(plan.kind), `${id} ${path}: ${plan.kind}`);
        assert.ok(plan.f0 > 20 && plan.vol > 0 && plan.vol <= 1.2 && plan.syll >= 2 && plan.syll <= 6, `${id}: ${line}`);
      } else {
        const spoken = line.replace(/\*[^*]*\*/g, " ").replace(/\{[^}]*\}/g, " ");
        assert.ok(!/[a-z]{2,}/i.test(spoken), `silent line has words: ${id} ${path}: ${line}`);
      }
    }
  assert.ok(sounds / total > 0.85, `${sounds}/${total} lines make a sound`);
});

test("each species keeps its own voice: dragons deep, goblins mid, slimes high and wet", () => {
  const plan = (id) => shoutPlan("Hello there, traveller.", id);
  assert.ok(plan("dragon").f0 < plan("goblin").f0);
  assert.ok(plan("goblin").f0 < plan("slime").f0);
  assert.ok(plan("rock").f0 < plan("dragon").f0);
  assert.ok(plan("dragon").size < plan("slime").size, "dragon formants sit lower (a bigger throat)");
  assert.equal(plan("slime").wet, true);
  assert.equal(plan("goblin").wet, false);
  // a wordless emote falls back to the species' own noise
  assert.equal(kindOf("slime", "*lunges at {target}*"), "squelch");
  assert.equal(kindOf("dragon", "*lunges at {target}*"), "growl");
  assert.equal(kindOf("snake", "*lunges at {target}*"), "hiss");
  assert.equal(kindOf("rock", "*lunges at {target}*"), "rumble");
  assert.equal(kindOf("goblin", "*lunges at {target}*"), "grunt");
  // a boss is deeper than the rest of its kind
  const boss = shoutPlan("RAAH!", "goblin", { boss: true });
  assert.ok(boss.f0 < shoutPlan("RAAH!", "goblin").f0 && boss.vol > shoutPlan("RAAH!", "goblin").vol);
});

test("free text from Jev: loose spellings, other languages, junk and huge input all land somewhere sane", () => {
  const free = [
    ["RAAAAAAH!!!", "roar"],
    ["*ROARS*", "roar"],
    ["Grrrrr... you dare?", "growl"],
    ["*growls low in its throat*", "growl"],
    ["Muahahaha! Foolish mortals!", "laugh"],
    ["*cackles madly*", "laugh"],
    ["Hehehe", "laugh"],
    ["*snorts*", "grunt"],
    ["Hissss...", "hiss"],
    ["Yessss, my preciousss", "hiss"],
    ["*SQUELCH*", "squelch"],
    ["BLORP", "squelch"],
    ["Gloop gloop", "squelch"],
    ["Aaaaaah!", "squeal"],
    ["*shrieks*", "squeal"],
    ["*whimpers*", "whimper"],
    ["*sighs heavily*", "sigh"],
    ["*rumbles ominously*", "rumble"],
    ["Hello, adventurer.", "babble"],
    ["Stop right there!", "bark"],
    ["YOU SHALL NOT PASS!", "roar"],
  ];
  for (const [line, want] of free) assert.equal(kindOf("goblin", line), want, line);
  // junk never throws and never plays
  for (const junk of [undefined, null, 42, {}, [], "", "   ", "...", "*stares blankly*", "{name}", "{target} {name}", "!!!", "*", "**", "🙂"]) {
    assert.doesNotThrow(() => shoutPlan(junk, "goblin"));
  }
  for (const silent of [undefined, null, 42, "", "...", "{name}", "*stares blankly*"]) assert.equal(shoutPlan(silent, "goblin"), null, String(silent));
  // an unknown species still gets a default voice; a huge line is cheap and capped
  assert.equal(shoutPlan("RAAH!", "beholder").species, "other");
  assert.ok(shoutPlan("RAAH!", undefined).f0 > 0);
  const huge = "blah ".repeat(20000);
  const t0 = performance.now();
  const p = shoutPlan(huge, "dragon");
  assert.ok(performance.now() - t0 < 50);
  assert.ok(p.syll <= 6);
  assert.equal(classifyKind("ROAR ".repeat(5000)), "roar");
});

test("the first vocal word wins, shouting beats a plain effect word, and placeholders are ignored", () => {
  assert.equal(classifyKind("*blank stare* ...blorp. *lunges*"), "squelch");
  assert.equal(classifyKind("Ssso. RAAH!"), "hiss");
  assert.equal(classifyKind("*stomps* Out of my way!"), "bark");
  assert.equal(classifyKind("BURN! *crackling lightning*"), "big");
  assert.equal(classifyKind("{target} {name}"), null);
  assert.equal(classifyKind("Oi! That's OUR gold you're wastin'!"), "big");
});

test("Sfx.shout respects the O toggle, plays once per monster per burst, and survives silent lines", () => {
  const sfx = new Sfx();
  const played = [];
  sfx.ctx = { state: "running", currentTime: 0 };
  sfx.play = (name, opt) => played.push([name, opt.kind]);
  assert.equal(sfx.shout("RAAH! *swings*", "goblin", { key: "e1" })?.kind, "roar");
  assert.equal(sfx.shout("RAAH again!", "goblin", { key: "e1" }), null, "same monster, same instant: one shout only");
  assert.equal(sfx.shout("*hisses*", "snake", { key: "e2" })?.kind, "hiss", "another monster speaks fine");
  sfx.ctx.currentTime = 1;
  assert.equal(sfx.shout("Hmph.", "goblin", { key: "e1" })?.kind, "grunt", "a second later it may speak again");
  assert.equal(sfx.shout("...", "goblin", { key: "e3" }), null);
  sfx.toggle();
  assert.equal(sfx.shout("RAAH!", "goblin", { key: "e9" }), null, "sound off: no shout");
  assert.deepEqual(played.map((p) => p[1]), ["roar", "hiss", "grunt"]);
  assert.deepEqual(played.map((p) => p[0]), ["voice_roar", "voice_hiss", "voice_grunt"]);
  const cold = new Sfx(); // audio never started (no key press yet)
  assert.equal(cold.shout("RAAH!", "goblin"), null);
});

test("every voice kind has a synth that drives the primitives, wet or dry", () => {
  for (const k of KINDS)
    for (const wet of [false, true]) {
      const prims = [];
      const sfx = new Sfx();
      sfx.ctx = { state: "running", currentTime: 0 };
      for (const m of ["tone", "noise", "vocal", "arp"]) sfx[m] = (_at, o) => prims.push([m, o]);
      sfx.play(`voice_${k}`, { f0: 100, size: 1, rasp: 0.3, wet, vol: 1, syll: 3 });
      assert.ok(prims.length > 0, `${k} makes no sound`);
      for (const [, o] of prims) if (o?.vol !== undefined) assert.ok(Number.isFinite(o.vol) && o.vol > 0, `${k} vol`);
    }
  for (const [id, v] of Object.entries(VOICES)) {
    assert.ok(v.f0 > 20 && v.size > 0 && KINDS.includes(v.big) && KINDS.includes(v.emote), id);
    for (const to of Object.values(v.remap)) assert.ok(KINDS.includes(to), `${id} remaps to ${to}`);
  }
});
