#!/usr/bin/env bash
# Plays the two ways through, over the pilot's five default seeds: the peaceful road, which never strikes, and the
# attack-only road, which never takes ACT or SPARE from the fight menu. Both have to reach the last stairs, and the
# attack-only games have to end with less health than the peaceful ones, because that cost is what makes the commands a
# choice rather than the same fight written twice (#163). Every attack-only game also has to take the fight menu, so a road
# whose branch stopped running is not the usual mix passing for it. A test, not a tool: it prints one line per road.
#   tools/roads_test.sh
# GODOT points at the Godot binary (default: godot on PATH); OUT is where the logs go (default: the run_tests.sh one).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=${OUT:-${TMPDIR:-/tmp}/donjon-tests}
mkdir -p "$OUT"
failed=0

# timeout(1) is GNU coreutils: macOS has it only as gtimeout, and with neither a run is left to its own watchdog (the
# suites' 90 s in tools/test_base.gd, autoplay's MAX_FRAMES). A system with no timeout says so once, rather than every
# command failing as "timeout: command not found" and the run looking like so many broken tests.
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout"
elif command -v gtimeout >/dev/null 2>&1; then LIMIT="gtimeout"
else
	LIMIT=""
	echo "note: no timeout(1) or gtimeout(1) here; each run is left to the game's own watchdog" >&2
fi

# Run the command that follows with a limit of $1 seconds, when the system has a timeout to give it.
limit() {
	local secs="$1"; shift
	if [ -n "$LIMIT" ]; then "$LIMIT" "$secs" "$@"; else "$@"; fi
}

# The summary line each game ends on, not the keepsakes' and floors' own lines, which carry a health figure too. A log
# with no summary line sums to 0, and the road then fails the check below instead of stopping this script.
health() {
	grep -E '^autoplay: seed' "$1" 2>/dev/null | sed -E 's/.* HP ([0-9]+)\/[0-9]+ .*/\1/' | awk '{s += $1} END {print s + 0}' || true
}

peace_log="$OUT/on-pacifist.log"
code=0
limit 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound pacifist >"$peace_log" 2>&1 || code=$?
if ! grep -qE '^autoplay: 5 of 5' "$peace_log" || grep -E '^autoplay: seed' "$peace_log" | grep -qvE ' slain 0 '; then
	code=1
fi
echo "on pacifist: exit $code, $(grep -E '^autoplay: [0-9]+ of' "$peace_log" || echo 'no verdict')"
if [ "$code" != 0 ]; then
	failed=1
	grep -E 'DID NOT FINISH|SCRIPT ERROR|Parse Error' "$peace_log" | cut -c1-220 | head -10 || true
fi

fight_log="$OUT/on-fight-only.log"
code=0
limit 200 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound fight-only >"$fight_log" 2>&1 || code=$?
fight_hp=$(health "$fight_log")
peace_hp=$(health "$peace_log")
# Each game must have taken the fight menu on this road: the usual mix also ends with less health than the peaceful one,
# so the cost comparison alone would pass with the road's own branch gone.
attack_menus=$(grep -cE '^autoplay: attack-only seed [0-9]+ took the fight menu [1-9][0-9]* times' "$fight_log" || true)
if ! grep -qE '^autoplay: 5 of 5' "$fight_log" || [ "$fight_hp" -ge "$peace_hp" ] || [ "$attack_menus" != 5 ]; then
	code=1
fi
echo "on fight-only: exit $code, $(grep -E '^autoplay: [0-9]+ of' "$fight_log" || echo 'no verdict'), $fight_hp health left against the peaceful road's $peace_hp, the fight menu taken in $attack_menus of 5 games"
if [ "$code" != 0 ]; then
	failed=1
	grep -E 'SCRIPT ERROR|DID NOT FINISH' "$fight_log" | cut -c1-220 | head -10 || true
fi

# Both roads reach the stairs and the attack-only one costs what the peaceful one saves, or a suite that only plays one
# road has stopped checking that the two are different.
exit "$failed"
