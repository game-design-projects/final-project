"""Quality probe: the enemy_turn fixture's perception questions under different player messages.
    python probe.py <base>   (temperatures: choice 2.098 / noul 2.795 / score 3.152, the 4b's; close enough for a sanity read)
"""
import json, os, pathlib, sys, copy
sys.path.insert(0, os.path.dirname(__file__))
import proto

base = sys.argv[1].rstrip("/")
T = {"noul": float(os.environ.get("TN", 2.795)), "score": float(os.environ.get("TS", 3.152))}
GOLDEN = pathlib.Path(__file__).resolve().parents[2] / "tests/jev/golden"
req = json.load(open(GOLDEN / "enemy_turn.json"))["request"]
keys = ["e0__threat", "e0__insult", "e0__joke", "e0__asks_to_join", "e0__asks_for_peace", "e0__offers_gold", "e0__kindness"]
ids = proto.letter_ids(base)
msgs = ["Hey little buddy.", "Move or I'll squash you flat, you puddle.", "You're a disgusting blob of snot.",
        "Why did the slime cross the road? To get to the other slide!", "Want to come adventure with us? We'd love to have you.",
        "Please, let's not fight. Let us pass in peace.", "Here, take these 20 gold coins if you leave us alone."]
print(f"{'message':62} " + " ".join(f"{k[4:12]:>8}" for k in keys))
for m in msgs:
    st = copy.deepcopy(req["state"]); st["party"]["latest_message"] = m
    ctx_ids = proto.tokenize(base, "Context:\n" + proto.render_state(st))
    proto.post(base, "/completion", {"prompt": ctx_ids, "n_predict": 0})
    row = []
    for k in keys:
        rq = proto.render_question(req["questions"][k])
        if rq["type"] == "score":
            fit = []
            for l in rq["legend"]:
                p, _, _ = proto.row_probs(base, ctx_ids, dict(question=proto.ISOLATED.format(q=rq["question"], level=l), options=["no", "yes"]), ids)
                fit.append(proto.with_temperature(p, T["score"])[1])
            s = sum(fit); row.append(sum(i * x / s for i, x in enumerate(fit)))
        else:
            p, _, _ = proto.row_probs(base, ctx_ids, dict(question=rq["question"], options=rq["options"]), ids)
            row.append(proto.with_temperature(p, T["noul"])[1])
    print(f"{m[:62]:62} " + " ".join(f"{x:8.2f}" for x in row))
