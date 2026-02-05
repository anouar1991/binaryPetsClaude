---
name: accessibility-journey
description: Audit keyboard navigation by tabbing through a page, capturing focus state at each stop, and running axe-core for WCAG violations.
---

# Accessibility Journey

Perform a complete keyboard navigation audit by tabbing through every focusable element on a page. At each tab stop, capture the focused element's properties, check for visible focus indicators, and record the tab order. Combine this with an axe-core WCAG audit for a comprehensive accessibility report.

## When to Use

- Auditing a page for WCAG 2.1 AA keyboard accessibility compliance
- Verifying that all interactive elements are reachable via Tab key
- Checking for missing focus indicators (outline, box-shadow) on focusable elements
- Detecting focus traps where keyboard users get stuck in a component
- Validating tab order matches the expected visual reading order
- Reviewing heading hierarchy and ARIA attribute correctness
- QA before accessibility certification or remediation planning

## Prerequisites

- Playwright MCP server connected with a browser session available
- Target page must be publicly accessible or already authenticated
- Page should be fully loaded (all interactive elements rendered)
- axe-core CDN must be reachable (or the page must already include axe-core)

## Workflow

### Step 1: Navigate to the Target Page

```
browser_navigate({ url: "https://example.com/page" })
```

Wait for the page to be ready:

```
browser_wait_for({ time: 3 })
```

### Step 2: Inject axe-core

Use `browser_evaluate` to load axe-core from CDN. This provides automated WCAG violation detection.

```javascript
browser_evaluate({
  function: `() => {
    return new Promise((resolve, reject) => {
      if (window.axe) {
        resolve('axe-core already loaded');
        return;
      }
      const script = document.createElement('script');
      script.src = 'https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.9.1/axe.min.js';
      script.onload = () => resolve('axe-core loaded: v' + window.axe.version);
      script.onerror = () => reject('Failed to load axe-core from CDN');
      document.head.appendChild(script);
    });
  }`
})
```

### Step 3: Run axe-core Audit

Use `browser_evaluate` to execute the full axe-core scan. This runs asynchronously and returns all violations, incomplete checks, and passes.

```javascript
browser_evaluate({
  function: `() => {
    return axe.run().then(results => {
      return {
        violations: results.violations.map(v => ({
          id: v.id,
          impact: v.impact,
          description: v.description,
          helpUrl: v.helpUrl,
          nodes: v.nodes.length,
          targets: v.nodes.slice(0, 5).map(n => ({
            target: n.target.join(' '),
            html: n.html.substring(0, 120),
            failureSummary: n.failureSummary
          }))
        })),
        incomplete: results.incomplete.map(i => ({
          id: i.id,
          impact: i.impact,
          description: i.description,
          nodes: i.nodes.length
        })),
        violationCount: results.violations.length,
        incompleteCount: results.incomplete.length,
        passCount: results.passes.length
      };
    });
  }`
})
```

### Step 4: Initialize Tab Journey Tracker

Use `browser_evaluate` to set up the tracking data structure before starting the tab loop.

```javascript
browser_evaluate({
  function: `() => {
    window.__tabJourney = [];
    window.__tabStartTime = performance.now();

    // Reset focus to the beginning of the document
    document.body.focus();
    document.activeElement?.blur?.();

    return {
      activeElement: document.activeElement?.tagName || 'BODY',
      journeyInitialized: true
    };
  }`
})
```

### Step 5: Tab Loop -- Press Tab and Capture Focus State

Repeat the following cycle up to 50 times or until focus returns to `<body>` or wraps around to the first element.

**5a: Press Tab**

```
browser_press_key({ key: "Tab" })
```

**5b: Capture focused element details**

Use `browser_evaluate` to inspect `document.activeElement` and check for focus indicator visibility.

