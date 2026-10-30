"""Quality of Decider's joint schema-first layout (every question in one cached prefix, then the state, then one answer
slot per question) on the enemy_turn questions, under different player messages. Slot k is read from a prompt that
ends at "Answer k: (" (causal, so it equals reading it from the full row); prompts extend each other, so the server's
cache carries every step.
    python probe_sf.py <base> <tokenizer dir> <T choice> <T score>
"""
import copy, json, math, pathlib, sys, time, urllib.request
from transformers import AutoTokenizer
from decider.infer import Example, Q, _NoShuffle
from decider.prompt import build, MAX_OPTIONS, label_table
from decider import systemone as SO

base, tokdir, TC, TS = sys.argv[1].rstrip("/"), sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
tok = AutoTokenizer.from_pretrained(tokdir)
_, lab, _ = label_table(tok)
GOLDEN = pathlib.Path(__file__).resolve().parents[2] / "tests/jev/golden"
req = json.load(open(GOLDEN / "enemy_turn.json"))["request"]
rqs = {k: SO.render_question(v) for k, v in req["questions"].items()}
keys = list(rqs)
show = ["e0__threat", "e0__insult", "e0__joke", "e0__asks_to_join", "e0__asks_for_peace", "e0__kindness"]


def post(p: str, b: dict) -> dict:
    r = urllib.request.Request(base + p, data=json.dumps(b).encode(), headers={"content-type": "application/json"})
    return json.loads(urllib.request.urlopen(r, timeout=600).read())


msgs = ["Hey little buddy.", "Move or I'll squash you flat, you puddle.", "You're a disgusting blob of snot.",
        "Why did the slime cross the road? To get to the other slide!", "Want to come adventure with us? We'd love to have you.",
        "Please, let's not fight. Let us pass in peace.", "Here, take these 20 gold coins if you leave us alone."]
print(f"{'message':62} " + " ".join(f"{k[4:12]:>8}" for k in show) + "   round ms")
for m in msgs:
    st = copy.deepcopy(req["state"]); st["party"]["latest_message"] = m
    qs = [Q(r["question"], r["options"], 0) for r in rqs.values()]
    it = build(Example(SO.render_state(st), qs), tok, _NoShuffle(), max_options=MAX_OPTIONS, max_ctx_tokens=32768, layout="schema_first")
    ids, slots, pre = it["ids"], it["slots"], it["prefix_len"]
    post("/completion", {"prompt": ids[:pre], "n_predict": 0})
    t0 = time.time(); out = {}
    for k, s, n in zip(keys, slots, it["nopts"]):
        r = post("/completion", {"prompt": ids[: s + 1], "n_predict": 0, "n_probs": n, "post_sampling_probs": True, "samplers": ["temperature"],
                                 "temperature": 1.0, "logit_bias": [[lab[j], 100.0] for j in range(n)]})
        by = {t["id"]: t["prob"] for t in r["completion_probabilities"][0]["top_probs"]}
        p = [by.get(lab[j], 0.0) for j in range(n)]
        T = TS if rqs[k]["type"] == "score" else TC
        z = [x ** (1 / T) if x > 0 else 0 for x in p]; s_ = sum(z); out[k] = [x / s_ for x in z]
    ms = (time.time() - t0) * 1000
    row = [sum(i * x for i, x in enumerate(out[k])) if rqs[k]["type"] == "score" else out[k][1] for k in show]
    print(f"{m[:62]:62} " + " ".join(f"{x:8.2f}" for x in row) + f"   {ms:6.0f}")
