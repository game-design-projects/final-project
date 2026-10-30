"""How long one round costs in Decider's schema-first layout (questions, then the state, then one answer slot per
question) when the question prefix is cached: prime the server with the prefix, then time prefix + state + slots.
    python schema_first.py <base> <tokenizer dir> <fixture.json>...
"""
import json, sys, time, urllib.request
from transformers import AutoTokenizer
from decider.infer import Example, Q, _NoShuffle
from decider.prompt import build, MAX_OPTIONS
from decider import systemone as SO

base, tokdir, files = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3:]
tok = AutoTokenizer.from_pretrained(tokdir)


def post(p: str, b: dict) -> dict:
    r = urllib.request.Request(base + p, data=json.dumps(b).encode(), headers={"content-type": "application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=600).read())


for f in files:
    req = json.load(open(f))["request"]
    rqs = {k: SO.render_question(v) for k, v in req["questions"].items()}
    qs = [Q(r["question"], r["options"], 0) for r in rqs.values()]          # listwise scores: one slot per question
    it = build(Example(SO.render_state(req["state"]), qs), tok, _NoShuffle(), max_options=MAX_OPTIONS, max_ctx_tokens=32768, layout="schema_first")
    ids, pre = it["ids"], it["prefix_len"]
    post("/completion", {"prompt": ids[:pre], "n_predict": 0})                 # the cached question prefix
    t0 = time.time(); out = post("/completion", {"prompt": ids, "n_predict": 0}); wall = time.time() - t0
    tm = out["timings"]
    print(f"{f.split('/')[-1]:22} questions {len(qs):3}  prefix {pre:5} tok  per-round {len(ids) - pre:4} tok  "
          f"server ran {tm['prompt_n']:4} tok in {tm['prompt_ms']:7.1f} ms  (wall {wall * 1000:6.0f} ms)")
