---
name: responsive-design-tester
description: >
  Tests a page across a six-device viewport matrix (Mobile S/M/L, Tablet,
  Desktop, Ultrawide). For each viewport captures a screenshot, detects active
  CSS media queries, checks horizontal overflow, validates touch targets
  (min 48x48), font readability (min 16px body), viewport meta tag, and image
  srcset/sizes. Produces a comparison table with per-viewport issue counts.
---

# Responsive Design Tester

Run a full responsive design audit across six viewports. At each breakpoint the
skill captures layout screenshots, measures interactive element sizes, checks
font readability, detects horizontal overflow, and validates responsive image
markup.

## When to Use

- Before shipping a new page or component to verify cross-device rendering.
- Diagnosing layout issues reported on specific device widths.
- Auditing touch-target compliance with WCAG 2.5.8 / Material guidelines.
- Checking that images serve appropriate sizes via srcset/sizes.
- Verifying the viewport meta tag is present and correct.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** recommended for full `matchMedia` and CDP touch emulation support.
- Target page must be reachable from the browser instance.

## Viewport Matrix

| Name       | Width | Height | Type    |
|------------|-------|--------|---------|
| Mobile S   | 320   | 568    | Mobile  |
| Mobile M   | 375   | 667    | Mobile  |
| Mobile L   | 425   | 812    | Mobile  |
| Tablet     | 768   | 1024   | Tablet  |
| Desktop    | 1440  | 900    | Desktop |
| Ultrawide  | 2560  | 1080   | Desktop |

## Workflow

Repeat Steps 1 through 9 for each viewport in the matrix above.

### Step 1 -- Resize the Viewport

Call `browser_resize` with the current viewport dimensions.

```
browser_resize({ width: 320, height: 568 })
```

### Step 2 -- Enable Touch Emulation (Mobile Viewports Only)

For Mobile S, Mobile M, and Mobile L viewports, enable touch emulation via CDP
so the page receives touch events and may activate mobile-specific styles.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setTouchEmulationEnabled', {
      enabled: true,
      maxTouchPoints: 5
    });
    return 'Touch emulation enabled';
  }`
})
```

For Tablet, Desktop, and Ultrawide viewports, disable touch emulation:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setTouchEmulationEnabled', {
      enabled: false
    });
    return 'Touch emulation disabled';
  }`
})
```

### Step 3 -- Navigate to the Target Page

Call `browser_navigate` to load the page fresh at this viewport size so that
media queries are evaluated during load.

```
browser_navigate({ url: "<target_url>" })
```

Wait for the page to settle:

```
browser_wait_for({ time: 2 })
```

### Step 4 -- Validate Viewport Meta Tag

Check that the page has a proper viewport meta tag for responsive rendering.

```javascript
browser_evaluate({
  function: `() => {
    const meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      return { present: false, content: null, issues: ['Missing <meta name="viewport"> tag'] };
    }
    const content = meta.getAttribute('content') || '';
    const issues = [];

    if (!content.includes('width=device-width')) {
      issues.push('Missing width=device-width');
    }
    if (!content.includes('initial-scale')) {
      issues.push('Missing initial-scale');
    }
    if (content.includes('maximum-scale=1') || content.includes('user-scalable=no')) {
      issues.push('Zoom disabled -- accessibility concern (WCAG 1.4.4)');
    }
    return { present: true, content, issues };
  }`
})
```

### Step 5 -- Detect Active CSS Media Queries

Determine which common breakpoint media queries are currently active.

```javascript
browser_evaluate({
  function: `() => {
    const queries = [
      '(max-width: 320px)',
      '(max-width: 375px)',
      '(max-width: 425px)',
      '(max-width: 480px)',
      '(max-width: 576px)',
      '(max-width: 640px)',
      '(max-width: 768px)',
      '(max-width: 1024px)',
      '(max-width: 1200px)',
      '(max-width: 1440px)',
      '(min-width: 320px)',
      '(min-width: 576px)',
      '(min-width: 768px)',
      '(min-width: 1024px)',
      '(min-width: 1200px)',
      '(min-width: 1440px)',
      '(min-width: 1920px)',
      '(prefers-color-scheme: dark)',
      '(prefers-reduced-motion: reduce)',
      '(orientation: portrait)',
      '(orientation: landscape)',
      '(hover: hover)',
      '(hover: none)',
      '(pointer: fine)',
      '(pointer: coarse)'
    ];

    const active = [];
    const inactive = [];
    for (const q of queries) {
      if (window.matchMedia(q).matches) {
        active.push(q);
      } else {
        inactive.push(q);
      }
    }
    return {
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      devicePixelRatio: window.devicePixelRatio,
      activeQueries: active,
      inactiveQueries: inactive
    };
  }`
})
```

### Step 6 -- Check Horizontal Overflow

Detect whether any content overflows the viewport horizontally, which causes
unwanted horizontal scrolling on mobile devices.

