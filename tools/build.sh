#!/usr/bin/env bash
# Exports the game into build/<platform>/ and zips each one as build/donjon-<version>-<platform>.zip.
#   tools/build.sh                                # every platform (web windows macos linux), monsters think with the local rules
#   tools/build.sh web macos                      # only some
#   tools/build.sh --proxy https://donjon-api.<you>.workers.dev [platforms...]
#                                                 # monsters ask Jev through your Worker (proxy/), which holds the key:
#                                                 # nothing secret ships, only the Worker's address
# GODOT points at the Godot 4.7 binary (default: godot on PATH), with export templates installed for it.
# The export presets are written here (export_presets.cfg is not committed) so CI and a laptop build the same way.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
proxy_file=config/jev_url.txt
cleanup() { rm -f "$proxy_file" export_presets.cfg; }
trap cleanup EXIT

base=""
platforms=()
while (($#)); do
  case "$1" in
    --proxy) base=${2:-}; shift ;;
    web|windows|macos|linux) platforms+=("$1") ;;
    *) echo "usage: tools/build.sh [--proxy <url>] [web windows macos linux]" >&2; exit 1 ;;
  esac
  shift
done
((${#platforms[@]})) || platforms=(web windows macos linux)

mkdir -p config build
if [[ -n $base ]]; then
  [[ $base =~ ^https://|^http://localhost(:[0-9]+)?$ ]] || { echo "--proxy needs the Worker's address, e.g. https://donjon-api.you.workers.dev" >&2; exit 1; }
  printf '%s\n' "${base%/}" > "$proxy_file" # the game reads it (src/mind/minds.gd) when no address is saved or given
else
  rm -f "$proxy_file"
fi

# One preset per platform: everything in the project except the tools and the unused voice bank, plus config/ and the text
# files of assets/ (CREDITS.txt: Godot ships only resources unless an include filter names the rest). The web build has its own page.
cat > export_presets.cfg <<'PRESETS'
[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="config/*, assets/*.txt"
exclude_filter="tools/*, proxy/*, docs/*, build/*, assets/voices/qwen3/*"
export_path=""

[preset.0.options]
variant/thread_support=false
variant/extensions_support=false
html/export_icon=true
html/custom_html_shell="res://web/shell.html"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true

[preset.1]
name="Windows"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="config/*, assets/*.txt"
exclude_filter="tools/*, proxy/*, docs/*, build/*, assets/voices/qwen3/*"
export_path=""

[preset.1.options]
binary_format/embed_pck=true
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false

[preset.2]
name="macOS"
platform="macOS"
runnable=true
export_filter="all_resources"
include_filter="config/*, assets/*.txt"
exclude_filter="tools/*, proxy/*, docs/*, build/*, assets/voices/qwen3/*"
export_path=""

[preset.2.options]
binary_format/architecture="universal"
application/bundle_identifier="app.donjon.game"
application/short_version="1.0"
application/version="1.0"
codesign/codesign=0
notarization/notarization=0

[preset.3]
name="Linux"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter="config/*, assets/*.txt"
exclude_filter="tools/*, proxy/*, docs/*, build/*, assets/voices/qwen3/*"
export_path=""

[preset.3.options]
binary_format/embed_pck=true
binary_format/architecture="x86_64"
PRESETS

version=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

# platform -> export preset name, and the file it writes inside build/<platform>/ (bash 3.2 has no maps)
preset_of() { case $1 in web) echo Web ;; windows) echo Windows ;; macos) echo macOS ;; linux) echo Linux ;; esac; }
file_of() { case $1 in web) echo index.html ;; windows) echo Donjon.exe ;; macos) echo Donjon.zip ;; linux) echo Donjon.x86_64 ;; esac; }
for p in "${platforms[@]}"; do
  preset=$(preset_of "$p")
  file=$(file_of "$p")
  out="build/$p"
  zip="build/donjon-$version-$p.zip"
  rm -rf "$out" "$zip"
  mkdir -p "$out"
  echo "== $p (preset $preset) -> $out/$file"
  "$GODOT" --headless --path . --export-release "$preset" "$out/$file"
  [[ -s "$out/$file" ]] || { echo "export for $p produced no $out/$file" >&2; exit 1; }
  if [[ $p == macos ]]; then
    cp "$out/Donjon.zip" "$zip" # Godot already zips the .app
  else
    (cd "$out" && zip -r -X -q "../$(basename "$zip")" .) # itch.io wants index.html at the top level
  fi
  echo "   $zip ($(du -h "$zip" | cut -f1))"
done
echo "Monsters in these builds: ${base:+Jev through $base}${base:-local rules}"
