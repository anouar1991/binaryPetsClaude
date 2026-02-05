#!/bin/bash
# Usage: side-by-side.sh <image-a> <image-b> <output-dir>
IMG_A="$1"
IMG_B="$2"
OUTPUT_DIR="$3"

set -euo pipefail
mkdir -p "$OUTPUT_DIR"

# Get dimensions
A_W=$(identify -format "%w" "$IMG_A")
A_H=$(identify -format "%h" "$IMG_A")
B_W=$(identify -format "%w" "$IMG_B")
B_H=$(identify -format "%h" "$IMG_B")

# Use max dimensions
MAX_W=$(( A_W > B_W ? A_W : B_W ))
MAX_H=$(( A_H > B_H ? A_H : B_H ))

# Normalize both to same dimensions
convert "$IMG_A" -gravity NorthWest -extent "${MAX_W}x${MAX_H}" -background white "${OUTPUT_DIR}/a-normalized.png"
convert "$IMG_B" -gravity NorthWest -extent "${MAX_W}x${MAX_H}" -background white "${OUTPUT_DIR}/b-normalized.png"

# Pixel diff with red highlights
CHANGED=$(compare -metric AE -highlight-color red -lowlight-color 'rgba(255,255,255,0.1)' \
  "${OUTPUT_DIR}/a-normalized.png" "${OUTPUT_DIR}/b-normalized.png" \
  "${OUTPUT_DIR}/diff-highlight.png" 2>&1) || true
echo "Changed pixels: $CHANGED"

# Side-by-side comparison
convert "${OUTPUT_DIR}/a-normalized.png" "${OUTPUT_DIR}/b-normalized.png" +append "${OUTPUT_DIR}/side-by-side.png"

# Overlay blend (50% transparency)
composite -blend 50 "${OUTPUT_DIR}/a-normalized.png" "${OUTPUT_DIR}/b-normalized.png" "${OUTPUT_DIR}/blend-overlay.png"

echo "Output: diff-highlight.png, side-by-side.png, blend-overlay.png in $OUTPUT_DIR"
