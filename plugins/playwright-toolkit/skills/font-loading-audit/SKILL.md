---
name: font-loading-audit
description: >
  Audits font loading behavior: FOIT/FOUT detection via timed screenshots,
  font-display validation per family, font file sizes and format efficiency
  (WOFF2 vs WOFF vs TTF), preload link validation, unused font declarations,
  and subsetting opportunities. Produces a font-by-font report with loading
  timeline and recommendations.
---

# Font Loading Audit

Perform a comprehensive font loading audit. Inspects every @font-face
declaration, checks font-display strategy, measures font file transfer sizes,
validates preload hints, detects unused font declarations, identifies format
inefficiencies, and captures timed screenshots to detect FOIT (Flash of
Invisible Text) and FOUT (Flash of Unstyled Text).

## When to Use

- Diagnosing invisible or unstyled text flashes during page load.
- Verifying that `font-display: swap` or `optional` is set correctly.
- Checking that fonts are served in WOFF2 format for optimal compression.
- Identifying unused @font-face declarations that waste bandwidth.
- Auditing `<link rel="preload" as="font">` correctness.
- Estimating subsetting savings for fonts with limited character usage.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP CSS domain, Network domain, and `document.fonts` API.
- Target page must be reachable from the browser instance.

## Workflow

### Step 1 -- Set Up Network Monitoring for Font Requests

Enable CDP Network monitoring before navigation to capture font request
timing, transfer sizes, and content types.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');

    const fontRequests = {};

    client.on('Network.requestWillBeSent', (params) => {
      const url = params.request.url;
      if (url.match(/\\.(woff2?|ttf|otf|eot)(\\?|$)/i) || params.type === 'Font') {
        fontRequests[params.requestId] = {
          url,
          method: params.request.method,
          timestamp: params.timestamp,
          initiator: params.initiator ? {
            type: params.initiator.type,
            url: params.initiator.url || null
          } : null
        };
      }
    });

    client.on('Network.responseReceived', (params) => {
      if (fontRequests[params.requestId]) {
        fontRequests[params.requestId].status = params.response.status;
        fontRequests[params.requestId].mimeType = params.response.mimeType;
        fontRequests[params.requestId].protocol = params.response.protocol;
        fontRequests[params.requestId].responseTimestamp = params.timestamp;
        fontRequests[params.requestId].headers = {
          contentLength: params.response.headers['content-length'] || null,
          contentType: params.response.headers['content-type'] || null,
          cacheControl: params.response.headers['cache-control'] || null,
          accessControlAllowOrigin: params.response.headers['access-control-allow-origin'] || null
        };
      }
    });

    client.on('Network.loadingFinished', (params) => {
      if (fontRequests[params.requestId]) {
        fontRequests[params.requestId].encodedDataLength = params.encodedDataLength;
        fontRequests[params.requestId].finishedTimestamp = params.timestamp;
      }
    });

    client.on('Network.loadingFailed', (params) => {
      if (fontRequests[params.requestId]) {
        fontRequests[params.requestId].failed = true;
        fontRequests[params.requestId].errorText = params.errorText;
        fontRequests[params.requestId].blockedReason = params.blockedReason || null;
      }
    });

    page.__fontRequests = fontRequests;
    page.__cdpClient = client;

    return 'Font network monitoring enabled';
  }`
})
```

### Step 2 -- Capture Early Screenshot (FOIT/FOUT Detection)

Take a screenshot immediately after navigation starts to capture the initial
text rendering state before custom fonts load.

```
browser_navigate({ url: "<target_url>" })
```

Take the first screenshot as quickly as possible after navigation to catch
FOIT (invisible text) or FOUT (system font fallback):

```
browser_take_screenshot({ type: "png", filename: "font-loading-t0-initial.png" })
```

Wait 500ms and capture another:

```
browser_wait_for({ time: 0.5 })
```

```
browser_take_screenshot({ type: "png", filename: "font-loading-t1-500ms.png" })
```

Wait 1 second more:

```
browser_wait_for({ time: 1 })
```

```
browser_take_screenshot({ type: "png", filename: "font-loading-t2-1500ms.png" })
```

Wait until fonts are fully loaded:

```
browser_wait_for({ time: 2 })
```

```
browser_take_screenshot({ type: "png", filename: "font-loading-t3-final.png" })
```

### Step 3 -- Check document.fonts API Status

Enumerate all fonts tracked by the browser's FontFaceSet API to check
their load status.

