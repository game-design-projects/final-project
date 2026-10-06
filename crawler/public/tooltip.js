// Pixel-art tooltips in place of the browser's own: any element with a title (or data-tip) gets a framed,
// pixel-font note on hover instead of the system's grey box. "A · B · C" titles become one line each, and a
// run of ability scores ("STRENGTH -1 DEXTERITY +2 ...") becomes a small table.
// tipModel() is pure (tested in Node); installTooltips() wires the DOM.

const ABILITY = /\b(STRENGTH|DEXTERITY|CONSTITUTION|INTELLIGENCE|WISDOM|CHARISMA) ([+-]\d+)/g;

// title text -> { lines: [string], stats: [[name, value]] }
export function tipModel(text) {
  const lines = [];
  let stats = [];
  for (const part of String(text ?? "").split(" · ")) {
    const t = part.trim();
    if (!t) continue;
    const found = [...t.matchAll(ABILITY)];
    // A part made only of ability scores becomes the table
    if (found.length >= 2 && t.replace(ABILITY, "").trim() === "") stats = found.map((m) => [m[1], Number(m[2])]);
    else lines.push(t);
  }
  return { lines, stats };
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

export function tipHtml({ lines, stats }) {
  const rows = lines.map((l, i) => `<p class="${i === 0 && lines.length > 1 ? "head" : ""}">${esc(l)}</p>`).join("");
  const table = stats.length
    ? `<div class="stats">${stats
        .map(([name, v]) => `<span><b>${name}</b><i class="${v > 0 ? "up" : v < 0 ? "down" : ""}">${v > 0 ? "+" : ""}${v}</i></span>`)
        .join("")}</div>`
    : "";
  return rows + table;
}

export function installTooltips({ root = document, delay = 220, accent = () => "#ffb347" } = {}) {
  const tip = document.createElement("div");
  tip.className = "pxtip";
  tip.setAttribute("role", "tooltip");
  tip.hidden = true;
  document.body.append(tip);
  let anchor = null;
  let timer = null;

  const hide = () => {
    clearTimeout(timer);
    anchor = null;
    tip.hidden = true;
  };
  const place = () => {
    if (!anchor?.isConnected) return hide();
    const r = anchor.getBoundingClientRect();
    const t = tip.getBoundingClientRect();
    const margin = 8;
    // Below the element if it fits, otherwise above; kept inside the window
    const below = r.bottom + 10 + t.height <= innerHeight - margin;
    const top = below ? r.bottom + 10 : Math.max(margin, r.top - 10 - t.height);
    const left = Math.min(Math.max(margin, r.left + r.width / 2 - t.width / 2), innerWidth - t.width - margin);
    tip.style.top = `${top + scrollY}px`;
    tip.style.left = `${left + scrollX}px`;
    tip.classList.toggle("above", !below);
    tip.style.setProperty("--arrow-x", `${Math.min(Math.max(10, r.left + r.width / 2 - left), t.width - 10)}px`);
  };

  root.addEventListener("mouseover", (ev) => {
    const el = ev.target.closest?.("[title], [data-tip]");
    if (!el || el === anchor) return;
    // Take the text out of title so the browser's own tooltip never shows
    if (el.hasAttribute("title")) {
      const t = el.getAttribute("title");
      el.removeAttribute("title");
      if (t) el.dataset.tip = t;
    }
    const text = el.dataset.tip;
    if (!text) return;
    clearTimeout(timer);
    timer = setTimeout(() => {
      anchor = el;
      tip.innerHTML = tipHtml(tipModel(text));
      tip.style.setProperty("--accent", accent());
      tip.hidden = false;
      place();
    }, anchor ? 0 : delay); // moving between tooltips is instant once one is up
  });
  root.addEventListener("mouseout", (ev) => {
    const el = ev.target.closest?.("[data-tip]");
    if (el && !el.contains(ev.relatedTarget)) hide();
  });
  addEventListener("keydown", hide, true);
  addEventListener("scroll", hide, true);
  addEventListener("resize", hide);
  return { hide };
}
