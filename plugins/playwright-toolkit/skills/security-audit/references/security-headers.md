# Security Headers Reference

## Required Headers

### Content-Security-Policy (CSP)

Controls which resources the browser is allowed to load. The most impactful security header.

**Key Directives:**

| Directive | Purpose | Example |
|-----------|---------|---------|
| `default-src` | Fallback for all resource types | `'self'` |
| `script-src` | JavaScript sources | `'self' 'nonce-abc123'` |
| `style-src` | CSS sources | `'self' 'unsafe-inline'` |
| `img-src` | Image sources | `'self' data: https:` |
| `font-src` | Font sources | `'self' https://fonts.gstatic.com` |
| `connect-src` | XHR, WebSocket, fetch targets | `'self' https://api.example.com` |
| `frame-src` | Iframe sources | `'none'` |
| `object-src` | Plugin sources (Flash, Java) | `'none'` |
| `base-uri` | Restricts `<base>` element | `'self'` |
| `form-action` | Form submission targets | `'self'` |
| `frame-ancestors` | Who can embed this page | `'none'` |
| `upgrade-insecure-requests` | Upgrade HTTP to HTTPS | (no value) |

**Common Policies:**

- **Strict (recommended):** `default-src 'self'; script-src 'self' 'nonce-{random}'; style-src 'self'; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`
- **Moderate:** `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:`
- **Report-Only (testing):** Use `Content-Security-Policy-Report-Only` header with `report-uri` directive to test before enforcing

**Red Flags:**
- `'unsafe-eval'` in `script-src` — allows `eval()`, major XSS vector
- `'unsafe-inline'` in `script-src` — allows inline scripts, defeats CSP purpose
- `*` or `https:` as sole source — too permissive
- Missing `object-src 'none'` — allows Flash/plugin-based attacks
- Missing `base-uri` — allows base tag injection

### Strict-Transport-Security (HSTS)

Forces HTTPS connections. Prevents protocol downgrade attacks and cookie hijacking.

| Parameter | Purpose | Recommendation |
|-----------|---------|---------------|
| `max-age` | Duration in seconds | `31536000` (1 year minimum) |
| `includeSubDomains` | Apply to all subdomains | Include if all subdomains support HTTPS |
| `preload` | Submit to browser preload list | Include for maximum protection |

**Recommended:** `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`

**Scoring:**
- max-age >= 31536000: Full marks
- max-age >= 15768000 (6 months): Partial
- max-age < 15768000 or missing: Fail

### X-Frame-Options

Prevents clickjacking by controlling whether the page can be embedded in iframes.

| Value | Behavior |
|-------|----------|
| `DENY` | Cannot be framed by any site (strongest) |
| `SAMEORIGIN` | Can only be framed by same origin |
| `ALLOW-FROM uri` | Deprecated, use CSP `frame-ancestors` instead |

**Note:** Superseded by CSP `frame-ancestors` directive, but still needed for older browsers.

### X-Content-Type-Options

Prevents MIME type sniffing attacks.

| Value | Behavior |
|-------|----------|
| `nosniff` | Browser must use declared Content-Type |

**Required value:** `X-Content-Type-Options: nosniff`

Only one valid value. Missing this header allows browsers to guess content types, potentially executing files as scripts.

### Referrer-Policy

Controls how much referrer information is sent with requests.

| Value | Privacy Level | Use Case |
|-------|--------------|----------|
| `no-referrer` | Maximum | Sensitive applications |
| `strict-origin-when-cross-origin` | Recommended | General websites |
| `same-origin` | High | Internal applications |
| `origin-when-cross-origin` | Moderate | Sites needing analytics |
| `no-referrer-when-downgrade` | Low (browser default) | Legacy compatibility |
| `unsafe-url` | None | Never recommended |

**Recommended:** `Referrer-Policy: strict-origin-when-cross-origin`

### Permissions-Policy

