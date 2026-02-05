---
name: audit-page
description: "Full quality audit before launch: security headers, SEO, images, fonts, PWA readiness, and accessibility in a single orchestrated pass."
user_invocable: true
arguments:
  - name: url
    description: "The URL to audit"
    required: true
---

# Full Page Audit Orchestrator

You are performing a **comprehensive quality audit** that orchestrates multiple audit skills simultaneously in a single browser session. The goal is to produce a launch-readiness report covering security, SEO, images, fonts, PWA, and accessibility.

**Skills orchestrated:** security-audit, seo-audit, image-optimization-audit, font-loading-audit, pwa-audit, accessibility-journey

## Orchestration Strategy

Enable all CDP domains and install all observers in one pass, navigate once, then extract all audit data from the DOM and network in parallel. This avoids redundant page loads and gives a consistent snapshot of the page state.

## Phase 1: Enable CDP Domains and Install Instrumentation (Single browser_run_code)

### Step 1 — CDP Session Setup

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    globalThis.__auditData = {
      security: { headers: {}, cookies: [] },
      network: { requests: [], fonts: [], images: [], thirdParty: [] },
      serviceWorker: { registered: false, scope: null }
    };

    // === Enable CDP Domains ===
    await client.send('Network.enable');
    await client.send('Security.enable');
    await client.send('CSS.enable');
    await client.send('ServiceWorker.enable');

    // === Track Security State ===
    client.on('Security.securityStateChanged', (params) => {
      globalThis.__auditData.security.state = params.summary;
      globalThis.__auditData.security.protocol = params.explanations?.find(e => e.securityState === 'secure')?.description;
    });

    // === Track Network Requests (fonts, images, third-party) ===
    const requests = new Map();

    client.on('Network.requestWillBeSent', (params) => {
      requests.set(params.requestId, {
        url: params.request.url,
        method: params.request.method,
        type: params.type,
        initiator: params.initiator?.type
      });
    });

    client.on('Network.responseReceived', (params) => {
      const req = requests.get(params.requestId);
      if (!req) return;

      req.status = params.response.status;
      req.mimeType = params.response.mimeType;
      req.headers = params.response.headers;
      req.encodedDataLength = params.response.encodedDataLength;
      req.protocol = params.response.protocol;

      // Capture main document security headers
      if (params.type === 'Document') {
        globalThis.__auditData.security.headers = params.response.headers;
      }

      // Track fonts
      if (params.type === 'Font' || params.response.mimeType?.includes('font')) {
        globalThis.__auditData.network.fonts.push({
          url: req.url,
          mimeType: params.response.mimeType,
          size: params.response.encodedDataLength,
          headers: {
            cacheControl: params.response.headers['cache-control'] || params.response.headers['Cache-Control'],
            fontDisplay: null  // Will be extracted from CSS
          }
        });
      }

      // Track images
      if (params.type === 'Image') {
        globalThis.__auditData.network.images.push({
          url: req.url,
          mimeType: params.response.mimeType,
          size: params.response.encodedDataLength
        });
      }

      // Track third-party requests
      const pageHost = new URL(page.url()).hostname;
      try {
        const reqHost = new URL(req.url).hostname;
        if (reqHost !== pageHost && !reqHost.endsWith('.' + pageHost)) {
          globalThis.__auditData.network.thirdParty.push({
            url: req.url,
            host: reqHost,
            type: params.type,
            size: params.response.encodedDataLength,
            blocking: params.type === 'Script' && req.initiator !== 'script'
          });
        }
      } catch(e) {}

      globalThis.__auditData.network.requests.push(req);
    });

    // === Track Service Workers ===
    client.on('ServiceWorker.workerRegistrationUpdated', (params) => {
      if (params.registrations?.length > 0) {
        globalThis.__auditData.serviceWorker.registered = true;
        globalThis.__auditData.serviceWorker.scope = params.registrations[0].scopeURL;
      }
    });

    globalThis.__auditCDP = { client, requests };

    return 'Audit instrumentation installed: Security + Network + CSS + ServiceWorker';
  }`
})
```

## Phase 2: Navigate and Wait

### Step 1 — Navigate to the target URL

```
browser_navigate({ url: "<TARGET_URL>" })
```

