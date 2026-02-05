---
name: third-party-impact
description: >
  Categorizes every third-party script by type (analytics, ads, social, tag
  managers, CDN libraries, fonts). Measures blocking time per script via Long
  Task attribution, byte weight per category, render-blocking identification,
  and connection cost per unique domain. Produces an impact breakdown report.
---

# Third-Party Impact

Analyze the performance impact of all third-party resources loaded on a page.
Categorizes scripts by vendor type, measures their contribution to main-thread
blocking time via Long Task attribution, calculates byte weight per category,
identifies render-blocking resources, and estimates connection overhead per
third-party domain.

## When to Use

- Diagnosing slow page loads caused by third-party scripts.
- Auditing tag manager bloat and identifying redundant trackers.
- Preparing a cost-benefit report for each third-party dependency.
- Identifying render-blocking third-party resources.
- Evaluating whether to self-host, defer, or remove specific vendors.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for Long Task attribution, CDP Network domain, and Performance metrics.
- Target page must be reachable from the browser instance.
- Best results on a fresh page load (no cached resources).

## Vendor Categorization Database

The following domain patterns are used for automatic categorization. Unknown
domains are labeled `unknown` for manual classification.

```
VENDOR_CATEGORIES = {
  "analytics": [
    "google-analytics.com", "analytics.google.com", "www.googletagmanager.com",
    "gtag", "ga.js", "analytics.js",
    "hotjar.com", "static.hotjar.com",
    "mixpanel.com", "cdn.mxpnl.com",
    "segment.com", "cdn.segment.com", "api.segment.io",
    "amplitude.com", "cdn.amplitude.com",
    "heap.io", "heapanalytics.com",
    "plausible.io", "matomo", "piwik",
    "clarity.ms", "fullstory.com", "logrocket.com",
    "newrelic.com", "bam.nr-data.net", "js-agent.newrelic.com",
    "sentry.io", "browser.sentry-cdn.com",
    "datadog", "datadoghq.com"
  ],
  "ads": [
    "googlesyndication.com", "pagead2.googlesyndication.com",
    "doubleclick.net", "googleadservices.com",
    "adservice.google.com", "adsense",
    "amazon-adsystem.com", "ads-twitter.com",
    "adsrvr.org", "criteo.com", "criteo.net",
    "outbrain.com", "taboola.com", "revcontent.com",
    "mediavine.com", "ezoic.net"
  ],
  "social": [
    "facebook.net", "connect.facebook.net", "fbcdn.net",
    "platform.twitter.com", "syndication.twitter.com",
    "platform.linkedin.com", "snap.licdn.com",
    "pinterest.com", "assets.pinterest.com",
    "tiktok.com", "reddit.com", "embedly.com",
    "addthis.com", "sharethis.com"
  ],
  "tag_managers": [
    "googletagmanager.com", "gtm.js",
    "tags.tiqcdn.com", "tealiumiq.com",
    "cdn.optimizely.com", "launchdarkly.com",
    "adobedtm.com", "assets.adobedtm.com"
  ],
  "cdn_libraries": [
    "cdn.jsdelivr.net", "cdnjs.cloudflare.com", "unpkg.com",
    "ajax.googleapis.com", "code.jquery.com",
    "stackpath.bootstrapcdn.com", "maxcdn.bootstrapcdn.com",
    "cdn.tailwindcss.com",
    "polyfill.io", "cdn.polyfill.io"
  ],
  "fonts": [
    "fonts.googleapis.com", "fonts.gstatic.com",
    "use.typekit.net", "p.typekit.net",
    "fast.fonts.net", "cloud.typography.com",
    "use.fontawesome.com", "kit.fontawesome.com"
  ],
  "video": [
    "youtube.com", "www.youtube.com", "player.vimeo.com",
    "fast.wistia.com", "vidyard.com"
  ],
  "chat_support": [
    "intercom.io", "widget.intercom.io",
    "crisp.chat", "client.crisp.chat",
    "zendesk.com", "static.zdassets.com",
    "drift.com", "js.driftt.com",
    "tawk.to", "livechatinc.com", "cdn.livechatinc.com"
  ],
  "consent_privacy": [
    "cookiebot.com", "consentmanager.net",
    "onetrust.com", "cdn.cookielaw.org",
    "osano.com", "iubenda.com"
  ]
}
```

