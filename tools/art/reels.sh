#!/usr/bin/env bash
# Makes GIFs of the clips tools/art_shots.gd recorded: tools/art/reels.sh <dir with clips> <out dir> [fps]
# It crops to the picture, which has the same place in every frame at the size the tool's window has.
set -euo pipefail
from=${1:?usage: reels.sh <clips dir> <out dir> [fps]}; out=${2:?usage: reels.sh <clips dir> <out dir> [fps]}; fps=${3:-20}
mkdir -p "$out"
for clip in "$from"/*/; do
	name=$(basename "$clip")
	ffmpeg -y -v error -framerate "$fps" -i "$clip/%04d.png" \
		-vf "crop=iw-44:ih*0.665:22:ih*0.062,fps=12,scale=448:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=32:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
		"$out/$name.gif"
	ls -la "$out/$name.gif"
done
