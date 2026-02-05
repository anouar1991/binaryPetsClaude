---
name: dark-mode-tester
description: >
  Test light and dark color scheme rendering by emulating prefers-color-scheme
  via CDP, capturing screenshots in both modes, computing WCAG 2.1 contrast
  ratios for all visible text, detecting hardcoded colors that ignore scheme
  changes, and validating color-scheme meta/CSS declarations.
---

# Dark Mode Tester

Perform a thorough dark mode audit by toggling `prefers-color-scheme` between
light and dark via Chrome DevTools Protocol, then comparing rendered colors,
contrast ratios, and visual output across both modes.

## When to Use

- Verifying that dark mode is implemented correctly across all components.
- Checking WCAG 2.1 contrast compliance in both light and dark modes.
- Finding elements with hardcoded colors that do not respond to scheme changes.
- Auditing `color-scheme` meta tag and CSS property declarations.
- Comparing visual differences between light and dark screenshots.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP `Emulation.setEmulatedMedia`.
- Target page must support `prefers-color-scheme` media query (or the audit will reveal that it does not).

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

### Step 2 -- Validate color-scheme Declarations

Check for `<meta name="color-scheme">` and CSS `color-scheme` property on the
root element.

```javascript
browser_evaluate({
  function: `() => {
    const results = { meta: null, cssRoot: null, cssBody: null };

    // Check meta tag
    const meta = document.querySelector('meta[name="color-scheme"]');
    results.meta = meta ? meta.content : 'NOT FOUND';

    // Check CSS color-scheme on :root and body
    const root = document.documentElement;
    const body = document.body;
    results.cssRoot = getComputedStyle(root).colorScheme || 'NOT SET';
    results.cssBody = getComputedStyle(body).colorScheme || 'NOT SET';

    return results;
  }`
})
```

### Step 3 -- Emulate Light Mode and Capture Baseline

Use CDP to force light mode, then collect all text element colors.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'light' }]
    });
    // Allow re-render
    await page.waitForTimeout(1000);
    return 'Light mode emulated';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "dark-mode-light.png" })
```

```
browser_snapshot()
```

Collect computed colors for all visible text elements in light mode:

```javascript
browser_evaluate({
  function: `() => {
    const elements = [];
    const selector = 'h1,h2,h3,h4,h5,h6,p,span,a,li,td,th,label,button,input,textarea,select,div,section,article';
    document.querySelectorAll(selector).forEach(el => {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      // Skip invisible elements
      if (rect.width === 0 || rect.height === 0 || style.display === 'none' || style.visibility === 'hidden') return;
      // Only include elements with direct text content
      const hasDirectText = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim());
      if (!hasDirectText && !['INPUT','TEXTAREA','SELECT','BUTTON'].includes(el.tagName)) return;

      elements.push({
        tag: el.tagName,
        id: el.id || null,
        class: el.className ? String(el.className).split(' ')[0] : null,
        color: style.color,
        backgroundColor: style.backgroundColor,
        text: el.textContent.trim().substring(0, 60)
      });
    });
    window.__lightColors = elements;
    return { totalElements: elements.length, sample: elements.slice(0, 10) };
  }`
})
```

### Step 4 -- Emulate Dark Mode and Capture

Switch to dark mode and collect the same data.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setEmulatedMedia', {
      features: [{ name: 'prefers-color-scheme', value: 'dark' }]
    });
    await page.waitForTimeout(1000);
    return 'Dark mode emulated';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "dark-mode-dark.png" })
```

```
browser_snapshot()
```

Collect computed colors in dark mode:

