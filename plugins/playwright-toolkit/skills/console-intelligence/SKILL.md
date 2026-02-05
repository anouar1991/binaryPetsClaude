---
name: console-intelligence
description: >
  Capture and categorize all console output with stack traces, source
  attribution, frequency deduplication, and temporal grouping. Uses CDP
  Runtime and Log domains for browser-level entries and unhandled exceptions.
---

# Console Intelligence

Capture every console message, unhandled exception, and browser-level log
entry from a page session. Categorize by severity, group by source file,
deduplicate repeated messages, detect framework-specific warnings (React,
Vue, Angular), identify CSP violations, and produce a prioritized report.

## When to Use

- Debugging production pages where console errors indicate broken functionality.
- Auditing a page for JavaScript errors, deprecation warnings, and CSP violations before release.
- Identifying noisy third-party scripts that flood the console.
- Detecting React/Vue/Angular framework warnings that indicate misuse or performance issues.
- Understanding the temporal sequence of errors during page load and interaction.

## Prerequisites

- **Playwright MCP server** connected and responding.
- **Chromium-based browser** for CDP Runtime and Log domain access.
- Target page must be reachable from the browser instance.

## Workflow

### Phase 1: Install Console Interceptors via CDP

Install CDP listeners **before** navigation so that early page errors are
captured. This uses three complementary channels:

1. **Runtime.exceptionThrown** -- catches unhandled exceptions with async stack traces.
2. **Log.entryAdded** -- catches browser-level entries (network errors, security warnings, interventions).
3. **Console method patching** via `browser_evaluate` -- catches all `console.*` calls with caller location.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);

    await client.send('Runtime.enable');
    await client.send('Log.enable');

    const entries = [];
    let idCounter = 0;

    // Channel 1: Unhandled exceptions (async stack traces included)
    client.on('Runtime.exceptionThrown', (params) => {
      const ex = params.exceptionDetails;
      const entry = {
        id: ++idCounter,
        channel: 'exception',
        level: 'error',
        timestamp: params.timestamp,
        text: ex.text || '',
        description: ex.exception ? (ex.exception.description || ex.exception.value || '') : '',
        url: ex.url || null,
        lineNumber: ex.lineNumber,
        columnNumber: ex.columnNumber,
        stackTrace: null
      };

      if (ex.stackTrace && ex.stackTrace.callFrames) {
        entry.stackTrace = ex.stackTrace.callFrames.map(f => ({
          functionName: f.functionName || '(anonymous)',
          url: f.url,
          lineNumber: f.lineNumber,
          columnNumber: f.columnNumber
        }));
      }

      entries.push(entry);
    });

    // Channel 2: Browser-level log entries
    client.on('Log.entryAdded', (params) => {
      const e = params.entry;
      entries.push({
        id: ++idCounter,
        channel: 'browser',
        level: e.level,
        timestamp: e.timestamp,
        text: e.text,
        url: e.url || null,
        lineNumber: e.lineNumber || null,
        source: e.source,
        category: e.category || null,
        networkRequestId: e.networkRequestId || null
      });
    });

    globalThis.__consoleIntel = { client, entries };
    return 'CDP console interceptors installed';
  }`
})
```

### Phase 2: Install Console Method Patches

Patch `console.*` methods in the page context to capture calls with caller
information. This runs in the page's JavaScript context.

```javascript
browser_evaluate({
  function: `() => {
    window.__consoleCaptures = [];
    const methods = ['log', 'warn', 'error', 'info', 'debug', 'trace', 'assert'];
    const originals = {};

    methods.forEach(method => {
      originals[method] = console[method].bind(console);
      console[method] = (...args) => {
        // Capture caller location from stack trace
        const stack = new Error().stack || '';
        const callerLine = stack.split('\\n')[2] || '';
        const match = callerLine.match(/(?:at\\s+)?(?:.*?)\\(?(.+?):(\\d+):(\\d+)\\)?/);

        window.__consoleCaptures.push({
          method: method,
          timestamp: Date.now(),
          args: args.map(a => {
            try {
              if (typeof a === 'object') return JSON.stringify(a).substring(0, 500);
              return String(a).substring(0, 500);
            } catch { return '[unserializable]'; }
          }),
          sourceUrl: match ? match[1] : null,
          line: match ? parseInt(match[2]) : null,
          column: match ? parseInt(match[3]) : null
        });

        originals[method](...args);
      };
    });

    return 'Console methods patched (' + methods.length + ' methods)';
  }`
})
```

