#!/usr/bin/env python3
"""Qwen3-TTS (Qwen3-TTS-12Hz-0.6B-Base) voice cloning, float32; CPU is enough.
tools/voices/render.py runs this in an environment with `pip install qwen-tts`:
  python engines/qwen3.py --model-dir Qwen/Qwen3-TTS-12Hz-0.6B-Base --batch lines.json
  python engines/qwen3.py --ref refs/x.wav --ref-text "..." --text "Hello, tiny." --out out.wav
--batch is a JSON list of {text, ref, ref_text, out}; relative paths are against the JSON file's folder.
Measured on 4 CPU threads: about 5-8x slower than real time, 5.8 GB of memory.
"""
import argparse
import json
import os
import resource
import time
from pathlib import Path


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ref", help="reference wav")
    ap.add_argument("--ref-text", help="exact transcript of --ref")
    ap.add_argument("--text", help="text to synthesise")
    ap.add_argument("--out", help="output wav (24 kHz mono 16-bit)")
    ap.add_argument("--batch", help="JSON list of {text, ref, ref_text, out}")
    ap.add_argument("--language", default="english")
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1986, help="per-line RNG seed (same seed+text => same take)")
    ap.add_argument("--temperature", type=float, default=None, help="override talker temperature (default 0.9)")
    ap.add_argument("--model-dir", default="Qwen/Qwen3-TTS-12Hz-0.6B-Base", help="the weights: a folder or a Hugging Face id")
    ap.add_argument("--stats", help="write timing JSON here")
    ap.add_argument("--trim", action="store_true", help="trim leading/trailing silence (keeps 30 ms / 80 ms pads)")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    if not a.batch and not all([a.ref, a.ref_text, a.text, a.out]):
        ap.error("need --batch, or all of --ref --ref-text --text --out")
    return a


def peak_rss_mb():
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024


def max_tokens_for(text):
    # 12.5 codec frames per second; allow ~0.2 s/char + 3 s headroom so a runaway take is bounded.
    return int(13 * max(4.0, 0.2 * len(text) + 3.0))


def main():
    a = parse_args()
    if a.batch:
        bdir = Path(a.batch).resolve().parent
        items = json.loads(Path(a.batch).read_text())
        res = lambda p: str(p if Path(p).is_absolute() else (bdir / p))
        jobs = [dict(text=i["text"], ref=res(i["ref"]), ref_text=i["ref_text"], out=res(i["out"])) for i in items]
    else:
        jobs = [dict(text=a.text, ref=a.ref, ref_text=a.ref_text, out=a.out)]

    import numpy as np
    import soundfile as sf
    import torch
    torch.set_num_threads(a.threads)
    if a.quiet:
        import transformers
        transformers.logging.set_verbosity_error()
    from qwen_tts import Qwen3TTSModel

    t0 = time.perf_counter()
    model = Qwen3TTSModel.from_pretrained(a.model_dir, device_map="cpu", dtype=torch.float32)
    load_s = time.perf_counter() - t0
    print(f"[qwen3] model loaded in {load_s:.1f}s  (threads={torch.get_num_threads()})", flush=True)

    prompt_cache = {}
    stats = {"engine": "qwen3", "load_s": round(load_s, 2), "threads": a.threads, "lines": []}
    gen_kw = {}
    if a.temperature is not None:
        gen_kw["temperature"] = a.temperature
    for j in jobs:
        key = (os.path.abspath(j["ref"]), j["ref_text"])
        tp = time.perf_counter()
        if key not in prompt_cache:
            prompt_cache[key] = model.create_voice_clone_prompt(ref_audio=j["ref"], ref_text=j["ref_text"])
        prompt_s = time.perf_counter() - tp
        torch.manual_seed(a.seed)
        np.random.seed(a.seed)
        ts = time.perf_counter()
        with torch.inference_mode():
            wavs, sr = model.generate_voice_clone(text=j["text"], language=a.language,
                                                  voice_clone_prompt=prompt_cache[key],
                                                  max_new_tokens=max_tokens_for(j["text"]), **gen_kw)
        synth_s = time.perf_counter() - ts
        wav = np.clip(np.asarray(wavs[0], dtype=np.float32).reshape(-1), -1.0, 1.0)
        if a.trim and len(wav) > 1:
            import librosa
            _, (b0, b1) = librosa.effects.trim(wav, top_db=40)
            wav = wav[max(0, b0 - int(0.03 * sr)):min(len(wav), b1 + int(0.08 * sr))]
        Path(j["out"]).parent.mkdir(parents=True, exist_ok=True)
        sf.write(j["out"], wav, sr, subtype="PCM_16")
        audio_s = len(wav) / sr
        rec = {"out": j["out"], "text": j["text"], "audio_s": round(audio_s, 2), "synth_s": round(synth_s, 2),
               "prompt_s": round(prompt_s, 2), "rtf": round(synth_s / max(audio_s, 1e-6), 2), "sr": sr}
        stats["lines"].append(rec)
        print(f"[qwen3] {audio_s:5.2f}s audio in {synth_s:6.2f}s  RTF={rec['rtf']:.2f}  -> {j['out']}", flush=True)

    stats["peak_rss_mb"] = round(peak_rss_mb())
    print(f"[qwen3] peak RSS {stats['peak_rss_mb']} MB", flush=True)
    if a.stats:
        Path(a.stats).write_text(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
