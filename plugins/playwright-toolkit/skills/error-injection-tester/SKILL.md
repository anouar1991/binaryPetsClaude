---
name: error-injection-tester
description: >
  Test application resilience by injecting failures: offline mode, blocked
  resources, API error responses (500/403/timeout), JS exceptions, localStorage
  quota exceeded, and slow network (3G). Captures app response to each failure
  including error UI, console errors, and graceful degradation.
---

# Error Injection Tester

Systematically inject failures into a running web application to evaluate its
resilience, error handling UI, and graceful degradation behavior. Each injection
is isolated, documented with screenshots, and console output is captured.

## When to Use

- Verifying error boundaries and fallback UI render correctly.
- Testing offline/network-failure behavior before shipping a PWA.
- Ensuring API error responses produce user-friendly messages.
- Checking that third-party resource failures do not break the page.
- Validating storage quota handling for localStorage-heavy apps.
- Simulating slow networks to test loading states and timeouts.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP network emulation and blocked URLs.
- Target page must be loaded before injections begin.

## Workflow

### Step 1 -- Navigate and Establish Baseline

```
browser_navigate({ url: "<target_url>" })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-baseline.png" })
```

```
browser_console_messages({ level: "error" })
```

### Step 2 -- Test Offline Mode

Simulate a complete network disconnection.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');
    await client.send('Network.emulateNetworkConditions', {
      offline: true,
      latency: 0,
      downloadThroughput: 0,
      uploadThroughput: 0
    });
    return 'Network set to offline';
  }`
})
```

Trigger an action that requires network (e.g., click a button, navigate):

```javascript
browser_evaluate({
  function: `() => {
    // Attempt a fetch to trigger offline behavior
    fetch(window.location.href).catch(err => {
      window.__offlineError = err.message;
    });
    return 'Fetch attempted while offline';
  }`
})
```

```
browser_wait_for({ time: 3 })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-offline.png" })
```

```
browser_console_messages({ level: "error" })
```

Restore network:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 0,
      downloadThroughput: -1,
      uploadThroughput: -1
    });
    return 'Network restored';
  }`
})
```

### Step 3 -- Test Blocked Resources (CSS/JS/Images)

Block specific resource types and reload to see degraded rendering.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');
    await client.send('Network.setBlockedURLs', {
      urls: ['*.css', '*.js']
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    return 'CSS and JS blocked, page reloaded';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-no-css-js.png" })
```

```
browser_console_messages({ level: "error" })
```

Unblock and test image blocking:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.setBlockedURLs', {
      urls: ['*.png', '*.jpg', '*.jpeg', '*.webp', '*.gif', '*.svg', '*.avif']
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    return 'Images blocked, page reloaded';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-no-images.png" })
```

Clear blocked URLs:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.setBlockedURLs', { urls: [] });
    await page.reload({ waitUntil: 'load' });
    return 'Blocks cleared, page reloaded';
  }`
})
```

### Step 4 -- Inject API Error Responses (500, 403, Timeout)

Intercept API calls and return error responses.

**500 Internal Server Error:**

```javascript
browser_run_code({
  code: `async (page) => {
    await page.route('**/api/**', route => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Internal Server Error', message: 'Injected 500 by error-injection-tester' })
      });
    });
    return 'API routes intercepted with 500 responses';
  }`
})
```

Trigger an API call (click a button or interact with the page using
`browser_snapshot` + `browser_click`), then capture the result:

```
browser_wait_for({ time: 3 })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-api-500.png" })
```

```
browser_console_messages({ level: "error" })
```

**403 Forbidden:**

```javascript
browser_run_code({
  code: `async (page) => {
    await page.unrouteAll();
    await page.route('**/api/**', route => {
      route.fulfill({
        status: 403,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Forbidden', message: 'Injected 403 by error-injection-tester' })
      });
    });
    return 'API routes intercepted with 403 responses';
  }`
})
```

```
browser_wait_for({ time: 3 })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-api-403.png" })
```

**Timeout (30-second hang):**

```javascript
browser_run_code({
  code: `async (page) => {
    await page.unrouteAll();
    await page.route('**/api/**', route => {
      // Never respond -- simulates a timeout
      // The route will hang until navigation or unroute
    });
    return 'API routes intercepted with infinite hang (timeout simulation)';
  }`
})
```

```
browser_wait_for({ time: 10 })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-api-timeout.png" })
```

Clean up routes:

```javascript
browser_run_code({
  code: `async (page) => {
    await page.unrouteAll();
    return 'All route intercepts removed';
  }`
})
```

### Step 5 -- Inject JavaScript Exceptions

Test that error boundaries catch unhandled errors.

```javascript
browser_evaluate({
  function: `() => {
    // Inject unhandled error
    window.__errorsCaught = [];
    const origHandler = window.onerror;
    window.onerror = (msg, src, line, col, err) => {
      window.__errorsCaught.push({ msg, src, line, col });
      if (origHandler) origHandler(msg, src, line, col, err);
    };

    // Throw in a timeout to simulate async error
    setTimeout(() => {
      throw new Error('Injected error: Component render failure simulation');
    }, 100);

    // Throw in a promise to test unhandled rejection
    Promise.reject(new Error('Injected unhandled promise rejection'));

    return 'JS exceptions injected';
  }`
})
```

```
browser_wait_for({ time: 2 })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-js-error.png" })
```

```
browser_console_messages({ level: "error" })
```

```javascript
browser_evaluate({
  function: `() => {
    return {
      errorsCaught: window.__errorsCaught || [],
      errorBoundaryVisible: !!document.querySelector('[class*="error"], [class*="fallback"], [role="alert"]')
    };
  }`
})
```

