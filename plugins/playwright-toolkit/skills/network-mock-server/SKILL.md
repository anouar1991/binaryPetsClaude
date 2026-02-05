---
name: network-mock-server
description: >
  Set up request interception to mock API responses: record real responses for
  baseline, replay them deterministically, modify response fields, add latency
  per endpoint, simulate errors, and persist mocks across navigation. Supports
  both Playwright page.route() and CDP Fetch domain for lower-level control.
---

# Network Mock Server

Create a flexible API mocking layer that intercepts network requests and returns
controlled responses. Record real API responses as a baseline, then replay,
modify, or replace them for testing. Mocks persist across page navigations
within the same browser context.

## When to Use

- Testing frontend behavior against specific API response shapes.
- Reproducing edge cases by modifying real API response fields.
- Simulating slow endpoints to test loading states and timeouts.
- Testing error handling by returning specific HTTP status codes per endpoint.
- Creating deterministic test environments that do not depend on backend availability.
- Recording API responses for offline development or snapshot testing.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP `Fetch.enable` (optional, for lower-level control).
- Target page must make API requests (XHR/fetch) that you want to intercept.

## Workflow

### Step 1 -- Navigate and Record Baseline API Responses

First, load the page normally and capture all API responses as a baseline.

```
browser_navigate({ url: "<target_url>" })
```

```
browser_wait_for({ time: 5 })
```

Capture all network requests made during page load:

```
browser_network_requests({ includeStatic: false })
```

### Step 2 -- Record Detailed API Responses

Install a response recorder that captures full response bodies for API calls.

```javascript
browser_run_code({
  code: `async (page) => {
    const recorded = [];

    // Listen to all responses
    page.on('response', async (response) => {
      const url = response.url();
      // Only record API calls, skip static assets
      if (url.includes('/api/') || url.includes('/graphql') ||
          response.request().resourceType() === 'xhr' ||
          response.request().resourceType() === 'fetch') {
        try {
          const body = await response.text();
          recorded.push({
            url: url,
            method: response.request().method(),
            status: response.status(),
            headers: response.headers(),
            contentType: response.headers()['content-type'] || null,
            body: body.substring(0, 50000),
            timestamp: Date.now()
          });
        } catch (e) {
          recorded.push({
            url: url,
            method: response.request().method(),
            status: response.status(),
            error: 'Could not read body: ' + e.message,
            timestamp: Date.now()
          });
        }
      }
    });

    // Store reference for later harvest
    page.__recordedResponses = recorded;

    // Reload to capture from scratch
    await page.reload({ waitUntil: 'networkidle' });

    return 'Response recorder installed and page reloaded';
  }`
})
```

### Step 3 -- Harvest Recorded Responses

```javascript
browser_run_code({
  code: `async (page) => {
    const recorded = page.__recordedResponses || [];
    return {
      totalRecorded: recorded.length,
      endpoints: recorded.map(r => ({
        method: r.method,
        url: r.url,
        status: r.status,
        contentType: r.contentType,
        bodySize: r.body ? r.body.length : 0,
        bodyPreview: r.body ? r.body.substring(0, 500) : null
      }))
    };
  }`
})
```

### Step 4 -- Set Up Mock Replay (Exact Replay)

Replay recorded responses for deterministic behavior.

```javascript
browser_run_code({
  code: `async (page) => {
    const recorded = page.__recordedResponses || [];
    if (recorded.length === 0) return { error: 'No recorded responses to replay' };

    // Build a lookup map: method+url -> response
    const mockMap = {};
    for (const r of recorded) {
      const key = r.method + ' ' + new URL(r.url).pathname;
      if (!mockMap[key]) mockMap[key] = r; // First response wins
    }

    // Clear any existing routes
    await page.unrouteAll();

    // Install mock routes
    await page.route('**/*', (route) => {
      const req = route.request();
      const key = req.method() + ' ' + new URL(req.url()).pathname;
      const mock = mockMap[key];

      if (mock) {
        route.fulfill({
          status: mock.status,
          contentType: mock.contentType || 'application/json',
          body: mock.body,
          headers: { 'x-mocked': 'true' }
        });
      } else {
        // Pass through non-mocked requests
        route.continue();
      }
    });

    return {
      mockedEndpoints: Object.keys(mockMap).length,
      endpoints: Object.keys(mockMap)
    };
  }`
})
```

### Step 5 -- Mock with Modified Responses

