#!/usr/bin/env bash
# Exports the game into build/<platform>/ and zips each one as build/donjon-<version>-<platform>.zip.
#   tools/build.sh                         # every platform (web windows macos linux), no key: monsters run on mock Jev
#   tools/build.sh web macos               # only some
#   OPENROUTER_API_KEY=sk-or-... tools/build.sh --openrouter [platforms...]
#                                          # Jev via OpenRouter, called by the game itself WITH THIS KEY INSIDE THE BUILD:
#                                          # anyone can read it, so use a key with a small credit limit
#                                          # (openrouter.ai/settings/keys). This is how the itch.io and release builds ship.
#   tools/build.sh --proxy https://halls-of-jev-api.<you>.workers.dev [platforms...]
#                                          # Jev via your Worker (proxy/), which holds the key: nothing secret ships
# GODOT points at the Godot 4.7 binary (default: godot on PATH), with export templates installed for it.
# The key is written into config/jev_config.json only for the export and removed afterwards; it is never committed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
config=config/jev_config.json
cleanup() { rm -f "$config"; }
trap cleanup EXIT

provider=""
platforms=()
base=""
while (($#)); do
  case "$1" in
    --openrouter) provider=openrouter ;;
    --proxy) provider=proxy; base=${2:-}; shift ;;
    web|windows|macos|linux) platforms+=("$1") ;;
    *) echo "usage: tools/build.sh [--openrouter | --proxy <url>] [web windows macos linux]" >&2; exit 1 ;;
  esac
  shift
done
((${#platforms[@]})) || platforms=(web windows macos linux)

mkdir -p config build
case "$provider" in
  openrouter)
    key=$(printf %s "${OPENROUTER_API_KEY:-}" | tr -d '[:space:]')
    [[ $key == sk-or-* ]] || { echo "--openrouter needs OPENROUTER_API_KEY (an OpenRouter key, sk-or-...) in the environment." >&2; exit 1; }
    printf '{"provider":"openrouter","key":"%s","debug":true}\n' "$key" > "$config"
    ;;
  proxy)
    [[ $base =~ ^https://|^http://localhost(:[0-9]+)?$ ]] || { echo "--proxy needs the Worker URL, e.g. https://halls-of-jev-api.you.workers.dev" >&2; exit 1; }
    printf '{"provider":"proxy","apiBase":"%s","debug":true}\n' "${base%/}" > "$config"
    ;;
  "") rm -f "$config" ;; # no config: the build finds no key and runs on mock Jev
esac

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
echo "Jev in these builds: ${provider:-mock (no key)}"
