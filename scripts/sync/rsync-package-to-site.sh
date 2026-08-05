#!/usr/bin/env bash
#
# Sync a plugin/theme working copy INTO a Bedrock site, so unreleased changes can
# be tested on a real site without cutting a release.
#
# This is the reverse direction of scripts/sync/rsync-theme.sh, which pulls a theme
# out of a Trellis site back into its standalone repo. Use this one when the
# package repo is the source of truth and the site is disposable.
#
# Why not a Composer `path` repository? That approach (see
# bedrock/local-package-development/README.md) is better when you want Composer
# itself to resolve the package and you are happy editing the site's
# composer.json. This script is better when the package is a *pinned* dependency
# you would rather not touch, and you want a dist-faithful copy on disk in one
# command. A `composer update <vendor/package>` on the site restores the released
# code either way.
#
# The rsync mirrors .distignore when the package has one, so what you test is
# what ships — a file excluded from the release zip never reaches the site.
#
# The sync runs with --delete --delete-excluded, so it can remove files at the
# destination. Pass --dry-run to see exactly what would change without writing.
#
# Usage:
#   rsync-package-to-site.sh [-n|--dry-run] <plugin|theme> <package-slug> [source-dir]
#
# Examples:
#   rsync-package-to-site.sh plugin my-plugin              # cwd is the package repo
#   rsync-package-to-site.sh theme  my-theme ~/code/my-theme
#   rsync-package-to-site.sh -n theme my-theme             # preview only
#
# Configure the destination once, in your shell profile or per invocation:
#   SITE_ROOT=~/code/example.com/demo/web/app rsync-package-to-site.sh theme my-theme
#
# SITE_ROOT is the Bedrock content directory — the one holding plugins/ and
# themes/ (web/app in a stock Bedrock install, wp-content elsewhere).

# The usage() function below prints lines 2-36 of this file verbatim, so this
# manifest block is placed after that range to avoid altering its output.
# @desc     Rsync a plugin/theme working copy into a Bedrock site for testing unreleased changes
# @category sync
# @platform any
# @runs     local
# @requires rsync
# @arg      kind          required  {plugin|theme}  Package type
# @arg      package-slug  required  {my-plugin}  Plugin/theme directory slug at the destination
# @arg      source-dir    optional  {.}  Package working tree (default: current directory)
# @flag     --dry-run     optional  {}  Preview the sync without writing anything
# @example  wp-ops scripts/sync/rsync-package-to-site theme my-theme
# @doc      docs/bedrock/local-package-development/README.md
set -euo pipefail

usage() {
	sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
	exit "${1:-1}"
}

# Flags first, so the positional arguments below keep their existing meaning.
dry_run=false
while [ $# -gt 0 ]; do
	case "$1" in
		-n|--dry-run) dry_run=true; shift ;;
		-h|--help) usage 0 ;;
		--) shift; break ;;
		-*) echo "✗ unknown option '$1'" >&2; echo >&2; usage 1 ;;
		*) break ;;
	esac
done

[ $# -ge 2 ] || usage 1

kind="$1"
slug="$2"
src="${3:-$PWD}"

case "$kind" in
	plugin) dir="plugins" ;;
	theme)  dir="themes" ;;
	*) echo "✗ first argument must be 'plugin' or 'theme', got '$kind'" >&2; exit 1 ;;
esac

# Default to the conventional local Trellis/Bedrock layout. Override for your own.
SITE_ROOT="${SITE_ROOT:-$HOME/code/example.com/demo/web/app}"

src="$(cd "$src" && pwd)"
dest="$SITE_ROOT/$dir/$slug"

[ -d "$src" ] || { echo "✗ source $src not found" >&2; exit 1; }
[ -d "$dest" ] || {
	echo "✗ $dest not found — is the package installed on that site?" >&2
	echo "  Set SITE_ROOT to the Bedrock content directory (the one holding plugins/ and themes/)." >&2
	exit 1
}

# Never push development-only files onto a site. A package's own .distignore is
# the authoritative list when it has one; the fallback covers the usual suspects
# so this still does the right thing for a package without one.
excludes=(
	--exclude '.git/'
	--exclude '.github/'
	--exclude '.claude/'
	--exclude '.vscode/'
	--exclude '.idea/'
	--exclude 'node_modules/'
	--exclude 'vendor/'
	--exclude 'docs/'
	--exclude 'tests/'
	--exclude 'bin/'
	--exclude '*.sh'
	--exclude '.gitignore'
	--exclude '.gitattributes'
	--exclude '.distignore'
	--exclude '.editorconfig'
	--exclude '.DS_Store'
)
if [ -f "$src/.distignore" ]; then
	excludes+=( --exclude-from "$src/.distignore" )
fi

# --delete-excluded matters: without it, a file that used to ship and is now
# excluded lingers at the destination and you test something that no longer
# exists in the release.
rsync_args=(-a --delete --delete-excluded)
if [ "$dry_run" = true ]; then
	# -v as well: a silent dry run would print nothing at all.
	rsync_args+=(--dry-run -v)
fi

rsync "${rsync_args[@]}" "${excludes[@]}" "$src/" "$dest/"

if [ "$dry_run" = true ]; then
	echo
	echo "Dry run — nothing was written. Re-run without --dry-run to apply."
	exit 0
fi

# Report the version that landed, so it is obvious when a sync silently no-ops.
if [ "$kind" = "theme" ] && [ -f "$dest/style.css" ]; then
	version=$(grep -m1 -i '^[[:space:]]*\*\{0,1\}[[:space:]]*Version:' "$dest/style.css" | tr -d ' *')
else
	version=$(grep -rm1 -i '^[[:space:]]*\*[[:space:]]*Version:' "$dest"/*.php 2>/dev/null | sed 's/.*://' | tr -d ' ')
	version="${version:+Version:$version}"
fi

echo "✓ $slug → $dest ${version:+($version)}"
