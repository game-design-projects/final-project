#!/usr/bin/env bash
# Promote a drawing from raw/ to source/ as 8-bit grey (a tenth of the size), which is what process.py and git keep:
#   tools/art/keep.sh <name> <number>     (a figure's sheet is named <name>.set1 or <name>.set2)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
name=${1:?usage: keep.sh <name> <number>}; n=${2:?usage: keep.sh <name> <number>}
ffmpeg -y -v error -i "$here/raw/$name-$n.png" -pix_fmt gray -compression_level 100 "$here/source/$name.png"
ls -la "$here/source/$name.png"
