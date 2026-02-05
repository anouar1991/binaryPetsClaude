---
name: form-debugger
description: >
  Analyze all forms on a page: validation states, autocomplete attribute
  coverage, label/input association, required field audit, submission behavior
  interception, password field security, and ARIA attributes on custom controls.
---

# Form Debugger

Perform a comprehensive audit of all forms on a page covering HTML5 validation,
accessibility, autocomplete, security, and submission behavior.

## When to Use

- Auditing form accessibility before launch (labels, ARIA, focus order).
- Debugging validation issues (mismatched patterns, missing required attributes).
- Verifying autocomplete attributes for browser autofill compatibility.
- Checking password field security (autocomplete, visibility toggle, strength).
- Understanding form submission behavior (action, method, encoding, JS intercept).
- Reviewing custom form controls for ARIA compliance.

## Prerequisites

- **Playwright MCP server** connected and responding (all `mcp__playwright__browser_*` tools available).
- Target page must contain one or more `<form>` elements or form controls.

## Workflow

### Step 1 -- Navigate to the Target Page

```
browser_navigate({ url: "<target_url>" })
```

### Step 2 -- Enumerate All Forms and Inputs

Collect detailed metadata about every form and its inputs.

```javascript
browser_evaluate({
  function: `() => {
    const forms = Array.from(document.querySelectorAll('form'));
    const orphanInputs = Array.from(document.querySelectorAll('input:not(form input), select:not(form select), textarea:not(form textarea)'));

    function getInputInfo(input) {
      const labels = [];
      // Explicit label via for attribute
      if (input.id) {
        document.querySelectorAll('label[for="' + input.id + '"]').forEach(l => labels.push(l.textContent.trim()));
      }
      // Implicit label (input inside label)
      const parentLabel = input.closest('label');
      if (parentLabel) labels.push(parentLabel.textContent.trim().substring(0, 100));
      // aria-label and aria-labelledby
      const ariaLabel = input.getAttribute('aria-label');
      const ariaLabelledBy = input.getAttribute('aria-labelledby');
      let ariaLabelText = null;
      if (ariaLabelledBy) {
        ariaLabelText = ariaLabelledBy.split(' ').map(id => {
          const el = document.getElementById(id);
          return el ? el.textContent.trim() : null;
        }).filter(Boolean).join(' ');
      }

      const validity = input.validity ? {
        valid: input.validity.valid,
        valueMissing: input.validity.valueMissing,
        typeMismatch: input.validity.typeMismatch,
        patternMismatch: input.validity.patternMismatch,
        tooLong: input.validity.tooLong,
        tooShort: input.validity.tooShort,
        rangeUnderflow: input.validity.rangeUnderflow,
        rangeOverflow: input.validity.rangeOverflow,
        stepMismatch: input.validity.stepMismatch,
        customError: input.validity.customError,
        validationMessage: input.validationMessage || null
      } : null;

      return {
        tag: input.tagName,
        type: input.type || null,
        name: input.name || null,
        id: input.id || null,
        required: input.required || input.getAttribute('aria-required') === 'true',
        disabled: input.disabled,
        readOnly: input.readOnly || false,
        placeholder: input.placeholder || null,
        autocomplete: input.autocomplete || 'NOT SET',
        pattern: input.pattern || null,
        minLength: input.minLength > -1 ? input.minLength : null,
        maxLength: input.maxLength > -1 ? input.maxLength : null,
        min: input.min || null,
        max: input.max || null,
        value: input.type === 'password' ? '[REDACTED]' : (input.value || '').substring(0, 50),
        labels: labels,
        ariaLabel: ariaLabel,
        ariaLabelText: ariaLabelText,
        hasLabel: labels.length > 0 || !!ariaLabel || !!ariaLabelText,
        role: input.getAttribute('role'),
        ariaInvalid: input.getAttribute('aria-invalid'),
        ariaDescribedBy: input.getAttribute('aria-describedby'),
        validity: validity,
        tabIndex: input.tabIndex
      };
    }

    const formData = forms.map((form, idx) => ({
      index: idx,
      id: form.id || null,
      name: form.name || null,
      action: form.action || null,
      method: form.method || 'GET',
      enctype: form.enctype || null,
      noValidate: form.noValidate,
      target: form.target || null,
      inputCount: form.elements.length,
      inputs: Array.from(form.elements).map(getInputInfo)
    }));

    const orphans = orphanInputs.map(getInputInfo);

    return {
      formCount: forms.length,
      forms: formData,
      orphanInputCount: orphans.length,
      orphanInputs: orphans.slice(0, 20)
    };
  }`
})
```