### Step 6 -- Inject localStorage Quota Exceeded

Simulate storage quota being exceeded.

```javascript
browser_evaluate({
  function: `() => {
    const results = { filled: false, error: null };
    try {
      // Fill localStorage with large data
      const chunk = 'x'.repeat(1024 * 1024); // 1MB chunks
      for (let i = 0; i < 20; i++) {
        try {
          localStorage.setItem('__quota_test_' + i, chunk);
        } catch (e) {
          results.filled = true;
          results.error = e.message;
          results.itemsBeforeQuota = i;
          break;
        }
      }

      // If we didn't hit quota naturally, override setItem
      if (!results.filled) {
        const origSetItem = localStorage.setItem.bind(localStorage);
        localStorage.setItem = function(key, value) {
          if (!key.startsWith('__quota_test_')) {
            throw new DOMException('QuotaExceededError', 'QuotaExceededError');
          }
          origSetItem(key, value);
        };
        results.filled = true;
        results.error = 'setItem overridden to throw QuotaExceededError';
      }
    } catch (e) {
      results.error = e.message;
    }
    return results;
  }`
})
```

Trigger an action that writes to localStorage, then capture:

```
browser_wait_for({ time: 2 })
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-storage-quota.png" })
```

```
browser_console_messages({ level: "error" })
```

Clean up:

```javascript
browser_evaluate({
  function: `() => {
    // Remove test keys
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key && key.startsWith('__quota_test_')) keys.push(key);
    }
    keys.forEach(k => localStorage.removeItem(k));

    // Restore setItem if overridden (reload is more reliable)
    return 'Cleaned up ' + keys.length + ' test keys';
  }`
})
```

### Step 7 -- Test Slow Network (3G Simulation)

Emulate a slow 3G connection and reload the page.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');
    await client.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 400,
      downloadThroughput: 400 * 1024 / 8,   // 400 kbps
      uploadThroughput: 400 * 1024 / 8       // 400 kbps
    });
    const start = Date.now();
    await page.reload({ waitUntil: 'load', timeout: 60000 });
    const loadTime = Date.now() - start;
    return 'Page loaded on 3G in ' + loadTime + 'ms';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-slow-3g.png" })
```

Capture loading state mid-load (optional -- reload with shorter wait):

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 400,
      downloadThroughput: 400 * 1024 / 8,
      uploadThroughput: 400 * 1024 / 8
    });
    // Reload but capture mid-load
    page.reload({ waitUntil: 'load', timeout: 60000 });
    await page.waitForTimeout(2000); // Capture at 2s into load
    return 'Mid-load state captured';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "error-injection-slow-3g-loading.png" })
```

Restore normal network:

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 0,
      downloadThroughput: -1,
      uploadThroughput: -1
    });
    return 'Network conditions reset to normal';
  }`
})
```

### Step 8 -- Compile Results

Gather all console errors from the session:

```
browser_console_messages({ level: "error" })
```

## Interpreting Results

### Report Format

```
## Error Injection Audit -- <url>

### Offline Mode
- Behavior: [error message shown / blank page / cached version / spinner]
- Service Worker: [active / not registered]
- Screenshot: error-injection-offline.png

### Blocked Resources
- Without CSS/JS: [unstyled content / blank / partial render]
- Without Images: [alt text shown / broken icons / placeholders]
- Screenshots: error-injection-no-css-js.png, error-injection-no-images.png

### API Errors
| Scenario | App Response | User-Facing Message | Console Errors |
|----------|-------------|---------------------|----------------|
| 500      | Error toast  | "Something went wrong" | 0            |
| 403      | Redirect to login | "Session expired" | 0           |
| Timeout  | Spinner forever | None shown | 1 (timeout)    |

### JS Exceptions
- Error boundary activated: [yes/no]
- Fallback UI shown: [yes/no]
- Unhandled rejections caught: [count]

### Storage Quota
- Graceful handling: [yes/no]
- User notification: [yes/no]

### Slow Network (3G)
- Full load time: 12,400ms
- Loading states visible: [yes/no]
- Content prioritization: [above-fold loads first / all at once]
```

### What to Look For

- **Offline: blank page or uncaught errors**: the app lacks a service worker or offline fallback. Consider adding cache-first strategies for critical resources.
- **Blocked CSS shows no content**: critical CSS should be inlined in `<head>` for progressive rendering.
- **API 500 with no user feedback**: missing error boundaries or try/catch around fetch calls.
- **API timeout with infinite spinner**: no request timeout configured. Add `AbortController` with a reasonable timeout.
- **JS errors crash the page**: missing React Error Boundaries or global `window.onerror` handler.
- **Storage quota silently fails**: data loss risk. Wrap `setItem` in try/catch and notify the user.
- **3G with no loading indicators**: users see a blank screen. Add skeleton screens or progress indicators.

## Limitations

- **Chromium only**: CDP `Network.emulateNetworkConditions` and `Network.setBlockedURLs` are Chromium-specific.
- **Route interception scope**: `page.route()` only intercepts requests from the current page. Service Worker fetch events may bypass route interception.
- **localStorage override**: overriding `localStorage.setItem` only affects code that runs after the override. Code that cached a reference to the original method will bypass it.
- **3G simulation is approximate**: actual 3G has variable latency and bandwidth. The emulation uses fixed values.
- **Error boundary detection**: the heuristic looks for elements with `error`, `fallback`, or `role="alert"` classes/attributes. Custom error UI with different naming will not be detected automatically.
