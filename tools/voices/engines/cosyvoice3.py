#!/usr/bin/env python3
"""CosyVoice3 (Fun-CosyVoice3-0.5B-2512), the engine of the Feiyu stack: zero-shot voice cloning, CPU is enough.
tools/voices/render.py runs this in an environment with FunAudioLLM/CosyVoice's requirements installed:
  python engines/cosyvoice3.py --src ~/CosyVoice --model-dir ~/Fun-CosyVoice3-0.5B-2512 --batch lines.json
  python engines/cosyvoice3.py --src ... --model-dir ... --ref refs/x.wav --ref-text "..." --text "Hi." --out out.wav
--batch is a JSON list of {text, ref, ref_text, out}; relative paths are against the JSON file's folder.
--src is a checkout of https://github.com/FunAudioLLM/CosyVoice (with its third_party/Matcha-TTS submodule).
Measured on 4 CPU threads: about 6-8x slower than real time, 8.3 GB of memory.
"""
import argparse
import json
import logging
import os
import re
import resource
import sys
import time
from pathlib import Path

PROMPT_PREFIX = "You are a helpful assistant.<|endofprompt|>"


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", help="reference wav (any rate; resampled internally)")
    ap.add_argument("--ref-text", help="exact transcript of --ref")
    ap.add_argument("--text", help="text to synthesise")
    ap.add_argument("--out", help="output wav (24 kHz mono 16-bit)")
    ap.add_argument("--batch", help="JSON list of {text, ref, ref_text, out}")
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1986, help="per-line RNG seed (same seed+text => same take)")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--steps", type=int, default=10, help="flow-matching Euler steps (model default 10; fewer = faster)")
    ap.add_argument("--model-dir", required=True, help="the Fun-CosyVoice3-0.5B-2512 weights")
    ap.add_argument("--src", required=True, help="a checkout of FunAudioLLM/CosyVoice")
    ap.add_argument("--stats", help="write timing JSON here")
    ap.add_argument("--keep-caps", action="store_true",
                    help="don't lowercase ALL-CAPS words (CosyVoice3 spells them out letter by letter: YOU -> Y-O-U)")
    ap.add_argument("--trim", action="store_true", help="trim leading/trailing silence (keeps 30 ms / 80 ms pads)")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    if not a.batch and not all([a.ref, a.ref_text, a.text, a.out]):
        ap.error("need --batch, or all of --ref --ref-text --text --out")
    return a


def fix_caps(text):
    """'Now I break YOU.' -> 'Now I break you.'; 'RAAH!' -> 'Raah!' (CosyVoice3 spells out all-caps tokens)."""
    t = re.sub(r"\b[A-Z]{2,}\b", lambda m: m.group(0).lower(), text)
    return re.sub(r"(^|[.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), t)


def peak_rss_mb():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024


def main():
    a = parse_args()
    if a.batch:
        bdir = Path(a.batch).resolve().parent
        items = json.loads(Path(a.batch).read_text())
        res = lambda p: str(p if Path(p).is_absolute() else (bdir / p))
        jobs = [dict(text=i["text"], ref=res(i["ref"]), ref_text=i["ref_text"], out=res(i["out"])) for i in items]
    else:
        jobs = [dict(text=a.text, ref=a.ref, ref_text=a.ref_text, out=a.out)]

    logging.basicConfig(level=logging.WARNING if a.quiet else logging.INFO)
    import torch
    torch.set_num_threads(a.threads)
    sys.path.insert(0, a.src)
    sys.path.insert(0, str(Path(a.src) / "third_party" / "Matcha-TTS"))
    import numpy as np
    import soundfile as sf
    # ttsfrd isn't installed and wetext fetches its FSTs from ModelScope (403 here): skip both so the
    # frontend goes straight to its built-in English path (inflect number spelling + sentence split).
    sys.modules.setdefault("ttsfrd", None)
    sys.modules.setdefault("wetext", None)
    from cosyvoice.cli.cosyvoice import CosyVoice3
    from cosyvoice.utils.common import set_all_random_seed
    if a.quiet:
        logging.getLogger().setLevel(logging.WARNING)

    t0 = time.perf_counter()
    model = CosyVoice3(a.model_dir, load_trt=False, load_vllm=False, fp16=False)
    load_s = time.perf_counter() - t0
    sr = model.sample_rate
    if a.steps != 10:
        dec = model.model.flow.decoder
        _fwd = dec.forward
        dec.forward = lambda *args, **kw: _fwd(*args, **{**kw, "n_timesteps": a.steps})
    print(f"[cosyvoice3] model loaded in {load_s:.1f}s  (threads={torch.get_num_threads()}, sr={sr})", flush=True)

    spk_cache = {}
    stats = {"engine": "cosyvoice3", "load_s": round(load_s, 2), "threads": a.threads, "steps": a.steps, "lines": []}
    for j in jobs:
        key = (os.path.abspath(j["ref"]), j["ref_text"])
        tp = time.perf_counter()
        if key not in spk_cache:
            sid = f"spk{len(spk_cache)}"
            model.add_zero_shot_spk(PROMPT_PREFIX + j["ref_text"], j["ref"], sid)
            spk_cache[key] = sid
        prompt_s = time.perf_counter() - tp
        set_all_random_seed(a.seed)
        ts = time.perf_counter()
        text = j["text"] if a.keep_caps else fix_caps(j["text"])
        chunks = [o["tts_speech"] for o in model.inference_zero_shot(
            text, "", "", zero_shot_spk_id=spk_cache[key], stream=False, speed=a.speed)]
        synth_s = time.perf_counter() - ts
        wav = torch.cat(chunks, dim=1).squeeze(0).cpu().numpy() if chunks else np.zeros(1, dtype=np.float32)
        wav = np.clip(wav, -1.0, 1.0)
        if a.trim and len(wav) > 1:
            import librosa
            _, (b0, b1) = librosa.effects.trim(wav, top_db=40)
            wav = wav[max(0, b0 - int(0.03 * sr)):min(len(wav), b1 + int(0.08 * sr))]
        Path(j["out"]).parent.mkdir(parents=True, exist_ok=True)
        sf.write(j["out"], wav, sr, subtype="PCM_16")
        audio_s = len(wav) / sr
        rec = {"out": j["out"], "text": j["text"], "audio_s": round(audio_s, 2), "synth_s": round(synth_s, 2),
               "prompt_s": round(prompt_s, 2), "rtf": round(synth_s / max(audio_s, 1e-6), 2)}
        stats["lines"].append(rec)
        print(f"[cosyvoice3] {audio_s:5.2f}s audio in {synth_s:6.2f}s  RTF={rec['rtf']:.2f}  -> {j['out']}", flush=True)

    stats["peak_rss_mb"] = round(peak_rss_mb())
    print(f"[cosyvoice3] peak RSS {stats['peak_rss_mb']} MB", flush=True)
    if a.stats:
        Path(a.stats).write_text(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
