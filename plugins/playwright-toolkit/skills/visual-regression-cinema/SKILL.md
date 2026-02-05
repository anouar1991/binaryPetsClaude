---
name: visual-regression-cinema
description: Record video of browser interactions, extract frames at scene-change boundaries, pixel-diff consecutive frames, and produce a filmstrip of meaningful visual transitions.
---

# Visual Regression Cinema

Record a video of browser interactions using Playwright's built-in video recording, then use ffmpeg to extract frames at scene-change boundaries and ImageMagick to pixel-diff consecutive frames. The result is a filmstrip of meaningful visual transitions showing exactly what changed and when.

## When to Use

- Verifying that a multi-step user flow produces the expected visual states
- Debugging CSS transitions, animations, or dynamic content that changes over time
- Reviewing visual regressions across a sequence of interactions (click, scroll, hover)
- Creating a visual changelog of UI behavior for design review
- Investigating flaky visual tests by capturing the exact moment something changes

## Prerequisites

- **Playwright MCP server** connected and available
- **ffmpeg**: Install via `npx playwright install ffmpeg` or system package manager (`apt install ffmpeg`, `brew install ffmpeg`)
- **ImageMagick**: The `compare`, `convert`, and `identify` commands must be available (`apt install imagemagick`, `brew install imagemagick`)

Verify prerequisites:

```bash
ffmpeg -version | head -1
compare --version | head -1
```

## Workflow

### Step 1: Create a Video-Recording Browser Context

Use `browser_run_code` to create a new BrowserContext with video recording enabled, then open a new page in that context.

```javascript
async (page) => {
  const context = await page.context().browser().newContext({
    recordVideo: {
      dir: '/tmp/playwright-toolkit/visual-regression-cinema',
      size: { width: 1280, height: 720 }
    }
  });
  const newPage = await context.newPage();
  // Store references for later steps
  globalThis.__vrcContext = context;
  globalThis.__vrcPage = newPage;
  return 'Video-recording context created. Page ready for interactions.';
}
```

### Step 2: Navigate and Interact

Use `browser_run_code` to perform the interactions you want to capture. Navigate to the target URL, scroll, click elements, fill forms, or trigger any UI behavior.

```javascript
async (page) => {
  const p = globalThis.__vrcPage;

  // Navigate to target
  await p.goto('https://example.com', { waitUntil: 'networkidle' });
  await p.waitForTimeout(1000);

  // Perform interactions (customize as needed)
  await p.evaluate(() => window.scrollTo(0, document.body.scrollHeight / 2));
  await p.waitForTimeout(800);

  await p.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await p.waitForTimeout(800);

  return 'Interactions complete. Ready to finalize video.';
}
```

### Step 3: Finalize the Video and Get Its Path

Close the context to finalize the video file, then retrieve the video path.

```javascript
async (page) => {
  const p = globalThis.__vrcPage;
  const videoPath = await p.video().path();
  await globalThis.__vrcContext.close();

  // Clean up global refs
  delete globalThis.__vrcPage;
  delete globalThis.__vrcContext;

  return `Video saved to: ${videoPath}`;
}
```

### Step 4: Extract Scene-Change Frames and Generate Diffs

Run the `frame-diff.sh` script to extract frames at scene-change boundaries using ffmpeg, then generate pixel diffs between consecutive frames using ImageMagick.

```bash
bash /home/noreddine/.claude/plugins/marketplaces/binaryPetsClaude/plugins/playwright-toolkit/skills/visual-regression-cinema/scripts/frame-diff.sh \
  "<video-path-from-step-3>" \
  "/tmp/playwright-toolkit/visual-regression-cinema/output" \
  0.3
```

The threshold parameter (default `0.3`) controls scene-change sensitivity. Lower values (e.g., `0.1`) detect subtler changes; higher values (e.g., `0.5`) only detect major transitions.

### Step 5: Read the Extracted Frames and Diffs

Use the `Read` tool to visually inspect each scene-change frame (`scene-*.png`) and each diff image (`diff-*.png`) in the output directory. Also read `timestamps.txt` for timing information.

### Step 6: Report

Compile a timeline of visual state changes:

- **Timestamp**: When each scene change occurred in the video
- **Frame content**: What the page looked like at that moment
- **Diff analysis**: What specifically changed between consecutive frames (layout shifts, content appearing/disappearing, color changes)
- **RMSE values**: Quantitative measure of change magnitude from the diff text files

## Interpreting Results

- **Scene-change frames** (`scene-*.png`): Each represents a visually distinct state captured at the moment the scene changed significantly.
- **Diff images** (`diff-*.png`): Red-highlighted areas show pixels that differ between consecutive frames. More red means more change.
- **RMSE values** (in `diff-*.txt`): Root Mean Square Error between consecutive frames. Higher values indicate larger visual differences.
  - RMSE < 1000: Minor change (e.g., cursor blink, subtle animation)
  - RMSE 1000-5000: Moderate change (e.g., content appearing, color shift)
  - RMSE > 5000: Major change (e.g., page navigation, modal overlay)
- **timestamps.txt**: Contains `pts_time` values showing when each scene change occurred in the video timeline.

## Limitations

- Video recording requires a headed or headful-like browser context; some CI environments may need `xvfb` for video capture.
- The scene-change threshold is a heuristic; very gradual transitions (slow fades) may not trigger extraction. Adjust the threshold parameter to compensate.
- ffmpeg scene detection works on full frames, so small localized changes (e.g., a spinner in a corner) may not exceed the threshold.
- Video codec and compression can introduce artifacts that affect diff accuracy. Playwright records in WebM format by default.
- ImageMagick `compare` requires both images to have identical dimensions; the script uses frames from the same video, so this is handled automatically.
- Very long recordings produce large video files and many frames. Keep interactions focused and concise.
