---
name: state-inspector
description: >
  Detect the frontend framework (React, Vue, Angular, Svelte) and inspect
  application state: React fiber tree traversal with component props/state/hooks
  via __REACT_DEVTOOLS_GLOBAL_HOOK__, Vue instance tree via __VUE__, and store
  inspection for Redux, Vuex, Pinia, Zustand, MobX, and Jotai. Supports state
  snapshots before/after user actions for diffing.
---

# State Inspector

Detect which frontend framework and state management libraries a page uses,
then inspect their internal state. Traverse component trees, read props and
state, snapshot store contents, and diff state changes across user actions.

## When to Use

- Debugging component state without installing browser devtools extensions.
- Understanding the component hierarchy and data flow of an unfamiliar app.
- Verifying that a user action correctly updates application state.
- Inspecting Redux/Vuex/Pinia/Zustand store contents.
- Diffing state before and after an interaction to trace data flow.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- Target page must use a detectable frontend framework (React, Vue, Angular, Svelte, or vanilla JS with state management libraries).
- React DevTools hook detection works best when React is built in development mode. Production builds may have limited fiber tree access.

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

```
browser_wait_for({ time: 2 })
```

### Step 2 -- Detect Frontend Framework and State Libraries

```javascript
browser_evaluate({
  function: `() => {
    const detection = {
      framework: null,
      version: null,
      stateManagement: [],
      details: {}
    };

    // --- React ---
    if (window.__REACT_DEVTOOLS_GLOBAL_HOOK__) {
      detection.framework = 'React';
      const hook = window.__REACT_DEVTOOLS_GLOBAL_HOOK__;
      if (hook.renderers && hook.renderers.size > 0) {
        const renderer = hook.renderers.values().next().value;
        detection.version = renderer.version || 'unknown';
      }
      detection.details.fiberRootCount = hook.getFiberRoots ? hook.getFiberRoots(1)?.size || 0 : 'N/A';
    } else if (document.querySelector('[data-reactroot], [data-reactid]')) {
      detection.framework = 'React';
      detection.version = 'production (no devtools hook)';
    }

    // --- Vue ---
    if (window.__VUE__) {
      detection.framework = detection.framework ? detection.framework + ' + Vue' : 'Vue';
      detection.version = window.__VUE__.version || 'unknown';
    } else if (window.__vue_app__) {
      detection.framework = detection.framework ? detection.framework + ' + Vue' : 'Vue';
      detection.details.vueApp = true;
    } else if (document.querySelector('[data-v-]') || document.querySelector('.__vue-inspector-container')) {
      detection.framework = detection.framework ? detection.framework + ' + Vue' : 'Vue';
      detection.version = 'detected via data-v- attributes';
    }

    // --- Angular ---
    if (window.ng || window.getAllAngularRootElements) {
      detection.framework = detection.framework ? detection.framework + ' + Angular' : 'Angular';
      if (window.ng && window.ng.getComponent) detection.details.angularIvy = true;
    }

    // --- Svelte ---
    if (document.querySelector('[class*="svelte-"]')) {
      detection.framework = detection.framework ? detection.framework + ' + Svelte' : 'Svelte';
    }

    // --- State Management ---
    // Redux
    if (window.__REDUX_DEVTOOLS_EXTENSION__) {
      detection.stateManagement.push('Redux DevTools Extension');
    }
    // Check for Redux store on common locations
    const reduxStore = window.__REDUX_STORE__ || window.store;
    if (reduxStore && typeof reduxStore.getState === 'function' && typeof reduxStore.dispatch === 'function') {
      detection.stateManagement.push('Redux (global store)');
    }

    // Zustand
    if (window.__zustand_stores || document.querySelector('[data-zustand]')) {
      detection.stateManagement.push('Zustand');
    }

    // MobX
    if (window.__mobxGlobals || window.__mobxInstanceCount) {
      detection.stateManagement.push('MobX');
    }

    // Vuex
    if (window.__VUE__ && window.__vue_app__ && window.__vue_app__.config && window.__vue_app__.config.globalProperties.$store) {
      detection.stateManagement.push('Vuex');
    }

    // Pinia
    if (window.__pinia) {
      detection.stateManagement.push('Pinia');
    }

    // Jotai / Recoil (hard to detect without devtools)
    // Check for common patterns

    if (!detection.framework) {
      detection.framework = 'None detected (vanilla JS or unrecognized framework)';
    }

    return detection;
  }`
})
```

