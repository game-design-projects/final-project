#!/usr/bin/env bash
# Makes the opening CG (assets/video/intro.ogv) from a rendered video. Godot plays Ogg Theora and nothing else, so the mp4
# a video model gives back is re-encoded: 30 fps, Theora quality 7 (crisp line art), Vorbis for the sound, brought up to the loudness
# of the game's music (about -16 LUFS: a render comes back near -23, which sounds weak next to it) with a true-peak ceiling.
# The picture is also graded toward the game's own: a render comes back with saturated gold and green fills, brighter and cleaner than the
# halls, which are bone-white lines on black with a glow and faint scanlines. So the colour is pulled down, the lines glow a little, and
# the corners darken. (Grading in RGB: ffmpeg's `eq` treats gbrp planes as YUV and turns the picture purple, so hue and curves are used.)
#   tools/intro_video.sh path/to/render.mp4
set -euo pipefail

cd "$(dirname "$0")/.."
src="${1:?usage: tools/intro_video.sh <rendered video>}"
out=assets/video/intro.ogv
mkdir -p assets/video
GRADE="hue=s=0.5,format=gbrp,curves=all='0/0 0.5/0.47 1/0.97',split[a][b];[b]gblur=sigma=7[g];[a][g]blend=all_mode=screen:all_opacity=0.6,vignette=PI/4.5,drawgrid=w=iw:h=3:t=1:c=black@0.12,format=yuv420p"
ffmpeg -v error -y -i "$src" -r 30 -vf "$GRADE" -c:v libtheora -q:v 7 -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ar 44100 -c:a libvorbis -q:a 3 "$out"
ls -l "$out" | awk '{printf "intro_video: %s, %.1f MB\n", $9, $5 / 1048576}'
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height -of default=nw=1 "$out" | tr '\n' ' '; echo
