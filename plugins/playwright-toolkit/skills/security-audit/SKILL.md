---
name: security-audit
description: >
  Comprehensive security posture audit: TLS certificate validation, CSP
  analysis, mixed content detection, cookie security flags, SRI checks,
  security headers (HSTS, X-Frame-Options), and open redirect detection
  via CDP Security and Audits domains.
---

# Security Audit

Perform a comprehensive client-side security assessment of a web page. Uses
CDP Security and Audits domains to detect mixed content, insecure cookies, and
CSP violations. Supplements with browser evaluation for SRI checks and meta
CSP, and independent TLS analysis via openssl and curl.

## When to Use

- Pre-launch security review of a web application.
- Investigating mixed content warnings or CSP violation reports.
- Auditing cookie security flags (Secure, HttpOnly, SameSite) for compliance.
- Verifying TLS configuration and certificate validity.
- Checking that CDN scripts have Subresource Integrity (SRI) attributes.
- Validating security headers are properly set (HSTS, X-Frame-Options, etc.).

## Prerequisites

- **Playwright MCP server** connected and responding.
- **Chromium-based browser** for CDP Security and Audits domains.
- **openssl** and **curl** available in the shell for TLS and header analysis.
- Target page must be reachable from the browser instance.

## Workflow

### Phase 1: Enable CDP Security and Audits Domains

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    await client.send('Security.enable');
    await client.send('Audits.enable');
    await client.send('Network.enable');

    const findings = {
      securityState: null,
      mixedContent: [],
      cookieIssues: [],
      cspViolations: [],
      otherIssues: [],
      certificates: []
    };

    // Security state changes
    client.on('Security.visibleSecurityStateChanged', (params) => {
      findings.securityState = {
        securityState: params.visibleSecurityState.securityState,
        certificateSecurityState: params.visibleSecurityState.certificateSecurityState || null,
        safetyTipInfo: params.visibleSecurityState.safetyTipInfo || null
      };
    });

    // Audits domain catches mixed content, cookie issues, CSP, etc.
    client.on('Audits.issueAdded', (params) => {
      const issue = params.issue;
      const code = issue.code;
      const details = issue.details;

      if (details.mixedContentIssueDetails) {
        findings.mixedContent.push({
          resourceType: details.mixedContentIssueDetails.resourceType,
          resolutionStatus: details.mixedContentIssueDetails.resolutionStatus,
          insecureURL: details.mixedContentIssueDetails.insecureURL,
          mainResourceURL: details.mixedContentIssueDetails.mainResourceURL,
          request: details.mixedContentIssueDetails.request
        });
      } else if (details.cookieIssueDetails) {
        findings.cookieIssues.push({
          cookie: details.cookieIssueDetails.cookie,
          cookieWarningReasons: details.cookieIssueDetails.cookieWarningReasons,
          cookieExclusionReasons: details.cookieIssueDetails.cookieExclusionReasons,
          operation: details.cookieIssueDetails.operation
        });
      } else if (details.contentSecurityPolicyIssueDetails) {
        findings.cspViolations.push({
          violatedDirective: details.contentSecurityPolicyIssueDetails.violatedDirective,
          blockedURL: details.contentSecurityPolicyIssueDetails.blockedURL,
          isReportOnly: details.contentSecurityPolicyIssueDetails.isReportOnly,
          contentSecurityPolicyViolationType: details.contentSecurityPolicyIssueDetails.contentSecurityPolicyViolationType,
          sourceCodeLocation: details.contentSecurityPolicyIssueDetails.sourceCodeLocation
        });
      } else {
        findings.otherIssues.push({
          code: code,
          details: JSON.stringify(details).substring(0, 500)
        });
      }
    });

    globalThis.__securityAudit = { client, findings };
    return 'Security audit interceptors installed';
  }`
})
```

### Phase 2: Navigate to Target

```
browser_navigate({ url: "<target_url>" })
```

```
browser_wait_for({ time: 5 })
```

### Phase 3: Analyze Cookies