### Step 3 -- Traverse React Fiber Tree (if React detected)

Walk the React fiber tree to extract component hierarchy, props, and state.

```javascript
browser_evaluate({
  function: `() => {
    const hook = window.__REACT_DEVTOOLS_GLOBAL_HOOK__;
    if (!hook || !hook.getFiberRoots) {
      return { error: 'React DevTools hook not available. App may be in production mode.' };
    }

    const roots = hook.getFiberRoots(1);
    if (!roots || roots.size === 0) {
      return { error: 'No fiber roots found' };
    }

    const root = roots.values().next().value;
    const tree = [];
    let nodeCount = 0;
    const maxNodes = 100;

    function getHooksState(fiber) {
      const hooks = [];
      let hook = fiber.memoizedState;
      let idx = 0;
      while (hook && idx < 10) {
        let value = hook.memoizedState;
        // Simplify complex objects
        if (value && typeof value === 'object') {
          try {
            const str = JSON.stringify(value);
            if (str.length > 500) value = str.substring(0, 500) + '...';
            else value = JSON.parse(str);
          } catch {
            value = '[Complex Object]';
          }
        }
        hooks.push({ index: idx, value: value });
        hook = hook.next;
        idx++;
      }
      return hooks;
    }

    function walkFiber(fiber, depth) {
      if (!fiber || nodeCount >= maxNodes) return;

      // Only include function/class components, skip host elements
      if (typeof fiber.type === 'function' || (fiber.type && fiber.type.$$typeof)) {
        nodeCount++;
        const name = fiber.type.displayName || fiber.type.name || 'Anonymous';

        let props = {};
        if (fiber.memoizedProps) {
          try {
            const p = {};
            for (const [key, val] of Object.entries(fiber.memoizedProps)) {
              if (key === 'children') { p.children = typeof val === 'string' ? val.substring(0, 50) : '[children]'; continue; }
              if (typeof val === 'function') { p[key] = '[Function]'; continue; }
              if (typeof val === 'object' && val !== null) {
                try { const s = JSON.stringify(val); p[key] = s.length > 200 ? s.substring(0, 200) + '...' : JSON.parse(s); }
                catch { p[key] = '[Object]'; }
                continue;
              }
              p[key] = val;
            }
            props = p;
          } catch { props = '[Error reading props]'; }
        }

        const hooks = getHooksState(fiber);

        tree.push({
          depth: depth,
          name: name,
          key: fiber.key || null,
          props: props,
          hooks: hooks.length > 0 ? hooks : null,
          hasState: hooks.length > 0
        });
      }

      // Traverse children
      walkFiber(fiber.child, typeof fiber.type === 'function' ? depth + 1 : depth);
      // Traverse siblings
      walkFiber(fiber.sibling, depth);
    }

    walkFiber(root.current, 0);

    return {
      totalComponents: nodeCount,
      maxDepth: Math.max(...tree.map(n => n.depth), 0),
      tree: tree
    };
  }`
})
```

### Step 4 -- Inspect Vue Instance Tree (if Vue detected)

