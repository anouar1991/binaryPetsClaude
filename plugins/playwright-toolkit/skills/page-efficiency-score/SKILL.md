---
name: page-efficiency-score
description: Compute a composite 0-100 efficiency score using JS/CSS coverage, render-blocking resources, transfer size, and navigation timing via CDP.
---

# Page Efficiency Score

Calculate a weighted composite score (0-100) that measures how efficiently a page uses its resources. Combines JavaScript coverage, CSS coverage, render-blocking resource count, total transfer size, TTFB, and DOMContentLoaded timing into a single actionable metric.

## When to Use

- Quick health check of page load efficiency during development or QA
- Comparing efficiency across pages, routes, or deployments
- Identifying the primary bottleneck category (JS bloat, CSS bloat, render-blocking, network)
- Tracking efficiency improvements over time with a single comparable number
- Prioritizing optimization efforts based on weighted category scores

## Prerequisites

- Playwright MCP server connected with a **Chromium** browser session (CDP required for JS/CSS coverage)
- Target page must be accessible in the browser session
- Page should be tested in a clean state (clear cache for accurate transfer size measurement, or test with cache to measure real-world performance)
- Network conditions should be consistent between comparisons

## Scoring System

The composite score is the weighted sum of six category scores. Each category is scored 0, 5, or 10 based on thresholds.

### Scoring Table

| Category | Weight | Good (10 pts) | OK (5 pts) | Bad (0 pts) |
|---|---|---|---|---|
| JS Unused % | 25% | < 30% unused | 30-60% unused | > 60% unused |
| CSS Unused % | 15% | < 40% unused | 40-70% unused | > 70% unused |
| Render-blocking Resources | 20% | 0-2 resources | 3-5 resources | > 5 resources |
| Total Transfer Size | 20% | < 500 KB | 500 KB - 2 MB | > 2 MB |
| TTFB | 10% | < 200 ms | 200-600 ms | > 600 ms |
| DOMContentLoaded | 10% | < 1000 ms | 1000-3000 ms | > 3000 ms |

### Score Interpretation

| Score Range | Rating | Meaning |
|---|---|---|
| 85 - 100 | Excellent | Page is well-optimized; minor improvements possible |
| 70 - 84 | Good | Solid performance with some optimization opportunities |
| 50 - 69 | Needs Work | Significant inefficiencies; prioritize top weight categories |
| 30 - 49 | Poor | Major resource waste; likely impacts user experience |
| 0 - 29 | Critical | Severe inefficiency across multiple categories |

## Workflow

### Step 1: Start Coverage Tracking via CDP

Use `browser_run_code` to initialize both JavaScript and CSS coverage tracking. This must run **before** navigation.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    page.__cdpClient = client;

    // Enable profiler for JS coverage
    await client.send('Profiler.enable');
    await client.send('Profiler.startPreciseCoverage', {
      callCount: false,
      detailed: true
    });

    // Enable CSS coverage
    await client.send('CSS.enable');
    await client.send('CSS.startRuleUsageTracking');

    return 'JS and CSS coverage tracking started';
  }`
})
```

### Step 2: Navigate to the Target Page

```
browser_navigate({ url: "https://example.com/page" })
```

Wait for the page to be fully loaded. Use `networkidle` state for the most accurate measurement:

```javascript
browser_run_code({
  code: `async (page) => {
    await page.waitForLoadState('networkidle');
    return 'Page loaded (networkidle)';
  }`
})
```

### Step 3: Collect JS and CSS Coverage Data

