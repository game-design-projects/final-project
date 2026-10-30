#!/usr/bin/env bash
# Starts the Godot MCP server (github.com/Coding-Solo/godot-mcp) for .mcp.json, installing it first when needed:
# npm ci runs on the first start and again whenever package-lock.json changes. stdout is the MCP channel,
# so everything else goes to stderr. Godot is found on PATH (or the usual install spots); GODOT_PATH overrides.
set -euo pipefail
cd "$(dirname "$0")"
stamp=node_modules/.package-lock.json
if [ ! -f "$stamp" ] || [ package-lock.json -nt "$stamp" ]; then
  npm ci --no-audit --no-fund --loglevel=error >&2
fi
exec node node_modules/@coding-solo/godot-mcp/build/index.js
