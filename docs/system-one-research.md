# Replacing Jev with an open-source System One model: research and evidence

Status: **for group discussion, nothing decided yet.** This page collects what was surveyed, what was built on
`feat/opensource-jev`, and every measurement taken, so the group can pick a route. Measured on 2026-10-29 on an
Apple M4 Pro laptop and on a Linux desktop with an NVIDIA RTX 4070 Ti SUPER.

## The question

Every monster decision in Donjon comes from **Jev**, TypeSafe's hosted System One model: the game sends a `state` and
typed questions (`noul` = yes/no, `choice`, `score`) and gets calibrated probabilities back, and the rules roll on them.
The ask was to replace it with the best **open-source** System One model, and the constraints that came up:

1. **Runs locally** (no hosted API, no key).
2. **Every platform**: macOS, Linux, Windows, each with or without a GPU, with or without CUDA / Metal (MPS).
3. **Feedback under 400 ms.**

What the game asks, per request (golden fixtures in `tests/jev/golden/`, tokens counted with Decider's tokenizer):

| Request | Questions | Prompt rows* | State tokens | Question tokens |
| --- | ---: | ---: | ---: | ---: |
| `enemy_turn` (one monster, the player talked) | 23 | 26 | 363 | 3,013 |
| `group_talk` (three monsters) | 73 | 80 (+2 with 11 options) | 982 | 8,500 |
| `ally_reactions_three` (after a fight) | 11 | 23 | 363 | 2,209 |

\* a `score` question becomes one yes/no row per level (Decider's "isolated levels").

Where `enemy_turn`'s question tokens go: one "which line fits" question per possible action (10 rows, 1,141 tokens),
the action choice (450), the feeling (433), kindness (4 rows, 219), the join reasons (356), target (96), the rest small.

## Models surveyed

| Model | Size | License | Local runtime | Jev wire format | Evidence | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **Decider** (Mapika) | 0.8B–35B; 2B and 4B have GGUF | Apache-2.0 | llama.cpp (GGUF), torch CUDA/MPS/CPU, own `/v1/systemone` server | yes | JevBench v1.5.2: decider-4b **71.3 (#7)** vs Jev 1.13 72.1; Decision Index sample: 4b v3 51.0, 2b v12 38.2 | **chosen** |
| Clef / Clef-flash (Cloudflare) | 27B / 9B | Apache-2.0 | Workers AI (hosted), vLLM / SGLang | yes | beats Jev on 7 of 10 of Cloudflare's benchmarks | too big to run locally on a CPU |
| d1 (Liquid AI) | 3B / 600M | LFM Open License (not OSI) | transformers; no decision path in GGUF | no | Decision Index 48.6 (3B) | license, no local decision runtime |
| pplx-decider (Perplexity) | 27B / 4B flash | Apache-2.0 | community GGUF / MLX | hosted only | Decision Index 61.6 (v1.1 27B) | 27B too big; no local server |
| Kev | 0.8B–27B | Apache-2.0 | MLX, ROCm, CUDA | yes | JevBench kev 4B 38.1, 8B 34.2 | weak |
| Vela 2.0 (KR Labs × vLLM SR) | 0.3B–9B encoder | Apache-2.0 | ONNX, Core ML | yes | safety / PII benchmarks only | trained for routing and guards |
| WaterSheep | ModernBERT-base | Apache-2.0 | ONNX (also in the browser) | yes | held-out 61.2% acc, ECE 0.043; GoEmotions 22% | too weak on feelings and social reads |
| Quyet, RSI-Jev, Torchcast, Drex | 9B–35B | various (Torchcast non-commercial) | vLLM / GGUF | some | Torchcast 27B DI 65.0 | too big, or license |

Why Decider: it is the only open model that is (a) Apache-2.0, (b) speaks Jev's exact wire format, (c) small enough
for a laptop (2B 1.3 GB, 4B 2.7 GB as Q4_K_M), (d) on par with Jev on JevBench at 4B, and (e) runs in llama.cpp,
which has official builds for every platform and backend (macOS Metal / x64, Linux CPU / Vulkan / CUDA / ROCm,
Windows CPU / Vulkan / CUDA / ROCm, arm64 too). Decider answers in one forward pass: the probability of each option
letter at an `Answer: (` slot, softmaxed at a temperature fitted per answer type.

## What is built on this branch (work in progress)

The game talks to any System One server, or to Decider through a stock `llama-server` with the readout in GDScript:

| File | What it does |
| --- | --- |
| `src/jev/jev.gd` | three ways in: `local` (Decider on llama-server), `systemone` (any `POST /v1/systemone` server, e.g. Decider's own), `mock`; no API key anywhere |
| `src/jev/decider.gd` | Decider's readout ported from decider-ai 1.10.0: prompt rows, Python-`json.dumps` state text, temperatures, confidence formulas, answer assembly; pinned model table |
| `src/jev/local.gd` | the `local` transport: primes llama-server with the state, then one `/completion` per row with a logit bias on the option letters |
| `src/jev/local_server.gd`, `local_setup.gd` | start/stop llama-server; download a pinned llama.cpp build (b11429, sha256-checked) and the pinned GGUF for this OS / backend |
| `src/jev/config.gd`, `http.gd` | decides the way in (mock flag, `config/jev_config.json`, the setup's `install.json`, else mock with a warning) |
| `tools/decider_golden.py`, `tests/jev/golden/decider/` | what Decider's own code makes of every golden request, for byte-for-byte tests |

All 476 tests and the mock scenarios pass (`godot --headless --path . -s res://tests/run_tests.gd`). Not done yet:
the GDScript tests for `decider.gd` / `local.gd` / `local_setup.gd`, game hooks (stop the server on quit, a
`setup-local` flag), wording in the UI that still says Jev, removing the Jev Worker (`proxy/`, `worker.yml`; its PR
check will fail because `jev.gd` changed), a cross-platform CI job, README / ARCHITECTURE / CHANGELOG.

## Evidence

Two machines:

- **M4 Pro**: Apple M4 Pro (10 performance + 4 efficiency cores, integrated GPU), macOS. llama.cpp b11429 (Homebrew
  llama.cpp 0.6.0), decider-ai 1.10.0, llama-cpp-python 0.3.36 (Metal), torch 2.15.0.
- **RTX**: NVIDIA GeForce RTX 4070 Ti SUPER (16 GB, driver 595.99.02, CUDA 13.2), Intel Core i7-14700K (20 cores,
  28 threads), Ubuntu 24.04. llama.cpp built from source with CUDA for sm_89 (commit `2092353`, 2026-09-07),
  decider-ai 1.10.0, torch 2.15.0+cu132.

"Metal" / "CUDA" = GPU (`-ngl 999`), "CPU" = `llama-server -dev none -ngl 0`. Models: `decider-4b-v3-Q4_K_M.gguf`,
`decider-2b-v12-Q4_K_M.gguf` (pinned revisions in `src/jev/decider.gd`, the same files on both machines, sha256
checked). Scripts in `tools/system-one/`.

### 1. The readout is exact

Against Decider's own GGUF engine (llama-cpp-python, the reference), per prompt row:

| Fixture | Rows | Prompt text equal | Tokens equal | max \|p_ref − p_ours\| |
| --- | ---: | ---: | ---: | ---: |
| vow | 6 | 6/6 | 6/6 | 0.0002 |
| ally_talk | 6 | 6/6 | 6/6 | 0.0001 |
| enemy_turn | 26 | 26/26 | 26/26 | 0.0009 |

All 213 rows of the 11 fixtures (including the 11-option rows, which put each label in its own token) tokenize to
exactly Decider's ids, and a mixed `[token ids…, "text"]` prompt gives the same probabilities as an all-ids one (max
difference 0.0). The same file gives probabilities up to 0.085 apart on CPU vs Metal (llama.cpp numerics).

On CUDA the batch split moves uncertain rows too: one row read fresh (no cache), with the cache, or after the state was
primed differs by up to 0.15 in `enemy_turn` and 0.21–0.36 in `group_talk` (mean 0.02; `vow` 0.02), at temperature 1.
The rows that move are close calls (0.59 / 0.41 → 0.81 / 0.19) or a 0.97 that drops to 0.85; at the calibrated
temperatures that is a shift of 0.07–0.11, and on each of the rows that moved most the answer stays on the same side
(`prime_check.py`).

### 2. Latency with one row per question (what `local.gd` does)

| Model | Machine | Backend | How | enemy_turn | group_talk | Prompt tokens run (enemy) |
| --- | --- | --- | --- | ---: | ---: | ---: |
| 4B | M4 Pro | Metal | rows, one after another | 7.2 s | 23.5 s | 4,455 |
| 4B | M4 Pro | Metal | 4 parallel slots | 15.9 s | 51.9 s | 10,867 |
| 2B | M4 Pro | Metal | rows | 5.4 s | 12.6 s | 8,854 |
| 2B | M4 Pro | CPU | rows | 35.9 s | – | 8,854 |
| 4B | M4 Pro | CPU | rows | 95.4 s | – | 8,854 |
| 2B | M4 Pro | CPU | **state primed first**, then rows | **13.8 s** | – | 3,013 |
| 4B | RTX | CUDA | rows | 2.02 s | 5.85 s | 8,854 |
| 4B | RTX | CUDA | state primed, rows | **1.67 s** | **4.77 s** | 3,013 |
| 2B | RTX | CUDA | rows | 0.94 s | 2.58 s | 8,854 |
| 2B | RTX | CUDA | state primed, rows | **0.78 s** | **2.08 s** | 3,013 |
| 2B | RTX | CPU (i7-14700K) | state primed, rows | 10.6 s | – | 3,013 |
| 4B | RTX | CPU (i7-14700K) | state primed, rows | 26.2 s | – | 3,013 |

The model's layers are partly recurrent, so llama.cpp can only resume from a checkpoint; sending the state alone
first puts one at its end, and every row then runs only its question (3,013 = exactly the question tokens). Parallel
slots are slower: each keeps its own cache. Throughput: 4B ~630 tok/s on Metal, ~3,500–4,400 on CUDA, ~95–115 on
CPU; 2B ~1,640 on Metal, ~8,000–9,400 on CUDA, ~220–285 on CPU. Estimated with priming on the M4 Pro: 4B Metal ~5 s,
2B Metal ~2 s, 4B CPU ~35 s per `enemy_turn`. On CUDA the rows are short (~115 tokens each), so per-request overhead
dominates: 26 primed rows take 1.67 s, ~64 ms each, at only ~2,100 tok/s.

### 3. Latency with every question cached and one forward pass (schema-first)

Decider also has a "schema-first" layout: all questions first (a prefix that can be cached across rounds), then the
state, then one `Answer k: (` slot per question, all read in one pass. llama-server can't read several slots in one
pass, so this is the server's time for the state plus slots after the question prefix was cached, i.e. the best case
for an engine that can (llama-cpp-python):

| Model | Machine | Backend | enemy_turn (516 tok) | group_talk (1,485 tok) | ally_reactions_three (432 tok) |
| --- | --- | --- | ---: | ---: | ---: |
| 2B | M4 Pro | Metal | **297 ms** | 963 ms | **255 ms** |
| 2B | M4 Pro | CPU | 2.9 s | 14.4 s | 2.1 s |
| 4B | M4 Pro | Metal | 752 ms | 2.5 s | 633 ms |
| 4B | M4 Pro | CPU | 7.6 s | 41.7 s | 5.0 s |
| 2B | RTX | CUDA | **42 ms** | **96 ms** | **34 ms** |
| 4B | RTX | CUDA | **93 ms** | **215 ms** | **83 ms** |
| 2B | RTX | CPU (i7-14700K) | 1.5 s | 5.6 s | 1.2 s |
| 4B | RTX | CPU (i7-14700K) | 4.1 s | 13.8 s | 3.3 s |

Reading the 23 `enemy_turn` slots through llama-server instead, one request each (what `probe_sf.py` does), takes
~1.1 s for the 4B and ~0.42 s for the 2B on CUDA: the one-pass numbers need an engine that returns every slot's
logits from one call.

### 4. Decider's official torch server

`decider.serve` (decider-ai 1.10.0): one row per question, the state shared across the rows
(`DECIDER_SHARED_MIN_TOKENS=64`), bf16 weights, median of 7 runs. On MPS it runs eager; on CUDA it captures CUDA graphs
at start-up.

| Model | Machine | vow (2 q) | ally_talk (2 q) | ally_reactions_three (11 q) | enemy_turn (23 q) | group_recruit (20 q) | group_talk (73 q) | Start-up |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2B | M4 Pro (MPS) | 1.13–1.21 s | – | – | 7.3–7.7 s | – | – | – |
| 2B | RTX (CUDA) | **128 ms** | **68 ms** | **235 ms** | 722 ms | 617 ms | 2.58 s | 47 s |
| 4B | RTX (CUDA) | **331 ms** | **156 ms** | 585 ms | 1.70 s | 1.45 s | out of memory | 58 s |

- The MPS numbers are the same with the optional MLX kernel installed.
- On CUDA it is about as fast as llama-server's primed rows (`enemy_turn`: 2B 0.78 s, 4B 1.67 s). It batches the rows,
  but its weights are bf16 where the GGUF is 4-bit.
- 16 GB of VRAM is tight. With the default graph budget the 2B captured 89 graphs in 214 s and ran out of memory on
  `group_talk`; `DECIDER_GRAPH_TOKEN_BUDGET=8192` fits it at the same speed. The 4B (8 GB of weights) runs out on
  `group_talk` even with `DECIDER_MAX_BATCH=8 DECIDER_GRAPH_TOKEN_BUDGET=4096`.
- Its noul answers come out as 0 or 1. The shipped `decider_config.json` sets the noul temperature to 0.05, tuned for
  JevBench's 0.2–0.8 band rule. The calibrated temperature that `src/jev/decider.gd` uses (4B 2.795, 2B 3.185) would
  need an edited config, because `DECIDER_TEMPERATURE` sets one temperature for every answer type.

### 5. Quality: does it read the player's words?

The `enemy_turn` slime, with `party.latest_message` replaced. Probabilities at the calibrated temperatures (noul 2.795
for the 4B, 3.185 for the 2B; kindness is a 0–3 score).

One row per question (sections 2 and 4):

| Message | 4B threat | insult | joke | asks to join | asks for peace | kindness | 2B threat | insult | joke | join | peace | kindness |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Hey little buddy. | .06 | .17 | .15 | .11 | .09 | 1.77 | .10 | .27 | .32 | .12 | .14 | 2.08 |
| Move or I'll squash you flat, you puddle. | **.95** | .76 | .16 | .04 | .15 | 0.50 | .69 | .43 | .09 | .11 | .12 | 0.49 |
| You're a disgusting blob of snot. | .12 | **.89** | .25 | .03 | .07 | 0.32 | .16 | .75 | .14 | .06 | .12 | 0.24 |
| Why did the slime cross the road? To get to the other slide! | .06 | .37 | **.87** | .11 | .11 | 1.49 | .16 | .25 | .42 | .18 | .11 | 0.98 |
| Want to come adventure with us? We'd love to have you. | .03 | .03 | .12 | **.95** | .10 | 2.38 | .09 | .09 | .13 | .24 | .07 | 2.19 |
| Please, let's not fight. Let us pass in peace. | .04 | .04 | .08 | .16 | **.94** | 2.22 | .17 | .10 | .09 | .12 | .74 | 2.02 |

Schema-first, one pass (section 3):

| Message | 4B threat | insult | joke | join | peace | kindness | 2B threat | insult | joke | join | peace | kindness |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Hey little buddy. | .07 | .40 | .30 | .14 | .09 | 1.30 | .22 | .50 | .67 | .22 | .34 | 1.52 |
| Move or I'll squash you flat, you puddle. | .90 | .74 | .39 | .14 | .61 | 0.53 | .87 | .43 | .21 | .27 | .51 | 0.48 |
| You're a disgusting blob of snot. | .17 | .89 | .54 | .08 | .13 | 0.39 | .21 | .77 | .62 | .14 | .40 | 0.50 |
| Why did the slime cross the road? … | .08 | .66 | .80 | .13 | .10 | 0.95 | .20 | .60 | .73 | .29 | .45 | 1.43 |
| Want to come adventure with us? … | .05 | .30 | .16 | .86 | .12 | 2.03 | .20 | .52 | .47 | .87 | .75 | 1.84 |
| Please, let's not fight. Let us pass in peace. | .09 | .51 | .13 | .19 | .83 | 1.19 | .80 | .59 | .25 | .71 | .90 | 1.93 |

On the RTX (CUDA) both probes read the same as on Metal: one row per question within 0.05 of the numbers above
(kindness within 0.19 on its 0–3 scale), schema-first within 0.04. The judgement is the model's, not the machine's.

Reading: the **4B one-row-per-question** reads every message right. The 2B is mushy (an open invitation to join
scores .24; the game needs ≥ .6). Schema-first keeps the 4B mostly right but noisier (a joke reads as .66 insult, a
plea for peace as .51 insult), and breaks the 2B (a plea for peace reads as a .80 threat). Decider's config says the
released models were not trained on schema-first (`"schema_first_trained": false`).

## What this means for "under 400 ms"

- **On an RTX 4070 Ti SUPER, the 4B schema-first round fits easily: 93 ms for `enemy_turn`, 215 ms for `group_talk`.**
  Its judgement is good but noisier than one row per question (section 5). It needs an engine that reads every slot
  in one pass (llama-cpp-python, or a small program on llama.cpp's C API). Through llama-server, one request per slot,
  the same round takes ~1.1 s.
- **The best reader (4B, one row per question) takes 1.7 s on that GPU**, both with llama-server (primed) and with
  Decider's CUDA-graph server. The rows are short, so per-request overhead takes the time. An engine that ran a
  request's rows as one batch from the shared state would process ~3,000 question tokens: ~0.45–0.55 s at the 4B's
  measured 5,500–6,900 tok/s. That is an estimate, not a measurement, and it sits at the edge of 400 ms rather than
  under it.
- **No configuration measured on the M4 Pro's GPU reaches 400 ms with judgement we would ship.** The only one under
  400 ms (2B, schema-first) misreads players. The best reader takes ~5 s. Batching would not help there: Metal runs
  the 4B at ~600–700 tok/s even in one pass, so it is compute-bound, not overhead-bound.
- **Without a GPU, 400 ms is out of reach** for any model of this quality. A desktop i7-14700K is 1.3–3 times as fast
  as the M4 Pro's CPU, and its cached best case is still 1.2–1.5 s (2B) and 3.3–4.1 s (4B) per round. Only
  ~150–300M encoder models could, and they read feelings poorly.

## Routes to discuss

Latencies are per `enemy_turn` (`group_talk` in brackets). "est." marks a value worked out from measured
throughput, not measured itself.

| Route | M4 Pro (Metal) | RTX 4070 Ti SUPER (CUDA) | Judgement | Work |
| --- | ---: | ---: | --- | --- |
| **A.** 4B, schema-first, one pass (a llama-cpp-python sidecar), request sent the moment the player commits so it overlaps the party's animations, and visible / audible feedback within 400 ms of every key | ~750 ms (2.5 s) | **~95 ms (215 ms)** | good, noisier than B | medium: Python sidecar per platform |
| **B.** keep what is built: 4B, one row per question on llama-server, plus the same overlap and instant feedback | ~5 s | 1.7 s (4.8 s) | best | small |
| **C.** A, plus shorter questions and only the state's changing parts after the cached prefix (target < 250 tokens per round) | maybe < 400 ms | well under | to be re-measured | large: rewrites the questions and the golden fixtures |
| **D.** B's rows, but all of a request's rows in one batch from the shared state (a small engine on llama.cpp's C API or llama-cpp-python) | ~4.5 s est. | ~0.5 s est. | best (same rows as B) | medium: the same sidecar as A, different readout |

Questions for the group:

1. Is 400 ms the **decision** (the monster's answer) or the **feedback** (the game visibly reacting to a key press,
   the Doherty threshold)? Route B already meets the second if we add the feedback.
2. What hardware do our players have: NVIDIA, Apple Silicon, or CPU only?
3. When latency and judgement conflict, which wins?
4. Only an NVIDIA GPU gets a decision under 400 ms (route A). Is it enough that decisions are fast there and take
   seconds, behind instant feedback, everywhere else?

## Reproducing

```bash
M=~/decider-models   # outside the repo, so Godot doesn't scan gigabytes
hf download Mapika/decider-4b-GGUF decider-4b-v3-Q4_K_M.gguf tokenizer.json decider_config.json --local-dir $M/decider-4b
hf download Mapika/decider-2b-GGUF decider-2b-v12-Q4_K_M.gguf tokenizer.json decider_config.json --local-dir $M/decider-2b
uv venv $M/ref && uv pip install -p $M/ref/bin/python "decider-ai[gguf,serve]==1.10.0"   # Decider's own code, the reference
#   ([serve] alone covers everything but compare.py, and skips building llama-cpp-python on Linux / Windows)
# plus a llama-server (llama.cpp b11429 or later) on PATH

tools/system-one/run_all.sh $M $M/ref/bin/python        # sections 1 (priming), 2, 3 and 5 in one go, GPU then CPU
# or one at a time:
tools/system-one/run_bench.sh $M/decider-4b/decider-4b-v3-Q4_K_M.gguf 4b-gpu enemy_turn group_talk            # section 2
PRIME=1 tools/system-one/run_bench.sh $M/decider-2b/decider-2b-v12-Q4_K_M.gguf 2b-cpu enemy_turn -- -dev none -ngl 0
DECIDER_PY=$M/ref/bin/python tools/system-one/run_sf.sh $M/decider-2b/decider-2b-v12-Q4_K_M.gguf 2b-gpu       # section 3
# with a llama-server on 127.0.0.1:41715 (run_bench.sh leaves one running):
python3 tools/system-one/probe.py http://127.0.0.1:41715                                                       # section 5, rows
$M/ref/bin/python tools/system-one/probe_sf.py http://127.0.0.1:41715 $M/decider-4b 2.795 3.152                # section 5, schema-first
$M/ref/bin/python tools/system-one/compare.py $M/decider-4b/decider-4b-v3-Q4_K_M.gguf http://127.0.0.1:41715 tests/jev/golden/enemy_turn.json   # section 1
# Decider's torch server (section 4); needs the full model folder: hf download Mapika/decider-2b --local-dir $M/hf-decider-2b
# on a 16 GB NVIDIA card add DECIDER_GRAPH_TOKEN_BUDGET=8192, or group_talk runs out of memory
DECIDER_MODEL=$M/hf-decider-2b DECIDER_SHARED_MIN_TOKENS=64 $M/ref/bin/uvicorn decider.serve:app --port 41716 &
python3 tools/system-one/bench_s1.py http://127.0.0.1:41716
```

`tools/system-one/README.md` says what each script does.

## Sources

[Jev on OpenRouter](https://openrouter.ai/docs/guides/community/jev) ·
[Decider](https://github.com/Mapika/decider) · [decider-4b-GGUF](https://huggingface.co/Mapika/decider-4b-GGUF) ·
[Clef on Workers AI](https://developers.cloudflare.com/workers-ai/models/clef/) ·
[Clef launch](https://developers.cloudflare.com/changelog/post/2026-10-01-clef-workers-ai/) ·
[d1](https://www.liquid.ai/blog/d1-open) · [Vela 2.0](https://huggingface.co/vllm-sr/Vela-2.0-0.3B) ·
[WaterSheep](https://github.com/SamratDuttaOfficial/WaterSheep) ·
[awesome-system-one](https://github.com/raullenchai/awesome-system-one) ·
[JevBench](https://benchlm.ai/benchmarks/jevbench) · [systemonemodels.org](https://systemonemodels.org/) ·
[llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)