Controls which browser features and APIs the page can use.

**Key Features:**

| Feature | Risk if Unrestricted |
|---------|---------------------|
| `camera` | Unauthorized camera access |
| `microphone` | Unauthorized audio capture |
| `geolocation` | Location tracking |
| `payment` | Unauthorized payment requests |
| `usb` | USB device access |
| `autoplay` | Audio/video autoplay |
| `fullscreen` | Fullscreen UI spoofing |
| `display-capture` | Screen capture |

**Recommended:** `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()`

`()` means disabled for all origins. `(self)` allows same-origin only.

## Cookie Security Flags

| Flag | Purpose | Recommendation |
|------|---------|---------------|
| `HttpOnly` | Prevents JavaScript access via `document.cookie` | Required for session cookies |
| `Secure` | Only sent over HTTPS | Required for all cookies on HTTPS sites |
| `SameSite=Strict` | Not sent with cross-site requests | Best for session cookies |
| `SameSite=Lax` | Sent with top-level navigations only | Good default for most cookies |
| `SameSite=None` | Sent with all cross-site requests | Requires `Secure` flag; use only when needed |
| `Path=/` | Scope to path | Set to narrowest useful scope |
| `Domain` | Scope to domain | Omit to restrict to exact origin |
| `Max-Age` / `Expires` | Cookie lifetime | Set short lifetimes for sensitive cookies |

**Red Flags:**
- Session cookie without `HttpOnly` — XSS can steal sessions
- Any cookie without `Secure` on HTTPS site — transmitted in plaintext
- `SameSite=None` without `Secure` — browser will reject
- No `SameSite` attribute — browser defaults vary

## Additional Recommended Headers

| Header | Value | Purpose |
|--------|-------|---------|
| `X-DNS-Prefetch-Control: off` | Disable DNS prefetching | Prevents information leakage |
| `X-Permitted-Cross-Domain-Policies: none` | Block Flash/PDF cross-domain | Prevents legacy plugin attacks |
| `Cross-Origin-Opener-Policy: same-origin` | Isolate browsing context | Prevents Spectre-type attacks |
| `Cross-Origin-Resource-Policy: same-origin` | Restrict resource loading | Prevents cross-origin data leaks |
| `Cross-Origin-Embedder-Policy: require-corp` | Require CORP for subresources | Enables SharedArrayBuffer |

## Security Headers Grading Rubric

### Grade Calculation

| Grade | Score Range | Criteria |
|-------|------------|----------|
| **A+** | 95-100 | All headers present with optimal values |
| **A** | 85-94 | All critical headers, minor optimizations possible |
| **B** | 70-84 | Most headers present, some missing or weak |
| **C** | 55-69 | Several headers missing or misconfigured |
| **D** | 40-54 | Major headers missing |
| **F** | 0-39 | Minimal or no security headers |

### Point Allocation

| Header | Points | Criteria for Full Points |
|--------|--------|------------------------|
| Content-Security-Policy | 25 | Present without `unsafe-eval`/`unsafe-inline` in script-src |
| Strict-Transport-Security | 20 | max-age >= 31536000 with includeSubDomains |
| X-Frame-Options | 10 | DENY or SAMEORIGIN |
| X-Content-Type-Options | 10 | nosniff |
| Referrer-Policy | 10 | strict-origin-when-cross-origin or stricter |
| Permissions-Policy | 10 | Present with camera/microphone/geolocation restricted |
| Cookie Flags | 15 | All session cookies have HttpOnly, Secure, SameSite |

### Deductions

| Issue | Deduction |
|-------|-----------|
| `unsafe-eval` in CSP script-src | -15 |
| `unsafe-inline` in CSP script-src | -10 |
| Wildcard `*` in CSP | -10 |
| HSTS max-age < 6 months | -10 |
| Session cookie without HttpOnly | -10 per cookie |
| Any cookie without Secure on HTTPS | -5 per cookie |
