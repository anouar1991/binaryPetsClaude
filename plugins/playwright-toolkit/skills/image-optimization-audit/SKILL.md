---
name: image-optimization-audit
description: >
  Analyzes every image on a page: format efficiency (WebP/AVIF vs legacy),
  dimension vs display size ratio, lazy loading correctness, responsive images
  (srcset/sizes/picture), above-fold images that should not be lazy, total
  weight with savings estimate, missing width/height (CLS risk), and broken
  images. Produces an image-by-image report with actionable recommendations.
---

# Image Optimization Audit

Perform a comprehensive audit of every image on the page. Checks format
efficiency, oversized dimensions, lazy loading correctness, responsive markup,
CLS risk from missing dimensions, and broken images. Calculates potential byte
savings from format conversion and dimension optimization.

## When to Use

- Diagnosing slow page loads where images are the primary bottleneck.
- Checking that lazy loading is correctly applied (not on above-fold images).
- Verifying responsive image markup (srcset, sizes, picture) is present.
- Estimating byte savings from converting JPEG/PNG to WebP/AVIF.
- Identifying missing width/height attributes that cause layout shifts.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP Network domain and full image introspection.
- Target page must be reachable from the browser instance.

## Workflow

### Step 1 -- Set Up Network Monitoring via CDP

Enable CDP Network monitoring before navigation to capture image transfer
sizes and content types.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');

    const imageRequests = {};

    client.on('Network.responseReceived', (params) => {
      const url = params.response.url;
      const mimeType = params.response.mimeType || '';
      if (mimeType.startsWith('image/') || params.type === 'Image') {
        imageRequests[params.requestId] = {
          url,
          mimeType,
          status: params.response.status,
          protocol: params.response.protocol,
          headers: {
            contentLength: params.response.headers['content-length'] || null,
            contentType: params.response.headers['content-type'] || null,
            cacheControl: params.response.headers['cache-control'] || null
          }
        };
      }
    });

    client.on('Network.loadingFinished', (params) => {
      if (imageRequests[params.requestId]) {
        imageRequests[params.requestId].encodedDataLength = params.encodedDataLength;
      }
    });

    client.on('Network.loadingFailed', (params) => {
      if (imageRequests[params.requestId]) {
        imageRequests[params.requestId].failed = true;
        imageRequests[params.requestId].errorText = params.errorText;
      }
    });

    page.__imageRequests = imageRequests;
    page.__cdpClient = client;

    return 'Image network monitoring enabled';
  }`
})
```

### Step 2 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

Wait for images to load (including lazy-loaded ones triggered by scroll):

```
browser_wait_for({ time: 3 })
```

### Step 3 -- Scroll to Trigger Lazy-Loaded Images

Scroll through the page to trigger lazy-loaded images, then wait for them
to load.

```javascript
browser_evaluate({
  function: `() => {
    return new Promise((resolve) => {
      const totalHeight = document.documentElement.scrollHeight;
      const viewportHeight = window.innerHeight;
      let currentPosition = 0;
      const step = viewportHeight * 0.8;

      const scrollInterval = setInterval(() => {
        currentPosition += step;
        window.scrollTo(0, currentPosition);

        if (currentPosition >= totalHeight) {
          clearInterval(scrollInterval);
          // Scroll back to top
          window.scrollTo(0, 0);
          resolve('Scrolled through entire page, height: ' + totalHeight + 'px');
        }
      }, 200);
    });
  }`
})
```

```
browser_wait_for({ time: 3 })
```

### Step 4 -- Enumerate All Images with Full Attributes

Collect comprehensive data for every image element on the page.

