---
name: test-responsive
description: "Verify page works across devices and themes: responsive layout, dark mode, touch targets, font readability, and Core Web Vitals at each viewport."
user_invocable: true
arguments:
  - name: url
    description: "The URL to test"
    required: true
  - name: viewports
    description: "Viewport set to test: 'all', 'mobile', 'tablet', 'desktop', or comma-separated like 'mobile,tablet'. Default: 'mobile,desktop'"
    required: false
---

# Responsive Design Test Orchestrator

You are performing a **comprehensive responsive design test** that verifies a page works correctly across multiple viewport sizes, color schemes, and interaction modes. Each viewport is tested for layout correctness, touch target compliance, font readability, dark mode rendering, and Core Web Vitals.

**Skills orchestrated:** responsive-design-tester, dark-mode-tester, accessibility-journey, core-web-vitals-audit

## Viewport Matrix

Parse the `viewports` argument (default: `mobile,desktop`) and select from:

| Keyword | Width | Height | DPR | Device Label |
|---------|-------|--------|-----|-------------|
| `mobile` | 375 | 667 | 2 | iPhone SE |
| `mobile-large` | 430 | 932 | 3 | iPhone 14 Pro Max |
| `tablet` | 768 | 1024 | 2 | iPad Mini |
| `tablet-large` | 1024 | 1366 | 2 | iPad Pro 12.9" |
| `desktop` | 1440 | 900 | 1 | Desktop HD |
| `desktop-large` | 1920 | 1080 | 1 | Full HD |
| `ultrawide` | 2560 | 1440 | 1 | QHD Ultrawide |

If `viewports` is `"all"`, test: mobile, tablet, desktop, ultrawide.

## Orchestration Strategy

For each viewport in the matrix, run a complete test cycle: resize, install observers, navigate, analyze layout, toggle dark mode, screenshot both modes. Collect CWV data per viewport. Finish with a keyboard accessibility pass at the narrowest viewport.

## Phase 1: Per-Viewport Test Loop

For EACH viewport in the selected matrix, perform the following sequence:

### Step 1 — Resize Browser

```
browser_resize({ width: <WIDTH>, height: <HEIGHT> })
```

### Step 2 — Install CWV and Layout Observers

```javascript
browser_evaluate({
  function: `() => {
    window.__responsiveTest = {
      cwv: { cls: [], lcp: null },
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
        dpr: window.devicePixelRatio
      }
    };

    // CLS observer
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (!entry.hadRecentInput) {
          window.__responsiveTest.cwv.cls.push({
            value: entry.value,
            sources: entry.sources?.map(s => ({
              node: s.node?.tagName + (s.node?.id ? '#' + s.node.id : ''),
              previousRect: s.previousRect,
              currentRect: s.currentRect
            })) || []
          });
        }
      }
    }).observe({ type: 'layout-shift', buffered: true });

    // LCP observer
    new PerformanceObserver((list) => {
      const entries = list.getEntries();
      const last = entries[entries.length - 1];
      window.__responsiveTest.cwv.lcp = {
        value: last.startTime,
        element: last.element?.tagName,
        id: last.element?.id,
        size: last.size
      };
    }).observe({ type: 'largest-contentful-paint', buffered: true });

    return 'Responsive observers installed at ' + window.innerWidth + 'x' + window.innerHeight;
  }`
})
```

### Step 3 — Navigate to Target URL

```
browser_navigate({ url: "<TARGET_URL>" })
browser_wait_for({ time: 2 })
```

### Step 4 — Analyze Layout, Touch Targets, and Fonts