```javascript
browser_evaluate({
  function: `() => {
    // Vue 3
    const app = window.__vue_app__;
    if (!app) {
      // Try to find Vue instance from DOM
      const el = document.querySelector('[__vue_app__]') || document.getElementById('app');
      if (el && el.__vue_app__) {
        window.__vue_app__ = el.__vue_app__;
      } else {
        return { error: 'Vue app instance not found' };
      }
    }

    const tree = [];
    let count = 0;
    const maxNodes = 100;

    function walkVueTree(instance, depth) {
      if (!instance || count >= maxNodes) return;
      count++;

      const name = instance.type ? (instance.type.name || instance.type.__name || 'Anonymous') : 'Root';

      let data = {};
      if (instance.setupState) {
        try {
          for (const [key, val] of Object.entries(instance.setupState)) {
            if (typeof val === 'function') { data[key] = '[Function]'; continue; }
            try { const s = JSON.stringify(val); data[key] = s.length > 200 ? s.substring(0, 200) + '...' : JSON.parse(s); }
            catch { data[key] = '[Reactive Object]'; }
          }
        } catch {}
      }

      let props = {};
      if (instance.props) {
        try {
          for (const [key, val] of Object.entries(instance.props)) {
            if (typeof val === 'function') { props[key] = '[Function]'; continue; }
            try { const s = JSON.stringify(val); props[key] = s.length > 200 ? s.substring(0, 200) + '...' : JSON.parse(s); }
            catch { props[key] = '[Object]'; }
          }
        } catch {}
      }

      tree.push({
        depth: depth,
        name: name,
        props: Object.keys(props).length > 0 ? props : null,
        data: Object.keys(data).length > 0 ? data : null
      });

      // Traverse children
      const subTree = instance.subTree;
      if (subTree && subTree.component) {
        walkVueTree(subTree.component, depth + 1);
      }
      if (subTree && subTree.children) {
        for (const child of (Array.isArray(subTree.children) ? subTree.children : [])) {
          if (child && child.component) {
            walkVueTree(child.component, depth + 1);
          }
        }
      }
    }

    const rootInstance = app._instance;
    if (rootInstance) {
      walkVueTree(rootInstance, 0);
    }

    return { totalComponents: count, tree: tree };
  }`
})
```

### Step 5 -- Inspect State Management Stores

#### Redux Store

```javascript
browser_evaluate({
  function: `() => {
    // Try common Redux store locations
    const store = window.__REDUX_STORE__ || window.store;

    // If Redux DevTools extension is present, try to get state from it
    if (!store && window.__REDUX_DEVTOOLS_EXTENSION__) {
      return { source: 'Redux DevTools Extension detected but store not directly accessible' };
    }

    if (!store || typeof store.getState !== 'function') {
      return { found: false };
    }

    const state = store.getState();
    let serialized;
    try {
      serialized = JSON.parse(JSON.stringify(state));
    } catch {
      serialized = '[Unserializable state]';
    }

    // Get top-level keys and their sizes
    const slices = {};
    if (typeof serialized === 'object' && serialized !== null) {
      for (const [key, val] of Object.entries(serialized)) {
        const str = JSON.stringify(val);
        slices[key] = {
          type: Array.isArray(val) ? 'array[' + val.length + ']' : typeof val,
          size: str ? str.length : 0,
          preview: str ? str.substring(0, 300) : null
        };
      }
    }

    return {
      found: true,
      source: 'Redux',
      sliceCount: Object.keys(slices).length,
      slices: slices
    };
  }`
})
```

#### Pinia Stores (Vue)

```javascript
browser_evaluate({
  function: `() => {
    const pinia = window.__pinia;
    if (!pinia) return { found: false };

    const stores = {};
    if (pinia._s) {
      pinia._s.forEach((store, id) => {
        const state = {};
        try {
          for (const [key, val] of Object.entries(store.$state)) {
            try { state[key] = JSON.parse(JSON.stringify(val)); }
            catch { state[key] = '[Unserializable]'; }
          }
        } catch {}
        stores[id] = {
          id: id,
          state: state,
          getters: Object.keys(store).filter(k => !k.startsWith('$') && !k.startsWith('_') && typeof store[k] !== 'function' && !(k in store.$state)),
          actions: Object.keys(store).filter(k => !k.startsWith('$') && !k.startsWith('_') && typeof store[k] === 'function')
        };
      });
    }

    return { found: true, source: 'Pinia', storeCount: Object.keys(stores).length, stores: stores };
  }`
})
```

