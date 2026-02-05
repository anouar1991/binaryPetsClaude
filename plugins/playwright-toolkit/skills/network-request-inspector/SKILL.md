---
name: network-request-inspector
description: >
  Intercept all HTTP requests/responses with full headers, timing breakdown
  (DNS, connect, TLS, TTFB, download), status codes, payload sizes, CORS
  validation, and redirect chain analysis via CDP Network domain.
---

# Network Request Inspector

Capture the complete HTTP request/response lifecycle for every resource loaded
by a page. Uses CDP Network domain events to record headers, timing
breakdowns, redirect chains, and payload sizes. Cross-references with the
browser Performance API for server timing data, and independently verifies
CORS and security headers via curl.

## When to Use

- Debugging slow page loads by identifying which requests have high TTFB or DNS latency.
- Investigating failed requests (4xx/5xx) and their response bodies.
- Validating CORS headers are correctly configured for cross-origin fetches.
- Tracing redirect chains to detect unnecessary hops or open redirects.
- Auditing per-domain connection overhead (DNS, TLS handshake) to justify preconnect hints.
- Measuring total transfer size and identifying oversized payloads.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP Network domain timing data.
- Target page must be reachable from the browser instance.

## Workflow

### Phase 1: Install CDP Network Interceptor

Set up CDP session with listeners for the full request lifecycle. This must be
done **before** navigating to the target page so that all requests are captured.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable', {
      maxTotalBufferSize: 10000000,
      maxResourceBufferSize: 5000000
    });

    const requests = new Map();
    const redirectChains = new Map();

    client.on('Network.requestWillBeSent', (params) => {
      const entry = {
        url: params.request.url,
        method: params.request.method,
        requestHeaders: params.request.headers,
        timestamp: params.timestamp,
        wallTime: params.wallTime,
        initiator: {
          type: params.initiator.type,
          url: params.initiator.url || null,
          lineNumber: params.initiator.lineNumber || null
        },
        resourceType: params.type,
        redirectChain: []
      };

      // Track redirect chains
      if (params.redirectResponse) {
        const prev = requests.get(params.requestId);
        if (prev) {
          const chainId = redirectChains.get(params.requestId) || params.requestId;
          redirectChains.set(params.requestId, chainId);
          entry.redirectChain = [
            ...(prev.redirectChain || []),
            {
              url: prev.url,
              status: params.redirectResponse.status,
              headers: params.redirectResponse.headers
            }
          ];
        }
      }

      requests.set(params.requestId, entry);
    });

    client.on('Network.responseReceived', (params) => {
      const req = requests.get(params.requestId);
      if (req) {
        req.status = params.response.status;
        req.statusText = params.response.statusText;
        req.responseHeaders = params.response.headers;
        req.mimeType = params.response.mimeType;
        req.protocol = params.response.protocol;
        req.remoteAddress = params.response.remoteIPAddress
          ? params.response.remoteIPAddress + ':' + params.response.remotePort
          : null;
        req.securityState = params.response.securityState;

        // Detailed timing breakdown (milliseconds relative to request start)
        const t = params.response.timing;
        if (t) {
          req.timing = {
            dnsStart: t.dnsStart,
            dnsEnd: t.dnsEnd,
            dnsMs: t.dnsEnd > 0 ? Math.round(t.dnsEnd - t.dnsStart) : 0,
            connectStart: t.connectStart,
            connectEnd: t.connectEnd,
            connectMs: t.connectEnd > 0 ? Math.round(t.connectEnd - t.connectStart) : 0,
            sslStart: t.sslStart,
            sslEnd: t.sslEnd,
            sslMs: t.sslEnd > 0 ? Math.round(t.sslEnd - t.sslStart) : 0,
            sendStart: t.sendStart,
            sendEnd: t.sendEnd,
            sendMs: Math.round(t.sendEnd - t.sendStart),
            receiveHeadersEnd: t.receiveHeadersEnd,
            ttfbMs: Math.round(t.receiveHeadersEnd - t.sendEnd),
            workerStart: t.workerStart,
            workerReady: t.workerReady
          };
        }

        // CORS analysis for cross-origin requests
        const origin = new URL(params.response.url).origin;
        const pageOrigin = req._pageOrigin;
        if (pageOrigin && origin !== pageOrigin) {
          const h = params.response.headers;
          req.cors = {
            crossOrigin: true,
            allowOrigin: h['access-control-allow-origin'] || h['Access-Control-Allow-Origin'] || null,
            allowMethods: h['access-control-allow-methods'] || h['Access-Control-Allow-Methods'] || null,
            allowHeaders: h['access-control-allow-headers'] || h['Access-Control-Allow-Headers'] || null,
            allowCredentials: h['access-control-allow-credentials'] || h['Access-Control-Allow-Credentials'] || null,
            exposeHeaders: h['access-control-expose-headers'] || h['Access-Control-Expose-Headers'] || null
          };
        }
      }
    });

    client.on('Network.loadingFinished', (params) => {
      const req = requests.get(params.requestId);
      if (req) {
        req.encodedDataLength = params.encodedDataLength;
        req.finished = true;
        req.endTimestamp = params.timestamp;
        if (req.timestamp) {
          req.totalTimeMs = Math.round((params.timestamp - req.timestamp) * 1000);
        }
      }
    });

    client.on('Network.loadingFailed', (params) => {
      const req = requests.get(params.requestId);
      if (req) {
        req.failed = true;
        req.errorText = params.errorText;
        req.canceled = params.canceled || false;
        req.blockedReason = params.blockedReason || null;
        req.corsErrorStatus = params.corsErrorStatus || null;
      }
    });

    globalThis.__networkInspector = { client, requests };
    return 'Network inspector installed — navigate to target page now';
  }`
})
```