```javascript
browser_evaluate({
  function: `() => {
    const elements = [];
    const selector = 'h1,h2,h3,h4,h5,h6,p,span,a,li,td,th,label,button,input,textarea,select,div,section,article';
    document.querySelectorAll(selector).forEach(el => {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0 || style.display === 'none' || style.visibility === 'hidden') return;
      const hasDirectText = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim());
      if (!hasDirectText && !['INPUT','TEXTAREA','SELECT','BUTTON'].includes(el.tagName)) return;

      elements.push({
        tag: el.tagName,
        id: el.id || null,
        class: el.className ? String(el.className).split(' ')[0] : null,
        color: style.color,
        backgroundColor: style.backgroundColor,
        text: el.textContent.trim().substring(0, 60)
      });
    });
    window.__darkColors = elements;
    return { totalElements: elements.length, sample: elements.slice(0, 10) };
  }`
})
```

### Step 5 -- Compute Contrast Ratios (WCAG 2.1)

Calculate contrast ratios for all text elements in both modes using the
relative luminance formula from WCAG 2.1.

```javascript
browser_evaluate({
  function: `() => {
    function parseColor(str) {
      const m = str.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
      if (!m) return null;
      return { r: parseInt(m[1]), g: parseInt(m[2]), b: parseInt(m[3]) };
    }

    function sRGBtoLinear(c) {
      c = c / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function luminance(rgb) {
      return 0.2126 * sRGBtoLinear(rgb.r) + 0.7152 * sRGBtoLinear(rgb.g) + 0.0722 * sRGBtoLinear(rgb.b);
    }

    function contrastRatio(fg, bg) {
      const l1 = Math.max(luminance(fg), luminance(bg));
      const l2 = Math.min(luminance(fg), luminance(bg));
      return (l1 + 0.05) / (l2 + 0.05);
    }

    function gradeContrast(ratio, isLargeText) {
      if (isLargeText) {
        if (ratio >= 4.5) return 'AAA';
        if (ratio >= 3) return 'AA';
        return 'FAIL';
      }
      if (ratio >= 7) return 'AAA';
      if (ratio >= 4.5) return 'AA';
      return 'FAIL';
    }

    function analyzeMode(elements, mode) {
      const results = [];
      for (const el of elements) {
        const fg = parseColor(el.color);
        const bg = parseColor(el.backgroundColor);
        if (!fg || !bg) continue;
        const ratio = Math.round(contrastRatio(fg, bg) * 100) / 100;
        const isLarge = ['H1','H2','H3'].includes(el.tag);
        const grade = gradeContrast(ratio, isLarge);
        if (grade === 'FAIL') {
          results.push({
            element: el.tag + (el.id ? '#' + el.id : '') + (el.class ? '.' + el.class : ''),
            text: el.text,
            foreground: el.color,
            background: el.backgroundColor,
            ratio: ratio,
            grade: grade,
            mode: mode
          });
        }
      }
      return results;
    }

    const lightFails = analyzeMode(window.__lightColors || [], 'light');
    const darkFails = analyzeMode(window.__darkColors || [], 'dark');

    return {
      lightMode: { total: (window.__lightColors || []).length, failures: lightFails.length, details: lightFails.slice(0, 20) },
      darkMode: { total: (window.__darkColors || []).length, failures: darkFails.length, details: darkFails.slice(0, 20) }
    };
  }`
})
```

### Step 6 -- Detect Hardcoded Colors (Unchanged Between Modes)

Find elements whose foreground or background color did not change between light
and dark mode, indicating hardcoded values that ignore the color scheme.

```javascript
browser_evaluate({
  function: `() => {
    const light = window.__lightColors || [];
    const dark = window.__darkColors || [];
    const unchanged = [];

    const minLen = Math.min(light.length, dark.length);
    for (let i = 0; i < minLen; i++) {
      const l = light[i];
      const d = dark[i];
      // Match by tag + id + class
      if (l.tag !== d.tag || l.id !== d.id) continue;

      const fgSame = l.color === d.color;
      const bgSame = l.backgroundColor === d.backgroundColor;

      // Skip if background is transparent in both (inherits from parent)
      if (l.backgroundColor === 'rgba(0, 0, 0, 0)' && d.backgroundColor === 'rgba(0, 0, 0, 0)') continue;

      if (fgSame && bgSame) {
        unchanged.push({
          element: l.tag + (l.id ? '#' + l.id : '') + (l.class ? '.' + l.class : ''),
          text: l.text,
          color: l.color,
          backgroundColor: l.backgroundColor,
          issue: 'Both foreground and background unchanged'
        });
      } else if (fgSame) {
        unchanged.push({
          element: l.tag + (l.id ? '#' + l.id : '') + (l.class ? '.' + l.class : ''),
          text: l.text,
          color: l.color,
          issue: 'Foreground color unchanged'
        });
      } else if (bgSame && l.backgroundColor !== 'rgba(0, 0, 0, 0)') {
        unchanged.push({
          element: l.tag + (l.id ? '#' + l.id : '') + (l.class ? '.' + l.class : ''),
          text: l.text,
          backgroundColor: l.backgroundColor,
          issue: 'Background color unchanged'
        });
      }
    }

    return { totalUnchanged: unchanged.length, details: unchanged.slice(0, 30) };
  }`
})
```

### Step 7 -- Reset to Default

Restore the default media emulation.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Emulation.setEmulatedMedia', { features: [] });
    return 'Media emulation reset';
  }`
})
```