Use `browser_run_code` to stop coverage tracking and retrieve the raw data.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = page.__cdpClient;

    // Collect JS coverage
    const jsCoverage = await client.send('Profiler.takePreciseCoverage');
    await client.send('Profiler.stopPreciseCoverage');
    await client.send('Profiler.disable');

    // Collect CSS coverage
    const cssCoverage = await client.send('CSS.stopRuleUsageTracking');

    // Calculate JS usage
    let totalJSBytes = 0;
    let usedJSBytes = 0;

    jsCoverage.result.forEach(script => {
      const scriptLength = script.end || 0;
      totalJSBytes += scriptLength;
      script.functions.forEach(fn => {
        fn.ranges.forEach(range => {
          if (range.count > 0) {
            usedJSBytes += (range.endOffset - range.startOffset);
          }
        });
      });
    });

    const jsUnusedPercent = totalJSBytes > 0
      ? Math.round(((totalJSBytes - usedJSBytes) / totalJSBytes) * 1000) / 10
      : 0;

    // Calculate CSS usage
    const totalCSSRules = cssCoverage.ruleUsage.length;
    const usedCSSRules = cssCoverage.ruleUsage.filter(r => r.used).length;
    const cssUnusedPercent = totalCSSRules > 0
      ? Math.round(((totalCSSRules - usedCSSRules) / totalCSSRules) * 1000) / 10
      : 0;

    // Store for later use
    await page.evaluate((data) => {
      window.__coverageData = data;
    }, {
      jsUnusedPercent,
      cssUnusedPercent,
      totalJSBytes,
      usedJSBytes,
      totalCSSRules,
      usedCSSRules
    });

    return {
      jsUnusedPercent,
      cssUnusedPercent,
      totalJSKB: Math.round(totalJSBytes / 1024),
      usedJSKB: Math.round(usedJSBytes / 1024),
      totalCSSRules,
      usedCSSRules
    };
  }`
})
```

### Step 4: Collect Timing and Resource Data

Use `browser_evaluate` to extract Resource Timing, Navigation Timing, and render-blocking resource information.

```javascript
browser_evaluate({
  function: `() => {
    // Navigation Timing
    const navEntry = performance.getEntriesByType('navigation')[0] || {};
    const ttfb = Math.round(navEntry.responseStart - navEntry.requestStart) || 0;
    const domContentLoaded = Math.round(navEntry.domContentLoadedEventEnd - navEntry.startTime) || 0;
    const loadEventEnd = Math.round(navEntry.loadEventEnd - navEntry.startTime) || 0;
    const domInteractive = Math.round(navEntry.domInteractive - navEntry.startTime) || 0;

    // Resource Timing
    const resources = performance.getEntriesByType('resource');
    let totalTransferBytes = 0;
    let renderBlockingCount = 0;
    const renderBlockingResources = [];

    resources.forEach(r => {
      totalTransferBytes += (r.transferSize || 0);

      // Check renderBlockingStatus (Chromium 105+)
      if (r.renderBlockingStatus === 'blocking') {
        renderBlockingCount++;
        renderBlockingResources.push({
          url: r.name.split('/').pop().split('?')[0].substring(0, 60),
          type: r.initiatorType,
          transferSizeKB: Math.round((r.transferSize || 0) / 1024 * 10) / 10,
          durationMs: Math.round(r.duration)
        });
      }
    });

    const totalTransferKB = Math.round(totalTransferBytes / 1024 * 10) / 10;

    return {
      timing: {
        ttfb: ttfb,
        domContentLoaded: domContentLoaded,
        domInteractive: domInteractive,
        loadEventEnd: loadEventEnd
      },
      transfer: {
        totalTransferKB: totalTransferKB,
        totalTransferMB: Math.round(totalTransferKB / 1024 * 100) / 100,
        resourceCount: resources.length
      },
      renderBlocking: {
        count: renderBlockingCount,
        resources: renderBlockingResources
      }
    };
  }`
})
```

### Step 5: Collect Network Request Count

Use `browser_network_requests` to get the total number of HTTP requests.

```
browser_network_requests({ includeStatic: true })
```

### Step 6: Compute the Composite Score

Use `browser_evaluate` to calculate the weighted composite score using all collected data. Pass the coverage data and resource data as needed.

