---
name: pwa-audit
description: >
  Audits Progressive Web App readiness: manifest validation, service worker
  status and scope, offline capability test, HTTPS enforcement, installability
  criteria, push notification permission, and cache strategy analysis.
  Produces a PWA scorecard with pass/fail per criterion.
---

# PWA Audit

Perform a comprehensive Progressive Web App readiness assessment. Validates
the web app manifest, inspects the service worker lifecycle and scope, tests
offline behavior by emulating network disconnection, and checks installability
criteria against the PWA checklist.

## When to Use

- Before submitting an app to app stores via PWA wrappers (TWA, PWABuilder).
- Verifying service worker registration and cache strategy after deployment.
- Diagnosing "Add to Home Screen" prompt not appearing.
- Checking offline fallback behavior after a service worker update.
- Auditing push notification readiness.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP service worker inspection and network emulation.
- Target page must be served over HTTPS (or localhost for development).

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

Wait for the page to fully load and the service worker to register:

```
browser_wait_for({ time: 3 })
```

### Step 2 -- Check HTTPS Enforcement

Verify the page is served over HTTPS (required for service workers and PWA installability).

```javascript
browser_evaluate({
  function: `() => {
    const protocol = window.location.protocol;
    const isLocalhost = window.location.hostname === 'localhost'
      || window.location.hostname === '127.0.0.1'
      || window.location.hostname === '[::1]';
    const isSecure = protocol === 'https:' || isLocalhost;

    return {
      protocol,
      hostname: window.location.hostname,
      isLocalhost,
      isSecureContext: window.isSecureContext,
      isHTTPS: protocol === 'https:',
      passesRequirement: isSecure,
      issue: !isSecure
        ? 'Page is not served over HTTPS. Service workers and PWA features require a secure context.'
        : null
    };
  }`
})
```

### Step 3 -- Validate the Web App Manifest

Fetch and validate the manifest linked in the page head.

```javascript
browser_evaluate({
  function: `() => {
    const link = document.querySelector('link[rel="manifest"]');
    if (!link) {
      return { found: false, href: null, issues: ['No <link rel="manifest"> found in document head'] };
    }
    return { found: true, href: link.href };
  }`
})
```

If a manifest link is found, fetch and validate its contents using Bash:

```bash
curl -sL "<manifest_url>" | python3 -c "
import json, sys
try:
    m = json.load(sys.stdin)
except:
    print(json.dumps({'valid_json': False, 'error': 'Failed to parse manifest as JSON'}))
    sys.exit(0)

required = ['name', 'short_name', 'start_url', 'display', 'icons']
recommended = ['background_color', 'theme_color', 'description', 'scope', 'lang', 'orientation']
issues = []

for field in required:
    if field not in m:
        issues.append(f'Missing required field: {field}')

for field in recommended:
    if field not in m:
        issues.append(f'Missing recommended field: {field}')

# Validate display mode
valid_display = ['fullscreen', 'standalone', 'minimal-ui', 'browser']
if m.get('display') and m['display'] not in valid_display:
    issues.append(f'Invalid display mode: {m[\"display\"]}. Must be one of: {valid_display}')

if m.get('display') == 'browser':
    issues.append('display: browser does not meet installability criteria. Use standalone, fullscreen, or minimal-ui.')

# Validate icons
icons = m.get('icons', [])
has_192 = any(i.get('sizes') == '192x192' for i in icons)
has_512 = any(i.get('sizes') == '512x512' for i in icons)
has_maskable = any('maskable' in (i.get('purpose') or '') for i in icons)
has_svg = any((i.get('type') or '').endswith('svg') or (i.get('src') or '').endswith('.svg') for i in icons)

if not has_192:
    issues.append('Missing 192x192 icon (required for Android install)')
if not has_512:
    issues.append('Missing 512x512 icon (required for splash screen)')
if not has_maskable:
    issues.append('No maskable icon defined (recommended for adaptive icon support)')

# Validate start_url
if 'start_url' in m and not m['start_url']:
    issues.append('start_url is empty')

result = {
    'valid_json': True,
    'name': m.get('name'),
    'short_name': m.get('short_name'),
    'start_url': m.get('start_url'),
    'display': m.get('display'),
    'background_color': m.get('background_color'),
    'theme_color': m.get('theme_color'),
    'scope': m.get('scope'),
    'icon_count': len(icons),
    'has_192_icon': has_192,
    'has_512_icon': has_512,
    'has_maskable_icon': has_maskable,
    'has_svg_icon': has_svg,
    'issues': issues
}
print(json.dumps(result, indent=2))
"
```

