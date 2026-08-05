#!/usr/bin/env bash
#
# Sync theme files from a Trellis project to a standalone theme repository.
#
# Useful for a theme development workflow where the theme is edited inside a
# working site but released from its own repo.
#
# How it works:
# - rsync -av: Archive mode (preserves permissions, timestamps) with verbose output
# - --delete: Removes files in destination that don't exist in source
# - --exclude: Skips syncing specific directories (dependencies, git files)
#
# --delete makes this destructive: anything at the destination that is not in
# the source is removed. Run --dry-run first when you are not certain the
# destination is clean — it prints exactly what would change and writes nothing.
#
# Usage:
#   rsync-theme.sh [-n|--dry-run] [-h|--help]
#
# Customize the paths below for your setup:
# - SOURCE: Your theme location within the Trellis project
# - DEST:   Your standalone theme repository
#
# Both can be overridden per invocation without editing the script:
#   SOURCE=~/code/example.com/site/web/app/themes/my-theme DEST=~/code/my-theme rsync-theme.sh -n
#
# Example theme name used: 'elayne' - replace with your actual theme name

# The usage() function below prints lines 2-27 of this file verbatim, so this
# manifest block is placed after that range to avoid altering its output.
# @desc     Rsync theme files from a Trellis site back to its standalone theme repository
# @category sync
# @platform any
# @runs     local
# @requires rsync
# @flag     --dry-run  optional  {}  Preview the sync without writing anything
# @example  wp-ops rsync-theme --dry-run
set -euo pipefail

# Trailing slashes matter to rsync: "src/" copies the *contents* of src.
SOURCE="${SOURCE:-$HOME/code/example.com/demo/web/app/themes/elayne/}"
DEST="${DEST:-$HOME/code/elayne/}"

usage() {
	sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
	exit "${1:-1}"
}

dry_run=false
while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) dry_run=true ;;
		-h|--help) usage 0 ;;
		*) echo "✗ unknown option '$1'" >&2; echo >&2; usage 1 ;;
	esac
	shift
done

# Built as an array so --dry-run can be added conditionally. Anything not passed
# here is silently ignored, which is why unknown options are rejected above.
args=(-av --delete)
[ "$dry_run" = true ] && args+=(--dry-run)
args+=(
	--exclude create-pr.sh
	--exclude .distignore
	--exclude 'node_modules/'
	--exclude 'vendor/'
	--exclude '.git/'
	--exclude '.github/'
)

rsync "${args[@]}" "$SOURCE" "$DEST"

if [ "$dry_run" = true ]; then
	echo
	echo "Dry run — nothing was written. Re-run without --dry-run to apply."
fi