#### Zustand Stores (React)

```javascript
browser_evaluate({
  function: `() => {
    // Zustand stores are typically not on window, but we can try to find them
    // through React fiber tree or known globals
    const stores = {};

    // Check if stores are exposed globally
    for (const key of Object.keys(window)) {
      const val = window[key];
      if (val && typeof val === 'object' && typeof val.getState === 'function' && typeof val.subscribe === 'function' && typeof val.setState === 'function') {
        try {
          const state = val.getState();
          stores[key] = {
            state: JSON.parse(JSON.stringify(state)),
            stateKeys: Object.keys(state)
          };
        } catch {
          stores[key] = { state: '[Unserializable]' };
        }
      }
    }

    return {
      found: Object.keys(stores).length > 0,
      source: 'Zustand (globally exposed)',
      stores: stores
    };
  }`
})
```

### Step 6 -- Take State Snapshot (Before Action)

Create a labeled snapshot of all detectable state for later diffing.

```javascript
browser_evaluate({
  function: `() => {
    const snapshot = { timestamp: Date.now(), label: 'before' };

    // Redux
    const reduxStore = window.__REDUX_STORE__ || window.store;
    if (reduxStore && typeof reduxStore.getState === 'function') {
      try { snapshot.redux = JSON.parse(JSON.stringify(reduxStore.getState())); } catch {}
    }

    // Pinia
    if (window.__pinia && window.__pinia._s) {
      snapshot.pinia = {};
      window.__pinia._s.forEach((store, id) => {
        try { snapshot.pinia[id] = JSON.parse(JSON.stringify(store.$state)); } catch {}
      });
    }

    // React component state (simplified -- top-level hooks)
    const hook = window.__REACT_DEVTOOLS_GLOBAL_HOOK__;
    if (hook && hook.getFiberRoots) {
      const roots = hook.getFiberRoots(1);
      if (roots && roots.size > 0) {
        snapshot.reactSnapshotAvailable = true;
      }
    }

    window.__stateSnapshot_before = snapshot;
    return { snapshotTaken: true, label: 'before', keys: Object.keys(snapshot) };
  }`
})
```

### Step 7 -- Perform User Action

Use `browser_snapshot` to find the target element, then interact with it.

```
browser_snapshot()
```

Click a button, submit a form, or perform the action whose state change you
want to observe:

```
browser_click({ ref: "<ref_from_snapshot>", element: "Target action element" })
```

```
browser_wait_for({ time: 2 })
```

### Step 8 -- Take State Snapshot (After Action) and Diff

