---
name: animation-profiler
description: >
  Profile CSS and JS animations: identify all running animations via CDP
  Animation domain, measure frame rates with requestAnimationFrame, detect
  expensive layout-triggering property animations vs compositor-only,
  audit will-change usage, and detect jank via long-animation-frame entries.
---

# Animation Profiler

Instrument a page to capture and analyze all CSS and JavaScript animations.
Uses the CDP Animation domain to enumerate active animations, PerformanceObserver
for long animation frames (jank detection), and requestAnimationFrame hooks for
frame timing analysis.

## When to Use

- Diagnosing janky animations or low frame rates.
- Finding animations that trigger layout/paint instead of using compositor-only properties.
- Auditing `will-change` usage (overuse causes memory waste, underuse causes jank).
- Profiling animation performance before a launch.
- Identifying which animations are running and their durations/timing functions.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP `Animation.enable`, `LayerTree.enable`, and `Rendering.setShowPaintRects`.
- Target page must have visible animations (CSS transitions, CSS animations, or JS-driven animations).

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

### Step 2 -- Enable CDP Animation Domain

Capture all animation start events via CDP.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    // Enable Animation domain
    await client.send('Animation.enable');

    const animations = [];
    client.on('Animation.animationStarted', (params) => {
      const anim = params.animation;
      animations.push({
        id: anim.id,
        name: anim.name || '(unnamed)',
        type: anim.type, // CSSTransition, CSSAnimation, WebAnimation
        duration: anim.source ? anim.source.duration : null,
        delay: anim.source ? anim.source.delay : null,
        iterationStart: anim.source ? anim.source.iterationStart : null,
        iterations: anim.source ? anim.source.iterations : null,
        easing: anim.source ? anim.source.easing : null,
        backendNodeId: anim.source ? anim.source.backendNodeId : null,
        keyframesRule: anim.source ? anim.source.keyframesRule : null,
        startTime: anim.startTime,
        playbackRate: anim.playbackRate,
        cssId: anim.cssId || null
      });
    });

    page.__animationData = animations;
    return 'Animation domain enabled, listening for animations';
  }`
})
```

### Step 3 -- Enable Layer Tree Inspection

Inspect compositor layers to understand which elements have their own layers.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('LayerTree.enable');

    const layers = [];
    client.on('LayerTree.layerTreeDidChange', (params) => {
      if (params.layers) {
        layers.length = 0;
        for (const layer of params.layers) {
          layers.push({
            layerId: layer.layerId,
            parentLayerId: layer.parentLayerId || null,
            backendNodeId: layer.backendNodeId || null,
            width: layer.width,
            height: layer.height,
            paintCount: layer.paintCount,
            drawsContent: layer.drawsContent,
            compositingReasons: layer.compositingReasonIds || []
          });
        }
      }
    });

    page.__layerData = layers;
    return 'LayerTree domain enabled';
  }`
})
```

### Step 4 -- Install Frame Timing Monitor

Hook `requestAnimationFrame` to measure actual frame durations and detect
dropped frames.

```javascript
browser_evaluate({
  function: `() => {
    window.__frameTiming = {
      frames: [],
      startTime: performance.now(),
      frameCount: 0,
      droppedFrames: 0,
      maxFrameTime: 0,
      running: true
    };

    let lastTimestamp = performance.now();

    function measureFrame(timestamp) {
      if (!window.__frameTiming.running) return;

      const delta = timestamp - lastTimestamp;
      window.__frameTiming.frameCount++;
      window.__frameTiming.frames.push(delta);

      // Keep only last 300 frames to limit memory
      if (window.__frameTiming.frames.length > 300) {
        window.__frameTiming.frames.shift();
      }

      // Frame longer than 33.33ms means we dropped below 30fps
      if (delta > 33.33) {
        window.__frameTiming.droppedFrames++;
      }
      if (delta > window.__frameTiming.maxFrameTime) {
        window.__frameTiming.maxFrameTime = delta;
      }

      lastTimestamp = timestamp;
      requestAnimationFrame(measureFrame);
    }

    requestAnimationFrame(measureFrame);
    return 'Frame timing monitor installed';
  }`
})
```

