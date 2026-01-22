---
name: Zimlet Debugging
description: This skill should be used when the user asks about "zimlet sideloader", "debug zimlet", "zimlet not loading", "zimlet error", "zimlet console", "zimlet dev mode", "zimlet hot reload", "zimlet breakpoint", or mentions troubleshooting zimlet development. Covers debugging techniques for both Classic and Modern zimlets.
version: 1.0.0
---

# Zimlet Debugging

Comprehensive guide for debugging zimlets during development and troubleshooting production issues.

## Development Setup

### Modern Zimlets (Sideloader)

The sideloader enables local development without deploying to the server.

#### Install Sideloader Extension

1. Build the sideloader extension:
```bash
git clone https://github.com/Zimbra/zm-x-sideloader
cd zm-x-sideloader
npm install
npm run build
```

2. Load in Chrome:
   - Navigate to `chrome://extensions/`
   - Enable "Developer mode"
   - Click "Load unpacked"
   - Select `zm-x-sideloader/dist`

#### Configure Sideloader

1. Click the sideloader extension icon in Chrome
2. Add your local zimlet URL (e.g., `http://localhost:8081/index.js`)
3. Navigate to your Zimbra Modern Web Client
4. The sideloader injects your local zimlet code

#### Local Development Workflow

```bash
# Start zimlet dev server
cd my-zimlet
zimlet watch

# Output:
# Listening on http://localhost:8081
# Zimlet available at http://localhost:8081/index.js

# Add this URL to sideloader extension
# Refresh Zimbra web client to see changes
```

### Classic Zimlets (Dev Mode)

Enable unminified JavaScript:

```
https://mail.domain.com/?dev=1
```

Or set server-wide:

```bash
zmprov ms mail.domain.com zimbraZimletDevMode TRUE
zmmailboxdctl restart
```

## Browser Developer Tools

### Console Logging

#### Modern Zimlet Logging

```javascript
// Add logging throughout your code
export default function Zimlet(context) {
    console.log('[MyZimlet] Initializing with context:', context);

    const { plugins } = context;

    plugins.register('my-zimlet', {
        menu: {
            handler: function(menu, ctx) {
                console.log('[MyZimlet] Menu handler called');
                console.log('[MyZimlet] Current account:', ctx.account);
                return [];
            }
        }
    });
}
```

#### Classic Zimlet Logging

```javascript
com_mycompany_myzimlet_HandlerObject.prototype.init = function() {
    console.log("[MyZimlet] init() called");
    console.log("[MyZimlet] User properties:", this.getUserProperty("allProperties"));
    DBG.println(AjxDebug.DBG1, "[MyZimlet] Debug level message");
};
```

### Network Tab Analysis

Monitor GraphQL and SOAP requests:

1. Open DevTools → Network tab
2. Filter by:
   - `graphql` for Modern zimlets
   - `service/soap` for Classic zimlets
3. Inspect request/response payloads
4. Check for error responses (look for `faultcode`)

### Breakpoint Debugging

#### Source Maps (Modern)

```bash
# Build with source maps
zimlet build --sourcemaps

# Or in zimlet watch mode (enabled by default)
zimlet watch
```

Then in DevTools:
1. Go to Sources tab
2. Find your source files under `webpack://`
3. Set breakpoints in original source code

#### Classic Zimlet Breakpoints

```javascript
// Add debugger statement
com_mycompany_myzimlet_HandlerObject.prototype.singleClicked = function() {
    debugger; // Browser pauses here when DevTools open
    this._showDialog();
};
```

Or set breakpoints directly in browser:
1. Sources → find `com_mycompany_myzimlet.js`
2. Click line number to set breakpoint

## Common Issues and Solutions

### Zimlet Not Loading

#### Modern Zimlet

**Symptoms**: No errors, zimlet simply doesn't appear

**Debugging steps**:
```javascript
// 1. Verify entry point is exporting correctly
export default function Zimlet(context) {
    console.log('[DEBUG] Zimlet function called');
    // ...
}

// 2. Check slot registration
plugins.register('my-zimlet', exports);
console.log('[DEBUG] Registered exports:', exports);

// 3. Verify slots are enabled in zimlet.json
// Check: "slots": { "menu": true }
```

**Common causes**:
- Missing `export default` on zimlet function
- Slot not enabled in `zimlet.json`
- JavaScript error preventing initialization
- Zimlet not enabled for user's COS

**Check zimlet is deployed**:
```bash
zmzimletctl listZimlets | grep my-zimlet
```

#### Classic Zimlet

**Debugging steps**:
```bash
# Check zimlet is deployed
zmzimletctl listZimlets

# Check zimlet is enabled for COS
zmprov gc default zimbraZimletAvailableZimlets | grep my-zimlet

# Check for JavaScript errors in console
# Enable dev mode: ?dev=1
```

### Slot Not Rendering

