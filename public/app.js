const $ = (s) => document.querySelector(s);
const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const human = (id) => id.replaceAll("_", " ");
const cheb = (a, b) => Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
const pct = (p) => `${Math.round(p * 100)}%`;

const TILE = { ".": "grass", "=": "road", ",": "city", "#": "wall", G: "gate", T: "tree", "~": "water", H: "house" };
const DECOR = { T: "🌳", H: "🏠" };

let gameId = null;
let view = null;
let prevMeters = null;
let busy = false;
let tiles = [];

async function api(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
  const json = await res.json();
  if (!res.ok) throw Object.assign(new Error(json.error || res.statusText), { status: res.status });
  return json;
}

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), 2200);
}

async function newGame() {
  const r = await api("/api/new");
  gameId = r.id;
  prevMeters = null;
  $("#inspect").hidden = true;
  render(r.view, null, null);
}

async function act(action) {
  if (busy || !gameId || view?.over) return;
  busy = true;
  syncControls();
  const slow = setTimeout(() => ($("#thinking").hidden = false), 120);
  try {
    const r = await api("/api/turn", { id: gameId, action });
    if (r.notice) toast(r.notice);
    if (r.trace || !r.notice) render(r.view, r.trace, action);
  } catch (e) {
    toast(e.message);
    if (e.status === 404) await newGame();
  } finally {
    clearTimeout(slow);
    $("#thinking").hidden = true;
    busy = false;
    syncControls();
  }
}

// ---------- board ----------

function buildBoard(map) {
  const board = $("#board");
  board.innerHTML = "";
  tiles = [];
  map.forEach((row, y) =>
    [...row].forEach((ch, x) => {
      const d = document.createElement("div");
      d.className = `tile t-${TILE[ch] === "tree" ? "grass t-tree" : TILE[ch] === "house" ? "city t-house" : TILE[ch]}`;
      if (DECOR[ch]) d.textContent = DECOR[ch];
      board.append(d);
      tiles.push({ el: d, x, y, ch });
    }),
  );
  const layer = document.createElement("div");
  layer.className = "entities";
  layer.id = "entities";
  board.append(layer);
}

function place(el, x, y) {
  el.style.left = `${(x / 15) * 100}%`;
  el.style.top = `${(y / 11) * 100}%`;
}

function renderBoard(v, trace, action, hurt) {
  if (!tiles.length) buildBoard(v.map);
  const g = v.guard;
  for (const t of tiles) {
    if (t.ch === "G") t.el.classList.toggle("open", v.gateOpen);
    t.el.classList.toggle("seen", !g.yielded && t.y >= 3 && cheb(t, g) <= g.sight);
  }
  const layer = $("#entities");
  layer.innerHTML = "";
  const ent = (emoji, x, y, cls = "") => {
    const e = document.createElement("div");
    e.className = `ent ${cls}`;
    e.textContent = emoji;
    place(e, x, y);
    layer.append(e);
    return e;
  };
  for (const it of v.ground) ent(it.emoji, it.x, it.y, "item").title = it.name;
  ent(g.yielded ? "🤕" : "💂", g.x, g.y, hurt.guard ? "hit" : "").title = "Captain Jimbo";
  ent("🧑", v.player.x, v.player.y, hurt.player ? "hit" : "").title = "You";

  const bubble = (text, who, x, y, below) => {
    const b = document.createElement("div");
    b.className = `bubble ${who}${below ? " below" : ""}`;
    b.textContent = text;
    b.style.left = `${((x + 0.5) / 15) * 100}%`;
    b.style.top = `${((below ? y + 1 : y) / 11) * 100}%`;
    layer.append(b);
  };
  const said = action?.type === "say" ? action.text : null;
  const npcLine = trace?.called && !trace.line?.silent ? trace.line?.text : null;
  const close = cheb(v.player, g) <= 3;
  if (npcLine) bubble(npcLine, "npc", g.x, g.y, false);
  if (said) bubble(said, "you", v.player.x, v.player.y, !!npcLine && close && v.player.y >= g.y);
}

// ---------- HUD, controls, log ----------

