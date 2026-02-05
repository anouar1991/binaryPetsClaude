---
name: viewport-exposure-map
description: Track element visibility during scroll using IntersectionObserver and generate an exposure heatmap showing which content users actually see.
---

# Viewport Exposure Map

Measure how long each significant content element stays visible in the viewport during a full scroll session. Identify CTAs that are never seen, content with minimal exposure, and layout regions that dominate user attention.

## When to Use

- Auditing landing page layout to ensure CTAs are visible without excessive scrolling
- Validating that key content (hero sections, pricing, signup forms) receives adequate viewport time
- Comparing two page variants for scroll-based content exposure
- Detecting elements pushed below the fold or hidden behind lazy-load failures
- QA for long-form content pages (blogs, documentation, product pages)

## Prerequisites

- Playwright MCP server connected with a browser session available
- Target page must be publicly accessible or already authenticated in the browser session
- Page should be fully loaded before starting (wait for network idle or a specific selector)

## Workflow

### Step 1: Navigate to the Target Page

Use `browser_navigate` to load the page.

```
browser_navigate({ url: "https://example.com/landing" })
```

Wait for the page to be fully loaded:

```
browser_wait_for({ text: "some expected text" })
```

Or wait a fixed time if no specific text anchor exists:

```
browser_wait_for({ time: 3 })
```

### Step 2: Inject IntersectionObserver Tracking

Use `browser_evaluate` to attach an IntersectionObserver to all significant content elements. This must run before any scrolling occurs.

```javascript
browser_evaluate({
  function: `() => {
    const SELECTORS = [
      'h1', 'h2', 'h3', 'h4',
      'p', 'img', 'section', 'article',
      'button', 'a',
      '[data-testid]',
      'figure', 'video',
      '.card', '.hero', '.cta',
      'form', 'nav', 'footer', 'header'
    ];

    const elements = new Set();
    SELECTORS.forEach(sel => {
      document.querySelectorAll(sel).forEach(el => elements.add(el));
    });

    window.__exposureData = new Map();
    let idCounter = 0;

    const observer = new IntersectionObserver((entries) => {
      const now = performance.now();
      entries.forEach(entry => {
        const id = entry.target.dataset.__exposureId;
        const data = window.__exposureData.get(id);
        if (!data) return;

        if (entry.isIntersecting && entry.intersectionRatio > 0) {
          if (!data._enteredAt) {
            data._enteredAt = now;
            if (!data.firstSeen) data.firstSeen = now;
          }
          if (entry.intersectionRatio > data.maxRatio) {
            data.maxRatio = entry.intersectionRatio;
          }
        } else {
          if (data._enteredAt) {
            data.totalVisibleMs += (now - data._enteredAt);
            data._enteredAt = null;
          }
        }
      });
    }, {
      threshold: [0, 0.25, 0.5, 0.75, 1.0]
    });

    elements.forEach(el => {
      const id = 'exp_' + (idCounter++);
      el.dataset.__exposureId = id;
      window.__exposureData.set(id, {
        tag: el.tagName.toLowerCase(),
        text: (el.textContent || '').trim().substring(0, 80),
        className: el.className ? String(el.className).substring(0, 60) : '',
        id: el.id || '',
        rect: el.getBoundingClientRect().toJSON(),
        firstSeen: null,
        totalVisibleMs: 0,
        maxRatio: 0,
        _enteredAt: null
      });
      observer.observe(el);
    });

    window.__exposureObserver = observer;
    return { tracked: elements.size };
  }`
})
```

### Step 3: Perform Automated Scroll Sequence

Use `browser_run_code` to scroll the page smoothly from top to bottom and back. This simulates a real user scanning the page.

```javascript
browser_run_code({
  code: `async (page) => {
    // Scroll to bottom smoothly over ~5 seconds
    const scrollHeight = await page.evaluate(() => document.documentElement.scrollHeight);
    const viewportHeight = await page.evaluate(() => window.innerHeight);
    const steps = 25;
    const stepSize = (scrollHeight - viewportHeight) / steps;

    for (let i = 1; i <= steps; i++) {
      await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'smooth' }), stepSize * i);
      await page.waitForTimeout(200);
    }

    // Pause at bottom
    await page.waitForTimeout(2000);

    // Scroll back to top
    for (let i = steps - 1; i >= 0; i--) {
      await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'smooth' }), stepSize * i);
      await page.waitForTimeout(200);
    }

    // Pause at top
    await page.waitForTimeout(1000);
    return 'Scroll complete';
  }`
})
```

### Step 4: Harvest Exposure Data

Use `browser_evaluate` to finalize timing for any currently-visible elements and extract the results.