Extract all cookies with full attribute inspection via CDP.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = globalThis.__securityAudit.client;
    const { cookies } = await client.send('Network.getAllCookies');

    const analyzed = cookies.map(c => {
      const issues = [];
      if (!c.secure) issues.push('Missing Secure flag');
      if (!c.httpOnly && c.name.match(/session|token|auth|csrf/i)) {
        issues.push('Sensitive cookie missing HttpOnly');
      }
      if (c.sameSite === 'None' && !c.secure) {
        issues.push('SameSite=None requires Secure');
      }
      if (!c.sameSite || c.sameSite === 'None') {
        issues.push('Consider SameSite=Lax or Strict');
      }
      if (c.expires === -1) {
        // Session cookie -- acceptable but note it
      } else if (c.expires > 0) {
        const daysUntilExpiry = (c.expires - Date.now() / 1000) / 86400;
        if (daysUntilExpiry > 365) issues.push('Expires in ' + Math.round(daysUntilExpiry) + ' days (excessive)');
      }

      return {
        name: c.name,
        domain: c.domain,
        path: c.path,
        secure: c.secure,
        httpOnly: c.httpOnly,
        sameSite: c.sameSite || 'None (default)',
        expires: c.expires === -1 ? 'Session' : new Date(c.expires * 1000).toISOString(),
        size: c.size,
        priority: c.priority,
        issues
      };
    });

    return {
      total: analyzed.length,
      withIssues: analyzed.filter(c => c.issues.length > 0).length,
      cookies: analyzed
    };
  }`
})
```

### Phase 4: Check SRI and Meta CSP in Page Context

```javascript
browser_evaluate({
  function: `() => {
    // SRI check: external scripts and stylesheets from CDN/third-party origins
    const pageOrigin = window.location.origin;
    const externalResources = [];
    document.querySelectorAll('script[src], link[rel="stylesheet"][href]').forEach(el => {
      const url = el.src || el.href;
      try {
        const resourceOrigin = new URL(url, window.location.href).origin;
        if (resourceOrigin !== pageOrigin) {
          externalResources.push({
            tag: el.tagName,
            url: url.substring(0, 200),
            hasIntegrity: !!el.integrity,
            integrity: el.integrity || null,
            crossorigin: el.crossOrigin || el.getAttribute('crossorigin') || null
          });
        }
      } catch {}
    });

    // Meta CSP
    const metaCSP = [];
    document.querySelectorAll('meta[http-equiv="Content-Security-Policy"]').forEach(el => {
      metaCSP.push(el.content);
    });

    // Check for open redirect patterns in links
    const suspiciousLinks = [];
    document.querySelectorAll('a[href]').forEach(a => {
      const href = a.href;
      if (/[?&](redirect|url|next|return|goto|target)=/i.test(href)) {
        suspiciousLinks.push({
          text: (a.textContent || '').substring(0, 50),
          href: href.substring(0, 200)
        });
      }
    });

    // Check for password inputs without autocomplete=off
    const passwordInputs = [];
    document.querySelectorAll('input[type="password"]').forEach(input => {
      passwordInputs.push({
        name: input.name || input.id || '(unnamed)',
        autocomplete: input.autocomplete || 'not set',
        form: input.form ? (input.form.action || '').substring(0, 100) : null
      });
    });

    return {
      sri: {
        totalExternal: externalResources.length,
        withSRI: externalResources.filter(r => r.hasIntegrity).length,
        resources: externalResources
      },
      metaCSP,
      suspiciousLinks,
      passwordInputs
    };
  }`
})
```

### Phase 5: TLS Certificate Analysis via OpenSSL

Replace `<hostname>` with the actual target hostname.

```bash
echo | openssl s_client -connect <hostname>:443 -servername <hostname> 2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName -checkend 2592000
```

Check supported TLS versions and cipher suites:

```bash
echo | openssl s_client -connect <hostname>:443 -servername <hostname> -tls1_2 2>&1 | grep -E "Protocol|Cipher|Verify"
```

```bash
echo | openssl s_client -connect <hostname>:443 -servername <hostname> -tls1_3 2>&1 | grep -E "Protocol|Cipher|Verify"
```

### Phase 6: Security Headers via curl

```bash
curl -sI "https://<hostname>" | grep -iE "^(strict-transport|content-security-policy|x-frame-options|x-content-type|referrer-policy|permissions-policy|x-xss-protection|cross-origin-embedder|cross-origin-opener|cross-origin-resource)"
```

### Phase 7: Harvest CDP Findings