### Step 4 -- Inspect Service Worker Status and Scope

Check service worker registration, state, and scope.

```javascript
browser_evaluate({
  function: `() => {
    if (!('serviceWorker' in navigator)) {
      return { supported: false, issues: ['Service Worker API not available in this browser'] };
    }

    return navigator.serviceWorker.getRegistration().then(reg => {
      if (!reg) {
        return {
          supported: true,
          registered: false,
          issues: ['No service worker registered for this scope']
        };
      }

      const sw = reg.active || reg.waiting || reg.installing;
      return {
        supported: true,
        registered: true,
        scope: reg.scope,
        scriptURL: sw ? sw.scriptURL : null,
        state: sw ? sw.state : null,
        hasActive: !!reg.active,
        hasWaiting: !!reg.waiting,
        hasInstalling: !!reg.installing,
        updateViaCache: reg.updateViaCache,
        issues: []
      };
    }).catch(err => ({
      supported: true,
      registered: false,
      error: err.message,
      issues: ['Service worker registration check failed: ' + err.message]
    }));
  }`
})
```

### Step 5 -- Deep Service Worker Inspection via CDP

Use CDP to get detailed service worker information including cache names
and script contents.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    await client.send('ServiceWorker.enable');

    // Give the service worker time to report
    await page.waitForTimeout(2000);

    // Get all service worker versions
    const { versions } = await client.send('ServiceWorker.inspectWorker', {}).catch(() => ({ versions: [] }));

    // Get storage usage to understand cache sizes
    const { usage, quota } = await client.send('Storage.getUsageAndQuota', {
      origin: new URL(page.url()).origin
    }).catch(() => ({ usage: 0, quota: 0 }));

    // Get cache storage names
    const { caches } = await client.send('CacheStorage.requestCacheNames', {
      securityOrigin: new URL(page.url()).origin
    }).catch(() => ({ caches: [] }));

    await client.send('ServiceWorker.disable');

    return {
      cacheNames: caches.map(c => c.cacheName),
      cacheCount: caches.length,
      storageUsageBytes: usage,
      storageQuotaBytes: quota,
      storageUsageMB: Math.round(usage / 1024 / 1024 * 100) / 100,
      storageQuotaMB: Math.round(quota / 1024 / 1024 * 100) / 100
    };
  }`
})
```

### Step 6 -- Test Offline Capability

Emulate offline network conditions via CDP, then attempt to reload the page
and capture the result.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    // Go offline
    await client.send('Network.enable');
    await client.send('Network.emulateNetworkConditions', {
      offline: true,
      latency: 0,
      downloadThroughput: 0,
      uploadThroughput: 0
    });

    // Attempt to reload
    let offlineResult;
    try {
      await page.reload({ timeout: 10000, waitUntil: 'domcontentloaded' });

      // Check what loaded
      const title = await page.title();
      const bodyText = await page.evaluate(() => document.body ? document.body.innerText.substring(0, 500) : '');
      const hasContent = bodyText.length > 50;
      const isDefaultOfflinePage = bodyText.includes('No internet') || bodyText.includes('ERR_INTERNET_DISCONNECTED');

      offlineResult = {
        loaded: true,
        title,
        hasContent,
        isDefaultOfflinePage,
        bodyPreview: bodyText.substring(0, 200),
        passesOfflineTest: hasContent && !isDefaultOfflinePage
      };
    } catch (err) {
      offlineResult = {
        loaded: false,
        error: err.message,
        passesOfflineTest: false
      };
    }

    // Restore online
    await client.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: 0,
      downloadThroughput: -1,
      uploadThroughput: -1
    });

    return offlineResult;
  }`
})
```

