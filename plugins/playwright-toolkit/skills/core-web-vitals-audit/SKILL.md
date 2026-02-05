---
name: core-web-vitals-audit
description: >
  Measure Core Web Vitals (LCP, INP, CLS) with full attribution across mobile,
  tablet, and desktop viewports. Produces a multi-viewport report card with
  pass/fail grades, element-level attribution, and annotated screenshots.
---

# Core Web Vitals Audit

Perform a comprehensive Core Web Vitals assessment across three viewport
breakpoints. Installs PerformanceObserver-based instrumentation, drives
realistic user interactions, and harvests LCP, INP, and CLS with full
attribution data.

## When to Use

- Evaluating page performance before a release.
- Diagnosing which element is the Largest Contentful Paint.
- Identifying layout shift sources and their visual impact.
- Measuring interaction responsiveness (INP) on a real page.
- Comparing performance across mobile, tablet, and desktop viewports.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for `PerformanceObserver` with full attribution (`layoutShift.sources`, `largest-contentful-paint` element attribution, `event` timing breakdowns).
- Target page must be reachable from the browser instance.

## Workflow

Repeat the following steps for each viewport:

| Viewport | Width | Height |
|----------|-------|--------|
| Mobile   | 375   | 667    |
| Tablet   | 768   | 1024   |
| Desktop  | 1440  | 900    |

### Step 1 -- Resize the Viewport

Call `browser_resize` with the viewport dimensions.

```
browser_resize({ width: 375, height: 667 })
```

### Step 2 -- Navigate to the Target Page

Call `browser_navigate` to load the page. This triggers a fresh page load so
LCP and CLS observers capture the full loading lifecycle.

```
browser_navigate({ url: "<target_url>" })
```

### Step 3 -- Install Performance Observers

Call `browser_evaluate` with the following function to set up observers for all
three Core Web Vitals before any interactions occur.

```javascript
browser_evaluate({
  function: `() => {
    window.__cwv = { lcp: null, cls: { value: 0, sources: [] }, interactions: [] };

    // --- LCP Observer ---
    new PerformanceObserver((list) => {
      const entries = list.getEntries();
      const last = entries[entries.length - 1];
      window.__cwv.lcp = {
        value: last.startTime,
        renderTime: last.renderTime,
        loadTime: last.loadTime,
        size: last.size,
        element: last.element ? last.element.tagName + (last.element.id ? '#' + last.element.id : '') : null,
        url: last.url || null
      };
      // Store element reference for screenshot annotation
      window.__cwv._lcpElement = last.element || null;
    }).observe({ type: 'largest-contentful-paint', buffered: true });

    // --- CLS Observer ---
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!entry.hadRecentInput) {
          window.__cwv.cls.value += entry.value;
          if (entry.sources) {
            for (const src of entry.sources) {
              window.__cwv.cls.sources.push({
                node: src.node ? src.node.tagName + (src.node.id ? '#' + src.node.id : '') + (src.node.className ? '.' + String(src.node.className).split(' ')[0] : '') : null,
                previousRect: src.previousRect ? { x: src.previousRect.x, y: src.previousRect.y, width: src.previousRect.width, height: src.previousRect.height } : null,
                currentRect: src.currentRect ? { x: src.currentRect.x, y: src.currentRect.y, width: src.currentRect.width, height: src.currentRect.height } : null
              });
            }
          }
        }
      }
    }).observe({ type: 'layout-shift', buffered: true });

    // --- INP / Event Timing Observer ---
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        window.__cwv.interactions.push({
          name: entry.name,
          duration: entry.duration,
          startTime: entry.startTime,
          processingStart: entry.processingStart,
          processingEnd: entry.processingEnd,
          inputDelay: entry.processingStart - entry.startTime,
          processingTime: entry.processingEnd - entry.processingStart,
          presentationDelay: entry.startTime + entry.duration - entry.processingEnd,
          interactionId: entry.interactionId,
          target: entry.target ? entry.target.tagName + (entry.target.id ? '#' + entry.target.id : '') : null
        });
      }
    }).observe({ type: 'event', durationThreshold: 0, buffered: true });

    return 'CWV observers installed';
  }`
})
```

### Step 4 -- Perform Realistic Interactions

After observers are installed, simulate realistic user behavior to trigger INP
measurements and potential layout shifts.

1. **Scroll the page** -- call `browser_evaluate`:
   ```javascript
   browser_evaluate({
     function: `() => {
       window.scrollBy(0, window.innerHeight * 2);
       return 'scrolled';
     }`
   })
   ```

2. **Wait for content to settle** -- call `browser_wait_for`:
   ```
   browser_wait_for({ time: 2 })
   ```

