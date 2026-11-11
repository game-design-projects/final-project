#!/usr/bin/env bash
# Every test script and whole games with no window: as the game ships, with no feature switched off (features_test switches
# them itself), then with no strike, from the practice floor and with skill-combat. Prints a line per suite and the failing
# checks; exits 1 if any failed.
#   tools/run_tests.sh
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${TMPDIR:-/tmp}/donjon-tests"
mkdir -p "$OUT"
SUITES=(social_test moods_test rules_test gameplay_test menu_test saves_test network_test view_test audio_test map_test meta_test art_test features_test)
failed=0

run_mode() {
	local mode="$1"; shift
	local extra=("$@")
	for t in "${SUITES[@]}"; do
		local log="$OUT/$mode-$t.log"
		local code=0
		local sound=nosound
		if [ "$t" = audio_test ]; then
			sound="" # it builds the audio buses
		fi
		timeout 170 "$GODOT" --headless --path . -s "res://tools/$t.gd" -- nosave $sound ${extra[@]+"${extra[@]}"} >"$log" 2>&1 || code=$?
		local fails
		fails=$(grep -c ' FAIL ' "$log" || true)
		if ! grep -q 'all checks passed' "$log"; then
			code=1 # a script that doesn't parse never runs and still exits with 0
		fi
		if grep -q 'SCRIPT ERROR' "$log"; then
			code=1 # an error in the middle of a check ends that check and the run still says all passed
		fi
		echo "$mode $t: exit $code, $fails failed"
		if [ "$code" != 0 ]; then
			failed=1
			grep -E ' FAIL |SCRIPT ERROR|Parse Error' "$log" | cut -c1-220 | head -20 || true
		fi
	done
	local log="$OUT/$mode-autoplay.log"
	local code=0
	timeout 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound ${extra[@]+"${extra[@]}"} >"$log" 2>&1 || code=$?
	if ! grep -qE '^autoplay: [0-9]+ of' "$log"; then
		code=1 # as above: a script that doesn't parse exits with 0
	fi
	echo "$mode autoplay: exit $code, $(grep -E '^autoplay: [0-9]+ of' "$log" || echo 'no verdict')"
	if [ "$code" != 0 ]; then
		failed=1
		grep -E 'DID NOT FINISH|SCRIPT ERROR|Parse Error' "$log" | cut -c1-220 | head -10 || true
	fi
}

run_mode on
# A run with no strike in it, start to end: the peaceful way through has to stay open.
log="$OUT/on-pacifist.log"
code=0
timeout 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound pacifist >"$log" 2>&1 || code=$?
if ! grep -qE '^autoplay: 5 of 5' "$log" || grep -E '^autoplay: seed' "$log" | grep -qvE ' slain 0 '; then
	code=1
fi
echo "on pacifist: exit $code, $(grep -E '^autoplay: [0-9]+ of' "$log" || echo 'no verdict')"
if [ "$code" != 0 ]; then
	failed=1
fi
# A first run, which starts on the practice floor and has to get from it to the end like any other.
log="$OUT/on-practice.log"
code=0
timeout 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound practice >"$log" 2>&1 || code=$?
if ! grep -qE '^autoplay: 5 of 5' "$log"; then
	code=1
fi
# reaching the end proves little: each of the 5 games must also have started on the practice floor and left it by its stairs
if [ "$(grep -c 'flow: new run, seed [0-9]*, on the practice floor' "$log" || true)" != 5 ] || [ "$(grep -c 'end: the practice floor done' "$log" || true)" != 5 ]; then
	echo "on practice: not every game played the practice floor"
	code=1
fi
echo "on practice: exit $code, $(grep -E '^autoplay: [0-9]+ of' "$log" || echo 'no verdict')"
if [ "$code" != 0 ]; then
	failed=1
fi
# skill-combat is off unless named: play it through too.
log="$OUT/on-skill-combat.log"
code=0
timeout 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound skill-combat >"$log" 2>&1 || code=$?
if ! grep -qE '^autoplay: 5 of 5' "$log"; then
	code=1
fi
echo "on skill-combat: exit $code, $(grep -E '^autoplay: [0-9]+ of' "$log" || echo 'no verdict')"
if [ "$code" != 0 ]; then
	failed=1
fi
exit "$failed"
