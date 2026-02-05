---
name: css-coverage-treemap
description: Collect CSS rule usage via Chrome DevTools Protocol (CDP) and report per-stylesheet coverage with unused selector analysis.
---

# CSS Coverage Treemap

Use the Chrome DevTools Protocol (CDP) to track which CSS rules are actually used during page rendering and user interaction. Produces a per-stylesheet breakdown of used vs. unused rules, identifies the top unused selectors, and estimates potential file size savings.

## When to Use

- Identifying dead CSS that can be safely removed to reduce page weight
- Auditing CSS frameworks (Bootstrap, Tailwind utility classes) for unused rules
- Measuring CSS coverage before and after a refactoring effort
- Estimating transfer size savings from CSS tree-shaking
- Comparing CSS usage across different page routes in a single-page application

## Prerequisites

- Playwright MCP server connected with a **Chromium** browser session (CDP required)
- Target page must be accessible in the browser session
- For accurate coverage, the page should be interacted with to trigger dynamic CSS (hover states, modals, accordions, media queries)

## Workflow

### Step 1: Start CSS Coverage Tracking via CDP

Use `browser_run_code` to create a CDP session and begin tracking CSS rule usage. This must run **before** navigating to the page so that all stylesheets are captured from initial load.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    // Store CDP client for later use
    page.__cdpClient = client;

    // Enable CSS domain and start tracking rule usage
    await client.send('CSS.enable');
    await client.send('CSS.startRuleUsageTracking');

    return 'CSS coverage tracking started';
  }`
})
```

### Step 2: Navigate to the Target Page

```
browser_navigate({ url: "https://example.com/page" })
```

Wait for the page to fully load including stylesheets:

```
browser_wait_for({ time: 3 })
```

Or wait for a specific element that indicates the page is ready:

```
browser_wait_for({ text: "some content" })
```

### Step 3: Exercise Dynamic CSS

Interact with the page to trigger CSS rules that only apply during user interactions. This step is critical for accurate coverage -- without it, hover styles, modal styles, and animation classes will appear as unused.

Use a combination of MCP tools to simulate interactions:

**Hover over navigation menus:**

```
browser_snapshot()
```

Then identify menu elements and hover:

```
browser_hover({ ref: "menu-ref", element: "Navigation menu" })
browser_wait_for({ time: 1 })
```

**Open modals or dialogs:**

```
browser_click({ ref: "modal-trigger-ref", element: "Open modal button" })
browser_wait_for({ time: 1 })
browser_press_key({ key: "Escape" })
```

**Expand accordions or collapsible sections:**

```
browser_click({ ref: "accordion-ref", element: "Accordion header" })
browser_wait_for({ time: 0.5 })
```

**Scroll to trigger lazy-loaded components and scroll-based styles:**

```javascript
browser_run_code({
  code: `async (page) => {
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForTimeout(1500);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(500);
    return 'Scroll complete';
  }`
})
```

### Step 4: Stop Tracking and Collect Rule Usage

Use `browser_run_code` to stop the tracking and retrieve the raw rule usage data.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = page.__cdpClient;

    const { ruleUsage } = await client.send('CSS.stopRuleUsageTracking');

    // Store the raw data for analysis
    await page.evaluate((data) => {
      window.__cssRuleUsage = data;
    }, ruleUsage);

    return {
      totalRules: ruleUsage.length,
      usedRules: ruleUsage.filter(r => r.used).length,
      unusedRules: ruleUsage.filter(r => !r.used).length
    };
  }`
})
```

### Step 5: Enumerate Stylesheets and Map Rules

Use `browser_evaluate` to correlate the CDP rule usage data with actual stylesheet information from the DOM.

```javascript
browser_evaluate({
  function: `() => {
    const sheets = Array.from(document.styleSheets);
    const sheetData = [];

    sheets.forEach((sheet, sheetIndex) => {
      try {
        const href = sheet.href || ('inline-style-' + sheetIndex);
        const shortName = href.includes('/')
          ? href.split('/').pop().split('?')[0]
          : href;

        let rules;
        try {
          rules = Array.from(sheet.cssRules || []);
        } catch (e) {
          // Cross-origin stylesheet, cannot read rules
          sheetData.push({
            href: href,
            shortName: shortName,
            crossOrigin: true,
            totalRules: 'unknown',
            error: 'Cannot read cross-origin stylesheet'
          });
          return;
        }

        const ruleDetails = rules.map((rule, ruleIndex) => {
          let selector = '';
          let type = rule.type;
          let typeName = 'unknown';

          switch (rule.type) {
            case 1: // CSSStyleRule
              selector = rule.selectorText || '';
              typeName = 'style';
              break;
            case 3: // CSSImportRule
              typeName = 'import';
              break;
            case 4: // CSSMediaRule
              selector = '@media ' + rule.conditionText;
              typeName = 'media';
              break;
            case 5: // CSSFontFaceRule
              typeName = 'font-face';
              break;
            case 7: // CSSKeyframesRule
              selector = '@keyframes ' + rule.name;
              typeName = 'keyframes';
              break;
            case 12: // CSSSupportsRule
              selector = '@supports ' + rule.conditionText;
              typeName = 'supports';
              break;
            default:
              typeName = 'type-' + rule.type;
          }

          return {
            index: ruleIndex,
            selector: selector.substring(0, 120),
            typeName: typeName,
            cssText: rule.cssText ? rule.cssText.substring(0, 200) : ''
          };
        });

        sheetData.push({
          href: href,
          shortName: shortName,
          crossOrigin: false,
          totalRules: rules.length,
          rules: ruleDetails
        });
      } catch (e) {
        sheetData.push({
          href: sheet.href || 'unknown',
          error: e.message
        });
      }
    });

    return { sheets: sheetData, totalSheets: sheets.length };
  }`
})
```

