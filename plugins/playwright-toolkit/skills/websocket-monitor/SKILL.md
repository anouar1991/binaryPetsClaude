---
name: websocket-monitor
description: >
  Monitor WebSocket connections via CDP: lifecycle events, message payloads
  with JSON auto-parse, frequency and size analysis, latency measurement,
  reconnection tracking, and Socket.IO/engine.io protocol detection.
---

# WebSocket Monitor

Instrument a page to capture all WebSocket activity using Chrome DevTools
Protocol events. Provides real-time visibility into connection lifecycle,
message flow, payload analysis, and protocol-level detection for Socket.IO
and engine.io.

## When to Use

- Debugging WebSocket connection issues (handshake failures, unexpected closes).
- Analyzing message payloads and frequency for optimization.
- Verifying Socket.IO or engine.io protocol behavior.
- Tracking reconnection patterns and connection stability.
- Measuring message latency between sent and received pairs.
- Profiling WebSocket bandwidth usage (message sizes).

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- **Chromium-based browser** required for CDP WebSocket events.
- Target page must establish WebSocket connections (the monitor captures connections created after instrumentation is installed).

## Workflow

### Step 1 -- Install CDP WebSocket Listeners

Set up CDP session and register all WebSocket event handlers before navigating
to the target page.

```javascript
browser_run_code({
  code: `async (page) => {
    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');

    // Storage for all WebSocket data
    window.__wsMonitor = {
      connections: {},
      messages: [],
      timeline: [],
      stats: { totalSent: 0, totalReceived: 0, totalBytesSent: 0, totalBytesReceived: 0 }
    };
    // Attach to page for later retrieval
    await page.evaluate(() => {
      window.__wsMonitor = {
        connections: {},
        messages: [],
        timeline: [],
        stats: { totalSent: 0, totalReceived: 0, totalBytesSent: 0, totalBytesReceived: 0 }
      };
    });

    const monitor = { connections: {}, messages: [], timeline: [] };
    let totalSent = 0, totalReceived = 0, totalBytesSent = 0, totalBytesReceived = 0;

    client.on('Network.webSocketCreated', (params) => {
      monitor.connections[params.requestId] = {
        requestId: params.requestId,
        url: params.url,
        createdAt: Date.now(),
        status: 'connecting',
        handshake: null,
        closedAt: null,
        closeCode: null,
        closeReason: null,
        messageCount: { sent: 0, received: 0 },
        byteCount: { sent: 0, received: 0 }
      };
      monitor.timeline.push({ type: 'created', requestId: params.requestId, url: params.url, time: Date.now() });
    });

    client.on('Network.webSocketHandshakeResponseReceived', (params) => {
      const conn = monitor.connections[params.requestId];
      if (conn) {
        conn.status = 'open';
        conn.handshake = {
          status: params.response.status,
          statusText: params.response.statusText,
          headers: params.response.headers
        };
      }
      monitor.timeline.push({ type: 'handshake', requestId: params.requestId, time: Date.now() });
    });

    client.on('Network.webSocketFrameSent', (params) => {
      const payload = params.response.payloadData;
      const size = new Blob([payload]).size;
      totalSent++;
      totalBytesSent += size;
      const conn = monitor.connections[params.requestId];
      if (conn) { conn.messageCount.sent++; conn.byteCount.sent += size; }
      monitor.messages.push({
        direction: 'sent',
        requestId: params.requestId,
        time: Date.now(),
        size: size,
        payload: payload.substring(0, 2000),
        opcode: params.response.opcode
      });
    });

    client.on('Network.webSocketFrameReceived', (params) => {
      const payload = params.response.payloadData;
      const size = new Blob([payload]).size;
      totalReceived++;
      totalBytesReceived += size;
      const conn = monitor.connections[params.requestId];
      if (conn) { conn.messageCount.received++; conn.byteCount.received += size; }
      monitor.messages.push({
        direction: 'received',
        requestId: params.requestId,
        time: Date.now(),
        size: size,
        payload: payload.substring(0, 2000),
        opcode: params.response.opcode
      });
    });

    client.on('Network.webSocketClosed', (params) => {
      const conn = monitor.connections[params.requestId];
      if (conn) {
        conn.status = 'closed';
        conn.closedAt = Date.now();
      }
      monitor.timeline.push({ type: 'closed', requestId: params.requestId, time: Date.now() });
    });

    // Store reference for later harvest
    page.__wsMonitorData = monitor;
    page.__wsMonitorStats = () => ({
      totalSent, totalReceived, totalBytesSent, totalBytesReceived
    });

    return 'WebSocket CDP listeners installed';
  }`
})
```

### Step 2 -- Install Protocol Detection (Socket.IO / engine.io)

Patch the WebSocket constructor on the page to detect Socket.IO and engine.io
handshake patterns.

