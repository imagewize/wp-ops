#!/usr/bin/env bash
# install.sh - Add wp-ops to your PATH
#
# Usage: ./install.sh
#
# Appends this repo to PATH via your shell's rc file (~/.zshrc for zsh,
# ~/.bashrc for bash), so the `wp-ops` command works from any directory.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(basename "${SHELL:-}")" in
    zsh)
        RC_FILE="${HOME}/.zshrc"
        ;;
    bash)
        RC_FILE="${HOME}/.bashrc"
        ;;
    *)
        echo "Error: Unrecognized shell '${SHELL:-unknown}'."
        echo "Add this line to your shell's rc file manually:"
        echo "  export PATH=\"${REPO_ROOT}:\$PATH\""
        exit 1
        ;;
esac

if [[ -f "$RC_FILE" ]] && grep -Fq "$REPO_ROOT" "$RC_FILE"; then
    echo "wp-ops is already on PATH via $RC_FILE"
    exit 0
fi

{
    echo ""
    echo "# Added by wp-ops install.sh"
    echo "export PATH=\"${REPO_ROOT}:\$PATH\""
} >> "$RC_FILE"

echo "Added wp-ops to PATH in $RC_FILE"
echo "Run 'source $RC_FILE' (or open a new terminal), then 'wp-ops --help' to get started."
