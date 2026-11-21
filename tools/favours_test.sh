#!/usr/bin/env bash
# Plays four seeded games and checks that a favour goes all the way: asked, taken, done and paid. A fetch is paid on the
# spot, where the thing is handed over; a rid or a spare only after walking back to the asker once the monster it named is
# off the floor. The pilot used to stop at the empty cell, so over these four seeds every rid and spare was taken and left
# unpaid (11 taken, 3 paid, all three a fetch). Hence: all four games reach the stairs, at least four favours are taken, at
# least one is paid, and at least one of the paid ones is a rid or a spare — and at least one of those is a spare, which the
# pilot plays by taking SPARE whenever the kin it was asked for is the foe (killing it would fail the favour).
# These are the stray asker's and the floor lord's favours, so the games are played with `no-clan-requests`: with the clans'
# askers on (the default) those two stand on no floor, and the pilot steps past a clan's asker without taking its request
# (`tools/features_test.gd` plays those, a request at a time).
#   tools/favours_test.sh
# GODOT points at the Godot binary (default: godot on PATH); OUT is where the log goes (default: the run_tests.sh one).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=${OUT:-${TMPDIR:-/tmp}/donjon-tests}
mkdir -p "$OUT"
log="$OUT/on-favours.log"
: >"$log"
code=0
for seed in 7 11 23 47; do
	timeout 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound mock no-clan-requests "seed=$seed" >>"$log" 2>&1 || code=1
done
reached=$(grep -cE '^autoplay: 1 of 1' "$log" || true)
taken=$(grep -cE '^request: taken' "$log" || true)
paid=$(grep -cE '^requests: .* is paid' "$log" || true)
# Which askers wanted a rid or a spare, paired by name with the paid lines (a fetch pays without the walk back, so it can
# not tell this path from a broken one).
nonfetch=$(awk '
	# a new game has its own names: another seed may reuse one for another kind, so neither map carries over
	/^autoplay: seed [0-9]+ / {
		split("", wanted)
		split("", sparer)
	}
	/asks: / {
		line = $0
		if (line ~ /^lords: /) {
			name = substr(line, 8)
			sub(/, .*/, "", name)
		} else if (line ~ /^requests: /) {
			name = substr(line, 11)
			sub(/ the .*/, "", name)
		} else {
			next
		}
		kind = line
		sub(/.*asks: /, "", kind)
		sub(/ .*/, "", kind)
		if (kind == "rid" || kind == "spare") wanted[name] = 1
		if (kind == "spare") sparer[name] = 1
	}
	/^requests: / && / is paid/ {
		name = substr($0, 11)
		sub(/ is paid.*/, "", name)
		if (wanted[name]) paid++
		if (sparer[name]) spared++
	}
	END { print paid + 0, spared + 0 }
' "$log")
read -r nonfetch spare_paid <<<"$nonfetch"
if [ "$reached" != 4 ] || [ "$taken" -lt 4 ] || [ "$paid" -lt 1 ] || [ "$nonfetch" -lt 1 ] || [ "$spare_paid" -lt 1 ]; then
	code=1
fi
echo "on favours: exit $code, $reached of 4 games reached the stairs, $taken favours taken, $paid paid, $nonfetch of them a rid or a spare, $spare_paid a spare"
if [ "$code" != 0 ]; then
	grep -E 'SCRIPT ERROR|DID NOT FINISH' "$log" | cut -c1-220 | head -10 || true
fi
exit "$code"