### Step 3 -- Capture Accessibility Tree for Form Structure

Use the accessibility snapshot to verify how assistive technologies see the
form structure.

```
browser_snapshot()
```

### Step 4 -- Audit Autocomplete Coverage

Check that interactive fields have appropriate `autocomplete` values.

```javascript
browser_evaluate({
  function: `() => {
    const inputs = Array.from(document.querySelectorAll('input, select, textarea'));
    const autocompleteAudit = { covered: 0, missing: 0, incorrect: [], recommendations: [] };

    const typeToAutocomplete = {
      email: 'email',
      tel: 'tel',
      url: 'url',
      password: 'current-password',
      text: null // depends on context
    };

    const nameHints = {
      'first': 'given-name', 'firstname': 'given-name', 'fname': 'given-name',
      'last': 'family-name', 'lastname': 'family-name', 'lname': 'family-name',
      'name': 'name', 'fullname': 'name',
      'email': 'email', 'mail': 'email',
      'phone': 'tel', 'tel': 'tel', 'mobile': 'tel',
      'address': 'street-address', 'street': 'street-address',
      'city': 'address-level2', 'state': 'address-level1',
      'zip': 'postal-code', 'postal': 'postal-code', 'postcode': 'postal-code',
      'country': 'country-name',
      'cc-number': 'cc-number', 'cardnumber': 'cc-number',
      'cc-exp': 'cc-exp', 'expiry': 'cc-exp',
      'cc-csc': 'cc-csc', 'cvv': 'cc-csc', 'cvc': 'cc-csc',
      'username': 'username', 'user': 'username',
      'organization': 'organization', 'company': 'organization'
    };

    for (const input of inputs) {
      if (input.type === 'hidden' || input.type === 'submit' || input.type === 'button' || input.type === 'reset') continue;
      if (input.disabled || input.readOnly) continue;

      const ac = input.autocomplete;
      if (ac && ac !== 'on' && ac !== 'off') {
        autocompleteAudit.covered++;
      } else {
        autocompleteAudit.missing++;
        // Try to recommend based on name/id
        const identifier = (input.name || input.id || '').toLowerCase();
        for (const [hint, value] of Object.entries(nameHints)) {
          if (identifier.includes(hint)) {
            autocompleteAudit.recommendations.push({
              element: input.tagName + (input.id ? '#' + input.id : '') + (input.name ? '[name=' + input.name + ']' : ''),
              current: ac || 'NOT SET',
              recommended: value,
              reason: 'Name/ID contains "' + hint + '"'
            });
            break;
          }
        }
        // Type-based recommendation
        if (typeToAutocomplete[input.type] && !autocompleteAudit.recommendations.find(r => r.element.includes(input.id || input.name || ''))) {
          autocompleteAudit.recommendations.push({
            element: input.tagName + (input.id ? '#' + input.id : '') + (input.name ? '[name=' + input.name + ']' : ''),
            current: ac || 'NOT SET',
            recommended: typeToAutocomplete[input.type],
            reason: 'Input type is "' + input.type + '"'
          });
        }
      }
    }

    return autocompleteAudit;
  }`
})
```

### Step 5 -- Audit Password Field Security

Check password inputs for security best practices.

