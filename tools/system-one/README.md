# System One model experiments

The scripts behind [docs/system-one-research.md](../../docs/system-one-research.md): how Decider reads the game's
Jev requests, how fast, and how well. They run against a `llama-server` on `127.0.0.1:41715` (or Decider's own server
on `41716`) and the golden requests in `tests/jev/golden/`. Godot ignores this folder.

| Script | Needs | What it prints |
| --- | --- | --- |
| `proto.py` | stdlib | (a module) the readout over llama-server that `src/jev/local.gd` ports: rows, prompt pieces, logit bias, temperatures |
| `compare.py <gguf> <base> <fixture>...` | decider-ai[gguf] | per fixture: prompt text and token parity with Decider's own GGUF engine, max probability difference |
| `run_bench.sh <gguf> <tag> <fixture>... [-- server args]` | llama-server | starts a server, then `bench.py`: wall time and prompt tokens for one row per question (`PRIME=1` sends the state first) |
| `bench.py <base> <fixture> <concurrency> [ref.json]` | stdlib | the same against a running server; `concurrency` > 1 needs a server started with `-np N` |
| `probe.py <base>` | stdlib | the perception questions of `enemy_turn` under seven player messages (temperatures: `TN`, `TS`) |
| `run_sf.sh <gguf> <tag> [server args]` | llama-server, decider-ai (`DECIDER_PY`) | starts a server, then `schema_first.py`: one round's cost with the question prefix cached |
| `probe_sf.py <base> <tokenizer dir> <T noul> <T score>` | decider-ai | the perception probe in the schema-first layout |
| `bench_s1.py <base> [runs]` | stdlib | latency of a `/v1/systemone` server (Decider's `decider.serve`) on the golden requests, and the probe |
| `prime_check.py <base> <fixture>` | stdlib | how far each row's probabilities move when read fresh, with the cache, or after priming |
| `run_all.sh <models dir> <decider python>` | llama-server, decider-ai | every llama-server measurement of the doc, GPU then CPU, in one go (~10 min on an RTX 4070 Ti SUPER) |

Server logs and reference files go to `$TMPDIR`. CPU-only runs: pass `-dev none -ngl 0` to llama-server.
