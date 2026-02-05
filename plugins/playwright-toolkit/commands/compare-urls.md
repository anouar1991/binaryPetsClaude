---
name: compare-urls
description: "A/B visual and structural comparison of two URLs across multiple viewports, with pixel diff, accessibility tree diff, and performance delta."
user_invocable: true
arguments:
  - name: url_a
    description: "First URL to compare"
    required: true
  - name: url_b
    description: "Second URL to compare"
    required: true
  - name: viewports
    description: "Comma-separated viewports: mobile,tablet,desktop (default: desktop)"
    required: false
---

# URL Comparison Orchestrator

Compare two URLs across visual, structural, and performance dimensions simultaneously. Runs video recording, visual diff, accessibility tree comparison, and CWV measurement for both URLs in a single orchestrated flow.

## Orchestration Strategy

For EACH viewport size, capture both URLs and produce:
1. **Visual diff** (ImageMagick pixel comparison)
2. **Structural diff** (accessibility tree comparison)
3. **Performance delta** (CWV measurements for both)
4. **Video** of each page loading (scene-change comparison)

## Phase 1: Viewport Matrix

Default viewports if not specified:
- desktop: 1440x900

All viewports if "all" specified:
- mobile: 375x667
- tablet: 768x1024
- desktop: 1440x900

## Phase 2: Per-Viewport Capture

For each viewport, do the following. The output directory is `/tmp/playwright-toolkit/compare-urls/<viewport>/`.

### Step 1 — Set viewport size

```
browser_resize({ width: <W>, height: <H> })
```

### Step 2 — Capture URL A

```
browser_navigate({ url: "<URL_A>" })
browser_wait_for({ time: 3 })
```

Install CWV observers (same as analyze-page), then:

```
browser_take_screenshot({ type: "png", filename: "/tmp/playwright-toolkit/compare-urls/<viewport>/page-a.png" })
browser_snapshot({ filename: "/tmp/playwright-toolkit/compare-urls/<viewport>/snapshot-a.md" })
```

Harvest CWV data via `browser_evaluate`.

### Step 3 — Capture URL B

```
browser_navigate({ url: "<URL_B>" })
browser_wait_for({ time: 3 })
```

Install CWV observers again (fresh page), then:

```
browser_take_screenshot({ type: "png", filename: "/tmp/playwright-toolkit/compare-urls/<viewport>/page-b.png" })
browser_snapshot({ filename: "/tmp/playwright-toolkit/compare-urls/<viewport>/snapshot-b.md" })
```

Harvest CWV data via `browser_evaluate`.

### Step 4 — Generate Visual Diffs

Run the side-by-side script:

```bash
bash /home/noreddine/.claude/plugins/marketplaces/binaryPetsClaude/plugins/playwright-toolkit/skills/ab-visual-compare/scripts/side-by-side.sh \
  /tmp/playwright-toolkit/compare-urls/<viewport>/page-a.png \
  /tmp/playwright-toolkit/compare-urls/<viewport>/page-b.png \
  /tmp/playwright-toolkit/compare-urls/<viewport>/
```

This produces:
- `diff-highlight.png` — Red pixel diff overlay
- `side-by-side.png` — Both pages next to each other
- `blend-overlay.png` — 50% transparency blend

### Step 5 — Read and Analyze

Read the diff images, both snapshots, and CWV data. Compare:

1. **Visual differences** from diff-highlight.png
2. **Structural differences** by comparing the two accessibility tree snapshots
3. **Performance differences** by comparing CWV metrics

## Phase 3: Parallel Video Recording (Optional)

For deeper analysis, record video of both URLs loading:

```javascript
browser_run_code({
  code: `async (page) => {
    const browser = page.context().browser();

    // Record URL A
    const ctxA = await browser.newContext({
      recordVideo: { dir: '/tmp/playwright-toolkit/compare-urls/video-a', size: { width: 1280, height: 720 } }
    });
    const pageA = await ctxA.newPage();
    await pageA.goto('<URL_A>', { waitUntil: 'networkidle' });
    await pageA.waitForTimeout(3000);
    const videoA = await pageA.video().path();
    await ctxA.close();

    // Record URL B
    const ctxB = await browser.newContext({
      recordVideo: { dir: '/tmp/playwright-toolkit/compare-urls/video-b', size: { width: 1280, height: 720 } }
    });
    const pageB = await ctxB.newPage();
    await pageB.goto('<URL_B>', { waitUntil: 'networkidle' });
    await pageB.waitForTimeout(3000);
    const videoB = await pageB.video().path();
    await ctxB.close();

    return { videoA, videoB };
  }`
})
```

Then extract scene-change frames from both and compare loading sequences.

## Phase 4: Report

```markdown
# URL Comparison: URL_A vs URL_B

## Visual Diff Summary

### Desktop (1440x900)
- Changed pixels: N (X% of viewport)
- Key differences: [describe from diff image analysis]
- [Embed diff-highlight.png analysis]

### Mobile (375x667) — if multi-viewport
- Changed pixels: N
- Key differences: ...

## Structural Diff
- Elements added in B: [list]
- Elements removed from A: [list]
- Changed roles/labels: [list]
- Heading hierarchy changes: [if any]

## Performance Delta

| Metric | URL A | URL B | Delta | Winner |
|--------|-------|-------|-------|--------|
| LCP | Xms | Xms | +/-Xms | A/B |
| CLS | X.XX | X.XX | +/-X.XX | A/B |
| INP | Xms | Xms | +/-Xms | A/B |

## Loading Sequence Comparison (if video recorded)
- URL A: First paint at Xs, fully loaded at Xs
- URL B: First paint at Xs, fully loaded at Xs
- Key difference: [B loads hero image faster but has layout shift at 2s]

## Recommendations
1. ...
```
