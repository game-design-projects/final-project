#!/usr/bin/env bash
# Turns a render (WAV or the old AAC .m4a) into the game's Ogg Vorbis file.
#
#   to_ogg.sh loop  <in> <out.ogg> <loop seconds>   a looping track, trimmed to exactly one loop
#                                                   (seconds may be an expression: 3840/132)
#   to_ogg.sh sting <in> <out.ogg>                  a one-shot, converted whole
#
# A render holds one loop plus a repeat of its first second (sampler.py TAIL). The loop is cut from
# LOOP_START (0.25 s in) for exactly floor(seconds * 44100) samples, so Godot's gapless Ogg loop wraps
# inside the music. The first 10 ms of the loop are cross-faded with the repeated material that follows
# the loop's end, so the wrap point is continuous even through a lossy encode.
#   src/audio/ambient.gd keeps LOOP_START = 0.25 because beat 0 of a render sits 0.25 s before the cut.
set -euo pipefail

SR=44100
LOOP_START_SAMPLES=11025 # 0.25 s
FADE_SAMPLES=441 # 10 ms
QUALITY=6

mode=${1:?usage: to_ogg.sh loop|sting <in> <out.ogg> [loop seconds]}
in=${2:?missing input}
out=${3:?missing output}

case "$mode" in
loop)
	seconds=${4:?missing loop seconds}
	[[ "$seconds" =~ ^[0-9+*/.\ ()-]+$ ]] || { echo "loop seconds must be a number or arithmetic: $seconds" >&2; exit 2; }
	# floor(seconds * 44100), with a hair of slack so 3840/126 * 44100 = 1343999.99999 still counts as 1344000
	len=$(awk -v sr="$SR" "BEGIN { printf \"%d\", ($seconds) * sr + 0.001 }")
	end=$((LOOP_START_SAMPLES + len))
	tail_end=$((end + FADE_SAMPLES))
	ffmpeg -v error -y -i "$in" -filter_complex "\
[0:a]aresample=$SR,asplit=2[x][y];\
[x]atrim=start_sample=$LOOP_START_SAMPLES:end_sample=$end,asetpts=N/SR/TB,afade=t=in:ss=0:d=$(awk -v n="$FADE_SAMPLES" -v sr="$SR" 'BEGIN { printf "%.6f", n / sr }'):curve=tri[a];\
[y]atrim=start_sample=$end:end_sample=$tail_end,asetpts=N/SR/TB,afade=t=out:ss=0:d=$(awk -v n="$FADE_SAMPLES" -v sr="$SR" 'BEGIN { printf "%.6f", n / sr }'):curve=tri,apad=whole_len=$len[b];\
[a][b]amix=inputs=2:normalize=0:duration=first[o]" \
		-map '[o]' -c:a libvorbis -q:a "$QUALITY" "$out"
	;;
sting)
	ffmpeg -v error -y -i "$in" -c:a libvorbis -q:a "$QUALITY" "$out"
	;;
*)
	echo "unknown mode: $mode" >&2
	exit 2
	;;
esac