### Step 2 — Wait for full load

```
browser_wait_for({ time: 3 })
```

## Phase 3: DOM Analysis (Single browser_evaluate)

Extract all audit data from the DOM in one call:

```javascript
browser_evaluate({
  function: `() => {
    const result = {};

    // ============================================
    // SEO AUDIT
    // ============================================
    const seo = {};

    // Title
    const title = document.querySelector('title');
    seo.title = {
      text: title?.textContent || null,
      length: title?.textContent?.length || 0,
      present: !!title?.textContent
    };

    // Meta description
    const desc = document.querySelector('meta[name="description"]');
    seo.description = {
      text: desc?.content || null,
      length: desc?.content?.length || 0,
      present: !!desc?.content
    };

    // Canonical
    const canonical = document.querySelector('link[rel="canonical"]');
    seo.canonical = {
      href: canonical?.href || null,
      present: !!canonical,
      matchesUrl: canonical?.href === window.location.href
    };

    // Viewport
    const viewport = document.querySelector('meta[name="viewport"]');
    seo.viewport = {
      content: viewport?.content || null,
      present: !!viewport,
      hasDeviceWidth: viewport?.content?.includes('device-width') || false,
      blocksZoom: viewport?.content?.includes('maximum-scale=1') || viewport?.content?.includes('user-scalable=no') || false
    };

    // Open Graph
    const ogTags = ['og:title', 'og:description', 'og:image', 'og:url', 'og:type', 'og:site_name'];
    seo.openGraph = {};
    ogTags.forEach(tag => {
      const el = document.querySelector('meta[property="' + tag + '"]');
      seo.openGraph[tag] = el?.content || null;
    });

    // Twitter Card
    const twTags = ['twitter:card', 'twitter:title', 'twitter:description', 'twitter:image'];
    seo.twitterCard = {};
    twTags.forEach(tag => {
      const el = document.querySelector('meta[name="' + tag + '"]');
      seo.twitterCard[tag] = el?.content || null;
    });

    // Headings
    const headings = [];
    document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(h => {
      headings.push({ level: parseInt(h.tagName[1]), text: h.textContent.trim().substring(0, 80) });
    });
    seo.headings = {
      list: headings,
      h1Count: headings.filter(h => h.level === 1).length,
      hasSkippedLevels: false
    };
    // Check for skipped levels
    for (let i = 1; i < headings.length; i++) {
      if (headings[i].level > headings[i-1].level + 1) {
        seo.headings.hasSkippedLevels = true;
        break;
      }
    }

    // Robots
    const robotsMeta = document.querySelector('meta[name="robots"]');
    seo.robots = {
      content: robotsMeta?.content || null,
      noindex: robotsMeta?.content?.includes('noindex') || false,
      nofollow: robotsMeta?.content?.includes('nofollow') || false
    };

    // Structured data
    const jsonLdScripts = document.querySelectorAll('script[type="application/ld+json"]');
    seo.structuredData = [];
    jsonLdScripts.forEach(script => {
      try {
        const data = JSON.parse(script.textContent);
        seo.structuredData.push({
          type: data['@type'] || 'unknown',
          context: data['@context'] || null,
          valid: true,
          keys: Object.keys(data)
        });
      } catch(e) {
        seo.structuredData.push({ valid: false, error: e.message });
      }
    });

    result.seo = seo;

    // ============================================
    // IMAGE AUDIT
    // ============================================
    const images = [];
    document.querySelectorAll('img').forEach(img => {
      const rect = img.getBoundingClientRect();
      images.push({
        src: img.src?.substring(0, 200),
        alt: img.alt,
        hasAlt: img.hasAttribute('alt'),
        altEmpty: img.alt === '',
        width: img.naturalWidth,
        height: img.naturalHeight,
        displayWidth: rect.width,
        displayHeight: rect.height,
        hasWidthHeight: img.hasAttribute('width') && img.hasAttribute('height'),
        loading: img.loading || 'eager',
        fetchpriority: img.fetchPriority || null,
        hasSrcset: !!img.srcset,
        isAboveFold: rect.top < window.innerHeight,
        format: img.src?.split('.').pop()?.split('?')[0]?.toLowerCase() || 'unknown',
        inPicture: img.parentElement?.tagName === 'PICTURE',
        hasWebPSource: img.parentElement?.tagName === 'PICTURE' ?
          !!img.parentElement.querySelector('source[type="image/webp"]') : false,
        hasAvifSource: img.parentElement?.tagName === 'PICTURE' ?
          !!img.parentElement.querySelector('source[type="image/avif"]') : false
      });
    });
    result.images = {
      list: images,
      total: images.length,
      missingAlt: images.filter(i => !i.hasAlt).length,
      missingDimensions: images.filter(i => !i.hasWidthHeight).length,
      lazyAboveFold: images.filter(i => i.isAboveFold && i.loading === 'lazy').length,
      withoutModernFormat: images.filter(i => !i.inPicture && !['webp', 'avif', 'svg'].includes(i.format)).length
    };

    // ============================================
    // FONT AUDIT (CSS analysis)
    // ============================================
    const fontFaces = [];
    for (const sheet of document.styleSheets) {
      try {
        for (const rule of sheet.cssRules) {
          if (rule instanceof CSSFontFaceRule) {
            fontFaces.push({
              family: rule.style.getPropertyValue('font-family').replace(/['"]/g, ''),
              display: rule.style.getPropertyValue('font-display') || 'auto',
              src: rule.style.getPropertyValue('src')?.substring(0, 200),
              weight: rule.style.getPropertyValue('font-weight'),
              style: rule.style.getPropertyValue('font-style')
            });
          }
        }
      } catch(e) { /* cross-origin stylesheet */ }
    }

    // Check preloaded fonts
    const preloadedFonts = [];
    document.querySelectorAll('link[rel="preload"][as="font"]').forEach(link => {
      preloadedFonts.push({
        href: link.href,
        crossorigin: link.crossOrigin,
        type: link.type
      });
    });

    result.fonts = {
      fontFaces,
      preloadedFonts,
      totalFontFaces: fontFaces.length,
      withoutFontDisplay: fontFaces.filter(f => f.display === 'auto' || !f.display).length,
      usingSwap: fontFaces.filter(f => f.display === 'swap').length,
      usingOptional: fontFaces.filter(f => f.display === 'optional').length
    };

    // ============================================
    // PWA AUDIT (manifest and service worker check)
    // ============================================
    const manifest = document.querySelector('link[rel="manifest"]');
    const themeColor = document.querySelector('meta[name="theme-color"]');
    const appleTouchIcon = document.querySelector('link[rel="apple-touch-icon"]');

    result.pwa = {
      hasManifest: !!manifest,
      manifestHref: manifest?.href || null,
      hasThemeColor: !!themeColor,
      themeColor: themeColor?.content || null,
      hasAppleTouchIcon: !!appleTouchIcon,
      appleTouchIconHref: appleTouchIcon?.href || null,
      isHttps: window.location.protocol === 'https:'
    };

    // ============================================
    // FORM ACCESSIBILITY (quick check)
    // ============================================
    const forms = [];
    document.querySelectorAll('form').forEach(form => {
      const inputs = form.querySelectorAll('input, select, textarea');
      const unlabeled = [];
      inputs.forEach(input => {
        if (input.type === 'hidden' || input.type === 'submit') return;
        const hasLabel = input.labels?.length > 0 || input.getAttribute('aria-label') || input.getAttribute('aria-labelledby');
        if (!hasLabel) unlabeled.push({ tag: input.tagName, type: input.type, name: input.name });
      });
      forms.push({ action: form.action, method: form.method, inputCount: inputs.length, unlabeledInputs: unlabeled });
    });
    result.forms = forms;

    // ============================================
    // LANG AND DOCTYPE
    // ============================================
    result.html = {
      lang: document.documentElement.lang || null,
      hasLang: !!document.documentElement.lang,
      doctype: document.doctype ? document.doctype.name : null,
      charset: document.characterSet
    };

    return result;
  }`
})
```

## Phase 4: Security Headers Analysis

Extract the security headers captured during navigation:

```javascript
browser_run_code({
  code: `async (page) => {
    const headers = globalThis.__auditData.security.headers;
    const h = (name) => headers[name] || headers[name.toLowerCase()] || null;

    const securityAnalysis = {
      csp: {
        present: !!h('Content-Security-Policy'),
        value: h('Content-Security-Policy')?.substring(0, 500),
        hasUnsafeEval: h('Content-Security-Policy')?.includes("'unsafe-eval'") || false,
        hasUnsafeInline: h('Content-Security-Policy')?.includes("'unsafe-inline'") || false
      },
      hsts: {
        present: !!h('Strict-Transport-Security'),
        value: h('Strict-Transport-Security'),
        maxAge: parseInt(h('Strict-Transport-Security')?.match(/max-age=(\\d+)/)?.[1] || '0'),
        includeSubDomains: h('Strict-Transport-Security')?.includes('includeSubDomains') || false,
        preload: h('Strict-Transport-Security')?.includes('preload') || false
      },
      xFrameOptions: {
        present: !!h('X-Frame-Options'),
        value: h('X-Frame-Options')
      },
      xContentTypeOptions: {
        present: !!h('X-Content-Type-Options'),
        value: h('X-Content-Type-Options')
      },
      referrerPolicy: {
        present: !!h('Referrer-Policy'),
        value: h('Referrer-Policy')
      },
      permissionsPolicy: {
        present: !!h('Permissions-Policy'),
        value: h('Permissions-Policy')?.substring(0, 300)
      },
      coop: h('Cross-Origin-Opener-Policy'),
      corp: h('Cross-Origin-Resource-Policy'),
      coep: h('Cross-Origin-Embedder-Policy')
    };

    // Get cookies
    const client = globalThis.__auditCDP.client;
    const { cookies } = await client.send('Network.getCookies');
    securityAnalysis.cookies = cookies.map(c => ({
      name: c.name,
      domain: c.domain,
      secure: c.secure,
      httpOnly: c.httpOnly,
      sameSite: c.sameSite,
      issues: [
        !c.secure ? 'Missing Secure flag' : null,
        !c.httpOnly && c.name.toLowerCase().includes('session') ? 'Session cookie without HttpOnly' : null,
        c.sameSite === 'None' && !c.secure ? 'SameSite=None without Secure' : null,
        !c.sameSite || c.sameSite === '' ? 'Missing SameSite attribute' : null
      ].filter(Boolean)
    }));

    return securityAnalysis;
  }`
})
```

## Phase 5: PWA Manifest Fetch and Service Worker Test

### Step 1 — Fetch and validate manifest (if present)

If the DOM audit found a manifest link, fetch and parse it:

```javascript
browser_evaluate({
  function: `() => {
    const manifestLink = document.querySelector('link[rel="manifest"]');
    if (!manifestLink) return { hasManifest: false };

    return fetch(manifestLink.href)
      .then(r => r.json())
      .then(manifest => ({
        hasManifest: true,
        name: manifest.name,
        shortName: manifest.short_name,
        startUrl: manifest.start_url,
        display: manifest.display,
        backgroundColor: manifest.background_color,
        themeColor: manifest.theme_color,
        icons: manifest.icons?.map(i => ({ src: i.src, sizes: i.sizes, type: i.type })) || [],
        hasRequiredFields: !!(manifest.name && manifest.start_url && manifest.display && manifest.icons?.length > 0),
        has192Icon: manifest.icons?.some(i => i.sizes?.includes('192x192')) || false,
        has512Icon: manifest.icons?.some(i => i.sizes?.includes('512x512')) || false
      }))
      .catch(e => ({ hasManifest: true, fetchError: e.message }));
  }`
})
```

### Step 2 — Check service worker registration

```javascript
browser_evaluate({
  function: `() => {
    if (!navigator.serviceWorker) return { supported: false };
    return navigator.serviceWorker.getRegistration().then(reg => ({
      supported: true,
      registered: !!reg,
      scope: reg?.scope || null,
      active: reg?.active?.state || null,
      waiting: reg?.waiting?.state || null
    })).catch(e => ({ supported: true, error: e.message }));
  }`
})
```

## Phase 6: Accessibility Journey (Tab Navigation)

Test keyboard navigation through the page's interactive elements:

```javascript
browser_run_code({
  code: `async (page) => {
    const focusableElements = [];
    const maxTabs = 30;

    for (let i = 0; i < maxTabs; i++) {
      await page.keyboard.press('Tab');
      const info = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName,
          role: el.getAttribute('role'),
          text: (el.textContent || el.getAttribute('aria-label') || el.title || '').trim().substring(0, 50),
          tabIndex: el.tabIndex,
          hasVisibleFocus: (() => {
            const styles = getComputedStyle(el);
            return styles.outlineStyle !== 'none' || styles.boxShadow !== 'none';
          })(),
          isVisible: rect.width > 0 && rect.height > 0,
          isInViewport: rect.top >= 0 && rect.top < window.innerHeight
        };
      });

      if (!info) break;
      focusableElements.push(info);

      // Stop if we've looped back to the first element
      if (focusableElements.length > 2 &&
          info.tag === focusableElements[0].tag &&
          info.text === focusableElements[0].text) break;
    }

    return {
      focusableCount: focusableElements.length,
      withoutVisibleFocus: focusableElements.filter(e => !e.hasVisibleFocus).length,
      hiddenElements: focusableElements.filter(e => !e.isVisible).length,
      elements: focusableElements
    };
  }`
})
```