```javascript
browser_evaluate({
  function: `() => {
    window.__wsProtocolInfo = [];
    const OrigWS = window.WebSocket;
    window.WebSocket = function(url, protocols) {
      const ws = new OrigWS(url, protocols);
      const info = {
        url: url,
        protocols: protocols || null,
        detectedProtocol: 'raw-websocket',
        engineIO: false,
        socketIO: false
      };

      // Detect engine.io / Socket.IO from URL patterns
      if (url.includes('engine.io') || url.includes('EIO=')) {
        info.engineIO = true;
        info.detectedProtocol = 'engine.io';
      }
      if (url.includes('socket.io') || url.includes('transport=websocket')) {
        info.socketIO = true;
        info.detectedProtocol = 'socket.io';
      }

      // Listen for first message to detect Socket.IO packet format
      const origOnMessage = ws.onmessage;
      const messageListener = (event) => {
        const data = typeof event.data === 'string' ? event.data : '';
        // engine.io open packet starts with '0'
        if (data.startsWith('0{') || data.startsWith('0\\x7b')) {
          info.engineIO = true;
          if (!info.socketIO) info.detectedProtocol = 'engine.io';
        }
        // Socket.IO connect packet
        if (data === '40' || data.startsWith('40{') || data.startsWith('42[')) {
          info.socketIO = true;
          info.detectedProtocol = 'socket.io';
        }
      };
      ws.addEventListener('message', messageListener);

      window.__wsProtocolInfo.push(info);
      return ws;
    };
    window.WebSocket.prototype = OrigWS.prototype;
    window.WebSocket.CONNECTING = OrigWS.CONNECTING;
    window.WebSocket.OPEN = OrigWS.OPEN;
    window.WebSocket.CLOSING = OrigWS.CLOSING;
    window.WebSocket.CLOSED = OrigWS.CLOSED;

    return 'WebSocket constructor patched for protocol detection';
  }`
})
```

### Step 3 -- Navigate to the Target Page

Navigate after instrumentation is installed to capture all connections from
page load.

```
browser_navigate({ url: "<target_url>" })
```

### Step 4 -- Wait for WebSocket Activity

Allow time for connections to establish and messages to flow.

```
browser_wait_for({ time: 10 })
```

Adjust the wait time based on expected application behavior. For real-time
apps, 10-30 seconds captures a representative sample. For apps that only
connect on specific user actions, perform those actions between waiting.

### Step 5 -- Harvest Connection Data

Retrieve all captured WebSocket data from the CDP monitor.

```javascript
browser_run_code({
  code: `async (page) => {
    const monitor = page.__wsMonitorData;
    const stats = page.__wsMonitorStats();
    if (!monitor) return { error: 'Monitor data not found' };

    return {
      connections: Object.values(monitor.connections),
      stats: stats,
      timelineLength: monitor.timeline.length,
      messageCount: monitor.messages.length
    };
  }`
})
```

### Step 6 -- Analyze Message Payloads

Parse JSON payloads and compute frequency/size statistics.

