#!/usr/bin/env python3
"""Gemini TTS as a voice engine for render.py: each line is one request to the Gemini API's Interactions endpoint, in a
prebuilt voice with a style of delivery (voices.json "gemini"), and comes back as a 24 kHz mono WAV.

Standard library only, so it runs in the Python render.py runs in. The API key is read from an environment variable
(GEMINI_API_KEY unless --key-env names another) and goes nowhere but the request header: it is never printed, logged
or written to a file.

Every reply is written to disk as it arrived (build/voices/gemini/responses/) before anything reads it, so a reply that
was paid for is never lost to a parsing mistake; a second run reads the saved reply instead of asking again.

The wire format is the one documented at https://ai.google.dev/gemini-api/docs/speech-generation (read 2026-11-17):

    POST https://generativelanguage.googleapis.com/v1beta/interactions      x-goog-api-key: <key>
    {"model": "gemini-3.8-flash-tts",
     "input": [{"type": "user_input", "content": [{"type": "text", "text": "<the line>",
                "annotations": [{"type": "speech_metadata", "style": "<how it is said>"}]}]}],
     "response_format": {"type": "audio"},
     "generation_config": {"speech_config": [{"voice": "Kore"}]}}

and the audio is the base64 `data` of the last `audio` item of the last `model_output` step (a WAV, RIFF header and all).
"""
import base64
import io
import json
import os
import time
import urllib.error
import urllib.request
import wave

URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
MODEL = "gemini-3.8-flash-tts"
KEY_ENV = "GEMINI_API_KEY"
RATE = 24000
AUDIO_TOKENS_PER_S = 25
# USD per million tokens (text in, audio out), standard tier, as listed on 2026-11-17 for use through 2026-12-31
PRICES = {
    "gemini-3.8-flash-tts": (0.50, 9.00),
    "gemini-3.8-flash-lite-tts": (0.50, 6.00),
    "gemini-3.1-flash-tts-preview": (1.00, 20.00),
    "gemini-2.5-flash-preview-tts": (0.50, 10.00),
    "gemini-2.5-pro-preview-tts": (1.00, 20.00),
}
CHARS_PER_S = 13.0  # how fast a line is spoken, about, for the estimate
CHARS_PER_TOKEN = 4.0
RETRIES = 5  # for a busy or failing server (429, 5xx, a dropped connection)
BACKOFF_S = 8.0
TIMEOUT_S = 120


class GeminiError(Exception):
    """the API refused a request in a way that asking again will not fix"""


def request_body(text, voice, style, model=MODEL):
    """the JSON of one line: the words as the transcript, the style as how they are said, in one prebuilt voice"""
    item = {"type": "text", "text": text}
    if style:
        item["annotations"] = [{"type": "speech_metadata", "style": style}]
    return {
        "model": model,
        "input": [{"type": "user_input", "content": [item]}],
        "response_format": {"type": "audio"},
        "generation_config": {"speech_config": [{"voice": voice}]},
    }


def audio_of(reply):
    """the audio bytes in a reply: the last audio item of the model's output steps"""
    found = None
    for step in reply.get("steps") or []:
        if not isinstance(step, dict) or step.get("type") != "model_output":
            continue
        for item in step.get("content") or []:
            if isinstance(item, dict) and item.get("type") == "audio" and isinstance(item.get("data"), str):
                found = item["data"]
    if found is None:
        raise ValueError("no audio in the reply (top-level fields: %s)" % ", ".join(sorted(reply)) if isinstance(reply, dict)
                         else "the reply is not a JSON object")
    return base64.b64decode(found)


def as_wav(audio):
    """the bytes as a WAV file: as they are when they have a RIFF header, wrapped as 24 kHz mono 16-bit when they are bare PCM"""
    if audio[:4] == b"RIFF" and audio[8:12] == b"WAVE":
        return audio
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(audio)
    return out.getvalue()


def estimate(items, model=MODEL):
    """what rendering these items costs, about: {lines, chars, seconds, usd}; usd is None for a model with no listed price"""
    chars = sum(len(it["text"]) for it in items)
    style_chars = sum(len(it.get("style", "")) for it in items)
    seconds = chars / CHARS_PER_S + 0.4 * len(items)
    price = PRICES.get(model)
    usd = None
    if price:
        usd = ((chars + style_chars) / CHARS_PER_TOKEN * price[0] + seconds * AUDIO_TOKENS_PER_S * price[1]) / 1e6
    return {"lines": len(items), "chars": chars, "seconds": seconds, "usd": usd}


def _post(url, body, key):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("x-goog-api-key", key)
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
        return r.read()


def _ask(url, body, key, log):
    """the reply's bytes; a busy or failing server is asked again, a refusal is not"""
    for attempt in range(1, RETRIES + 1):
        try:
            return _post(url, body, key)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:600]
            if e.code != 429 and e.code < 500:
                raise GeminiError(f"HTTP {e.code}: {detail}")
            wait = float(e.headers.get("Retry-After") or 0) or BACKOFF_S * attempt
            log(f"  HTTP {e.code}, try {attempt} of {RETRIES}, waiting {wait:.0f} s: {detail[:160]}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            wait = BACKOFF_S * attempt
            log(f"  {type(e).__name__}: {e}, try {attempt} of {RETRIES}, waiting {wait:.0f} s")
        if attempt < RETRIES:
            time.sleep(wait if wait < 120 else 120)
    raise GeminiError(f"no answer after {RETRIES} tries")


def render(items, key, responses_dir, model=MODEL, url=URL, rpm=10.0, log=print, force=False):
    """Render every item {text, voice, style, out} to a WAV at `out`. Each reply is saved under `responses_dir` (named as the
    WAV is) before it is read, and a saved reply is used instead of asking again unless `force`. Returns how many requests
    were made. A refusal (a bad key, a bad request) stops the run with GeminiError: the next lines would fail the same way."""
    if not key:
        raise GeminiError("no API key")
    os.makedirs(responses_dir, exist_ok=True)
    asked = 0
    gap = 60.0 / rpm if rpm > 0 else 0.0
    last = 0.0
    for n, it in enumerate(items, 1):
        name = os.path.splitext(os.path.basename(it["out"]))[0]
        kept = os.path.join(responses_dir, os.path.basename(os.path.dirname(it["out"])), name + ".json")
        os.makedirs(os.path.dirname(kept), exist_ok=True)
        t0 = time.time()
        fresh = force or not os.path.exists(kept)
        if fresh:
            wait = gap - (time.time() - last)
            if asked and wait > 0:
                time.sleep(wait)
            last = time.time()
            raw = _ask(url, request_body(it["text"], it["voice"], it.get("style", ""), model), key, log)
            asked += 1
            with open(kept, "wb") as f:  # as it arrived, before anything reads it
                f.write(raw)
        with open(kept, "rb") as f:
            raw = f.read()
        try:
            audio = as_wav(audio_of(json.loads(raw)))
        except (ValueError, json.JSONDecodeError) as e:
            log(f"[{n}/{len(items)}] no audio for: {it['text']} ({e}); the reply is in {kept}")
            continue
        os.makedirs(os.path.dirname(it["out"]), exist_ok=True)
        with open(it["out"], "wb") as f:
            f.write(audio)
        with wave.open(it["out"], "rb") as w:
            seconds = w.getnframes() / w.getframerate()
        log(f"[{n}/{len(items)}] {'%.1fs' % (time.time() - t0) if fresh else 'kept'} {it['voice']} {seconds:.1f}s {it['text']}")
    return asked
