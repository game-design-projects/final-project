#!/usr/bin/env python3
"""Smoke test for donjon-asr: feeds WAV files through its stdin protocol the way the game does (small frames, as a
microphone would deliver them) and checks the words that come back.

    python3 native/asr/smoke.py build/asr/linux/donjon-asr build/asr/model [wav expected-words ...]

With no WAVs it uses the model's own test_wavs/0.wav and 8k.wav (an 8 kHz file: sherpa-onnx resamples) and their
transcripts. The first file is sent at the pace of speech and must show words before it ends; the others are sent at
once (the helper catches up, then reports). Each expected-words string must appear, in order, in the final text (case and punctuation ignored).
Exits 1 on any failure. Standard library only, so it runs on every CI runner.
"""
import json
import os
import re
import struct
import subprocess
import sys
import time
import wave

FRAME_S = 0.02


def model_args(model_dir):
    names = os.listdir(model_dir)

    def find(prefix):
        hits = sorted(n for n in names if n.startswith(prefix) and n.endswith(".onnx"))
        int8 = [n for n in hits if ".int8." in n]
        if not hits:
            sys.exit(f"no {prefix}*.onnx in {model_dir}")
        return os.path.join(model_dir, (int8 or hits)[0])

    return [
        "--tokens=" + os.path.join(model_dir, "tokens.txt"),
        "--encoder=" + find("encoder"),
        "--decoder=" + find("decoder"),
        "--joiner=" + find("joiner"),
        "--threads=2",  # as the game runs it
    ]


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getsampwidth() == 2, f"{path}: 16-bit PCM expected"
        rate, ch = w.getframerate(), w.getnchannels()
        raw = w.readframes(w.getnframes())
    ints = struct.unpack("<%dh" % (len(raw) // 2), raw)
    mono = [sum(ints[i:i + ch]) / (ch * 32768.0) for i in range(0, len(ints), ch)]
    return rate, mono


def frame(tag, payload=b""):
    return tag + struct.pack("<I", len(payload)) + payload


def words(s):
    return re.sub(r"[^a-z' ]", " ", s.lower()).split()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    exe, model_dir = sys.argv[1], sys.argv[2]
    cases = list(zip(sys.argv[3::2], sys.argv[4::2]))
    if not cases:
        tw = os.path.join(model_dir, "test_wavs")
        trans = dict(line.split(" ", 1) for line in open(os.path.join(tw, "trans.txt")).read().strip().splitlines())
        cases = [(os.path.join(tw, n), trans[n]) for n in ("0.wav", "8k.wav")]

    t0 = time.time()
    p = subprocess.Popen([exe] + model_args(model_dir), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    ready = json.loads(p.stdout.readline() or b'{"event":"exited"}')
    if ready.get("event") != "ready":
        sys.exit(f"FAIL: expected ready, got {ready}")
    print(f"ready in {time.time() - t0:.1f} s")

    failed = 0
    for n, (path, expected) in enumerate(cases):
        live = n == 0
        rate, mono = read_wav(path)
        step = max(1, int(rate * FRAME_S))
        t1 = time.time()
        p.stdin.write(frame(b"S", struct.pack("<i", rate)))
        for i in range(0, len(mono), step):
            chunk = mono[i:i + step]
            p.stdin.write(frame(b"A", struct.pack("<%df" % len(chunk), *chunk)))
            if live:
                p.stdin.flush()
                time.sleep(FRAME_S)
        p.stdin.write(frame(b"F"))
        p.stdin.flush()
        partials = 0
        while True:
            line = p.stdout.readline()
            if not line:
                sys.exit("FAIL: donjon-asr exited early")
            ev = json.loads(line)
            if ev["event"] == "text":
                partials += 1
            elif ev["event"] == "final":
                break
            else:
                sys.exit(f"FAIL: {ev}")
        got = words(ev["text"])
        want = words(expected)
        hits = sum(1 for w in want if w in got)
        ok = hits >= 0.8 * len(want) and (partials > 0 or not live)
        failed += not ok
        print(f"{'ok' if ok else 'FAIL'} {os.path.basename(path)}: {hits}/{len(want)} words, {partials} partials, "
              f"{len(mono) / rate:.1f} s of audio {'spoken' if live else 'sent at once'}, final after "
              f"{time.time() - t1:.1f} s")
        print(f"   heard: {ev['text']}")

    # an aborted utterance gives no result, and the next one still works
    p.stdin.write(frame(b"S", struct.pack("<i", 16000)) + frame(b"A", struct.pack("<4f", 0, 0, 0, 0)) + frame(b"X"))
    p.stdin.write(frame(b"F"))
    p.stdin.flush()
    ev = json.loads(p.stdout.readline())
    if ev != {"event": "final", "text": ""}:
        failed += 1
        print(f"FAIL after abort: {ev}")
    p.stdin.close()
    code = p.wait(timeout=30)
    if code != 0:
        failed += 1
        print(f"FAIL: exit code {code}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