```javascript
browser_run_code({
  code: `async (page) => {
    const monitor = page.__wsMonitorData;
    if (!monitor) return { error: 'No monitor data' };

    const messages = monitor.messages;
    const analysis = {
      totalMessages: messages.length,
      byDirection: { sent: 0, received: 0 },
      avgSize: { sent: 0, received: 0 },
      jsonMessages: 0,
      binaryMessages: 0,
      messageTypes: {},
      frequencyPerSecond: 0,
      largestMessage: { size: 0, direction: null, preview: null },
      recentMessages: []
    };

    let sentSizes = [], receivedSizes = [];

    for (const msg of messages) {
      if (msg.direction === 'sent') { analysis.byDirection.sent++; sentSizes.push(msg.size); }
      else { analysis.byDirection.received++; receivedSizes.push(msg.size); }

      if (msg.size > analysis.largestMessage.size) {
        analysis.largestMessage = { size: msg.size, direction: msg.direction, preview: msg.payload.substring(0, 200) };
      }

      // Try JSON parse
      let parsed = null;
      try { parsed = JSON.parse(msg.payload); analysis.jsonMessages++; } catch {}

      // Socket.IO format: "42[eventName, data]"
      if (!parsed && msg.payload.match(/^\\d+\\[/)) {
        try {
          const jsonPart = msg.payload.replace(/^\\d+/, '');
          parsed = JSON.parse(jsonPart);
          analysis.jsonMessages++;
          if (Array.isArray(parsed) && typeof parsed[0] === 'string') {
            const eventName = parsed[0];
            analysis.messageTypes[eventName] = (analysis.messageTypes[eventName] || 0) + 1;
          }
        } catch {}
      }

      if (parsed && typeof parsed === 'object' && parsed.type) {
        analysis.messageTypes[parsed.type] = (analysis.messageTypes[parsed.type] || 0) + 1;
      }
    }

    analysis.avgSize.sent = sentSizes.length ? Math.round(sentSizes.reduce((a,b) => a+b, 0) / sentSizes.length) : 0;
    analysis.avgSize.received = receivedSizes.length ? Math.round(receivedSizes.reduce((a,b) => a+b, 0) / receivedSizes.length) : 0;

    if (messages.length >= 2) {
      const duration = (messages[messages.length - 1].time - messages[0].time) / 1000;
      analysis.frequencyPerSecond = duration > 0 ? Math.round((messages.length / duration) * 100) / 100 : 0;
    }

    // Last 10 messages with parsed payloads
    analysis.recentMessages = messages.slice(-10).map(m => ({
      direction: m.direction,
      size: m.size,
      payload: m.payload.substring(0, 500),
      time: m.time
    }));

    return analysis;
  }`
})
```

### Step 7 -- Retrieve Protocol Detection Results

```javascript
browser_evaluate({
  function: `() => {
    return {
      protocols: window.__wsProtocolInfo || [],
      summary: (window.__wsProtocolInfo || []).map(p => p.detectedProtocol + ': ' + p.url)
    };
  }`
})
```

### Step 8 -- Track Reconnections (Optional)

If monitoring over a longer period, check for reconnection patterns.

```javascript
browser_run_code({
  code: `async (page) => {
    const monitor = page.__wsMonitorData;
    if (!monitor) return { error: 'No monitor data' };

    const timeline = monitor.timeline;
    const connections = Object.values(monitor.connections);

    // Group events by URL to detect reconnections
    const byUrl = {};
    for (const conn of connections) {
      if (!byUrl[conn.url]) byUrl[conn.url] = [];
      byUrl[conn.url].push(conn);
    }

    const reconnections = {};
    for (const [url, conns] of Object.entries(byUrl)) {
      if (conns.length > 1) {
        reconnections[url] = {
          connectionCount: conns.length,
          connections: conns.map(c => ({
            status: c.status,
            createdAt: c.createdAt,
            closedAt: c.closedAt,
            duration: c.closedAt ? c.closedAt - c.createdAt : Date.now() - c.createdAt,
            closeCode: c.closeCode
          }))
        };
      }
    }

    return {
      totalUniqueUrls: Object.keys(byUrl).length,
      urlsWithReconnections: Object.keys(reconnections).length,
      reconnections: reconnections
    };
  }`
})
```

## Interpreting Results

### Report Format

```
## WebSocket Monitor -- <url>

### Connections
| # | URL | Protocol | Status | Duration | Messages (S/R) | Bytes (S/R) |
|---|-----|----------|--------|----------|----------------|-------------|
| 1 | wss://api.example.com/ws | socket.io | open | 25.3s | 12/48 | 1.2K/15.6K |
| 2 | wss://cdn.example.com/stream | raw-websocket | open | 25.1s | 0/120 | 0/89.2K |

### Message Analysis
- Total messages: 180
- Frequency: 7.2 msg/sec
- Average size: sent 102B, received 743B
- Largest message: 4.2KB (received) -- JSON array of 50 items

### Message Types (Socket.IO events)
| Event | Count | Direction |
|-------|-------|-----------|
| chat:message | 45 | received |
| presence:update | 32 | received |
| typing | 12 | sent |

### Reconnections
- wss://api.example.com/ws: 3 connections (2 reconnections)
  - Connection 1: closed after 8.2s (code 1006 -- abnormal)
  - Connection 2: closed after 2.1s (code 1006 -- abnormal)
  - Connection 3: open (current, 15.0s)

### Protocol Detection
- Socket.IO v4 detected (engine.io EIO=4 in URL)
- Transport: websocket (upgraded from polling)
```

### WebSocket Close Codes

| Code | Meaning | Notes |
|------|---------|-------|
| 1000 | Normal closure | Clean disconnect |
| 1001 | Going away | Page navigation or server shutdown |
| 1006 | Abnormal closure | No close frame sent (network issue) |
| 1008 | Policy violation | Authentication failure |
| 1011 | Unexpected condition | Server error |
| 1012 | Service restart | Server restarting |
| 1013 | Try again later | Server overloaded |

### What to Look For

- **Frequent reconnections (code 1006)**: network instability or server dropping connections. Check server-side connection timeouts and heartbeat intervals.
- **High message frequency (>50/sec)**: consider batching or throttling messages to reduce overhead.
- **Large payloads (>10KB)**: consider compression (`permessage-deflate` extension) or pagination.
- **Missing heartbeats**: if using Socket.IO, check that `pingInterval` and `pingTimeout` are configured appropriately.
- **One-directional traffic**: if only receiving but never sending (or vice versa), the connection may be used as a pub/sub channel -- verify this is intentional.

## Limitations

- **Chromium only**: CDP WebSocket events are Chromium-specific.
- **Instrumentation timing**: connections established before Step 1 completes will not be captured. The workflow navigates after installing listeners to avoid this.
- **Payload truncation**: payloads longer than 2000 characters are truncated in the capture to prevent memory issues.
- **Binary messages**: binary WebSocket frames are captured but payload content is not decoded (shown as the string representation).
- **WebSocket constructor patch**: the protocol detection patch in Step 2 only captures connections created via `new WebSocket()`. Connections from Web Workers or Service Workers are not patched but are still captured by CDP events (without protocol detection).
- **Close codes**: CDP `webSocketClosed` event does not include the close code. Close codes are only available if the application logs them.
