# Zimbra Modern Zimlet Slot API Reference

Complete reference for available slots in Zimbra Modern Web Client.

## Slot System Overview

Slots are injection points in the Modern Web Client UI where zimlets can add components. Slots are registered in `zimlet.json` and implemented in the zimlet's entry point.

## Available Slots

### Navigation Slots

#### menu

**Location:** Hamburger menu
**Purpose:** Add navigation items

```javascript
exports.menu = {
    handler: function(menu, context) {
        const { MenuItem } = context.zimletComps;
        return [
            <MenuItem
                icon="fa fa-star"
                onClick={() => context.openSidebar('my-panel')}
            >
                My Item
            </MenuItem>
        ];
    }
};
```

#### routes

**Location:** App routing
**Purpose:** Add custom views/pages

```javascript
exports.routes = {
    handler: function() {
        return [
            {
                path: '/my-route',
                component: () => import('./components/MyView')
            }
        ];
    }
};
```

### Sidebar Slots

#### sidebars

**Location:** Right side panels
**Purpose:** Custom contextual panels

```javascript
exports.sidebars = {
    handler: function() {
        return {
            'my-sidebar': () => import('./components/MySidebar')
        };
    }
};

// Open sidebar: context.openSidebar('my-sidebar')
```

### Compose Slots

#### compose-attachment-buttons

**Location:** Compose toolbar
**Purpose:** Custom attachment sources

```javascript
exports['compose-attachment-buttons'] = {
    handler: function(props) {
        return [
            <button onClick={() => props.onAttach({ type: 'my-source' })}>
                Attach from My Service
            </button>
        ];
    }
};
```

#### composer-toolbar

**Location:** Rich text editor toolbar
**Purpose:** Custom formatting buttons

```javascript
exports['composer-toolbar'] = {
    handler: function(props) {
        return [
            <button onClick={() => props.execCommand('bold')}>
                Custom Bold
            </button>
        ];
    }
};
```

### Action Menu Slots

#### mail-action-menu

**Location:** Email context menu
**Purpose:** Message actions

```javascript
exports['mail-action-menu'] = {
    handler: function(props, context) {
        return [
            <MenuItem onClick={() => handleMessage(props.message)}>
                My Action
            </MenuItem>
        ];
    }
};
```

#### calendar-action-menu

**Location:** Calendar event context menu
**Purpose:** Event actions

```javascript
exports['calendar-action-menu'] = {
    handler: function(props) {
        return [
            <MenuItem onClick={() => handleEvent(props.event)}>
                Export Event
            </MenuItem>
        ];
    }
};
```

#### contact-action-menu

**Location:** Contact context menu
**Purpose:** Contact actions

```javascript
exports['contact-action-menu'] = {
    handler: function(props) {
        return [
            <MenuItem onClick={() => handleContact(props.contact)}>
                Sync Contact
            </MenuItem>
        ];
    }
};
```

### Search Slots

#### search-bar

**Location:** Search area
**Purpose:** Search enhancements

```javascript
exports['search-bar'] = {
    handler: function(props) {
        return [
            <button onClick={() => props.setQuery('special:filter')}>
                Quick Filter
            </button>
        ];
    }
};
```

## zimlet.json Slot Configuration

Enable slots in `zimlet.json`:

```json
{
  "name": "my-zimlet",
  "slots": {
    "menu": true,
    "routes": true,
    "sidebars": true,
    "compose-attachment-buttons": true,
    "mail-action-menu": true
  }
}
```

## Handler Context

Slot handlers receive context object with:

```javascript
{
    // Zimbra components
    zimletComps: { MenuItem, Button, Dialog, ... },

    // Account info
    account: { name, email, authToken, ... },

    // Actions
    openSidebar: (name) => void,
    closeSidebar: () => void,

    // Apollo client
    getApolloClient: () => ApolloClient,

    // Internationalization
    intl: { formatMessage, ... }
}
```

## Slot Handler Return Types

| Return Type | Usage |
|-------------|-------|
| `JSX.Element[]` | Array of components |
| `Promise<Component>` | Async component loading |
| `null` | Don't render anything |
| `Object` | Configuration object (routes, sidebars) |