function renderHud(v) {
  const p = v.player;
  $("#hp").textContent = `${p.hp}/${p.maxHp}`;
  $("#gold").textContent = p.gold;
  const inv = $("#inventory");
  inv.innerHTML = "";
  if (!p.inventory.length) {
    const s = document.createElement("span");
    s.className = "chip empty";
    s.textContent = "Nothing carried yet. Explore the fields.";
    inv.append(s);
  }
  for (const it of p.inventory) {
    const b = document.createElement("button");
    b.className = "chip";
    b.textContent = `${it.emoji} ${it.name}${it.id === "sword" && p.swordDrawn ? " (drawn)" : ""}`;
    b.onclick = () => {
      const box = $("#inspect");
      const same = !box.hidden && box.dataset.id === it.id;
      box.hidden = same;
      box.dataset.id = it.id;
      box.textContent = `${it.emoji} ${it.desc}`;
    };
    inv.append(b);
  }

  const sel = $("#offerItem");
  const opts = [];
  if (p.gold > 0) opts.push(["gold", `🪙 ${Math.min(p.gold, 10)} gold`]);
  for (const it of p.inventory) if (it.id === "flowers" || it.id === "ring") opts.push([it.id, `${it.emoji} ${it.name}`]);
  const keep = sel.value;
  sel.innerHTML = opts.length ? opts.map(([v, l]) => `<option value="${v}">${esc(l)}</option>`).join("") : "<option>nothing to offer</option>";
  if (opts.some(([v]) => v === keep)) sel.value = keep;
  sel.dataset.empty = opts.length ? "" : "1";
}

function syncControls() {
  if (!view) return;
  const p = view.player;
  const g = view.guard;
  const d = cheb(p, g);
  const off = busy || !!view.over;
  const hasItem = (id) => p.inventory.some((i) => i.id === id);
  for (const b of document.querySelectorAll("[data-move], #wait")) b.disabled = off;
  $("#sword").disabled = off || !hasItem("sword");
  $("#sword").firstChild.textContent = p.swordDrawn ? "Sheathe sword " : "Draw sword ";
  $("#attack").disabled = off || d > 1 || g.yielded;
  $("#offer").disabled = off || d > 2 || !!$("#offerItem").dataset.empty || g.yielded;
  $("#offerItem").disabled = off || !!$("#offerItem").dataset.empty;
  $("#showWrit").disabled = off || d > 2 || !hasItem("writ") || g.yielded;
  $("#showWrit").hidden = !hasItem("writ");
  $("#sayText").disabled = !!view.over;
}

function renderLog(v) {
  const log = $("#log");
  log.innerHTML = v.log.map((l) => `<li class="${l.kind}">${esc(l.text)}</li>`).join("");
  log.scrollTop = log.scrollHeight;
}

function renderOver(v) {
  const o = $("#over");
  o.hidden = !v.over;
  if (!v.over) return;
  $("#overKind").textContent = v.over.kind === "win" ? "You made it" : "Game over";
  $("#overKind").className = `over-kind ${v.over.kind}`;
  $("#overTitle").textContent = v.over.title;
  $("#overText").textContent = v.over.text;
}

// ---------- brain panel ----------

function renderMeters(v) {
  const g = v.guard;
  const row = (key, label, value, max = 100) => {
    const prev = prevMeters?.[key];
    const diff = prev === undefined ? 0 : value - prev;
    const delta = diff ? `<span class="delta ${diff > 0 ? "up" : "down"} ${key}">${diff > 0 ? "+" : ""}${diff}</span>` : "";
    return `<span class="name">${label}</span><div class="bar ${key}"><span style="width:${(value / max) * 100}%"></span></div><span class="num">${value}${delta}</span>`;
  };
  $("#meters").innerHTML =
    row("trust", "Trust", g.trust) +
    row("suspicion", "Suspicion", g.suspicion) +
    row("anger", "Anger", g.anger) +
    row("hp", "Health", g.hp, g.maxHp);
  prevMeters = { trust: g.trust, suspicion: g.suspicion, anger: g.anger, hp: g.hp };
  $("#impressions").innerHTML = g.impressions.length
    ? g.impressions.map((t) => `<li>${esc(t)}</li>`).join("")
    : "<li>Nothing yet.</li>";
}

function perceptionRows(items) {
  return items
    .map((x) => {
      if (x.type === "choice")
        return `<span>${esc(x.label)}</span><span class="tag"><code>${esc(x.value)}</code> · conf ${x.confidence.toFixed(2)}</span>`;
      const frac = x.type === "score" ? x.value / x.max : x.value;
      const hot = frac >= 0.6;
      return `<span class="${hot ? "strong" : ""}">${esc(x.label)}</span><div class="bar ${hot ? "hot" : ""}"><span style="width:${frac * 100}%"></span></div><span class="v">${x.value.toFixed(2)}</span>`;
    })
    .join("");
}