## Interpreting Results

### Contrast Ratio Thresholds (WCAG 2.1)

| Text Size    | AA Minimum | AAA Minimum |
|-------------|-----------|-------------|
| Normal text | 4.5:1     | 7:1         |
| Large text  | 3:1       | 4.5:1       |

### Report Format

```
## Dark Mode Audit -- <url>

### color-scheme Declarations
- Meta tag: light dark
- CSS :root: light dark
- CSS body: normal

### Contrast Failures
#### Light Mode (2 failures)
1. P.intro -- ratio 2.8:1 (FAIL) -- #999 on #fff
2. SPAN.caption -- ratio 3.1:1 (FAIL) -- #aaa on #f5f5f5

#### Dark Mode (4 failures)
1. P.intro -- ratio 1.9:1 (FAIL) -- #666 on #1a1a1a
2. A.nav-link -- ratio 2.3:1 (FAIL) -- #888 on #222

### Hardcoded Colors (not responding to scheme)
1. BUTTON.cta -- both fg (#fff) and bg (#0066cc) unchanged
2. DIV.badge -- foreground (#333) unchanged between modes

### Screenshots
- Light mode: dark-mode-light.png
- Dark mode: dark-mode-dark.png
```

### What to Look For

- **Contrast failures in dark mode only**: common when dark mode is an afterthought; text colors may not be lightened enough against dark backgrounds.
- **Hardcoded colors on interactive elements**: buttons, badges, and alerts often use hardcoded brand colors that become unreadable in dark mode.
- **Missing `color-scheme` meta tag**: without `<meta name="color-scheme" content="light dark">`, the browser cannot optimize default colors (form controls, scrollbars) for dark mode.
- **Transparent backgrounds inheriting wrong parent color**: an element with `background: transparent` may inherit a light parent background in dark mode if the parent was not updated.

## Limitations

- **Chromium only**: CDP `Emulation.setEmulatedMedia` is Chromium-specific. Firefox and Safari require different approaches.
- **Element matching heuristic**: the hardcoded-color detection matches elements by tag, id, and class index position. DOM changes between modes (conditional rendering) may cause false positives.
- **Inherited backgrounds**: elements with `background-color: transparent` rely on parent backgrounds. The tool reports the computed value, which may be `rgba(0, 0, 0, 0)` even when the visual background is opaque.
- **CSS custom properties**: the tool checks computed values, not declared values. It cannot tell if a color comes from a CSS variable or is hardcoded in the stylesheet.
- **Images and SVGs**: contrast analysis covers text elements only. Images, SVG icons, and canvas content are not analyzed for dark mode compatibility.
