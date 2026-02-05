---
name: debug-page
description: "Debug everything about a broken page: console errors, network failures, storage state, framework state, and targeted error injection in a single orchestrated session."
user_invocable: true
arguments:
  - name: url
    description: "The URL to debug"
    required: true
---

# Full Page Debugging Orchestrator

You are performing a **comprehensive debugging session** that orchestrates multiple debugging skills simultaneously in a single browser session. The goal is to diagnose why a page is broken or misbehaving by collecting all diagnostic data in parallel, then running targeted tests based on findings.

**Skills orchestrated:** console-intelligence, network-request-inspector, storage-inspector, state-inspector, error-injection-tester

## Orchestration Strategy

Install ALL CDP listeners and DOM observers in one `browser_run_code` call, navigate once, let the page load and fail naturally, then harvest all diagnostic data. Use findings from Phase 3 to guide targeted error injection in Phase 4.

## Phase 1: Install All Instrumentation (Single browser_run_code)

### Step 1 — Enable CDP Domains and Install Listeners

Use `browser_run_code` to create a CDP session and enable all debugging domains at once:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    // Storage for all collected data
    globalThis.__debugData = {
      console: [],
      networkRequests: [],
      networkFailures: [],
      cookies: [],
      localStorage: {},
      sessionStorage: {},
      frameworkState: null,
      errors: [],
      warnings: [],
      uncaughtExceptions: [],
      unhandledRejections: []
    };

    // === Enable CDP Domains ===
    await client.send('Network.enable');
    await client.send('Runtime.enable');
    await client.send('Log.enable');
    await client.send('DOMStorage.enable');

    // === Network: Track all requests and failures ===
    const requests = new Map();

    client.on('Network.requestWillBeSent', (params) => {
      requests.set(params.requestId, {
        url: params.request.url,
        method: params.request.method,
        type: params.type,
        timestamp: params.timestamp,
        headers: params.request.headers,
        initiator: params.initiator?.type
      });
    });

    client.on('Network.responseReceived', (params) => {
      const req = requests.get(params.requestId);
      if (req) {
        req.status = params.response.status;
        req.statusText = params.response.statusText;
        req.mimeType = params.response.mimeType;
        req.responseHeaders = params.response.headers;
        if (params.response.status >= 400) {
          globalThis.__debugData.networkFailures.push({
            ...req,
            failureType: 'http-error'
          });
        }
      }
    });

    client.on('Network.loadingFailed', (params) => {
      const req = requests.get(params.requestId);
      globalThis.__debugData.networkFailures.push({
        url: req?.url || 'unknown',
        method: req?.method || 'unknown',
        type: req?.type || 'unknown',
        errorText: params.errorText,
        canceled: params.canceled,
        blockedReason: params.blockedReason,
        corsErrorStatus: params.corsErrorStatus,
        failureType: 'load-failed'
      });
    });

    // === Console and Runtime Errors ===
    client.on('Runtime.consoleAPICalled', (params) => {
      const entry = {
        type: params.type,
        timestamp: params.timestamp,
        args: params.args.map(a => a.value || a.description || a.type).join(' '),
        stackTrace: params.stackTrace?.callFrames?.slice(0, 3).map(f =>
          f.functionName + ' (' + f.url + ':' + f.lineNumber + ')'
        )
      };
      globalThis.__debugData.console.push(entry);
      if (params.type === 'error') globalThis.__debugData.errors.push(entry);
      if (params.type === 'warning') globalThis.__debugData.warnings.push(entry);
    });

    client.on('Runtime.exceptionThrown', (params) => {
      globalThis.__debugData.uncaughtExceptions.push({
        text: params.exceptionDetails.text,
        description: params.exceptionDetails.exception?.description,
        url: params.exceptionDetails.url,
        line: params.exceptionDetails.lineNumber,
        column: params.exceptionDetails.columnNumber,
        stackTrace: params.exceptionDetails.stackTrace?.callFrames?.slice(0, 5).map(f =>
          f.functionName + ' (' + f.url + ':' + f.lineNumber + ')'
        )
      });
    });

    // === Log Domain (catches network errors, security errors, etc.) ===
    client.on('Log.entryAdded', (params) => {
      if (params.entry.level === 'error' || params.entry.level === 'warning') {
        globalThis.__debugData.console.push({
          type: params.entry.level,
          source: params.entry.source,
          text: params.entry.text,
          url: params.entry.url,
          timestamp: params.entry.timestamp
        });
      }
    });

    // Store CDP client and requests map for later harvest
    globalThis.__debugCDP = { client, requests };

    return 'All debugging instrumentation installed: Network + Runtime + Log + DOMStorage';
  }`
})
```

