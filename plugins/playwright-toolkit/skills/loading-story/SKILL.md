---
name: loading-story
description: Capture timed screenshots during page load, overlay with network waterfall data, and produce a visual narrative of the loading experience with annotated filmstrip.
---

# Loading Story

Capture the complete loading experience of a web page as a visual narrative. Collect performance milestones (First Paint, First Contentful Paint, Largest Contentful Paint), take screenshots at key moments, gather network waterfall data, and produce an annotated filmstrip that tells the story of what the user sees at each stage of loading.

## When to Use

- Diagnosing slow page loads by visualizing what the user sees at each milestone
- Comparing loading experiences between pages, deployments, or network conditions
- Presenting loading performance to stakeholders with visual evidence
- Identifying render-blocking resources by correlating network requests with paint events
- Optimizing perceived performance by understanding the visual loading sequence

## Prerequisites

- **Playwright MCP server** connected and available
- **ImageMagick**: The `convert` and `montage` commands must be available (`apt install imagemagick`, `brew install imagemagick`)

Verify prerequisites:

```bash
convert --version | head -1
montage --version | head -1
```

## Workflow

### Step 1: Install Performance Observers

Before navigating, use `browser_evaluate` to install a PerformanceObserver on the current page that will capture paint and LCP events. This must be done via `addInitScript` so it runs before the page loads.

```javascript
async (page) => {
  await page.context().addInitScript(() => {
    window.__loadingStoryMilestones = [];

    const paintObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        window.__loadingStoryMilestones.push({
          name: entry.name,
          startTime: Math.round(entry.startTime),
          type: 'paint'
        });
      }
    });
    paintObserver.observe({ type: 'paint', buffered: true });

    const lcpObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        window.__loadingStoryMilestones.push({
          name: 'largest-contentful-paint',
          startTime: Math.round(entry.startTime),
          type: 'lcp',
          element: entry.element ? entry.element.tagName : 'unknown',
          size: entry.size
        });
      }
    });
    lcpObserver.observe({ type: 'largest-contentful-paint', buffered: true });
  });

  return 'Performance observers installed via addInitScript.';
}
```

### Step 2: Navigate to the Target URL

Use `browser_navigate` to go to the target URL. The performance observers from Step 1 will automatically capture paint events as they occur.

### Step 3: Wait for Full Page Load

Use `browser_wait_for` to allow the page to fully load. Wait at least 3-5 seconds for LCP to fire on most pages, or wait for a specific element that indicates full load.

### Step 4: Harvest Performance Milestones

Use `browser_evaluate` to collect all captured milestones along with Navigation Timing data.

```javascript
async (page) => {
  const data = await page.evaluate(() => {
    const nav = performance.getEntriesByType('navigation')[0];
    const milestones = window.__loadingStoryMilestones || [];

    // Add navigation timing milestones
    const timingMilestones = [
      { name: 'domContentLoaded', startTime: Math.round(nav.domContentLoadedEventStart), type: 'timing' },
      { name: 'loadEvent', startTime: Math.round(nav.loadEventStart), type: 'timing' },
      { name: 'domInteractive', startTime: Math.round(nav.domInteractive), type: 'timing' },
      { name: 'responseStart (TTFB)', startTime: Math.round(nav.responseStart), type: 'timing' }
    ];

    const all = [...milestones, ...timingMilestones]
      .filter(m => m.startTime > 0)
      .sort((a, b) => a.startTime - b.startTime);

    return {
      milestones: all,
      url: window.location.href,
      totalLoadTime: Math.round(nav.loadEventEnd - nav.startTime)
    };
  });

  return JSON.stringify(data, null, 2);
}
```

### Step 5: Capture Network Waterfall

Use `browser_network_requests` to get the complete network waterfall. Note the request timings, sizes, and types to correlate with visual milestones.

Set `includeStatic: true` to capture all resources including images, fonts, and scripts.

### Step 6: Take Screenshots at Milestone Intervals

Use `browser_run_code` to replay the navigation while capturing screenshots at timed intervals corresponding to the milestones discovered in Step 4. This creates a visual record of what the user sees at each stage.