### Phase 2: Navigate and Capture

Navigate to the target page and wait for the network to settle.

```
browser_navigate({ url: "<target_url>" })
```

```javascript
browser_evaluate({
  function: `() => {
    // Store the page origin for CORS analysis
    if (globalThis.__networkInspector) {
      for (const [, req] of globalThis.__networkInspector.requests) {
        req._pageOrigin = window.location.origin;
      }
    }
    return window.location.origin;
  }`
})
```

Wait for late-loading resources (analytics, lazy images, deferred scripts):

```
browser_wait_for({ time: 5 })
```

### Phase 3: Collect Performance API Resource Entries

Supplement CDP data with the browser Performance API for server timing and
decoded body sizes.

```javascript
browser_evaluate({
  function: `() => {
    const entries = performance.getEntriesByType('resource').map(e => ({
      name: e.name,
      initiatorType: e.initiatorType,
      transferSize: e.transferSize,
      decodedBodySize: e.decodedBodySize,
      encodedBodySize: e.encodedBodySize,
      duration: Math.round(e.duration),
      serverTiming: e.serverTiming ? e.serverTiming.map(st => ({
        name: st.name,
        duration: st.duration,
        description: st.description
      })) : []
    }));
    return { count: entries.length, entries };
  }`
})
```

### Phase 4: Harvest CDP Data

Extract the collected request map for analysis.

```javascript
browser_run_code({
  code: `async (page) => {
    const inspector = globalThis.__networkInspector;
    if (!inspector) return { error: 'Inspector not installed' };

    const results = [];
    for (const [id, req] of inspector.requests) {
      // Strip internal fields
      const { _pageOrigin, ...clean } = req;
      results.push({ requestId: id, ...clean });
    }

    // Sort by start timestamp
    results.sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));

    // Summary statistics
    const finished = results.filter(r => r.finished);
    const failed = results.filter(r => r.failed);
    const byDomain = {};
    for (const r of results) {
      try {
        const domain = new URL(r.url).hostname;
        if (!byDomain[domain]) byDomain[domain] = { count: 0, totalBytes: 0, totalTimeMs: 0 };
        byDomain[domain].count++;
        byDomain[domain].totalBytes += r.encodedDataLength || 0;
        byDomain[domain].totalTimeMs += r.totalTimeMs || 0;
      } catch {}
    }

    return {
      total: results.length,
      finished: finished.length,
      failed: failed.length,
      totalTransferBytes: finished.reduce((s, r) => s + (r.encodedDataLength || 0), 0),
      byDomain,
      requests: results
    };
  }`
})
```

