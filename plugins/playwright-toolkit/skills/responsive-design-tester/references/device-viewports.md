# Device Viewports and Responsive Design Reference

## Standard Test Viewports

### Mobile Devices

| Device | Width | Height | DPR | Category |
|--------|-------|--------|-----|----------|
| iPhone SE | 375 | 667 | 2 | Small Mobile |
| iPhone 14 | 390 | 844 | 3 | Mobile |
| iPhone 14 Pro Max | 430 | 932 | 3 | Large Mobile |
| Samsung Galaxy S21 | 360 | 800 | 3 | Mobile |
| Samsung Galaxy S24 Ultra | 412 | 915 | 3.5 | Large Mobile |
| Google Pixel 8 | 412 | 915 | 2.625 | Mobile |

### Tablet Devices

| Device | Width | Height | DPR | Category |
|--------|-------|--------|-----|----------|
| iPad Mini | 768 | 1024 | 2 | Small Tablet |
| iPad Air | 820 | 1180 | 2 | Tablet |
| iPad Pro 11" | 834 | 1194 | 2 | Tablet |
| iPad Pro 12.9" | 1024 | 1366 | 2 | Large Tablet |
| Samsung Galaxy Tab S9 | 800 | 1280 | 2 | Tablet |
| Surface Pro | 912 | 1368 | 2 | Large Tablet |

### Desktop Viewports

| Viewport | Width | Height | Category |
|----------|-------|--------|----------|
| Laptop (small) | 1280 | 720 | Small Desktop |
| Laptop (standard) | 1366 | 768 | Desktop |
| Desktop (HD) | 1440 | 900 | Desktop |
| Desktop (Full HD) | 1920 | 1080 | Large Desktop |
| Desktop (QHD) | 2560 | 1440 | Ultrawide |
| Desktop (4K) | 3840 | 2160 | 4K |

### Recommended Test Matrix

| Test Level | Viewports | Use Case |
|-----------|-----------|----------|
| Quick (2) | 375x667, 1440x900 | Fast sanity check |
| Standard (4) | 375x667, 768x1024, 1440x900, 1920x1080 | Regular testing |
| Full (6) | 375x667, 430x932, 768x1024, 1024x1366, 1440x900, 1920x1080 | Pre-launch audit |
| Ultrawide (7+) | Standard + 2560x1440 | Apps with wide layouts |

## CSS Framework Breakpoints

### Tailwind CSS (v3/v4)

| Breakpoint | Min Width | Typical Use |
|-----------|-----------|-------------|
| `sm` | 640px | Landscape phones |
| `md` | 768px | Tablets |
| `lg` | 1024px | Laptops |
| `xl` | 1280px | Desktops |
| `2xl` | 1536px | Large screens |

### Bootstrap 5

| Breakpoint | Min Width | Typical Use |
|-----------|-----------|-------------|
| `sm` | 576px | Landscape phones |
| `md` | 768px | Tablets |
| `lg` | 992px | Desktops |
| `xl` | 1200px | Large desktops |
| `xxl` | 1400px | Extra large screens |

### Material UI (MUI v5/v6)

| Breakpoint | Min Width | Typical Use |
|-----------|-----------|-------------|
| `xs` | 0px | Extra small (phones) |
| `sm` | 600px | Small (tablets) |
| `md` | 900px | Medium (small laptops) |
| `lg` | 1200px | Large (desktops) |
| `xl` | 1536px | Extra large |

### Testing at Breakpoints

When testing responsive design, test at:
1. Each breakpoint width exactly (to test the transition)
2. One pixel below each breakpoint (to test the previous tier)
3. A representative width within each range

## Touch Target Requirements

### WCAG 2.5.5 (Level AAA) — Target Size (Enhanced)

| Requirement | Value | Notes |
|-------------|-------|-------|
| Minimum target size | 44 x 44 CSS pixels | For pointer inputs |
| Exceptions | Inline text links, browser-native controls | |
| Spacing alternative | 24px minimum if target is smaller | With sufficient spacing |

### WCAG 2.5.8 (Level AA) — Target Size (Minimum)

| Requirement | Value | Notes |
|-------------|-------|-------|
| Minimum target size | 24 x 24 CSS pixels | Or sufficient spacing |
| Spacing requirement | At least 24px offset from adjacent targets | Alternative to size |

### Google Mobile-Friendly Guidelines

| Requirement | Value | Notes |
|-------------|-------|-------|
| Recommended target size | 48 x 48 CSS pixels | Material Design standard |
| Minimum spacing between targets | 8 CSS pixels | Prevents accidental taps |

### Audit Checks

