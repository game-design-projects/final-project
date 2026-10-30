"""Prototype of the in-game readout: a System One request answered by Decider over a stock llama-server.

Mirrors decider.systemone + decider.prompt (state-first plain layout, narrow options, isolated score levels), but sends
text pieces to llama-server /completion and reads the option-letter probabilities from n_probs with a logit bias.
stdlib only, so the same logic can be ported to GDScript line by line.
"""
import json, math, time, urllib.request

LETTERS = "ABCDEFGHIJ"
BIAS = 100.0


def py_json(v: object) -> str:
    return json.dumps(v, ensure_ascii=False)


def annotate(x: object, min_len: int = 8) -> object:
    if isinstance(x, list):
        if len(x) >= min_len:
            return [({"_index": i, **annotate(v, min_len)} if isinstance(v, dict) else {"_index": i, "value": annotate(v, min_len)}) for i, v in enumerate(x)]
        return [annotate(v, min_len) for v in x]
    if isinstance(x, dict):
        return {k: annotate(v, min_len) for k, v in x.items()}
    return x


def render_state(state: object) -> str:
    return state if isinstance(state, str) else py_json(annotate(state))


def txt(v: object) -> str:
    return v if isinstance(v, str) else py_json(v)


def render_question(spec: dict) -> dict:
    t = spec["type"]; crit = spec.get("criteria"); ins = txt(spec.get("instructions", ""))
    if t == "choice":
        names = list(crit); opts = [n if crit[n] in (None, "") else f"{n}: {txt(crit[n])}" for n in names]; legend = None
    elif t == "score":
        names = list(range(len(crit))); opts = [f"{i}: {txt(c)}" for i, c in enumerate(crit)]; legend = [txt(c) for c in crit]
    else:
        c = crit or {}; f, tr = c.get("false"), c.get("true"); names = [False, True]; legend = None
        opts = ["no" if f in (None, "") else f"no: {txt(f)}", "yes" if tr in (None, "") else f"yes: {txt(tr)}"]
    return dict(question=ins, options=opts, type=t, names=names, legend=legend)


ISOLATED = "{q}\nProposed answer: {level}\nDoes the proposed answer fit?"


def plan_rows(rqs: dict) -> tuple[list, list]:
    rows, index = [], []
    for k, r in rqs.items():
        if r["type"] == "score":
            index.append((k, "iso", len(rows), len(r["legend"])))
            rows += [dict(question=ISOLATED.format(q=r["question"], level=l), options=["no", "yes"], type="score") for l in r["legend"]]
        else:
            index.append((k, "list", len(rows), 1)); rows.append(dict(question=r["question"], options=r["options"], type=r["type"]))
    return rows, index


def piece(row: dict) -> str:
    assert len(row["options"]) <= len(LETTERS)
    return "".join([f"\n\nQuestion: {row['question']}\nOptions:"] + [f"\n({LETTERS[j]}) {o}" for j, o in enumerate(row["options"])] + ["\nAnswer: ("])


def post(base: str, path: str, body: dict, timeout: float = 600) -> dict:
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(), headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def letter_ids(base: str) -> list[int]:
    return [post(base, "/tokenize", {"content": L})["tokens"][0] for L in LETTERS]


def tokenize(base: str, text: str) -> list[int]:
    return post(base, "/tokenize", {"content": text})["tokens"]


def row_probs(base: str, ctx_ids: list[int], row: dict, ids: list[int], temperature: float = 1.0) -> tuple[list[float], dict, object]:
    """Probabilities over the row's options (softmax of the letter logits / T), and the server's timings."""
    n = len(row["options"])
    body = {"prompt": ctx_ids + tokenize(base, piece(row)), "n_predict": 1, "n_probs": n, "post_sampling_probs": True,
            "samplers": ["temperature"], "temperature": temperature, "logit_bias": [[ids[j], BIAS] for j in range(n)],
            "cache_prompt": True}
    out = post(base, "/completion", body)
    top = out["completion_probabilities"][0]["top_probs"]
    by_id = {t["id"]: t["prob"] for t in top}
    p = [by_id.get(ids[j], 0.0) for j in range(n)]
    s = sum(p) or 1.0
    return [x / s for x in p], out.get("timings", {}), out.get("tokens_cached")


def with_temperature(p: list[float], T: float) -> list[float]:
    z = [x ** (1.0 / T) if x > 0 else 0.0 for x in p]; s = sum(z) or 1.0
    return [x / s for x in z]


def choice_confidence(p: list[float]) -> float:
    n = len(p)
    return 1.0 if n <= 1 else min(1.0, max(0.0, (n * max(p) - 1) / (n - 1)))


def score_confidence(p: list[float]) -> float:
    n = len(p)
    if n <= 1:
        return 1.0
    k = max(range(n), key=p.__getitem__)
    spread = sum(x * abs(i - k) for i, x in enumerate(p)); uniform = sum(abs(i - (n - 1) / 2) for i in range(n)) / n
    return min(1.0, max(0.0, 1.0 - spread / uniform))