## Workflow

### Step 1 -- Navigate with Network Monitoring via CDP

Set up CDP Network monitoring before navigation to capture all requests
from the very beginning.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    // Storage for all requests
    window.__thirdParty = { requests: [], longTasks: [] };

    await client.send('Network.enable');

    // Collect all network requests
    const requests = [];
    client.on('Network.requestWillBeSent', (params) => {
      requests.push({
        requestId: params.requestId,
        url: params.request.url,
        method: params.request.method,
        type: params.type,
        initiator: params.initiator ? {
          type: params.initiator.type,
          url: params.initiator.url || null,
          lineNumber: params.initiator.lineNumber || null
        } : null,
        timestamp: params.timestamp,
        isLinkPreload: params.request.isLinkPreload || false
      });
    });

    client.on('Network.responseReceived', (params) => {
      const req = requests.find(r => r.requestId === params.requestId);
      if (req) {
        req.status = params.response.status;
        req.mimeType = params.response.mimeType;
        req.protocol = params.response.protocol;
        req.remoteAddress = params.response.remoteIPAddress || null;
        req.headers = {
          contentLength: params.response.headers['content-length'] || null,
          contentEncoding: params.response.headers['content-encoding'] || null,
          cacheControl: params.response.headers['cache-control'] || null,
          server: params.response.headers['server'] || null
        };
      }
    });

    client.on('Network.loadingFinished', (params) => {
      const req = requests.find(r => r.requestId === params.requestId);
      if (req) {
        req.encodedDataLength = params.encodedDataLength;
        req.finished = true;
      }
    });

    // Store reference for later retrieval
    page.__cdpRequests = requests;
    page.__cdpClient = client;

    return 'CDP Network monitoring enabled';
  }`
})
```

### Step 2 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

Wait for the page and all deferred scripts to load:

```
browser_wait_for({ time: 5 })
```

### Step 3 -- Install Long Task Observer

Set up a PerformanceObserver for Long Tasks with attribution to identify
which scripts are blocking the main thread.

```javascript
browser_evaluate({
  function: `() => {
    window.__longTasks = [];

    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        const task = {
          startTime: entry.startTime,
          duration: entry.duration,
          attribution: []
        };

        if (entry.attribution) {
          for (const attr of entry.attribution) {
            task.attribution.push({
              name: attr.name,
              entryType: attr.entryType,
              containerType: attr.containerType,
              containerSrc: attr.containerSrc,
              containerId: attr.containerId,
              containerName: attr.containerName
            });
          }
        }

        window.__longTasks.push(task);
      }
    }).observe({ type: 'longtask', buffered: true });

    return 'Long Task observer installed';
  }`
})
```

Perform some interactions to trigger deferred script execution:

```javascript
browser_evaluate({
  function: `() => {
    window.scrollBy(0, window.innerHeight * 3);
    return 'scrolled';
  }`
})
```

```
browser_wait_for({ time: 3 })
```

### Step 4 -- Harvest Network Request Data

Collect all captured network requests and categorize them.

