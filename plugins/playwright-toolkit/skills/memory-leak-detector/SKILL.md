---
name: memory-leak-detector
description: >
  Detect JavaScript memory leaks by measuring JS heap size and DOM node count
  across repeated interactions. Uses CDP HeapProfiler.collectGarbage for forced
  GC, analyzes growth trends, and reports leak rate per iteration.
---

# Memory Leak Detector

Measure JavaScript heap usage and DOM node count across repeated user
interactions to detect memory leaks. Forces garbage collection between
measurements via CDP, then analyzes whether growth is monotonic and computes
the leak rate per iteration.

## When to Use

- A page becomes sluggish after extended use (SPA with route changes).
- Opening and closing a modal/dialog repeatedly causes growing memory.
- A list or table component leaks detached DOM nodes on re-render.
- You need quantitative evidence of a memory leak before deep-diving with
  Chrome DevTools heap snapshots.

## Prerequisites

- **Playwright MCP server** connected and responding.
- **Chromium-based browser** required. Two Chromium-specific features are used:
  - `performance.memory` (non-standard, Chromium only) for JS heap metrics.
  - CDP `HeapProfiler.collectGarbage` via `browser_run_code` for forced GC.
- The skill degrades gracefully if `performance.memory` is unavailable (falls
  back to DOM node count only).

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

Wait for the page to stabilize:

```
browser_wait_for({ time: 3 })
```

### Step 2 -- Capture Baseline

Call `browser_run_code` to create a CDP session, force garbage collection, and
record baseline heap and DOM metrics.

```javascript
browser_run_code({
  code: `async (page) => {
    // Create CDP session for GC control
    const client = await page.context().newCDPSession(page);
    await client.send('HeapProfiler.collectGarbage');
    // Store client reference for later use
    // (We will create a new session each time since we cannot persist it)

    // Wait for GC to complete
    await page.waitForTimeout(500);

    // Measure baseline
    const baseline = await page.evaluate(() => {
      const result = {
        timestamp: performance.now(),
        domNodeCount: document.querySelectorAll('*').length,
        hasPerformanceMemory: !!performance.memory
      };
      if (performance.memory) {
        result.usedJSHeapSize = performance.memory.usedJSHeapSize;
        result.totalJSHeapSize = performance.memory.totalJSHeapSize;
        result.jsHeapSizeLimit = performance.memory.jsHeapSizeLimit;
      }
      return result;
    });

    await client.detach();
    return baseline;
  }`
})
```

Record the baseline values for comparison.

### Step 3 -- Define the Interaction to Repeat

Before looping, identify the interaction sequence that you suspect leaks
memory. Common patterns:

- **Route change loop**: navigate to a sub-page, then back.
- **Modal open/close**: open a dialog, interact with it, close it.
- **List manipulation**: add items, remove them, repeat.
- **Search/filter cycle**: type a query, clear it, repeat.

Take a `browser_snapshot` to identify the interactive elements and their refs.

### Step 4 -- Repeat Interaction N Times with Measurements

Call `browser_run_code` with the interaction loop. Replace the interaction
section with the actual steps for your use case.

```javascript
browser_run_code({
  code: `async (page) => {
    const iterations = 10;  // Adjust as needed
    const measurements = [];

    for (let i = 0; i < iterations; i++) {
      // ===== YOUR INTERACTION HERE =====
      // Example: open and close a modal
      // await page.click('button#open-modal');
      // await page.waitForTimeout(500);
      // await page.click('button.modal-close');
      // await page.waitForTimeout(500);

      // Example: navigate and return
      // await page.click('a[href="/details"]');
      // await page.waitForTimeout(1000);
      // await page.goBack();
      // await page.waitForTimeout(1000);
      // ===== END INTERACTION =====

      // Force GC
      const client = await page.context().newCDPSession(page);
      await client.send('HeapProfiler.collectGarbage');
      await page.waitForTimeout(500);
      await client.detach();

      // Measure
      const measurement = await page.evaluate((iteration) => {
        const result = {
          iteration: iteration + 1,
          timestamp: performance.now(),
          domNodeCount: document.querySelectorAll('*').length
        };
        if (performance.memory) {
          result.usedJSHeapSize = performance.memory.usedJSHeapSize;
          result.totalJSHeapSize = performance.memory.totalJSHeapSize;
        }
        return result;
      }, i);

      measurements.push(measurement);
    }

    return measurements;
  }`
})
```

