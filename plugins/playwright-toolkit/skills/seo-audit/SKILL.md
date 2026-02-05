---
name: seo-audit
description: >
  Comprehensive SEO audit: meta tags, Open Graph/Twitter Card validation,
  heading hierarchy, image alt coverage, structured data (JSON-LD)
  extraction, hreflang, internal/external link analysis, and
  robots.txt/sitemap.xml checking.
---

# SEO Audit

Perform a comprehensive search engine optimization audit of a web page.
Extracts and validates meta tags (title, description, canonical, robots),
Open Graph and Twitter Card markup, heading hierarchy, image alt text
coverage, structured data (JSON-LD), hreflang annotations, and link
analysis. Supplements with robots.txt and sitemap.xml checks via curl.

## When to Use

- Pre-launch SEO review of new pages or redesigns.
- Diagnosing why a page is not appearing in search results.
- Validating Open Graph and Twitter Card previews before social sharing.
- Auditing structured data (JSON-LD) for rich snippet eligibility.
- Checking heading hierarchy for accessibility and SEO best practices.
- Identifying missing alt text on images.
- Verifying robots.txt and sitemap.xml configuration.

## Prerequisites

- **Playwright MCP server** connected and responding.
- **curl** available in the shell for robots.txt and sitemap.xml fetching.
- Target page must be reachable from the browser instance.

## Workflow

### Phase 1: Navigate to Target

```
browser_navigate({ url: "<target_url>" })
```

```
browser_wait_for({ time: 3 })
```

### Phase 2: Extract Meta Tags and Head Elements

```javascript
browser_evaluate({
  function: `() => {
    const getMeta = (name) => {
      const el = document.querySelector(
        'meta[name="' + name + '"], meta[property="' + name + '"]'
      );
      return el ? el.content : null;
    };

    // Core meta tags
    const meta = {
      title: document.title || null,
      titleLength: (document.title || '').length,
      description: getMeta('description'),
      descriptionLength: (getMeta('description') || '').length,
      robots: getMeta('robots'),
      googlebot: getMeta('googlebot'),
      canonical: null,
      viewport: getMeta('viewport'),
      charset: document.characterSet,
      language: document.documentElement.lang || null
    };

    // Canonical
    const canonicalEl = document.querySelector('link[rel="canonical"]');
    meta.canonical = canonicalEl ? canonicalEl.href : null;

    // Open Graph
    const og = {};
    document.querySelectorAll('meta[property^="og:"]').forEach(el => {
      const prop = el.getAttribute('property').replace('og:', '');
      og[prop] = el.content;
    });

    // Twitter Card
    const twitter = {};
    document.querySelectorAll('meta[name^="twitter:"]').forEach(el => {
      const name = el.getAttribute('name').replace('twitter:', '');
      twitter[name] = el.content;
    });

    // hreflang
    const hreflang = [];
    document.querySelectorAll('link[rel="alternate"][hreflang]').forEach(el => {
      hreflang.push({
        lang: el.hreflang,
        href: el.href
      });
    });

    // Preload/prefetch hints
    const resourceHints = [];
    document.querySelectorAll('link[rel="preload"], link[rel="prefetch"], link[rel="preconnect"], link[rel="dns-prefetch"]').forEach(el => {
      resourceHints.push({
        rel: el.rel,
        href: el.href,
        as: el.getAttribute('as') || null,
        crossorigin: el.crossOrigin || null
      });
    });

    return { meta, og, twitter, hreflang, resourceHints };
  }`
})
```

### Phase 3: Analyze Heading Hierarchy

Use the accessibility tree for accurate heading structure, then supplement
with DOM analysis.

```
browser_snapshot()
```