```javascript
browser_run_code({
  code: `async (page) => {
    const audit = globalThis.__securityAudit;
    if (!audit) return { error: 'Audit not installed' };
    return audit.findings;
  }`
})
```

### Phase 8: Cleanup

```javascript
browser_run_code({
  code: `async (page) => {
    if (globalThis.__securityAudit) {
      await globalThis.__securityAudit.client.detach();
      delete globalThis.__securityAudit;
    }
    return 'Security audit CDP session detached';
  }`
})
```

## Scoring

Assign a letter grade based on findings:

| Grade | Criteria |
|-------|----------|
| A | No mixed content, all cookies secure, valid CSP, HSTS present, SRI on CDN resources, TLS 1.2+ only |
| B | Minor cookie issues (missing SameSite on non-sensitive), no mixed content, basic security headers |
| C | Some missing security headers, cookies without HttpOnly on sensitive names, no SRI |
| D | Mixed content warnings, missing HSTS, sensitive cookies without Secure flag |
| F | Active mixed content, no CSP, sensitive cookies exposed, TLS issues |

## Report Template

```markdown
## Security Audit Report -- <URL>

**Date:** <timestamp>
**Overall Grade:** <A-F>

### TLS Certificate

| Property | Value |
|----------|-------|
| Subject | CN=example.com |
| Issuer | Let's Encrypt Authority X3 |
| Valid From | 2025-01-01 |
| Valid To | 2025-04-01 |
| Days Until Expiry | 62 |
| TLS Versions | 1.2, 1.3 |
| Cipher (TLS 1.3) | TLS_AES_256_GCM_SHA384 |

### Security Headers

| Header | Value | Status |
|--------|-------|--------|
| Strict-Transport-Security | max-age=31536000; includeSubDomains | PASS |
| Content-Security-Policy | default-src 'self'; script-src 'self' cdn.example.com | PASS |
| X-Frame-Options | DENY | PASS |
| X-Content-Type-Options | nosniff | PASS |
| Referrer-Policy | strict-origin-when-cross-origin | PASS |
| Permissions-Policy | geolocation=(), camera=() | PASS |
| Cross-Origin-Opener-Policy | — | MISSING |

### Cookie Security

| Cookie | Secure | HttpOnly | SameSite | Issues |
|--------|--------|----------|----------|--------|
| session_id | Yes | Yes | Lax | None |
| _ga | No | No | None | Missing Secure, consider SameSite |
| auth_token | Yes | No | None | Missing HttpOnly on auth cookie |

**Cookies:** <N> total, <N> with issues

### Mixed Content

| Type | Resource | Status |
|------|----------|--------|
| (none detected) | — | PASS |

### CSP Violations

| Directive | Blocked URL | Type |
|-----------|-------------|------|
| script-src | inline | InlineViolation |

### Subresource Integrity (SRI)

| Resource | Has SRI | Crossorigin |
|----------|---------|-------------|
| https://cdn.example.com/lib.js | Yes | anonymous |
| https://fonts.googleapis.com/css | No | — |

**Coverage:** <N>/<M> external resources have SRI

### Open Redirect Candidates

| Link Text | URL Pattern |
|-----------|-------------|
| Login | /auth?redirect=... |

### Recommendations

1. **Add HttpOnly to auth_token cookie:** Prevents JavaScript access to authentication cookie.
2. **Add SRI to Google Fonts:** Subresource integrity ensures CDN resources are not tampered with.
3. **Set Cross-Origin-Opener-Policy:** Prevents cross-origin window references. Add `same-origin`.
4. **Review open redirect parameter:** /auth?redirect= should validate against an allowlist.
```

## Limitations

- **CDP Audits domain** reports issues as the browser encounters them. Resources loaded after the audit may have additional issues not captured.
- **openssl analysis** reflects the TLS configuration at audit time. Certificate rotation or config changes require re-audit.
- **CSP evaluation** covers both HTTP header and meta tag CSP, but report-only policies are flagged separately and do not block content.
- **SRI checking** only covers `<script>` and `<link>` elements present in the DOM at audit time. Dynamically injected scripts are not checked.
- **Cookie analysis** uses `Network.getAllCookies` which returns cookies for all domains the browser has encountered, not just the target page.