```javascript
// Debug slot handler
exports.menu = {
    handler: function(menu, context) {
        console.log('[DEBUG] Menu slot handler called');
        console.log('[DEBUG] Menu param:', menu);
        console.log('[DEBUG] Context:', context);

        const items = [
            <MenuItem onClick={() => console.log('clicked')}>
                Test Item
            </MenuItem>
        ];

        console.log('[DEBUG] Returning items:', items);
        return items;
    }
};
```

**Common causes**:
- Handler returning `null` or `undefined`
- Handler throwing exception (check console)
- Slot name mismatch between code and manifest
- Component import error

### GraphQL Errors

```javascript
// Add error handling to queries
function MyComponent() {
    const { data, loading, error } = useQuery(MY_QUERY);

    if (error) {
        console.error('[MyZimlet] GraphQL error:', error);
        console.error('[MyZimlet] GraphQL error details:', error.graphQLErrors);
        console.error('[MyZimlet] Network error:', error.networkError);
        return <div>Error: {error.message}</div>;
    }

    // ... rest of component
}
```

**Common GraphQL issues**:
- Invalid field names (check schema)
- Missing required variables
- Authentication expired
- Permission denied

### CORS Errors (External APIs)

```javascript
// Symptom: Network requests to external APIs fail with CORS error

// Solution 1: Use proxy through Zimbra server
const response = await fetch('/service/proxy?target=' + encodeURIComponent(externalUrl));

// Solution 2: Configure external service to allow CORS
// Add headers: Access-Control-Allow-Origin: https://mail.domain.com

// Solution 3: Use server-side extension (if available)
```

### State Not Updating

```javascript
// Debug state changes
const [myState, setMyState] = useState(initialValue);

useEffect(() => {
    console.log('[DEBUG] State changed:', myState);
}, [myState]);

const handleUpdate = (newValue) => {
    console.log('[DEBUG] Setting state to:', newValue);
    setMyState(newValue);
};
```

**Common causes**:
- Not using state setter function correctly
- Mutating state directly instead of creating new object
- useEffect dependency array issues

## Performance Debugging

### Profile Renders

```javascript
import { Component } from 'preact';

class ProfiledComponent extends Component {
    componentDidUpdate(prevProps) {
        console.log('[PERF] Component updated');
        console.log('[PERF] Previous props:', prevProps);
        console.log('[PERF] New props:', this.props);
    }

    render() {
        console.log('[PERF] Rendering component');
        return <div>{/* ... */}</div>;
    }
}
```

### Check Bundle Size

```bash
# Analyze bundle
zimlet build --analyze

# Opens webpack-bundle-analyzer showing module sizes
```

### Memory Leaks

```javascript
// Clean up subscriptions and timers
function MyComponent() {
    useEffect(() => {
        const timer = setInterval(() => {
            console.log('tick');
        }, 1000);

        // Cleanup function
        return () => {
            console.log('[DEBUG] Cleaning up timer');
            clearInterval(timer);
        };
    }, []);
}
```

## Server-Side Debugging

### Check Zimlet Logs

```bash
# Zimlet deployment logs
tail -f /opt/zimbra/log/mailbox.log | grep -i zimlet

# Search for specific zimlet
grep "my-zimlet" /opt/zimbra/log/mailbox.log
```

### Verify Zimlet Configuration

```bash
# List deployed zimlets
zmzimletctl listZimlets

# Check zimlet properties
zmprov gaz my-zimlet

# Check zimlet enabled for COS
zmprov gc default zimbraZimletAvailableZimlets

# Check zimlet config
zmprov gcz com_mycompany_myzimlet
```

### Redeploy Zimlet

```bash
# Undeploy first
zmzimletctl undeploy my-zimlet

# Clear cache
zmprov fc all

# Redeploy
zmzimletctl deploy my-zimlet.zip

# Restart mailbox (if needed)
zmmailboxdctl restart
```

## Debug Checklist

### Modern Zimlet Not Working

- [ ] Sideloader extension installed and enabled
- [ ] Local URL added to sideloader
- [ ] `zimlet watch` running without errors
- [ ] Console shows "Zimlet function called"
- [ ] No JavaScript errors in console
- [ ] Slots enabled in `zimlet.json`
- [ ] `export default` present on main function
- [ ] Zimlet registered with `plugins.register()`

### Classic Zimlet Not Working

- [ ] Zimlet deployed: `zmzimletctl listZimlets`
- [ ] Enabled for COS: `zmprov gc default zimbraZimletAvailableZimlets`
- [ ] No XML syntax errors (check mailbox.log)
- [ ] Handler class name matches package name
- [ ] `init()` function called (add console.log)
- [ ] No JavaScript errors in console

## Additional Resources

### Reference Files

- **`references/sideloader-setup.md`** - Detailed sideloader configuration
- **`references/common-errors.md`** - Error message reference

### Example Files

- **`examples/debug-logging.js`** - Comprehensive logging setup
- **`examples/error-boundary.js`** - Error handling component
