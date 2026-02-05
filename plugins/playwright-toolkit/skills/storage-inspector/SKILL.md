---
name: storage-inspector
description: >
  Dump and analyze all client-side storage: localStorage, sessionStorage,
  cookies with full attributes, IndexedDB schemas and record counts,
  Cache API contents, and storage quota usage via CDP Storage and
  IndexedDB domains.
---

# Storage Inspector

Perform a comprehensive audit of all client-side storage mechanisms used by a
web page. Extracts localStorage, sessionStorage, cookies with full attributes,
IndexedDB database schemas with record counts and estimated sizes, Cache API
cached URLs, and overall storage quota usage.

## When to Use

- Debugging data persistence issues (missing or stale stored values).
- Auditing what data a site stores on the client for privacy review.
- Identifying storage quota pressure from large IndexedDB databases or caches.
- Detecting stale or orphaned storage entries from deprecated features.
- Understanding cookie sprawl across domains and their security attributes.
- Investigating Cache API contents for service worker debugging.

## Prerequisites

- **Playwright MCP server** connected and responding.
- **Chromium-based browser** for CDP DOMStorage, IndexedDB, Storage, and Network domains.
- Target page must be navigated to before inspection (storage is origin-scoped).

## Workflow

### Phase 1: Navigate to Target

Storage inspection is origin-scoped, so we must navigate first.

```
browser_navigate({ url: "<target_url>" })
```

```
browser_wait_for({ time: 3 })
```

### Phase 2: Enable CDP Domains and Get Storage Origin

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    await client.send('DOMStorage.enable');
    await client.send('IndexedDB.enable');

    const origin = await page.evaluate(() => window.location.origin);

    globalThis.__storageInspector = { client, origin };
    return 'Storage inspector ready for origin: ' + origin;
  }`
})
```

### Phase 3: Inspect localStorage and sessionStorage

```javascript
browser_run_code({
  code: `async (page) => {
    const { client, origin } = globalThis.__storageInspector;

    // localStorage
    const localStorageId = { securityOrigin: origin, isLocalStorage: true };
    const localItems = await client.send('DOMStorage.getDOMStorageItems', { storageId: localStorageId });

    // sessionStorage
    const sessionStorageId = { securityOrigin: origin, isLocalStorage: false };
    const sessionItems = await client.send('DOMStorage.getDOMStorageItems', { storageId: sessionStorageId });

    const analyzeItems = (items) => {
      return items.map(([key, value]) => {
        let parsedType = 'string';
        let size = key.length + value.length;
        try {
          const parsed = JSON.parse(value);
          parsedType = Array.isArray(parsed) ? 'array' : typeof parsed;
        } catch { /* not JSON */ }
        return {
          key,
          value: value.substring(0, 200) + (value.length > 200 ? '...' : ''),
          fullLength: value.length,
          sizeBytes: size * 2, // UTF-16
          type: parsedType
        };
      });
    };

    return {
      localStorage: {
        count: localItems.entries.length,
        totalSizeBytes: localItems.entries.reduce((s, [k, v]) => s + (k.length + v.length) * 2, 0),
        items: analyzeItems(localItems.entries)
      },
      sessionStorage: {
        count: sessionItems.entries.length,
        totalSizeBytes: sessionItems.entries.reduce((s, [k, v]) => s + (k.length + v.length) * 2, 0),
        items: analyzeItems(sessionItems.entries)
      }
    };
  }`
})
```

### Phase 4: Inspect Cookies

