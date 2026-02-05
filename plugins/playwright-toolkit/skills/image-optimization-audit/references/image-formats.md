# Image Formats and Optimization Reference

## Format Comparison

### Raster Formats

| Format | Best For | Compression | Transparency | Animation | Browser Support |
|--------|----------|-------------|-------------|-----------|----------------|
| JPEG | Photos, complex images | Lossy | No | No | Universal |
| PNG | Graphics, screenshots, transparency | Lossless | Yes (alpha) | No | Universal |
| GIF | Simple animations, small graphics | Lossless (256 colors) | Yes (1-bit) | Yes | Universal |
| WebP | Photos and graphics (replaces JPEG/PNG) | Lossy + Lossless | Yes (alpha) | Yes | 97%+ browsers |
| AVIF | Photos (next-gen, best compression) | Lossy + Lossless | Yes (alpha) | Yes | 92%+ browsers |

### Vector Format

| Format | Best For | Scalability | Animation | Interactivity |
|--------|----------|-------------|-----------|--------------|
| SVG | Icons, logos, illustrations, simple graphics | Infinite | Yes (SMIL/CSS) | Yes (DOM events) |

## Compression Ratios (vs JPEG at equivalent visual quality)

| Format | Typical Savings | Notes |
|--------|----------------|-------|
| WebP (lossy) | 25-35% smaller | Near-universal browser support |
| AVIF (lossy) | 40-50% smaller | Growing browser support, slower encoding |
| WebP (lossless) | 25-30% smaller than PNG | Good PNG replacement |
| AVIF (lossless) | 20-30% smaller than PNG | Best lossless compression |

## Use Case Decision Matrix

| Content Type | Recommended Format | Fallback |
|-------------|-------------------|----------|
| Photographs | AVIF > WebP > JPEG | JPEG |
| Screenshots / UI | WebP (lossless) > PNG | PNG |
| Icons / Logos | SVG | PNG (with @2x) |
| Simple animations | WebP > GIF | GIF |
| Complex animations | Video (MP4/WebM) | GIF (last resort) |
| Decorative patterns | CSS or SVG | PNG |
| Transparent photos | WebP > AVIF > PNG | PNG |

## Responsive Images

### srcset Syntax

```html
<!-- Resolution switching (same aspect ratio, different sizes) -->
<img
  src="image-800.jpg"
  srcset="image-400.jpg 400w,
          image-800.jpg 800w,
          image-1200.jpg 1200w,
          image-1600.jpg 1600w"
  sizes="(max-width: 600px) 100vw,
         (max-width: 1200px) 50vw,
         33vw"
  alt="Description">
```

**`srcset` with `w` descriptors:** Browser chooses based on viewport width and device pixel ratio.

**`sizes` attribute:** Tells the browser the intended display width at each breakpoint. Required when using `w` descriptors.

### `<picture>` Element

```html
<!-- Format switching with art direction -->
<picture>
  <!-- Modern format, narrow viewport -->
  <source media="(max-width: 600px)" type="image/avif" srcset="hero-mobile.avif">
  <source media="(max-width: 600px)" type="image/webp" srcset="hero-mobile.webp">

  <!-- Modern format, wide viewport -->
  <source type="image/avif" srcset="hero-desktop.avif">
  <source type="image/webp" srcset="hero-desktop.webp">

  <!-- Fallback -->
  <img src="hero-desktop.jpg" alt="Hero image">
</picture>
```

**When to use `<picture>`:**
- Format negotiation (AVIF -> WebP -> JPEG)
- Art direction (different crops at different viewports)
- When `srcset`/`sizes` is not enough

### Audit Checks for Responsive Images

| Check | Pass Criteria | Severity |
|-------|--------------|----------|
| `srcset` present on content images | At least 2 sizes defined | Warning |
| `sizes` matches actual layout | Declared size within 20% of actual | Warning |
| `<picture>` for format switching | Modern format (WebP/AVIF) source present | Info |
| Missing `sizes` with `w` descriptors | `sizes` attribute is present | Error |

## Lazy Loading

### Native Lazy Loading