```javascript
browser_evaluate({
  function: `() => {
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const analysis = {};

    // === Horizontal Overflow Detection ===
    analysis.overflow = {
      hasHorizontalScroll: document.documentElement.scrollWidth > document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      clientWidth: document.documentElement.clientWidth,
      overflowAmount: document.documentElement.scrollWidth - document.documentElement.clientWidth
    };

    // === Touch Target Analysis ===
    const interactiveSelectors = 'a, button, input, select, textarea, [role="button"], [role="link"], [role="menuitem"], [role="tab"], [onclick]';
    const interactiveEls = document.querySelectorAll(interactiveSelectors);
    const touchTargets = [];
    const tooSmall = [];
    const overlapping = [];

    interactiveEls.forEach(el => {
      const rect = el.getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) return;
      const info = {
        tag: el.tagName,
        text: (el.textContent || el.getAttribute('aria-label') || '').trim().substring(0, 40),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        top: Math.round(rect.top),
        left: Math.round(rect.left)
      };
      touchTargets.push(info);
      if (rect.width < 44 || rect.height < 44) tooSmall.push(info);
    });

    // Check for overlapping adjacent targets
    for (let i = 0; i < touchTargets.length - 1; i++) {
      for (let j = i + 1; j < Math.min(i + 5, touchTargets.length); j++) {
        const a = touchTargets[i];
        const b = touchTargets[j];
        const gap = Math.max(
          Math.max(0, b.left - (a.left + a.width)),
          Math.max(0, a.left - (b.left + b.width)),
          Math.max(0, b.top - (a.top + a.height)),
          Math.max(0, a.top - (b.top + b.height))
        );
        if (gap < 8 && gap >= 0) {
          overlapping.push({ element1: a.text, element2: b.text, gap: Math.round(gap) });
        }
      }
    }

    analysis.touchTargets = {
      total: touchTargets.length,
      tooSmall: tooSmall.length,
      tooSmallList: tooSmall.slice(0, 10),
      overlapping: overlapping.slice(0, 5)
    };

    // === Font Readability ===
    const textElements = document.querySelectorAll('p, li, span, a, label, td, th, input, button, h1, h2, h3, h4, h5, h6');
    let smallFontCount = 0;
    let tooSmallFonts = [];
    const fontSizes = {};

    textElements.forEach(el => {
      const styles = getComputedStyle(el);
      const fontSize = parseFloat(styles.fontSize);
      const rounded = Math.round(fontSize);
      fontSizes[rounded] = (fontSizes[rounded] || 0) + 1;

      if (fontSize < 12 && el.textContent.trim().length > 0 && el.offsetHeight > 0) {
        smallFontCount++;
        if (tooSmallFonts.length < 5) {
          tooSmallFonts.push({
            tag: el.tagName,
            text: el.textContent.trim().substring(0, 30),
            fontSize: rounded
          });
        }
      }
    });

    // Check input font size (iOS zoom trigger)
    const inputs = document.querySelectorAll('input, select, textarea');
    const inputsBelow16 = [];
    inputs.forEach(input => {
      const fs = parseFloat(getComputedStyle(input).fontSize);
      if (fs < 16) {
        inputsBelow16.push({
          tag: input.tagName,
          type: input.type,
          name: input.name,
          fontSize: Math.round(fs)
        });
      }
    });

    analysis.fonts = {
      smallFontCount,
      tooSmallFonts,
      inputsBelow16px: inputsBelow16,
      fontSizeDistribution: fontSizes
    };

    // === Layout Issues ===
    // Check for elements pushed off-screen
    const offScreen = [];
    document.querySelectorAll('section, article, div, nav, header, footer, main, aside').forEach(el => {
      const rect = el.getBoundingClientRect();
      if (rect.width > 0 && rect.left + rect.width < 0) {
        offScreen.push({ tag: el.tagName, id: el.id, className: el.className?.toString()?.substring(0, 40) });
      }
      if (rect.width > 0 && rect.left > vw) {
        offScreen.push({ tag: el.tagName, id: el.id, className: el.className?.toString()?.substring(0, 40) });
      }
    });

    analysis.layout = {
      offScreenElements: offScreen.length,
      offScreenList: offScreen.slice(0, 5)
    };

    // === CWV Harvest ===
    const clsTotal = window.__responsiveTest.cwv.cls.reduce((s, e) => s + e.value, 0);
    analysis.cwv = {
      lcp: window.__responsiveTest.cwv.lcp,
      lcpRating: window.__responsiveTest.cwv.lcp?.value < 2500 ? 'GOOD' : window.__responsiveTest.cwv.lcp?.value < 4000 ? 'NEEDS IMPROVEMENT' : 'POOR',
      cls: clsTotal,
      clsRating: clsTotal < 0.1 ? 'GOOD' : clsTotal < 0.25 ? 'NEEDS IMPROVEMENT' : 'POOR'
    };

    return analysis;
  }`
})
```

### Step 5 — Screenshot Light Mode

```
browser_take_screenshot({ type: "png", filename: "responsive-<VIEWPORT>-light.png" })
```

### Step 6 — Toggle Dark Mode via CDP

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'dark' }]
    });
    // Wait for CSS transitions to complete
    await page.waitForTimeout(500);
    return 'Dark mode emulated';
  }`
})
```

### Step 7 — Analyze Dark Mode

```javascript
browser_evaluate({
  function: `() => {
    // Check for dark mode awareness
    const isDarkMediaActive = window.matchMedia('(prefers-color-scheme: dark)').matches;

    // Check for common dark mode indicators
    const html = document.documentElement;
    const body = document.body;
    const htmlBg = getComputedStyle(html).backgroundColor;
    const bodyBg = getComputedStyle(body).backgroundColor;

    // Parse background color to determine if dark
    const parseBg = (bg) => {
      const match = bg.match(/\\d+/g);
      if (!match) return { r: 255, g: 255, b: 255 };
      return { r: parseInt(match[0]), g: parseInt(match[1]), b: parseInt(match[2]) };
    };

    const bgColor = parseBg(bodyBg);
    const luminance = (0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b) / 255;
    const hasDarkBackground = luminance < 0.5;

    // Check for contrast issues (light text on light bg or dark on dark)
    const contrastIssues = [];
    document.querySelectorAll('p, h1, h2, h3, a, li, span, button').forEach(el => {
      if (el.offsetHeight === 0) return;
      const styles = getComputedStyle(el);
      const textColor = parseBg(styles.color);
      const elBg = parseBg(styles.backgroundColor);

      // Simple contrast check
      const textLum = (0.299 * textColor.r + 0.587 * textColor.g + 0.114 * textColor.b) / 255;
      const bgLum = (0.299 * elBg.r + 0.587 * elBg.g + 0.114 * elBg.b) / 255;
      const contrast = (Math.max(textLum, bgLum) + 0.05) / (Math.min(textLum, bgLum) + 0.05);

      if (contrast < 3 && el.textContent.trim().length > 0) {
        if (contrastIssues.length < 10) {
          contrastIssues.push({
            tag: el.tagName,
            text: el.textContent.trim().substring(0, 30),
            contrast: contrast.toFixed(2),
            textColor: styles.color,
            bgColor: styles.backgroundColor
          });
        }
      }
    });

    return {
      darkMediaActive: isDarkMediaActive,
      hasDarkBackground,
      bodyBackground: bodyBg,
      htmlHasDarkClass: html.classList.contains('dark') || html.dataset.theme === 'dark',
      contrastIssues: contrastIssues.length,
      contrastIssuesList: contrastIssues
    };
  }`
})
```

