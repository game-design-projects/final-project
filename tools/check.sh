#!/usr/bin/env bash
# Runs one headless tool and fails unless it finished and said it passed.
#   tools/check.sh res://tools/network_test.gd
#   tools/check.sh res://tools/autoplay.gd -- mock seed=313
# The exit code alone is not enough: Godot exits with 0 when the script it was given doesn't load (a parse error the import
# doesn't report, such as a member its parent class already has), so a suite that never ran would count as green.
# GODOT points at the Godot binary (default: godot on PATH).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
script=${1:?usage: tools/check.sh res://tools/<tool>.gd [-- flags]}
shift
log=$(mktemp)
trap 'rm -f "$log"' EXIT
"$GODOT" --headless --path . -s "$script" "$@" 2>&1 | tee "$log"
if ! grep -qE '(: all checks passed$|^autoplay: [0-9]+ of [0-9]+ games reached the stairs$)' "$log"; then
  echo "::error::$script exited with 0 but never said it passed (did it load?)"
  exit 1
fi
