#!/usr/bin/env bash
# start.sh - Build and start the wp-ops MCP server
#
# Usage: ./start.sh
#
# @desc     Build and start the MCP server
# @category mcp-server
# @platform any
# @runs     local
# @requires npm node

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d node_modules ]]; then
    npm install
fi

# npm's "prestart" hook (package.json) runs the build automatically.
npm start
