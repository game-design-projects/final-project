"""Does priming change the answers? Each row of a fixture read three ways against a running llama-server: fresh (no
cache), as bench.py sends it (cache on, no prime), and primed (the state sent first, as local.gd does).
    python prime_check.py <base> <fixture.json>
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import proto

base, f = sys.argv[1].rstrip("/"), sys.argv[2]
req = json.load(open(f))["request"]
ids = proto.letter_ids(base)
rows, _ = proto.plan_rows({k: proto.render_question(v) for k, v in req["questions"].items()})
rows = [r for r in rows if len(r["options"]) <= 10]
ctx = proto.tokenize(base, "Context:\n" + proto.render_state(req["state"]))


def read(row: dict, cache: bool) -> tuple[list[float], int]:
    n = len(row["options"])
    out = proto.post(base, "/completion", {"prompt": ctx + proto.tokenize(base, proto.piece(row)), "n_predict": 0, "n_probs": n,
                                           "post_sampling_probs": True, "samplers": ["temperature"], "temperature": 1.0,
                                           "logit_bias": [[ids[j], 100.0] for j in range(n)], "cache_prompt": cache})
    by = {t["id"]: t["prob"] for t in out["completion_probabilities"][0]["top_probs"]}
    p = [by.get(ids[j], 0.0) for j in range(n)]; s = sum(p) or 1
    return [x / s for x in p], out["timings"]["prompt_n"]


fresh = [read(r, False) for r in rows]
cached = [read(r, True) for r in rows]
proto.post(base, "/completion", {"prompt": ctx, "n_predict": 0})
primed = [read(r, True) for r in rows]


def dp(a: list, b: list) -> list[float]:
    return [max(abs(x - y) for x, y in zip(p[0], q[0])) for p, q in zip(a, b)]


for name, other in [("cached", cached), ("primed", primed)]:
    d = dp(fresh, other)
    print(f"{os.path.basename(f):24} rows {len(rows):3}  fresh vs {name}: max|dp| {max(d):.4f}  mean {sum(d) / len(d):.4f}  "
          f"rows > 0.05: {sum(x > 0.05 for x in d)}  prompt tokens {sum(x[1] for x in other)}")
d = dp(fresh, primed)
for i in sorted(range(len(rows)), key=lambda i: -d[i])[:3]:
    print(f"   row {i:3} dp {d[i]:.3f}  fresh {[round(x, 3) for x in fresh[i][0]]}  primed {[round(x, 3) for x in primed[i][0]]}  "
          f"{rows[i]['question'][:70]!r}")
