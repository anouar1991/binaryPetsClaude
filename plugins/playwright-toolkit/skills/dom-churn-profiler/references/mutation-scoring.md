# DOM Churn Scoring Reference

## Churn Score Calculation

The DOM churn score identifies which subtrees are responsible for excessive DOM mutations and correlates them with rendering jank.

### Per-Subtree Metrics

| Metric | Description | Weight |
|--------|-------------|--------|
| Mutation count | Total MutationObserver records | 30% |
| Adds + Removes | childList mutations (node additions/removals) | 30% |
| Attribute changes | Style/class/data attribute modifications | 20% |
| Jank correlation | Mutations during Long Animation Frames | 20% |

### Churn Rate Classification

| Rate (mutations/sec) | Classification | Typical Cause |
|----------------------|----------------|---------------|
| < 5 | Low | Normal interactivity |
| 5-50 | Moderate | Framework re-renders, animations |
| 50-200 | High | Excessive re-renders, live updates |
| > 200 | Critical | Render loop, infinite updates |

### Jank Correlation

A mutation is "jank-correlated" if it occurs during a Long Animation Frame (>50ms).

| Jank-correlated % | Classification |
|-------------------|----------------|
| < 10% | Mutations are lightweight |
| 10-40% | Some mutations cause jank |
| > 40% | Mutations are primary jank source |

## Target Identification Strategy

MutationObserver's `target` is the node where the mutation occurred. To make this useful, walk up the DOM tree to find the nearest identifiable ancestor:

1. Check `el.id` → use `#id`
2. Check `el.dataset.testid` → use `[data-testid="..."]`
3. Check `el.className` → use `TAG.firstClass`
4. Fallback: use `TAG` (e.g., `DIV`, `SPAN`)

## Long Animation Frame (LoAF) API

The `long-animation-frame` PerformanceObserver entry type provides:

| Field | Description |
|-------|-------------|
| duration | Total frame duration (>50ms triggers entry) |
| blockingDuration | Time the main thread was blocked |
| scripts[] | Array of script attributions |
| scripts[].sourceURL | Source file causing the long frame |
| scripts[].sourceFunctionName | Function name |
| scripts[].duration | Per-script duration |

**Browser support**: Chrome 123+ (March 2024). Feature detect:
```javascript
try {
  new PerformanceObserver(() => {}).observe({ type: 'long-animation-frame' });
} catch(e) {
  // Not supported, fall back to 'longtask'
}
```

## Interpreting Results

### Red Flags
- Single subtree responsible for >50% of all mutations
- Mutation rate >100/sec during idle (no user interaction)
- >50% of mutations jank-correlated
- Same element mutated >10 times per second (likely re-render loop)

### Common Causes
- **React/Vue re-renders**: State changes causing subtree reconciliation
- **CSS animations via JS**: requestAnimationFrame modifying styles
- **Live data updates**: WebSocket/SSE pushing frequent DOM updates
- **Scroll handlers**: Modifying DOM on every scroll event (should use IntersectionObserver)