### Step 7 -- Capture Offline Screenshot

If the page loaded (or showed a fallback) in offline mode, capture a screenshot
before restoring connectivity.

```
browser_take_screenshot({ type: "png", filename: "pwa-offline-fallback.png" })
```

Reload the page online to restore normal state:

```
browser_navigate({ url: "<target_url>" })
```

```
browser_wait_for({ time: 2 })
```

### Step 8 -- Check Installability Criteria

Verify the browser's installability assessment by checking all the criteria
Chrome uses to determine if a PWA can be installed.

```javascript
browser_evaluate({
  function: `() => {
    const criteria = [];

    // 1. Secure context
    criteria.push({
      name: 'Secure Context',
      pass: window.isSecureContext,
      detail: window.isSecureContext ? 'Page is in a secure context' : 'Page requires HTTPS'
    });

    // 2. Manifest link
    const manifestLink = document.querySelector('link[rel="manifest"]');
    criteria.push({
      name: 'Manifest Link',
      pass: !!manifestLink,
      detail: manifestLink ? 'Manifest found at ' + manifestLink.href : 'No manifest link'
    });

    // 3. Service worker
    const hasSW = 'serviceWorker' in navigator;
    criteria.push({
      name: 'Service Worker API',
      pass: hasSW,
      detail: hasSW ? 'Service Worker API available' : 'Service Worker API not available'
    });

    // 4. display-mode media query (checks if display mode is standalone/fullscreen)
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches
      || window.matchMedia('(display-mode: fullscreen)').matches
      || window.matchMedia('(display-mode: minimal-ui)').matches;
    criteria.push({
      name: 'Display Mode',
      pass: true, // This is informational
      detail: isStandalone ? 'Currently running in app mode' : 'Running in browser (normal for audit)'
    });

    // 5. beforeinstallprompt support
    criteria.push({
      name: 'beforeinstallprompt Event',
      pass: true, // Cannot test directly without waiting
      detail: 'Listen for beforeinstallprompt event to trigger install UI'
    });

    const passing = criteria.filter(c => c.pass).length;
    return {
      criteria,
      passing,
      total: criteria.length,
      installable: passing >= 3 // Minimum: secure context + manifest + SW
    };
  }`
})
```

### Step 9 -- Check Push Notification Permission

Check the current state of push notification permission and whether the Push API
is available.

```javascript
browser_evaluate({
  function: `() => {
    const result = {
      notificationAPIAvailable: 'Notification' in window,
      pushAPIAvailable: 'PushManager' in window,
      permissionState: null,
      issues: []
    };

    if ('Notification' in window) {
      result.permissionState = Notification.permission; // 'default', 'granted', 'denied'
      if (Notification.permission === 'denied') {
        result.issues.push('Push notifications are blocked by the user. Cannot request permission again.');
      }
    } else {
      result.issues.push('Notification API not available in this context');
    }

    if (!('PushManager' in window)) {
      result.issues.push('Push API not available. Ensure service worker is registered and page is secure.');
    }

    return result;
  }`
})
```

### Step 10 -- Analyze Cache Strategy

Examine what the service worker has cached and infer the caching strategy.

