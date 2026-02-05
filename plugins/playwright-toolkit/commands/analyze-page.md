---
name: analyze-page
description: "Comprehensive single-page UI analysis combining video recording, performance metrics, DOM profiling, and accessibility audit in a single orchestrated pass."
user_invocable: true
arguments:
  - name: url
    description: "The URL to analyze"
    required: true
---

# Full Page Analysis Orchestrator

You are performing a **comprehensive UI analysis** that orchestrates multiple analysis skills simultaneously in a single browser session. The goal is maximum insight with minimum redundant page loads.

## Orchestration Strategy

The key innovation is **parallel instrumentation**: install ALL observers in one `browser_evaluate` call, perform ONE set of interactions that exercises the page for all skills, then harvest all data at once. Meanwhile, record video in a separate context to capture the visual timeline.

## Phase 1: Parallel Setup (Single browser_evaluate)

### Step 1 — Start Video Recording

Use `browser_run_code` to create a **separate BrowserContext** with video recording enabled. This runs in parallel with the main analysis context.

```javascript
browser_run_code({
  code: `async (page) => {
    const browser = page.context().browser();
    const videoContext = await browser.newContext({
      recordVideo: { dir: '/tmp/playwright-toolkit/analyze-page/video', size: { width: 1280, height: 720 } }
    });
    const videoPage = await videoContext.newPage();

    // Store references globally so we can close later
    globalThis.__analysisVideo = { context: videoContext, page: videoPage };
    return 'Video context ready';
  }`
})
```

### Step 2 — Navigate BOTH contexts to the target URL

Navigate the main page AND the video page to the same URL:

```
browser_navigate({ url: "<TARGET_URL>" })
```

Then navigate the video page:

```javascript
browser_run_code({
  code: `async (page) => {
    await globalThis.__analysisVideo.page.goto('<TARGET_URL>', { waitUntil: 'networkidle' });
    return 'Video page loaded';
  }`
})
```

### Step 3 — Install ALL Observers at Once

In a single `browser_evaluate` call on the MAIN page, install:
- Core Web Vitals observers (LCP, CLS, INP)
- DOM Churn profiler (MutationObserver + Long Animation Frames)
- Viewport Exposure tracker (IntersectionObserver)
- Interaction Replay tracker (Event Timing)

