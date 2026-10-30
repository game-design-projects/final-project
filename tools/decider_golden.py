"""Writes tests/jev/golden/decider/*.json: what Decider's own code makes of every golden Jev request, so the GDScript
readout (src/jev/decider.gd) can be checked against it byte for byte without a model.

For each tests/jev/golden/<name>.json request it records
  state_text   decider.systemone.render_state(state)
  rows         every prompt row of decider's state-first plain layout (decider.systemone.plan_rows with isolated Score
               levels, the default of the released checkpoints), each as `pieces`: the strings the row is tokenized from,
               in order, with {"label": j} where the wide layout (more than 10 options) puts option j's label token
  answers      decider.systemone.assemble() of synthetic letter logits (row r, option j: logit = ((r * 7 + j * 3) % 5) / 2)
               through decider.temperature with the temperatures of decider-4b-v3 (calibrated noul), so the
               temperatures, the isolated Score levels and the confidence formulas are checked too

Run it with decider-ai's pure-Python modules on the path (no torch needed for these):
    uv venv /tmp/dg && uv pip install -p /tmp/dg --no-deps decider-ai==1.10.0 && /tmp/dg/bin/python tools/decider_golden.py
"""
import json, logging, math, pathlib

from decider import systemone as SO
from decider.prompt import LETTERS, NARROW

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC, OUT = ROOT / "tests/jev/golden", ROOT / "tests/jev/golden/decider"
log = logging.getLogger("decider_golden")
TEMPERATURES = {"choice": 2.098, "noul": 2.795, "score": 3.152}


def pieces(row: dict) -> list:
    """The strings decider.prompt.build tokenizes one row from (state-first plain layout, one question per row)."""
    head = f"\n\nQuestion: {row['question']}\nOptions:"
    tail = "\nAnswer: ("
    if len(row["options"]) <= NARROW:
        return ["".join([head] + [f"\n({LETTERS[j]}) {o}" for j, o in enumerate(row["options"])] + [tail])]
    out = [head]
    for j, o in enumerate(row["options"]):
        out += ["\n(", {"label": j}, f") {o}"]
    return out + [tail]


def logits(r: int, n: int) -> list[float]:
    return [((r * 7 + j * 3) % 5) / 2 for j in range(n)]


def softmax(z: list[float], t: float) -> list[float]:
    m = max(z)
    e = [math.exp((x - m) / t) for x in z]
    s = sum(e)
    return [x / s for x in e]


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for f in sorted(SRC.glob("*.json")):
        if f.name == "results.json":
            continue
        req = json.loads(f.read_text())["request"]
        rqs = {k: SO.render_question(v) for k, v in req["questions"].items()}
        flat, index = SO.plan_rows(rqs, isolated=True)
        types = SO.row_types(rqs, index)
        probs = [softmax(logits(r, len(row["options"])), TEMPERATURES[types[r]]) for r, row in enumerate(flat)]
        out = {
            "state_text": SO.render_state(req["state"]),
            "rows": [{"type": types[r], "options": len(row["options"]), "pieces": pieces(row)} for r, row in enumerate(flat)],
            "answers": SO.assemble(rqs, index, probs),
        }
        (OUT / f.name).write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
        log.info("%s: %d rows", f.name, len(flat))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    main()