```javascript
browser_evaluate({
  function: `() => {
    const headings = [];
    document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((el, index) => {
      headings.push({
        level: parseInt(el.tagName[1]),
        text: el.textContent.trim().substring(0, 100),
        index,
        id: el.id || null,
        isVisible: el.offsetParent !== null,
        parentSection: el.closest('section, article, main, aside, nav')?.tagName || null
      });
    });

    // Check hierarchy issues
    const issues = [];
    const h1Count = headings.filter(h => h.level === 1).length;
    if (h1Count === 0) issues.push('No H1 element found');
    if (h1Count > 1) issues.push('Multiple H1 elements found (' + h1Count + ')');

    for (let i = 1; i < headings.length; i++) {
      const gap = headings[i].level - headings[i - 1].level;
      if (gap > 1) {
        issues.push(
          'Heading level skipped: H' + headings[i - 1].level +
          ' -> H' + headings[i].level +
          ' at "' + headings[i].text.substring(0, 40) + '"'
        );
      }
    }

    return {
      total: headings.length,
      h1Count,
      hierarchy: headings,
      issues
    };
  }`
})
```

### Phase 4: Image Alt Text Coverage

```javascript
browser_evaluate({
  function: `() => {
    const images = [];
    document.querySelectorAll('img').forEach(img => {
      const hasAlt = img.hasAttribute('alt');
      const altText = img.getAttribute('alt');
      const isDecorative = altText === '';
      const isVisible = img.offsetParent !== null && img.naturalWidth > 0;

      images.push({
        src: (img.src || img.dataset.src || '').substring(0, 150),
        alt: altText,
        hasAlt,
        isDecorative,
        isVisible,
        width: img.naturalWidth,
        height: img.naturalHeight,
        loading: img.loading || null,
        fetchpriority: img.fetchPriority || null,
        inViewport: img.getBoundingClientRect().top < window.innerHeight
      });
    });

    const missingAlt = images.filter(i => !i.hasAlt && i.isVisible);
    const emptyAlt = images.filter(i => i.isDecorative && i.isVisible);
    const withAlt = images.filter(i => i.hasAlt && !i.isDecorative);

    return {
      total: images.length,
      visible: images.filter(i => i.isVisible).length,
      missingAlt: missingAlt.length,
      decorative: emptyAlt.length,
      withAlt: withAlt.length,
      coveragePercent: images.length > 0
        ? Math.round((withAlt.length + emptyAlt.length) / images.filter(i => i.isVisible).length * 100)
        : 100,
      images: images.slice(0, 50)
    };
  }`
})
```

### Phase 5: Structured Data (JSON-LD) Extraction

```javascript
browser_evaluate({
  function: `() => {
    const jsonLdScripts = [];
    document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
      try {
        const data = JSON.parse(script.textContent);
        const items = Array.isArray(data) ? data : [data];
        items.forEach(item => {
          jsonLdScripts.push({
            type: item['@type'] || 'unknown',
            context: item['@context'] || null,
            data: JSON.stringify(item).substring(0, 1000),
            valid: true
          });
        });
      } catch (e) {
        jsonLdScripts.push({
          type: 'parse-error',
          error: e.message,
          raw: script.textContent.substring(0, 200),
          valid: false
        });
      }
    });

    // Also check for microdata
    const microdataItems = [];
    document.querySelectorAll('[itemscope]').forEach(el => {
      microdataItems.push({
        type: el.getAttribute('itemtype') || 'untyped',
        properties: Array.from(el.querySelectorAll('[itemprop]')).map(p => ({
          name: p.getAttribute('itemprop'),
          value: (p.content || p.textContent || p.href || '').substring(0, 100)
        })).slice(0, 20)
      });
    });

    return {
      jsonLd: {
        count: jsonLdScripts.length,
        items: jsonLdScripts
      },
      microdata: {
        count: microdataItems.length,
        items: microdataItems.slice(0, 10)
      }
    };
  }`
})
```

### Phase 6: Link Analysis

