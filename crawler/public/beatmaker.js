import { Music, INSTRUMENTS, DRUMS, CHORDS, TRACKS, IN_KEY, emptyPattern, normalize, loadTheme, loadSavedSong } from "./music.js";

const $ = (s) => document.querySelector(s);
const music = new Music();
const LENGTHS = [[0, "UNTIL NEXT"], [1, "1/16"], [2, "1/8"], [3, "DOTTED 1/8"], [4, "1/4"], [8, "1/2"]];
let P;
let playing = false;
let page = 0; // which 8 bars of a long song the grid shows
const PAGE_BARS = 8;

// Change the number of bars, keeping what fits (or repeating the pattern to fill new bars)
function resize(p, bars) {
  const steps = bars * 16;
  const fit = (arr, empty) => Array.from({ length: steps }, (_, i) => arr[i % arr.length] ?? empty);
  const out = { ...p, bars, chords: Array.from({ length: bars }, (_, i) => p.chords[i % p.chords.length]) };
  out.drums = Object.fromEntries(Object.entries(p.drums).map(([d, a]) => [d, fit(a, 0)]));
  for (const t of Object.keys(TRACKS)) out[t] = fit(p[t], null);
  out.layers = (p.layers ?? []).map((l) => ({ ...l, events: l.events.filter(([s]) => s < steps) }));
  return out;
}

function save() {
  try {
    localStorage.setItem("hallsOfJev.beat4", JSON.stringify(P));
  } catch {}
  if (playing) music.setPattern(P);
}

function status(t) {
  $("#status").textContent = t;
  clearTimeout(status.t);
  status.t = setTimeout(() => ($("#status").textContent = ""), 3500);
}

const cellClass = (i) => `cell${i % 4 === 0 ? " beat" : ""}${i % 16 === 0 && i > 0 ? " bar" : ""}`;
const instrumentSelect = (track, bass) =>
  `<select data-inst="${track}">${Object.entries(INSTRUMENTS)
    .filter(([, v]) => !!v.bass === bass)
    .map(([id, v]) => `<option value="${id}" ${P.instruments[track] === id ? "selected" : ""}>${v.label}</option>`)
    .join("")}</select>`;
const lengthSelect = (track) =>
  `<select data-len="${track}">${LENGTHS.map(([v, l]) => `<option value="${v}" ${P[`${track}Len`] === v ? "selected" : ""}>${l}</option>`).join("")}</select>`;

function build() {
  $("#bpm").value = P.bpm;
  $("#bpmv").textContent = P.bpm;
  $("#bars").value = String(P.bars);
  $("#pad").checked = P.pad;
  $("#padInst").innerHTML = instrumentSelect("pad", false);
  const pages = Math.ceil(P.bars / PAGE_BARS);
  page = Math.min(page, pages - 1);
  const first = page * PAGE_BARS;
  const shown = Math.min(PAGE_BARS, P.bars - first);
  $("#page").innerHTML = Array.from({ length: pages }, (_, i) => `<option value="${i}" ${i === page ? "selected" : ""}>BARS ${i * PAGE_BARS + 1}–${Math.min(P.bars, (i + 1) * PAGE_BARS)}</option>`).join("");
  $("#pageWrap").hidden = pages < 2;
  $("#chords").innerHTML = P.chords
    .slice(first, first + shown)
    .map((c, j) => `<select data-bar="${first + j}">${Object.keys(CHORDS).map((k) => `<option ${k === c ? "selected" : ""}>${k}</option>`).join("")}</select>`)
    .join("");
  renderLayers();

  const startStep = first * 16;
  const steps = shown * 16;
  const row = (label, track, value, cls, dim) =>
    `<div class="row${dim ? " out" : ""}"><label class="track">${label}</label><div class="cells">${Array.from({ length: steps }, (_, j) => {
      const i = startStep + j;
      const on = DRUMS[track] ? !!P.drums[track][i] : P[track][i] === value;
      return `<button class="${cellClass(j)} ${cls}${on ? " on" : ""}" data-track="${track}" data-step="${i}"${value ? ` data-note="${value}"` : ""} aria-label="${label} step ${i + 1}"></button>`;
    }).join("")}</div></div>`;

  $("#drums").innerHTML = Object.entries(DRUMS).map(([d, def]) => row(def.label, d, undefined, "drum")).join("");
  for (const [t, def] of Object.entries(TRACKS)) {
    $(`#${t}Head`).innerHTML = `${def.label} ${instrumentSelect(t, t === "bass")} ${lengthSelect(t)}`;
    $(`#${t}`).innerHTML = def
      .rows()
      .map((n) => row(n, t, n, t, !IN_KEY.has(n.replace(/-?\d+$/, ""))))
      .join("");
  }
  $("#mix").innerHTML = Object.keys(P.volumes)
    .map((k) => `<label>${(DRUMS[k]?.label ?? k).toUpperCase()} <input type="range" min="0" max="1" step="0.01" value="${P.volumes[k]}" data-vol="${k}" /></label>`)
    .join("");
}

