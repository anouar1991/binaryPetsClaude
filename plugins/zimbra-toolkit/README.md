# Zimbra Toolkit Plugin

A comprehensive Claude Code plugin for Zimbra administrators and developers.

## Features

### Skills (Auto-activate based on context)

- **zimbra-admin** - Server administration with zmprov, zmcontrol, user/domain management
- **zimbra-mail-flow** - Postfix integration, content filters, queues, routing
- **zimbra-api** - SOAP API, REST API, LDAP queries, authentication
- **zimlet-classic** - Classic zimlet development (XML, JavaScript, slots, panels)
- **zimlet-modern** - Modern zimlet development (React/Preact, GraphQL, slots)
- **zimlet-debugging** - Sideloader, browser debugging, logging, troubleshooting

### Commands

- `/zimbra:diagnose` - Diagnose Zimbra services, ports, and common issues
- `/zimbra:provision` - Guide through user/domain provisioning
- `/zimbra:zimlet-scaffold` - Generate zimlet project boilerplate (Classic or Modern)
- `/zimbra:backup-config` - Export current Zimbra configuration
- `/zimbra:zimlet-sideload` - Setup and use the zimlet sideloader

### Agents

- **zimbra-troubleshooter** - Autonomous debugging of Zimbra issues
- **zimlet-reviewer** - Code review for zimlet best practices

## Installation

### Local Development
```bash
claude --plugin-dir /path/to/zimbra-toolkit
```

### Add to Project
Copy to your project's `.claude-plugins/` directory.

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

- Zimbra 8.8.x (Legacy)
- Zimbra 9.x
- Zimbra 10.x

## Testing the Plugin

### Test Installation

```bash
# From the zimbra-toolkit directory
claude --plugin-dir .
```

### Verify Skills Load

Ask questions that should trigger skills:

- "How do I create a Zimbra user with zmprov?" → Should load `zimbra-admin`
- "How do I set up a content filter in Postfix?" → Should load `zimbra-mail-flow`
- "How do I use the Zimbra SOAP API?" → Should load `zimbra-api`
- "How do I create a classic zimlet?" → Should load `zimlet-classic`
- "How do I create a modern zimlet with Preact?" → Should load `zimlet-modern`
- "My zimlet isn't loading, how do I debug it?" → Should load `zimlet-debugging`

### Test Commands

```bash
# In Claude Code session:
/zimbra:diagnose
/zimbra:provision user test@domain.com
/zimbra:zimlet-scaffold modern my-zimlet
/zimbra:backup-config ./backup
/zimbra:zimlet-sideload setup
```

### Test Agents

Create scenarios that should trigger agents:

- "Emails aren't being delivered, can you help?" → Should trigger `zimbra-troubleshooter`
- "Can you review my zimlet code in com_acme_tracker?" → Should trigger `zimlet-reviewer`

## Resources

- [Zimbra Documentation](https://zimbra.github.io/zm-api-docs/)
- [Zimlet Development Guide](https://github.com/Zimbra/zimlet-cli)
- [Zimbra GitHub](https://github.com/Zimbra)

## Plugin Structure

```
zimbra-toolkit/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── agents/
│   ├── zimbra-troubleshooter.md # Debugging agent
│   └── zimlet-reviewer.md       # Code review agent
├── commands/
│   ├── diagnose.md              # /zimbra:diagnose
│   ├── provision.md             # /zimbra:provision
│   ├── zimlet-scaffold.md       # /zimbra:zimlet-scaffold
│   ├── backup-config.md         # /zimbra:backup-config
│   └── zimlet-sideload.md       # /zimbra:zimlet-sideload
├── skills/
│   ├── zimbra-admin/            # Administration skill
│   ├── zimbra-mail-flow/        # Mail transport skill
│   ├── zimbra-api/              # API integration skill
│   ├── zimlet-classic/          # Classic zimlet skill
│   ├── zimlet-modern/           # Modern zimlet skill
│   └── zimlet-debugging/        # Debugging skill
└── README.md
```
