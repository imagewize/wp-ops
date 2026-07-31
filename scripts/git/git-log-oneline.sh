#!/bin/bash

# git-log-oneline.sh - Show recent git commits as compact one-liners
# 
# Quick way to review the last N commits with short hash and message.
# Useful for quickly checking recent work or changes before creating a PR.
#
# Usage:
#   ./git-log-oneline.sh              # Show last 10 commits (default)
#   ./git-log-oneline.sh 20           # Show last 20 commits
#   ./git-log-oneline.sh 5            # Show last 5 commits
#
# Examples:
#   # Check what you've been working on
#   ./scripts/git/git-log-oneline.sh
#
#   # See a longer history
#   ./scripts/git/git-log-oneline.sh 50
#
#   # Use with head to limit output further
#   ./scripts/git/git-log-oneline.sh 100 | head -n 25
#
# Author: wp-ops
# Created: 2025-05-06

set -euo pipefail

# Default number of commits to show
NUM_COMMITS=${1:-10}

# Validate input is a positive integer
if ! [[ "$NUM_COMMITS" =~ ^[0-9]+$ ]] || [ "$NUM_COMMITS" -le 0 ] 2>/dev/null; then
    echo "Error: Please provide a positive integer for the number of commits." >&2
    echo "Usage: $0 [N]  where N is the number of commits to show (default: 10)" >&2
    exit 1
fi

# Show the last N commits as one-liners
git log --oneline -n "$NUM_COMMITS"