```javascript
browser_evaluate({
  function: `() => {
    const docWidth = document.documentElement.scrollWidth;
    const viewportWidth = window.innerWidth;
    const hasOverflow = docWidth > viewportWidth;

    // Find overflowing elements
    const overflowing = [];
    if (hasOverflow) {
      const all = document.querySelectorAll('*');
      for (const el of all) {
        const rect = el.getBoundingClientRect();
        if (rect.right > viewportWidth + 1 || rect.left < -1) {
          const tag = el.tagName.toLowerCase();
          const id = el.id ? '#' + el.id : '';
          const cls = el.className && typeof el.className === 'string'
            ? '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.')
            : '';
          overflowing.push({
            element: tag + id + cls,
            left: Math.round(rect.left),
            right: Math.round(rect.right),
            width: Math.round(rect.width),
            overflowPx: Math.round(Math.max(0, rect.right - viewportWidth) + Math.max(0, -rect.left))
          });
        }
      }
      // Deduplicate: keep only elements that are not ancestors of smaller overflowing elements
      overflowing.sort((a, b) => b.overflowPx - a.overflowPx);
    }

    return {
      documentWidth: docWidth,
      viewportWidth,
      hasHorizontalOverflow: hasOverflow,
      overflowPx: Math.max(0, docWidth - viewportWidth),
      overflowingElements: overflowing.slice(0, 15)
    };
  }`
})
```

### Step 7 -- Validate Touch Targets

Check that all interactive elements meet the minimum 48x48px touch target
size recommended by Material Design and WCAG 2.5.8.

```javascript
browser_evaluate({
  function: `() => {
    const MIN_SIZE = 48;
    const interactive = document.querySelectorAll(
      'a, button, input, select, textarea, [role="button"], [role="link"], ' +
      '[role="checkbox"], [role="radio"], [role="tab"], [onclick], [tabindex]'
    );

    const results = { total: 0, passing: 0, failing: 0, failures: [] };
    const seen = new Set();

    for (const el of interactive) {
      // Skip hidden elements
      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') continue;

      const rect = el.getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) continue;

      results.total++;
      const w = Math.round(rect.width);
      const h = Math.round(rect.height);

      if (w >= MIN_SIZE && h >= MIN_SIZE) {
        results.passing++;
      } else {
        results.failing++;
        const tag = el.tagName.toLowerCase();
        const id = el.id ? '#' + el.id : '';
        const text = (el.textContent || '').trim().substring(0, 30);
        const key = tag + id + w + 'x' + h;
        if (!seen.has(key)) {
          seen.add(key);
          results.failures.push({
            element: tag + id,
            text: text || null,
            width: w,
            height: h,
            issue: w < MIN_SIZE && h < MIN_SIZE
              ? 'Both width (' + w + 'px) and height (' + h + 'px) below ' + MIN_SIZE + 'px'
              : w < MIN_SIZE
                ? 'Width (' + w + 'px) below ' + MIN_SIZE + 'px'
                : 'Height (' + h + 'px) below ' + MIN_SIZE + 'px'
          });
        }
      }
    }

    results.failures = results.failures.slice(0, 20);
    return results;
  }`
})
```

### Step 8 -- Check Font Readability

Verify that body text uses at least 16px font size for mobile readability,
and gather font size distribution across the page.

```javascript
browser_evaluate({
  function: `() => {
    const body = document.body;
    const bodyStyle = window.getComputedStyle(body);
    const bodyFontSize = parseFloat(bodyStyle.fontSize);

    // Sample text-containing elements
    const textElements = document.querySelectorAll(
      'p, li, td, th, span, a, label, div, section, article, blockquote'
    );

    const fontSizes = {};
    let tooSmallCount = 0;
    let totalChecked = 0;
    const tooSmallExamples = [];

    for (const el of textElements) {
      // Only check elements with direct text content
      const text = Array.from(el.childNodes)
        .filter(n => n.nodeType === Node.TEXT_NODE)
        .map(n => n.textContent.trim())
        .join('');
      if (!text || text.length < 3) continue;

      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden') continue;

      const size = Math.round(parseFloat(style.fontSize));
      totalChecked++;
      fontSizes[size + 'px'] = (fontSizes[size + 'px'] || 0) + 1;

      if (size < 16) {
        tooSmallCount++;
        if (tooSmallExamples.length < 10) {
          const tag = el.tagName.toLowerCase();
          const id = el.id ? '#' + el.id : '';
          tooSmallExamples.push({
            element: tag + id,
            fontSize: size + 'px',
            text: text.substring(0, 40)
          });
        }
      }
    }

    return {
      bodyFontSize: bodyFontSize + 'px',
      bodyFontSizeOk: bodyFontSize >= 16,
      totalTextElements: totalChecked,
      tooSmallCount,
      fontSizeDistribution: fontSizes,
      tooSmallExamples
    };
  }`
})
```

### Step 9 -- Check Image srcset and sizes

Scan all images for responsive image markup (srcset, sizes, picture element).