### Step 5 -- Analyze Results

Call `browser_evaluate` to compute leak metrics from the measurements array.
Pass the baseline and measurements data collected from the previous steps.

```javascript
browser_evaluate({
  function: `() => {
    // Paste baseline and measurements from previous steps
    const baseline = __BASELINE__;      // Replace with actual baseline object
    const measurements = __MEASUREMENTS__; // Replace with actual measurements array

    const hasHeap = baseline.hasPerformanceMemory;
    const n = measurements.length;
    if (n < 2) return { error: 'Need at least 2 measurements' };

    // --- Heap analysis ---
    let heapAnalysis = null;
    if (hasHeap) {
      const heapSizes = [baseline.usedJSHeapSize, ...measurements.map(m => m.usedJSHeapSize)];
      const heapGrowths = [];
      let monotonic = true;
      for (let i = 1; i < heapSizes.length; i++) {
        const growth = heapSizes[i] - heapSizes[i - 1];
        heapGrowths.push(growth);
        if (growth < 0) monotonic = false;
      }
      const totalGrowth = heapSizes[heapSizes.length - 1] - heapSizes[0];
      const growthPercent = (totalGrowth / heapSizes[0]) * 100;
      const avgGrowthPerIteration = totalGrowth / n;

      heapAnalysis = {
        baselineBytes: heapSizes[0],
        finalBytes: heapSizes[heapSizes.length - 1],
        totalGrowthBytes: totalGrowth,
        totalGrowthMB: Math.round(totalGrowth / 1048576 * 100) / 100,
        growthPercent: Math.round(growthPercent * 100) / 100,
        avgGrowthPerIterationBytes: Math.round(avgGrowthPerIteration),
        avgGrowthPerIterationKB: Math.round(avgGrowthPerIteration / 1024 * 100) / 100,
        isMonotonic: monotonic,
        verdict: growthPercent > 10 ? 'PROBABLE_LEAK' :
                 growthPercent > 5 ? 'POSSIBLE_LEAK' : 'LIKELY_OK',
        perIterationGrowths: heapGrowths.map(g => Math.round(g / 1024 * 100) / 100 + ' KB')
      };
    }

    // --- DOM node analysis ---
    const domCounts = [baseline.domNodeCount, ...measurements.map(m => m.domNodeCount)];
    const domGrowths = [];
    let domMonotonic = true;
    for (let i = 1; i < domCounts.length; i++) {
      const growth = domCounts[i] - domCounts[i - 1];
      domGrowths.push(growth);
      if (growth < 0) domMonotonic = false;
    }
    const totalDomGrowth = domCounts[domCounts.length - 1] - domCounts[0];
    const avgDomGrowthPerIteration = totalDomGrowth / n;

    const domAnalysis = {
      baselineNodes: domCounts[0],
      finalNodes: domCounts[domCounts.length - 1],
      totalGrowth: totalDomGrowth,
      avgGrowthPerIteration: Math.round(avgDomGrowthPerIteration * 100) / 100,
      isMonotonic: domMonotonic,
      verdict: avgDomGrowthPerIteration > 10 ? 'DOM_LEAK' :
               avgDomGrowthPerIteration > 0 && domMonotonic ? 'POSSIBLE_DOM_LEAK' : 'LIKELY_OK',
      perIterationGrowths: domGrowths
    };

    return {
      iterations: n,
      heapAnalysis,
      domAnalysis,
      overallVerdict: (heapAnalysis && heapAnalysis.verdict === 'PROBABLE_LEAK') || domAnalysis.verdict === 'DOM_LEAK'
        ? 'MEMORY LEAK DETECTED'
        : (heapAnalysis && heapAnalysis.verdict === 'POSSIBLE_LEAK') || domAnalysis.verdict === 'POSSIBLE_DOM_LEAK'
        ? 'POSSIBLE MEMORY LEAK -- investigate further'
        : 'NO LEAK DETECTED'
    };
  }`
})
```

