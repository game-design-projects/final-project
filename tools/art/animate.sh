#!/usr/bin/env bash
# Draws continuous animation frames with Codex: tools/art/animate.sh <character> <action> <reference.png>
# The prompt is prompts/_style.txt, prompts/_anim.txt and prompts/<character>.<action>.txt, or prompts/_action.<action>.txt with the
# character's own description. The picture lands in tools/art/raw/<character>.<action>-<n>.png, numbered so nothing is overwritten.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
who=${1:?usage: animate.sh <character> <action> <reference.png>}; act=${2:?action}; ref=${3:?reference}
mkdir -p "$here/raw"
n=1; while [[ -e "$here/raw/$who.$act-$n.png" ]]; do n=$((n + 1)); done
out="$here/raw/$who.$act-$n.png"
prompt=$(mktemp)
{
  echo "Use your built-in image_gen tool (no script, no API key) exactly once to generate the image below, then copy the resulting PNG from \$CODEX_HOME/generated_images/... to this exact path, and print the path and its pixel size. Do nothing else and change no other file."
  echo "Save to: $out"
  echo
  echo "Input images: Image 1 is the character sheet. Use its top-left pose as the resting pose, and keep the character's design exactly."
  cat "$here/prompts/_style.txt" "$here/prompts/_anim.txt"
  sed -e '/^Input images:/d' "$here/prompts/$who.txt"
  if [[ -f "$here/prompts/$who.$act.txt" ]]; then cat "$here/prompts/$who.$act.txt"; else cat "$here/prompts/_action.$act.txt"; fi
} > "$prompt"
log="$here/raw/$who.$act-$n.log"
t0=$(date +%s)
codex exec --skip-git-repo-check -s workspace-write --add-dir "$here/raw" -C "$here/raw" --json - -i "$ref" < "$prompt" > "$log" 2>&1
rm -f "$prompt"
[[ -f $out ]] || { echo "$who.$act: no picture came back, see $log" >&2; exit 1; }
echo "$who.$act: $out in $(( $(date +%s) - t0 )) s"