### Step 2 — Install In-Page Error Handlers

Install unhandled rejection and error listeners directly on the page:

```javascript
browser_evaluate({
  function: `() => {
    window.addEventListener('unhandledrejection', (event) => {
      window.__unhandledRejections = window.__unhandledRejections || [];
      window.__unhandledRejections.push({
        reason: event.reason?.message || event.reason?.toString() || 'Unknown',
        stack: event.reason?.stack?.split('\\n').slice(0, 5)
      });
    });

    window.addEventListener('error', (event) => {
      window.__pageErrors = window.__pageErrors || [];
      window.__pageErrors.push({
        message: event.message,
        filename: event.filename,
        line: event.lineno,
        column: event.colno,
        stack: event.error?.stack?.split('\\n').slice(0, 5)
      });
    });

    return 'In-page error handlers installed';
  }`
})
```

## Phase 2: Navigate and Wait for Failures

### Step 1 — Navigate to the target URL

```
browser_navigate({ url: "<TARGET_URL>" })
```

### Step 2 — Wait for page to settle

Wait 3-5 seconds for async operations to complete, API calls to return, and errors to manifest:

```
browser_wait_for({ time: 5 })
```

## Phase 3: Harvest All Diagnostic Data

### Step 1 — Harvest CDP data (network requests, storage)

```javascript
browser_run_code({
  code: `async (page) => {
    const client = globalThis.__debugCDP.client;
    const requests = globalThis.__debugCDP.requests;

    // Finalize network requests
    globalThis.__debugData.networkRequests = Array.from(requests.values());

    // Get cookies via CDP
    const { cookies } = await client.send('Network.getCookies');
    globalThis.__debugData.cookies = cookies.map(c => ({
      name: c.name,
      domain: c.domain,
      path: c.path,
      secure: c.secure,
      httpOnly: c.httpOnly,
      sameSite: c.sameSite,
      expires: c.expires,
      size: c.size,
      valueLength: c.value.length
    }));

    return JSON.stringify({
      totalRequests: globalThis.__debugData.networkRequests.length,
      failedRequests: globalThis.__debugData.networkFailures.length,
      consoleEntries: globalThis.__debugData.console.length,
      errors: globalThis.__debugData.errors.length,
      warnings: globalThis.__debugData.warnings.length,
      uncaughtExceptions: globalThis.__debugData.uncaughtExceptions.length,
      cookies: globalThis.__debugData.cookies.length
    });
  }`
})
```

### Step 2 — Harvest in-page data (storage, framework state, errors)

```javascript
browser_evaluate({
  function: `() => {
    // === Local Storage ===
    const ls = {};
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      const value = localStorage.getItem(key);
      ls[key] = value.length > 200 ? value.substring(0, 200) + '...[truncated]' : value;
    }

    // === Session Storage ===
    const ss = {};
    for (let i = 0; i < sessionStorage.length; i++) {
      const key = sessionStorage.key(i);
      const value = sessionStorage.getItem(key);
      ss[key] = value.length > 200 ? value.substring(0, 200) + '...[truncated]' : value;
    }

    // === Framework State Detection ===
    let frameworkState = null;

    // React
    const reactRoot = document.querySelector('[data-reactroot], #root, #__next');
    if (reactRoot) {
      const fiberKey = Object.keys(reactRoot).find(k => k.startsWith('__reactFiber') || k.startsWith('__reactInternalInstance'));
      frameworkState = { framework: 'React', detected: true, hasErrors: !!document.querySelector('.error-boundary, [data-error]') };
    }

    // Vue
    if (window.__VUE_DEVTOOLS_GLOBAL_HOOK__ || document.querySelector('[data-v-]')) {
      const vueApp = document.querySelector('#app')?.__vue_app__ || document.querySelector('[data-v-app]')?.__vue_app__;
      frameworkState = { framework: 'Vue', detected: true, version: vueApp?.version || 'unknown' };
    }

    // Angular
    if (window.ng || document.querySelector('[ng-version]')) {
      frameworkState = { framework: 'Angular', detected: true, version: document.querySelector('[ng-version]')?.getAttribute('ng-version') };
    }

    // Next.js
    if (window.__NEXT_DATA__) {
      frameworkState = {
        framework: 'Next.js',
        detected: true,
        buildId: window.__NEXT_DATA__.buildId,
        page: window.__NEXT_DATA__.page,
        hasRuntimeConfig: !!window.__NEXT_DATA__.runtimeConfig,
        props: window.__NEXT_DATA__.props ? Object.keys(window.__NEXT_DATA__.props) : []
      };
    }

    // Nuxt
    if (window.__NUXT__) {
      frameworkState = {
        framework: 'Nuxt',
        detected: true,
        error: window.__NUXT__.error,
        state: window.__NUXT__.state ? Object.keys(window.__NUXT__.state) : []
      };
    }

    return {
      localStorage: ls,
      localStorageKeys: Object.keys(ls).length,
      sessionStorage: ss,
      sessionStorageKeys: Object.keys(ss).length,
      frameworkState,
      unhandledRejections: window.__unhandledRejections || [],
      pageErrors: window.__pageErrors || [],
      documentTitle: document.title,
      documentReadyState: document.readyState,
      currentUrl: window.location.href
    };
  }`
})
```