### Step 5 -- Install Long Animation Frame Observer

Use the `long-animation-frame` PerformanceObserver to detect jank.

```javascript
browser_evaluate({
  function: `() => {
    window.__longFrames = [];

    try {
      const observer = new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          window.__longFrames.push({
            startTime: entry.startTime,
            duration: entry.duration,
            blockingDuration: entry.blockingDuration,
            renderStart: entry.renderStart,
            styleAndLayoutStart: entry.styleAndLayoutStart,
            scripts: (entry.scripts || []).map(s => ({
              name: s.name,
              entryType: s.entryType,
              startTime: s.startTime,
              duration: s.duration,
              sourceURL: s.sourceURL,
              sourceFunctionName: s.sourceFunctionName,
              sourceCharPosition: s.sourceCharPosition
            }))
          });
        }
      });
      observer.observe({ type: 'long-animation-frame', buffered: true });
      return 'Long animation frame observer installed';
    } catch (e) {
      return 'long-animation-frame not supported: ' + e.message;
    }
  }`
})
```

### Step 6 -- Trigger Animations and Wait

Scroll the page and interact with elements to trigger animations. Wait for
a collection period.

```javascript
browser_evaluate({
  function: `() => {
    // Scroll to trigger scroll-based animations
    window.scrollBy(0, window.innerHeight);
    return 'Scrolled one viewport';
  }`
})
```

```
browser_wait_for({ time: 3 })
```

```javascript
browser_evaluate({
  function: `() => {
    window.scrollBy(0, window.innerHeight);
    return 'Scrolled another viewport';
  }`
})
```

```
browser_wait_for({ time: 3 })
```

Hover over interactive elements to trigger hover animations. Use
`browser_snapshot` to find elements, then `browser_click` or `browser_hover`.

```
browser_snapshot()
```

Use refs from the snapshot to hover over buttons, cards, or navigation items
that may have hover animations:

```
browser_hover({ ref: "<ref_from_snapshot>", element: "Interactive element" })
```

```
browser_wait_for({ time: 5 })
```

### Step 7 -- Detect Expensive Property Animations

Identify which CSS properties are being animated and classify them as
compositor-only (cheap) or layout/paint-triggering (expensive).

```javascript
browser_evaluate({
  function: `() => {
    const compositorOnly = new Set([
      'transform', 'opacity', 'filter', 'backdrop-filter',
      'offset-distance', 'offset-path', 'offset-rotate'
    ]);

    const paintOnly = new Set([
      'color', 'background-color', 'background-image', 'border-color',
      'outline-color', 'text-decoration-color', 'box-shadow', 'visibility'
    ]);

    // Layout-triggering = everything else that's animated

    const allAnimations = document.getAnimations();
    const analysis = [];

    for (const anim of allAnimations) {
      const effect = anim.effect;
      if (!effect || !effect.getKeyframes) continue;

      const target = effect.target;
      const keyframes = effect.getKeyframes();
      const animatedProps = new Set();

      for (const kf of keyframes) {
        for (const prop of Object.keys(kf)) {
          if (['offset', 'composite', 'easing', 'computedOffset'].includes(prop)) continue;
          animatedProps.add(prop);
        }
      }

      const propAnalysis = [];
      for (const prop of animatedProps) {
        const cssName = prop.replace(/([A-Z])/g, '-$1').toLowerCase();
        let cost;
        if (compositorOnly.has(cssName)) cost = 'compositor-only (cheap)';
        else if (paintOnly.has(cssName)) cost = 'paint-only (moderate)';
        else cost = 'layout-triggering (expensive)';
        propAnalysis.push({ property: cssName, cost: cost });
      }

      analysis.push({
        type: anim.constructor.name,
        animationName: anim.animationName || null,
        id: anim.id || null,
        playState: anim.playState,
        duration: effect.getTiming ? effect.getTiming().duration : null,
        iterations: effect.getTiming ? effect.getTiming().iterations : null,
        target: target ? target.tagName + (target.id ? '#' + target.id : '') + (target.className ? '.' + String(target.className).split(' ')[0] : '') : null,
        properties: propAnalysis,
        hasExpensiveProps: propAnalysis.some(p => p.cost.includes('layout') || p.cost.includes('paint'))
      });
    }

    return {
      totalAnimations: analysis.length,
      expensiveCount: analysis.filter(a => a.hasExpensiveProps).length,
      animations: analysis
    };
  }`
})
```