```javascript
browser_evaluate({
  function: `() => {
    const snapshot = { timestamp: Date.now(), label: 'after' };

    // Redux
    const reduxStore = window.__REDUX_STORE__ || window.store;
    if (reduxStore && typeof reduxStore.getState === 'function') {
      try { snapshot.redux = JSON.parse(JSON.stringify(reduxStore.getState())); } catch {}
    }

    // Pinia
    if (window.__pinia && window.__pinia._s) {
      snapshot.pinia = {};
      window.__pinia._s.forEach((store, id) => {
        try { snapshot.pinia[id] = JSON.parse(JSON.stringify(store.$state)); } catch {}
      });
    }

    window.__stateSnapshot_after = snapshot;

    // Compute diff
    const before = window.__stateSnapshot_before;
    if (!before) return { error: 'No before snapshot found' };

    function diff(a, b, path) {
      const changes = [];
      if (a === b) return changes;
      if (typeof a !== typeof b) {
        changes.push({ path, before: a, after: b, type: 'type_change' });
        return changes;
      }
      if (typeof a !== 'object' || a === null || b === null) {
        if (a !== b) changes.push({ path, before: a, after: b, type: 'value_change' });
        return changes;
      }
      const allKeys = new Set([...Object.keys(a), ...Object.keys(b)]);
      for (const key of allKeys) {
        if (!(key in a)) {
          changes.push({ path: path + '.' + key, before: undefined, after: b[key], type: 'added' });
        } else if (!(key in b)) {
          changes.push({ path: path + '.' + key, before: a[key], after: undefined, type: 'removed' });
        } else {
          changes.push(...diff(a[key], b[key], path + '.' + key));
        }
      }
      return changes;
    }

    const diffs = {};
    if (before.redux && snapshot.redux) {
      diffs.redux = diff(before.redux, snapshot.redux, 'redux');
    }
    if (before.pinia && snapshot.pinia) {
      diffs.pinia = diff(before.pinia, snapshot.pinia, 'pinia');
    }

    return {
      timeDelta: snapshot.timestamp - before.timestamp,
      diffs: diffs,
      totalChanges: Object.values(diffs).reduce((sum, d) => sum + d.length, 0)
    };
  }`
})
```

## Interpreting Results

### Report Format

```
## State Inspector -- <url>

### Framework Detection
- Framework: React 18.2.0
- State Management: Redux, Zustand

### Component Tree (top 15)
| Depth | Component | Props | Hooks/State |
|-------|-----------|-------|-------------|
| 0 | App | {} | 2 hooks |
| 1 | Router | {basename: "/"} | 1 hook |
| 2 | Layout | {} | 0 hooks |
| 3 | Header | {user: {name: "John"}} | 1 hook |
| 3 | MainContent | {isLoading: false} | 3 hooks |
| 4 | ProductList | {items: Array[12]} | 2 hooks |

### Redux Store
| Slice | Type | Size | Preview |
|-------|------|------|---------|
| user | object | 342B | {name: "John", email: "..."} |
| cart | array[3] | 1.2KB | [{id: 1, qty: 2}, ...] |
| ui | object | 89B | {sidebarOpen: false, theme: "light"} |

### State Diff (after clicking "Add to Cart")
| Path | Before | After | Type |
|------|--------|-------|------|
| redux.cart.length | 3 | 4 | value_change |
| redux.cart.3 | undefined | {id: 5, qty: 1} | added |
| redux.ui.cartBadge | 3 | 4 | value_change |

Total changes: 3 in 245ms
```

### What to Look For

- **Deeply nested component trees (>15 levels)**: may indicate unnecessary wrapper components or missing composition patterns.
- **Large props objects**: components receiving too many props may need refactoring (container/presenter pattern).
- **Stale state after action**: if the diff shows no changes after a user action, the event handler may not be dispatching correctly.
- **Overly large store slices**: Redux slices with >100KB of data may cause performance issues. Consider normalization or lazy loading.
- **Missing state management in detected framework**: if React is detected but no Redux/Zustand/Context state is found, the app may use prop drilling extensively.

## Limitations

- **Production React builds**: production React builds strip component names and may obfuscate the fiber tree. Development builds provide significantly more detail.
- **React DevTools hook dependency**: fiber tree traversal requires `__REACT_DEVTOOLS_GLOBAL_HOOK__` which is injected by React DevTools or React itself in development mode.
- **Zustand store detection**: Zustand stores are not globally exposed by default. Only stores attached to `window` can be detected. Most apps keep stores in module scope.
- **Vue 2 vs Vue 3**: the Vue inspection code targets Vue 3 APIs (`__vue_app__`, `setupState`). Vue 2 uses different internal APIs (`__vue__`, `$data`).
- **Snapshot serialization**: state containing circular references, DOM nodes, or class instances cannot be fully serialized. These are replaced with placeholder strings.
- **Diff depth**: the recursive diff has no depth limit but truncates display. Very large state trees may produce thousands of diff entries.
