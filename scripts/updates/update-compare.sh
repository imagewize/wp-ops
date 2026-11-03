#!/bin/bash

# Update Compare
# Diff two update-snapshot runs and build a before/after compare page.
#
# For every PNG in <before-dir>, finds the same file in <after-dir>, computes
# how many pixels changed (ImageMagick, with a fuzz tolerance so antialiasing
# doesn't count), writes a diff image, and builds a self-contained compare
# folder: index.html plus copies of every image, so it can be zipped and sent
# to a client as-is. Shots of different heights are padded to the same size
# before diffing, so a page that grew still gets a diff instead of a skip.
#
# Exit code: 0 when every shot is under --threshold, 1 when any shot is over
# it or missing from <after-dir>.
#
# Usage:
#   ./update-compare.sh <before-dir> <after-dir> [options]
#   wp-ops update-compare snapshots/before snapshots/after --out=snapshots/compare
#
# Options:
#   --out=DIR        Compare folder to write (default: <after-dir>-compare)
#   --fuzz=N         Per-pixel color tolerance in percent (default: 15)
#   --threshold=N    Percent of changed pixels that flags a shot (default: 0.5)
#   --title=TEXT     Heading for the compare page (default: Update compare)
#
# @desc     Diff two update-snapshot runs and build a before/after compare page
# @category monitoring
# @platform any
# @runs     local
# @requires magick
# @arg      before-dir   required  {snapshots/before}  Directory from the first update-snapshot run
# @arg      after-dir    required  {snapshots/after}  Directory from the second update-snapshot run
# @flag     --out        optional  {snapshots/compare}  Compare folder to write (default: <after-dir>-compare)
# @flag     --fuzz       optional  {15}  Per-pixel color tolerance in percent
# @flag     --threshold  optional  {0.5}  Percent of changed pixels that flags a shot
# @flag     --title      optional  {"example.com update, Nov 3"}  Heading for the compare page
# @example  wp-ops update-compare snapshots/before snapshots/after --out=snapshots/compare

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <before-dir> <after-dir> [--out=DIR] [--fuzz=15] [--threshold=0.5] [--title=TEXT]"
  exit 1
}

BEFORE=""; AFTER=""; OUT=""; FUZZ=15; THRESHOLD=0.5; TITLE="Update compare"
for arg in "$@"; do
  case "$arg" in
    --out=*) OUT="${arg#*=}" ;;
    --fuzz=*) FUZZ="${arg#*=}" ;;
    --threshold=*) THRESHOLD="${arg#*=}" ;;
    --title=*) TITLE="${arg#*=}" ;;
    -h|--help) usage ;;
    --*) echo "Unknown option: $arg"; usage ;;
    *) if [[ -z "$BEFORE" ]]; then BEFORE="$arg"; elif [[ -z "$AFTER" ]]; then AFTER="$arg"; else usage; fi ;;
  esac
done
[[ -n "$BEFORE" && -n "$AFTER" ]] || usage
[[ -d "$BEFORE" ]] || { echo "Error: $BEFORE is not a directory"; exit 1; }
[[ -d "$AFTER" ]] || { echo "Error: $AFTER is not a directory"; exit 1; }
command -v magick >/dev/null || { echo "Error: ImageMagick 7 (magick) is required"; exit 1; }
OUT="${OUT:-${AFTER%/}-compare}"

mkdir -p "$OUT/before" "$OUT/after" "$OUT/diff"

html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

