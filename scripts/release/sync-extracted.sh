#!/usr/bin/env bash
#
# sync-extracted.sh — keep the extracted downstream repos in step with wp-ops
#
# Two scripts and one PHP command have been published outside this repository:
# the monitoring scripts as the Ansible Galaxy role imagewize.trellis_wp_monitoring,
# and the pattern validator as the WP-CLI package imagewize/wp-cli-pattern-validate.
# Both were copied by hand. Nothing has propagated an edit since, and nothing
# has checked: commit 5569454 added "@mutates false" to both monitoring scripts
# here on 2026-08-27 and the published role never saw it. That difference was
# harmless — a wp-ops manifest directive has no business in a Galaxy role — but
# the next one will not announce itself.
#
# The split that already holds in practice, verified against all three files:
#
#   header  — the leading comment block. Differs on purpose. wp-ops carries the
#             manifest directives (@desc, @category, @flag, ...); the published
#             copies carry their own install instructions instead.
#   body    — everything after it. Byte-identical, and must stay that way.
#
# So wp-ops owns the logic, each downstream owns its own framing, and this
# script enforces exactly that line: it rebuilds each downstream file as its
# own header plus this repo's body.
#
# Usage:
#   ./sync-extracted.sh                 # report drift, change nothing
#   ./sync-extracted.sh --write         # rewrite downstream bodies from here
#   ./sync-extracted.sh --root ~/src    # look for the clones somewhere else
#
# --write only stages the files in the downstream working trees. Review, commit,
# and tag there yourself — a Galaxy role and a WP-CLI package are both versioned
# artifacts, and this script has no opinion about their release cadence.
#
# @desc     Check or update the extracted Galaxy role and WP-CLI package against their wp-ops sources
# @category release
# @platform any
# @runs     local
# @requires git
# @flag     --write   optional  {}  Rewrite downstream files instead of only reporting
# @flag     --root    optional  {~/code}  Directory holding the downstream clones
# @example  wp-ops sync-extracted
# @example  wp-ops sync-extracted --write
# @doc      docs/trellis-extensions-evaluation.md

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# source in this repo | downstream clone | path within that clone
MAPPINGS=(
    "scripts/monitoring/security-monitor.sh|trellis-wp-monitoring|files/security-monitor.sh"
    "scripts/monitoring/traffic-monitor.sh|trellis-wp-monitoring|files/traffic-monitor.sh"
    "wp-cli/content-creation/wp-cli-pattern-validate.php|wp-cli-pattern-validate|command.php"
)

DOWNSTREAM_ROOT="${WP_OPS_EXTRACTED_ROOT:-$HOME/code}"
WRITE=false

while [ $# -gt 0 ]; do
    case "$1" in
    --write)
        WRITE=true
        ;;
    --root)
        shift
        [ $# -gt 0 ] || { echo "--root needs a directory" >&2; exit 1; }
        DOWNSTREAM_ROOT="$1"
        ;;
    --root=*)
        DOWNSTREAM_ROOT="${1#--root=}"
        ;;
    -h | --help)
        sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
    shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# First body line: the first line past the leading comment block. PHP files open
# with a docblock, so the body starts after its closing */; shell files open with
# a shebang and # comments. Both forms are checked by the pairs above.
body_start() {
    local file="$1"
    case "$file" in
    *.php)
        awk 'found { print NR; exit } /^[[:space:]]*\*\//{ found = 1 }' "$file"
        ;;
    *)
        awk 'NR == 1 && /^#!/ { next }
             /^[[:space:]]*#/ { next }
             /^[[:space:]]*$/ { next }
             { print NR; exit }' "$file"
        ;;
    esac
}

drifted=0
synced=0
skipped=0
warned_clones=""
updated_clones=""

for mapping in "${MAPPINGS[@]}"; do
    IFS='|' read -r src_rel clone dst_rel <<<"$mapping"

    src="$REPO_ROOT/$src_rel"
    dst="$DOWNSTREAM_ROOT/$clone/$dst_rel"

    if [ ! -f "$src" ]; then
        echo -e "${RED}missing source${NC}  $src_rel"
        echo "  The mapping in this script is stale — the file moved or was renamed."
        drifted=$((drifted + 1))
        continue
    fi

    if [ ! -d "$DOWNSTREAM_ROOT/$clone" ]; then
        # Several mappings can share one clone; warn about it once.
        case " $warned_clones " in
        *" $clone "*) ;;
        *)
            echo -e "${YELLOW}no clone${NC}      $clone"
            echo "  Expected at $DOWNSTREAM_ROOT/$clone — clone it or pass --root."
            warned_clones="$warned_clones $clone"
            skipped=$((skipped + 1))
            ;;
        esac
        continue
    fi

    if [ ! -f "$dst" ]; then
        echo -e "${RED}missing target${NC}  $clone/$dst_rel"
        drifted=$((drifted + 1))
        continue
    fi

    src_body_line="$(body_start "$src")"
    dst_body_line="$(body_start "$dst")"

    if [ -z "$src_body_line" ] || [ -z "$dst_body_line" ]; then
        echo -e "${RED}unparsable${NC}     $clone/$dst_rel"
        echo "  Could not find where the header ends in one of the two files."
        drifted=$((drifted + 1))
        continue
    fi

    if diff -q <(tail -n +"$src_body_line" "$src") <(tail -n +"$dst_body_line" "$dst") >/dev/null; then
        echo -e "${GREEN}in sync${NC}       $clone/$dst_rel"
        continue
    fi

    if [ "$WRITE" = true ]; then
        # The downstream header is preserved verbatim; only the body is replaced.
        # mktemp creates 0600, so the target's own mode is restored afterwards
        # rather than assumed — chmod +x would leave a role file at 0711.
        dst_mode="$(stat -f '%Lp' "$dst" 2>/dev/null || stat -c '%a' "$dst")"
        tmp="$(mktemp)"
        head -n "$((dst_body_line - 1))" "$dst" >"$tmp"
        tail -n +"$src_body_line" "$src" >>"$tmp"
        mv "$tmp" "$dst"
        chmod "$dst_mode" "$dst"
        echo -e "${BLUE}updated${NC}       $clone/$dst_rel"
        synced=$((synced + 1))
        case " $updated_clones " in
        *" $clone "*) ;;
        *) updated_clones="$updated_clones $clone" ;;
        esac
    else
        echo -e "${YELLOW}drifted${NC}       $clone/$dst_rel"
        diff <(tail -n +"$src_body_line" "$src") <(tail -n +"$dst_body_line" "$dst") |
            sed 's/^/    /' | head -20
        drifted=$((drifted + 1))
    fi
done

echo
if [ "$WRITE" = true ]; then
    if [ "$synced" -gt 0 ]; then
        echo -e "${GREEN}Updated $synced file(s).${NC} Review and commit them in their own repos:"
        for clone in $updated_clones; do
            echo "  git -C $DOWNSTREAM_ROOT/$clone diff"
        done
    else
        echo -e "${GREEN}Nothing to update.${NC}"
    fi
fi

if [ "$skipped" -gt 0 ]; then
    echo -e "${YELLOW}$skipped repo(s) not checked.${NC}"
fi

if [ "$drifted" -gt 0 ] && [ "$WRITE" = false ]; then
    echo -e "${RED}$drifted file(s) out of sync.${NC} Re-run with --write to update them."
    exit 1
fi

exit 0
