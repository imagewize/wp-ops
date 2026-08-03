#!/usr/bin/env bash
# start.sh - Build and start the wp-ops MCP server
#
# Usage: ./start.sh

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ ! -d node_modules ]]; then
    npm install
fi

# npm's "prestart" hook (package.json) runs the build automatically.
npm start