```javascript
browser_evaluate({
  function: `() => {
    if (!('caches' in window)) {
      return { available: false, issues: ['Cache API not available'] };
    }

    return caches.keys().then(async (cacheNames) => {
      const details = [];
      let totalEntries = 0;

      for (const name of cacheNames) {
        const cache = await caches.open(name);
        const keys = await cache.keys();
        const entries = keys.map(req => {
          const url = new URL(req.url);
          return {
            path: url.pathname,
            hostname: url.hostname
          };
        });

        // Categorize cached resources
        const categories = {};
        for (const entry of entries) {
          const ext = entry.path.split('.').pop().toLowerCase();
          let cat = 'other';
          if (['html', 'htm'].includes(ext) || entry.path.endsWith('/')) cat = 'html';
          else if (['js', 'mjs'].includes(ext)) cat = 'javascript';
          else if (['css'].includes(ext)) cat = 'css';
          else if (['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'avif', 'ico'].includes(ext)) cat = 'images';
          else if (['woff', 'woff2', 'ttf', 'otf', 'eot'].includes(ext)) cat = 'fonts';
          else if (['json'].includes(ext)) cat = 'json';
          categories[cat] = (categories[cat] || 0) + 1;
        }

        totalEntries += keys.length;
        details.push({
          cacheName: name,
          entryCount: keys.length,
          categories
        });
      }

      // Infer strategy
      let inferredStrategy = 'unknown';
      const hasHTML = details.some(d => (d.categories.html || 0) > 0);
      const hasAssets = details.some(d =>
        (d.categories.javascript || 0) + (d.categories.css || 0) + (d.categories.images || 0) > 0
      );

      if (cacheNames.some(n => n.includes('precache') || n.includes('workbox'))) {
        inferredStrategy = 'Workbox (precache + runtime caching)';
      } else if (hasHTML && hasAssets) {
        inferredStrategy = 'Cache-first or Stale-while-revalidate (app shell + assets)';
      } else if (hasAssets && !hasHTML) {
        inferredStrategy = 'Cache-first for assets only (network-first for HTML)';
      } else if (hasHTML && !hasAssets) {
        inferredStrategy = 'Offline page only (minimal offline support)';
      }

      return {
        available: true,
        cacheCount: cacheNames.length,
        totalCachedEntries: totalEntries,
        caches: details,
        inferredStrategy,
        issues: totalEntries === 0 ? ['No resources cached -- offline support unlikely'] : []
      };
    });
  }`
})
```

## Interpreting Results

### PWA Scorecard Format

```
## PWA Audit -- <page_url>

| Criterion              | Status | Detail                                    |
|------------------------|--------|-------------------------------------------|
| HTTPS                  | PASS   | Served over HTTPS                         |
| Manifest               | PASS   | Valid manifest with all required fields    |
| Service Worker         | PASS   | Active, scope covers start_url            |
| Offline Capability     | FAIL   | Page shows browser offline error          |
| Installability         | PASS   | Meets Chrome install criteria             |
| Icons (192 + 512)      | PASS   | Both sizes present                        |
| Maskable Icon          | WARN   | No maskable icon defined                  |
| Push Notifications     | INFO   | Permission: default (not yet requested)   |
| Cache Strategy         | PASS   | Workbox precache with 45 assets cached    |
| Display Mode           | PASS   | standalone                                |

### Score: 8/10 (Installable but not fully offline-capable)
```

### What to Look For

- **No service worker registered**: the app cannot work offline and is not installable. Register a service worker with at least a fetch handler.
- **Manifest missing required fields**: Chrome requires `name` or `short_name`, `start_url`, `display` (not `browser`), and at least one icon >= 192px.
- **Offline test fails**: the service worker does not have a fetch handler that serves cached content. Implement cache-first or stale-while-revalidate strategy.
- **display: browser**: this does not qualify as installable. Change to `standalone`, `fullscreen`, or `minimal-ui`.
- **No maskable icon**: on Android, the icon will be placed in a white circle instead of adapting to the device shape. Add a `purpose: maskable` icon.
- **Push permission denied**: the user has blocked notifications. The app must handle this gracefully and not repeatedly request permission.

## Limitations

- **Service worker inspection via CDP**: CDP ServiceWorker domain provides version and registration info, but cannot inspect the actual fetch handler logic. Cache analysis is used as a proxy.
- **Offline test is page-reload only**: tests whether the main page loads offline. Does not test offline navigation between routes in an SPA.
- **beforeinstallprompt cannot be triggered programmatically**: the skill checks prerequisites but cannot confirm the browser would actually show the install prompt.
- **Push notification test is permission-check only**: the skill checks Notification.permission but does not send a test push notification.
- **Chromium-specific**: some CDP calls (ServiceWorker.enable, CacheStorage.requestCacheNames) are Chromium-only. Firefox and Safari have different PWA criteria.
