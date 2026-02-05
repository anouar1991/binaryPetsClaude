---
name: interaction-replay-debugger
description: >
  Capture and analyze every user interaction with full Event Timing API
  breakdown (inputDelay, processingTime, presentationDelay). Correlate with
  Long Animation Frames and console errors to produce a ranked report of the
  slowest interactions and compute INP.
---

# Interaction Replay Debugger

Install an Event Timing API PerformanceObserver with `durationThreshold: 0` to
capture every interaction event. After performing a series of clicks, key
presses, and text inputs, harvest entries with full per-phase timing
breakdowns. Correlate slow interactions with Long Animation Frames and console
errors to diagnose responsiveness issues.

## When to Use

- A page feels unresponsive on specific interactions but you don't know which
  phase (input delay, processing, or presentation) is the bottleneck.
- You need to compute the page's INP (Interaction to Next Paint) value.
- You want to identify which event handler is slow and whether the slowness is
  in JavaScript processing or in rendering after the handler completes.
- You need to correlate slow interactions with console errors that may indicate
  thrown exceptions in event handlers.

## Prerequisites

- **Playwright MCP server** connected and responding.
- **Chromium-based browser** required for:
  - Event Timing API with `interactionId` (Chrome 96+).
  - `durationThreshold: 0` to capture all interactions, not just slow ones.
  - Long Animation Frame entries with script attribution (Chrome 123+).
- Target page must be reachable from the browser instance.

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

### Step 2 -- Install Event Timing and Long Animation Frame Observers

Call `browser_evaluate` to set up instrumentation before any interactions.

```javascript
browser_evaluate({
  function: `() => {
    window.__interactions = {
      events: [],
      longFrames: []
    };

    // --- Event Timing Observer (captures ALL interactions) ---
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        window.__interactions.events.push({
          name: entry.name,
          entryType: entry.entryType,
          startTime: entry.startTime,
          duration: entry.duration,
          processingStart: entry.processingStart,
          processingEnd: entry.processingEnd,
          interactionId: entry.interactionId,
          // Phase breakdowns
          inputDelay: entry.processingStart - entry.startTime,
          processingTime: entry.processingEnd - entry.processingStart,
          presentationDelay: entry.startTime + entry.duration - entry.processingEnd,
          // Target identification
          target: entry.target ? (() => {
            const el = entry.target;
            let label = el.tagName;
            if (el.id) label += '#' + el.id;
            else if (el.getAttribute && el.getAttribute('data-testid')) label += '[data-testid="' + el.getAttribute('data-testid') + '"]';
            else if (el.className && typeof el.className === 'string') label += '.' + el.className.trim().split(/\\s+/)[0];
            if (el.textContent && el.textContent.length < 40) label += ' ("' + el.textContent.trim().substring(0, 30) + '")';
            return label;
          })() : null
        });
      }
    }).observe({ type: 'event', durationThreshold: 0, buffered: true });

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
          window.__interactions.longFrames.push(frame);
        }
      }).observe({ type: 'long-animation-frame', buffered: true });
    } catch (e) {
      window.__interactions._loafError = e.message;
    }

    return 'Interaction observers installed (durationThreshold: 0)';
  }`
})
```

### Step 3 -- Perform Interactions

Take a `browser_snapshot` to identify interactive elements and their refs.
Then drive a variety of interactions:

**Click interactions:**
```
browser_click({ ref: "<button_ref>", element: "Submit button" })
browser_wait_for({ time: 1 })
```

**Text input interactions:**
```
browser_type({ ref: "<input_ref>", text: "search query", element: "Search input" })
browser_wait_for({ time: 1 })
```

**Key press interactions:**
```
browser_press_key({ key: "Enter" })
browser_wait_for({ time: 1 })
browser_press_key({ key: "Escape" })
browser_wait_for({ time: 1 })
```

**Scroll interaction (via evaluate):**
```javascript
browser_evaluate({
  function: `() => { window.scrollBy(0, 300); return 'scrolled'; }`
})
```

Allow a brief wait between interactions so the browser has time to process
and the observers can record entries:

```
browser_wait_for({ time: 1 })
```

### Step 4 -- Capture Console Messages

Call `browser_console_messages` to check for errors that occurred during
interactions:

```
browser_console_messages({ level: "error" })
```

Save these for correlation with slow interactions.

### Step 5 -- Harvest and Analyze

Call `browser_evaluate` to process the collected interaction data.

