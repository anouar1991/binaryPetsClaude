# SEO Audit Checklist Reference

## Meta Tags

### Title Tag

| Criteria | Requirement | Score Impact |
|----------|------------|-------------|
| Present | Required | -20 if missing |
| Length | 50-60 characters | -5 if outside range |
| Unique | Must not duplicate other pages | -5 if generic |
| Keyword placement | Primary keyword near the beginning | -3 if keyword absent |
| Brand | Brand name at end (optional) | Informational |

**Optimal format:** `Primary Keyword - Secondary Info | Brand`

**Red flags:** Empty title, "Untitled", "Home", longer than 70 chars (truncated in SERPs).

### Meta Description

| Criteria | Requirement | Score Impact |
|----------|------------|-------------|
| Present | Recommended | -10 if missing |
| Length | 150-160 characters | -3 if outside range |
| Unique | Must not duplicate other pages | -3 if generic |
| Call to action | Encourages clicks | Informational |
| Primary keyword | Should be included naturally | -2 if absent |

**Red flags:** Empty, duplicate of title, over 160 chars (truncated in SERPs), under 70 chars (too short).

### Canonical URL

| Criteria | Requirement | Score Impact |
|----------|------------|-------------|
| Present | Required for all indexable pages | -10 if missing |
| Self-referencing | Points to current page URL | -5 if incorrect |
| Absolute URL | Must be full URL, not relative | -5 if relative |
| Single canonical | Only one per page | -10 if multiple |
| Protocol match | Should match site protocol (HTTPS) | -3 if mismatch |

**Check:** `<link rel="canonical" href="https://example.com/page">`

### Viewport Meta Tag

| Criteria | Requirement | Score Impact |
|----------|------------|-------------|
| Present | Required for mobile-friendliness | -15 if missing |
| Width | `width=device-width` | -5 if fixed width |
| Initial scale | `initial-scale=1` | -3 if missing |
| No maximum-scale=1 | Allows user zoom (accessibility) | -5 if zoom disabled |

**Recommended:** `<meta name="viewport" content="width=device-width, initial-scale=1">`

## Open Graph Tags

Required for social sharing previews on Facebook, LinkedIn, and other platforms.

| Tag | Required | Validation |
|-----|----------|------------|
| `og:title` | Yes | Non-empty, under 60 chars |
| `og:description` | Yes | Non-empty, 100-200 chars |
| `og:image` | Yes | Absolute URL, image exists (200 status), minimum 1200x630px recommended |
| `og:url` | Yes | Absolute URL, matches canonical |
| `og:type` | Recommended | `website`, `article`, `product`, etc. |
| `og:site_name` | Recommended | Brand name |
| `og:locale` | Optional | Language code (e.g., `en_US`) |

**Red flags:** Missing og:image (no preview in social shares), og:url not matching canonical, relative URLs.

## Twitter Card Tags

| Tag | Required | Validation |
|-----|----------|------------|
| `twitter:card` | Yes | `summary`, `summary_large_image`, `player`, or `app` |
| `twitter:title` | Yes | Non-empty, under 70 chars |
| `twitter:description` | Yes | Non-empty, under 200 chars |
| `twitter:image` | Recommended | Absolute URL, min 144x144 (summary), 300x157 (large) |
| `twitter:site` | Optional | @username of site |
| `twitter:creator` | Optional | @username of content creator |

**Fallback behavior:** Twitter uses Open Graph tags if Twitter-specific tags are missing.

## Heading Hierarchy

| Rule | Requirement | Score Impact |
|------|------------|-------------|
| Single H1 | Exactly one `<h1>` per page | -10 if zero or multiple |
| H1 content | Non-empty, contains primary keyword | -5 if empty |
| Logical nesting | No skipped levels (H1 -> H3 without H2) | -3 per skip |
| No empty headings | All headings have text content | -2 per empty heading |
| Heading order | H1 appears before H2, H2 before H3, etc. | -2 if out of order |