| Check | Threshold | Severity |
|-------|-----------|----------|
| Interactive element < 24x24 CSS px | Fails WCAG 2.5.8 (AA) | Error |
| Interactive element < 44x44 CSS px | Fails WCAG 2.5.5 (AAA) | Warning |
| Interactive element < 48x48 CSS px | Below Google recommendation | Info |
| Adjacent targets < 8px apart | Accidental tap risk | Warning |
| Touch target overlaps another | Unusable on touch devices | Error |

**Interactive elements to check:** `<a>`, `<button>`, `<input>`, `<select>`, `<textarea>`, `[role="button"]`, `[role="link"]`, `[role="menuitem"]`, `[role="tab"]`, `[onclick]`.

## Font Readability

### Minimum Font Sizes

| Context | Minimum | Recommended | Maximum |
|---------|---------|-------------|---------|
| Body text (mobile) | 14px | 16px | 20px |
| Body text (desktop) | 14px | 16-18px | 22px |
| Secondary/caption text | 12px | 13-14px | 16px |
| Navigation links | 14px | 16px | 18px |
| Form labels | 14px | 16px | 18px |
| Form inputs | 16px (iOS zoom prevention) | 16px | 20px |
| Buttons | 14px | 16px | 18px |

**iOS zoom prevention:** Input fields with font-size < 16px trigger automatic zoom on iOS Safari. Always use `font-size: 16px` or larger for inputs on mobile.

### Line Height and Spacing

| Property | Minimum | Recommended |
|----------|---------|-------------|
| Line height (body) | 1.4 | 1.5-1.6 |
| Line height (headings) | 1.1 | 1.2-1.3 |
| Paragraph spacing | 0.5em | 1em |
| Letter spacing | Normal | -0.02em to 0.02em |
| Maximum line width | - | 45-80 characters (ch) |

### Audit Checks

| Check | Threshold | Severity |
|-------|-----------|----------|
| Body text < 14px | Below minimum | Error |
| Body text < 16px on mobile | Below recommended | Warning |
| Input font-size < 16px on mobile | iOS will auto-zoom | Error |
| Line height < 1.3 for body text | Too tight for readability | Warning |
| Line width > 90 characters | Too wide for readability | Warning |
| Text with insufficient contrast | WCAG AA: 4.5:1 (normal), 3:1 (large) | Error |

## Viewport Meta Tag

### Standard Configuration

```html
<meta name="viewport" content="width=device-width, initial-scale=1">
```

### Audit Checks

| Check | Expected | Severity |
|-------|----------|----------|
| Viewport meta present | Yes | Error if missing |
| `width=device-width` | Yes | Error if fixed width |
| `initial-scale=1` | Yes | Warning if missing |
| `maximum-scale=1` or `user-scalable=no` | No (blocks zoom) | Error (accessibility) |
| `minimum-scale` | Not set or >= 0.5 | Warning |

## Common Responsive Issues and Detection

### Horizontal Overflow

**Detection:** `document.documentElement.scrollWidth > document.documentElement.clientWidth`

**Common causes:**
- Fixed-width elements wider than viewport
- Images without `max-width: 100%`
- Tables without responsive wrapper
- Absolute positioned elements extending beyond viewport
- `vw` units not accounting for scrollbar (`100vw` includes scrollbar width)

### Content Truncation

**Detection:** Elements with `overflow: hidden` where `scrollWidth > clientWidth` or `scrollHeight > clientHeight`.

**Common causes:**
- Fixed heights on containers with variable content
- Text truncation without `text-overflow: ellipsis` indicator
- Flexbox items shrinking beyond content minimums

### Layout Breakage Patterns

| Issue | Detection Method |
|-------|-----------------|
| Overlapping elements | Compare bounding rects of sibling elements |
| Elements pushed off-screen | Element rect fully outside viewport |
| Collapsed containers | Element has 0 width or 0 height but has children |
| Text overflow without ellipsis | scrollWidth > clientWidth without text-overflow |
| Navigation wrapping | Nav items wrapping to new line at narrow widths |
| Table overflow | Table wider than its container |
| Image distortion | Aspect ratio of rendered image differs from intrinsic |

### Responsive Design Scoring

| Grade | Criteria |
|-------|---------|
| **A** | No overflow, all touch targets pass, all fonts readable, no layout breaks |
| **B** | Minor issues: 1-2 touch targets below recommended, font size warnings |
| **C** | Moderate: horizontal overflow on some viewports, several small touch targets |
| **D** | Significant: layout breakage at common viewports, many small targets |
| **F** | Critical: page unusable at mobile viewports, no viewport meta tag |