### Step 8 — Screenshot Dark Mode

```
browser_take_screenshot({ type: "png", filename: "responsive-<VIEWPORT>-dark.png" })
```

### Step 9 — Reset to Light Mode

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'light' }]
    });
    return 'Light mode restored';
  }`
})
```

**Repeat Steps 1-9 for each viewport in the matrix.**

## Phase 2: Keyboard Accessibility at Mobile Viewport

After all viewports are tested, set the smallest viewport and run a keyboard navigation test:

```
browser_resize({ width: 375, height: 667 })
browser_navigate({ url: "<TARGET_URL>" })
```

```javascript
browser_run_code({
  code: `async (page) => {
    const focusPath = [];
    const maxTabs = 25;

    for (let i = 0; i < maxTabs; i++) {
      await page.keyboard.press('Tab');
      const info = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        const rect = el.getBoundingClientRect();
        const styles = getComputedStyle(el);
        return {
          tag: el.tagName,
          text: (el.textContent || el.getAttribute('aria-label') || '').trim().substring(0, 40),
          hasVisibleFocus: styles.outlineStyle !== 'none' || styles.boxShadow !== 'none',
          isVisible: rect.width > 0 && rect.height > 0,
          isInViewport: rect.top >= 0 && rect.top < window.innerHeight,
          targetSize: { width: Math.round(rect.width), height: Math.round(rect.height) }
        };
      });

      if (!info) break;
      focusPath.push(info);

      if (focusPath.length > 2 &&
          info.tag === focusPath[0].tag &&
          info.text === focusPath[0].text) break;
    }

    return {
      totalFocusable: focusPath.length,
      withoutVisibleFocus: focusPath.filter(e => !e.hasVisibleFocus).length,
      hiddenButFocusable: focusPath.filter(e => !e.isVisible).length,
      outOfViewport: focusPath.filter(e => !e.isInViewport).length,
      tooSmallTargets: focusPath.filter(e => e.targetSize.width < 44 || e.targetSize.height < 44).length,
      path: focusPath
    };
  }`
})
```

## Phase 3: Comparative Report

Compile results from all viewports into a comparative report. Read `skills/responsive-design-tester/references/device-viewports.md` for grading criteria.

```markdown
# Responsive Design Test: <URL>

## Overall Grade: [A-F]

## Viewport Comparison Matrix

| Metric | Mobile (375) | Tablet (768) | Desktop (1440) | Ultrawide (2560) |
|--------|-------------|-------------|----------------|-----------------|
| Horizontal Overflow | Yes/No | ... | ... | ... |
| Touch Targets < 44px | N | ... | ... | ... |
| Fonts < 12px | N | ... | ... | ... |
| Inputs < 16px (iOS zoom) | N | ... | ... | ... |
| LCP | Xms (GOOD) | ... | ... | ... |
| CLS | X.XX (GOOD) | ... | ... | ... |
| Dark Mode Adapted | Yes/No | ... | ... | ... |
| Contrast Issues (Dark) | N | ... | ... | ... |

## Per-Viewport Details

### Mobile (375x667)
- **Overflow:** [details]
- **Touch Targets:** N too small [list worst offenders]
- **Font Issues:** [details]
- **Dark Mode:** [adapted/not adapted, contrast issues]
- **CWV:** LCP Xms, CLS X.XX

[Screenshots: responsive-mobile-light.png, responsive-mobile-dark.png]

### Tablet (768x1024)
...

### Desktop (1440x900)
...

## Keyboard Navigation (Mobile Viewport)
- Focusable elements: N
- Without visible focus: N
- Hidden but focusable: N
- Outside viewport: N
- Focus order: [logical/issues]

## Dark Mode Summary
| Viewport | Responds to prefers-color-scheme | Background Changes | Contrast Issues |
|----------|--------------------------------|-------------------|----------------|
...

## Issues by Priority

### Critical (Blocks launch)
1. ...

### High (Should fix)
1. ...

### Medium (Improve UX)
1. ...

### Low (Nice to have)
1. ...

## Recommendations
1. ...
2. ...
3. ...
```
