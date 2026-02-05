#!/bin/bash
# Usage: frame-diff.sh <video-file> <output-dir> [scene-threshold]
# Extracts frames at scene changes, generates pixel diffs between consecutive frames
VIDEO="$1"
OUTPUT_DIR="$2"
THRESHOLD="${3:-0.3}"

set -euo pipefail
mkdir -p "$OUTPUT_DIR"

# Extract frames at scene change boundaries
ffmpeg -y -i "$VIDEO" \
  -vf "select=gt(scene\,${THRESHOLD}),showinfo" \
  -vsync vfn \
  "${OUTPUT_DIR}/scene-%04d.png" 2>&1 | grep "pts_time" > "${OUTPUT_DIR}/timestamps.txt" || true

# Count extracted frames
FRAME_COUNT=$(ls "${OUTPUT_DIR}"/scene-*.png 2>/dev/null | wc -l)
echo "Extracted $FRAME_COUNT scene-change frames"

# Generate diffs between consecutive frames
prev=""
for f in "${OUTPUT_DIR}"/scene-*.png; do
  if [ -n "$prev" ]; then
    base=$(basename "$f" .png)
    compare -metric RMSE "$prev" "$f" "${OUTPUT_DIR}/diff-${base}.png" 2>"${OUTPUT_DIR}/diff-${base}.txt" || true
    echo "Diff: $(basename "$prev") → $(basename "$f"): $(cat "${OUTPUT_DIR}/diff-${base}.txt")"
  fi
  prev="$f"
done

echo "Done. Frames: ${OUTPUT_DIR}/scene-*.png, Diffs: ${OUTPUT_DIR}/diff-*.png"
