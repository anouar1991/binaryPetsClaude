# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Code plugins marketplace by binaryPets. Contains plugins that extend Claude Code functionality.

**Installation:**
```bash
/plugin marketplace add anouar1991/binaryPetsClaude
/plugin install <plugin-name>@binaryPetsClaude
```

## Architecture

```
binaryPetsClaude/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace manifest
├── plugins/
│   └── {plugin-name}/
│       ├── .claude-plugin/
│       │   └── plugin.json       # Plugin manifest
│       ├── agents/               # Specialized subagents (.md)
│       ├── commands/             # User-invocable commands (.md)
│       └── skills/               # Reusable knowledge patterns (.md)
└── README.md
```

### Plugin Components

| Component | Purpose | Invocation |
|-----------|---------|------------|
| **Agents** | Autonomous workers for specific tasks | Via Task tool with `subagent_type` |
| **Commands** | User-invocable pipelines | `/plugin-name:command-name` |
| **Skills** | Reusable knowledge/patterns | Auto-invoked by agents or `/plugin-name:skill-name` |

### Manifest Schemas

**marketplace.json** (top-level):
```json
{
  "name": "marketplace-name",
  "owner": { "name": "...", "email": "..." },
  "plugins": [{ "name": "...", "source": "./plugins/..." }]
}
```

**plugin.json** (per-plugin):
```json
{
  "name": "plugin-name",
  "description": "...",
  "version": "1.0.0",
  "author": { "name": "...", "email": "..." }
}
```

### Agent/Command/Skill Format

All use YAML frontmatter + Markdown:
```markdown
---
name: component-name
description: What it does
tools: Read, Write, Edit, Grep, Glob, Task  # (agents/commands only)
color: red                                   # (agents only)
---

# Component Title

## Mission/Purpose
...
```

## Current Plugins

### rules-learning-pipeline

Automated learning pipeline that evaluates model sessions, extracts lessons, and optimizes CLAUDE.md rules.

**Commands:**
- `/rules-learning-pipeline:learn-from-session <file>` - Full 4-phase pipeline
- `/rules-learning-pipeline:evaluate-model <file>` - Phase 1 only
- `/rules-learning-pipeline:critics-review <file>` - Phase 2 only
- `/rules-learning-pipeline:optimize-prompts <file>` - Phase 3 only

**4-Phase Pipeline:**
1. **Evaluate** (model-evaluator): Parse sessions, calculate metrics, extract lessons
2. **Review** (critics-reviewer): Validate scopes, check specificity, catch missed patterns
3. **Optimize** (prompt-optimizer): Route lessons by scope, apply peripheral bias, write rules
4. **Report**: Generate summary, update changelog

**Wasteful Patterns Detected:**
- BDN (Broad-Dismiss-Narrow): Full check → dismiss errors → narrow check
- CIP (Check-Ignore-Proceed): Find errors → ignore → continue
- Verification Theater: "verify" → errors → "looks good"
- Redundant Tool Chains: Multiple tools when one suffices

**User Correction Patterns Detected:**
- UCP (User Correction Pattern): User had to correct model's wrong value
- IEI (Ignored Explicit Instruction): Model didn't use value user provided
- RIP (Repeated Instruction Pattern): User repeated same request multiple times
- CIA (Critical Info Amnesia): Model forgot info provided earlier in session
- VSE (Value Substitution Error): Model substituted user's value with default

**Scope Classification:**
| Scope | Target | Usage |
|-------|--------|-------|
| user-general | `~/.claude/CLAUDE.md` | Universal practices |
| cross-project-domain | `~/.claude/rules/{framework}.md` | Framework-specific |
| project | `project/CLAUDE.md` | Project-specific |
| domain | `context/rules/{domain}.md` | Project + domain-specific |

## Development Guidelines

### Adding a New Plugin

1. Create directory: `plugins/{plugin-name}/`
2. Add manifest: `plugins/{plugin-name}/.claude-plugin/plugin.json`
3. Add to marketplace: Update `.claude-plugin/marketplace.json` plugins array
4. Add components in `agents/`, `commands/`, `skills/` subdirectories

### Component Best Practices

**Agents:**
- Define clear mission and output format
- Specify allowed tools in frontmatter
- Include workflow phases

**Commands:**
- Document usage with examples
- Specify pipeline phases if orchestrating agents
- Include output file locations

**Skills:**
- Keep focused on single concern
- Document detection patterns
- Include output format examples
