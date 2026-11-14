#!/bin/bash
set -euo pipefail

WALLPAPER_DIR="$HOME/.wallpapers"
TEMP_DIR="$HOME/.local/share/split-wallpapers"

usage() {
    cat <<EOF
Usage: ${0##*/} [IMAGE]

Splits a wallpaper across all monitors and applies it via Plasma.

  IMAGE   Optional path to an image file. If omitted, a random image is
          picked from $WALLPAPER_DIR
EOF
}

case "${1-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

if [ "$#" -gt 1 ]; then
    echo "Error: too many arguments" >&2
    usage >&2
    exit 1
fi

if [ "$#" -eq 1 ]; then
    # Use the image the caller gave us
    WALLPAPER="$1"

    if [ ! -f "$WALLPAPER" ]; then
        echo "Error: '$WALLPAPER' is not a file" >&2
        exit 1
    fi

    if ! magick identify "$WALLPAPER" > /dev/null 2>&1; then
        echo "Error: '$WALLPAPER' is not a readable image" >&2
        exit 1
    fi

    # Resolve to an absolute path so the file:// URL stays valid
    WALLPAPER=$(readlink -f "$WALLPAPER")
else
    # Randomly select a wallpaper
    WALLPAPER=$(find "$WALLPAPER_DIR/" -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" \) | shuf -n 1)

    if [ -z "$WALLPAPER" ]; then
        echo "No wallpapers found in $WALLPAPER_DIR" >&2
        exit 1
    fi
fi

mkdir -p "$TEMP_DIR"
rm -f "$TEMP_DIR"/*.png

# Generate a random id for this wallpaper change
SESSION_ID=$(date +%s%N | sha256sum | head -c 8)

# Get monitor information (strip ANSI colour codes)
MONITOR_INFO=$(kscreen-doctor -o | sed 's/\x1b\[[0-9;]*m//g')

# Parse geometries: "X,Y WIDTHxHEIGHT"
readarray -t GEOMETRIES < <(echo "$MONITOR_INFO" | grep "Geometry:" | awk '{print $2, $3}')

NUM_MONITORS=${#GEOMETRIES[@]}
if [ "$NUM_MONITORS" -eq 0 ]; then
    echo "Could not parse any monitor geometries from kscreen-doctor" >&2
    exit 1
fi

declare -a WIDTHS HEIGHTS POSITIONS
TOTAL_WIDTH=0

for ((i = 0; i < NUM_MONITORS; i++)); do
    GEOM="${GEOMETRIES[$i]}"
    POS_PART=$(echo "$GEOM" | awk '{print $1}')
    SIZE_PART=$(echo "$GEOM" | awk '{print $2}')

    X_POS=$(echo "$POS_PART" | cut -d',' -f1)
    WIDTH=$(echo "$SIZE_PART" | cut -d'x' -f1)
    HEIGHT=$(echo "$SIZE_PART" | cut -d'x' -f2)

    WIDTHS[$i]=$WIDTH
    HEIGHTS[$i]=$HEIGHT
    POSITIONS[$i]=$X_POS
    TOTAL_WIDTH=$((TOTAL_WIDTH + WIDTH))
done

# Layout origin (leftmost X — may be negative) and tallest monitor
MIN_X=${POSITIONS[0]}
for x in "${POSITIONS[@]}"; do
    [ "$x" -lt "$MIN_X" ] && MIN_X=$x
done

MAX_HEIGHT=${HEIGHTS[0]}
for h in "${HEIGHTS[@]}"; do
    [ "$h" -gt "$MAX_HEIGHT" ] && MAX_HEIGHT=$h
done

# Resize and centre the original across the full virtual canvas
magick "$WALLPAPER" \
    -resize "${TOTAL_WIDTH}x${MAX_HEIGHT}^" \
    -gravity center \
    -extent "${TOTAL_WIDTH}x${MAX_HEIGHT}" \
    "$TEMP_DIR/${SESSION_ID}_full.png"

# Split the canvas, naming each crop after the monitor's absolute X position
for ((i = 0; i < NUM_MONITORS; i++)); do
    W=${WIDTHS[$i]}
    H=${HEIGHTS[$i]}
    X_POS=${POSITIONS[$i]}
    OFFSET=$((X_POS - MIN_X))

    magick "$TEMP_DIR/${SESSION_ID}_full.png" \
        -crop "${W}x${H}+${OFFSET}+0" +repage \
        "$TEMP_DIR/${SESSION_ID}_x${X_POS}.png"
done

# Apply wallpapers, matching each desktop to its crop by screen X position
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var allDesktops = desktops();
var sessionId = '$SESSION_ID';
for (var i = 0; i < allDesktops.length; i++) {
    var d = allDesktops[i];
    var g = screenGeometry(d.screen);
    d.wallpaperPlugin = 'org.kde.image';
    d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
    d.writeConfig('Image', 'file://$TEMP_DIR/' + sessionId + '_x' + g.x + '.png');
    d.writeConfig('SlidePaths', '');
}
" > /dev/null

# Reload all desktops to apply changes
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var allDesktops = desktops();
for (var i = 0; i < allDesktops.length; i++) {
    allDesktops[i].reloadConfig();
}
" > /dev/null

echo "Wallpaper applied: $WALLPAPER"