```javascript
browser_evaluate({
  function: `() => {
    const el = document.activeElement;
    if (!el || el === document.body) {
      return { reachedBody: true, journeyLength: window.__tabJourney.length };
    }

    const rect = el.getBoundingClientRect();
    const style = getComputedStyle(el);
    const outlineStyle = style.outlineStyle;
    const outlineWidth = parseFloat(style.outlineWidth) || 0;
    const outlineColor = style.outlineColor;
    const boxShadow = style.boxShadow;

    const hasOutline = outlineStyle !== 'none' && outlineWidth > 0;
    const hasBoxShadow = boxShadow && boxShadow !== 'none';
    const hasFocusIndicator = hasOutline || hasBoxShadow;

    const stop = {
      index: window.__tabJourney.length,
      tag: el.tagName.toLowerCase(),
      role: el.getAttribute('role') || '',
      ariaLabel: el.getAttribute('aria-label') || '',
      ariaLabelledBy: el.getAttribute('aria-labelledby') || '',
      text: (el.textContent || '').trim().substring(0, 60),
      href: el.getAttribute('href') || '',
      type: el.getAttribute('type') || '',
      tabIndex: el.tabIndex,
      id: el.id || '',
      className: String(el.className || '').substring(0, 60),
      rect: {
        top: Math.round(rect.top),
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      },
      focusIndicator: {
        hasOutline: hasOutline,
        outlineStyle: outlineStyle,
        outlineWidth: outlineWidth,
        outlineColor: outlineColor,
        hasBoxShadow: hasBoxShadow,
        visible: hasFocusIndicator
      },
      isOffscreen: rect.top < 0 || rect.left < 0 ||
                   rect.bottom > window.innerHeight || rect.right > window.innerWidth,
      timestamp: Math.round(performance.now() - window.__tabStartTime)
    };

    window.__tabJourney.push(stop);

    // Check for focus trap (same element as previous 2 stops)
    const journey = window.__tabJourney;
    const isTrap = journey.length >= 3 &&
      journey[journey.length - 1].tag === journey[journey.length - 2].tag &&
      journey[journey.length - 1].id === journey[journey.length - 2].id &&
      journey[journey.length - 2].tag === journey[journey.length - 3].tag &&
      journey[journey.length - 2].id === journey[journey.length - 3].id;

    return {
      stop: stop,
      journeyLength: journey.length,
      focusTrapDetected: isTrap,
      reachedBody: false
    };
  }`
})
```

**5c: Take screenshot at each tab stop (optional, for detailed audits)**

```
browser_take_screenshot({ type: "png", filename: "tab-stop-{index}.png" })
```

Replace `{index}` with the current tab stop number.

**5d: Check termination conditions**

Stop the tab loop when any of these conditions is met:
- `reachedBody` is `true` (focus returned to body)
- `journeyLength` reaches 50
- `focusTrapDetected` is `true` (log it and break)
- The current element matches the first element in the journey (focus wrapped around)

### Step 6: Capture Accessibility Tree Snapshot

Use `browser_snapshot` to get the full accessibility tree as Playwright sees it.

```
browser_snapshot()
```

### Step 7: Extract Final Journey Report

Use `browser_evaluate` to compile the complete journey data and summary statistics.

```javascript
browser_evaluate({
  function: `() => {
    const journey = window.__tabJourney;

    const missingFocusIndicator = journey.filter(s => !s.focusIndicator.visible);
    const offscreenStops = journey.filter(s => s.isOffscreen);
    const interactiveElements = journey.filter(s =>
      ['a', 'button', 'input', 'select', 'textarea'].includes(s.tag)
    );
    const nonInteractiveTabStops = journey.filter(s =>
      !['a', 'button', 'input', 'select', 'textarea'].includes(s.tag) &&
      !s.role
    );

    // Check for skip link (first tab stop with href starting with #)
    const skipLink = journey.length > 0 && journey[0].tag === 'a' &&
                     journey[0].href.startsWith('#');

    // Extract heading hierarchy from page
    const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6')).map(h => ({
      level: parseInt(h.tagName[1]),
      text: h.textContent.trim().substring(0, 80)
    }));

    // Check heading order violations
    const headingViolations = [];
    for (let i = 1; i < headings.length; i++) {
      if (headings[i].level > headings[i - 1].level + 1) {
        headingViolations.push({
          message: 'Skipped heading level: h' + headings[i - 1].level + ' -> h' + headings[i].level,
          at: headings[i].text
        });
      }
    }

    return {
      totalTabStops: journey.length,
      tabOrder: journey.map(s => ({
        index: s.index,
        element: s.tag + (s.id ? '#' + s.id : '') + (s.role ? '[role=' + s.role + ']' : ''),
        label: s.ariaLabel || s.text.substring(0, 40),
        focusVisible: s.focusIndicator.visible
      })),
      missingFocusIndicator: missingFocusIndicator.map(s => ({
        index: s.index,
        element: s.tag + (s.id ? '#' + s.id : ''),
        label: s.ariaLabel || s.text.substring(0, 40)
      })),
      offscreenStops: offscreenStops.length,
      nonInteractiveTabStops: nonInteractiveTabStops.length,
      hasSkipLink: skipLink,
      headings: headings,
      headingViolations: headingViolations,
      summary: {
        totalStops: journey.length,
        missingIndicatorCount: missingFocusIndicator.length,
        offscreenCount: offscreenStops.length,
        hasSkipLink: skipLink,
        headingViolationCount: headingViolations.length
      }
    };
  }`
})
```

