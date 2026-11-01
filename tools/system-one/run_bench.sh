#!/usr/bin/env bash
# run_bench.sh <gguf> <tag> <fixture names...> -- [llama-server args...]: start llama-server on 41715, bench each fixture sequentially
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); G=$HERE/../../tests/jev/golden; B=http://127.0.0.1:41715
OUT=${TMPDIR:-/tmp}; PY=${DECIDER_PY:-python3}  # DECIDER_PY: a python with decider-ai (run_sf.sh)
gguf=$1 tag=$2; shift 2; fixtures=(); while (($#)) && [[ $1 != -- ]]; do fixtures+=("$1"); shift; done; (($#)) && shift
pkill -f "llama-server -m $gguf" || true; sleep 1
llama-server -m "$gguf" --host 127.0.0.1 --port 41715 -c 16384 -np 1 --no-webui "$@" > "$OUT/server-$tag.log" 2>&1 &
for i in $(seq 1 90); do curl -s -m 2 $B/health | grep -q '"ok"' && break; sleep 1; done
curl -s -m 2 $B/health | grep -q '"ok"' || { echo "server $tag did not start"; tail -3 "$OUT/server-$tag.log"; exit 1; }
for f in "${fixtures[@]}"; do echo -n "$tag  "; python3 -I "$HERE/bench.py" $B "$G/$f.json" 1 "$OUT/ref-4b-$f.json"; done