```javascript
browser_evaluate({
  function: `() => {
    const data = window.__interactions;

    // --- Group events by interactionId ---
    // A single user interaction (e.g., click) may produce multiple events
    // (pointerdown, pointerup, click). Group them by interactionId.
    const interactionMap = {};
    for (const evt of data.events) {
      if (evt.interactionId && evt.interactionId > 0) {
        if (!interactionMap[evt.interactionId]) {
          interactionMap[evt.interactionId] = [];
        }
        interactionMap[evt.interactionId].push(evt);
      }
    }

    // For each interaction, take the event with the longest duration
    // (this is how INP is computed -- per interaction, not per event)
    const interactions = Object.entries(interactionMap).map(([id, events]) => {
      const longest = events.reduce((a, b) => a.duration > b.duration ? a : b);
      return {
        interactionId: Number(id),
        dominantEvent: longest.name,
        duration: longest.duration,
        inputDelay: Math.round(longest.inputDelay * 100) / 100,
        processingTime: Math.round(longest.processingTime * 100) / 100,
        presentationDelay: Math.round(longest.presentationDelay * 100) / 100,
        target: longest.target,
        startTime: longest.startTime,
        allEvents: events.map(e => e.name)
      };
    });

    // Sort by duration descending
    interactions.sort((a, b) => b.duration - a.duration);

    // --- Compute INP (p98 of interaction durations) ---
    const durations = interactions.map(i => i.duration).sort((a, b) => a - b);
    let inp = 0;
    if (durations.length > 0) {
      const p98Index = Math.min(Math.ceil(durations.length * 0.98) - 1, durations.length - 1);
      inp = durations[p98Index];
    }

    // --- Correlate with Long Animation Frames ---
    const correlations = [];
    for (const interaction of interactions.slice(0, 10)) {
      const iStart = interaction.startTime;
      const iEnd = interaction.startTime + interaction.duration;
      const overlapping = data.longFrames.filter(f =>
        f.startTime < iEnd && (f.startTime + f.duration) > iStart
      );
      if (overlapping.length > 0) {
        correlations.push({
          interactionId: interaction.interactionId,
          event: interaction.dominantEvent,
          target: interaction.target,
          duration: interaction.duration,
          longFrames: overlapping.map(f => ({
            duration: f.duration,
            blockingDuration: f.blockingDuration,
            scripts: f.scripts.map(s => ({
              source: s.sourceURL ? s.sourceURL.split('/').pop() + ':' + (s.sourceCharPosition || '?') : 'unknown',
              function: s.sourceFunctionName || 'anonymous',
              duration: s.duration,
              forcedLayout: s.forcedStyleAndLayoutDuration
            }))
          }))
        });
      }
    }

    // --- Phase analysis: what is the dominant bottleneck? ---
    const avgPhases = interactions.reduce((acc, i) => {
      acc.inputDelay += i.inputDelay;
      acc.processingTime += i.processingTime;
      acc.presentationDelay += i.presentationDelay;
      return acc;
    }, { inputDelay: 0, processingTime: 0, presentationDelay: 0 });

    const count = interactions.length || 1;
    const phaseAvg = {
      inputDelay: Math.round(avgPhases.inputDelay / count * 100) / 100,
      processingTime: Math.round(avgPhases.processingTime / count * 100) / 100,
      presentationDelay: Math.round(avgPhases.presentationDelay / count * 100) / 100
    };

    const dominantPhase = phaseAvg.inputDelay >= phaseAvg.processingTime && phaseAvg.inputDelay >= phaseAvg.presentationDelay
      ? 'inputDelay'
      : phaseAvg.processingTime >= phaseAvg.presentationDelay
        ? 'processingTime'
        : 'presentationDelay';

    return {
      summary: {
        totalInteractions: interactions.length,
        totalEvents: data.events.length,
        inp: inp,
        inpRating: inp < 200 ? 'GOOD' : inp < 500 ? 'NEEDS IMPROVEMENT' : 'POOR',
        longAnimationFrames: data.longFrames.length,
        loafSupported: !data._loafError,
        dominantBottleneck: dominantPhase,
        averagePhases: phaseAvg
      },
      slowest10: interactions.slice(0, 10),
      longFrameCorrelations: correlations,
      allInteractionDurations: interactions.map(i => ({ id: i.interactionId, event: i.dominantEvent, target: i.target, duration: i.duration }))
    };
  }`
})
```

## Interpreting Results

### INP Thresholds

| INP Duration | Rating            |
|-------------|-------------------|
| < 200 ms    | GOOD              |
| 200 -- 500 ms | NEEDS IMPROVEMENT |
| > 500 ms    | POOR              |

