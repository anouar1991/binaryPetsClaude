---
name: optimize-prompts
description: Optimize and route lessons to rule files (Phase 3 only)
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

# Optimize Prompts

Run Phase 3 of the learning pipeline - route lessons and optimize rule files.

## Usage

```
/rules-learning-pipeline:optimize-prompts <lessons-file> [--dry-run]
```

## What It Does

1. Route lessons by validated scope:
   - user-general → ~/.claude/CLAUDE.md
   - cross-project-domain → ~/.claude/rules/*.md
   - project → project/CLAUDE.md
   - domain → context/rules/*.md

2. For each target file:
   - Merge with existing rules
   - Remove duplicates
   - Apply peripheral bias (critical at start/end)
   - Add emphasis keywords (MUST, NEVER, CRITICAL)
   - Enforce line limits (< 60 ideal, < 300 max)

3. Route expansion decisions:
   - Critical pattern (≥1 rule) → CREATE immediately
   - Standard pattern (≥3 rules) → CREATE domain file
   - Below threshold → Add to pending section

## Execution

```
Task(
  subagent_type: "prompt-optimizer",
  prompt: "Optimize lessons at {lessons_file}:

    1. GROUP lessons by scope:
       - user-general → ~/.claude/CLAUDE.md
       - cross-project-domain → ~/.claude/rules/{framework}.md
       - project → project/CLAUDE.md
       - domain → context/rules/{domain}.md

    2. FOR each target file:
       - Read existing rules
       - Merge new lessons
       - Remove duplicates
       - Apply peripheral bias
       - Add emphasis (MUST/NEVER/CRITICAL)
       - Verify < 60 lines (warn if exceeded)

    3. ROUTE expansion:
       IF critical pattern → CREATE file immediately
       ELSE IF ≥3 rules → CREATE domain file
       ELSE → Add to pending section

    4. UPDATE router index

    Output to:
    - docs/evaluations/{session}-optimized.md
    - Updated rule files (unless --dry-run)"
)
```

## Anthropic Best Practices Applied

| Practice | Implementation |
|----------|----------------|
| Length < 60 lines | Enforced per file, warn if exceeded |
| Peripheral bias | Critical rules at START and END |
| Emphasis keywords | MUST, NEVER, CRITICAL, ALWAYS |
| Specificity | No vague language allowed |
| No style rules | Defer to linters |

## Output

- `docs/evaluations/{session}-optimized.md` - Optimization report
- Updated `~/.claude/CLAUDE.md` (if user-general rules)
- Updated `project/CLAUDE.md` (if project rules)
- Updated/created `context/rules/*.md` (if domain rules)