### Step 8 -- Audit will-change Usage

Check for `will-change` declarations: overuse wastes GPU memory, underuse on
animated elements causes jank.

```javascript
browser_evaluate({
  function: `() => {
    const allElements = document.querySelectorAll('*');
    const willChangeElements = [];
    const animatedWithoutWillChange = [];

    const activeAnimations = document.getAnimations();
    const animatedElements = new Set(activeAnimations.map(a => a.effect && a.effect.target).filter(Boolean));

    for (const el of allElements) {
      const style = getComputedStyle(el);
      const wc = style.willChange;

      if (wc && wc !== 'auto') {
        const rect = el.getBoundingClientRect();
        willChangeElements.push({
          element: el.tagName + (el.id ? '#' + el.id : '') + (el.className ? '.' + String(el.className).split(' ')[0] : ''),
          willChange: wc,
          isCurrentlyAnimated: animatedElements.has(el),
          size: Math.round(rect.width) + 'x' + Math.round(rect.height),
          issue: !animatedElements.has(el) ? 'will-change set but element is not animated (wasted GPU memory)' : null
        });
      }

      if (animatedElements.has(el) && (!wc || wc === 'auto')) {
        animatedWithoutWillChange.push({
          element: el.tagName + (el.id ? '#' + el.id : '') + (el.className ? '.' + String(el.className).split(' ')[0] : ''),
          animations: activeAnimations
            .filter(a => a.effect && a.effect.target === el)
            .map(a => a.animationName || a.constructor.name)
        });
      }
    }

    return {
      willChangeCount: willChangeElements.length,
      willChangeElements: willChangeElements,
      animatedWithoutWillChange: animatedWithoutWillChange.slice(0, 20),
      recommendation: willChangeElements.length > 10 ? 'EXCESSIVE: ' + willChangeElements.length + ' elements with will-change. This wastes GPU memory.' : 'OK'
    };
  }`
})
```

### Step 9 -- Harvest Frame Timing and Jank Data

```javascript
browser_evaluate({
  function: `() => {
    // Stop the frame monitor
    window.__frameTiming.running = false;

    const frames = window.__frameTiming.frames;
    const fps = frames.length > 0 ? 1000 / (frames.reduce((a,b) => a+b, 0) / frames.length) : 0;

    // Percentile calculation
    const sorted = [...frames].sort((a,b) => a - b);
    const p50 = sorted[Math.floor(sorted.length * 0.5)] || 0;
    const p95 = sorted[Math.floor(sorted.length * 0.95)] || 0;
    const p99 = sorted[Math.floor(sorted.length * 0.99)] || 0;

    return {
      frameTiming: {
        totalFrames: window.__frameTiming.frameCount,
        droppedFrames: window.__frameTiming.droppedFrames,
        droppedPct: Math.round((window.__frameTiming.droppedFrames / window.__frameTiming.frameCount) * 10000) / 100,
        avgFps: Math.round(fps * 10) / 10,
        maxFrameTime: Math.round(window.__frameTiming.maxFrameTime * 100) / 100,
        percentiles: {
          p50: Math.round(p50 * 100) / 100,
          p95: Math.round(p95 * 100) / 100,
          p99: Math.round(p99 * 100) / 100
        }
      },
      longAnimationFrames: {
        count: window.__longFrames.length,
        frames: window.__longFrames.slice(0, 10)
      }
    };
  }`
})
```

### Step 10 -- Harvest CDP Animation Data

```javascript
browser_run_code({
  code: `async (page) => {
    return {
      cdpAnimations: page.__animationData || [],
      layerCount: (page.__layerData || []).length,
      layers: (page.__layerData || []).filter(l => l.drawsContent).slice(0, 20)
    };
  }`
})
```