function renderTrace(trace, v) {
  const el = $("#trace");
  const raw = $("#raw");
  if (!trace) {
    el.innerHTML = `<p class="idle">Jimbo runs on plain code (patrolling) until he can see you. Step into the lit area around him, within ${v.guard.sight} tiles, and every turn becomes one Jev request: it reads your words and the situation, then picks his action and line from an approved list.</p>`;
    return;
  }
  if (!trace.called) {
    el.innerHTML = `<p class="idle">${esc(trace.reason)}</p>`;
    return;
  }
  raw.textContent = JSON.stringify(
    { precheck: trace.precheck ?? undefined, request: trace.request, answers: trace.answers },
    null,
    2,
  );
  if (trace.error) {
    el.innerHTML = `<p class="error">Jev call failed: ${esc(trace.error)}. Jimbo fell back to watching you warily.</p>`;
    return;
  }

  let html = `<p class="callmeta"><b>${trace.questionCount}</b> questions in one request · <b>${trace.ms} ms</b> · ${trace.inputTokens.toLocaleString()} tokens · ${esc(trace.model)}</p>`;

  if (trace.precheck) {
    const pc = trace.precheck;
    html += `<section><h3>Writ check · separate request first (${pc.ms} ms)</h3><div class="rows">${perceptionRows(pc.perception)}</div><p class="final">Verdict: <code>${esc(pc.verdict)}</code></p></section>`;
  }

  if (trace.perception.length) {
    html += `<section><h3>What Jev read in your message</h3><div class="rows">${perceptionRows(trace.perception)}</div></section>`;
  }

  const a = trace.action;
  html += `<section><h3>Action choice · confidence ${a.confidence.toFixed(2)}</h3><div class="rows">`;
  for (const { id, p } of a.probabilities) {
    const chosen = id === a.picked;
    html += `<span class="${chosen ? "chosen" : ""}">${esc(human(id))}</span><div class="bar ${chosen ? "hot" : ""}"><span style="width:${p * 100}%"></span></div><span class="v">${pct(p)}</span>`;
  }
  html += `</div>`;
  if (a.blocked)
    html += `<p class="policy"><b>Code policy blocked “${esc(human(a.picked))}”:</b> ${esc(a.blocked)}. Doing <b>${esc(human(a.final))}</b> instead.</p>`;
  html += `<p class="final">He does: <code>${esc(human(a.final))}</code></p></section>`;

  const l = trace.line;
  html += `<section><h3>Line from the approved list</h3>`;
  if (l.silent) html += `<p class="callmeta">He stays quiet: you said nothing new and he's repeating last turn's action (a code rule, so he doesn't nag). Jev's pick was:</p>`;
  html += `<p class="line">${esc(l.text)}</p><ul class="alts">`;
  for (const alt of l.ranked ?? []) if (alt.id !== l.id) html += `<li><span>${pct(alt.p)}</span>${esc(alt.text)}</li>`;
  html += `</ul></section>`;

  el.innerHTML = html;
}

// ---------- main render ----------

function render(v, trace, action) {
  const hurt = {
    player: view && v.player.hp < view.player.hp,
    guard: view && v.guard.hp < view.guard.hp,
  };
  if (!view || v.turn === 0) tiles = [];
  view = v;
  renderBoard(v, trace, action, hurt);
  renderHud(v);
  renderLog(v);
  renderOver(v);
  renderMeters(v);
  renderTrace(trace, v);
  syncControls();
}

// ---------- input ----------

for (const b of document.querySelectorAll("[data-move]")) b.onclick = () => act({ type: "move", dir: b.dataset.move });
$("#wait").onclick = () => act({ type: "wait" });
$("#sword").onclick = () => act({ type: "sword" });
$("#attack").onclick = () => act({ type: "attack" });
$("#offer").onclick = () => act({ type: "offer", item: $("#offerItem").value });
$("#showWrit").onclick = () => act({ type: "show_writ" });
$("#newGame").onclick = () => newGame();
$("#again").onclick = () => newGame();
$("#say").onsubmit = (e) => {
  e.preventDefault();
  const input = $("#sayText");
  const text = input.value.trim();
  if (!text || busy) return;
  input.value = "";
  act({ type: "say", text });
};

const KEYS = { arrowup: "up", w: "up", arrowdown: "down", s: "down", arrowleft: "left", a: "left", arrowright: "right", d: "right" };
document.addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.target.matches("input, select, textarea")) {
    if (e.key === "Escape") e.target.blur();
    return;
  }
  const k = e.key.toLowerCase();
  if (e.target.matches("button") && (k === " " || k === "enter")) return;
  if (KEYS[k]) {
    e.preventDefault();
    act({ type: "move", dir: KEYS[k] });
  } else if (k === "t" || k === "enter") {
    e.preventDefault();
    $("#sayText").focus();
  } else if (k === " ") {
    e.preventDefault();
    act({ type: "wait" });
  } else if (k === "q" && !$("#sword").disabled) act({ type: "sword" });
  else if (k === "f" && !$("#attack").disabled) act({ type: "attack" });
});

newGame().catch((e) => toast(`Couldn't start: ${e.message}`));
