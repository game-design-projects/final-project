// Debug: every API request the game makes, newest first, with the raw Jev calls behind it (what went to
// TypeSafe and what came back). Lives in the Jev panel's REQUESTS tab. summarize() is pure and tested;
// requestsHtml()/jsonBlock() build the markup, and the game wires the panel (game.js).

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// One line per request: what it was, how it went, what it cost
export function summarize(e) {
  const calls = e.jev ?? [];
  const questions = calls.reduce((n, c) => n + Object.keys(c.questions ?? {}).length, 0);
  const tokens = calls.reduce((n, c) => n + (c.response?.usage?.input_tokens ?? 0), 0);
  const ok = typeof e.status === "number" && e.status < 400;
  return {
    name: e.path.replace(/^\/api\//, "").replace(/-/g, " ").toUpperCase(),
    state: e.status == null ? "pending" : ok ? "ok" : "bad",
    status: e.status == null ? "…" : String(e.status),
    ms: e.ms,
    calls: calls.length,
    questions,
    tokens,
    traced: e.jev != null,
  };
}

// Pretty JSON with each token wrapped for the pixel palette: keys, strings, numbers, true/false/null
const TOKEN = /("(?:\\u[a-fA-F0-9]{4}|\\[^u]|[^\\"])*")(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/g;
export function highlightJson(value) {
  const text = JSON.stringify(value, null, 2) ?? "undefined";
  let out = "";
  let last = 0;
  for (const m of text.matchAll(TOKEN)) {
    out += esc(text.slice(last, m.index));
    const cls = m[1] ? (m[2] ? "k" : "s") : m[3] ? "b" : "n";
    out += m[1] && m[2] ? `<i class="k">${esc(m[1])}</i>${esc(m[2])}` : `<i class="${cls}">${esc(m[0])}</i>`;
    last = m.index + m[0].length;
  }
  return out + esc(text.slice(last));
}

export function jsonBlock(label, value, key) {
  return `<div class="jsec"><h4><span class="tab">${esc(label)}</span><button type="button" class="copy" data-copy="${esc(key)}">COPY</button></h4><pre>${highlightJson(value)}</pre></div>`;
}

// The body of one request, built only when it's opened (the JSON can be large)
export function requestDetail(e) {
  let h = jsonBlock("SENT TO THE GAME SERVER", e.request, `${e.n}:request`);
  h += e.error ? `<p class="bad">${esc(e.error)}</p>` : jsonBlock("THE GAME SERVER ANSWERED", e.response, `${e.n}:response`);
  if (e.jev == null) h += `<p class="meta">NO JEV DETAILS: THIS SERVER DOESN'T SEND THEM (AN OLDER WORKER? REDEPLOY IT).</p>`;
  (e.jev ?? []).forEach((c, i) => {
    const q = Object.keys(c.questions ?? {}).length;
    h += `<details class="jcall" data-call="${i}"><summary>JEV CALL ${i + 1} · ${c.ms ?? "?"} MS · ${q} QUESTIONS${
      c.response?.usage ? ` · ${c.response.usage.input_tokens} TOKENS` : ""
    }${c.attempts > 1 ? ` · ${c.attempts} TRIES` : ""}${c.error ? " · FAILED" : ""}</summary>${jsonBlock("STATE (WHAT JEV KNOWS)", c.state, `${e.n}:${i}:state`)}${jsonBlock(
      "QUESTIONS",
      c.questions,
      `${e.n}:${i}:questions`,
    )}${c.error ? `<p class="bad">${esc(c.error)}</p>` : jsonBlock("ANSWERS", c.response?.answers, `${e.n}:${i}:answers`)}</details>`;
  });
  return h;
}

export function requestsHtml(log, open) {
  if (!log.length) return `<p class="meta">NO REQUESTS YET. EVERY CALL TO THE GAME SERVER SHOWS UP HERE, WITH THE JEV CALLS BEHIND IT.</p>`;
  return log
    .map((e) => {
      const s = summarize(e);
      const time = e.at.toTimeString().slice(0, 8);
      const isOpen = open.has(e.n);
      return `<details class="req ${s.state}" data-n="${e.n}"${isOpen ? " open" : ""}><summary><b>#${e.n}</b> <span class="name">${s.name}</span><span class="st">${s.status}</span><span class="ms">${s.ms ?? "…"} MS</span><span class="sub">${
        s.traced ? `${s.calls} JEV CALL${s.calls === 1 ? "" : "S"} · ${s.questions} QUESTIONS${s.tokens ? ` · ${s.tokens} TOKENS` : ""}` : ""
      } <time>${time}</time></span></summary><div class="body">${isOpen ? requestDetail(e) : ""}</div></details>`;
    })
    .join("");
}

// Look up what a COPY button refers to: "n:request", "n:response", "n:i:state|questions|answers", or "n" (all)
export function copyValue(log, key) {
  const [n, a, b] = key.split(":");
  const e = log.find((x) => x.n === Number(n));
  if (!e) return null;
  if (a === undefined) return e;
  if (a === "request" || a === "response") return e[a];
  const c = e.jev?.[Number(a)];
  return b === "answers" ? c?.response?.answers : c?.[b];
}
