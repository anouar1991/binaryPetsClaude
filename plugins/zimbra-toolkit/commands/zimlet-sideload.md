---
description: Setup and use the zimlet sideloader for development
allowed-tools: Bash, Read, WebFetch, AskUserQuestion
argument-hint: [setup|add|list|remove] [url]
---

Help configure and use the Zimbra zimlet sideloader for local development.

## Determine Action

Based on $1:
- **setup**: Guide through sideloader installation
- **add**: Add a local zimlet URL to sideload
- **list**: Show currently sideloaded zimlets
- **remove**: Remove a sideloaded zimlet
- (no argument): Show status and available actions

## Setup Sideloader

If action is "setup":

### 1. Check Prerequisites

- Modern browser (Chrome/Firefox recommended)
- Zimbra Modern Web Client access
- Local development environment (Node.js for modern zimlets)

### 2. Install Sideloader Extension

**Option A: Build from Source**

```bash
# Clone the sideloader repository
git clone https://github.com/Zimbra/zm-x-sideloader.git
cd zm-x-sideloader

# Install dependencies
npm install

# Build extension
npm run build
```

**Option B: Pre-built Extension**

Check if pre-built version is available in the Zimbra releases.

### 3. Load Extension in Browser

**Chrome:**
1. Navigate to `chrome://extensions/`
2. Enable "Developer mode" (toggle in top-right)
3. Click "Load unpacked"
4. Select the `zm-x-sideloader/dist` directory
5. Sideloader icon appears in toolbar

**Firefox:**
1. Navigate to `about:debugging#/runtime/this-firefox`
2. Click "Load Temporary Add-on..."
3. Select any file in `zm-x-sideloader/dist`
4. Sideloader icon appears in toolbar

### 4. Verify Installation

- Click sideloader extension icon
- Should see empty list of sideloaded zimlets
- Status should show "Ready"

### 5. Configure Zimbra Server (Optional)

For development, may need to allow CORS:

```bash
# On Zimbra server (as zimbra user)
zmprov mcf +zimbraResponseHeader "Access-Control-Allow-Origin: *"
zmmailboxdctl restart
```

**Note**: Only do this on development servers, not production.

## Add Zimlet URL

If action is "add":

### 1. Get Zimlet URL

If $2 is provided, use it as the URL.
Otherwise, prompt for the local zimlet URL.

Common patterns:
- `http://localhost:8081/index.js` (zimlet watch default)
- `http://localhost:3000/index.js` (custom dev server)

### 2. Verify Local Server Running

```bash
# Check if local dev server is running
curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/index.js
```

If not running, guide user to start it:
```bash
cd /path/to/zimlet
zimlet watch
```

### 3. Add to Sideloader

Provide instructions:

1. Click sideloader extension icon in browser toolbar
2. In the input field, enter: `[URL]`
3. Click "Add" or press Enter
4. URL appears in sideloaded list

### 4. Reload Zimbra

1. Navigate to Zimbra Modern Web Client
2. Refresh the page (Ctrl+R / Cmd+R)
3. Zimlet should now be active

### 5. Verify Loading

Check browser console for zimlet initialization:
- Open DevTools (F12)
- Console tab
- Look for zimlet log messages

## List Sideloaded Zimlets

If action is "list":

Provide instructions to view current sideloads:

1. Click sideloader extension icon
2. View list of URLs being sideloaded
3. Each entry shows:
   - URL
   - Status (active/error)
   - Remove button

## Remove Sideloaded Zimlet

If action is "remove":

If $2 is provided, identify zimlet to remove.
Otherwise, prompt for which URL to remove.

Instructions:

1. Click sideloader extension icon
2. Find the zimlet URL in the list
3. Click the "X" or "Remove" button next to it
4. Refresh Zimbra to see changes

## Troubleshooting

### Zimlet Not Loading

**Check local server:**
```bash
# Verify server is running
curl http://localhost:8081/index.js
```

**Check browser console:**
- Open DevTools → Console
- Look for errors related to zimlet loading
- Common issues:
  - CORS errors: Need server-side CORS config
  - 404 errors: Wrong URL or server not running
  - Syntax errors: Fix code and rebuild

**Check sideloader status:**
- Click extension icon
- Verify URL is in the list
- Check for error indicators

### CORS Errors

If seeing "Access-Control-Allow-Origin" errors:

**On Zimbra server:**
```bash
zmprov mcf +zimbraResponseHeader "Access-Control-Allow-Origin: *"
zmmailboxdctl restart
```

**Or use browser extension:**
Install a CORS-allowing extension for development only.

### Hot Reload Not Working

**Verify zimlet watch is running:**
```bash
zimlet watch
# Should show "Listening on http://localhost:8081"
```

**Check for build errors:**
Look at terminal running `zimlet watch` for compilation errors.

**Hard refresh:**
- Chrome: Ctrl+Shift+R (Cmd+Shift+R on Mac)
- Clear browser cache if needed

### Extension Not Working

**Reinstall extension:**
1. Remove extension from browser
2. Rebuild: `npm run build`
3. Reload unpacked extension

**Check extension permissions:**
- Ensure extension has access to Zimbra domain

## Development Workflow

Recommended workflow for zimlet development:

```
1. Start local dev server
   $ cd my-zimlet
   $ zimlet watch

2. Add URL to sideloader
   - Click extension → Add URL

3. Open Zimbra Modern Web Client
   - Navigate to mail.domain.com

4. Make code changes
   - Edit source files
   - Watch auto-rebuilds

5. Refresh browser to see changes
   - Ctrl+R / Cmd+R

6. Debug with DevTools
   - Console for logs
   - Network for requests
   - Sources for breakpoints

7. When ready, build for production
   $ zimlet build
   $ zimlet package
```

## Output

Provide appropriate guidance based on action:

- **setup**: Step-by-step installation guide
- **add**: Confirm URL added, verify loading
- **list**: Show current sideloaded URLs
- **remove**: Confirm removal, refresh instruction

Always include troubleshooting tips for common issues.
