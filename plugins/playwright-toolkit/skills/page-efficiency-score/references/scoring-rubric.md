# Page Efficiency Scoring Rubric

## Composite Score (0-100)

The page efficiency score is a weighted composite of 6 categories. Each category scores 0, 5, or 10 points, then is multiplied by its weight.

**Formula**: `score = sum(category_score * weight) / sum(weights) * 10`

## Category Breakdown

### JavaScript Unused % (Weight: 25%)

Measured via CDP Profiler.startPreciseCoverage.

| Score | Threshold | Meaning |
|-------|-----------|---------|
| 10 | < 20% unused | Lean JS bundles, good tree-shaking |
| 5 | 20-50% unused | Room for code splitting |
| 0 | > 50% unused | Major dead code problem |

### CSS Unused % (Weight: 15%)

Measured via CDP CSS.startRuleUsageTracking.

| Score | Threshold | Meaning |
|-------|-----------|---------|
| 10 | < 30% unused | CSS is well-scoped |
| 5 | 30-60% unused | Consider purging unused rules |
| 0 | > 60% unused | Likely shipping entire framework CSS |

### Render-Blocking Resources (Weight: 20%)

Counted from Resource Timing entries where renderBlockingStatus = 'blocking'.

| Score | Threshold | Meaning |
|-------|-----------|---------|
| 10 | 0 blocking | All resources are async/deferred |
| 5 | 1-2 blocking | Minor render blocking |
| 0 | 3+ blocking | Significant render delay |

### Total Transfer Size (Weight: 20%)

Sum of transferSize from all Resource Timing entries.

| Score | Threshold | Meaning |
|-------|-----------|---------|
| 10 | < 500 KB | Lightweight page |
| 5 | 500 KB - 2 MB | Average size |
| 0 | > 2 MB | Heavy page |

### Time to First Byte (Weight: 10%)

From Navigation Timing: responseStart - requestStart.

| Score | Threshold | Meaning |
|-------|-----------|---------|
| 10 | < 200ms | Fast server response |
| 5 | 200-600ms | Acceptable |
| 0 | > 600ms | Slow server or CDN issue |

### DOM Content Loaded (Weight: 10%)

From Navigation Timing: domContentLoadedEventEnd.

| Score | Threshold | Meaning |
|-------|-----------|---------|
| 10 | < 1000ms | Fast DOM ready |
| 5 | 1000-3000ms | Moderate |
| 0 | > 3000ms | Slow parsing/execution |

## Example Score Calculation

```
JS unused: 35% → score 5, weighted: 5 * 0.25 = 1.25
CSS unused: 45% → score 5, weighted: 5 * 0.15 = 0.75
Render-blocking: 1 → score 5, weighted: 5 * 0.20 = 1.00
Transfer: 800KB → score 5, weighted: 5 * 0.20 = 1.00
TTFB: 150ms → score 10, weighted: 10 * 0.10 = 1.00
DCL: 1500ms → score 5, weighted: 5 * 0.10 = 0.50

Total weighted = 5.50 / 10 * 100 = 55/100
```

## Grade Scale

| Score | Grade | Action |
|-------|-------|--------|
| 90-100 | A | Excellent - minor optimizations only |
| 75-89 | B | Good - address largest category gap |
| 50-74 | C | Needs work - multiple categories need attention |
| 25-49 | D | Poor - significant optimization needed |
| 0-24 | F | Critical - fundamental architecture issues |
