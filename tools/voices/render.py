#!/usr/bin/env python3
"""Renders a voice bank: every line a monster can say (cli/voice_lines.gd), spoken in that monster's voice, as Ogg
files in assets/voices/<bank>/ with the manifest.json src/audio/tts_engines.gd's Bank reads.

Each monster's voice is cloned from a Creative Commons recording (voices.json "refs", credited in
assets/CREDITS.txt), then shaped a little (voices.json "shape": semitones and tempo, so a dragon rumbles and a slime
squeaks), trimmed, loudness-normalised (EBU R128) and encoded to mono Ogg Vorbis. voices.json "say" gives a bank's
engine another spelling of a line it can't say as written (CosyVoice3 gives "Hmph." no sound at all).

    python3 tools/voices/render.py cosyvoice3 --python ~/tts/cosy/.venv/bin/python --model ~/tts/Fun-CosyVoice3-0.5B-2512 \
        --src ~/tts/CosyVoice
    python3 tools/voices/render.py qwen3 --python ~/tts/qwen/.venv/bin/python --model Qwen/Qwen3-TTS-12Hz-0.6B-Base
    python3 tools/voices/render.py cosyvoice3 --service feiyu --url http://gpu-box:8000 --key ... --voice <a CC voice>
    python3 tools/voices/render.py qwen3 --service qwen --url http://mac:8001

  cosyvoice3   CosyVoice3, the engine of the Feiyu stack (engines/cosyvoice3.py, run with --python: an environment
               with FunAudioLLM/CosyVoice's requirements; --src: its checkout), zero-shot from the reference recording
  qwen3        Qwen3-TTS Base (engines/qwen3.py, an environment with `qwen-tts`), cloned from the same recording
  --service    instead of a local model, a running service renders the lines: feiyu (POST /v1/speech, the job
               queue) or qwen (POST /synthesize). They use their own voices (--voice / --speaker), not voices.json.

Other options: --only slime,goblin  --limit N (lines per monster, to try things out)  --force (render again)
--threads N (default 4)  --seed N (default 1986). A take that comes out much too short (a clipped grunt) or too long
(a runaway) for its words is rendered again with the next seeds, up to RETAKES times.
--lines FILE (default build/voice-lines.json; made with Godot if missing: GODOT=godot)
Raw renders are kept in build/voices/<bank>/raw/ so a second run only renders what's new. Needs ffmpeg (libvorbis).
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
RATE = 24000
RETAKES = 3
LOUDNESS = "I=-18:TP=-1.5:LRA=11"
QUALITY = 4  # libvorbis -q: about 64 kb/s mono, plenty for speech

LABELS = {"cosyvoice3": "CosyVoice3 (Feiyu stack)", "qwen3": "Qwen3-TTS"}


def log(*a):
    print(*a, flush=True)


def line_file(species, key):
    return f"{species}/{hashlib.sha1(key.encode()).hexdigest()[:12]}.ogg"


def load_lines(path):
    if not os.path.exists(path):
        godot = os.environ.get("GODOT", "godot")
        log(f"{path} is missing: listing the lines with {godot}")
        subprocess.run([godot, "--headless", "--path", ROOT, "-s", "res://cli/voice_lines.gd", "--", "--out=" + path],
                       check=True)
    return json.load(open(path))


def has_rubberband():
    out = subprocess.run(["ffmpeg", "-hide_banner", "-filters"], capture_output=True, text=True).stdout
    return " rubberband " in out


def shape_filter(shape, rubberband):
    """ffmpeg filters for a voice's shape: semitones (pitch) and tempo (speed), formant-preserving where possible"""
    st = float(shape.get("semitones", 0))
    tempo = float(shape.get("tempo", 1))
    if st == 0 and tempo == 1:
        return []
    ratio = 2 ** (st / 12)
    if rubberband:
        return [f"rubberband=pitch={ratio:.5f}:tempo={tempo:.5f}:formant=preserved:pitchq=quality"]
    # asetrate shifts pitch and speed together; atempo puts the speed back where it should be
    return [f"asetrate={RATE}*{ratio:.5f}", f"aresample={RATE}", f"atempo={tempo / ratio:.5f}"]