```javascript
browser_evaluate({
  function: `() => {
    const passwordInputs = Array.from(document.querySelectorAll('input[type="password"]'));
    if (passwordInputs.length === 0) return { found: false, message: 'No password fields found' };

    return passwordInputs.map(input => {
      const form = input.closest('form');
      return {
        id: input.id || null,
        name: input.name || null,
        autocomplete: input.autocomplete || 'NOT SET',
        autocompleteCorrect: ['current-password', 'new-password'].includes(input.autocomplete),
        minLength: input.minLength > -1 ? input.minLength : null,
        maxLength: input.maxLength > -1 ? input.maxLength : null,
        hasPattern: !!input.pattern,
        pattern: input.pattern || null,
        required: input.required,
        hasVisibilityToggle: !!(input.parentElement && input.parentElement.querySelector('[class*="eye"], [class*="toggle"], [class*="show"], [class*="visibility"], [aria-label*="show"], [aria-label*="toggle"]')),
        formAction: form ? form.action : null,
        formMethod: form ? form.method : null,
        formIsHTTPS: form ? (form.action || '').startsWith('https') || !(form.action || '').startsWith('http') : null,
        ariaDescribedBy: input.getAttribute('aria-describedby'),
        hasStrengthIndicator: !!document.querySelector('[class*="strength"], [class*="meter"], [role="meter"], [role="progressbar"]')
      };
    });
  }`
})
```

### Step 6 -- Intercept Form Submission

Install a submit event interceptor to capture submission behavior without
actually submitting the form.

```javascript
browser_evaluate({
  function: `() => {
    window.__formSubmissions = [];
    document.querySelectorAll('form').forEach((form, idx) => {
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const formData = new FormData(form);
        const entries = {};
        for (const [key, val] of formData.entries()) {
          entries[key] = typeof val === 'string' ? val.substring(0, 100) : '[File: ' + val.name + ']';
        }
        window.__formSubmissions.push({
          formIndex: idx,
          formId: form.id || null,
          action: form.action,
          method: form.method,
          enctype: form.enctype,
          data: entries,
          timestamp: Date.now(),
          defaultPrevented: true
        });
      }, { capture: true });
    });
    return 'Submit interceptors installed on ' + document.querySelectorAll('form').length + ' forms';
  }`
})
```

### Step 7 -- Test Autocomplete with browser_fill_form

Use `browser_snapshot` to identify form fields, then test browser autofill
behavior using `browser_fill_form`.

```
browser_snapshot()
```

Based on the snapshot, fill a representative form:

```
browser_fill_form({
  fields: [
    { name: "First Name", type: "textbox", ref: "<ref_from_snapshot>", value: "Jane" },
    { name: "Last Name", type: "textbox", ref: "<ref_from_snapshot>", value: "Doe" },
    { name: "Email", type: "textbox", ref: "<ref_from_snapshot>", value: "jane.doe@example.com" }
  ]
})
```

### Step 8 -- Audit Custom Controls for ARIA

Check non-native form controls (divs/spans acting as inputs) for required ARIA
attributes.

```javascript
browser_evaluate({
  function: `() => {
    const roles = ['combobox', 'listbox', 'slider', 'spinbutton', 'switch', 'searchbox', 'textbox', 'checkbox', 'radio', 'radiogroup', 'menuitemcheckbox', 'menuitemradio'];
    const customControls = Array.from(document.querySelectorAll(roles.map(r => '[role="' + r + '"]').join(',')));

    // Also find div/span with click handlers that might be custom controls
    const clickables = Array.from(document.querySelectorAll('div[tabindex], span[tabindex], div[onclick], span[onclick]'));
    const allCustom = [...new Set([...customControls, ...clickables])];

    return allCustom.map(el => {
      const role = el.getAttribute('role');
      const issues = [];

      // Required: role
      if (!role) issues.push('Missing role attribute');

      // Required: accessible name
      const hasName = el.getAttribute('aria-label') || el.getAttribute('aria-labelledby') || el.getAttribute('title');
      if (!hasName) issues.push('Missing accessible name (aria-label, aria-labelledby, or title)');

      // Required for interactive: tabindex
      if (el.tabIndex < 0 && !el.closest('[tabindex]')) issues.push('Not keyboard accessible (tabindex < 0)');

      // Role-specific checks
      if (role === 'checkbox' || role === 'switch') {
        if (!el.getAttribute('aria-checked')) issues.push('Missing aria-checked');
      }
      if (role === 'combobox') {
        if (!el.getAttribute('aria-expanded')) issues.push('Missing aria-expanded');
        if (!el.getAttribute('aria-controls') && !el.getAttribute('aria-owns')) issues.push('Missing aria-controls/aria-owns');
      }
      if (role === 'slider') {
        if (!el.getAttribute('aria-valuenow')) issues.push('Missing aria-valuenow');
        if (!el.getAttribute('aria-valuemin')) issues.push('Missing aria-valuemin');
        if (!el.getAttribute('aria-valuemax')) issues.push('Missing aria-valuemax');
      }

      return {
        tag: el.tagName,
        role: role,
        id: el.id || null,
        class: el.className ? String(el.className).split(' ')[0] : null,
        text: el.textContent.trim().substring(0, 50),
        ariaLabel: el.getAttribute('aria-label'),
        tabIndex: el.tabIndex,
        issues: issues,
        compliant: issues.length === 0
      };
    });
  }`
})
```

