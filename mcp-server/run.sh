#!/usr/bin/env bash
# run.sh - Rebuild if stale, then exec the MCP server for stdio transport.
#
# This is the launcher to register in mcpServers (~/.claude.json / .mcp.json),
# not a bare `node dist/index.js` and not `npm start`. Two reasons:
#
#   - `node dist/index.js` alone never rebuilds, so edits to src/*.ts are
#     silently ignored by an already-registered client until someone remembers
#     to run `npm run build` by hand.
#   - `npm start` (even with the prestart hook) risks mixing npm's own log
#     lines into stdout ahead of the server's JSON-RPC output, which corrupts
#     stdio framing. Build output here goes to stderr, and `exec` replaces
#     this shell with the node process so stdout carries only the MCP stream.
#
# Usage: point mcpServers.wp-ops.command at this script's absolute path
# (no args needed).

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d node_modules ]]; then
    npm install >&2
fi

if [[ ! -f dist/index.js ]] || [[ -n "$(find src -newer dist/index.js -print -quit 2>/dev/null)" ]]; then
    npm run build --silent >&2
fi

exec node dist/index.js
