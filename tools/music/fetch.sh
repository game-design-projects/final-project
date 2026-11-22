#!/usr/bin/env bash
# Puts the parts of the VSCO-2 CE orchestra (CC0, https://github.com/sgossner/VSCO-2-CE) that build-themes.py plays into
# build/vsco2 (ignored by git, left out of every export): the strings, brass, woodwinds, the organ and some percussion,
# about 2 GB. Run once from anywhere; run again to update. VSCO2=/other/dir puts it elsewhere (orchestra.py reads it too).
#   tools/music/fetch.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="${VSCO2:-$root/build/vsco2}"
paths=('/Strings/' '/Brass/' '/Woodwinds/' '/Keys/Organ/' '/Percussion/Timpani/' '/Percussion/Glock/' '/Percussion/Marimba/'
	'/Percussion/Snare2-*' '/Percussion/Tamb1-*' '/Percussion/Triangle3-*' '/Percussion/BDrumNewhit_*' '/Percussion/cymbal-crash1_*'
	'/Percussion/susCymb1-*' '/Percussion/gongHit_*' '/LICENSE' '/README.md')

if [ ! -d "$dest/.git" ]; then
	git clone --filter=blob:none --no-checkout --depth 1 https://github.com/sgossner/VSCO-2-CE.git "$dest"
	git -C "$dest" sparse-checkout init --no-cone
fi
git -C "$dest" sparse-checkout set "${paths[@]}"
git -C "$dest" checkout master
git -C "$dest" pull --ff-only
echo "fetch: $(find "$dest" -name '*.wav' | wc -l | tr -d ' ') samples in $dest"