```html
<!-- Below-fold images: lazy load -->
<img src="photo.jpg" loading="lazy" alt="Description">

<!-- Above-fold images: eager load (default, or explicit) -->
<img src="hero.jpg" loading="eager" alt="Hero">
<!-- Or fetchpriority for LCP candidates: -->
<img src="hero.jpg" fetchpriority="high" alt="Hero">
```

### Audit Rules

| Rule | Criteria | Severity |
|------|----------|----------|
| Above-fold images must NOT be lazy | Images in initial viewport should not have `loading="lazy"` | Error |
| Below-fold images should be lazy | Images below viewport should have `loading="lazy"` | Warning |
| LCP image must not be lazy | The LCP element (if image) must not have `loading="lazy"` | Error |
| LCP image should have `fetchpriority="high"` | Helps browser prioritize LCP resource | Warning |

**Above-fold detection:** Image's bounding rect top < viewport height at initial load.

## CLS Prevention with Images

### Width and Height Attributes

```html
<!-- CORRECT: Browser reserves space before image loads -->
<img src="photo.jpg" width="800" height="600" alt="Photo">

<!-- CORRECT: CSS aspect-ratio as alternative -->
<img src="photo.jpg" style="aspect-ratio: 4/3; width: 100%;" alt="Photo">

<!-- WRONG: No dimensions, causes layout shift when image loads -->
<img src="photo.jpg" alt="Photo">
```

### Audit Rules

| Rule | Criteria | Severity |
|------|----------|----------|
| Width and height present | Both `width` and `height` attributes set, OR CSS `aspect-ratio` defined | Warning |
| Correct aspect ratio | Declared ratio matches intrinsic image ratio (within 5%) | Warning |
| CSS override safe | If CSS sets `width: 100%; height: auto;`, HTML attributes still needed for aspect ratio calculation | Info |

## Oversized Image Detection

### Thresholds

| Condition | Classification | Severity |
|-----------|---------------|----------|
| Intrinsic size > 2x display size | Oversized | Warning |
| Intrinsic size > 3x display size | Significantly oversized | Error |
| Intrinsic size > 4x display size | Wasteful | Error |
| Intrinsic size < display size | Undersized (blurry) | Warning |

**Calculation:**
```
oversize_ratio = (intrinsic_width * intrinsic_height) / (display_width * display_height * device_pixel_ratio^2)
```

A ratio of 1.0 is perfect. Greater than 1.0 means wasted bytes. Less than 1.0 means blurry rendering.

**Device pixel ratio consideration:** A 400x400 CSS image on a 2x display needs an 800x800 source image. Factor in `window.devicePixelRatio` when calculating oversizing.

### File Size Thresholds

| Image Type | Warning Threshold | Error Threshold |
|-----------|-------------------|-----------------|
| Hero / LCP image | > 200 KB | > 500 KB |
| Content image | > 100 KB | > 300 KB |
| Thumbnail | > 30 KB | > 80 KB |
| Icon / decorative | > 10 KB | > 30 KB |

## Image Audit Scoring

### Grade Calculation

| Grade | Score Range |
|-------|-----------|
| **A** | 90-100 |
| **B** | 75-89 |
| **C** | 60-74 |
| **D** | 40-59 |
| **F** | 0-39 |

### Point Allocation (100 total)

| Category | Points | Criteria |
|----------|--------|----------|
| Modern formats | 20 | Percentage of images served as WebP/AVIF |
| Responsive images | 20 | srcset/picture usage on content images |
| Lazy loading | 15 | Correct lazy/eager on below/above fold |
| Dimensions defined | 15 | Width/height or aspect-ratio present |
| Sizing efficiency | 15 | No images > 2x display size |
| File size | 15 | All images under threshold for their type |

### Deductions

| Issue | Deduction |
|-------|-----------|
| LCP image is lazy-loaded | -15 |
| Image > 1 MB on page | -10 per image |
| No WebP/AVIF anywhere on page | -10 |
| Total image weight > 3 MB | -10 |
| Missing alt text on content image | -3 per image (cross-reference with SEO) |