```javascript
browser_evaluate({
  function: `() => {
    const pageOrigin = window.location.origin;
    const pageUrl = window.location.href;
    const links = [];
    const issues = [];

    document.querySelectorAll('a[href]').forEach(a => {
      const href = a.href;
      let type = 'internal';
      try {
        const linkOrigin = new URL(href, pageUrl).origin;
        if (linkOrigin !== pageOrigin) type = 'external';
      } catch { type = 'invalid'; }

      if (href.startsWith('javascript:')) type = 'javascript';
      if (href === '#' || href === '') type = 'empty';

      const rel = a.getAttribute('rel') || '';
      const hasNofollow = rel.includes('nofollow');
      const hasNoopener = rel.includes('noopener');
      const target = a.getAttribute('target');
      const opensNewTab = target === '_blank';

      // Check for issues
      if (type === 'external' && opensNewTab && !hasNoopener) {
        issues.push('External link opens new tab without rel="noopener": ' + href.substring(0, 100));
      }
      if (type === 'javascript') {
        issues.push('JavaScript href found: ' + a.textContent.trim().substring(0, 50));
      }
      if (type === 'empty') {
        issues.push('Empty/hash-only href: ' + (a.textContent.trim().substring(0, 50) || '(no text)'));
      }

      links.push({
        href: href.substring(0, 200),
        text: (a.textContent || '').trim().substring(0, 80),
        type,
        rel: rel || null,
        target: target || null,
        hasNofollow,
        hasNoopener,
        isVisible: a.offsetParent !== null
      });
    });

    const internal = links.filter(l => l.type === 'internal');
    const external = links.filter(l => l.type === 'external');

    // Check for links with no anchor text
    const emptyTextLinks = links.filter(l =>
      l.isVisible && !l.text && l.type !== 'empty' && l.type !== 'javascript'
    );
    if (emptyTextLinks.length > 0) {
      issues.push(emptyTextLinks.length + ' visible links have no anchor text');
    }

    return {
      total: links.length,
      internal: internal.length,
      external: external.length,
      nofollow: links.filter(l => l.hasNofollow).length,
      issues,
      links: links.slice(0, 100)
    };
  }`
})
```

### Phase 7: Check robots.txt and sitemap.xml

Replace `<origin>` with the actual page origin.

```bash
curl -s "<origin>/robots.txt" | head -50
```

```bash
curl -sI "<origin>/sitemap.xml" | head -20
```

If sitemap.xml returns 200, fetch the content:

```bash
curl -s "<origin>/sitemap.xml" | head -100
```

### Phase 8: Page Performance Indicators Relevant to SEO

```javascript
browser_evaluate({
  function: `() => {
    const timing = performance.getEntriesByType('navigation')[0] || {};
    return {
      domContentLoaded: Math.round(timing.domContentLoadedEventEnd || 0),
      loadComplete: Math.round(timing.loadEventEnd || 0),
      ttfb: Math.round(timing.responseStart || 0),
      domElements: document.querySelectorAll('*').length,
      documentSize: document.documentElement.outerHTML.length,
      wordCount: (document.body.innerText || '').split(/\\s+/).filter(w => w.length > 0).length,
      hasServiceWorker: !!navigator.serviceWorker?.controller
    };
  }`
})
```

## Scoring

Assign a score out of 100 based on weighted categories:

| Category | Weight | Criteria |
|----------|--------|----------|
| Meta Tags | 20 | Title (60 chars), description (160 chars), canonical, robots |
| Headings | 15 | Single H1, no skipped levels, descriptive text |
| Images | 15 | Alt text coverage > 95%, no missing alt on visible images |
| Links | 10 | No broken patterns, anchor text present, noopener on external _blank |
| Structured Data | 15 | Valid JSON-LD present, appropriate schema types |
| Social | 10 | OG title/description/image, Twitter card present |
| Technical | 15 | Canonical set, hreflang (if multilingual), robots.txt, sitemap.xml |

## Report Template