```javascript
browser_run_code({
  code: `async (page) => {
    const { client, origin } = globalThis.__storageInspector;
    const { cookies } = await client.send('Network.getAllCookies');

    // Filter to relevant domain
    const hostname = new URL(origin).hostname;
    const relevantCookies = cookies.filter(c =>
      hostname.endsWith(c.domain.replace(/^\\./, '')) || c.domain === hostname
    );

    const analyzed = relevantCookies.map(c => ({
      name: c.name,
      value: (c.value || '').substring(0, 100) + (c.value && c.value.length > 100 ? '...' : ''),
      domain: c.domain,
      path: c.path,
      secure: c.secure,
      httpOnly: c.httpOnly,
      sameSite: c.sameSite || 'None',
      expires: c.expires === -1 ? 'Session' : new Date(c.expires * 1000).toISOString(),
      size: c.size,
      priority: c.priority,
      sameParty: c.sameParty || false
    }));

    const totalSize = analyzed.reduce((s, c) => s + c.size, 0);

    return {
      total: analyzed.length,
      totalSizeBytes: totalSize,
      sessionCookies: analyzed.filter(c => c.expires === 'Session').length,
      persistentCookies: analyzed.filter(c => c.expires !== 'Session').length,
      cookies: analyzed
    };
  }`
})
```

### Phase 5: Inspect IndexedDB

Enumerate all databases, their object stores, indexes, and record counts.

```javascript
browser_run_code({
  code: `async (page) => {
    const { client, origin } = globalThis.__storageInspector;

    // Request database names for this origin
    const { databaseNames } = await client.send('IndexedDB.requestDatabaseNames', {
      securityOrigin: origin
    });

    const databases = [];

    for (const dbName of databaseNames) {
      try {
        const { databaseWithObjectStores } = await client.send('IndexedDB.requestDatabase', {
          securityOrigin: origin,
          databaseName: dbName
        });

        const db = {
          name: databaseWithObjectStores.name,
          version: databaseWithObjectStores.version,
          objectStores: []
        };

        for (const os of databaseWithObjectStores.objectStores) {
          // Get record count by requesting data with limit 0
          let recordCount = 0;
          try {
            const data = await client.send('IndexedDB.requestData', {
              securityOrigin: origin,
              databaseName: dbName,
              objectStoreName: os.name,
              indexName: '',
              skipCount: 0,
              pageSize: 1
            });
            recordCount = data.totalCount || 0;
          } catch {}

          db.objectStores.push({
            name: os.name,
            keyPath: os.keyPath ? os.keyPath.string || JSON.stringify(os.keyPath.array) : '(auto)',
            autoIncrement: os.autoIncrement,
            indexes: os.indexes.map(idx => ({
              name: idx.name,
              keyPath: idx.keyPath ? idx.keyPath.string || JSON.stringify(idx.keyPath.array) : '',
              unique: idx.unique,
              multiEntry: idx.multiEntry
            })),
            recordCount
          });
        }

        databases.push(db);
      } catch (err) {
        databases.push({ name: dbName, error: err.message });
      }
    }

    return {
      databaseCount: databases.length,
      databases
    };
  }`
})
```

### Phase 6: Inspect Cache API

```javascript
browser_evaluate({
  function: `async () => {
    if (!('caches' in self)) return { supported: false };

    const cacheNames = await caches.keys();
    const cacheDetails = [];

    for (const name of cacheNames) {
      const cache = await caches.open(name);
      const requests = await cache.keys();

      const entries = [];
      for (const req of requests.slice(0, 50)) {
        const response = await cache.match(req);
        let size = 0;
        try {
          const blob = await response.clone().blob();
          size = blob.size;
        } catch {}

        entries.push({
          url: req.url.substring(0, 200),
          method: req.method,
          contentType: response.headers.get('content-type') || 'unknown',
          status: response.status,
          sizeBytes: size
        });
      }

      cacheDetails.push({
        name,
        entryCount: requests.length,
        sampledEntries: entries,
        totalSizeBytes: entries.reduce((s, e) => s + e.sizeBytes, 0),
        truncated: requests.length > 50
      });
    }

    return {
      supported: true,
      cacheCount: cacheDetails.length,
      caches: cacheDetails
    };
  }`
})
```

### Phase 7: Storage Quota Usage