```javascript
browser_evaluate({
  function: `() => {
    window.__fullAnalysis = {
      cwv: { cls: [], lcp: null, inp: [] },
      churn: { mutations: [], longFrames: [], startTime: performance.now() },
      exposure: {},
      interactions: { events: [], longFrames: [] }
    };

    // === CWV: CLS with attribution ===
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!entry.hadRecentInput) {
          window.__fullAnalysis.cwv.cls.push({
            value: entry.value,
            startTime: entry.startTime,
            sources: entry.sources?.map(s => ({
              node: s.node?.tagName + (s.node?.id ? '#' + s.node.id : ''),
              previousRect: s.previousRect,
              currentRect: s.currentRect
            })) || []
          });
        }
      }
    }).observe({ type: 'layout-shift', buffered: true });

    // === CWV: LCP with element identification ===
    new PerformanceObserver((list) => {
      const entries = list.getEntries();
      const last = entries[entries.length - 1];
      window.__fullAnalysis.cwv.lcp = {
        value: last.startTime,
        element: last.element?.tagName,
        id: last.element?.id,
        url: last.url,
        size: last.size,
        renderTime: last.renderTime
      };
    }).observe({ type: 'largest-contentful-paint', buffered: true });

    // === CWV: INP via Event Timing ===
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.interactionId) {
          window.__fullAnalysis.cwv.inp.push({
            duration: entry.duration,
            inputDelay: entry.processingStart - entry.startTime,
            processingTime: entry.processingEnd - entry.processingStart,
            presentationDelay: entry.startTime + entry.duration - entry.processingEnd,
            target: entry.target?.tagName + (entry.target?.id ? '#' + entry.target.id : ''),
            type: entry.name
          });
        }
        // Also feed to interaction replay
        window.__fullAnalysis.interactions.events.push({
          name: entry.name,
          duration: entry.duration,
          interactionId: entry.interactionId,
          inputDelay: entry.processingStart - entry.startTime,
          processingTime: entry.processingEnd - entry.processingStart,
          presentationDelay: entry.startTime + entry.duration - entry.processingEnd,
          target: entry.target ? entry.target.tagName + (entry.target.id ? '#' + entry.target.id : '') : null
        });
      }
    }).observe({ type: 'event', durationThreshold: 0, buffered: true });

    // === DOM Churn: MutationObserver ===
    new MutationObserver((records) => {
      const now = performance.now();
      for (const record of records) {
        let el = record.target instanceof Element ? record.target : record.target.parentElement;
        let id = '';
        while (el && !id) {
          if (el.id) id = '#' + el.id;
          else if (el.dataset?.testid) id = '[data-testid=\"' + el.dataset.testid + '\"]';
          else if (el.className && typeof el.className === 'string') id = el.tagName + '.' + el.className.split(' ')[0];
          el = el.parentElement;
        }
        window.__fullAnalysis.churn.mutations.push({
          time: now, type: record.type, target: id || record.target.nodeName,
          adds: record.addedNodes.length, removes: record.removedNodes.length
        });
      }
    }).observe(document.documentElement, {
      childList: true, attributes: true, characterData: true, subtree: true
    });

    // === DOM Churn + Interaction: Long Animation Frames ===
    try {
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          const frame = {
            startTime: entry.startTime,
            duration: entry.duration,
            blockingDuration: entry.blockingDuration,
            scripts: entry.scripts?.map(s => ({
              sourceURL: s.sourceURL, sourceFunctionName: s.sourceFunctionName, duration: s.duration
            })) || []
          };
          window.__fullAnalysis.churn.longFrames.push(frame);
          window.__fullAnalysis.interactions.longFrames.push(frame);
        }
      }).observe({ type: 'long-animation-frame', buffered: true });
    } catch(e) { /* LoAF not supported */ }

    // === Viewport Exposure: IntersectionObserver ===
    const exposureSelectors = 'h1,h2,h3,h4,p,img,section,article,button,a,[data-testid],figure,video';
    const elements = document.querySelectorAll(exposureSelectors);
    new IntersectionObserver((entries) => {
      const now = performance.now();
      for (const entry of entries) {
        const eid = entry.target.dataset.__eid;
        if (!window.__fullAnalysis.exposure[eid]) {
          window.__fullAnalysis.exposure[eid] = {
            tag: entry.target.tagName, text: entry.target.textContent?.trim().substring(0, 30),
            totalVisible: 0, maxRatio: 0, enterTime: null
          };
        }
        const d = window.__fullAnalysis.exposure[eid];
        if (entry.isIntersecting) {
          d.enterTime = now;
          d.maxRatio = Math.max(d.maxRatio, entry.intersectionRatio);
        } else if (d.enterTime) {
          d.totalVisible += now - d.enterTime;
          d.enterTime = null;
        }
      }
    }, { threshold: [0, 0.25, 0.5, 0.75, 1.0] })
    .observe && elements.forEach((el, i) => {
      el.dataset.__eid = 'e' + i;
      // observe each element
    });

    // Fix: actually observe each element
    const io = new IntersectionObserver((entries) => {
      const now = performance.now();
      for (const entry of entries) {
        const eid = entry.target.dataset.__eid;
        if (!eid) continue;
        if (!window.__fullAnalysis.exposure[eid]) {
          window.__fullAnalysis.exposure[eid] = {
            tag: entry.target.tagName, text: entry.target.textContent?.trim().substring(0, 30),
            totalVisible: 0, maxRatio: 0, enterTime: null
          };
        }
        const d = window.__fullAnalysis.exposure[eid];
        if (entry.isIntersecting) {
          d.enterTime = now;
          d.maxRatio = Math.max(d.maxRatio, entry.intersectionRatio);
        } else if (d.enterTime) {
          d.totalVisible += now - d.enterTime;
          d.enterTime = null;
        }
      }
    }, { threshold: [0, 0.25, 0.5, 0.75, 1.0] });
    elements.forEach((el, i) => { el.dataset.__eid = 'e' + i; io.observe(el); });

    return 'All observers installed: CWV + DOM Churn + Exposure + Interaction Timing (' + elements.length + ' elements tracked)';
  }`
})
```

## Phase 2: Interaction Pass (Exercise the page for all skills simultaneously)

Perform a realistic interaction sequence. The video context mirrors this via its own page. On the main page:

1. **Wait for page to settle** (2 seconds)
2. **Scroll down** slowly (exercises exposure tracking, triggers layout shifts)
3. **Click primary CTA** (exercises INP, interaction replay, DOM churn)
4. **Type in search/input** if available (exercises keyboard interactions)
5. **Scroll back up** (more exposure data)
6. **Hover over navigation** (exercises dynamic CSS, DOM mutations)
7. **Wait** (2 seconds for final data collection)

Mirror the same interactions on the video page using `browser_run_code`:

```javascript
browser_run_code({
  code: `async (page) => {
    const vp = globalThis.__analysisVideo.page;
    // Mirror interactions on video page
    await vp.mouse.wheel(0, 500);
    await vp.waitForTimeout(1000);
    await vp.mouse.wheel(0, 500);
    await vp.waitForTimeout(1000);
    await vp.mouse.wheel(0, -1000);
    await vp.waitForTimeout(2000);
    return 'Video interactions mirrored';
  }`
})
```

## Phase 3: Parallel Harvest

### Step 1 — Finalize video recording

```javascript
browser_run_code({
  code: `async (page) => {
    const videoPath = await globalThis.__analysisVideo.page.video().path();
    await globalThis.__analysisVideo.context.close();
    return 'Video saved: ' + videoPath;
  }`
})
```

