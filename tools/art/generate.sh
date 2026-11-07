#!/usr/bin/env bash
# Draws one sheet with Codex's built-in image tool: tools/art/generate.sh <name> [reference.png ...]
# The prompt is prompts/_style.txt, prompts/_figure.txt for a character sheet, and prompts/<name>.txt. Every picture comes back into
# tools/art/raw/ (git-ignored) under a numbered name first, so a bad one is never lost or overwritten; tools/art/keep.sh promotes one.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name=${1:?usage: generate.sh <name> [reference.png ...]}; shift
figures=" slime bandit snake rock dragon witch trader "
mkdir -p "$here/raw"
n=1; while [[ -e "$here/raw/$name-$n.png" ]]; do n=$((n + 1)); done
out="$here/raw/$name-$n.png"
prompt=$(mktemp)
{
  echo "Use your built-in image_gen tool (no script, no API key) exactly once to generate the image below, then copy the resulting PNG from \$CODEX_HOME/generated_images/... to this exact path, and print the path and its pixel size. Do nothing else and change no other file."
  echo "Save to: $out"
  echo
  [[ $# -gt 0 ]] && echo "Input images: Image 1 is a style reference only: match its line weight, its wobble and its calm, cute feel, but do not copy its character."
  cat "$here/prompts/_style.txt"
  [[ $figures == *" $name "* ]] && cat "$here/prompts/_figure.txt"
  cat "$here/prompts/$name.txt"
} > "$prompt"
images=(); for r in "$@"; do images+=(-i "$r"); done
log="$here/raw/$name-$n.log"
t0=$(date +%s)
codex exec --skip-git-repo-check -s workspace-write --add-dir "$here/raw" -C "$here/raw" --json - ${images[@]+"${images[@]}"} < "$prompt" > "$log" 2>&1
rm -f "$prompt"
[[ -f $out ]] || { echo "$name: no picture came back, see $log" >&2; exit 1; }
echo "$name: $out in $(( $(date +%s) - t0 )) s"
