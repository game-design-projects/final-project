#!/usr/bin/env bash
# run_all.sh <models dir> <python with decider-ai>: every llama-server measurement of docs/system-one-research.md, on the
# GPU (-ngl 999: CUDA, Metal or Vulkan) and then the CPU. Needs a llama-server on PATH; <models dir> holds decider-4b/ and
# decider-2b/ as the doc's hf download leaves them. About ten minutes on an RTX 4070 Ti SUPER.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); G=$HERE/../../tests/jev/golden; B=http://127.0.0.1:41715
M=$(cd "$1" && pwd); PY=$2
G4=$M/decider-4b/decider-4b-v3-Q4_K_M.gguf; G2=$M/decider-2b/decider-2b-v12-Q4_K_M.gguf
stop() { pkill -f "llama-server -m $M/" || true; sleep 2; }
log() { echo; echo "=== $* ($(date +%T))"; }

llama-server --version 2>&1 | tail -2
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null || true

for m in 4b 2b; do
  if [[ $m == 4b ]]; then g=$G4 t=(2.795 3.152); else g=$G2 t=(3.185 2.833); fi
  stop; log "$m gpu rows"
  "$HERE/run_bench.sh" "$g" $m-gpu enemy_turn group_talk -- -ngl 999
  log "$m gpu rows, state primed"
  PRIME=1 "$HERE/run_bench.sh" "$g" $m-gpu-primed enemy_turn group_talk -- -ngl 999
  log "$m gpu priming check"
  python3 -I "$HERE/prime_check.py" $B "$G/enemy_turn.json"
  log "$m gpu probe (rows)"
  TN=${t[0]} TS=${t[1]} python3 -I "$HERE/probe.py" $B
  stop; log "$m gpu schema-first"
  DECIDER_PY=$PY "$HERE/run_sf.sh" "$g" $m-gpu-sf -ngl 999
  log "$m gpu probe (schema-first)"
  "$PY" -I "$HERE/probe_sf.py" $B "$(dirname "$g")" "${t[@]}"
done

for m in 2b 4b; do
  g=$G4; [[ $m == 2b ]] && g=$G2
  stop; log "$m cpu rows, state primed"
  PRIME=1 "$HERE/run_bench.sh" "$g" $m-cpu-primed enemy_turn -- -dev none -ngl 0
  stop; log "$m cpu schema-first"
  DECIDER_PY=$PY "$HERE/run_sf.sh" "$g" $m-cpu-sf -dev none -ngl 0
done
stop; log done
