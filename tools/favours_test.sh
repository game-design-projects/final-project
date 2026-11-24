#!/usr/bin/env bash
# Plays four seeded games and checks that a favour goes all the way: asked, taken, done and paid. A fetch is paid on the
# spot, where the thing is handed over; a rid or a spare only after walking back to the asker once the monster it named is
# off the floor. The pilot used to stop at the empty cell, so over these four seeds every rid and spare was taken and left
# unpaid (11 taken, 3 paid, all three a fetch). Hence: all four games reach the stairs, at least four favours are taken, at
# least one is paid, and at least one of the paid ones is a rid or a spare — and at least one of those is a spare, which the
# pilot plays by taking SPARE whenever the kin it was asked for is the foe (killing it would fail the favour). A lord met on
# the first floor of a biome asks a second favour where that biome comes back; paying it swears the clan (and its lord joins),
# so at least one of those is checked too: the pilot used to skip a name it already knew, which left the pact unplayed.
# These are the stray asker's and the floor lord's favours, so the games are played with `no-clan-requests`: with the clans'
# askers on (the default) those two stand on no floor.
# Then the same four seeds as the game ships, with the clans' askers on (#259): the pilot takes their requests and does them, so
# at least four have to be taken, two paid, one clan's teleporter opened and walked through, and its lord heard out in its hall.
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

for seed in 7 11 23 47; do
	limit 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound mock no-clan-requests "seed=$seed" >>"$log" 2>&1 || code=1
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
pacts=$(grep -cE 'swears its clan to you' "$log" || true)
read -r nonfetch spare_paid <<<"$nonfetch"
if [ "$reached" != 4 ] || [ "$taken" -lt 4 ] || [ "$paid" -lt 1 ] || [ "$nonfetch" -lt 1 ] || [ "$spare_paid" -lt 1 ] || [ "$pacts" -lt 1 ]; then
	code=1
fi
echo "on favours: exit $code, $reached of 4 games reached the stairs, $taken favours taken, $paid paid, $nonfetch of them a rid or a spare, $spare_paid a spare, $pacts pacts"
if [ "$code" != 0 ]; then
	grep -E 'SCRIPT ERROR|DID NOT FINISH' "$log" | cut -c1-220 | head -10 || true
fi

# The clans' askers, as the game ships (#259).
asks="$OUT/on-requests.log"
: >"$asks"
asks_code=0
for seed in 7 11 23 47; do
	limit 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound mock "seed=$seed" >>"$asks" 2>&1 || asks_code=1
done
r_reached=$(grep -cE '^autoplay: 1 of 1' "$asks" || true)
r_taken=$(grep -cE '^envoys: [a-z_]+ taken' "$asks" || true)
r_done=$(grep -cE '^envoys: [a-z_]+ done' "$asks" || true)
r_opened=$(grep -cE "^envoys: .*'s teleporter is open" "$asks" || true)
r_through=$(grep -cE "^end: through .*'S TELEPORTER" "$asks" || true)
r_lords=$(grep -cE '^envoys: the lord of .* was heard out' "$asks" || true)
if [ "$r_reached" != 4 ] || [ "$r_taken" -lt 4 ] || [ "$r_done" -lt 2 ] || [ "$r_opened" -lt 1 ] || [ "$r_through" -lt 1 ] || [ "$r_lords" -lt 1 ]; then
	asks_code=1
fi
echo "on clan requests: exit $asks_code, $r_reached of 4 games reached the stairs, $r_taken requests taken, $r_done done, $r_opened teleporters opened, $r_through walked through, $r_lords lords heard out"
if [ "$asks_code" != 0 ]; then
	grep -E 'SCRIPT ERROR|DID NOT FINISH' "$asks" | cut -c1-220 | head -10 || true
	code=1
fi
exit "$code"