```javascript
browser_evaluate({
  function: `() => {
    const coverage = window.__coverageData || {};

    // Navigation Timing
    const navEntry = performance.getEntriesByType('navigation')[0] || {};
    const ttfb = Math.round(navEntry.responseStart - navEntry.requestStart) || 0;
    const domContentLoaded = Math.round(navEntry.domContentLoadedEventEnd - navEntry.startTime) || 0;

    // Resources
    const resources = performance.getEntriesByType('resource');
    let totalTransferBytes = 0;
    let renderBlockingCount = 0;
    resources.forEach(r => {
      totalTransferBytes += (r.transferSize || 0);
      if (r.renderBlockingStatus === 'blocking') renderBlockingCount++;
    });
    // Include the document itself
    totalTransferBytes += (navEntry.transferSize || 0);
    const totalTransferKB = totalTransferBytes / 1024;

    // --- Scoring Functions ---
    function scoreCategory(value, goodMax, okMax) {
      if (value <= goodMax) return 10;
      if (value <= okMax) return 5;
      return 0;
    }

    // JS Unused % (lower is better)
    const jsScore = scoreCategory(coverage.jsUnusedPercent || 0, 30, 60);

    // CSS Unused % (lower is better)
    const cssScore = scoreCategory(coverage.cssUnusedPercent || 0, 40, 70);

    // Render-blocking count (lower is better)
    const blockingScore = scoreCategory(renderBlockingCount, 2, 5);

    // Total transfer KB (lower is better)
    const transferScore = scoreCategory(totalTransferKB, 500, 2048);

    // TTFB ms (lower is better)
    const ttfbScore = scoreCategory(ttfb, 200, 600);

    // DOMContentLoaded ms (lower is better)
    const dclScore = scoreCategory(domContentLoaded, 1000, 3000);

    // --- Weighted Composite ---
    const weights = {
      jsUnused: 0.25,
      cssUnused: 0.15,
      renderBlocking: 0.20,
      transferSize: 0.20,
      ttfb: 0.10,
      domContentLoaded: 0.10
    };

    const compositeScore = Math.round(
      (jsScore * weights.jsUnused +
       cssScore * weights.cssUnused +
       blockingScore * weights.renderBlocking +
       transferScore * weights.transferSize +
       ttfbScore * weights.ttfb +
       dclScore * weights.domContentLoaded) * 10
    );

    // Rating
    let rating;
    if (compositeScore >= 85) rating = 'Excellent';
    else if (compositeScore >= 70) rating = 'Good';
    else if (compositeScore >= 50) rating = 'Needs Work';
    else if (compositeScore >= 30) rating = 'Poor';
    else rating = 'Critical';

    return {
      compositeScore: compositeScore,
      rating: rating,
      breakdown: {
        jsUnused: {
          value: Math.round(coverage.jsUnusedPercent || 0) + '%',
          score: jsScore,
          weight: '25%',
          weighted: Math.round(jsScore * weights.jsUnused * 10)
        },
        cssUnused: {
          value: Math.round(coverage.cssUnusedPercent || 0) + '%',
          score: cssScore,
          weight: '15%',
          weighted: Math.round(cssScore * weights.cssUnused * 10)
        },
        renderBlocking: {
          value: renderBlockingCount + ' resources',
          score: blockingScore,
          weight: '20%',
          weighted: Math.round(blockingScore * weights.renderBlocking * 10)
        },
        transferSize: {
          value: Math.round(totalTransferKB) + ' KB',
          score: transferScore,
          weight: '20%',
          weighted: Math.round(transferScore * weights.transferSize * 10)
        },
        ttfb: {
          value: ttfb + ' ms',
          score: ttfbScore,
          weight: '10%',
          weighted: Math.round(ttfbScore * weights.ttfb * 10)
        },
        domContentLoaded: {
          value: domContentLoaded + ' ms',
          score: dclScore,
          weight: '10%',
          weighted: Math.round(dclScore * weights.domContentLoaded * 10)
        }
      },
      rawMetrics: {
        jsUnusedPercent: coverage.jsUnusedPercent,
        cssUnusedPercent: coverage.cssUnusedPercent,
        renderBlockingCount: renderBlockingCount,
        totalTransferKB: Math.round(totalTransferKB),
        ttfbMs: ttfb,
        domContentLoadedMs: domContentLoaded,
        totalJSKB: Math.round((coverage.totalJSBytes || 0) / 1024),
        totalCSSRules: coverage.totalCSSRules,
        totalResources: resources.length
      }
    };
  }`
})
```

## Interpreting Results

### Composite Score