```javascript
async (page) => {
  const framesDir = '/tmp/playwright-toolkit/loading-story/frames';
  const fs = require('fs');
  fs.mkdirSync(framesDir, { recursive: true });

  // Define capture intervals (in ms from navigation start)
  // Adjust these based on milestones from Step 4
  const capturePoints = [0, 100, 200, 500, 800, 1000, 1500, 2000, 3000, 5000];

  const labels = [];

  for (let i = 0; i < capturePoints.length; i++) {
    const delay = i === 0 ? 0 : capturePoints[i] - capturePoints[i - 1];

    if (i === 0) {
      // Navigate fresh
      page.goto('TARGET_URL_HERE', { waitUntil: 'commit' }).catch(() => {});
      await new Promise(r => setTimeout(r, 50));
    } else {
      await new Promise(r => setTimeout(r, delay));
    }

    const framePath = `${framesDir}/frame-${String(i).padStart(4, '0')}.png`;
    await page.screenshot({ path: framePath });
    labels.push(`${capturePoints[i]}ms`);
  }

  // Write labels file
  fs.writeFileSync(`${framesDir}/labels.txt`, labels.join('\n'));

  return `Captured ${capturePoints.length} frames in ${framesDir}`;
}
```

### Step 7: Annotate and Create Filmstrip

Run the `waterfall-annotate.sh` script to annotate each frame with its timestamp and milestone label, then montage them into a horizontal filmstrip.

```bash
bash /home/noreddine/.claude/plugins/marketplaces/binaryPetsClaude/plugins/playwright-toolkit/skills/loading-story/scripts/waterfall-annotate.sh \
  "/tmp/playwright-toolkit/loading-story/frames" \
  "/tmp/playwright-toolkit/loading-story/filmstrip.png" \
  "/tmp/playwright-toolkit/loading-story/frames/labels.txt"
```

### Step 8: Read the Filmstrip

Use the `Read` tool to visually inspect the annotated filmstrip at `/tmp/playwright-toolkit/loading-story/filmstrip.png`.

### Step 9: Compose the Narrative Report

Write a narrative that describes the loading experience from the user's perspective, incorporating all collected data:

- **Timeline**: At each milestone timestamp, describe what the user sees
- **Network correlation**: Which resources were loading/completed at each visual state
- **Bottlenecks**: Identify render-blocking resources or long gaps between milestones
- **Recommendations**: Suggest optimizations based on the observed loading sequence

Example narrative format:
> "At 0ms the browser begins navigation. At 180ms (TTFB) the first byte arrives after a 180ms server response time. At 350ms First Paint occurs -- the user sees a white screen with the background color applied. At 520ms First Contentful Paint fires as the header and navigation render, while 3 JavaScript bundles (total 450KB) are still downloading. At 1200ms the hero image appears as Largest Contentful Paint, bringing the page to a visually complete state. The main thread remains blocked until 1800ms when the remaining JS executes and the page becomes interactive at domInteractive."

## Interpreting Results

- **TTFB (Time to First Byte)**: Server response time. Values > 600ms suggest server-side optimization needed.
- **First Paint (FP)**: When the browser first renders anything (even a background color). Long gap between TTFB and FP suggests render-blocking resources.
- **First Contentful Paint (FCP)**: When meaningful content first appears. Should be < 1.8s for good user experience.
- **Largest Contentful Paint (LCP)**: When the largest visible content element renders. Should be < 2.5s. The `element` and `size` fields identify what triggered LCP.
- **domInteractive**: When the DOM is ready for interaction. Large gap between FCP and domInteractive suggests heavy JavaScript execution.
- **loadEvent**: When all resources (images, scripts, stylesheets) finish loading.

### Performance Budget Reference

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| TTFB | < 200ms | 200-600ms | > 600ms |
| FCP | < 1.8s | 1.8-3.0s | > 3.0s |
| LCP | < 2.5s | 2.5-4.0s | > 4.0s |
| Total Load | < 3.0s | 3.0-5.0s | > 5.0s |

## Limitations

- Screenshot timing is approximate. Playwright's `page.screenshot()` takes 50-200ms to execute, so frames captured at rapid intervals (< 100ms apart) may not represent the exact visual state at that timestamp.
- The `addInitScript` approach requires navigating after the script is installed. If you need to capture a page that is already loaded, the observers will not have buffered early events.
- LCP may update multiple times during load as larger elements render. The final LCP value is the most meaningful.
- Network waterfall data from `browser_network_requests` does not include sub-resource timing breakdowns (DNS, TCP, TLS). Use browser DevTools or the Resource Timing API for granular network analysis.
- The filmstrip montage can become very wide with many frames. Consider selecting only the most meaningful capture points rather than capturing at every 100ms interval.
- Service workers, cached resources, and CDN behavior can significantly affect loading times. Results may vary between runs. Consider averaging multiple captures for reliable benchmarks.
