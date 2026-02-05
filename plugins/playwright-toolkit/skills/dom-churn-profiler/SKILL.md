---
name: dom-churn-profiler
description: >
  Identify which DOM subtrees cause excessive mutations and jank by injecting
  MutationObserver and Long Animation Frame instrumentation. Correlates DOM
  churn with long frames to pinpoint the source of visual instability.
---

# DOM Churn Profiler

Inject a MutationObserver and a Long Animation Frame PerformanceObserver into
the page to record every DOM mutation with timestamps and target
identification. After user interactions, harvest and correlate the data to
answer: "which DOM subtree causes jank?"

## When to Use

- A page feels janky but you don't know which component is thrashing the DOM.
- React/Vue/Svelte app has excessive re-renders causing dropped frames.
- You want to identify which subtree (by id, data-testid, or class) is being
  mutated most frequently.
- You need to correlate DOM mutations with long animation frames to prove
  causality between DOM churn and jank.

## Prerequisites

- **Playwright MCP server** connected and responding.
- **Chromium-based browser** required for `long-animation-frame` PerformanceObserver entries (Chrome 123+). The MutationObserver portion works in all browsers.
- Target page must be reachable from the browser instance.

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

### Step 2 -- Inject MutationObserver and Long Animation Frame Observer

Call `browser_evaluate` to install both observers before any interactions.

```javascript
browser_evaluate({
  function: `() => {
    window.__domChurn = {
      mutations: [],
      longFrames: [],
      startTime: performance.now()
    };

    // --- Helper: walk up DOM to find identifiable ancestor ---
    function identify(node) {
      let el = node.nodeType === 1 ? node : node.parentElement;
      const path = [];
      while (el && el !== document.body && path.length < 5) {
        let label = el.tagName.toLowerCase();
        if (el.id) {
          label += '#' + el.id;
          path.unshift(label);
          break;
        }
        if (el.getAttribute('data-testid')) {
          label += '[data-testid="' + el.getAttribute('data-testid') + '"]';
          path.unshift(label);
          break;
        }
        if (el.className && typeof el.className === 'string') {
          label += '.' + el.className.trim().split(/\\s+/)[0];
        }
        path.unshift(label);
        el = el.parentElement;
      }
      return path.join(' > ') || 'unknown';
    }

    // --- MutationObserver ---
    const observer = new MutationObserver((records) => {
      const ts = performance.now();
      for (const record of records) {
        window.__domChurn.mutations.push({
          timestamp: ts,
          type: record.type,
          target: identify(record.target),
          addedNodes: record.addedNodes.length,
          removedNodes: record.removedNodes.length,
          attributeName: record.attributeName || null
        });
      }
    });

    observer.observe(document.body, {
      childList: true,
      attributes: true,
      characterData: true,
      subtree: true
    });

    window.__domChurn._observer = observer;

    // --- Long Animation Frame Observer ---
    try {
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          const frame = {
            startTime: entry.startTime,
            duration: entry.duration,
            blockingDuration: entry.blockingDuration,
            renderStart: entry.renderStart,
            styleAndLayoutStart: entry.styleAndLayoutStart,
            scripts: []
          };
          if (entry.scripts) {
            for (const script of entry.scripts) {
              frame.scripts.push({
                invoker: script.invoker || null,
                invokerType: script.invokerType || null,
                sourceURL: script.sourceURL || null,
                sourceFunctionName: script.sourceFunctionName || null,
                sourceCharPosition: script.sourceCharPosition || null,
                executionStart: script.executionStart,
                duration: script.duration,
                forcedStyleAndLayoutDuration: script.forcedStyleAndLayoutDuration || 0
              });
            }
          }
          window.__domChurn.longFrames.push(frame);
        }
      }).observe({ type: 'long-animation-frame', buffered: true });
    } catch (e) {
      window.__domChurn._loafError = e.message;
    }

    return 'DOM Churn observers installed';
  }`
})
```

### Step 3 -- Perform Interactions

Drive the interactions that you suspect cause DOM churn. Use a combination of:

- `browser_click` -- click on tabs, accordions, menus, buttons.
- `browser_type` -- type in search or filter fields that trigger live updates.
- `browser_press_key` -- press Escape, Enter, arrow keys.
- `browser_evaluate` with `window.scrollBy()` -- scroll the page.
- `browser_wait_for` -- wait between interactions so mutations can accumulate.

Take a `browser_snapshot` first to identify interactive elements and their
refs.

**Example interaction sequence:**

```
browser_snapshot()
-- identify a tab control, click it --
browser_click({ ref: "<tab_ref>", element: "Tab button" })
browser_wait_for({ time: 2 })
browser_click({ ref: "<another_tab_ref>", element: "Another tab" })
browser_wait_for({ time: 2 })
```

### Step 4 -- Harvest and Analyze

Call `browser_evaluate` to process the collected data.