### Step 9 -- Retrieve Submission Data (if forms were submitted)

```javascript
browser_evaluate({
  function: `() => {
    return {
      submissions: window.__formSubmissions || [],
      count: (window.__formSubmissions || []).length
    };
  }`
})
```

## Interpreting Results

### Report Format

```
## Form Debugger Audit -- <url>

### Form Summary
| # | ID | Method | Action | Inputs | Issues |
|---|----|--------|--------|--------|--------|
| 0 | login-form | POST | /api/auth | 3 | 1 label missing |
| 1 | search-form | GET | /search | 1 | autocomplete not set |

### Label/Input Association
- 12/14 inputs have associated labels (86%)
- Missing labels:
  1. INPUT#phone-ext [type=text] -- no label, no aria-label
  2. SELECT#country -- no label (has placeholder only)

### Autocomplete Coverage
- 8/14 inputs have autocomplete: 57%
- Recommendations:
  1. INPUT#fname -- set autocomplete="given-name" (name contains "fname")
  2. INPUT#email -- set autocomplete="email" (type is "email")
  3. INPUT[type=password] -- set autocomplete="current-password"

### Validation States
- 3 required fields found
- Pattern validation on 1 field (email regex)
- No custom validity messages set

### Password Security
- autocomplete: "NOT SET" (should be "current-password" or "new-password")
- No minLength constraint
- No visibility toggle found
- No strength indicator found
- Form submits over HTTPS

### Custom Controls ARIA Audit
| Control | Role | Issues |
|---------|------|--------|
| DIV.dropdown | combobox | Missing aria-expanded, missing aria-controls |
| SPAN.toggle | (none) | Missing role, missing accessible name |

### Submission Behavior
- Form #0 (login-form): submit event intercepted, POST to /api/auth
- Fields submitted: username, password
```

### What to Look For

- **Missing labels**: every input must have an associated `<label>`, `aria-label`, or `aria-labelledby`. Screen readers cannot announce unlabeled inputs.
- **autocomplete="off" on login forms**: browsers may ignore this. Use `autocomplete="current-password"` or `autocomplete="new-password"` for password managers.
- **Missing required attribute**: if a field must be filled, use `required` and/or `aria-required="true"`.
- **Custom controls without ARIA**: div/span-based dropdowns, toggles, and sliders must have appropriate `role`, `aria-*` attributes, and keyboard handling.
- **Password fields without minLength**: no minimum length encourages weak passwords.
- **Form submission over HTTP**: credentials sent in plain text. Always use HTTPS.

## Limitations

- **Submit interception is JavaScript-only**: forms submitted via native browser behavior before the interceptor loads will not be captured.
- **Custom validation libraries**: the tool inspects native HTML5 `ValidityState`. Custom JS validation (e.g., Formik, Yup, Zod) is not detected through this mechanism.
- **Dynamic forms**: forms loaded after the initial audit (via AJAX, SPA navigation) require re-running the evaluation steps.
- **autocomplete recommendations are heuristic**: the name/ID matching is best-effort. Manual review is needed for non-standard naming.