```javascript
browser_evaluate({
  function: `() => {
    const images = document.querySelectorAll('img');
    const pictureElements = document.querySelectorAll('picture');
    const results = [];

    for (const img of images) {
      const rect = img.getBoundingClientRect();
      const style = window.getComputedStyle(img);

      // Check if image is in a <picture> element
      const inPicture = img.parentElement && img.parentElement.tagName === 'PICTURE';
      let pictureSources = [];
      if (inPicture) {
        const sources = img.parentElement.querySelectorAll('source');
        for (const source of sources) {
          pictureSources.push({
            srcset: source.srcset || null,
            sizes: source.sizes || null,
            type: source.type || null,
            media: source.media || null
          });
        }
      }

      results.push({
        src: img.src || null,
        currentSrc: img.currentSrc || null,
        srcset: img.srcset || null,
        sizes: img.sizes || null,
        alt: img.alt,
        hasAlt: img.hasAttribute('alt'),
        loading: img.loading || 'auto',
        decoding: img.decoding || 'auto',
        fetchpriority: img.fetchPriority || null,
        hasWidthAttr: img.hasAttribute('width'),
        hasHeightAttr: img.hasAttribute('height'),
        widthAttr: img.getAttribute('width'),
        heightAttr: img.getAttribute('height'),
        naturalWidth: img.naturalWidth,
        naturalHeight: img.naturalHeight,
        displayWidth: Math.round(rect.width),
        displayHeight: Math.round(rect.height),
        isVisible: style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0,
        isComplete: img.complete,
        isBroken: img.complete && img.naturalWidth === 0 && img.src,
        inPicture,
        pictureSources,
        cssObjectFit: style.objectFit,
        cssAspectRatio: style.aspectRatio,
        top: Math.round(rect.top + window.scrollY),
        left: Math.round(rect.left)
      });
    }

    // Also check CSS background images on key elements
    const bgImages = [];
    const elements = document.querySelectorAll('[style*="background-image"], .hero, .banner, .jumbotron, header, section');
    for (const el of elements) {
      const bg = window.getComputedStyle(el).backgroundImage;
      if (bg && bg !== 'none') {
        const urls = bg.match(/url\(["']?([^"')]+)["']?\)/g);
        if (urls) {
          for (const u of urls) {
            const match = u.match(/url\(["']?([^"')]+)["']?\)/);
            if (match) {
              bgImages.push({
                element: el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/)[0] : ''),
                url: match[1],
                elementWidth: Math.round(el.getBoundingClientRect().width),
                elementHeight: Math.round(el.getBoundingClientRect().height)
              });
            }
          }
        }
      }
    }

    return {
      totalImages: images.length,
      totalPictureElements: pictureElements.length,
      images: results,
      cssBackgroundImages: bgImages.slice(0, 20)
    };
  }`
})
```

### Step 5 -- Detect Above-Fold Images

Identify which images are above the fold (visible in the initial viewport
without scrolling) to check lazy loading correctness.

```javascript
browser_evaluate({
  function: `() => {
    const viewportHeight = window.innerHeight;
    const images = document.querySelectorAll('img');
    const aboveFold = [];
    const belowFold = [];

    for (const img of images) {
      const rect = img.getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) continue;

      const entry = {
        src: (img.src || '').split('/').pop().substring(0, 50),
        top: Math.round(rect.top),
        loading: img.loading || 'auto',
        fetchpriority: img.fetchPriority || null,
        displayWidth: Math.round(rect.width),
        displayHeight: Math.round(rect.height)
      };

      // Image is above fold if its top edge is within the viewport
      if (rect.top < viewportHeight && rect.bottom > 0) {
        aboveFold.push(entry);
      } else {
        belowFold.push(entry);
      }
    }

    // Identify issues
    const issues = [];
    for (const img of aboveFold) {
      if (img.loading === 'lazy') {
        issues.push({
          src: img.src,
          issue: 'Above-fold image has loading="lazy" -- delays LCP. Remove lazy or add fetchpriority="high".'
        });
      }
    }
    for (const img of belowFold) {
      if (img.loading !== 'lazy') {
        issues.push({
          src: img.src,
          issue: 'Below-fold image missing loading="lazy" -- wastes bandwidth on initial load.'
        });
      }
    }

    return {
      viewportHeight,
      aboveFoldCount: aboveFold.length,
      belowFoldCount: belowFold.length,
      aboveFold,
      belowFold: belowFold.slice(0, 20),
      lazyLoadingIssues: issues
    };
  }`
})
```

### Step 6 -- Collect Network Transfer Data for Images