Modify specific fields in recorded responses (e.g., change user name, empty arrays,
alter counts).

```javascript
browser_run_code({
  code: `async (page) => {
    await page.unrouteAll();

    // Example: modify a specific endpoint's response
    await page.route('**/api/users**', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { 'x-mocked': 'modified' },
        body: JSON.stringify({
          users: [
            { id: 1, name: 'Mock User 1', email: 'mock1@test.com', role: 'admin' },
            { id: 2, name: 'Mock User 2', email: 'mock2@test.com', role: 'user' }
          ],
          total: 2,
          page: 1
        })
      });
    });

    // Example: return empty collection
    await page.route('**/api/notifications**', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { 'x-mocked': 'empty' },
        body: JSON.stringify({ notifications: [], unread: 0 })
      });
    });

    // Pass through everything else
    await page.route('**/*', (route) => {
      if (!route.request().url().includes('/api/users') &&
          !route.request().url().includes('/api/notifications')) {
        route.continue();
      }
    });

    return 'Modified mocks installed for /api/users and /api/notifications';
  }`
})
```

Reload and verify:

```javascript
browser_run_code({
  code: `async (page) => {
    await page.reload({ waitUntil: 'networkidle' });
    return 'Page reloaded with modified mocks';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "mock-modified-response.png" })