### Step 2 — Extract scene-change frames from video

```bash
bash: /home/noreddine/.claude/plugins/marketplaces/binaryPetsClaude/plugins/playwright-toolkit/skills/visual-regression-cinema/scripts/frame-diff.sh /tmp/playwright-toolkit/analyze-page/video/*.webm /tmp/playwright-toolkit/analyze-page/frames 0.3
```

### Step 3 — Harvest ALL analysis data in one browser_evaluate

```javascript
browser_evaluate({
  function: `() => {
    const d = window.__fullAnalysis;

    // Finalize exposure timers
    const now = performance.now();
    for (const [id, data] of Object.entries(d.exposure)) {
      if (data.enterTime) { data.totalVisible += now - data.enterTime; data.enterTime = null; }
    }

    // CWV summary
    const clsTotal = d.cwv.cls.reduce((s, e) => s + e.value, 0);
    const inpDurations = d.cwv.inp.map(e => e.duration).sort((a, b) => a - b);
    const inpP98 = inpDurations.length > 0 ? inpDurations[Math.min(Math.ceil(inpDurations.length * 0.98) - 1, inpDurations.length - 1)] : 0;

    // Churn summary
    const elapsed = (now - d.churn.startTime) / 1000;
    const subtrees = {};
    for (const m of d.churn.mutations) {
      if (!subtrees[m.target]) subtrees[m.target] = 0;
      subtrees[m.target]++;
    }
    const topChurners = Object.entries(subtrees).sort((a, b) => b[1] - a[1]).slice(0, 10);

    // Exposure summary
    const exposureItems = Object.values(d.exposure).sort((a, b) => b.totalVisible - a.totalVisible);
    const neverSeen = exposureItems.filter(e => e.totalVisible === 0);

    return {
      cwv: {
        lcp: d.cwv.lcp,
        lcpRating: d.cwv.lcp?.value < 2500 ? 'GOOD' : d.cwv.lcp?.value < 4000 ? 'NEEDS IMPROVEMENT' : 'POOR',
        cls: clsTotal,
        clsRating: clsTotal < 0.1 ? 'GOOD' : clsTotal < 0.25 ? 'NEEDS IMPROVEMENT' : 'POOR',
        inp: inpP98,
        inpRating: inpP98 < 200 ? 'GOOD' : inpP98 < 500 ? 'NEEDS IMPROVEMENT' : 'POOR',
        clsShifts: d.cwv.cls.length,
        inpInteractions: d.cwv.inp.length
      },
      churn: {
        totalMutations: d.churn.mutations.length,
        mutationsPerSecond: (d.churn.mutations.length / elapsed).toFixed(1),
        longFrames: d.churn.longFrames.length,
        topChurners: topChurners.map(([target, count]) => ({ target, count }))
      },
      exposure: {
        totalTracked: exposureItems.length,
        neverSeen: neverSeen.length,
        neverSeenItems: neverSeen.slice(0, 5).map(e => e.tag + ': ' + e.text),
        topExposed: exposureItems.slice(0, 5).map(e => ({ tag: e.tag, text: e.text, visibleMs: Math.round(e.totalVisible) }))
      },
      interactions: {
        total: d.interactions.events.filter(e => e.interactionId > 0).length,
        slowest: d.interactions.events.filter(e => e.duration > 100).sort((a, b) => b.duration - a.duration).slice(0, 5)
      }
    };
  }`
})
```

### Step 4 — Collect network data

```
browser_network_requests({ includeStatic: false })
```

### Step 5 — Take final screenshot and accessibility snapshot

```
browser_take_screenshot({ type: "png", fullPage: true })
browser_snapshot()
```

### Step 6 — Read extracted video frames

Read the scene-change frames from `/tmp/playwright-toolkit/analyze-page/frames/` to analyze visual transitions.

## Phase 4: Report

Compile all data into a structured report:

```markdown
# Full Page Analysis: <URL>

## Core Web Vitals
| Metric | Value | Rating |
|--------|-------|--------|
| LCP | Xms (element: ...) | GOOD/NEEDS IMPROVEMENT/POOR |
| CLS | X.XX (N shifts) | ... |
| INP | Xms (target: ...) | ... |

## DOM Churn
- Total mutations: N
- Rate: N/sec
- Long animation frames: N
- Top churners: ...

## Viewport Exposure
- Elements tracked: N
- Never seen by user: N
- Items below fold that were never scrolled to: ...

## Visual Timeline (from video)
- Scene 1 (0.5s): Initial paint - hero visible
- Scene 2 (2.1s): After scroll - content section visible
- Scene 3 (4.5s): After CTA click - modal opened
...

## Network Summary
- Total requests: N
- Failed: N
- Slowest resources: ...

## Slowest Interactions
| Event | Target | Duration | Bottleneck Phase |
|-------|--------|----------|-----------------|
...

## Recommendations
1. ...
2. ...
```
