#!/usr/bin/env bash
# Builds the web export (the itch.io HTML5 upload) into build/web and zips it as build/donjon-web.zip.
#   tools/build-web.sh                                   # no key: monsters run on mock Jev (CI's validation build)
#   OPENROUTER_API_KEY=sk-or-... tools/build-web.sh --openrouter
#                                                        # the itch build: the browser calls Jev on OpenRouter itself,
#                                                        # WITH THIS KEY IN THE PAGE, so use a key with a small credit
#                                                        # limit (openrouter.ai/settings/keys)
#   tools/build-web.sh --proxy https://halls-of-jev-api.<you>.workers.dev
#                                                        # the browser calls your Worker (proxy/), which holds the key
# GODOT points at the Godot 4.7 binary (default: godot on PATH). Export templates must be installed for it.
# The key is only written into config/jev_config.json for the export and removed afterwards; it is never committed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
mode=${1:-}
config=config/jev_config.json
cleanup() { rm -f "$config"; }
trap cleanup EXIT
mkdir -p config build
case "$mode" in
  --openrouter)
    key=$(printf %s "${OPENROUTER_API_KEY:-}" | tr -d '[:space:]')
    [[ $key == sk-or-* ]] || { echo "--openrouter needs OPENROUTER_API_KEY (an OpenRouter key, sk-or-...) in the environment." >&2; exit 1; }
    printf '{"provider":"openrouter","key":"%s","debug":true}\n' "$key" > "$config"
    ;;
  --proxy)
    base=${2:-}
    [[ $base =~ ^https://|^http://localhost(:[0-9]+)?$ ]] || { echo "--proxy needs the Worker URL, e.g. https://halls-of-jev-api.you.workers.dev" >&2; exit 1; }
    printf '{"provider":"proxy","apiBase":"%s","debug":true}\n' "${base%/}" > "$config"
    ;;
  "")
    rm -f "$config" # no config: the build finds no key and runs on mock Jev
    ;;
  *)
    echo "usage: tools/build-web.sh [--openrouter | --proxy <url>]" >&2; exit 1
    ;;
esac
rm -rf build/web build/donjon-web.zip
mkdir -p build/web
"$GODOT" --headless --path . --import >/dev/null
"$GODOT" --headless --path . --export-release Web build/web/index.html
# itch.io wants index.html at the top level of the zip
(cd build/web && zip -r -X -q ../donjon-web.zip .)
echo "Built build/donjon-web.zip ($(du -h build/donjon-web.zip | cut -f1)) -> Jev: ${mode:-mock}"
