#!/usr/bin/env bash
# Makes the opening CG (assets/video/intro.ogv) from a rendered video. Godot plays Ogg Theora and nothing else, so the mp4
# a video model gives back is re-encoded: 30 fps, Theora quality 7 (crisp line art), Vorbis for the sound.
#   tools/intro_video.sh path/to/render.mp4
set -euo pipefail

cd "$(dirname "$0")/.."
src="${1:?usage: tools/intro_video.sh <rendered video>}"
out=assets/video/intro.ogv
mkdir -p assets/video
ffmpeg -v error -y -i "$src" -r 30 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 3 "$out"
ls -l "$out" | awk '{printf "intro_video: %s, %.1f MB\n", $9, $5 / 1048576}'
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height -of default=nw=1 "$out" | tr '\n' ' '; echo