// Score layers (e.g. the arranged symphony): pick an instrument, set volume, or mute each one.
function renderLayers() {
  const box = $("#layers");
  box.hidden = !P.layers.length;
  $("#layerList").innerHTML = P.layers
    .map(
      (l, i) => `<div class="layer"><label><input type="checkbox" data-mute="${i}" ${l.muted ? "" : "checked"} /> ${l.label ?? l.id}</label>
        <select data-layer-inst="${i}">${Object.entries(INSTRUMENTS)
          .map(([id, v]) => `<option value="${id}" ${l.instrument === id ? "selected" : ""}>${v.label}</option>`)
          .join("")}</select>
        <input type="range" min="0" max="1" step="0.01" value="${l.volume ?? 0.3}" data-layer-vol="${i}" aria-label="${l.label ?? l.id} volume" /></div>`,
    )
    .join("");
}

document.addEventListener("click", (ev) => {
  const c = ev.target.closest(".cell");
  if (!c) return;
  const { track, step, note } = c.dataset;
  const i = Number(step);
  if (DRUMS[track]) P.drums[track][i] = P.drums[track][i] ? 0 : 1;
  else P[track][i] = P[track][i] === note ? null : note; // one note per step per track
  document.querySelectorAll(`.cell[data-track="${track}"][data-step="${i}"]`).forEach((b) => {
    b.classList.toggle("on", DRUMS[track] ? !!P.drums[track][i] : P[track][i] === b.dataset.note);
  });
  // Hear what you placed
  if (!playing && (DRUMS[track] ? P.drums[track][i] : P[track][i])) music.preview(track, note, P.instruments[track]);
  save();
});

document.addEventListener("input", (ev) => {
  const t = ev.target;
  if (t.dataset.vol) {
    P.volumes[t.dataset.vol] = Number(t.value);
    return save();
  }
  if (t.dataset.layerVol) {
    P.layers[Number(t.dataset.layerVol)].volume = Number(t.value);
    return save();
  }
  if (t.id === "bpm") {
    P.bpm = Number(t.value);
    $("#bpmv").textContent = P.bpm;
    return save();
  }
});

document.addEventListener("change", (ev) => {
  const t = ev.target;
  if (t.dataset.bar) P.chords[Number(t.dataset.bar)] = t.value;
  else if (t.dataset.mute) P.layers[Number(t.dataset.mute)].muted = !t.checked;
  else if (t.dataset.layerInst) P.layers[Number(t.dataset.layerInst)].instrument = t.value;
  else if (t.id === "page") {
    page = Number(t.value);
    return build();
  }
  else if (t.dataset.inst) P.instruments[t.dataset.inst] = t.value;
  else if (t.dataset.len) P[`${t.dataset.len}Len`] = Number(t.value);
  else if (t.id === "bars") {
    P = resize(P, Number(t.value));
    build();
  } else if (t.id === "pad") P.pad = t.checked;
  save();
});

$("#play").onclick = async () => {
  if (playing) {
    music.stop();
    playing = false;
    $("#play").textContent = "▶ PLAY";
    document.querySelectorAll(".playing").forEach((c) => c.classList.remove("playing"));
    return;
  }
  $("#play").textContent = "LOADING...";
  await music.start(P);
  playing = true;
  $("#play").textContent = "■ STOP";
};

let lastCol = [];
music.onStep = (s) => {
  lastCol.forEach((c) => c.classList.remove("playing"));
  lastCol = [...document.querySelectorAll(`.cell[data-step="${s}"]`)];
  lastCol.forEach((c) => c.classList.add("playing"));
};

$("#theme").onclick = async () => {
  P = await loadTheme();
  page = 0;
  build();
  save();
  status("LOADED THE BUILT-IN THEME");
};
$("#clear").onclick = () => {
  P = emptyPattern(P.bars);
  build();
  save();
};
$("#copy").onclick = async () => {
  try {
    await navigator.clipboard.writeText(JSON.stringify(P));
    status("COPIED. PASTE IT TO CLAUDE IF YOU LIKE");
  } catch {
    status("COPY FAILED");
  }
};
$("#save").onclick = async () => {
  try {
    const r = await fetch("/api/dev/song", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(P) });
    const out = await r.json();
    if (!r.ok) throw new Error(out.error);
    status("SAVED. THE DUNGEON NOW PLAYS YOUR BEAT");
  } catch (err) {
    status(`SAVE FAILED: ${err.message}`);
  }
};
$("#reset").onclick = async () => {
  try {
    await fetch("/api/dev/song", { method: "DELETE" });
    status("GAME IS BACK TO THE BUILT-IN THEME");
  } catch (err) {
    status(`RESET FAILED: ${err.message}`);
  }
};

// Start from your last session here, else the game's current song
try {
  const saved = JSON.parse(localStorage.getItem("hallsOfJev.beat4"));
  if (saved?.bars) P = normalize(saved);
} catch {}
if (!P) P = await loadSavedSong();
build();

// For debugging in the console: beat.music, beat.pattern
window.beat = { music, get pattern() { return P; } };
