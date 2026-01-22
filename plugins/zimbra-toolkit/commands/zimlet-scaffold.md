---
description: Generate zimlet project boilerplate (Classic or Modern)
allowed-tools: Write, Bash, AskUserQuestion
argument-hint: [classic|modern] [zimlet-name]
---

Generate a zimlet project scaffold for Zimbra development.

## Determine Zimlet Type

If $1 is "classic" or "modern", use that type.
Otherwise, ask the user which type they want to create:

**Classic Zimlet:**
- XML-based definition
- JavaScript handler class
- For Zimbra Classic Web Client
- Zimbra 8.x and earlier
- Legacy but stable

**Modern Zimlet:**
- Preact/React components
- GraphQL integration
- For Zimbra Modern Web Client
- Zimbra 9.x and later
- New development recommended

## Get Zimlet Name

If $2 is provided, use it as the zimlet name.
Otherwise, ask for:
- Company/organization prefix (e.g., "acme")
- Zimlet name (e.g., "tickettracker")

## Classic Zimlet Scaffold

If creating classic zimlet:

### Package Name

Format: `com_<company>_<zimletname>` (lowercase, underscores only)
Example: `com_acme_tickettracker`

### Create Directory Structure

```
com_acme_tickettracker/
├── com_acme_tickettracker.xml
├── com_acme_tickettracker.js
├── com_acme_tickettracker.css
└── img/
    └── icon.png (placeholder)
```

### Generate XML Definition

Write `com_acme_tickettracker.xml`:

```xml
<zimlet name="com_acme_tickettracker" version="1.0.0"
        description="Description of your zimlet"
        xmlns="urn:zimbraZimlet">

    <!-- Panel item in side panel -->
    <zimletPanelItem label="Ticket Tracker" icon="com_acme_tickettracker-icon">
        <toolTipText>Click to open Ticket Tracker</toolTipText>
    </zimletPanelItem>

    <!-- Include JavaScript handler -->
    <include>com_acme_tickettracker.js</include>

    <!-- Include CSS -->
    <includeCSS>com_acme_tickettracker.css</includeCSS>

    <!-- User properties (preferences) -->
    <userProperties>
        <property name="setting1" type="string">default</property>
    </userProperties>

</zimlet>
```

### Generate JavaScript Handler

Write `com_acme_tickettracker.js`:

```javascript
/**
 * Zimlet Handler for com_acme_tickettracker
 */
function com_acme_tickettracker_HandlerObject() {
}

com_acme_tickettracker_HandlerObject.prototype = new ZmZimletBase();
com_acme_tickettracker_HandlerObject.prototype.constructor = com_acme_tickettracker_HandlerObject;

/**
 * Called when zimlet is initialized
 */
com_acme_tickettracker_HandlerObject.prototype.init = function() {
    console.log("[TicketTracker] Zimlet initialized");
};

/**
 * Called when panel item is single-clicked
 */
com_acme_tickettracker_HandlerObject.prototype.singleClicked = function() {
    this._showMainDialog();
};

/**
 * Called when panel item is double-clicked
 */
com_acme_tickettracker_HandlerObject.prototype.doubleClicked = function() {
    this.singleClicked();
};

/**
 * Show main dialog
 */
com_acme_tickettracker_HandlerObject.prototype._showMainDialog = function() {
    if (!this._dialog) {
        var view = new DwtComposite(this.getShell());
        view.setSize("400", "300");
        view.getHtmlElement().innerHTML = this._createDialogContent();

        this._dialog = new ZmDialog({
            title: "Ticket Tracker",
            view: view,
            parent: this.getShell(),
            standardButtons: [DwtDialog.OK_BUTTON, DwtDialog.CANCEL_BUTTON]
        });
    }
    this._dialog.popup();
};

com_acme_tickettracker_HandlerObject.prototype._createDialogContent = function() {
    return '<div style="padding: 20px;">' +
           '<h3>Ticket Tracker</h3>' +
           '<p>Your zimlet content here.</p>' +
           '</div>';
};
```