def finish(raw, out, shape, rubberband):
    """trim, shape, normalise and encode one line"""
    trim = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05"
    chain = [f"aresample={RATE}", trim, "areverse", trim, "areverse"] + shape_filter(shape, rubberband) + [
        f"loudnorm={LOUDNESS}", f"aresample={RATE}", "apad=pad_dur=0.08"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", raw, "-ac", "1", "-af", ",".join(chain),
                    "-c:a", "libvorbis", "-q:a", str(QUALITY), out], check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out or 0)


def run_local(engine, args, items, seed):
    """the engine's script, in its own environment, renders every item {text, ref, ref_text, out} in one load"""
    batch = os.path.join(ROOT, "build", "voices", f"{engine}-batch.json")
    json.dump([{k: it[k] for k in ("text", "ref", "ref_text", "out")} for it in items], open(batch, "w"), indent=1)
    cmd = [args.python, os.path.join(HERE, "engines", f"{engine}.py"), "--batch", batch, "--trim", "--quiet",
           "--threads", str(args.threads), "--seed", str(seed), "--stats", batch.replace(".json", "-stats.json")]
    if args.model:
        cmd += ["--model-dir", args.model]
    if engine == "cosyvoice3":
        cmd += ["--src", args.src]
    subprocess.run(cmd, check=True)


def wav_seconds(path):
    with wave.open(path, "rb") as w:
        return w.getnframes() / w.getframerate()


def odd_length(text, seconds):
    """a take far too short for its words (a clipped grunt) or far too long (a runaway)"""
    letters = sum(c.isalpha() for c in text)
    return seconds < max(0.25, 0.035 * letters) or seconds > 0.25 * letters + 3.0


def http(method, url, body=None, key=""):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if key:
        req.add_header("Authorization", "Bearer " + key)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.status, r.read()