## Interpreting Results

### Focus Indicator Assessment

| Condition | Severity | WCAG Criterion |
|---|---|---|
| No outline AND no box-shadow on focused element | Critical | 2.4.7 Focus Visible (AA) |
| Outline present but color matches background | Warning | 2.4.11 Focus Appearance (AAA) |
| Focus moves off-screen without scrolling | Critical | 2.4.7 Focus Visible (AA) |

### Tab Order Issues

| Issue | Severity | WCAG Criterion |
|---|---|---|
| Tab order does not follow visual reading order | Serious | 2.4.3 Focus Order (A) |
| Focus trap detected (stuck on same element) | Critical | 2.1.2 No Keyboard Trap (A) |
| No skip-link as first tab stop | Warning | 2.4.1 Bypass Blocks (A) |
| Non-interactive element receives focus | Warning | Best practice |

### Heading Hierarchy

| Issue | Severity | WCAG Criterion |
|---|---|---|
| Skipped heading level (e.g., h2 to h4) | Serious | 1.3.1 Info and Relationships (A) |
| Multiple h1 elements | Warning | Best practice |
| No h1 element on page | Serious | Best practice |

### axe-core Impact Levels

| Impact | Action Required |
|---|---|
| critical | Must fix before release; blocks users entirely |
| serious | Should fix; significantly impacts usability |
| moderate | Plan to fix; causes inconvenience |
| minor | Nice to fix; minor annoyance |

### Report Checklist

When reporting results, cover all of these:

1. **Tab order sequence**: List each tab stop with its element type and label
2. **Missing focus indicators**: Elements where keyboard users cannot see where focus is
3. **Focus traps**: Components that trap keyboard focus (modals without Escape, custom widgets)
4. **Skip-link behavior**: Whether the page has a skip-to-content link as the first tab stop
5. **Heading hierarchy**: Any skipped levels or structural issues
6. **ARIA violations**: Relevant axe-core violations (missing labels, invalid roles, etc.)
7. **Off-screen focus**: Tab stops that move focus outside the visible viewport

## Limitations

- **Shadow DOM**: Elements inside closed shadow DOM roots are not reachable by `document.activeElement` inspection from the main document context. Open shadow roots work correctly.
- **Modal dialogs**: Properly implemented modals should trap focus within themselves. This will appear as a "focus trap" in the report -- distinguish between intentional modal traps (correct) and unintentional traps (bugs).
- **iframe content**: Tab may move into iframes. The focus capture script only inspects `document.activeElement` in the main frame. Cross-origin iframes cannot be inspected.
- **Dynamic content**: Elements rendered after the tab loop begins (lazy modals, dropdown menus triggered by click rather than focus) will not appear in the tab journey.
- **axe-core CDN dependency**: The skill requires network access to load axe-core from CDN. If the CDN is blocked, inject axe-core via a local file or use a page that already includes it.
- **Browser-specific focus behavior**: Focus ring styles vary by browser and OS. Chromium's default focus ring may mask missing custom focus styles. Test in multiple browsers for production audits.
- **Works in all browsers**: This skill uses standard DOM APIs and does not require Chromium-specific features. The axe-core library is cross-browser compatible.