### Generate CSS

Write `com_acme_tickettracker.css`:

```css
/* Styles for com_acme_tickettracker */
.com_acme_tickettracker-icon {
    background: url('img/icon.png') no-repeat center;
    background-size: 16px 16px;
}
```

## Modern Zimlet Scaffold

If creating modern zimlet:

### Project Name

Format: `<zimlet-name>` (kebab-case)
Example: `ticket-tracker`

### Create Using zimlet-cli

If zimlet-cli is installed:
```bash
zimlet create ticket-tracker
```

Otherwise, create manually:

### Create Directory Structure

```
ticket-tracker/
├── package.json
├── zimlet.json
├── src/
│   ├── index.js
│   └── components/
│       ├── App.js
│       └── App.less
└── public/
    └── icon.png
```

### Generate package.json

Write `package.json`:

```json
{
  "name": "ticket-tracker",
  "version": "1.0.0",
  "description": "Ticket Tracker Zimlet",
  "main": "src/index.js",
  "scripts": {
    "build": "zimlet build",
    "watch": "zimlet watch",
    "package": "zimlet package"
  },
  "dependencies": {
    "preact": "^10.0.0"
  },
  "devDependencies": {
    "@zimbra/zimlet-cli": "^14.0.0"
  }
}
```

### Generate zimlet.json

Write `zimlet.json`:

```json
{
  "name": "ticket-tracker",
  "version": "1.0.0",
  "description": "Ticket Tracker Zimlet for Modern Web Client",
  "label": "Ticket Tracker",
  "icon": "icon.png",
  "host": "https://mail.example.com",
  "slots": {
    "menu": true,
    "routes": true,
    "sidebars": true
  }
}
```

### Generate Entry Point

Write `src/index.js`:

```javascript
import { createElement } from 'preact';
import App from './components/App';

export default function Zimlet(context) {
    const { plugins } = context;
    const exports = {};

    // Menu slot - add item to hamburger menu
    exports.menu = {
        handler: function MenuHandler(menu, context) {
            const { MenuItem } = context.zimletComps;
            return [
                <MenuItem
                    icon="fa fa-ticket"
                    onClick={() => context.openSidebar('ticket-tracker')}
                >
                    Ticket Tracker
                </MenuItem>
            ];
        }
    };

    // Sidebar slot
    exports.sidebars = {
        handler: function SidebarHandler() {
            return {
                'ticket-tracker': () => Promise.resolve({ default: App })
            };
        }
    };

    // Routes slot
    exports.routes = {
        handler: function RouteHandler() {
            return [
                {
                    path: '/ticket-tracker',
                    component: App
                }
            ];
        }
    };

    plugins.register('ticket-tracker', exports);
}
```

### Generate Main Component

Write `src/components/App.js`:

```javascript
import { createElement } from 'preact';
import { useState } from 'preact/hooks';
import style from './App.less';

export default function App({ context }) {
    const [count, setCount] = useState(0);

    return (
        <div class={style.container}>
            <h1>Ticket Tracker</h1>
            <p>Welcome to your new zimlet!</p>
            <button onClick={() => setCount(count + 1)}>
                Clicked {count} times
            </button>
        </div>
    );
}
```

### Generate Styles

Write `src/components/App.less`:

```less
.container {
    padding: 20px;

    h1 {
        color: #333;
        margin-bottom: 16px;
    }

    button {
        padding: 8px 16px;
        background: #007bff;
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;

        &:hover {
            background: #0056b3;
        }
    }
}
```

## Output

After scaffold is created:

```
=== Zimlet Scaffold Created ===

Type: [Classic/Modern]
Name: [package-name]
Location: [path]

Files Created:
  - [list of files]

Next Steps:
  1. [Development instructions]
  2. [How to build]
  3. [How to deploy]
  4. [Documentation links]
```

For Classic: Provide zmzimletctl deployment commands
For Modern: Provide npm install and zimlet watch instructions
