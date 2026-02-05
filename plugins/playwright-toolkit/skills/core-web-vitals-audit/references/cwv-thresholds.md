# Core Web Vitals Thresholds Reference

## Current Metrics (2024+)

### Largest Contentful Paint (LCP)
Measures perceived load speed — when the largest content element becomes visible.

| Rating | Threshold | Score |
|--------|-----------|-------|
| Good | <= 2500ms | Pass |
| Needs Improvement | <= 4000ms | Warning |
| Poor | > 4000ms | Fail |

**Common LCP elements**: Hero images, heading text, video poster images, background images with text overlay.

**Attribution data available**: element tag, id, className, url (for images), size, loadTime, renderTime.

### Interaction to Next Paint (INP)
Measures responsiveness — the latency of user interactions (replaced FID in March 2024).

| Rating | Threshold | Score |
|--------|-----------|-------|
| Good | <= 200ms | Pass |
| Needs Improvement | <= 500ms | Warning |
| Poor | > 500ms | Fail |

**INP breakdown phases**:
- `inputDelay` = processingStart - startTime (time waiting for main thread)
- `processingTime` = processingEnd - processingStart (event handler execution)
- `presentationDelay` = (startTime + duration) - processingEnd (rendering after handler)

INP is calculated as the p98 interaction duration across all interactions in a session.

### Cumulative Layout Shift (CLS)
Measures visual stability — unexpected layout shifts during the page lifecycle.

| Rating | Threshold | Score |
|--------|-----------|-------|
| Good | <= 0.1 | Pass |
| Needs Improvement | <= 0.25 | Warning |
| Poor | > 0.25 | Fail |

**CLS calculation**: Sum of individual layout shift scores, where each score = impact fraction * distance fraction. Only unexpected shifts count (hadRecentInput = false).

**Attribution data available**: source elements with previousRect and currentRect.

## Viewport Sizes for Testing

| Device | Width | Height | Category |
|--------|-------|--------|----------|
| Mobile | 375 | 667 | Small |
| Tablet | 768 | 1024 | Medium |
| Desktop | 1440 | 900 | Large |

## PerformanceObserver Entry Types

| Entry Type | API | What It Measures |
|------------|-----|-----------------|
| `largest-contentful-paint` | LCP | Largest visible content element timing |
| `layout-shift` | CLS | Unexpected element position changes |
| `event` | INP | Interaction latency with phase breakdown |
| `paint` | FP/FCP | First paint and first contentful paint |
| `long-animation-frame` | LoAF | Frames that took >50ms to render |
| `navigation` | Nav Timing | Full page load lifecycle |
| `resource` | Resource Timing | Individual resource load metrics |