```

### Step 6 -- Mock with Latency

Add artificial delay to specific endpoints to test loading states.

```javascript
browser_run_code({
  code: `async (page) => {
    await page.unrouteAll();

    await page.route('**/api/**', async (route) => {
      const url = route.request().url();

      // Add 3-second delay to specific endpoints
      if (url.includes('/api/search') || url.includes('/api/data')) {
        await new Promise(resolve => setTimeout(resolve, 3000));
      }

      // Add 1-second delay to all other API calls
      else {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }

      // Continue to real server (with delay applied)
      route.continue();
    });

    return 'Latency mocks installed: 3s for search/data, 1s for other APIs';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "mock-latency-loading.png" })
```

### Step 7 -- Mock Error Responses Per Endpoint

Return different error codes for different endpoints.

```javascript
browser_run_code({
  code: `async (page) => {
    await page.unrouteAll();

    const errorConfig = {
      '/api/auth': { status: 401, body: { error: 'Unauthorized', message: 'Token expired' } },
      '/api/users': { status: 500, body: { error: 'Internal Server Error', message: 'Database connection failed' } },
      '/api/upload': { status: 413, body: { error: 'Payload Too Large', message: 'File exceeds 10MB limit' } },
      '/api/search': { status: 429, body: { error: 'Too Many Requests', message: 'Rate limit exceeded. Retry after 60s', retryAfter: 60 } }
    };

    await page.route('**/api/**', (route) => {
      const pathname = new URL(route.request().url()).pathname;

      for (const [pattern, config] of Object.entries(errorConfig)) {
        if (pathname.includes(pattern)) {
          route.fulfill({
            status: config.status,
            contentType: 'application/json',
            headers: { 'x-mocked': 'error' },
            body: JSON.stringify(config.body)
          });
          return;
        }
      }

      // Pass through non-configured endpoints
      route.continue();
    });

    return 'Error mocks installed: ' + Object.entries(errorConfig).map(([k,v]) => k + ' -> ' + v.status).join(', ');
  }`
})
```

```javascript
browser_run_code({
  code: `async (page) => {
    await page.reload({ waitUntil: 'domcontentloaded' });
    return 'Page reloaded with error mocks';
  }`
})
```

```
browser_take_screenshot({ type: "png", filename: "mock-error-responses.png" })
```

### Step 8 -- CDP Fetch Domain for Lower-Level Control (Optional)

Use the CDP Fetch domain for intercepting requests at the network level,
before they reach the service worker or browser cache.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    // Enable Fetch domain to intercept requests
    await client.send('Fetch.enable', {
      patterns: [
        { urlPattern: '*/api/*', requestStage: 'Response' }
      ]
    });

    client.on('Fetch.requestPaused', async (params) => {
      try {
        // Get the original response
        const response = await client.send('Fetch.getResponseBody', {
          requestId: params.requestId
        });

        // Decode the body
        let body = response.base64Encoded
          ? Buffer.from(response.body, 'base64').toString('utf-8')
          : response.body;

        // Modify the response (example: inject a field)
        try {
          const json = JSON.parse(body);
          json.__mocked = true;
          json.__mockTimestamp = Date.now();
          body = JSON.stringify(json);
        } catch {} // Not JSON, pass through

        // Fulfill with modified response
        await client.send('Fetch.fulfillRequest', {
          requestId: params.requestId,
          responseCode: params.responseStatusCode,
          responseHeaders: params.responseHeaders,
          body: Buffer.from(body).toString('base64')
        });
      } catch (e) {
        // If modification fails, continue with original
        await client.send('Fetch.continueRequest', {
          requestId: params.requestId
        });
      }
    });

    return 'CDP Fetch domain interceptor installed';
  }`
})
```

### Step 9 -- Verify Mocked Data Received by Application

Confirm that the frontend received and rendered the mocked data.

```javascript
browser_evaluate({
  function: `() => {
    // Check if mocked data is visible in the DOM
    const bodyText = document.body.innerText;
    const results = {
      mockUserVisible: bodyText.includes('Mock User'),
      pageContent: bodyText.substring(0, 1000)
    };

    // Check for mock indicators in recent fetch responses
    if (window.performance) {
      const entries = performance.getEntriesByType('resource')
        .filter(e => e.name.includes('/api/'))
        .slice(-10);
      results.recentApiCalls = entries.map(e => ({
        url: e.name,
        duration: Math.round(e.duration),
        transferSize: e.transferSize
      }));
    }

    return results;
  }`
})
```

### Step 10 -- Clean Up All Mocks

```javascript
browser_run_code({
  code: `async (page) => {
    // Remove all Playwright route handlers
    await page.unrouteAll();

    // Disable CDP Fetch if it was enabled
    try {
      const client = await page.context().newCDPSession(page);
      await client.send('Fetch.disable');
    } catch {}

    // Reload to get real responses
    await page.reload({ waitUntil: 'networkidle' });
    return 'All mocks cleared, page reloaded with real responses';
  }`
})
```

## Interpreting Results

### Report Format

```
## Network Mock Server -- <url>

### Recorded Baseline
| # | Method | Endpoint | Status | Size | Content-Type |
|---|--------|----------|--------|------|--------------|
| 1 | GET | /api/users | 200 | 2.4KB | application/json |
| 2 | GET | /api/notifications | 200 | 890B | application/json |
| 3 | POST | /api/search | 200 | 12.1KB | application/json |
| 4 | GET | /api/config | 200 | 340B | application/json |

### Active Mocks
| Endpoint | Mode | Config |
|----------|------|--------|
| /api/users | modified | 2 mock users, role=admin |
| /api/notifications | empty | {notifications: [], unread: 0} |
| /api/search | latency | 3000ms delay, real response |
| /api/auth | error | 401 Token expired |

### Verification
- Mock User 1 visible in UI: yes
- Empty notification badge: yes
- Loading spinner during search: yes (3s)
- Login redirect on auth error: yes
```

### What to Look For

- **Empty state rendering**: mock endpoints with empty arrays to verify the app shows appropriate empty states (not broken layouts or errors).
- **Loading state quality**: add latency to observe loading indicators. Missing loading states cause perceived freezes.
- **Error message clarity**: mock error responses to check that user-facing error messages are helpful and specific (not "Something went wrong").
- **Auth token expiry handling**: mock 401 responses to verify the app redirects to login or refreshes tokens.
- **Rate limit handling**: mock 429 with `retryAfter` to verify the app respects rate limits and shows appropriate feedback.
- **Large payload handling**: record real responses and check if the app handles large datasets gracefully (pagination, virtual scrolling).

## Limitations

- **page.route() scope**: Playwright route handlers are scoped to the page instance. They do not intercept requests from Service Workers, Web Workers, or other pages in the context.
- **Navigation persistence**: `page.route()` handlers persist across same-page navigations but are lost if the page is closed. CDP Fetch domain handlers persist across navigations within the same CDP session.
- **Response body recording**: large response bodies (>50KB) are truncated during recording to prevent memory issues. Binary responses (images, fonts) are not recorded.
- **GraphQL**: GraphQL endpoints all use the same URL with different query bodies. URL-based matching will intercept all GraphQL requests. Use request body inspection (via CDP Fetch) for fine-grained GraphQL mocking.
- **CORS**: mocked responses do not automatically include CORS headers. If the frontend expects specific CORS headers, include them in the mock response headers.
- **Timing accuracy**: `setTimeout`-based latency in `page.route()` is approximate and adds to any real network latency if `route.continue()` is used after the delay.