```javascript
browser_evaluate({
  function: `async () => {
    const result = {};

    // Storage estimate (quota API)
    if (navigator.storage && navigator.storage.estimate) {
      const estimate = await navigator.storage.estimate();
      result.quota = {
        usage: estimate.usage,
        quota: estimate.quota,
        usagePercent: Math.round((estimate.usage / estimate.quota) * 10000) / 100,
        usageDetails: estimate.usageDetails || null
      };
    }

    // Persisted storage
    if (navigator.storage && navigator.storage.persisted) {
      result.persisted = await navigator.storage.persisted();
    }

    return result;
  }`
})
```

### Phase 8: Cleanup

```javascript
browser_run_code({
  code: `async (page) => {
    if (globalThis.__storageInspector) {
      await globalThis.__storageInspector.client.detach();
      delete globalThis.__storageInspector;
    }
    return 'Storage inspector CDP session detached';
  }`
})
```

## Report Template

```markdown
## Storage Inspector Report -- <URL>

**Date:** <timestamp>
**Origin:** <origin>

### Storage Quota

| Metric | Value |
|--------|-------|
| Usage | 12.4 MB |
| Quota | 2.1 GB |
| Usage % | 0.59% |
| Persisted | No |

### localStorage (<N> entries, <size> KB)

| Key | Type | Size | Value (preview) |
|-----|------|------|-----------------|
| user_preferences | object | 2.4 KB | {"theme":"dark","lang":"en"...} |
| auth_token | string | 1.8 KB | eyJhbGciOiJSUzI1NiIs... |
| feature_flags | object | 0.5 KB | {"newDashboard":true...} |

### sessionStorage (<N> entries, <size> KB)

| Key | Type | Size | Value (preview) |
|-----|------|------|-----------------|
| csrf_token | string | 64 B | a1b2c3d4... |
| form_draft | object | 3.1 KB | {"step":2,"data":{...}} |

### Cookies (<N> total, <size> B)

| Name | Domain | Secure | HttpOnly | SameSite | Expires | Size |
|------|--------|--------|----------|----------|---------|------|
| session_id | .example.com | Yes | Yes | Lax | Session | 45 B |
| _ga | .example.com | No | No | None | 2026-01-15 | 28 B |

### IndexedDB (<N> databases)

#### Database: myAppDB (v3)

| Object Store | Key Path | Records | Indexes |
|-------------|----------|---------|---------|
| users | id | 150 | email (unique), name |
| cache | url | 2,340 | timestamp |
| offline_queue | (auto) | 5 | — |

### Cache API (<N> caches)

#### Cache: v2-static

| URL (truncated) | Content-Type | Size |
|-----------------|-------------|------|
| /static/js/main.abc123.js | application/javascript | 245 KB |
| /static/css/app.def456.css | text/css | 18 KB |

**Entries:** 35 | **Total Size:** 1.2 MB

### Analysis and Recommendations

- **auth_token in localStorage:** Sensitive tokens should use httpOnly cookies instead of localStorage to prevent XSS exfiltration.
- **IndexedDB cache store has 2,340 records:** Consider implementing a TTL-based eviction policy to prevent unbounded growth.
- **_ga cookie missing Secure flag:** All cookies should use the Secure flag on HTTPS sites.
- **Storage usage is low (0.59%):** No quota pressure, but monitor IndexedDB growth over time.
- **Cache API v2-static (1.2 MB):** Ensure old cache versions are cleaned up in the service worker activate event.
```

## Limitations

- **IndexedDB record counting** uses CDP `requestData` with a page size of 1 to get `totalCount`. Very large databases may return approximate counts.
- **Cache API inspection** samples the first 50 entries per cache. Large caches with thousands of entries are truncated.
- **Cookie values** from `Network.getAllCookies` may include cookies from all visited origins in the browser session, not just the target origin. Filtering by domain is applied but may include subdomain cookies.
- **Storage quota** via `navigator.storage.estimate()` returns approximate values. Actual quotas depend on available disk space and browser heuristics.
- **Sensitive data detection** is basic pattern matching on key names. A thorough privacy audit requires domain-specific knowledge of what constitutes PII.
