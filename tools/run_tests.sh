#!/usr/bin/env bash
# Every test script and whole games with no window, with the features on (the default) and with `classic`, which is the game
# without them. Prints a line per suite and the failing checks; exits 1 if any failed.
#   tools/run_tests.sh            both modes
#   tools/run_tests.sh on         only the default
#   tools/run_tests.sh classic    only classic
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${TMPDIR:-/tmp}/donjon-tests"
mkdir -p "$OUT"
SUITES=(rules_test gameplay_test slice_test menu_test saves_test network_test view_test)
failed=0

run_mode() {
	local mode="$1"; shift
	local extra=("$@")
	for t in "${SUITES[@]}"; do
		local log="$OUT/$mode-$t.log"
		local code=0
		timeout 170 "$GODOT" --headless --path . -s "res://tools/$t.gd" -- nosave nosound ${extra[@]+"${extra[@]}"} >"$log" 2>&1 || code=$?
		local fails
		fails=$(grep -c ' FAIL ' "$log" || true)
		if ! grep -q 'all checks passed' "$log"; then
			code=1 # a script that doesn't parse never runs and still exits with 0
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

mode="${1:-both}"
if [ "$mode" = both ] || [ "$mode" = on ]; then
	SUITES+=(features_test) # it switches the features itself, so `classic` on the command line would only get in its way
	run_mode on
	unset 'SUITES[${#SUITES[@]}-1]'
fi
if [ "$mode" = both ] || [ "$mode" = classic ]; then
	run_mode classic classic
fi
exit "$failed"
