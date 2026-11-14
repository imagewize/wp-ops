#!/usr/bin/env bash
# Turn a VHS terminal recording (.mp4) into a README GIF, speeding up the
# stretches where nothing happens on screen instead of cutting them.
#
# Usage:
#   mp4-to-gif.sh --detect input.mp4
#       List frozen stretches (2s+) to pick segment times from.
#   mp4-to-gif.sh input.mp4 output.gif "start:end:speed ..."
#       Build the GIF. Each segment is start:end:speed in seconds; leave end
#       empty on the last one to run to the end of the video.
#
# Example (the database-pull recording):
#   mp4-to-gif.sh database-pull.mp4 database-pull.gif \
#     "0:6.9:1 6.9:17.3:4 17.3:27:1 27:99.5:20 99.5::1"

set -euo pipefail

# Configuration
WIDTH=800        # GIF width in px; height follows the aspect ratio
FPS=10           # frame rate of the GIF
COLORS=64        # palette size; terminal text needs few colors
FREEZE_MIN=2     # --detect: minimum frozen duration in seconds

if [[ "${1:-}" == "--detect" ]]; then
    [[ -f "${2:-}" ]] || { echo "Usage: $0 --detect input.mp4" >&2; exit 1; }
    ffmpeg -hide_banner -nostats -i "$2" \
        -vf "freezedetect=n=-60dB:d=${FREEZE_MIN}" -map 0:v -f null - 2>&1 \
        | grep -oE "freeze_(start|end): [0-9.]+"
    exit 0
fi

if [[ $# -ne 3 || ! -f "$1" ]]; then
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

input=$1
output=$2
read -ra segments <<< "$3"

filter=""
labels=""
i=0
for segment in "${segments[@]}"; do
    IFS=: read -r start end speed <<< "$segment"
    range="${start}${end:+:$end}"
    filter+="[0:v]trim=${range},setpts=(PTS-STARTPTS)/${speed:-1}[s$i];"
    labels+="[s$i]"
    i=$((i + 1))
done

filter+="${labels}concat=n=${i}:v=1,fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,split[g0][g1];"
filter+="[g0]palettegen=max_colors=${COLORS}:stats_mode=diff[p];"
filter+="[g1][p]paletteuse=dither=none:diff_mode=rectangle"

ffmpeg -hide_banner -loglevel error -y -i "$input" -filter_complex "$filter" "$output"

duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$output")
size=$(wc -c < "$output" | awk '{printf "%.1f MB", $1 / 1048576}')
echo "✓ $output (${duration%.*}s, $size)"
