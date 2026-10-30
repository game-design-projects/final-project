# Replacing Jev with an open-source System One model: research and evidence

Status: **for group discussion, nothing decided yet.** This page collects what was surveyed, what was built on
`feat/opensource-jev`, and every measurement taken, so the group can pick a route. Measured on 2026-10-29.

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

Machine: Apple M4 Pro (10 performance + 4 efficiency cores, integrated GPU), macOS. llama.cpp b11429 (Homebrew
llama.cpp 0.6.0), decider-ai 1.10.0, llama-cpp-python 0.3.36 (Metal), torch 2.15.0. "Metal" = GPU, "CPU" =
`llama-server -dev none -ngl 0`. Models: `decider-4b-v3-Q4_K_M.gguf`, `decider-2b-v12-Q4_K_M.gguf` (pinned revisions in
`src/jev/decider.gd`). Scripts in `tools/system-one/`.

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

### 2. Latency with one row per question (what `local.gd` does)

| Model | Backend | How | enemy_turn | group_talk | Prompt tokens run (enemy) |
| --- | --- | --- | ---: | ---: | ---: |
| 4B | Metal | rows, one after another | 7.2 s | 23.5 s | 4,455 |
| 4B | Metal | 4 parallel slots | 15.9 s | 51.9 s | 10,867 |
| 2B | Metal | rows | 5.4 s | 12.6 s | 8,854 |
| 2B | CPU | rows | 35.9 s | – | 8,854 |
| 4B | CPU | rows | 95.4 s | – | 8,854 |
| 2B | CPU | **state primed first**, then rows | **13.8 s** | – | 3,013 |

The model's layers are partly recurrent, so llama.cpp can only resume from a checkpoint; sending the state alone
first puts one at its end, and every row then runs only its question (3,013 = exactly the question tokens). Parallel
slots are slower: each keeps its own cache. Throughput: 4B ~630 tok/s on Metal, ~95 on CPU; 2B ~1,640 on Metal,
~220–250 on CPU. Estimated with priming: 4B Metal ~5 s, 2B Metal ~2 s, 4B CPU ~35 s per `enemy_turn`.

### 3. Latency with every question cached and one forward pass (schema-first)

Decider also has a "schema-first" layout: all questions first (a prefix that can be cached across rounds), then the
state, then one `Answer k: (` slot per question, all read in one pass. llama-server can't read several slots in one
pass, so this is the server's time for the state plus slots after the question prefix was cached, i.e. the best case
for an engine that can (llama-cpp-python):

| Model | Backend | enemy_turn (516 tok) | group_talk (1,485 tok) | ally_reactions_three (432 tok) |
| --- | --- | ---: | ---: | ---: |
| 2B | Metal | **297 ms** | 963 ms | **255 ms** |
| 2B | CPU | 2.9 s | 14.4 s | 2.1 s |
| 4B | Metal | 752 ms | 2.5 s | 633 ms |
| 4B | CPU | 7.6 s | 41.7 s | 5.0 s |

### 4. Decider's official torch server

`decider.serve` (decider-ai 1.10.0) on MPS with the 2B, shared prefix on (`DECIDER_SHARED_MIN_TOKENS=64`), eager
(CUDA graphs are CUDA only): **vow 1.13–1.21 s, enemy_turn 7.3–7.7 s**, the same with the optional MLX kernel
installed. On NVIDIA GPUs the same server uses CUDA graphs; its author reports a few ms per short request there. Not
measured here (no NVIDIA GPU on this machine).

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

Reading: the **4B one-row-per-question** reads every message right. The 2B is mushy (an open invitation to join
scores .24; the game needs ≥ .6). Schema-first keeps the 4B mostly right but noisier (a joke reads as .66 insult, a
plea for peace as .51 insult), and breaks the 2B (a plea for peace reads as a .80 threat). Decider's config says the
released models were not trained on schema-first (`"schema_first_trained": false`).

## What this means for "under 400 ms"

- **No configuration measured on the M4 Pro's GPU reaches 400 ms with judgement we would ship.** The only one under
  400 ms (2B, schema-first) misreads players. The best reader (4B, one row per question) takes ~5 s.
- **Without a GPU, 400 ms is out of reach** for any model of this quality: the CPU runs the 2B at ~220 tok/s, and even
  the cached best case is 2.1–2.9 s per round. Only ~150–300M encoder models could, and they read feelings poorly.
- **Discrete NVIDIA GPUs are the unknown**: llama.cpp CUDA and Decider's CUDA-graph server are both far faster than
  Metal here; someone with an NVIDIA card should run `tools/system-one/`.

## Routes to discuss

| Route | Decision latency on the M4 Pro | Judgement | Work |
| --- | --- | --- | --- |
| **A.** 4B, schema-first, one pass (a llama-cpp-python sidecar), request sent the moment the player commits so it overlaps the party's animations, and visible / audible feedback within 400 ms of every key | ~750 ms (NVIDIA likely ~200 ms) | good, noisier than B | medium: Python sidecar per platform |
| **B.** keep what is built: 4B, one row per question on llama-server, plus the same overlap and instant feedback | ~5 s | best | small |
| **C.** A, plus shorter questions and only the state's changing parts after the cached prefix (target < 250 tokens per round) | maybe < 400 ms | to be re-measured | large: rewrites the questions and the golden fixtures |

Questions for the group:

1. Is 400 ms the **decision** (the monster's answer) or the **feedback** (the game visibly reacting to a key press,
   the Doherty threshold)? Route B already meets the second if we add the feedback.
2. What hardware do our players have: NVIDIA, Apple Silicon, or CPU only?
3. When latency and judgement conflict, which wins?
4. Can someone with an NVIDIA GPU run the benchmarks below?

## Reproducing

```bash
M=~/decider-models   # outside the repo, so Godot doesn't scan gigabytes
hf download Mapika/decider-4b-GGUF decider-4b-v3-Q4_K_M.gguf tokenizer.json decider_config.json --local-dir $M/decider-4b
hf download Mapika/decider-2b-GGUF decider-2b-v12-Q4_K_M.gguf tokenizer.json decider_config.json --local-dir $M/decider-2b
uv venv $M/ref && uv pip install -p $M/ref/bin/python "decider-ai[gguf,serve]==1.10.0"   # Decider's own code, the reference
# plus a llama-server (llama.cpp b11429 or later) on PATH

tools/system-one/run_bench.sh $M/decider-4b/decider-4b-v3-Q4_K_M.gguf 4b-gpu enemy_turn group_talk            # section 2
PRIME=1 tools/system-one/run_bench.sh $M/decider-2b/decider-2b-v12-Q4_K_M.gguf 2b-cpu enemy_turn -- -dev none -ngl 0
DECIDER_PY=$M/ref/bin/python tools/system-one/run_sf.sh $M/decider-2b/decider-2b-v12-Q4_K_M.gguf 2b-gpu       # section 3
# with a llama-server on 127.0.0.1:41715 (run_bench.sh leaves one running):
python3 tools/system-one/probe.py http://127.0.0.1:41715                                                       # section 5, rows
$M/ref/bin/python tools/system-one/probe_sf.py http://127.0.0.1:41715 $M/decider-4b 2.795 3.152                # section 5, schema-first
$M/ref/bin/python tools/system-one/compare.py $M/decider-4b/decider-4b-v3-Q4_K_M.gguf http://127.0.0.1:41715 tests/jev/golden/enemy_turn.json   # section 1
# Decider's torch server (section 4); needs the full model folder: hf download Mapika/decider-2b --local-dir $M/hf-decider-2b
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