### Phase 5: Cross-reference with Built-in Network Log

Use the built-in tool as a baseline sanity check.

```
browser_network_requests({ includeStatic: true })
```

### Phase 6: Independent CORS and Security Header Verification

For each unique cross-origin domain found in Phase 4, verify headers
independently with curl. Replace `<url>` with the actual resource URL and
`<origin>` with the page origin.

```bash
curl -sI -H "Origin: <origin>" "<url>" | grep -iE "^(access-control|x-frame|x-content|strict-transport|content-security|referrer-policy|permissions-policy)"
```

### Phase 7: Cleanup

Detach the CDP session.

```javascript
browser_run_code({
  code: `async (page) => {
    if (globalThis.__networkInspector) {
      await globalThis.__networkInspector.client.detach();
      delete globalThis.__networkInspector;
    }
    return 'CDP session detached';
  }`
})
```

## Report Template

```markdown
## Network Request Inspector Report -- <URL>

**Date:** <timestamp>
**Total Requests:** <N> | **Finished:** <N> | **Failed:** <N>
**Total Transfer Size:** <N> KB

### Request Summary (sorted by total time, top 20 slowest)

| # | URL (truncated) | Method | Status | Type | Size (KB) | DNS | Connect | TLS | TTFB | Total | Protocol |
|---|-----------------|--------|--------|------|-----------|-----|---------|-----|------|-------|----------|
| 1 | /api/data       | GET    | 200    | XHR  | 45.2      | 0   | 0       | 0   | 320  | 385   | h2       |
| 2 | /images/hero.jpg| GET    | 200    | Img  | 280.5     | 23  | 45      | 32  | 180  | 350   | h2       |
| ...                                                                                                      |

### Failed Requests

| URL | Method | Error | Blocked Reason | CORS Error |
|-----|--------|-------|----------------|------------|
| /api/metrics | POST | net::ERR_CONNECTION_REFUSED | — | — |

### Redirect Chains

| Final URL | Hops | Chain |
|-----------|------|-------|
| /dashboard | 2 | /login (302) -> /auth/sso (302) -> /dashboard (200) |

### CORS Analysis

| Resource Domain | Access-Control-Allow-Origin | Allow-Credentials | Issues |
|----------------|-----------------------------|-------------------|--------|
| cdn.example.com | * | — | None |
| api.third-party.com | — | — | MISSING CORS headers |

### Per-Domain Breakdown

| Domain | Requests | Total Size (KB) | Avg Time (ms) | Connection Reuse |
|--------|----------|-----------------|----------------|------------------|
| cdn.example.com | 15 | 450.3 | 85 | Yes (h2) |
| api.example.com | 8 | 23.1 | 210 | Yes (h2) |

### Recommendations

- **Slow TTFB on /api/data (320ms):** Server processing time is high. Consider caching or query optimization.
- **Missing CORS headers on api.third-party.com:** Cross-origin requests will fail. Contact the API provider or proxy through your own domain.
- **Unnecessary redirect chain on /login (2 hops):** Consolidate to a single redirect to reduce latency.
- **Large image /images/hero.jpg (280 KB):** Consider WebP/AVIF format and responsive srcset.
```

## Limitations

- **CDP timing data** is relative to the request start, not wall clock time. Requests reusing a warm connection will show 0 for DNS/connect/TLS.
- **Request bodies** are not captured by default to avoid memory pressure. Use `Network.getRequestPostData` for individual requests if needed.
- **Response bodies** require explicit `Network.getResponseBody` calls per request. This skill focuses on metadata and timing.
- **Service Worker requests** may appear as separate entries with `workerStart` timing data.
- **HTTP/3 (QUIC)** timing may differ from traditional TCP-based breakdowns.
