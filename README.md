# binaryPetsClaude

Claude Code plugins marketplace by binaryPets.

## Installation

Add this marketplace to Claude Code:

```bash
claude plugin marketplace add https://github.com/anouar1991/binaryPetsClaude
```

## Available Plugins

| Plugin | Description | Version |
|--------|-------------|---------|
| [rules-learning-pipeline](./plugins/rules-learning-pipeline) | Automated learning pipeline that evaluates model sessions, extracts lessons, and optimizes CLAUDE.md rules | 1.0.0 |
| [zimbra-toolkit](./plugins/zimbra-toolkit) | Comprehensive toolkit for Zimbra administration, mail flow, APIs, and zimlet development (Classic & Modern) | 1.0.0 |

## Plugin Highlights

### rules-learning-pipeline

Automatically improve your CLAUDE.md rules by analyzing model behavior:
- Evaluate agentic workflows and tool-use trajectories
- Extract lessons from execution errors
- Optimize prompts following Claude best practices

### zimbra-toolkit

Complete Zimbra development and administration toolkit:
- **6 Skills**: zimbra-admin, zimbra-mail-flow, zimbra-api, zimlet-classic, zimlet-modern, zimlet-debugging
- **5 Commands**: `/diagnose`, `/provision`, `/zimlet-scaffold`, `/backup-config`, `/zimlet-sideload`
- **2 Agents**: zimbra-troubleshooter, zimlet-reviewer
- **50+ Modern UI Slots** documented with patterns and examples
- **Expert debugging techniques** including secret URL parameters

## Usage

After adding the marketplace, install plugins:

```bash
# List available plugins
claude plugin list --marketplace binaryPetsClaude

# Install a plugin
claude plugin install rules-learning-pipeline@binaryPetsClaude
claude plugin install zimbra-toolkit@binaryPetsClaude
```

## Author

**Noreddine Belhadj Cheikh**
Email: noreddine.belhadjcheikh@gmail.com

## License

MIT