```javascript
browser_evaluate({
  function: `() => {
    const data = window.__domChurn;
    const elapsed = (performance.now() - data.startTime) / 1000;

    // --- Group mutations by target subtree ---
    const subtreeMap = {};
    for (const m of data.mutations) {
      const key = m.target;
      if (!subtreeMap[key]) {
        subtreeMap[key] = { count: 0, added: 0, removed: 0, attributes: 0, types: {} };
      }
      subtreeMap[key].count++;
      subtreeMap[key].added += m.addedNodes;
      subtreeMap[key].removed += m.removedNodes;
      if (m.type === 'attributes') subtreeMap[key].attributes++;
      subtreeMap[key].types[m.type] = (subtreeMap[key].types[m.type] || 0) + 1;
    }

    // Sort by mutation count descending
    const topSubtrees = Object.entries(subtreeMap)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 15)
      .map(([target, stats]) => ({ target, ...stats }));

    // --- Correlate mutations with long animation frames ---
    const correlations = [];
    for (const frame of data.longFrames) {
      const frameStart = frame.startTime;
      const frameEnd = frame.startTime + frame.duration;
      const overlapping = data.mutations.filter(
        m => m.timestamp >= frameStart && m.timestamp <= frameEnd
      );
      if (overlapping.length > 0) {
        // Find dominant subtree during this frame
        const subtreeCounts = {};
        for (const m of overlapping) {
          subtreeCounts[m.target] = (subtreeCounts[m.target] || 0) + 1;
        }
        const dominant = Object.entries(subtreeCounts).sort((a, b) => b[1] - a[1])[0];
        correlations.push({
          frameDuration: frame.duration,
          blockingDuration: frame.blockingDuration,
          mutationsDuringFrame: overlapping.length,
          dominantSubtree: dominant[0],
          dominantCount: dominant[1],
          scripts: frame.scripts.slice(0, 3)
        });
      }
    }
    correlations.sort((a, b) => b.mutationsDuringFrame - a.mutationsDuringFrame);

    // --- Disconnect observer ---
    if (data._observer) data._observer.disconnect();

    return {
      summary: {
        totalMutations: data.mutations.length,
        elapsedSeconds: Math.round(elapsed * 100) / 100,
        mutationsPerSecond: Math.round(data.mutations.length / elapsed * 100) / 100,
        longAnimationFrames: data.longFrames.length,
        loafSupported: !data._loafError
      },
      topChurningSubtrees: topSubtrees,
      longFrameCorrelations: correlations.slice(0, 10)
    };
  }`
})
```

### Step 5 -- Take a Screenshot (Optional)

If a top-churning subtree is identifiable, highlight it and screenshot:

```javascript
browser_evaluate({
  function: `() => {
    // Attempt to highlight the top churning element
    const topTarget = '<paste_top_subtree_selector_here>';
    const parts = topTarget.split(' > ');
    // Try the most specific part (last segment)
    const last = parts[parts.length - 1];
    let el = null;
    if (last.includes('#')) {
      const id = last.split('#')[1].split('.')[0];
      el = document.getElementById(id);
    } else if (last.includes('[data-testid=')) {
      const testid = last.match(/data-testid="([^"]+)"/);
      if (testid) el = document.querySelector('[data-testid="' + testid[1] + '"]');
    }
    if (el) {
      el.style.outline = '4px solid orange';
      el.style.outlineOffset = '2px';
      el.scrollIntoView({ block: 'center' });
      return 'Highlighted: ' + el.tagName + '#' + el.id;
    }
    return 'Could not locate element for highlighting';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "dom-churn-hotspot.png" })
```

## Interpreting Results

### Key Metrics

| Metric | Healthy | Concerning | Problematic |
|--------|---------|------------|-------------|
| Mutations/second (idle) | < 5 | 5 -- 50 | > 50 |
| Mutations/second (active) | < 50 | 50 -- 200 | > 200 |
| Long animation frames | 0 | 1 -- 5 | > 5 |
| Mutations during a long frame | 0 | 1 -- 20 | > 20 |

### What to Look For

- **A single subtree dominates mutation count**: that component is re-rendering excessively. In React, add `React.memo` or check for unstable props/context. In Vue, check reactive dependency granularity.
- **Attribute mutations on the same element**: often CSS class toggling for animations. Consider using CSS transitions/animations instead of JS-driven class changes.
- **High addedNodes + removedNodes on a list container**: the entire list is being replaced on each update. Use keyed list rendering or virtualization.
- **Long animation frame with script attribution**: the `sourceURL` and `sourceFunctionName` fields point directly to the code causing the long frame. Check for forced reflows (`forcedStyleAndLayoutDuration > 0`).
- **Mutations correlate with long frames**: this is the smoking gun. The dominant subtree during a long frame is the component causing jank. Optimize that component's render path.

### Report Format

```
## DOM Churn Profile

### Summary
- Total mutations: 847
- Duration: 12.5s
- Rate: 67.8 mutations/sec (CONCERNING)
- Long animation frames: 3

### Top Churning Subtrees
| Rank | Subtree | Mutations | Added | Removed | Attributes |
|------|---------|-----------|-------|---------|------------|
| 1 | div#live-feed > ul.messages | 412 | 206 | 206 | 0 |
| 2 | div.sidebar > span.counter | 198 | 0 | 0 | 198 |
| 3 | div#chart-container | 85 | 42 | 42 | 1 |

### Jank Correlations
1. Long frame 156ms -- 312 mutations in div#live-feed > ul.messages
   Script: app.bundle.js:1247 renderMessages()
   Forced layout: 45ms
```

## Limitations

- **`long-animation-frame` is Chromium-only** (Chrome 123+). Firefox and Safari will not produce Long Animation Frame entries. The MutationObserver portion works everywhere.
- **MutationObserver overhead**: observing the entire `document.body` with `subtree: true` adds overhead. On extremely large or mutation-heavy pages, the observer itself may contribute to jank. For production profiling, scope the observer to a suspected subtree.
- **Target identification is heuristic**: the `identify()` function walks up the DOM looking for `id`, `data-testid`, or `className`. If the page lacks these attributes, targets will show as generic tag paths.
- **No React/Vue component names**: the profiler works at the DOM level. It cannot attribute mutations to specific framework components without framework-specific devtools integration.
- **Timing resolution**: `performance.now()` timestamps in the MutationObserver callback represent when the callback ran, not precisely when the mutation occurred. Multiple mutations batched into one microtask share the same timestamp.
