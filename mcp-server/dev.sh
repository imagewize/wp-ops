#!/usr/bin/env bash
# dev.sh - Run the wp-ops MCP server in development mode (tsx, no build step)
#
# Usage: ./dev.sh

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d node_modules ]]; then
    npm install
fi

npm run dev
