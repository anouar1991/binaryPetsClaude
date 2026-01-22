# Zimbra Toolkit Plugin

A comprehensive Claude Code plugin for Zimbra administrators and zimlet developers. Covers both Classic and Modern UI development with expert-level debugging techniques.

## Features

### Skills (Auto-activate based on context)

| Skill | Triggers | Coverage |
|-------|----------|----------|
| **zimbra-admin** | "zmprov", "zmcontrol", "zimbra user" | Server administration, user/domain management, COS |
| **zimbra-mail-flow** | "postfix", "content filter", "mail queue" | MTA integration, routing, spam filtering |
| **zimbra-api** | "SOAP API", "REST API", "LDAP" | API integration, authentication, queries |
| **zimlet-classic** | "classic zimlet", "zimlet XML", "DWT" | XML manifests, JavaScript handlers, DWT widgets |
| **zimlet-modern** | "modern zimlet", "Preact", "GraphQL" | Component development, 50+ slots, Apollo |
| **zimlet-debugging** | "debug zimlet", "sideloader", "zimlet error" | Expert debugging, URL parameters, troubleshooting |

### Commands

| Command | Description |
|---------|-------------|
| `/zimbra:diagnose` | Diagnose Zimbra services, ports, and common issues |
| `/zimbra:provision` | Guide through user/domain provisioning |
| `/zimbra:zimlet-scaffold` | Generate zimlet project boilerplate (Classic or Modern) |
| `/zimbra:backup-config` | Export current Zimbra configuration |
| `/zimbra:zimlet-sideload` | Setup and use the zimlet sideloader for development |

### Agents

| Agent | Trigger | Purpose |
|-------|---------|---------|
| **zimbra-troubleshooter** | "emails not delivering", "zimbra error" | Autonomous layer-by-layer debugging |
| **zimlet-reviewer** | "review my zimlet", "zimlet code review" | Best practices and security review |

## Key Documentation

### Modern Zimlet Development

- **50+ UI Slots** - Comprehensive slot reference organized by category (Header, Email, Calendar, Briefcase, etc.)
- **Code Patterns** - Project structure, component patterns, store patterns, service layer
- **GraphQL Integration** - Apollo Client usage, queries, mutations
- **Essential Tip:** Add `?zimletSlots=show` to your Zimbra URL to visualize all slot locations!

### Classic Zimlet Development

- **DWT Widget Library** - `DwtControl`, `DwtButton`, `DwtListView`, `DwtMenu`, `ZmToast`
- **XML Schema** - `<zimletPanelItem>`, `<contentObject>`, `<contextMenu>`
- **Namespace Safety** - CSS/JS prefixing to avoid conflicts

### Expert Debugging Techniques

| URL Parameter | Purpose |
|---------------|---------|
| `?dev=1` | Developer mode - unminified source files |
| `?debug=1/2/3` | Built-in Zimbra debug window for SOAP traffic |
| `?mode=mjsf` | Multiple JS Files - individual files for breakpoints |
| `?zimletSlots=show` | Visualize Modern UI slot locations |

## Installation

### Via Marketplace (Recommended)

```bash
# Add marketplace
claude plugin marketplace add https://github.com/anouar1991/binaryPetsClaude

# Install plugin
claude plugin install zimbra-toolkit@binaryPetsClaude
```

### Local Development

```bash
claude --plugin-dir /path/to/zimbra-toolkit
```

## Configuration (Optional)

Create `.claude/zimbra-toolkit.local.md` for server-specific settings:

```yaml
---
zimbra_host: mail.example.com
zimbra_user: zimbra
zimbra_version: 10.0
---

# Server Notes

Additional notes about this Zimbra installation...
```

## Supported Versions

- Zimbra 8.8.x (Legacy/Classic UI)
- Zimbra 9.x (Classic + Modern UI)
- Zimbra 10.x (Modern UI preferred)

## Quick Start Examples

### Ask about administration
```
"How do I create a Zimbra distribution list with zmprov?"
→ Triggers zimbra-admin skill
```

### Ask about zimlet development
```
"How do I add a button to the email toolbar in Modern UI?"
→ Triggers zimlet-modern skill with slot documentation
```

### Debug a zimlet issue
```
"My zimlet isn't loading in the browser"
→ Triggers zimlet-debugging skill with troubleshooting steps
```

### Use a command
```
/zimbra:zimlet-scaffold modern my-zimlet
→ Generates complete modern zimlet boilerplate
```

## Plugin Structure

```
zimbra-toolkit/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── zimbra-troubleshooter.md
│   └── zimlet-reviewer.md
├── commands/
│   ├── diagnose.md
│   ├── provision.md
│   ├── zimlet-scaffold.md
│   ├── backup-config.md
│   └── zimlet-sideload.md
├── skills/
│   ├── zimbra-admin/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── zmprov-commands.md
│   │       └── ldap-attributes.md
│   ├── zimbra-mail-flow/
│   │   └── SKILL.md
│   ├── zimbra-api/
│   │   └── SKILL.md
│   ├── zimlet-classic/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── zimlet-modern/
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── slot-api.md          # 50+ slots documented
│   │       ├── code-patterns.md     # Best practices
│   │       └── graphql-schema.md
│   └── zimlet-debugging/
│       ├── SKILL.md
│       └── references/
│           └── sideloader-setup.md
└── README.md
```

## Resources

### Official Documentation
- [Zimbra API Documentation](https://zimbra.github.io/zm-api-docs/)
- [Zimbra Wiki - ModernUI Zimlets](https://wiki.zimbra.com/wiki/ModernUI-Zimlets)
- [Zimlet Development Guide](https://github.com/Zimbra/zm-zimlet-guide)

### Example Zimlets
- [zimbra-zimlet-nextcloud](https://github.com/Zimbra/zimbra-zimlet-nextcloud)
- [zimbra-zimlet-sticky-notes](https://github.com/Zimbra/zimbra-zimlet-sticky-notes)
- [Zimbra Zimlet Gallery](https://gallery.zetalliance.org/extend/category/modern)

### Development Tools
- [Preact Documentation](https://preactjs.com/guide/v10/getting-started)
- [Apollo Client DevTools](https://www.apollographql.com/docs/react/development-testing/developer-tooling/)

## Contributing

Found an issue or want to add more documentation? Contributions welcome!

## License

MIT
