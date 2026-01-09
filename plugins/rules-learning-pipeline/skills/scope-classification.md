---
name: scope-classification
description: Classify lessons into correct scopes for proper routing
---

# Scope Classification Skill

Determines the correct scope for each lesson to ensure proper routing to rule files.

## Scope Types

| Scope | Target File | Applies To |
|-------|-------------|------------|
| user-general | `~/.claude/CLAUDE.md` | ANY project, ANY framework |
| cross-project-domain | `~/.claude/rules/{framework}.md` | ANY project using specific framework |
| project | `project/CLAUDE.md` | THIS project only, spans domains |
| domain | `context/rules/{domain}.md` | THIS project, specific domain |

## Decision Tree

```
FOR each lesson:

Q1: Does this apply to ANY project using ANY framework?
    YES → Q2
    NO  → Q3

Q2: Is it framework-specific (Django, React, Claude API)?
    YES → scope: cross-project-domain
          route: ~/.claude/rules/{framework}.md
    NO  → scope: user-general
          route: ~/.claude/CLAUDE.md

Q3: Is it specific to THIS project?
    YES → Q4
    NO  → scope: user-general (default)

Q4: Does it span multiple domains in this project?
    YES → scope: project
          route: project/CLAUDE.md
    NO  → scope: domain
          route: context/rules/{domain}.md
```

## Classification Examples

| Lesson | Scope | Rationale |
|--------|-------|-----------|
| "Read file before editing" | user-general | Universal best practice |
| "Claude API requires messages array" | cross-project-domain | Framework-specific, any project |
| "Trace Django URL routing first" | cross-project-domain | Django-specific, any project |
| "React useRef for connections" | cross-project-domain | React-specific, any project |
| "Zimbra at 172.17.0.4:2525" | project | IP/port specific to deployment |
| "Use context-router.md" | project | This project's convention |
| "Use SocketEvents enum" | domain (realtime) | Project-specific, single domain |

## Common Misclassifications

| Pattern | WRONG | CORRECT | Fix |
|---------|-------|---------|-----|
| Claude API patterns | project | cross-project-domain | Route to ~/.claude/rules/claude-api.md |
| Django URL routing | user-general | cross-project-domain | Route to ~/.claude/rules/django.md |
| Project IPs/ports | user-general | project | Route to project/CLAUDE.md |
| Universal practices | project | user-general | Route to ~/.claude/CLAUDE.md |

## Domain Detection Keywords

| Domain | Keywords |
|--------|----------|
| api | endpoint, REST, GraphQL, view, route, URL, HTTP |
| architecture | pattern, module, layer, dependency, coupling |
| testing | test, pytest, vitest, playwright, mock, E2E |
| infrastructure | docker, SSH, port, Redis, Zimbra, deploy |
| realtime | socket, emit, broadcast, event, websocket |
| security | auth, token, JWT, XSS, injection, sanitize |
| frontend | React, component, state, UI, CSS, hook |
| backend | Django, model, migration, Celery, queryset |

## Cross-Project Domain Files

| Framework | File |
|-----------|------|
| Claude/Anthropic API | `~/.claude/rules/claude-api.md` |
| Django | `~/.claude/rules/django.md` |
| React | `~/.claude/rules/react.md` |
| Flask | `~/.claude/rules/flask.md` |
| PostgreSQL | `~/.claude/rules/postgresql.md` |

## Usage

This skill is automatically invoked by:
- `model-evaluator` agent during Phase 1 (initial classification)
- `critics-reviewer` agent during Phase 2 (validation)

Manual invocation:
```
/rules-learning-pipeline:scope-classification <lesson-text>
```

## Output Format

```markdown
## Scope Classification

Lesson: "Claude API requires messages array format"

### Analysis
- Universal applicability: YES (any project can use Claude API)
- Framework-specific: YES (Claude/Anthropic API)
- Project-specific: NO

### Classification
- **Scope**: cross-project-domain
- **Route**: ~/.claude/rules/claude-api.md
- **Confidence**: HIGH

### Rationale
This is framework-specific knowledge (Claude API) that applies to ANY project using the Claude API, not just this project. Therefore it belongs in the cross-project-domain scope.
```