```javascript
browser_run_code({
  code: `async (page) => {
    const requests = page.__cdpRequests || [];
    const pageOrigin = new URL(page.url()).origin;

    // Vendor categorization
    const VENDOR_CATEGORIES = {
      analytics: [
        'google-analytics.com', 'analytics.google.com', 'googletagmanager.com',
        'hotjar.com', 'static.hotjar.com', 'mixpanel.com', 'cdn.mxpnl.com',
        'segment.com', 'cdn.segment.com', 'api.segment.io',
        'amplitude.com', 'cdn.amplitude.com', 'heap.io', 'heapanalytics.com',
        'plausible.io', 'clarity.ms', 'fullstory.com', 'logrocket.com',
        'newrelic.com', 'bam.nr-data.net', 'js-agent.newrelic.com',
        'sentry.io', 'browser.sentry-cdn.com', 'datadoghq.com'
      ],
      ads: [
        'googlesyndication.com', 'pagead2.googlesyndication.com',
        'doubleclick.net', 'googleadservices.com', 'adservice.google.com',
        'amazon-adsystem.com', 'ads-twitter.com', 'adsrvr.org',
        'criteo.com', 'criteo.net', 'outbrain.com', 'taboola.com',
        'mediavine.com', 'ezoic.net'
      ],
      social: [
        'facebook.net', 'connect.facebook.net', 'fbcdn.net',
        'platform.twitter.com', 'syndication.twitter.com',
        'platform.linkedin.com', 'snap.licdn.com',
        'pinterest.com', 'tiktok.com', 'addthis.com', 'sharethis.com'
      ],
      tag_managers: [
        'googletagmanager.com', 'tags.tiqcdn.com', 'tealiumiq.com',
        'cdn.optimizely.com', 'launchdarkly.com',
        'adobedtm.com', 'assets.adobedtm.com'
      ],
      cdn_libraries: [
        'cdn.jsdelivr.net', 'cdnjs.cloudflare.com', 'unpkg.com',
        'ajax.googleapis.com', 'code.jquery.com',
        'stackpath.bootstrapcdn.com', 'maxcdn.bootstrapcdn.com',
        'cdn.tailwindcss.com', 'polyfill.io', 'cdn.polyfill.io'
      ],
      fonts: [
        'fonts.googleapis.com', 'fonts.gstatic.com',
        'use.typekit.net', 'p.typekit.net',
        'fast.fonts.net', 'use.fontawesome.com', 'kit.fontawesome.com'
      ],
      video: [
        'youtube.com', 'www.youtube.com', 'player.vimeo.com',
        'fast.wistia.com', 'vidyard.com'
      ],
      chat_support: [
        'intercom.io', 'widget.intercom.io', 'crisp.chat',
        'client.crisp.chat', 'zendesk.com', 'static.zdassets.com',
        'drift.com', 'js.driftt.com', 'tawk.to',
        'livechatinc.com', 'cdn.livechatinc.com'
      ],
      consent_privacy: [
        'cookiebot.com', 'consentmanager.net',
        'onetrust.com', 'cdn.cookielaw.org', 'osano.com', 'iubenda.com'
      ]
    };

    function categorize(hostname) {
      for (const [category, domains] of Object.entries(VENDOR_CATEGORIES)) {
        if (domains.some(d => hostname.includes(d))) {
          return category;
        }
      }
      return 'unknown';
    }

    // Separate first-party vs third-party
    const thirdParty = [];
    const firstParty = [];

    for (const req of requests) {
      if (!req.url || !req.finished) continue;
      try {
        const url = new URL(req.url);
        const isThirdParty = url.origin !== pageOrigin;
        const entry = {
          url: req.url,
          hostname: url.hostname,
          type: req.type,
          mimeType: req.mimeType || null,
          encodedSize: req.encodedDataLength || 0,
          status: req.status,
          category: isThirdParty ? categorize(url.hostname) : 'first-party',
          initiator: req.initiator,
          cacheControl: req.headers ? req.headers.cacheControl : null,
          isLinkPreload: req.isLinkPreload
        };

        if (isThirdParty) {
          thirdParty.push(entry);
        } else {
          firstParty.push(entry);
        }
      } catch (e) { /* skip invalid URLs */ }
    }

    // Aggregate by category
    const byCategory = {};
    for (const req of thirdParty) {
      if (!byCategory[req.category]) {
        byCategory[req.category] = { requestCount: 0, totalBytes: 0, domains: new Set() };
      }
      byCategory[req.category].requestCount++;
      byCategory[req.category].totalBytes += req.encodedSize;
      byCategory[req.category].domains.add(req.hostname);
    }

    // Convert sets to arrays for serialization
    const categoryReport = {};
    for (const [cat, data] of Object.entries(byCategory)) {
      categoryReport[cat] = {
        requestCount: data.requestCount,
        totalBytes: data.totalBytes,
        totalKB: Math.round(data.totalBytes / 1024 * 100) / 100,
        domains: Array.from(data.domains)
      };
    }

    // Aggregate by domain
    const byDomain = {};
    for (const req of thirdParty) {
      if (!byDomain[req.hostname]) {
        byDomain[req.hostname] = { requestCount: 0, totalBytes: 0, category: req.category, types: new Set() };
      }
      byDomain[req.hostname].requestCount++;
      byDomain[req.hostname].totalBytes += req.encodedSize;
      byDomain[req.hostname].types.add(req.type);
    }

    const domainReport = Object.entries(byDomain)
      .map(([domain, data]) => ({
        domain,
        requestCount: data.requestCount,
        totalBytes: data.totalBytes,
        totalKB: Math.round(data.totalBytes / 1024 * 100) / 100,
        category: data.category,
        types: Array.from(data.types)
      }))
      .sort((a, b) => b.totalBytes - a.totalBytes);

    return {
      summary: {
        totalRequests: requests.length,
        firstPartyRequests: firstParty.length,
        thirdPartyRequests: thirdParty.length,
        thirdPartyBytes: thirdParty.reduce((sum, r) => sum + r.encodedSize, 0),
        thirdPartyKB: Math.round(thirdParty.reduce((sum, r) => sum + r.encodedSize, 0) / 1024 * 100) / 100,
        uniqueThirdPartyDomains: new Set(thirdParty.map(r => r.hostname)).size
      },
      byCategory: categoryReport,
      byDomain: domainReport.slice(0, 30)
    };
  }`
})
```

