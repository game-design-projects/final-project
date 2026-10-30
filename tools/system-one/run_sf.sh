#!/usr/bin/env bash
# run_sf.sh <gguf> <tag> [llama-server args...]: start llama-server on 41715 and time schema-first rounds
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); G=$HERE/../../tests/jev/golden; B=http://127.0.0.1:41715
OUT=${TMPDIR:-/tmp}; PY=${DECIDER_PY:-python3}  # DECIDER_PY: a python with decider-ai (run_sf.sh)
gguf=$1 tag=$2; shift 2
pkill -f "llama-server -m $gguf" || true; sleep 1
llama-server -m "$gguf" --host 127.0.0.1 --port 41715 -c 16384 -np 1 --no-webui "$@" > "$OUT/server-$tag.log" 2>&1 &
for i in $(seq 1 90); do curl -s -m 2 $B/health | grep -q '"ok"' && break; sleep 1; done
echo "== $tag"
"$PY" -I "$HERE/schema_first.py" $B "$(dirname "$gguf")" $G/enemy_turn.json $G/group_talk.json $G/ally_reactions_three.json 2>&1 | grep -v -i warn