```javascript
browser_evaluate({
  function: `() => {
    const images = document.querySelectorAll('img');
    const results = {
      total: images.length,
      withSrcset: 0,
      withSizes: 0,
      inPicture: 0,
      missingResponsive: [],
      responsive: []
    };

    for (const img of images) {
      const style = window.getComputedStyle(img);
      if (style.display === 'none') continue;

      const hasSrcset = !!img.srcset;
      const hasSizes = !!img.sizes;
      const inPicture = img.parentElement && img.parentElement.tagName === 'PICTURE';

      if (hasSrcset) results.withSrcset++;
      if (hasSizes) results.withSizes++;
      if (inPicture) results.inPicture++;

      const rect = img.getBoundingClientRect();
      const entry = {
        src: (img.src || '').split('/').pop().substring(0, 60),
        naturalWidth: img.naturalWidth,
        naturalHeight: img.naturalHeight,
        displayWidth: Math.round(rect.width),
        displayHeight: Math.round(rect.height),
        hasSrcset,
        hasSizes,
        inPicture,
        loading: img.loading || 'auto'
      };

      if (!hasSrcset && !inPicture && img.naturalWidth > 100) {
        results.missingResponsive.push(entry);
      } else if (hasSrcset || inPicture) {
        results.responsive.push(entry);
      }
    }

    results.missingResponsive = results.missingResponsive.slice(0, 15);
    results.responsive = results.responsive.slice(0, 15);
    return results;
  }`
})
```

### Step 10 -- Capture Screenshot

Take a full-page screenshot at the current viewport size.

```
browser_take_screenshot({ type: "png", filename: "responsive-<viewport_name>.png", fullPage: true })
```

### Step 11 -- Capture Accessibility Snapshot

Take an accessibility snapshot for structural comparison across viewports.

```
browser_snapshot({ filename: "responsive-snapshot-<viewport_name>.md" })
```

### Step 12 -- Repeat for Next Viewport

Go back to Step 1 with the next viewport from the matrix.

## Interpreting Results

### Report Format

Produce a side-by-side comparison table summarizing issues per viewport:

```
## Responsive Design Audit -- <page_url>

| Check                | Mobile S | Mobile M | Mobile L | Tablet | Desktop | Ultrawide |
|----------------------|----------|----------|----------|--------|---------|-----------|
| Viewport Meta        | PASS     | PASS     | PASS     | PASS   | PASS    | PASS      |
| Horizontal Overflow  | FAIL     | PASS     | PASS     | PASS   | PASS    | PASS      |
| Touch Targets (48px) | 5 fail   | 3 fail   | 2 fail   | 1 fail | N/A     | N/A       |
| Font >= 16px         | FAIL     | PASS     | PASS     | PASS   | PASS    | PASS      |
| Images w/ srcset     | 2/8      | 2/8      | 2/8      | 2/8    | 2/8     | 2/8       |
| Active Breakpoints   | max-480  | max-480  | max-576  | max-1024| none   | min-1920  |
| Total Issues         | 3        | 1        | 1        | 1      | 0       | 0         |
```

### Per-Viewport Detail

For each viewport with issues, include detail:

```
### Mobile S (320x568) -- 3 Issues

**Horizontal Overflow**: 15px overflow caused by:
- `.hero-image` (right: 335px, overflow: 15px)

**Touch Targets Below 48px**:
1. `a` "Learn more" -- 36x24px (both dimensions too small)
2. `button#menu-toggle` -- 32x32px (both dimensions too small)

**Font Readability**:
- Body font size: 14px (below 16px minimum)
- 12 text elements below 16px
```

### What to Look For

- **Horizontal overflow at narrow viewports**: usually caused by fixed-width elements, uncontrained images, or `vw` units not accounting for scrollbars. Fix with `max-width: 100%`, `overflow-x: hidden` on containers, or `box-sizing: border-box`.
- **Touch targets below 48px**: common on nav links, icon buttons, and form controls. Fix with `min-height: 48px; min-width: 48px` or adequate padding.
- **Body font below 16px**: iOS Safari auto-zooms on inputs with font < 16px. Use `font-size: 1rem` (16px default) for body text.
- **Missing srcset/sizes**: large images served at fixed resolution waste bandwidth on small screens and load slowly on mobile. Add `srcset` with width descriptors and a `sizes` attribute.
- **Viewport meta missing width=device-width**: page will render at desktop width on mobile and require pinch zoom.

## Limitations

- **Touch target check is geometric only**: it measures the CSS box size, not the actual interactive area which may be enlarged by padding or `::before`/`::after` pseudo-elements.
- **Font size check samples visible elements**: dynamically loaded or JS-rendered content may not be captured if it has not rendered by the time the check runs.
- **Media query detection checks common breakpoints**: custom or unusual breakpoints defined in the page stylesheet may not appear in the predefined list.
- **Touch emulation via CDP**: simulates touch events but does not replicate actual device rendering differences (sub-pixel rendering, font hinting).
- **Screenshot comparison is manual**: the skill captures screenshots but does not perform automated visual diff. Compare screenshots visually or with external diffing tools.