### Phase 3: Navigate and Interact

Navigate to the target page. Console interceptors are already active.

```
browser_navigate({ url: "<target_url>" })
```

Wait for page load and deferred scripts:

```
browser_wait_for({ time: 3 })
```

Perform interactions that may trigger console output:

1. Scroll the page to trigger lazy-loaded content:
   ```javascript
   browser_evaluate({
     function: `() => {
       window.scrollTo(0, document.body.scrollHeight / 2);
       return 'scrolled to midpoint';
     }`
   })
   ```

2. Wait for async operations:
   ```
   browser_wait_for({ time: 2 })
   ```

3. Take a snapshot and click interactive elements (buttons, tabs) to trigger
   event handler errors:
   ```
   browser_snapshot()
   ```
   Then use `browser_click` on elements identified in the snapshot.

4. Wait again for async responses:
   ```
   browser_wait_for({ time: 2 })
   ```

### Phase 4: Collect Baseline from Built-in Tool

Cross-reference with the built-in console capture.

```
browser_console_messages({ level: "debug" })
```

### Phase 5: Harvest and Analyze

Collect all captured data and perform categorization, deduplication, and
framework detection.

```javascript
browser_run_code({
  code: `async (page) => {
    const intel = globalThis.__consoleIntel;
    if (!intel) return { error: 'Interceptors not installed' };

    // Collect CDP entries
    const cdpEntries = [...intel.entries];

    // Collect page-context captures
    const pageCaptures = await page.evaluate(() => window.__consoleCaptures || []);

    // Merge into unified list
    const all = [];

    cdpEntries.forEach(e => all.push(e));
    pageCaptures.forEach(c => {
      all.push({
        id: all.length + 1,
        channel: 'console-patch',
        level: c.method === 'warn' ? 'warning'
             : c.method === 'assert' ? 'error'
             : c.method === 'trace' ? 'info'
             : c.method,
        timestamp: c.timestamp,
        text: c.args.join(' '),
        url: c.sourceUrl,
        lineNumber: c.line,
        method: c.method
      });
    });

    // Sort by timestamp
    all.sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));

    // Deduplicate: group identical messages
    const deduped = new Map();
    all.forEach(entry => {
      const key = entry.level + '|' + (entry.text || '').substring(0, 200);
      if (deduped.has(key)) {
        const existing = deduped.get(key);
        existing.count++;
        existing.lastSeen = entry.timestamp;
      } else {
        deduped.set(key, { ...entry, count: 1, lastSeen: entry.timestamp });
      }
    });

    // Framework detection patterns
    const frameworkPatterns = [
      { regex: /Warning:.*React/, framework: 'React', type: 'warning' },
      { regex: /react-dom\\.development/, framework: 'React', type: 'dev-mode' },
      { regex: /Each child in a list should have a unique/, framework: 'React', type: 'key-warning' },
      { regex: /Cannot update a component.*while rendering/, framework: 'React', type: 'state-during-render' },
      { regex: /\\[Vue warn\\]/, framework: 'Vue', type: 'warning' },
      { regex: /\\[deprecation\\]|NG\\d{4}/, framework: 'Angular', type: 'deprecation' },
      { regex: /Content.Security.Policy|CSP/, framework: 'Browser', type: 'csp-violation' },
      { regex: /Mixed Content/, framework: 'Browser', type: 'mixed-content' },
      { regex: /DEPRECATED|deprecated/, framework: 'General', type: 'deprecation' }
    ];

    const dedupedArr = Array.from(deduped.values());
    dedupedArr.forEach(entry => {
      entry.frameworkMatch = null;
      for (const pat of frameworkPatterns) {
        if (pat.regex.test(entry.text || '') || pat.regex.test(entry.description || '')) {
          entry.frameworkMatch = { framework: pat.framework, type: pat.type };
          break;
        }
      }
    });

    // Group by source file
    const bySource = {};
    dedupedArr.forEach(entry => {
      const source = entry.url || '(unknown)';
      if (!bySource[source]) bySource[source] = [];
      bySource[source].push(entry);
    });

    // Summary counts
    const summary = { error: 0, warning: 0, info: 0, debug: 0, total: all.length, unique: dedupedArr.length };
    dedupedArr.forEach(e => {
      if (e.level === 'error') summary.error += e.count;
      else if (e.level === 'warning') summary.warning += e.count;
      else if (e.level === 'info' || e.level === 'log') summary.info += e.count;
      else summary.debug += e.count;
    });

    return { summary, entries: dedupedArr, bySource };
  }`
})
```