### Step 3 — Get console messages and network requests from Playwright APIs

Run in parallel:

```
browser_console_messages({ level: "error" })
browser_network_requests({ includeStatic: false })
```

### Step 4 — Capture visual state

```
browser_take_screenshot({ type: "png", fullPage: true })
browser_snapshot()
```

## Phase 4: Targeted Error Injection (Based on Findings)

Based on what you found in Phase 3, run targeted error injections. Choose the relevant tests:

### If network failures detected — Test error handling:

```javascript
browser_run_code({
  code: `async (page) => {
    // Block the failing API endpoint and reload to test error UI
    const failedUrls = ${JSON.stringify(failedUrls)};  // Use actual URLs from Phase 3

    for (const url of failedUrls.slice(0, 3)) {
      await page.route(url, route => route.abort('failed'));
    }

    await page.reload({ waitUntil: 'networkidle' });

    // Check if error states are shown gracefully
    const errorElements = await page.$$eval('[class*="error"], [class*="Error"], [role="alert"]',
      els => els.map(e => ({ tag: e.tagName, text: e.textContent.trim().substring(0, 100), visible: e.offsetHeight > 0 }))
    );

    return { errorElements, errorHandlingDetected: errorElements.length > 0 };
  }`
})
```

### If JavaScript errors detected — Test with slow network:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    // Simulate slow 3G
    await client.send('Network.emulateNetworkConditions', {
      offline: false,
      downloadThroughput: 50000,   // 400 kbps
      uploadThroughput: 25000,     // 200 kbps
      latency: 400                 // 400ms RTT
    });

    await page.reload({ waitUntil: 'networkidle', timeout: 30000 });

    const errors = await page.evaluate(() => window.__pageErrors || []);

    // Reset network conditions
    await client.send('Network.emulateNetworkConditions', {
      offline: false, downloadThroughput: -1, uploadThroughput: -1, latency: 0
    });

    return { slowNetworkErrors: errors };
  }`
})
```

### If storage-related issues suspected — Test with cleared storage:

```javascript
browser_evaluate({
  function: `() => {
    const beforeKeys = {
      localStorage: Object.keys(localStorage),
      sessionStorage: Object.keys(sessionStorage)
    };
    localStorage.clear();
    sessionStorage.clear();
    return { cleared: true, previousKeys: beforeKeys };
  }`
})
```

Then reload and observe:

```
browser_navigate({ url: "<TARGET_URL>" })
browser_wait_for({ time: 3 })
browser_console_messages({ level: "error" })
```

## Phase 5: Report

Compile all findings into a structured debugging report:

```markdown
# Debug Report: <URL>

## Summary
- **Page Status:** [Working / Partially Broken / Fully Broken]
- **Root Cause (suspected):** [Brief description]
- **Framework:** [Detected framework and version]

## Console Errors (N total)
| # | Type | Message | Source |
|---|------|---------|--------|
| 1 | error | ... | file.js:42 |
...

## Uncaught Exceptions (N total)
| # | Error | File | Line | Stack |
|---|-------|------|------|-------|
...

## Network Failures (N of M requests failed)
| # | URL | Method | Error | Type |
|---|-----|--------|-------|------|
...

## Storage State
### Local Storage (N keys)
| Key | Value (preview) | Size |
...

### Session Storage (N keys)
...

### Cookies (N total)
| Name | Domain | Flags | Issues |
...

## Framework State
- Framework: X v.Y
- Error boundary active: Yes/No
- Relevant state: ...

## Error Injection Results
### Network failure handling: [Graceful / Ungraceful / None]
- Details: ...

### Slow network behavior: [Tolerant / Errors / Timeout]
- Details: ...

### Storage clear behavior: [Handles / Crashes]
- Details: ...

## Root Cause Analysis
1. Primary issue: ...
2. Contributing factors: ...
3. Error chain: ...

## Recommendations
1. [Priority: High] ...
2. [Priority: Medium] ...
3. [Priority: Low] ...
```
