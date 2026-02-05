# Memory Leak Detection Thresholds

## Heap Growth Analysis

### Classification

| Growth Pattern | Classification | Action |
|----------------|---------------|--------|
| Monotonic increase every iteration | **Probable leak** | Investigate immediately |
| Growth that plateaus after N iterations | **Cache warmup** | Normal behavior |
| Flat with occasional spikes | **GC pressure** | Monitor but likely OK |
| Decreasing trend | **No leak** | Healthy GC |

### Heap Size Thresholds

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Growth per iteration | < 50 KB | 50-500 KB | > 500 KB |
| Total growth over 10 iterations | < 2% | 2-10% | > 10% |
| Monotonic growth count (of 10) | < 3 | 3-7 | > 7 |

### DOM Node Thresholds

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Nodes added per iteration | < 5 | 5-50 | > 50 |
| Net node growth over 10 iterations | 0 | 1-100 | > 100 |
| Detached DOM trees | 0 | 1-5 | > 5 |

## Common Leak Patterns

### 1. Event Listener Leaks
- Symptom: Heap grows, DOM nodes stable
- Cause: addEventListener without removeEventListener
- Detection: Check `getEventListeners()` count growth (CDP only)

### 2. Detached DOM Trees
- Symptom: DOM node count grows, elements not in document
- Cause: References to removed DOM nodes in closures/arrays
- Detection: Compare querySelectorAll('*').length with expected count

### 3. Closure Leaks
- Symptom: Heap grows, no DOM growth
- Cause: Closures capturing large objects that are never released
- Detection: Heap snapshot comparison (advanced)

### 4. Timer Leaks
- Symptom: Steady growth, continues even when idle
- Cause: setInterval/setTimeout without clearInterval/clearTimeout
- Detection: Growth continues without user interaction

## Measurement Protocol

1. **Baseline**: Navigate, wait for idle, force GC, measure
2. **Iterations**: Perform action, wait 500ms, force GC, wait 500ms, measure
3. **Analysis**: Compute trend line across all measurements
4. **Confidence**: At least 10 iterations for reliable trend detection

### Forcing Garbage Collection

Via CDP: `HeapProfiler.collectGarbage`

This is more reliable than `gc()` which requires --expose-gc flag.

### performance.memory Fields

| Field | Description |
|-------|-------------|
| usedJSHeapSize | Current JS heap usage |
| totalJSHeapSize | Total allocated heap |
| jsHeapSizeLimit | Maximum heap size |

Note: `performance.memory` is Chromium-only and may require `--enable-precise-memory-info` for accurate readings. In MCP Playwright, this is typically available by default in Chromium.