3. **Click the primary CTA** -- take a `browser_snapshot` to identify the
   primary call-to-action, then call `browser_click` on it using the ref from
   the snapshot.

4. **Type in a search field** (if present) -- use `browser_snapshot` to locate
   a search input, then call `browser_type` with a short query string.

5. **Wait again** for any async responses:
   ```
   browser_wait_for({ time: 2 })
   ```

### Step 5 -- Harvest Metrics

Call `browser_evaluate` to collect all recorded data.

```javascript
browser_evaluate({
  function: `() => {
    const data = window.__cwv;

    // Compute INP (p98 of interaction durations)
    const durations = data.interactions
      .filter(i => i.interactionId > 0)
      .map(i => i.duration)
      .sort((a, b) => a - b);

    let inp = 0;
    if (durations.length > 0) {
      const p98Index = Math.min(Math.ceil(durations.length * 0.98) - 1, durations.length - 1);
      inp = durations[p98Index];
    }

    return {
      lcp: data.lcp,
      cls: { value: Math.round(data.cls.value * 10000) / 10000, sources: data.cls.sources.slice(0, 10) },
      inp: {
        value: inp,
        totalInteractions: durations.length,
        slowest5: data.interactions
          .filter(i => i.interactionId > 0)
          .sort((a, b) => b.duration - a.duration)
          .slice(0, 5)
      }
    };
  }`
})
```

### Step 6 -- Annotate and Screenshot the LCP Element

Call `browser_evaluate` to highlight the LCP element, then take a screenshot.

```javascript
browser_evaluate({
  function: `() => {
    const el = window.__cwv._lcpElement;
    if (el) {
      el.style.outline = '4px solid red';
      el.style.outlineOffset = '2px';
      el.scrollIntoView({ block: 'center' });
      return 'LCP element highlighted: ' + el.tagName + (el.id ? '#' + el.id : '');
    }
    return 'No LCP element reference available';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "cwv-<viewport>-lcp.png" })
```

### Step 7 -- Repeat for Next Viewport

Go back to Step 1 with the next viewport dimensions.

## Interpreting Results

### Thresholds (per Google Web Vitals)

| Metric | Good         | Needs Improvement | Poor     |
|--------|--------------|-------------------|----------|
| LCP    | < 2500 ms    | 2500 -- 4000 ms   | > 4000 ms |
| CLS    | < 0.1        | 0.1 -- 0.25       | > 0.25   |
| INP    | < 200 ms     | 200 -- 500 ms     | > 500 ms |

### Report Card Format

For each viewport, produce a summary:

```
## Core Web Vitals -- Mobile (375x667)

| Metric | Value   | Rating             |
|--------|---------|--------------------|
| LCP    | 1850 ms | GOOD               |
| CLS    | 0.032   | GOOD               |
| INP    | 245 ms  | NEEDS IMPROVEMENT  |

### LCP Attribution
- Element: IMG#hero-banner
- Size: 285,600 px
- Render Time: 1850 ms

### CLS Sources (top shifts)
1. DIV.ad-slot -- shifted 120px downward at load
2. IMG.lazy -- shifted 45px when decoded

### Slowest Interactions
1. click on BUTTON#submit -- 245ms (inputDelay: 12ms, processing: 180ms, presentation: 53ms)
2. keydown on INPUT#search -- 89ms (inputDelay: 4ms, processing: 62ms, presentation: 23ms)
```

### What to Look For

- **LCP element is an image**: check if it has `loading="lazy"` (anti-pattern for above-the-fold images), missing `fetchpriority="high"`, or no preload hint.
- **CLS sources reference ad slots or lazy images**: add explicit `width`/`height` or CSS `aspect-ratio` to reserve space.
- **INP has high processingTime**: the event handler is doing heavy synchronous work. Suggest `requestIdleCallback`, `scheduler.yield()`, or moving work to a Web Worker.
- **INP has high presentationDelay**: the browser is spending time on layout/paint after the handler. Look for forced reflows or large DOM mutations in the handler.

## Limitations

- **Chromium only**: `largest-contentful-paint` with element attribution, `layout-shift` with `sources`, and `event` timing with `interactionId` require Chromium. Firefox and Safari have partial or no support.
- **INP requires real interactions**: synthetic clicks via Playwright count as real events for Event Timing API, but the input delay component may be lower than real user input since there is no OS-level input queue contention.
- **CLS is session-based**: this measures CLS during the audit session only. Real-user CLS may differ based on scroll depth and session length.
- **`performance.memory` is Chromium-only** and not used here, but if heap analysis is needed, see the Memory Leak Detector skill.
- **Single page load**: LCP is only meaningful for the initial page load (or soft navigation in SPA). Re-navigating resets the observer.