| Score | Rating | Recommended Action |
|---|---|---|
| 85 - 100 | Excellent | No urgent action. Monitor for regressions. |
| 70 - 84 | Good | Review lowest-scoring categories for quick wins. |
| 50 - 69 | Needs Work | Focus on the two lowest-weighted-score categories first. |
| 30 - 49 | Poor | Multiple categories need attention. Start with the highest-weight Bad (0 pt) categories. |
| 0 - 29 | Critical | Fundamental efficiency problems. Likely needs architectural changes (code splitting, SSR, CDN). |

### Per-Category Deep Dive

**JS Unused % (Weight: 25%)**
- Good (< 30%): JS is well-tree-shaken or code-split
- Bad (> 60%): Large framework bundles shipping unused code; implement dynamic imports, lazy loading, or switch to lighter alternatives
- This is the highest-weight category because unused JS blocks the main thread during parse/compile

**CSS Unused % (Weight: 15%)**
- Good (< 40%): CSS is reasonably scoped
- Bad (> 70%): Full CSS framework loaded for a few classes; consider PurgeCSS, CSS modules, or utility-first with tree-shaking
- Lower weight than JS because unused CSS has less runtime impact

**Render-Blocking Resources (Weight: 20%)**
- Good (0-2): Minimal blocking; critical CSS likely inlined
- Bad (> 5): Too many synchronous CSS/JS files in `<head>`; add `async`/`defer` to scripts, use `media` attributes on non-critical CSS, inline critical CSS

**Total Transfer Size (Weight: 20%)**
- Good (< 500 KB): Lean page
- Bad (> 2 MB): Heavy page; audit images (WebP/AVIF), enable compression, lazy-load below-fold assets

**TTFB (Weight: 10%)**
- Good (< 200 ms): Fast server response
- Bad (> 600 ms): Slow backend or no CDN; investigate server-side caching, edge deployment, database queries

**DOMContentLoaded (Weight: 10%)**
- Good (< 1000 ms): DOM ready quickly
- Bad (> 3000 ms): Parser-blocking resources or heavy DOM construction; reduce synchronous scripts, defer non-critical work

### Report Format

Present results as a scorecard:

```
Page Efficiency Score: 72 / 100 (Good)

| Category              | Value        | Score | Weight | Weighted |
|-----------------------|--------------|-------|--------|----------|
| JS Unused %           | 42%          | 5     | 25%    | 12.5     |
| CSS Unused %          | 35%          | 10    | 15%    | 15.0     |
| Render-blocking       | 4 resources  | 5     | 20%    | 10.0     |
| Transfer Size         | 380 KB       | 10    | 20%    | 20.0     |
| TTFB                  | 450 ms       | 5     | 10%    | 5.0      |
| DOMContentLoaded      | 890 ms       | 10    | 10%    | 10.0     |

Top optimization opportunities:
1. JS Unused (42%): Split vendor bundle, lazy-load route components
2. Render-blocking (4): Defer analytics.js and fonts.css
```

## Limitations

- **Chromium-only**: This skill requires Chrome DevTools Protocol (CDP) for JavaScript and CSS coverage tracking. It will not work with Firefox or WebKit browser contexts in Playwright.
- **Single page measurement**: The score reflects a single page load. Different routes in an SPA will have different scores. For site-wide assessment, run on multiple representative pages.
- **Coverage accuracy**: JS/CSS coverage tracks what was executed/applied during the page load. Code needed for interactions (click handlers, hover styles) will appear "unused" unless those interactions are triggered before collecting coverage.
- **Transfer size vs. decoded size**: `transferSize` from Resource Timing reflects compressed (gzip/brotli) size over the wire. The actual decoded size may be 3-5x larger.
- **Cache impact**: If resources are cached, `transferSize` will be 0 for cached resources, making the transfer size score artificially good. Test with cache disabled for baseline measurement: `await page.context().clearCookies()` and use incognito context.
- **TTFB variability**: TTFB depends on network conditions, server load, and geography. Take multiple measurements and average, or test from a consistent location.
- **renderBlockingStatus**: The `renderBlockingStatus` property on Resource Timing entries is available in Chromium 105+. Older Chromium versions will report 0 render-blocking resources.
- **Score is relative**: The thresholds are based on general web performance best practices. Industry-specific pages (e-commerce, media, SaaS dashboards) may warrant adjusted thresholds.