Alternatively, perform the analysis directly in your response by examining the
measurement data -- no `browser_evaluate` call required if you have the raw
numbers.

### Step 6 -- Check Console for Warnings

Call `browser_console_messages` to look for memory-related warnings:

```
browser_console_messages({ level: "warning" })
```

Look for messages about detached DOM nodes, exceeded memory limits, or
framework-specific warnings about unmounted component state updates.

## Interpreting Results

### Heap Growth Thresholds

| Growth (% over baseline) | Monotonic? | Verdict |
|--------------------------|------------|---------|
| < 5% | No | Likely OK -- normal GC fluctuation |
| < 5% | Yes | Monitor -- could be slow leak |
| 5% -- 10% | Yes | POSSIBLE LEAK -- run more iterations |
| > 10% | Yes | PROBABLE LEAK -- investigate |
| > 10% | No | Fluctuating but growing -- possible fragmentation |

### DOM Node Growth Thresholds

| Nodes/iteration | Verdict |
|-----------------|---------|
| 0 (stable) | No DOM leak |
| 1 -- 10 | Minor -- may be intentional caching |
| > 10 | DOM LEAK -- detached nodes accumulating |

### Common Leak Patterns

- **Event listeners not removed**: component mounts a `window.addEventListener` but never removes it. Each mount adds another listener holding a closure reference.
- **Timers not cleared**: `setInterval` or `setTimeout` created in a component that is unmounted without clearing the timer.
- **Detached DOM trees**: a reference to a removed DOM element is held in a JavaScript variable (e.g., a closure, a Map, or a module-level cache).
- **Growing Map/Set/Array**: an in-memory collection that adds entries on each interaction but never removes them.
- **Framework-specific**: React state updates on unmounted components, Vue watchers not stopped, Angular subscriptions not unsubscribed.

### Report Format

```
## Memory Leak Analysis

### Configuration
- Interaction: open/close settings modal
- Iterations: 10

### JS Heap
- Baseline: 12.4 MB
- Final: 15.8 MB
- Growth: 3.4 MB (27.4%) -- PROBABLE LEAK
- Monotonic: Yes
- Rate: ~340 KB/iteration

### DOM Nodes
- Baseline: 1,247
- Final: 1,389
- Growth: 142 nodes (14.2/iteration) -- DOM LEAK
- Monotonic: Yes

### Verdict: MEMORY LEAK DETECTED
Both JS heap and DOM nodes show monotonic growth across 10 iterations.
The modal likely attaches event listeners or creates DOM elements that
are not cleaned up on close.

### Recommended Next Steps
1. Take Chrome DevTools heap snapshots before/after interaction
2. Compare snapshots to find retained objects
3. Check modal component for missing cleanup in unmount/destroy lifecycle
```

## Limitations

- **Chromium only**: `performance.memory` and CDP `HeapProfiler.collectGarbage` are Chromium-specific. Firefox and Safari do not expose JS heap size to web pages and do not support this CDP command. On non-Chromium browsers, only DOM node count analysis is available.
- **`performance.memory` precision**: the `usedJSHeapSize` value is not updated on every call. Chromium updates it periodically, so two rapid calls may return the same value. The forced GC + 500ms wait mitigates this.
- **GC is not deterministic**: even after `HeapProfiler.collectGarbage`, some objects may not be collected immediately (weak references, invoke finalizer queue). Small fluctuations (< 5%) are normal.
- **DOM node count is a proxy**: `document.querySelectorAll('*').length` counts only elements in the document. Detached DOM trees (elements removed from the document but still referenced by JS) are NOT counted. For detached node detection, a full heap snapshot comparison is needed.
- **Single-page scope**: this skill measures within a single page context. Cross-origin iframes and service workers have separate heaps that are not measured.
- **Interaction fidelity**: the repeated interaction in `browser_run_code` may not perfectly replicate real user behavior. Complex interactions (drag-and-drop, hover menus) may need careful adaptation.