### Phase 6: Cleanup

```javascript
browser_run_code({
  code: `async (page) => {
    if (globalThis.__consoleIntel) {
      await globalThis.__consoleIntel.client.detach();
      delete globalThis.__consoleIntel;
    }
    return 'CDP session detached';
  }`
})
```

## Report Template

```markdown
## Console Intelligence Report -- <URL>

**Date:** <timestamp>
**Total Messages:** <N> | **Unique:** <N>
**Errors:** <N> | **Warnings:** <N> | **Info:** <N> | **Debug:** <N>

### Severity Breakdown

| Level | Count | Unique Messages |
|-------|-------|-----------------|
| error | 12 | 4 |
| warning | 25 | 8 |
| info | 45 | 30 |
| debug | 3 | 2 |

### Errors (prioritized)

| # | Message (truncated) | Source | Line | Count | Framework |
|---|---------------------|--------|------|-------|-----------|
| 1 | TypeError: Cannot read property 'x' of null | app.js | 142 | 3 | — |
| 2 | Each child in a list should have unique key | react-dom.development.js | 890 | 15 | React (key-warning) |
| 3 | Content Security Policy violation: inline script | — | — | 1 | Browser (CSP) |

### Framework Warnings

| Framework | Type | Message | Count |
|-----------|------|---------|-------|
| React | key-warning | Each child in a list should have a unique "key" prop | 15 |
| React | state-during-render | Cannot update a component while rendering | 2 |
| Browser | csp-violation | Refused to execute inline script | 1 |

### Top Noisy Sources (by message volume)

| Source File | Total Messages | Errors | Warnings |
|-------------|---------------|--------|----------|
| https://cdn.analytics.com/tracker.js | 35 | 0 | 20 |
| /static/js/app.js | 18 | 4 | 5 |

### Exception Stack Traces

#### TypeError: Cannot read property 'x' of null (3 occurrences)
```
at handleClick (app.js:142:15)
at HTMLButtonElement.<anonymous> (app.js:89:7)
at EventTarget.dispatchEvent (events.js:45:12)
```

### Recommendations

- **Fix TypeError in app.js:142:** Null check required before property access in click handler.
- **Add key props to list components:** 15 React key warnings indicate missing keys in mapped lists.
- **Review CSP policy:** Inline script blocked -- either add nonce/hash to CSP or move script to external file.
- **Audit tracker.js:** Generates 35 console messages per page load. Consider disabling debug mode in production.
```

## Limitations

- **Console method patching** replaces native methods. If a page restores originals or uses `console.__proto__`, some messages may be missed by the patch channel. CDP Runtime and Log channels serve as fallback.
- **Stack traces** from CDP `Runtime.exceptionThrown` include async call frames when available, but minified production code requires source maps for useful attribution.
- **Timestamp alignment** between CDP (monotonic clock) and page-context `Date.now()` may have slight drift. Messages are sorted per-channel then merged.
- **Large volumes** of console output (10,000+ messages) may cause memory pressure. The deduplication step mitigates this for repeated messages.
- **Framework detection** uses regex pattern matching and may produce false positives on messages that coincidentally match patterns.