### Phase Breakdown Guide

Each interaction duration is decomposed into three phases:

```
|-- inputDelay --|-- processingTime --|-- presentationDelay --|
                 ^                     ^                       ^
          processingStart        processingEnd          next paint
```

| Phase | What It Measures | High Value Means |
|-------|-----------------|------------------|
| **inputDelay** | Time from user action to handler start | Main thread was busy when user interacted (long tasks, other scripts executing) |
| **processingTime** | Time spent in event handlers | Event handler code is doing heavy synchronous work |
| **presentationDelay** | Time from handler end to next paint | Browser is doing expensive layout, paint, or compositing after the handler |

### Dominant Bottleneck Actions

| Dominant Phase | Recommended Fix |
|---------------|-----------------|
| inputDelay | Break up long tasks with `scheduler.yield()`, defer non-critical work, reduce third-party script impact |
| processingTime | Optimize event handler logic, debounce rapid events, move heavy computation to Web Worker |
| presentationDelay | Reduce DOM mutations in handler, avoid forced reflows, simplify CSS (reduce selector complexity, layers) |

### Long Animation Frame Correlation

When a slow interaction overlaps with a Long Animation Frame, the frame's
`scripts` array reveals the exact source file, function name, and character
position of the code that caused the long frame. This is the most actionable
diagnostic data:

- `sourceURL`: the script file (often a bundled chunk).
- `sourceFunctionName`: the function name (if not minified).
- `forcedStyleAndLayoutDuration`: time spent in forced synchronous layout
  (reading layout properties like `offsetHeight` after DOM mutations).

### Report Format

```
## Interaction Replay Analysis

### Summary
- Total interactions: 8
- INP: 312 ms (NEEDS IMPROVEMENT)
- Dominant bottleneck: processingTime
- Long animation frames: 2

### INP Interaction
- Event: click on BUTTON#save-settings ("Save")
- Duration: 312 ms
  - Input delay: 8 ms
  - Processing: 245 ms  <-- bottleneck
  - Presentation: 59 ms

### Top 5 Slowest Interactions

| Rank | Event | Target | Duration | Input | Processing | Presentation |
|------|-------|--------|----------|-------|------------|--------------|
| 1 | click | BUTTON#save-settings | 312 ms | 8 ms | 245 ms | 59 ms |
| 2 | keydown | INPUT#search | 156 ms | 4 ms | 112 ms | 40 ms |
| 3 | click | A.nav-link | 89 ms | 12 ms | 45 ms | 32 ms |
| 4 | click | BUTTON.toggle | 45 ms | 3 ms | 24 ms | 18 ms |
| 5 | keydown | INPUT#email | 32 ms | 2 ms | 18 ms | 12 ms |

### Long Frame Correlation
1. click on BUTTON#save-settings overlaps with 298ms long frame
   - Script: settings.chunk.js:4521 saveAllSettings()
   - Forced layout: 42 ms
   - Handler validates form, serializes state, triggers DOM update synchronously

### Console Errors During Session
- (none)

### Recommendations
1. Defer serialization in saveAllSettings() to a microtask or Web Worker
2. Eliminate forced layout (42ms) -- defer offsetHeight read after DOM write
3. Debounce search input handler (currently fires on every keydown at 112ms)
```

## Limitations

- **Chromium only**: Event Timing API with `interactionId` and `durationThreshold: 0` is Chromium-specific. Firefox supports basic Event Timing but without `interactionId` grouping. Safari has no Event Timing support.
- **Long Animation Frame is Chromium 123+**: older Chromium versions will not produce `long-animation-frame` entries. The skill gracefully degrades (reports `loafSupported: false`) and still provides interaction timing without script attribution.
- **Synthetic input delay is lower**: Playwright dispatches events directly to the renderer process. Real user input goes through the OS input queue and the browser's compositor thread. The `inputDelay` phase measured here may be lower than what real users experience.
- **`durationThreshold: 0` captures everything**: this includes very fast interactions (< 8ms) that are normally below the Event Timing threshold. The volume of entries can be large on interaction-heavy pages. The analysis groups by `interactionId` to keep the output manageable.
- **Scroll is not an "interaction"**: the Event Timing API does not consider scroll events as interactions for INP purposes. Scroll responsiveness is measured separately via scroll-linked animations and is not captured here.
- **Minified source attribution**: Long Animation Frame script entries reference the deployed (often minified/bundled) source files. Source maps are not automatically applied. The `sourceFunctionName` may be mangled. Use the `sourceCharPosition` with your source map to find the original code.