```javascript
browser_evaluate({
  function: `() => {
    const now = performance.now();
    const results = [];

    window.__exposureData.forEach((data, id) => {
      // Close any open visibility session
      if (data._enteredAt) {
        data.totalVisibleMs += (now - data._enteredAt);
        data._enteredAt = null;
      }

      results.push({
        id: id,
        tag: data.tag,
        text: data.text,
        className: data.className,
        elementId: data.id,
        totalVisibleSec: Math.round(data.totalVisibleMs / 100) / 10,
        maxRatio: Math.round(data.maxRatio * 100),
        firstSeen: data.firstSeen ? Math.round(data.firstSeen) : null,
        neverSeen: data.firstSeen === null
      });
    });

    // Sort by totalVisibleSec descending
    results.sort((a, b) => b.totalVisibleSec - a.totalVisibleSec);

    const neverSeen = results.filter(r => r.neverSeen);
    const underOneSecond = results.filter(r => !r.neverSeen && r.totalVisibleSec < 1.0);
    const ctas = results.filter(r =>
      r.tag === 'button' || r.tag === 'a' ||
      r.className.includes('cta') || r.className.includes('btn')
    );
    const neverSeenCtas = ctas.filter(r => r.neverSeen);

    return {
      totalTracked: results.length,
      neverSeenCount: neverSeen.length,
      underOneSecondCount: underOneSecond.length,
      neverSeenCtas: neverSeenCtas,
      topExposed: results.slice(0, 15),
      neverSeen: neverSeen.slice(0, 20),
      underOneSecond: underOneSecond.slice(0, 20),
      allResults: results
    };
  }`
})
```

### Step 5 (Optional): Inject CSS Heatmap Overlay

Use `browser_evaluate` to color-code elements based on their exposure time. Green indicates high exposure, yellow is moderate, red means never or barely seen.

```javascript
browser_evaluate({
  function: `() => {
    window.__exposureData.forEach((data, id) => {
      const el = document.querySelector('[data-__exposure-id="' + id + '"]');
      if (!el) return;

      // Close any open session
      const now = performance.now();
      if (data._enteredAt) {
        data.totalVisibleMs += (now - data._enteredAt);
        data._enteredAt = null;
      }

      const sec = data.totalVisibleMs / 1000;
      let color;
      if (data.firstSeen === null) {
        color = 'rgba(255, 0, 0, 0.3)';       // Red: never seen
      } else if (sec < 1.0) {
        color = 'rgba(255, 165, 0, 0.3)';     // Orange: <1s
      } else if (sec < 3.0) {
        color = 'rgba(255, 255, 0, 0.25)';    // Yellow: 1-3s
      } else {
        color = 'rgba(0, 200, 0, 0.25)';      // Green: 3s+
      }

      el.style.outline = '2px solid ' + color.replace('0.3', '0.8').replace('0.25', '0.8');
      el.style.backgroundColor = color;
    });
    return 'Heatmap overlay applied';
  }`
})
```

### Step 6: Capture Full-Page Screenshot

Take a full-page screenshot showing the heatmap overlay.

```
browser_take_screenshot({ fullPage: true, type: "png", filename: "exposure-heatmap.png" })
```

## Interpreting Results

### Exposure Time Thresholds

| Exposure Time | Status | Meaning |
|---|---|---|
| 0 seconds (never seen) | Critical | Element is off-screen or hidden; users never see it |
| < 1 second | Warning | Barely visible; users likely scan past it |
| 1 - 3 seconds | Acceptable | Moderate exposure; may be noticed during scroll |
| > 3 seconds | Good | Strong visibility; likely above the fold or in a sticky area |

### Max Intersection Ratio

| Max Ratio | Meaning |
|---|---|
| 0% | Never entered viewport |
| < 50% | Only partially visible (clipped by viewport edges) |
| 75 - 100% | Fully or nearly fully visible at peak |

### Key Findings to Report

1. **Never-seen CTAs**: Buttons or links with `neverSeen: true` indicate conversion-critical elements that no user will interact with during a normal scroll
2. **Below-1s content**: Important content (headings, value propositions) with less than 1 second of exposure may need to be repositioned
3. **Top-exposed elements**: The 10-15 elements with the highest exposure time reveal what dominates the user's visual experience
4. **Ratio vs. time mismatch**: An element with high `maxRatio` but low `totalVisibleSec` was fully visible but only briefly (fast scroll zone)

## Heatmap Color Legend

| Color | Meaning |
|---|---|
| Red | Never entered viewport |
| Orange | Less than 1 second total exposure |
| Yellow | 1 to 3 seconds exposure |
| Green | More than 3 seconds exposure |

## Limitations

- **Smooth scroll timing**: Actual exposure durations depend on scroll speed. The automated scroll takes approximately 12 seconds total. Adjust step count and delays for longer or shorter pages.
- **Lazy-loaded content**: Elements that load only when scrolled into view will be tracked from their load time, not from page load. The observer handles this correctly, but elements that never load will not be tracked at all.
- **CSS visibility**: IntersectionObserver tracks geometric viewport intersection. It does not detect `opacity: 0`, `visibility: hidden`, or elements covered by overlays (z-index occlusion).
- **Dynamic content**: Single-page apps that swap content during scroll (infinite scroll, virtual lists) may show misleading results since elements are added/removed from the DOM.
- **Fixed/sticky elements**: Elements with `position: fixed` or `position: sticky` will show high exposure time since they remain in viewport during scroll. This is accurate but may skew "top exposed" rankings.
- **Works in all browsers**: This skill uses standard `IntersectionObserver` API and does not require Chromium-specific features.
