---
name: ab-visual-compare
description: Compare two URLs (or same URL at different viewports, or before/after deployment) visually and structurally using pixel diffing and accessibility tree comparison.
---

# A/B Visual Compare

Compare two web pages visually and structurally. Capture screenshots and accessibility snapshots of both pages, then use ImageMagick to produce pixel diffs, blend overlays, and side-by-side comparison images. Combine visual analysis with DOM structure diffing for a comprehensive comparison.

## When to Use

- Comparing a staging deployment against production to catch visual regressions
- Verifying responsive design by comparing the same URL at different viewport sizes
- Reviewing design changes by comparing before/after screenshots
- Comparing competitor pages or design alternatives side by side
- Validating that a refactor did not change the visual output

## Prerequisites

- **Playwright MCP server** connected and available
- **ImageMagick**: The `compare`, `convert`, `composite`, `identify`, and `montage` commands must be available (`apt install imagemagick`, `brew install imagemagick`)

Verify prerequisites:

```bash
compare --version | head -1
convert --version | head -1
```

## Workflow

### Step 1: Capture URL A

Navigate to the first URL, take a screenshot, and capture the accessibility snapshot.

Use `browser_navigate` to go to URL A.

Use `browser_take_screenshot` to save the screenshot:
- filename: `page-a.png`

Use `browser_snapshot` to capture the accessibility tree. Save or note the output as "Snapshot A".

### Step 2: Capture URL B

Navigate to the second URL, take a screenshot, and capture the accessibility snapshot.

Use `browser_navigate` to go to URL B.

Use `browser_take_screenshot` to save the screenshot:
- filename: `page-b.png`

Use `browser_snapshot` to capture the accessibility tree. Save or note the output as "Snapshot B".

### Step 3: Generate Visual Diffs

Run the `side-by-side.sh` script to produce pixel diff, blend overlay, and side-by-side comparison images.

```bash
bash /home/noreddine/.claude/plugins/marketplaces/binaryPetsClaude/plugins/playwright-toolkit/skills/ab-visual-compare/scripts/side-by-side.sh \
  "page-a.png" \
  "page-b.png" \
  "/tmp/playwright-toolkit/ab-visual-compare/output"
```

### Step 4: Analyze Visual Differences

Use the `Read` tool to inspect the generated images:

- **diff-highlight.png**: Red pixels indicate areas that differ between the two pages. Focus on these areas to identify visual regressions or intentional changes.
- **side-by-side.png**: Both pages placed next to each other for quick visual comparison.
- **blend-overlay.png**: A 50% transparency overlay of both pages. Aligned elements appear sharp; misaligned elements appear ghosted/doubled.

### Step 5: Compare Accessibility Tree Snapshots

Compare "Snapshot A" and "Snapshot B" from Steps 1 and 2. Look for:

- Elements present in one snapshot but missing in the other
- Changed roles, names, or states of interactive elements
- Structural differences in the DOM hierarchy
- Missing or altered ARIA labels and landmarks

### Step 6: Report

Compile findings into a structured report:

- **Visual differences**: What areas changed visually (with pixel count from the script output)
- **Structural differences**: What DOM elements were added, removed, or modified
- **Missing/added elements**: Interactive elements or landmarks that differ
- **Severity assessment**: Whether differences are intentional changes or regressions

## Interpreting Results

- **Changed pixels count**: The `AE` (Absolute Error) metric reports the number of pixels that differ.
  - 0 pixels: Pages are visually identical
  - < 100 pixels: Negligible differences (sub-pixel rendering, anti-aliasing)
  - 100-10,000 pixels: Minor differences (font rendering, small layout shifts)
  - > 10,000 pixels: Significant visual differences worth investigating
- **diff-highlight.png**: Red areas mark changed regions. Solid red blocks indicate content that moved or was replaced. Scattered red dots suggest rendering differences.
- **blend-overlay.png**: Sharp text/images mean alignment matches. Blurred or doubled elements indicate position shifts.
- **Accessibility snapshots**: Structural changes in the accessibility tree often indicate meaningful DOM changes even when visual differences are subtle.

## Variations

### Same URL, Different Viewports

To compare responsive behavior, use `browser_resize` between captures:

1. `browser_resize` to width 1920, height 1080 before Step 1
2. `browser_resize` to width 375, height 812 before Step 2

### Same URL, With/Without Interaction

1. Capture URL in initial state for Step 1
2. Perform interactions (click, hover, scroll) then capture for Step 2

## Limitations

- Screenshots capture only the visible viewport by default. Use `fullPage: true` in `browser_take_screenshot` for full-page comparison, but note that full-page screenshots of different-length pages will have different heights (the script normalizes dimensions automatically).
- Sub-pixel rendering differences between browser sessions can produce false positives. A small number of changed pixels (< 100) is usually noise.
- Dynamic content (ads, timestamps, randomized content) will always show as differences. Consider using `browser_evaluate` to freeze or remove dynamic elements before capturing.
- The accessibility snapshot comparison is text-based and manual. Large pages produce long snapshots that can be difficult to diff by eye.
- ImageMagick's `compare` command can be slow on very large images (e.g., full-page screenshots of long pages). Consider cropping to regions of interest if performance is a concern.