## Phase 7: Take Final Screenshots

```
browser_take_screenshot({ type: "png", fullPage: true })
browser_snapshot()
```

## Phase 8: Report

Compile all data into a comprehensive audit report with per-category grades. Use the reference files for grading criteria:

- `skills/security-audit/references/security-headers.md` for security grading
- `skills/seo-audit/references/seo-checklist.md` for SEO grading
- `skills/image-optimization-audit/references/image-formats.md` for image grading

```markdown
# Full Page Audit: <URL>

## Overall Grade: [A-F] (weighted average)

| Category | Grade | Score | Key Issues |
|----------|-------|-------|-----------|
| Security | X | NN/100 | ... |
| SEO | X | NN/100 | ... |
| Images | X | NN/100 | ... |
| Fonts | X | NN/100 | ... |
| PWA | X | NN/100 | ... |
| Accessibility | X | NN/100 | ... |

---

## Security Audit (Grade: X)

### Headers
| Header | Status | Value |
|--------|--------|-------|
| Content-Security-Policy | Present/Missing | ... |
| Strict-Transport-Security | Present/Missing | ... |
| X-Frame-Options | Present/Missing | ... |
| X-Content-Type-Options | Present/Missing | ... |
| Referrer-Policy | Present/Missing | ... |
| Permissions-Policy | Present/Missing | ... |

### Cookie Security
| Cookie | HttpOnly | Secure | SameSite | Issues |
|--------|----------|--------|----------|--------|
...

---

## SEO Audit (Grade: X)

### Meta Tags
| Tag | Status | Value |
|-----|--------|-------|
| Title | ... | ... |
| Description | ... | ... |
| Canonical | ... | ... |
| Viewport | ... | ... |

### Open Graph: [Complete/Partial/Missing]
### Twitter Card: [Complete/Partial/Missing]
### Heading Hierarchy: [Valid/Issues Found]
### Structured Data: [Valid/Invalid/Missing]
### Robots: [OK/Issues]

---

## Image Audit (Grade: X)
- Total images: N
- Missing alt text: N
- Missing dimensions: N
- Lazy-loaded above fold: N
- Without modern format (WebP/AVIF): N
- Oversized images: N

---

## Font Audit (Grade: X)
- Total @font-face rules: N
- Without font-display: N
- Preloaded fonts: N
- Font loading strategy: [swap/optional/auto]

---

## PWA Audit (Grade: X)
- Manifest: [Present/Missing]
- Service Worker: [Active/Inactive/None]
- HTTPS: [Yes/No]
- Icons: [192x192: Y/N, 512x512: Y/N]
- Theme color: [Present/Missing]
- Installable: [Yes/No]

---

## Accessibility Audit (Grade: X)
- Focusable elements: N
- Without visible focus indicator: N
- Hidden but focusable: N
- Unlabeled form inputs: N
- HTML lang attribute: [Present/Missing]

---

## Priority Recommendations
1. [Critical] ...
2. [High] ...
3. [Medium] ...
4. [Low] ...
```