### Step 5 -- Identify Render-Blocking Third-Party Resources

Scan the DOM for third-party scripts and stylesheets that are render-blocking.

```javascript
browser_evaluate({
  function: `() => {
    const pageOrigin = window.location.origin;
    const renderBlocking = [];

    // Check scripts without async/defer
    const scripts = document.querySelectorAll('script[src]');
    for (const script of scripts) {
      try {
        const url = new URL(script.src, window.location.href);
        if (url.origin === pageOrigin) continue;

        const isAsync = script.async;
        const isDefer = script.defer;
        const isModule = script.type === 'module';

        if (!isAsync && !isDefer) {
          renderBlocking.push({
            type: 'script',
            url: script.src,
            hostname: url.hostname,
            async: isAsync,
            defer: isDefer,
            isModule,
            issue: 'Synchronous script blocks HTML parsing and rendering',
            fix: 'Add async or defer attribute, or move to bottom of body'
          });
        }
      } catch (e) { /* skip */ }
    }

    // Check stylesheets
    const links = document.querySelectorAll('link[rel="stylesheet"][href]');
    for (const link of links) {
      try {
        const url = new URL(link.href, window.location.href);
        if (url.origin === pageOrigin) continue;

        const hasMedia = link.media && link.media !== 'all' && link.media !== '';
        renderBlocking.push({
          type: 'stylesheet',
          url: link.href,
          hostname: url.hostname,
          media: link.media || 'all',
          isConditional: hasMedia,
          issue: hasMedia
            ? 'Conditional stylesheet (media="' + link.media + '") -- may not block'
            : 'Render-blocking stylesheet delays first paint',
          fix: hasMedia ? null : 'Inline critical CSS, load rest async with media="print" onload trick'
        });
      } catch (e) { /* skip */ }
    }

    return {
      renderBlockingCount: renderBlocking.length,
      renderBlocking
    };
  }`
})
```

### Step 6 -- Harvest Long Task Data

Collect Long Task entries with attribution to identify which third-party
scripts are contributing to main thread blocking time.

