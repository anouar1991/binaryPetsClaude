#!/bin/bash
# Usage: waterfall-annotate.sh <frames-dir> <output-file> [labels-file]
# labels-file: one label per line matching frame order, e.g. "0ms - Blank" "200ms - FCP"
FRAMES_DIR="$1"
OUTPUT="$2"
LABELS_FILE="${3:-}"

set -euo pipefail

# Annotate each frame with its label
i=0
for frame in "${FRAMES_DIR}"/frame-*.png; do
  [ -f "$frame" ] || continue
  label=""
  if [ -n "$LABELS_FILE" ] && [ -f "$LABELS_FILE" ]; then
    label=$(sed -n "$((i+1))p" "$LABELS_FILE")
  fi
  if [ -n "$label" ]; then
    convert "$frame" \
      -gravity South \
      -background '#000000CC' \
      -fill white \
      -font Courier \
      -pointsize 16 \
      -splice 0x30 \
      -annotate +0+5 "$label" \
      "${FRAMES_DIR}/annotated-$(printf '%04d' $i).png"
  else
    cp "$frame" "${FRAMES_DIR}/annotated-$(printf '%04d' $i).png"
  fi
  i=$((i + 1))
done

# Create horizontal filmstrip montage
montage "${FRAMES_DIR}"/annotated-*.png \
  -tile x1 \
  -geometry '320x180+4+4' \
  -background '#1a1a2e' \
  -border 2 \
  -bordercolor '#333' \
  "$OUTPUT"

echo "Filmstrip: $OUTPUT ($i frames)"