```javascript
browser_evaluate({
  function: `() => {
    const fontSet = document.fonts;
    const fonts = [];

    fontSet.forEach((fontFace) => {
      fonts.push({
        family: fontFace.family,
        style: fontFace.style,
        weight: fontFace.weight,
        stretch: fontFace.stretch,
        unicodeRange: fontFace.unicodeRange,
        display: fontFace.display,
        status: fontFace.status // 'unloaded', 'loading', 'loaded', 'error'
      });
    });

    // Group by family
    const byFamily = {};
    for (const font of fonts) {
      const family = font.family.replace(/['"]/g, '');
      if (!byFamily[family]) {
        byFamily[family] = { variants: [], display: font.display, statuses: new Set() };
      }
      byFamily[family].variants.push({
        weight: font.weight,
        style: font.style,
        status: font.status,
        display: font.display
      });
      byFamily[family].statuses.add(font.status);
    }

    // Convert sets for serialization
    const familyReport = {};
    for (const [family, data] of Object.entries(byFamily)) {
      familyReport[family] = {
        variantCount: data.variants.length,
        display: data.display,
        allLoaded: Array.from(data.statuses).every(s => s === 'loaded'),
        statuses: Array.from(data.statuses),
        variants: data.variants
      };
    }

    return {
      readyState: fontSet.status, // 'loading' or 'loaded'
      totalFontFaces: fonts.length,
      byFamily: familyReport
    };
  }`
})
```

### Step 4 -- Extract @font-face Rules via CDP

Use the CDP CSS domain to enumerate all @font-face rules from all stylesheets,
including their font-display values and source URLs.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = page.__cdpClient || await page.context().newCDPSession(page);
    await client.send('CSS.enable');

    // Get all stylesheets
    const fontFaceRules = [];
    const styleSheetIds = [];

    // Collect stylesheet IDs
    client.on('CSS.styleSheetAdded', (params) => {
      styleSheetIds.push(params.header);
    });

    // Wait for stylesheets to be reported
    await page.waitForTimeout(1000);

    // Get stylesheet text and parse @font-face rules
    for (const header of styleSheetIds) {
      try {
        const { text } = await client.send('CSS.getStyleSheetText', {
          styleSheetId: header.styleSheetId
        });

        // Extract @font-face blocks
        const fontFaceRegex = /@font-face\\s*\\{([^}]+)\\}/gi;
        let match;
        while ((match = fontFaceRegex.exec(text)) !== null) {
          const block = match[1];

          const getProperty = (prop) => {
            const propRegex = new RegExp(prop + '\\\\s*:\\\\s*([^;]+)', 'i');
            const m = block.match(propRegex);
            return m ? m[1].trim() : null;
          };

          fontFaceRules.push({
            family: (getProperty('font-family') || '').replace(/['"]/g, ''),
            style: getProperty('font-style') || 'normal',
            weight: getProperty('font-weight') || '400',
            display: getProperty('font-display') || null,
            src: getProperty('src'),
            unicodeRange: getProperty('unicode-range') || null,
            sourceSheet: header.sourceURL || header.title || 'inline',
            isInline: header.isInline || false
          });
        }
      } catch (e) {
        // Some stylesheets may not be accessible (cross-origin)
      }
    }

    await client.send('CSS.disable');

    return {
      totalFontFaceRules: fontFaceRules.length,
      rules: fontFaceRules
    };
  }`
})
```

### Step 5 -- Validate font-display Values

Analyze font-display settings for each font family and flag missing or
problematic values.

```javascript
browser_evaluate({
  function: `() => {
    // This analyzes the @font-face data collected in Step 4
    // For now, check computed styles on text elements to see actual font usage

    const textElements = document.querySelectorAll('h1, h2, h3, h4, h5, h6, p, li, a, span, button, label, td, th');
    const usedFamilies = new Set();

    for (const el of textElements) {
      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden') continue;

      const fontFamily = style.fontFamily;
      // Extract individual families
      const families = fontFamily.split(',').map(f => f.trim().replace(/['"]/g, ''));
      for (const f of families) {
        usedFamilies.add(f);
      }
    }

    return {
      usedFontFamilies: Array.from(usedFamilies),
      totalUsedFamilies: usedFamilies.size
    };
  }`
})
```

### Step 6 -- Validate Preload Links

Check for `<link rel="preload" as="font">` tags and validate their correctness.

```javascript
browser_evaluate({
  function: `() => {
    const preloads = document.querySelectorAll('link[rel="preload"][as="font"]');
    const results = [];
    const issues = [];

    for (const link of preloads) {
      const href = link.href;
      const crossorigin = link.crossOrigin;
      const type = link.type;

      const entry = {
        href: href,
        type: type || null,
        crossorigin: crossorigin || null,
        filename: href.split('/').pop().split('?')[0]
      };

      // Validate crossorigin attribute (required for font preloads)
      if (!crossorigin && crossorigin !== '') {
        entry.issue = 'Missing crossorigin attribute -- font preload will be ignored and re-fetched';
        issues.push(entry);
      }

      // Check format
      if (href.match(/\\.woff2(\\?|$)/i)) {
        entry.format = 'woff2';
      } else if (href.match(/\\.woff(\\?|$)/i)) {
        entry.format = 'woff';
        issues.push({ ...entry, issue: 'Preloading WOFF instead of WOFF2 -- use WOFF2 for better compression' });
      } else if (href.match(/\\.(ttf|otf)(\\?|$)/i)) {
        entry.format = 'ttf/otf';
        issues.push({ ...entry, issue: 'Preloading TTF/OTF instead of WOFF2 -- use WOFF2 for web delivery' });
      }

      results.push(entry);
    }

    // Check if there are fonts used but not preloaded
    // (This is informational -- not all fonts need preloading)
    return {
      preloadCount: preloads.length,
      preloads: results,
      issues,
      note: preloads.length === 0
        ? 'No font preloads found. Consider preloading critical above-fold fonts.'
        : null
    };
  }`
})
```

### Step 7 -- Collect Font Network Transfer Data

Retrieve actual transfer sizes, timing, and format info from CDP network data.

```javascript
browser_run_code({
  code: `async (page) => {
    const fontRequests = page.__fontRequests || {};
    const entries = Object.values(fontRequests);

    let totalBytes = 0;
    const formatStats = {};
    const fontDetails = [];

    for (const entry of entries) {
      const size = entry.encodedDataLength || 0;
      totalBytes += size;

      // Detect format from URL
      let format = 'unknown';
      const url = entry.url || '';
      if (url.match(/\\.woff2(\\?|$)/i)) format = 'woff2';
      else if (url.match(/\\.woff(\\?|$)/i)) format = 'woff';
      else if (url.match(/\\.ttf(\\?|$)/i)) format = 'ttf';
      else if (url.match(/\\.otf(\\?|$)/i)) format = 'otf';
      else if (url.match(/\\.eot(\\?|$)/i)) format = 'eot';

      if (!formatStats[format]) {
        formatStats[format] = { count: 0, totalBytes: 0 };
      }
      formatStats[format].count++;
      formatStats[format].totalBytes += size;

      // Calculate load duration
      const loadDurationMs = entry.finishedTimestamp && entry.timestamp
        ? Math.round((entry.finishedTimestamp - entry.timestamp) * 1000)
        : null;

      fontDetails.push({
        url: url.split('/').pop().split('?')[0] || url.substring(0, 60),
        fullUrl: url,
        format,
        sizeBytes: size,
        sizeKB: Math.round(size / 1024 * 100) / 100,
        loadDurationMs,
        status: entry.status,
        failed: entry.failed || false,
        error: entry.errorText || null,
        cacheControl: entry.headers ? entry.headers.cacheControl : null,
        cors: entry.headers ? entry.headers.accessControlAllowOrigin : null
      });
    }

    // Format issues
    const formatIssues = [];
    if (formatStats.ttf) {
      formatIssues.push({
        format: 'TTF',
        count: formatStats.ttf.count,
        totalKB: Math.round(formatStats.ttf.totalBytes / 1024),
        issue: 'TTF fonts are uncompressed. Convert to WOFF2 for 50-70% size reduction.'
      });
    }
    if (formatStats.woff) {
      formatIssues.push({
        format: 'WOFF',
        count: formatStats.woff.count,
        totalKB: Math.round(formatStats.woff.totalBytes / 1024),
        issue: 'WOFF uses gzip compression. WOFF2 uses Brotli for 15-30% better compression.'
      });
    }
    if (formatStats.eot) {
      formatIssues.push({
        format: 'EOT',
        count: formatStats.eot.count,
        totalKB: Math.round(formatStats.eot.totalBytes / 1024),
        issue: 'EOT is IE-only legacy format. Remove and use WOFF2 with WOFF fallback.'
      });
    }

    // Format report with KB
    const formatReport = {};
    for (const [format, stats] of Object.entries(formatStats)) {
      formatReport[format] = {
        count: stats.count,
        totalKB: Math.round(stats.totalBytes / 1024 * 100) / 100
      };
    }

    return {
      totalFontRequests: entries.length,
      totalFontKB: Math.round(totalBytes / 1024 * 100) / 100,
      formatBreakdown: formatReport,
      formatIssues,
      fonts: fontDetails.sort((a, b) => b.sizeBytes - a.sizeBytes),
      failedFonts: fontDetails.filter(f => f.failed)
    };
  }`
})
```

### Step 8 -- Detect Unused Font Declarations

Cross-reference @font-face declarations with actual font usage on the page
to find fonts that are declared but never used.

```javascript
browser_evaluate({
  function: `() => {
    // Get all used font families from computed styles
    const allElements = document.querySelectorAll('*');
    const usedFamilies = new Set();

    for (const el of allElements) {
      const style = window.getComputedStyle(el);
      if (style.display === 'none') continue;

      // Only check elements with text content
      const hasText = Array.from(el.childNodes).some(
        n => n.nodeType === Node.TEXT_NODE && n.textContent.trim().length > 0
      );
      if (!hasText) continue;

      const families = style.fontFamily.split(',').map(f => f.trim().replace(/['"]/g, ''));
      for (const f of families) {
        usedFamilies.add(f.toLowerCase());
      }
    }

    // Get all declared @font-face families
    const declaredFamilies = new Set();
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules) {
          if (rule instanceof CSSFontFaceRule) {
            const family = rule.style.getPropertyValue('font-family').replace(/['"]/g, '').trim();
            declaredFamilies.add(family);
          }
        }
      } catch (e) {
        // Cross-origin stylesheet
      }
    }

    // Find unused
    const unused = [];
    for (const declared of declaredFamilies) {
      if (!usedFamilies.has(declared.toLowerCase())) {
        unused.push(declared);
      }
    }

    return {
      declaredFamilies: Array.from(declaredFamilies),
      usedFamilies: Array.from(usedFamilies).filter(f =>
        // Filter to only custom fonts, not system fonts
        !['serif', 'sans-serif', 'monospace', 'cursive', 'fantasy',
          'system-ui', 'ui-serif', 'ui-sans-serif', 'ui-monospace',
          'arial', 'helvetica', 'times new roman', 'georgia', 'verdana',
          'courier new', 'tahoma', 'trebuchet ms', 'impact',
          '-apple-system', 'blinkmacsystemfont', 'segoe ui'].includes(f.toLowerCase())
      ),
      unusedFonts: unused,
      unusedCount: unused.length,
      issue: unused.length > 0
        ? 'Found ' + unused.length + ' unused @font-face declaration(s). Remove to save bandwidth.'
        : null
    };
  }`
})
```

### Step 9 -- Assess Subsetting Opportunities

Check character usage on the page to identify subsetting opportunities
for fonts that load full character sets.

```javascript
browser_evaluate({
  function: `() => {
    // Collect all unique characters used on the page
    const bodyText = document.body.innerText || '';
    const uniqueChars = new Set(bodyText);

    // Categorize characters
    const categories = {
      basicLatin: 0,        // U+0020-007F (95 chars)
      latin1Supplement: 0,   // U+0080-00FF (128 chars)
      latinExtended: 0,     // U+0100-024F
      cyrillic: 0,          // U+0400-04FF
      greek: 0,             // U+0370-03FF
      cjk: 0,               // U+4E00-9FFF
      arabic: 0,            // U+0600-06FF
      emoji: 0,             // Various ranges
      other: 0
    };

    for (const char of uniqueChars) {
      const code = char.codePointAt(0);
      if (code >= 0x0020 && code <= 0x007F) categories.basicLatin++;
      else if (code >= 0x0080 && code <= 0x00FF) categories.latin1Supplement++;
      else if (code >= 0x0100 && code <= 0x024F) categories.latinExtended++;
      else if (code >= 0x0400 && code <= 0x04FF) categories.cyrillic++;
      else if (code >= 0x0370 && code <= 0x03FF) categories.greek++;
      else if (code >= 0x4E00 && code <= 0x9FFF) categories.cjk++;
      else if (code >= 0x0600 && code <= 0x06FF) categories.arabic++;
      else if (code >= 0x1F600) categories.emoji++;
      else categories.other++;
    }

    const totalUniqueChars = uniqueChars.size;
    const isLatinOnly = categories.cyrillic === 0 && categories.greek === 0
      && categories.cjk === 0 && categories.arabic === 0;

    return {
      totalUniqueCharacters: totalUniqueChars,
      characterCategories: categories,
      isLatinOnly,
      subsettingRecommendation: isLatinOnly && totalUniqueChars < 200
        ? 'Page uses only ' + totalUniqueChars + ' unique Latin characters. Subset fonts to Basic Latin + Latin-1 Supplement for significant size savings (typical 60-80% reduction).'
        : totalUniqueChars < 500
          ? 'Page uses ' + totalUniqueChars + ' unique characters. Consider unicode-range subsetting in @font-face to load only needed character ranges.'
          : 'Page uses ' + totalUniqueChars + ' unique characters across multiple scripts. Full font files may be justified.',
      tip: 'Tools like glyphhanger, subfont, or Google Fonts unicode-range can automate subsetting.'
    };
  }`
})
```

## Interpreting Results

### Report Format

```
## Font Loading Audit -- <page_url>

### Summary
- Font files loaded: 6
- Total font weight: 245 KB
- Formats: 4 WOFF2, 2 WOFF (no legacy TTF/EOT)
- Font families: 3 (Roboto, Roboto Mono, Material Icons)
- font-display set: 4/6 declarations
- Preloaded fonts: 2
- Unused font declarations: 1
- FOIT/FOUT detected: FOUT observed (system font visible at t0, swap at ~800ms)

### font-display Analysis
| Family         | Weight | font-display | Status | Issue                         |
|----------------|--------|-------------- |--------|-------------------------------|
| Roboto         | 400    | swap          | loaded | OK                            |
| Roboto         | 700    | swap          | loaded | OK                            |
| Roboto Mono    | 400    | (not set)     | loaded | MISSING -- defaults to auto (causes FOIT) |
| Material Icons | 400    | block         | loaded | WARN -- block causes 3s FOIT  |

### Font Files
| File              | Format | Size   | Load Time | Cached |
|-------------------|--------|--------|-----------|--------|
| roboto-v30-400.woff2 | WOFF2 | 42 KB | 120 ms | yes |
| roboto-v30-700.woff2 | WOFF2 | 44 KB | 130 ms | yes |
| roboto-mono.woff  | WOFF   | 68 KB  | 150 ms    | no     |
| materialicons.woff2 | WOFF2 | 52 KB | 180 ms   | yes    |

### Preload Validation
1. `roboto-v30-400.woff2` -- preloaded, crossorigin present -- OK
2. `roboto-v30-700.woff2` -- preloaded, missing crossorigin -- WILL BE RE-FETCHED

### Unused Fonts
1. "Roboto Condensed" -- declared in CSS but never used on this page

### Subsetting Opportunity
- Page uses 87 unique Latin characters
- Recommendation: Subset to Basic Latin + Latin-1 for ~60% size reduction
```

### What to Look For

- **Missing font-display**: defaults to `auto` (browser-dependent, often `block`), causing up to 3 seconds of invisible text (FOIT). Set `font-display: swap` for body text, `optional` for non-critical fonts.
- **font-display: block on body text**: causes invisible text for up to 3 seconds while the font loads. Use `swap` instead.
- **WOFF/TTF/EOT instead of WOFF2**: WOFF2 uses Brotli compression for 15-30% smaller files than WOFF (gzip). TTF is uncompressed. EOT is IE-only legacy.
- **Font preload missing crossorigin**: font preloads without `crossorigin` are fetched, then re-fetched with CORS, doubling the download. Always add `crossorigin="anonymous"`.
- **Unused @font-face declarations**: fonts are downloaded even if no text on the page uses them (in some browsers). Remove unused declarations.
- **Large font files (>50KB each)**: consider subsetting to only the character ranges used on the site. Google Fonts does this automatically with `unicode-range`.
- **FOIT in timed screenshots**: compare t0 and t3 screenshots. If text is invisible at t0 but visible at t3, FOIT is occurring. Add `font-display: swap`.
- **FOUT in timed screenshots**: if text at t0 uses a different (system) font than t3, FOUT is occurring. This is generally acceptable and preferred over FOIT.

## Limitations

- **FOIT/FOUT detection is visual**: the timed screenshots show text rendering state but require manual visual comparison. Automated pixel diffing is not included.
- **Screenshot timing is approximate**: the browser may not capture exactly at t=0. Network latency and page complexity affect when the first frame is painted.
- **CDP CSS.enable stylesheet access**: cross-origin stylesheets without CORS headers cannot be inspected. @font-face rules in those stylesheets will be missed.
- **Subsetting analysis checks page text only**: the font may be used on other pages of the site. Subsetting should be done based on site-wide character usage, not a single page.
- **document.fonts API**: reports font faces registered via CSS, but may miss dynamically loaded fonts (e.g., via Font Loading API `new FontFace()`).
- **Chromium-only**: CDP CSS domain and Network domain are Chromium-specific. The `document.fonts` API is cross-browser but has varying completeness.