```javascript
browser_evaluate({
  function: `() => {
    const tasks = window.__longTasks || [];
    const pageOrigin = window.location.origin;

    // Summarize long tasks
    const totalBlockingTime = tasks
      .filter(t => t.duration > 50)
      .reduce((sum, t) => sum + (t.duration - 50), 0);

    // Attribution breakdown
    const bySource = {};
    for (const task of tasks) {
      let source = 'self (first-party)';
      if (task.attribution && task.attribution.length > 0) {
        for (const attr of task.attribution) {
          if (attr.containerSrc) {
            try {
              const url = new URL(attr.containerSrc);
              if (url.origin !== pageOrigin) {
                source = url.hostname;
              }
            } catch (e) {
              source = attr.containerSrc;
            }
          } else if (attr.containerType === 'iframe') {
            source = 'iframe: ' + (attr.containerName || attr.containerId || 'unknown');
          }
        }
      }

      if (!bySource[source]) {
        bySource[source] = { taskCount: 0, totalDuration: 0, totalBlockingTime: 0 };
      }
      bySource[source].taskCount++;
      bySource[source].totalDuration += task.duration;
      bySource[source].totalBlockingTime += Math.max(0, task.duration - 50);
    }

    const sourceReport = Object.entries(bySource)
      .map(([source, data]) => ({ source, ...data }))
      .sort((a, b) => b.totalBlockingTime - a.totalBlockingTime);

    return {
      longTaskCount: tasks.length,
      totalBlockingTimeMs: Math.round(totalBlockingTime),
      bySource: sourceReport
    };
  }`
})
```

### Step 7 -- Get Performance Metrics via CDP

Retrieve script evaluation and compilation time from CDP Performance domain.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = page.__cdpClient || await page.context().newCDPSession(page);

    await client.send('Performance.enable');
    const { metrics } = await client.send('Performance.getMetrics');
    await client.send('Performance.disable');

    const relevant = [
      'ScriptDuration', 'TaskDuration', 'LayoutDuration',
      'RecalcStyleDuration', 'JSHeapUsedSize', 'JSHeapTotalSize',
      'DomContentLoaded', 'NavigationStart'
    ];

    const result = {};
    for (const m of metrics) {
      if (relevant.includes(m.name)) {
        result[m.name] = m.name.includes('Size')
          ? Math.round(m.value / 1024 / 1024 * 100) / 100 + ' MB'
          : Math.round(m.value * 1000) + ' ms';
      }
    }

    return result;
  }`
})
```

### Step 8 -- Measure Connection Cost Per Domain

Analyze the connection overhead (DNS + TCP + TLS) for each unique third-party
domain using Resource Timing.

```javascript
browser_evaluate({
  function: `() => {
    const entries = performance.getEntriesByType('resource');
    const pageOrigin = window.location.origin;
    const domainCosts = {};

    for (const entry of entries) {
      try {
        const url = new URL(entry.name);
        if (url.origin === pageOrigin) continue;

        const domain = url.hostname;
        if (!domainCosts[domain]) {
          domainCosts[domain] = {
            connectionCount: 0,
            totalDnsMs: 0,
            totalConnectMs: 0,
            totalTlsMs: 0,
            totalTtfbMs: 0
          };
        }

        // Only count if timing data is available (not cross-origin blocked)
        if (entry.connectEnd > 0) {
          domainCosts[domain].connectionCount++;
          domainCosts[domain].totalDnsMs += Math.max(0, entry.domainLookupEnd - entry.domainLookupStart);
          domainCosts[domain].totalConnectMs += Math.max(0, entry.connectEnd - entry.connectStart);
          domainCosts[domain].totalTlsMs += Math.max(0,
            entry.secureConnectionStart > 0
              ? entry.connectEnd - entry.secureConnectionStart
              : 0
          );
          domainCosts[domain].totalTtfbMs += Math.max(0, entry.responseStart - entry.requestStart);
        }
      } catch (e) { /* skip */ }
    }

    return Object.entries(domainCosts)
      .map(([domain, data]) => ({
        domain,
        connections: data.connectionCount,
        avgDnsMs: data.connectionCount > 0 ? Math.round(data.totalDnsMs / data.connectionCount) : 0,
        avgConnectMs: data.connectionCount > 0 ? Math.round(data.totalConnectMs / data.connectionCount) : 0,
        avgTlsMs: data.connectionCount > 0 ? Math.round(data.totalTlsMs / data.connectionCount) : 0,
        avgTtfbMs: data.connectionCount > 0 ? Math.round(data.totalTtfbMs / data.connectionCount) : 0,
        totalOverheadMs: Math.round(data.totalDnsMs + data.totalConnectMs)
      }))
      .sort((a, b) => b.totalOverheadMs - a.totalOverheadMs)
      .slice(0, 20);
  }`
})
```

