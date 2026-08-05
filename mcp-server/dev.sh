#!/usr/bin/env bash
# dev.sh - Run the wp-ops MCP server in development mode (tsx, no build step)
#
# Usage: ./dev.sh
#
# @desc     Install dependencies and start the MCP server in development mode
# @category mcp-server
# @platform any
# @runs     local
# @requires npm

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d node_modules ]]; then
    npm install
fi

npm run dev
