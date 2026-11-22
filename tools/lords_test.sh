#!/usr/bin/env bash
# Plays the default seeds and checks that a normal game has its clans' lords: a lord asks on the run's first floor of each
# biome (#154), and where that biome comes back the same lord asks its second, last favour, whose payment is the pact that
# swears the clan and opens its warren (#166). Two reports said no lord ever appeared in a default game and that the second
# favour was only reachable in the test room; this is the check that says otherwise, and it plays the seeds a player's first
# games use. Every game has to reach the stairs and meet at least one lord, one has to swear a clan, and the printout says
# how many lords each game met. The pilot walks up to an asker whose name it knows since #185; before that it skipped the
# second favour, which is why a favour check alone could not see the path.
#   tools/lords_test.sh
# GODOT points at the Godot binary (default: godot on PATH); OUT is where the log goes (default: the run_tests.sh one).
# The lord on its floor is what `no-clan-requests` plays: with the clans' askers on (the default) a lord stands in its clan's
# hall, behind two requests the pilot does not take, and on no floor of the run. So these games switch the askers off, as
# tools/favours_test.sh does; tools/features_test.gd walks to a lord in its hall.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=${OUT:-${TMPDIR:-/tmp}/donjon-tests}
mkdir -p "$OUT"
log="$OUT/on-lords.log"
: >"$log"
code=0

# timeout(1) is GNU coreutils: macOS has it only as gtimeout, and with neither a run is left to its own watchdog (autoplay's
# MAX_FRAMES), as tools/run_tests.sh and tools/favours_test.sh do.
if command -v timeout >/dev/null 2>&1; then LIMIT="timeout"
elif command -v gtimeout >/dev/null 2>&1; then LIMIT="gtimeout"
else
	LIMIT=""
	echo "note: no timeout(1) or gtimeout(1) here; each run is left to the game's own watchdog" >&2
fi

limit() {
	local secs="$1"; shift
	if [ -n "$LIMIT" ]; then "$LIMIT" "$secs" "$@"; else "$@"; fi
}

SEEDS=(1 2 3 4 5)
for seed in "${SEEDS[@]}"; do
	limit 170 "$GODOT" --headless --path . -s res://tools/autoplay.gd -- nosave nosound no-clan-requests "seed=$seed" >>"$log" 2>&1 || code=1
done
reached=$(grep -cE '^autoplay: seed [0-9]+ reached the last stairs' "$log" || true)
# per game: the summary line says how many lords it met and how many clans swore to it
read -r games fewest lords sworn <<EOF
$(grep -E '^autoplay: seed [0-9]+ ' "$log" | awk '
	{
		for (i = 1; i <= NF; i++) {
			if ($i == "lords") n = $(i + 1)
			if ($i == "sworn") s = $(i + 1)
		}
		games++
		total += n
		sworn += s
		if (games == 1 || n < fewest) fewest = n
	}
	END { printf "%d %d %d %d\n", games, fewest, total, sworn }')
EOF
if [ "$reached" != "${#SEEDS[@]}" ] || [ "$games" != "${#SEEDS[@]}" ] || [ "$fewest" -lt 1 ] || [ "$sworn" -lt 1 ]; then
	code=1
fi
echo "on lords: exit $code, $reached of ${#SEEDS[@]} games reached the stairs, $games said how many lords they met, the fewest was $fewest, $lords in all, $sworn sworn"
if [ "$code" != 0 ]; then
	grep -E 'DID NOT FINISH|SCRIPT ERROR|Parse Error|^autoplay: seed' "$log" | cut -c1-220 | head -10 || true
fi
exit "$code"