def run_service(args, items):
    """a running Feiyu or Qwen3-TTS service renders each line (the same requests the game makes)"""
    base = args.url.rstrip("/")
    for n, it in enumerate(items, 1):
        t0 = time.time()
        if args.service == "feiyu":
            body = {"text": it["text"], "voice": args.voice, "style": args.style}
            _, job = http("POST", base + "/v1/speech", body, args.key)
            job = json.loads(job)
            while job.get("status") != "success":
                if job.get("status") in ("failed", "interrupted"):
                    sys.exit(f"job {job['id']} {job['status']}: {job.get('error')}")
                time.sleep(0.25)
                job = json.loads(http("GET", f"{base}/v1/jobs/{job['id']}", key=args.key)[1])
            wav = http("GET", f"{base}/v1/jobs/{job['id']}/audio", key=args.key)[1]
        else:
            body = {"text": it["text"], "language": "en", "speaker": it.get("speaker") or args.speaker}
            wav = http("POST", base + "/synthesize", body, args.key)[1]
        open(it["out"], "wb").write(wav)
        log(f"[{n}/{len(items)}] {time.time() - t0:.1f}s {it['text']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bank", choices=["cosyvoice3", "qwen3"])
    ap.add_argument("--python", help="the Python of the engine's environment (local rendering)")
    ap.add_argument("--model", help="model folder or Hugging Face id (local rendering)")
    ap.add_argument("--src", help="cosyvoice3: a checkout of FunAudioLLM/CosyVoice")
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1986)
    ap.add_argument("--service", choices=["feiyu", "qwen"])
    ap.add_argument("--url")
    ap.add_argument("--key", default="")
    ap.add_argument("--voice", default="", help="feiyu: the voice package (not the Feiyu library)")
    ap.add_argument("--style", default="gentle")
    ap.add_argument("--speaker", default="Ryan", help="qwen service: the speaker")
    ap.add_argument("--lines", default=os.path.join(ROOT, "build", "voice-lines.json"))
    ap.add_argument("--only", default="")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if args.service and not args.url:
        ap.error("--service needs --url")
    if args.service == "feiyu" and not args.voice:
        ap.error("--service feiyu needs --voice: the service's default is the Feiyu voice library, which may not ship")
    if not args.service and not args.python:
        ap.error("local rendering needs --python (the engine's environment); or use --service")
    if not args.service and args.bank == "cosyvoice3" and not args.src:
        ap.error("cosyvoice3 needs --src, a checkout of FunAudioLLM/CosyVoice")
    if not shutil.which("ffmpeg"):
        sys.exit("needs ffmpeg (with libvorbis)")

    voices = json.load(open(os.path.join(HERE, "voices.json")))
    data = load_lines(args.lines)
    only = [s for s in args.only.split(",") if s]
    bank_dir = os.path.join(ROOT, "assets", "voices", args.bank)
    raw_dir = os.path.join(ROOT, "build", "voices", args.bank, "raw")
    manifest_path = os.path.join(bank_dir, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {"lines": {}}

    todo, plan = [], []
    for species, lines in data["species"].items():
        if only and species not in only:
            continue
        ref = voices["refs"][species]
        for line in lines[: args.limit or None]:
            rel = line_file(species, line["key"])
            raw = os.path.join(raw_dir, rel.replace(".ogg", ".wav"))
            plan.append((species, line, rel, raw))
            if args.force or not os.path.exists(raw):
                os.makedirs(os.path.dirname(raw), exist_ok=True)
                say = voices.get("say", {}).get(args.bank, {}).get(line["text"], line["text"])
                todo.append({"text": say, "ref": os.path.join(HERE, ref["wav"]), "ref_text": ref["text"],
                             "out": raw, "species": species})
    log(f"{args.bank}: {len(plan)} lines, {len(todo)} to render")
    t0 = time.time()
    if todo:
        if args.service:
            run_service(args, todo)
        else:
            run_local(args.bank, args, todo, args.seed)
            for retake in range(1, RETAKES + 1):
                odd = [it for it in todo if not os.path.exists(it["out"]) or odd_length(it["text"], wav_seconds(it["out"]))]
                if not odd:
                    break
                log(f"retake {retake}: {len(odd)} takes of an odd length: " + "; ".join(it["text"] for it in odd))
                run_local(args.bank, args, odd, args.seed + retake)
    rendered = time.time() - t0

    rubberband = has_rubberband()
    seconds = 0.0
    for species, line, rel, raw in plan:
        if not os.path.exists(raw):
            log(f"missing render, skipped: {species} {line['text']}")
            continue
        out = os.path.join(bank_dir, rel)
        if args.force or not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(raw):
            finish(raw, out, voices["shape"].get(species, {}), rubberband)
        seconds += duration(out)
        manifest["lines"].setdefault(species, {})[line["key"]] = rel

    manifest.update({
        "id": args.bank,
        "label": LABELS[args.bank],
        "engine": f"service:{args.service}" if args.service else args.bank,
        "model": args.model or args.url,
        "voices": {s: {k: v for k, v in r.items() if k != "text"} for s, r in voices["refs"].items()},
        "shape": voices["shape"],
    })
    os.makedirs(bank_dir, exist_ok=True)
    json.dump(manifest, open(manifest_path, "w"), indent=1, sort_keys=True)
    size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(bank_dir) for f in fs)
    audio = sum(duration(r) for _, _, _, r in plan if os.path.exists(r) and r in {t["out"] for t in todo})
    log(f"{args.bank}: {sum(len(v) for v in manifest['lines'].values())} lines in the manifest, "
        f"{seconds:.0f} s of speech, {size / 1e6:.1f} MB")
    if todo:
        log(f"rendered {len(todo)} lines ({audio:.0f} s) in {rendered:.0f} s: real-time factor {rendered / max(audio, 1e-6):.2f}")
    log("Import the new files before running the game: godot --headless --path . --import")


if __name__ == "__main__":
    main()