```markdown
## SEO Audit Report -- <URL>

**Date:** <timestamp>
**SEO Score:** <N>/100

### Meta Tags

| Tag | Value | Status |
|-----|-------|--------|
| Title | "Example Page Title" (28 chars) | PASS (< 60) |
| Description | "A description of..." (142 chars) | PASS (< 160) |
| Canonical | https://example.com/page | PASS |
| Robots | index, follow | PASS |
| Viewport | width=device-width, initial-scale=1 | PASS |
| Language | en | PASS |

### Open Graph

| Property | Value | Status |
|----------|-------|--------|
| og:title | Example Page Title | PASS |
| og:description | A description... | PASS |
| og:image | https://example.com/og.jpg | PASS |
| og:url | https://example.com/page | PASS |
| og:type | website | PASS |

### Twitter Card

| Property | Value | Status |
|----------|-------|--------|
| twitter:card | summary_large_image | PASS |
| twitter:title | Example Page Title | PASS |
| twitter:description | — | MISSING |
| twitter:image | https://example.com/tw.jpg | PASS |

### Heading Hierarchy

```
H1: Example Page Title
  H2: Features
    H3: Feature One
    H3: Feature Two
  H2: Pricing
    H3: Free Tier
    H3: Enterprise
  H2: FAQ
```

**H1 Count:** 1 (PASS)
**Level Skips:** None (PASS)

### Image Alt Text

| Metric | Value |
|--------|-------|
| Total Images | 24 |
| With Alt Text | 20 |
| Decorative (alt="") | 2 |
| Missing Alt | 2 |
| Coverage | 92% |

**Missing alt text:**
1. `/images/banner-bg.jpg` (visible, in viewport)
2. `/images/partner-logo.png` (visible)

### Structured Data (JSON-LD)

| Type | Valid | Properties |
|------|-------|------------|
| Organization | Yes | name, url, logo, sameAs |
| BreadcrumbList | Yes | 3 items |
| Article | Yes | headline, datePublished, author |

### Link Analysis

| Type | Count |
|------|-------|
| Internal | 45 |
| External | 12 |
| Nofollow | 3 |
| Issues | 2 |

**Issues:**
1. External link opens new tab without rel="noopener": https://analytics.example.com
2. 1 visible link has no anchor text

### robots.txt

```
User-agent: *
Allow: /
Disallow: /admin/
Sitemap: https://example.com/sitemap.xml
```

### sitemap.xml

**Status:** Found (200)
**URLs in sitemap:** 142

### Page Metrics

| Metric | Value |
|--------|-------|
| TTFB | 180 ms |
| DOM Content Loaded | 850 ms |
| DOM Elements | 1,240 |
| Word Count | 1,850 |
| Document Size | 95 KB |

### Recommendations

1. **Add alt text to 2 images:** banner-bg.jpg and partner-logo.png are visible and need descriptive alt text.
2. **Add twitter:description:** Missing Twitter Card description reduces social sharing quality.
3. **Add rel="noopener" to external links:** Security and performance best practice for target="_blank" links.
4. **Word count is adequate (1,850):** Content depth is good for search ranking.
5. **Consider adding FAQ structured data:** FAQ section exists but no FAQPage JSON-LD is present.
```

## Limitations

- **Dynamic content**: SPAs that render content via JavaScript may require additional wait time. The audit captures the DOM state after the initial wait period.
- **JSON-LD validation** checks syntax only, not schema.org compliance. Use Google's Rich Results Test for full validation.
- **Link status checking** is not performed by default to avoid flooding servers. Use the network-request-inspector skill for broken link detection.
- **robots.txt and sitemap.xml** are fetched via curl from the page origin. If the site uses a different domain for its sitemap, this must be checked manually.
- **Mobile-first indexing** considerations require running the audit at mobile viewport size. Use `browser_resize` before navigating for mobile SEO testing.
- **Page speed metrics** are basic navigation timing. Use the core-web-vitals-audit skill for comprehensive performance analysis.