Retrieve the actual transfer sizes and content types from CDP network data.

```javascript
browser_run_code({
  code: `async (page) => {
    const imageRequests = page.__imageRequests || {};
    const entries = Object.values(imageRequests);

    // Format analysis
    const formatStats = {};
    let totalBytes = 0;
    let estimatedWebPSavings = 0;
    let estimatedAVIFSavings = 0;

    for (const entry of entries) {
      if (entry.failed) continue;
      const size = entry.encodedDataLength || 0;
      totalBytes += size;

      const mime = (entry.mimeType || '').toLowerCase();
      let format = 'unknown';
      if (mime.includes('jpeg') || mime.includes('jpg')) format = 'jpeg';
      else if (mime.includes('png')) format = 'png';
      else if (mime.includes('gif')) format = 'gif';
      else if (mime.includes('webp')) format = 'webp';
      else if (mime.includes('avif')) format = 'avif';
      else if (mime.includes('svg')) format = 'svg';
      else if (mime.includes('ico')) format = 'ico';

      if (!formatStats[format]) {
        formatStats[format] = { count: 0, totalBytes: 0 };
      }
      formatStats[format].count++;
      formatStats[format].totalBytes += size;

      // Estimate savings from converting to modern formats
      // WebP is typically 25-35% smaller than JPEG, 26% smaller than PNG
      // AVIF is typically 50% smaller than JPEG
      if (format === 'jpeg') {
        estimatedWebPSavings += size * 0.30;
        estimatedAVIFSavings += size * 0.50;
      } else if (format === 'png') {
        estimatedWebPSavings += size * 0.26;
        estimatedAVIFSavings += size * 0.45;
      } else if (format === 'gif') {
        estimatedWebPSavings += size * 0.20;
        estimatedAVIFSavings += size * 0.40;
      }
    }

    // Format stats with KB
    const formatReport = {};
    for (const [format, stats] of Object.entries(formatStats)) {
      formatReport[format] = {
        count: stats.count,
        totalKB: Math.round(stats.totalBytes / 1024 * 100) / 100
      };
    }

    // Broken/failed images
    const brokenImages = entries
      .filter(e => e.failed || (e.status && e.status >= 400))
      .map(e => ({
        url: e.url,
        status: e.status || null,
        error: e.errorText || null
      }));

    return {
      totalImageRequests: entries.length,
      totalImageKB: Math.round(totalBytes / 1024 * 100) / 100,
      totalImageMB: Math.round(totalBytes / 1024 / 1024 * 100) / 100,
      formatBreakdown: formatReport,
      estimatedSavings: {
        webpSavingsKB: Math.round(estimatedWebPSavings / 1024),
        avifSavingsKB: Math.round(estimatedAVIFSavings / 1024),
        note: 'Estimated savings from converting JPEG/PNG/GIF to modern formats'
      },
      brokenImages,
      uncachedImages: entries
        .filter(e => !e.failed && (!e.headers.cacheControl || e.headers.cacheControl.includes('no-cache') || e.headers.cacheControl.includes('no-store')))
        .map(e => ({ url: (e.url || '').substring(0, 80), cacheControl: e.headers.cacheControl }))
        .slice(0, 10)
    };
  }`
})
```

### Step 7 -- Analyze Dimension Efficiency

Compare natural image dimensions against their display size to identify
oversized images that waste bandwidth.

