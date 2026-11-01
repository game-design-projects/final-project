"""Compare the llama-server readout (proto.py) with Decider's own GGUF engine on the game's golden Jev requests.

    python compare.py <gguf> <llama-server base url> <fixture.json>...
Prints, per fixture: rows, prompt-text and token parity, max |p_ref - p_server| over rows (T = 1), and server timings.
"""
import json, sys, time
sys.path.insert(0, __import__("os").path.dirname(__file__))
import proto
from decider.infer import Decider

gguf, base, files = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3:]
d = Decider(gguf, gguf_options=dict(n_ctx=16384, n_gpu_layers=-1))
ids = proto.letter_ids(base)
assert list(ids) == list(d.eng.letters[:10]), (ids, d.eng.letters[:10])
for f in files:
    req = json.load(open(f))["request"]
    state, questions = req["state"], req["questions"]
    rqs, index, items = d._system_one_items(state, questions)
    t0 = time.time(); ref = d.eng.score_items(items, temperature=1.0); t_ref = time.time() - t0
    prs = {k: proto.render_question(v) for k, v in questions.items()}
    rows, pindex = proto.plan_rows(prs)
    ctx = proto.render_state(state)
    assert len(rows) == len(items), (len(rows), len(items))
    text_ok = tok_ok = 0; worst = 0.0; prompt_n = []; t0 = time.time()
    ctx_ids = proto.tokenize(base, "Context:\n" + ctx)
    for it, row, rp in zip(items, rows, ref):
        mine = "Context:\n" + ctx + proto.piece(row)
        text_ok += d.m.tok.decode(it["ids"]) == mine
        toks = ctx_ids + proto.tokenize(base, proto.piece(row))
        tok_ok += toks == it["ids"]
        p, timings, cached = proto.row_probs(base, ctx_ids, row, ids)
        prompt_n.append(timings.get("prompt_n"))
        r = rp[0][: len(row["options"])].tolist()
        worst = max(worst, max(abs(a - b) for a, b in zip(p, r)))
    t_srv = time.time() - t0
    print(f"{f.split('/')[-1]:30} rows {len(rows):3}  text {text_ok}/{len(rows)}  tokens {tok_ok}/{len(rows)}  max|dp| {worst:.4f}  "
          f"ref {t_ref:5.2f}s  server {t_srv:5.2f}s  prompt_n first/rest {prompt_n[0]}/{sorted(set(prompt_n[1:]))[:6]}")
