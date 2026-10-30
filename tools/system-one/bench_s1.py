"""Latency of a System One server (Decider's decider.serve) on the game's golden requests, and the perception probe.
    python bench_s1.py <base> [runs]
"""
import copy, json, pathlib, statistics, sys, time, urllib.request

base, runs = sys.argv[1].rstrip("/"), int(sys.argv[2]) if len(sys.argv) > 2 else 5
GOLDEN = pathlib.Path(__file__).resolve().parents[2] / "tests/jev/golden"


def post(body: dict) -> tuple[dict, float]:
    r = urllib.request.Request(base + "/v1/systemone", data=json.dumps(body).encode(), headers={"content-type": "application/json"})
    t0 = time.time(); out = json.loads(urllib.request.urlopen(r, timeout=600).read()); return out, (time.time() - t0) * 1000


for f in ["vow", "ally_talk", "ally_reactions_three", "enemy_turn", "group_recruit", "group_talk"]:
    req = json.load(open(GOLDEN / f"{f}.json"))["request"]
    body = {"state": req["state"], "questions": req["questions"]}
    post(body)
    ms = [post(body)[1] for _ in range(runs)]
    print(f"{f:22} {len(req['questions']):3} questions   median {statistics.median(ms):7.0f} ms   min {min(ms):6.0f}   max {max(ms):6.0f}")

req = json.load(open(GOLDEN / "enemy_turn.json"))["request"]
show = ["e0__threat", "e0__insult", "e0__joke", "e0__asks_to_join", "e0__asks_for_peace", "e0__kindness"]
print(f"\n{'message':62} " + " ".join(f"{k[4:12]:>8}" for k in show))
for m in ["Hey little buddy.", "Move or I'll squash you flat, you puddle.", "You're a disgusting blob of snot.",
          "Why did the slime cross the road? To get to the other slide!", "Want to come adventure with us? We'd love to have you.",
          "Please, let's not fight. Let us pass in peace.", "Here, take these 20 gold coins if you leave us alone."]:
    st = copy.deepcopy(req["state"]); st["party"]["latest_message"] = m
    a = post({"state": st, "questions": req["questions"]})[0]["answers"]
    print(f"{m[:62]:62} " + " ".join(f"{(a[k]['score'] if a[k]['type'] == 'score' else a[k]['noul']):8.2f}" for k in show))
