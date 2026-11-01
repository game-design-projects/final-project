"""Time one fixture's rows against a running llama-server: sequential, or N concurrent requests (server started with -np N).
    python bench.py <base> <fixture.json> <concurrency> [reference.json to compare against / write]
"""
import json, sys, time, os
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(__file__))
import proto

base, f, conc = sys.argv[1].rstrip("/"), sys.argv[2], int(sys.argv[3])
refp = sys.argv[4] if len(sys.argv) > 4 else None
req = json.load(open(f))["request"]
ids = proto.letter_ids(base)
rows, _ = proto.plan_rows({k: proto.render_question(v) for k, v in req["questions"].items()})
rows = [r for r in rows if len(r["options"]) <= 10]
ctx_ids = proto.tokenize(base, "Context:\n" + proto.render_state(req["state"]))
pieces = [proto.tokenize(base, proto.piece(r)) for r in rows]


def one(i: int) -> tuple[list[float], dict]:
    n = len(rows[i]["options"])
    out = proto.post(base, "/completion", {"prompt": ctx_ids + pieces[i], "n_predict": 0, "n_probs": n, "post_sampling_probs": True,
                                           "samplers": ["temperature"], "temperature": 1.0, "logit_bias": [[ids[j], 100.0] for j in range(n)]})
    by = {t["id"]: t["prob"] for t in out["completion_probabilities"][0]["top_probs"]}
    p = [by.get(ids[j], 0.0) for j in range(n)]; s = sum(p) or 1
    return [x / s for x in p], out["timings"]


t0 = time.time()
if os.environ.get("PRIME"):
    pr = proto.post(base, "/completion", {"prompt": ctx_ids, "n_predict": 0})
    print(f"prime: prompt_n {pr['timings']['prompt_n']} in {pr['timings']['prompt_ms']:.0f} ms", end="  |  ")
if conc == 1:
    res = [one(i) for i in range(len(rows))]
else:
    with ThreadPoolExecutor(conc) as ex:
        res = list(ex.map(one, range(len(rows))))
wall = time.time() - t0
pn = sum(r[1]["prompt_n"] for r in res); pms = sum(r[1]["prompt_ms"] for r in res)
msg = f"{os.path.basename(f):24} rows {len(rows):3} conc {conc}  wall {wall:6.2f}s  prompt tokens {pn:6} ({pms/1000:6.2f}s server)  {pn/max(wall,1e-9):6.0f} tok/s"
probs = [r[0] for r in res]
if refp and os.path.exists(refp):
    ref = json.load(open(refp))
    msg += f"  max|dp| vs ref {max(max(abs(a - b) for a, b in zip(x, y)) for x, y in zip(probs, ref)):.4f}"
elif refp:
    json.dump(probs, open(refp, "w"))
print(msg)