**Check hierarchy:**
```
H1: Page Title (exactly one)
  H2: Section A
    H3: Subsection A.1
    H3: Subsection A.2
  H2: Section B
    H3: Subsection B.1
```

**Red flags:** Multiple H1s, H1 inside sidebar/footer, empty headings used for spacing, skipping from H2 to H4.

## Image Optimization for SEO

| Criteria | Requirement | Score Impact |
|----------|------------|-------------|
| Alt text | All meaningful `<img>` elements | -2 per missing alt |
| Decorative images | `alt=""` (empty) for decorative | -1 per incorrect |
| Alt length | Descriptive but under 125 chars | -1 if too long |
| Filename | Descriptive kebab-case | Informational |
| Lazy loading | `loading="lazy"` for below-fold images | Informational |

**Exempt from alt text:** Decorative images, spacer images, images inside links that have text.

## Structured Data (JSON-LD)

| Criteria | Requirement | Score Impact |
|----------|------------|-------------|
| Present | At least one schema type | -5 if missing entirely |
| Valid JSON | Parseable JSON-LD | -10 if malformed |
| @context | `https://schema.org` | -5 if missing |
| @type | Valid schema.org type | -5 if invalid |
| Required properties | Per type specification | -3 per missing required prop |

**Common Types:**

| Page Type | Recommended Schema | Required Properties |
|-----------|-------------------|-------------------|
| Homepage | `Organization`, `WebSite` | name, url, logo |
| Article | `Article`, `BlogPosting` | headline, datePublished, author |
| Product | `Product` | name, description, offers |
| FAQ | `FAQPage` | mainEntity with Question/Answer |
| Breadcrumb | `BreadcrumbList` | itemListElement |
| Local Business | `LocalBusiness` | name, address, telephone |

**Validation:** Parse all `<script type="application/ld+json">` blocks, verify valid JSON, check @context and @type.

## Robots Directives

| Source | Check | Score Impact |
|--------|-------|-------------|
| `<meta name="robots">` | `index,follow` (default, good), `noindex` (blocks indexing), `nofollow` (blocks link equity) | -15 if unintentional noindex |
| `X-Robots-Tag` header | Same values as meta robots | -15 if unintentional noindex |
| `robots.txt` | Check if page URL is disallowed | -15 if blocked |

**Red flags:** `noindex` on pages that should be indexed, `nofollow` on internal links, conflicting directives between meta and header.

## Performance and SEO Correlation

| CWV Metric | SEO Impact |
|------------|------------|
| LCP > 2.5s | Negative ranking signal |
| CLS > 0.1 | Negative ranking signal |
| INP > 200ms | Negative ranking signal |
| Mobile-unfriendly | Significant ranking penalty |
| Non-HTTPS | Ranking penalty |

## SEO Scoring Rubric

### Grade Calculation

| Grade | Score Range | Meaning |
|-------|------------|---------|
| **A+** | 95-100 | Excellent, fully optimized |
| **A** | 85-94 | Very good, minor improvements possible |
| **B** | 70-84 | Good, several optimizations recommended |
| **C** | 55-69 | Fair, significant issues to address |
| **D** | 40-54 | Poor, major SEO problems |
| **F** | 0-39 | Critical, fundamental issues |

### Point Allocation (100 total)

| Category | Points | Components |
|----------|--------|-----------|
| Title tag | 15 | Present (10), length (3), keyword (2) |
| Meta description | 10 | Present (7), length (3) |
| Canonical | 10 | Present and correct |
| Headings | 10 | Single H1 (5), hierarchy (5) |
| Open Graph | 10 | All four required tags |
| Twitter Card | 5 | Card type + title + description |
| Images | 10 | Alt text coverage percentage |
| Structured data | 10 | Valid JSON-LD with correct schema |
| Robots | 10 | No unintentional blocking |
| Viewport | 5 | Present with correct values |
| HTTPS | 5 | Page served over HTTPS |