### Step 6: Compute Coverage Analysis

Use `browser_evaluate` to merge the CDP rule usage data with the stylesheet enumeration and produce the final analysis.

```javascript
browser_evaluate({
  function: `() => {
    const ruleUsage = window.__cssRuleUsage || [];

    // Aggregate by stylesheet
    const byStylesheet = {};
    ruleUsage.forEach(rule => {
      const key = rule.styleSheetId;
      if (!byStylesheet[key]) {
        byStylesheet[key] = { used: 0, unused: 0, total: 0, rules: [] };
      }
      byStylesheet[key].total++;
      if (rule.used) {
        byStylesheet[key].used++;
      } else {
        byStylesheet[key].unused++;
      }
    });

    const totalUsed = ruleUsage.filter(r => r.used).length;
    const totalUnused = ruleUsage.filter(r => !r.used).length;
    const totalRules = ruleUsage.length;
    const usagePercent = totalRules > 0
      ? Math.round((totalUsed / totalRules) * 1000) / 10
      : 0;

    // Estimate savings from performance.getEntriesByType
    const cssResources = performance.getEntriesByType('resource')
      .filter(r => r.initiatorType === 'link' || r.name.endsWith('.css'));
    const totalCSSBytes = cssResources.reduce((sum, r) => sum + (r.transferSize || 0), 0);
    const estimatedSavingsBytes = Math.round(totalCSSBytes * (totalUnused / Math.max(totalRules, 1)));

    // Per-stylesheet summary
    const stylesheetSummary = Object.entries(byStylesheet).map(([id, data]) => ({
      styleSheetId: id,
      used: data.used,
      unused: data.unused,
      total: data.total,
      usagePercent: Math.round((data.used / data.total) * 1000) / 10
    }));

    // Sort by most unused
    stylesheetSummary.sort((a, b) => b.unused - a.unused);

    return {
      overall: {
        totalRules: totalRules,
        usedRules: totalUsed,
        unusedRules: totalUnused,
        usagePercent: usagePercent,
        totalCSSTransferKB: Math.round(totalCSSBytes / 1024 * 10) / 10,
        estimatedSavingsKB: Math.round(estimatedSavingsBytes / 1024 * 10) / 10
      },
      perStylesheet: stylesheetSummary,
      cssResources: cssResources.map(r => ({
        url: r.name.split('/').pop().split('?')[0],
        transferSizeKB: Math.round((r.transferSize || 0) / 1024 * 10) / 10,
        durationMs: Math.round(r.duration)
      }))
    };
  }`
})
```

## Interpreting Results

### Overall Coverage Thresholds

| Usage % | Assessment | Action |
|---|---|---|
| > 80% | Good | Minor cleanup opportunities |
| 60 - 80% | Moderate | Review unused rules, especially large selectors |
| 40 - 60% | Poor | Significant dead CSS; consider CSS-in-JS or purging |
| < 40% | Critical | Major framework bloat; audit utility class usage |

### Per-Stylesheet Assessment

| Scenario | Recommendation |
|---|---|
| Single stylesheet with < 30% usage | Split into critical/non-critical or use CSS modules |
| Framework CSS (bootstrap.css) at 20% usage | Replace with utility-first approach or tree-shake |
| Inline styles with 90%+ usage | Well-optimized; leave as-is |
| Multiple sheets with overlapping unused selectors | Consolidate and deduplicate |

### Estimated Savings

The estimated KB savings is calculated proportionally: `(unusedRules / totalRules) * totalCSSTransferSize`. This is an approximation because:
- Selectors vary in text length
- Minified CSS has different compression ratios
- Some "unused" rules may be needed for other pages

### Report Format

Present results as a table:

```
| Stylesheet          | Used | Unused | Total | Usage % |
|---------------------|------|--------|-------|---------|
| main.css            |  145 |    320 |   465 |  31.2%  |
| vendor.css          |   89 |   1240 |  1329 |   6.7%  |
| components.css      |  210 |     45 |   255 |  82.4%  |
| TOTAL               |  444 |   1605 |  2049 |  21.7%  |

Estimated savings: ~48.3 KB (of 62.1 KB total CSS transfer)
```

## Limitations

- **Chromium-only**: This skill requires Chrome DevTools Protocol (CDP) for CSS rule usage tracking. It will not work with Firefox or WebKit browser contexts in Playwright.
- **Cross-origin stylesheets**: Stylesheets loaded from different origins (CDNs without CORS headers) cannot have their individual rules enumerated via `document.styleSheets`. CDP tracking still counts their usage, but selector-level detail is unavailable.
- **Dynamic CSS**: CSS rules injected via JavaScript (`insertRule`, CSS-in-JS libraries like styled-components or Emotion) are tracked by CDP but may not appear in the `document.styleSheets` enumeration.
- **Media queries**: Rules inside `@media` blocks that do not match the current viewport will show as unused. Resize the viewport or test at multiple breakpoints for complete coverage.
- **Pseudo-class rules**: `:hover`, `:focus`, `:active` rules require actual user interaction to be marked as used. Step 3 (exercising dynamic CSS) is critical for these.
- **Multi-page coverage**: This skill measures coverage for a single page load. A CSS file may have rules used on other pages. For full-site coverage, run the skill on multiple pages and aggregate results.
- **Print styles**: `@media print` rules will appear unused unless the page is rendered in print mode.
