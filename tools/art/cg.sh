#!/usr/bin/env bash
# Draws the story CGs (docs/ART.md, "Story CGs") with Codex: tools/art/cg.sh [name ...] (names without the cg_ prefix; none = every
# cg_* in sheets.json that has no tools/art/source/<name>.png yet). Each one is generate.sh with the keyart as the style reference and
# the character references its sheets.json entry lists (`refs`, cut by cg_refs.py). JOBS (default 4) draw at once. A take lands in
# raw/ as usual; keep it with tools/art/keep.sh cg_<name> <n>.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
jobs=${JOBS:-4}
uv run --script "$here/cg_refs.py" > /dev/null
if [[ $# -gt 0 ]]; then
  names=(); for n in "$@"; do names+=("cg_${n#cg_}"); done
else
  names=(); while IFS= read -r n; do [[ -e "$here/source/$n.png" ]] || names+=("$n"); done < <(jq -r 'keys[] | select(startswith("cg_"))' "$here/sheets.json")
fi
echo "cg: drawing ${#names[@]} (${jobs} at once): ${names[*]}"
draw() {
  local name=$1 refs=("$here/raw/refs/style.png")
  while IFS= read -r r; do refs+=("$here/raw/refs/$r.png"); done < <(jq -r --arg n "$name" '.[$n].refs[]?' "$here/sheets.json")
  "$here/generate.sh" "$name" "${refs[@]}" || echo "cg: $name failed" >&2
}
running=0
for name in "${names[@]}"; do
  draw "$name" &
  running=$((running + 1))
  if (( running >= jobs )); then wait; running=0; fi # in batches: macOS bash 3.2 has no wait -n
done
wait