```javascript
browser_evaluate({
  function: `() => {
    const images = document.querySelectorAll('img');
    const oversized = [];
    let totalWastedPixels = 0;

    for (const img of images) {
      if (!img.complete || img.naturalWidth === 0) continue;
      const rect = img.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) continue;

      const displayWidth = Math.round(rect.width);
      const displayHeight = Math.round(rect.height);
      const dpr = window.devicePixelRatio || 1;

      // Account for device pixel ratio -- serving 2x is acceptable for retina
      const optimalWidth = Math.ceil(displayWidth * dpr);
      const optimalHeight = Math.ceil(displayHeight * dpr);

      const widthRatio = img.naturalWidth / optimalWidth;
      const heightRatio = img.naturalHeight / optimalHeight;
      const overallRatio = Math.max(widthRatio, heightRatio);

      // Flag if image is more than 1.5x the needed size (accounting for DPR)
      if (overallRatio > 1.5 && img.naturalWidth > 100) {
        const wastedPixels = (img.naturalWidth * img.naturalHeight) - (optimalWidth * optimalHeight);
        totalWastedPixels += wastedPixels;

        oversized.push({
          src: (img.src || '').split('/').pop().substring(0, 50),
          naturalSize: img.naturalWidth + 'x' + img.naturalHeight,
          displaySize: displayWidth + 'x' + displayHeight,
          optimalSize: optimalWidth + 'x' + optimalHeight + ' (@' + dpr + 'x)',
          oversizeRatio: Math.round(overallRatio * 100) / 100 + 'x',
          wastedPixels: wastedPixels,
          estimatedSavingsPercent: Math.round((1 - 1 / (overallRatio * overallRatio)) * 100) + '%'
        });
      }
    }

    oversized.sort((a, b) => b.wastedPixels - a.wastedPixels);

    return {
      devicePixelRatio: window.devicePixelRatio,
      oversizedCount: oversized.length,
      totalWastedMegapixels: Math.round(totalWastedPixels / 1000000 * 100) / 100,
      oversizedImages: oversized.slice(0, 20)
    };
  }`
})
```

### Step 8 -- Check CLS Risk from Missing Dimensions

Identify images missing explicit width/height attributes or CSS aspect-ratio,
which cause layout shifts when the image loads.

```javascript
browser_evaluate({
  function: `() => {
    const images = document.querySelectorAll('img');
    const clsRisk = [];

    for (const img of images) {
      const rect = img.getBoundingClientRect();
      if (rect.width === 0 && rect.height === 0) continue;

      const hasWidth = img.hasAttribute('width');
      const hasHeight = img.hasAttribute('height');
      const style = window.getComputedStyle(img);
      const hasAspectRatio = style.aspectRatio && style.aspectRatio !== 'auto';
      const hasCSSDimensions = style.width !== 'auto' && style.height !== 'auto'
        && !style.width.includes('%') && !style.height.includes('%');

      const hasDimensions = (hasWidth && hasHeight) || hasAspectRatio || hasCSSDimensions;

      if (!hasDimensions) {
        clsRisk.push({
          src: (img.src || '').split('/').pop().substring(0, 50),
          hasWidthAttr: hasWidth,
          hasHeightAttr: hasHeight,
          cssAspectRatio: style.aspectRatio,
          cssWidth: style.width,
          cssHeight: style.height,
          naturalSize: img.naturalWidth + 'x' + img.naturalHeight,
          displaySize: Math.round(rect.width) + 'x' + Math.round(rect.height),
          issue: 'Missing explicit dimensions -- causes layout shift when image loads',
          fix: 'Add width="' + img.naturalWidth + '" height="' + img.naturalHeight + '" attributes, or use CSS aspect-ratio'
        });
      }
    }

    return {
      totalImages: images.length,
      missingDimensionsCount: clsRisk.length,
      clsRiskImages: clsRisk.slice(0, 20)
    };
  }`
})
```

### Step 9 -- Capture Screenshot with Oversized Images Highlighted

Highlight oversized images on the page and take a screenshot for reference.

```javascript
browser_evaluate({
  function: `() => {
    const images = document.querySelectorAll('img');
    let highlighted = 0;
    const dpr = window.devicePixelRatio || 1;

    for (const img of images) {
      if (!img.complete || img.naturalWidth === 0) continue;
      const rect = img.getBoundingClientRect();
      if (rect.width === 0) continue;

      const optimalWidth = Math.ceil(rect.width * dpr);
      const ratio = img.naturalWidth / optimalWidth;

      if (ratio > 1.5 && img.naturalWidth > 100) {
        img.style.outline = '4px solid red';
        img.style.outlineOffset = '2px';
        img.title = 'OVERSIZED: ' + img.naturalWidth + 'x' + img.naturalHeight
          + ' displayed at ' + Math.round(rect.width) + 'x' + Math.round(rect.height)
          + ' (' + Math.round(ratio * 100) / 100 + 'x too large)';
        highlighted++;
      }
    }

    return 'Highlighted ' + highlighted + ' oversized images with red outlines';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "image-audit-oversized.png" })
