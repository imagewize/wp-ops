#!/usr/bin/env bash
#
# Sync a plugin/theme working copy INTO a Bedrock site, so unreleased changes can
# be tested on a real site without cutting a release.
#
# This is the reverse direction of scripts/rsync-theme.sh, which pulls a theme
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
# Usage:
#   rsync-package-to-site.sh <plugin|theme> <package-slug> [source-dir]
#
# Examples:
#   rsync-package-to-site.sh plugin my-plugin              # cwd is the package repo
#   rsync-package-to-site.sh theme  my-theme ~/code/my-theme
#
# Configure the destination once, in your shell profile or per invocation:
#   SITE_ROOT=~/code/example.com/demo/web/app rsync-package-to-site.sh theme my-theme
#
# SITE_ROOT is the Bedrock content directory — the one holding plugins/ and
# themes/ (web/app in a stock Bedrock install, wp-content elsewhere).

set -euo pipefail

usage() {
	sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
	exit "${1:-1}"
}

[ $# -ge 2 ] || usage 1
case "$1" in -h|--help) usage 0 ;; esac

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
rsync -a --delete --delete-excluded "${excludes[@]}" "$src/" "$dest/"

# Report the version that landed, so it is obvious when a sync silently no-ops.
if [ "$kind" = "theme" ] && [ -f "$dest/style.css" ]; then
	version=$(grep -m1 -i '^[[:space:]]*\*\{0,1\}[[:space:]]*Version:' "$dest/style.css" | tr -d ' *')
else
	version=$(grep -rm1 -i '^[[:space:]]*\*[[:space:]]*Version:' "$dest"/*.php 2>/dev/null | sed 's/.*://' | tr -d ' ')
	version="${version:+Version:$version}"
fi

echo "✓ $slug → $dest ${version:+($version)}"