rows_flag=""
rows_ok=""
flagged=0
total=0
shopt -s nullglob
for before_file in "$BEFORE"/*.png; do
  name="$(basename "$before_file")"
  after_file="$AFTER/$name"
  total=$((total + 1))
  cp "$before_file" "$OUT/before/$name"

  if [[ ! -f "$after_file" ]]; then
    flagged=$((flagged + 1))
    printf "%-34s %s\n" "${name%.png}" "MISSING in after"
    rows_flag+="<tr class=\"flag\"><td>$(html_escape "${name%.png}")</td><td colspan=\"3\">Missing in after run</td></tr>"
    continue
  fi
  cp "$after_file" "$OUT/after/$name"

  size_b="$(magick identify -format '%wx%h' "$before_file")"
  size_a="$(magick identify -format '%wx%h' "$after_file")"
  w=$(( ${size_b%x*} > ${size_a%x*} ? ${size_b%x*} : ${size_a%x*} ))
  h=$(( ${size_b#*x} > ${size_a#*x} ? ${size_b#*x} : ${size_a#*x} ))

  # Pad both to the same canvas so a height change still produces a diff.
  # With -compare as an operator, ImageMagick 7 reports AE as a fraction of
  # all pixels (0.018 = 1.8%), not as a pixel count.
  fraction="$(magick \( "$before_file" -background white -extent "${w}x${h}" \) \
                     \( "$after_file" -background white -extent "${w}x${h}" \) \
                     -fuzz "${FUZZ}%" -metric AE -compare -format '%[distortion]' info: 2>/dev/null || true)"
  magick \( "$before_file" -background white -extent "${w}x${h}" \) \
         \( "$after_file" -background white -extent "${w}x${h}" \) \
         -fuzz "${FUZZ}%" -highlight-color red -lowlight-color '#ffffffb0' \
         -compare "$OUT/diff/$name" 2>/dev/null || true
  [[ "$fraction" =~ ^[0-9.eE+-]+$ ]] || { echo "Error: could not diff $name (magick output: $fraction)"; exit 1; }
  pct="$(awk -v f="$fraction" 'BEGIN { printf "%.3f", f * 100 }')"
  over="$(awk -v a="$pct" -v t="$THRESHOLD" 'BEGIN { print (a > t) ? 1 : 0 }')"

  note=""
  [[ "$size_b" != "$size_a" ]] && note=" (size $size_b → $size_a)"
  if [[ "$over" == 1 ]]; then
    flagged=$((flagged + 1)); mark="✗"; cls="flag"
  else
    mark="✓"; cls="ok"
  fi
  printf "%s %-32s %7s%%%s\n" "$mark" "${name%.png}" "$pct" "$note"
  n="$(html_escape "$name")"
  row="<tr class=\"$cls\"><td>$(html_escape "${name%.png}")<br><small>$pct% changed$(html_escape "$note")</small></td>"
  row+="<td><a href=\"before/$n\"><img loading=\"lazy\" src=\"before/$n\" alt=\"before\"></a></td>"
  row+="<td><a href=\"after/$n\"><img loading=\"lazy\" src=\"after/$n\" alt=\"after\"></a></td>"
  row+="<td><a href=\"diff/$n\"><img loading=\"lazy\" src=\"diff/$n\" alt=\"diff\"></a></td></tr>"
  if [[ "$cls" == flag ]]; then rows_flag+="$row"; else rows_ok+="$row"; fi
done

if [[ "$total" == 0 ]]; then
  echo "Error: no PNG files in $BEFORE"; exit 1
fi

cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$(html_escape "$TITLE")</title>
<style>
body{font:15px/1.5 system-ui,sans-serif;margin:24px;color:#1f2933;background:#fff}
h1{font-size:22px;margin:0 0 4px}p.meta{color:#52606d;margin:0 0 20px}
table{border-collapse:collapse;width:100%}th,td{border-top:1px solid #e4e7eb;padding:10px;vertical-align:top;text-align:left}
td:first-child{width:180px;font-weight:600}td small{font-weight:400;color:#52606d}
tr.flag td:first-child{color:#c81e1e}tr.flag{background:#fff5f5}
img{width:100%;max-height:600px;object-fit:cover;object-position:top;border:1px solid #e4e7eb}
</style></head><body>
<h1>$(html_escape "$TITLE")</h1>
<p class="meta">$total shots, $flagged over ${THRESHOLD}% changed (fuzz ${FUZZ}%). Before: $(html_escape "$BEFORE") · After: $(html_escape "$AFTER") · $(date '+%Y-%m-%d %H:%M')</p>
<table><thead><tr><th>Page</th><th>Before</th><th>After</th><th>Changed pixels</th></tr></thead><tbody>
$rows_flag$rows_ok
</tbody></table></body></html>
HTML

echo ""
echo "$flagged of $total shots over ${THRESHOLD}% → $OUT/index.html"
[[ "$flagged" == 0 ]]