```

Clean up highlights:

```javascript
browser_evaluate({
  function: `() => {
    const images = document.querySelectorAll('img');
    for (const img of images) {
      img.style.outline = '';
      img.style.outlineOffset = '';
    }
    return 'Highlights removed';
  }`
})
```

## Interpreting Results

### Report Format

```
## Image Optimization Audit -- <page_url>

### Summary
- Total images: 24 (18 <img>, 3 <picture>, 3 CSS background)
- Total image weight: 2.4 MB
- Modern formats (WebP/AVIF): 8/24 (33%)
- Oversized images: 6 (serving 2-4x needed pixels)
- Missing lazy loading (below fold): 9
- Lazy loading on above-fold images: 1 (LCP risk)
- Missing width/height (CLS risk): 4
- Broken images: 1

### Estimated Savings
| Action               | Savings  |
|----------------------|----------|
| Convert to WebP      | ~420 KB  |
| Convert to AVIF      | ~680 KB  |
| Resize oversized     | ~850 KB  |
| Total potential       | ~1.1 MB (46% reduction) |

### Format Breakdown
| Format | Count | Weight  |
|--------|-------|---------|
| JPEG   | 12    | 1.6 MB  |
| PNG    | 5     | 520 KB  |
| WebP   | 4     | 180 KB  |
| SVG    | 2     | 12 KB   |
| GIF    | 1     | 89 KB   |

### Issues Detail

#### Oversized Images (top 5)
| Image              | Natural     | Display   | Optimal (@2x) | Ratio |
|--------------------|-------------|-----------|----------------|-------|
| hero-banner.jpg    | 3840x2160   | 1440x810  | 2880x1620      | 1.3x  |
| team-photo.jpg     | 4000x3000   | 400x300   | 800x600        | 5.0x  |
| product-thumb.png  | 1200x1200   | 150x150   | 300x300        | 4.0x  |

#### Lazy Loading Issues
1. `hero-banner.jpg` -- above fold with loading="lazy" (delays LCP)
2. `product-1.jpg` -- below fold without loading="lazy"

#### CLS Risk (Missing Dimensions)
1. `blog-image-3.jpg` -- no width/height, natural 800x600, display 400x300
   Fix: Add width="800" height="600"
```

### What to Look For

- **Legacy formats (JPEG/PNG) dominating**: use `<picture>` with WebP/AVIF sources and JPEG fallback to reduce weight by 25-50%.
- **Above-fold images with loading="lazy"**: this delays LCP because the browser waits for layout before fetching. Remove `loading="lazy"` and add `fetchpriority="high"` for the LCP image.
- **Below-fold images without loading="lazy"**: these waste bandwidth on initial load. Add `loading="lazy"` to defer fetching until the user scrolls near them.
- **Oversized images (>1.5x display size at DPR)**: serve correctly sized images via srcset or server-side resizing. A 4000px image displayed at 400px wastes 99% of its pixels.
- **Missing width/height**: causes Cumulative Layout Shift. Add explicit dimensions matching the image aspect ratio, or use CSS `aspect-ratio`.
- **Broken images (naturalWidth === 0)**: the image failed to load. Check the URL, CDN, and CORS configuration.

## Limitations

- **Savings estimates are approximate**: actual WebP/AVIF compression depends on image content. Estimates use industry averages (30% for WebP over JPEG, 50% for AVIF).
- **CSS background images**: detected but not fully analyzed for dimensions or lazy loading since they lack `<img>` attributes.
- **Lazy loading detection relies on attributes**: custom lazy loading via JavaScript (IntersectionObserver without `loading="lazy"`) is not detected by attribute scanning.
- **Above-fold detection uses current viewport**: the fold position depends on viewport size. Results are for the current browser dimensions.
- **Transfer sizes require CDP**: network transfer sizes come from CDP Network domain. If CDP is unavailable, only DOM-level attributes are reported.
