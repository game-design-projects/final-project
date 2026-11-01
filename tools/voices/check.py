#!/usr/bin/env python3
"""Checks a voice bank by ear, with the game's own speech recognizer: every Ogg in assets/voices/<bank>/ is decoded
(ffmpeg), sent through native/asr's helper and compared with the words it should say. Made-up words ("blorp",
"hur hur", "sssuch") are expected to come back differently; real words should come back.

    python3 tools/voices/check.py qwen3 [--only slime] [--json out.json]

Needs the helper and the model: native/asr/build.sh <platform> and native/asr/build.sh model. Prints each line with
the share of its words heard, the worst lines, and the bank's overall share; --json writes them all.
"""
import argparse
import json
import os
import platform
import re
import struct
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RATE = 16000


def words(s):
    return re.sub(r"[^a-z' ]", " ", s.lower().replace("-", " ")).split()


def frame(tag, payload=b""):
    return tag + struct.pack("<I", len(payload)) + payload


def decode(path):
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
                          "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return raw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bank")
    ap.add_argument("--only", default="")
    ap.add_argument("--json")
    args = ap.parse_args()
    plat = {"Linux": "linux", "Darwin": "macos", "Windows": "windows"}[platform.system()]
    exe = os.path.join(ROOT, "native", "dist", plat, "donjon-asr" + (".exe" if plat == "windows" else ""))
    model = os.path.join(ROOT, "build", "asr-model")
    if not os.path.exists(exe) or not os.path.exists(os.path.join(model, "tokens.txt")):
        sys.exit(f"needs the helper and the model: native/asr/build.sh {plat} && native/asr/build.sh model")
    bank_dir = os.path.join(ROOT, "assets", "voices", args.bank)
    manifest = json.load(open(os.path.join(bank_dir, "manifest.json")))
    lines = json.load(open(os.path.join(ROOT, "build", "voice-lines.json")))
    text_of = {(sp, l["key"]): l["text"] for sp, ls in lines["species"].items() for l in ls}

    p = subprocess.Popen([exe, "--tokens=" + os.path.join(model, "tokens.txt"),
                          "--encoder=" + os.path.join(model, "encoder.int8.onnx"),
                          "--decoder=" + os.path.join(model, "decoder.int8.onnx"),
                          "--joiner=" + os.path.join(model, "joiner.int8.onnx"), "--threads=2"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    assert json.loads(p.stdout.readline())["event"] == "ready"
    results = []
    only = [s for s in args.only.split(",") if s]
    for sp, entries in sorted(manifest["lines"].items()):
        if only and sp not in only:
            continue
        for key, rel in sorted(entries.items()):
            pcm = decode(os.path.join(bank_dir, rel))
            p.stdin.write(frame(b"S", struct.pack("<i", RATE)) + frame(b"A", pcm) + frame(b"F"))
            p.stdin.flush()
            while True:
                ev = json.loads(p.stdout.readline())
                if ev["event"] == "final":
                    break
            said = text_of.get((sp, key), key)
            want, got = words(said), words(ev["text"])
            share = sum(1 for w in want if w in got) / max(1, len(want))
            results.append({"species": sp, "file": rel, "text": said, "heard": ev["text"], "share": round(share, 2),
                            "seconds": round(len(pcm) / 4 / RATE, 2)})
            print(f"{share:4.0%}  {sp:6} {said!r:60.60} heard {ev['text']!r}", flush=True)
    p.stdin.close()
    p.wait()
    want_total = sum(len(words(r["text"])) for r in results)
    heard_total = sum(r["share"] * len(words(r["text"])) for r in results)
    overall = heard_total / max(1, want_total)
    print(f"\n{args.bank}: {len(results)} lines, {overall:.0%} of their words heard back; "
          f"{sum(r['share'] == 1 for r in results)} lines word for word")
    print("least understood:")
    for r in sorted(results, key=lambda r: r["share"])[:8]:
        print(f"  {r['share']:4.0%} {r['species']:6} {r['text']!r} -> {r['heard']!r}")
    if args.json:
        json.dump({"bank": args.bank, "overall": round(overall, 3), "lines": results}, open(args.json, "w"), indent=1)


if __name__ == "__main__":
    main()
