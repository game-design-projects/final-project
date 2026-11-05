#!/usr/bin/env bash
# Cuts Abdulla's FluidSynth audition (issue #49) into one Ogg per section, for trying them in the game with the `motifs` feature.
# The sections go to build/motifs/, which git ignores and no export takes: its soundfont and license are not known yet, so
# none of this ships (see docs/AUDIO.md).
#
#   cut_motifs.sh <motif_audition.mp3> [out dir]
#
# A section is what lies between silences of 0.8 s or more under -50 dB. It is a one-shot: an MP3 pads its start and end, so
# it can't loop cleanly, and a loop has to be rendered from the source.
set -euo pipefail
cd "$(dirname "$0")/../.."

in=${1:?usage: cut_motifs.sh <motif_audition.mp3> [out dir]}
out=${2:-build/motifs}
FADE=0.02 # seconds at each end, so a cut can't click
QUALITY=6

mkdir -p "$out"
total=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
silences=$(ffmpeg -hide_banner -i "$in" -af silencedetect=noise=-50dB:d=0.8 -f null - 2>&1 | grep -oE 'silence_(start|end): [0-9.]+' || true)

start=0
n=0
cut() {
	local from=$1 to=$2
	local len
	len=$(awk -v a="$from" -v b="$to" 'BEGIN { printf "%.3f", b - a }')
	if awk -v l="$len" 'BEGIN { exit !(l < 1) }'; then
		return # what is left after the last silence
	fi
	n=$((n + 1))
	local fade_at
	fade_at=$(awk -v l="$len" -v f="$FADE" 'BEGIN { printf "%.3f", l - f }')
	ffmpeg -v error -y -ss "$from" -t "$len" -i "$in" -af "afade=t=in:d=$FADE,afade=t=out:st=$fade_at:d=$FADE" -c:a libvorbis -q:a "$QUALITY" "$out/motif-$n.ogg"
	echo "motif $n: $from to $to ($len s) -> $out/motif-$n.ogg"
}

while read -r word at; do
	case "$word" in
	silence_start:) cut "$start" "$at" ;;
	silence_end:) start=$at ;;
	esac
done <<<"$silences"
cut "$start" "$total"
echo "$n sections in $out"