### Step 11 -- Optional: Enable Paint Rects Visualization

Enable paint flashing to visually identify areas being repainted.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Rendering.setShowPaintRects', { result: true });
    return 'Paint rects visualization enabled (green flashes on repainted areas)';
  }`
})
```

```
browser_wait_for({ time: 3 })
```

```
browser_take_screenshot({ type: "png", filename: "animation-paint-rects.png" })
```

Disable paint rects:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Rendering.setShowPaintRects', { result: false });
    return 'Paint rects visualization disabled';
  }`
})
```

## Interpreting Results

### Frame Rate Thresholds

| FPS | Rating | User Perception |
|-----|--------|----------------|
| 60 | Excellent | Buttery smooth |
| 45-59 | Good | Slightly noticeable on fast transitions |
| 30-44 | Poor | Visibly janky |
| < 30 | Critical | Unusable, stuttering |

### Property Cost Classification

| Cost Level | Properties | Impact |
|-----------|-----------|--------|
| Compositor-only | transform, opacity, filter | GPU-accelerated, no main thread |
| Paint-only | color, background-color, box-shadow | Repaint but no layout |
| Layout-triggering | width, height, top, left, margin, padding, font-size | Full layout recalculation |

### Report Format

```
## Animation Profiler -- <url>

### Frame Rate
- Average FPS: 57.2
- Dropped frames: 8/420 (1.9%)
- Max frame time: 42.1ms (p99: 28.3ms)

### Active Animations (6 total)
| # | Type | Name | Target | Duration | Properties | Cost |
|---|------|------|--------|----------|------------|------|
| 1 | CSSAnimation | fadeIn | DIV.hero | 500ms | opacity | compositor |
| 2 | CSSTransition | (unnamed) | BUTTON.cta | 200ms | background-color | paint |
| 3 | CSSAnimation | slideUp | DIV.card | 800ms | transform | compositor |
| 4 | CSSAnimation | expand | DIV.panel | 300ms | height, padding | LAYOUT |

### Expensive Animations (1 found)
1. DIV.panel "expand" animates height + padding (layout-triggering)
   Recommendation: use transform: scaleY() or max-height with overflow

### will-change Audit
- 3 elements with will-change
- 1 unnecessary: DIV.footer has will-change: transform but is not animated
- 2 animated elements missing will-change

### Long Animation Frames (jank)
- 2 long frames detected
  1. 68ms blocking at 2.3s (script: main.js:142 handleScroll)
  2. 52ms blocking at 5.1s (script: analytics.js:89 trackEvent)
```

### What to Look For

- **Layout-triggering animations**: animating `width`, `height`, `top`, `left`, `margin`, `padding`, or `font-size` causes expensive layout recalculations every frame. Use `transform` and `opacity` instead.
- **will-change on static elements**: `will-change` promotes elements to their own compositor layer, consuming GPU memory. Only use it on elements that will actually animate.
- **High dropped frame count (>5%)**: indicates jank. Check long animation frame data for the cause (heavy JS, forced synchronous layouts).
- **Long animation frames with script attribution**: the `sourceURL` and `sourceFunctionName` fields point directly to the JS function causing jank.

## Limitations

- **Chromium only**: CDP Animation domain, LayerTree domain, and `long-animation-frame` PerformanceObserver are Chromium-specific.
- **Web Animations API coverage**: `document.getAnimations()` captures CSS animations, CSS transitions, and Web Animations API animations. It does not capture JS-driven animations using `requestAnimationFrame` directly (those are detected via frame timing instead).
- **will-change audit is snapshot-based**: elements may have `will-change` added/removed dynamically via JS. The audit captures the state at the time of evaluation.
- **Frame timing via rAF**: the requestAnimationFrame-based frame measurement adds minimal overhead but is less precise than the browser's internal frame scheduler. Results are approximate.
- **Paint rects screenshot**: paint rect visualization (green flashes) requires capturing the screenshot at the exact moment of a repaint. The screenshot may not show active paint rects if repaints have settled.