## Interpreting Results

### Report Format

```
## Third-Party Impact Report -- <page_url>

### Summary
- Total requests: 87 (42 first-party, 45 third-party)
- Third-party weight: 892 KB (63% of total page weight)
- Third-party domains: 14
- Total Blocking Time from third parties: 340 ms
- Render-blocking third-party resources: 3

### Impact by Category

| Category        | Requests | Weight   | Domains | Blocking Time |
|-----------------|----------|----------|---------|---------------|
| analytics       | 12       | 145 KB   | 3       | 120 ms        |
| ads             | 18       | 420 KB   | 5       | 180 ms        |
| social          | 6        | 89 KB    | 2       | 40 ms         |
| tag_managers    | 3        | 78 KB    | 1       | 0 ms          |
| cdn_libraries   | 4        | 120 KB   | 2       | 0 ms          |
| fonts           | 2        | 40 KB    | 1       | 0 ms          |

### Heaviest Domains

| Domain                        | Requests | Weight  | Category  |
|-------------------------------|----------|---------|-----------|
| pagead2.googlesyndication.com | 12       | 310 KB  | ads       |
| www.google-analytics.com      | 4        | 85 KB   | analytics |
| connect.facebook.net          | 3        | 72 KB   | social    |

### Render-Blocking Resources
1. SCRIPT `https://example-cdn.com/widget.js` -- synchronous, no async/defer
2. STYLESHEET `https://fonts.googleapis.com/css2?family=...` -- blocks first paint

### Connection Overhead

| Domain                   | Connections | Avg DNS | Avg Connect | Avg TLS | Total Overhead |
|--------------------------|-------------|---------|-------------|---------|----------------|
| pagead2.googlesyndication.com | 4      | 12 ms   | 45 ms       | 32 ms   | 228 ms         |
| connect.facebook.net     | 2           | 8 ms    | 38 ms       | 28 ms   | 92 ms          |
```

### What to Look For

- **Ads dominating weight/blocking time**: consider lazy-loading ad slots below the fold, or using lighter ad formats.
- **Synchronous third-party scripts**: add `async` or `defer` to prevent parser blocking. For scripts that must be synchronous, consider self-hosting with a local copy.
- **Multiple analytics vendors**: redundant tracking libraries are common. Consolidate to one analytics platform where possible.
- **High connection overhead per domain**: use `<link rel="preconnect">` for critical third-party origins to reduce DNS+TCP+TLS latency.
- **Tag manager loading many sub-tags**: audit the tag container to remove unused tags and reduce cascading requests.
- **Large CDN library loads**: consider bundling only the needed modules instead of loading the full library from CDN.

## Limitations

- **Long Task attribution is limited**: the PerformanceObserver `longtask` entry only attributes tasks to iframe containers or script URLs. It cannot pinpoint which function within a script caused the blocking.
- **Resource Timing cross-origin**: timing details (DNS, connect, TLS) require the `Timing-Allow-Origin` header on the third-party response. Without it, these values are zero.
- **Single page load snapshot**: this measures impact during one page load. Real-user impact varies with cache state, geography, and network conditions.
- **Categorization is pattern-based**: unknown domains are labeled `unknown` and require manual classification. The vendor database covers common vendors but is not exhaustive.
- **Chromium-only**: Long Task with attribution, CDP Network, and Performance.getMetrics are Chromium-specific. Results may differ in other browsers.
