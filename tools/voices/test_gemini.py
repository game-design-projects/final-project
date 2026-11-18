#!/usr/bin/env python3
"""Checks engines/gemini.py against a stand-in server on this machine: no key, no network, nothing paid for.

    python3 tools/voices/test_gemini.py

Both ways in (OpenRouter's speech endpoint and Google's Interactions endpoint) are asked for two lines; the server
answers one of them 429 the first time and refuses a third outright. The checks: what was sent, that the reply is on disk
as it arrived, that the WAV is 24 kHz mono 16-bit, that a second run asks nobody, and that the key is in no file."""
import base64
import http.server
import io
import json
import os
import sys
import tempfile
import threading
import wave

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "engines"))
import gemini  # noqa: E402

KEY = "test-key-never-real"
PCM = b"\x01\x02" * 12000  # half a second at 24 kHz
failed = 0
seen = []
busy_once = {"left": 1}


def check(ok, what):
    global failed
    print("test_gemini: %s %s" % ("ok  " if ok else "FAIL", what))
    failed += 0 if ok else 1


def wav_bytes():
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(24000)
        w.writeframes(PCM)
    return out.getvalue()


class Stub(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        via = "google" if self.path.endswith("/interactions") else "openrouter"
        key = self.headers.get("x-goog-api-key") if via == "google" else (self.headers.get("Authorization") or "").replace("Bearer ", "")
        seen.append({"via": via, "path": self.path, "key": key, "body": body})
        text = body["input"] if via == "openrouter" else body["input"][0]["content"][0]["text"]
        if text == "busy" and busy_once["left"] > 0:
            busy_once["left"] -= 1
            return self.answer(429, "application/json", b'{"error": "slow down"}', {"Retry-After": "0.01"})
        if text == "refused":
            return self.answer(400, "application/json", b'{"error": {"message": "no such voice"}}')
        if via == "openrouter":
            return self.answer(200, "audio/pcm;rate=24000", PCM, {"X-Generation-Id": "gen-1"})
        reply = {"steps": [{"type": "thought"}, {"type": "model_output", "content": [{"type": "audio", "data": base64.b64encode(wav_bytes()).decode()}]}]}
        self.answer(200, "application/json", json.dumps(reply).encode())

    def answer(self, code, kind, body, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)


def main():
    gemini.BACKOFF_S = 0.01
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Stub)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % server.server_address[1]
    logs = []
    with tempfile.TemporaryDirectory() as tmp:
        for via, path in (("openrouter", "/api/v1/audio/speech"), ("google", "/v1beta/interactions")):
            seen.clear()
            busy_once["left"] = 1
            raw = os.path.join(tmp, via, "raw")
            kept = os.path.join(tmp, via, "responses")
            items = [{"text": t, "voice": "Leda", "style": "small and shy", "out": os.path.join(raw, "slime", n + ".wav")}
                     for t, n in (("Blorp. Hello.", "a"), ("busy", "b"))]
            asked = gemini.render(items, KEY, kept, url=base + path, rpm=0, log=logs.append, via=via)
            check(asked == 2 and len(seen) == 3, "%s: two lines are two requests, and the busy one is asked again (%d, %d)" % (via, asked, len(seen)))
            first = seen[0]
            check(first["key"] == KEY and first["path"] == path, "%s: the key goes in its header, to its endpoint" % via)
            if via == "openrouter":
                check(first["body"] == {"model": "google/gemini-3.8-flash-tts", "input": "Blorp. Hello.", "voice": "Leda", "instructions": "small and shy", "response_format": "pcm"},
                      "openrouter: the body is the line, the voice, the style beside it, and pcm")
            else:
                item = first["body"]["input"][0]["content"][0]
                check(first["body"]["model"] == "gemini-3.8-flash-tts" and item["text"] == "Blorp. Hello." and item["annotations"] == [{"type": "speech_metadata", "style": "small and shy"}]
                      and first["body"]["generation_config"] == {"speech_config": [{"voice": "Leda"}]} and first["body"]["response_format"] == {"type": "audio"},
                      "google: the body is the transcript, its style as an annotation, the voice, and audio")
            for it in items:
                with wave.open(it["out"], "rb") as w:
                    good = (w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()) == (24000, 1, 2, 12000)
                check(good, "%s: %s is 24 kHz mono 16-bit, half a second" % (via, os.path.basename(it["out"])))
            saved = sorted(os.listdir(os.path.join(kept, "slime")))
            check(len([f for f in saved if not f.endswith(".headers.json")]) == 2, "%s: each reply is on disk as it arrived (%s)" % (via, saved))
            if via == "openrouter":
                check(open(os.path.join(kept, "slime", "a.pcm"), "rb").read() == PCM, "openrouter: byte for byte")
            before = len(seen)
            again = gemini.render(items, KEY, kept, url=base + path, rpm=0, log=logs.append, via=via)
            check(again == 0 and len(seen) == before, "%s: a second run reads the kept replies and asks nobody" % via)
            try:
                gemini.render([{"text": "refused", "voice": "Nobody", "style": "", "out": os.path.join(raw, "slime", "c.wav")}], KEY, kept, url=base + path, rpm=0, log=logs.append, via=via)
                check(False, "%s: a refusal stops the run" % via)
            except gemini.GeminiError as e:
                check("400" in str(e) and "no such voice" in str(e) and KEY not in str(e), "%s: a refusal stops the run and says why (%s)" % (via, e))
            check(not os.path.exists(os.path.join(raw, "slime", "c.wav")), "%s: and writes no audio" % via)
        leaked = [os.path.join(d, f) for d, _, fs in os.walk(tmp) for f in fs if KEY.encode() in open(os.path.join(d, f), "rb").read()]
        check(not leaked and not any(KEY in str(l) for l in logs), "the key is in no file and no log line")
    try:
        gemini.render([], "", "/nonexistent")
        check(False, "no key is refused")
    except gemini.GeminiError:
        check(True, "no key is refused before anything is asked")
    check(gemini.rate_of("audio/pcm;rate=16000") == 16000 and gemini.rate_of("audio/pcm") == 24000, "the sample rate is read from the reply when it names one")
    for bad, why in ((b'{"error": "x"}', "text"), (b"\x00" * 3, "an odd number of bytes"), (b"", "nothing")):
        try:
            gemini.as_wav(bad)
            check(False, "%s is not taken for audio" % why)
        except ValueError:
            check(True, "%s is not taken for audio" % why)
    cost = gemini.estimate([{"text": "x" * 1300, "style": ""}], "gemini-3.8-flash-tts")
    want_s = 1300 / gemini.CHARS_PER_S + 0.4
    check(abs(cost["seconds"] - want_s) < 0.01 and abs(cost["usd"] - (325 * 0.5 + want_s * 25 * 9.0) / 1e6) < 1e-9, "the estimate is the text in and 25 audio tokens a second out ($%.4f)" % cost["usd"])
    check(gemini.estimate([], "some-new-model")["usd"] is None, "a model with no listed price gets no made-up one")
    server.shutdown()
    print("test_gemini: %s" % ("all checks passed" if failed == 0 else "%d CHECK(S) FAILED" % failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
