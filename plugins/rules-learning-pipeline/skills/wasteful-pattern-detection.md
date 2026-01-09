---
name: wasteful-pattern-detection
description: Detect wasteful workflow patterns and dismissive reasoning in model sessions
---

# Wasteful Pattern Detection Skill

Identifies anti-patterns in model workflows that waste resources or avoid responsibility.

## Patterns Detected

### 1. Broad-Dismiss-Narrow (BDN)

**Pattern**: Run broad check → dismiss results → run narrow check

```
Example sequence:
1. Bash(tsc --noEmit)           # Full project check
2. [errors in multiple files]
3. "These are pre-existing"     # Dismissal
4. Bash(grep "file.tsx" ...)    # Narrow re-check
```

**Detection**:
- Two similar commands with different scope
- Dismissive language between them
- Second command achieves what first should have

**Lesson**: "MUST scope verification to match change scope from the start"

---

### 2. Check-Ignore-Proceed (CIP)

**Pattern**: Run check → see errors → ignore → continue

```
Example sequence:
1. Bash(npm run lint)           # Check runs
2. [10 lint errors shown]       # Errors visible
3. [No fix attempted]           # Ignored
4. [Next task started]          # Proceeded anyway
```

**Detection**:
- Tool returns errors/warnings
- No subsequent action addresses them
- Next action is unrelated

**Lesson**: "MUST address all errors from checks before proceeding"

---

### 3. Verification Theater

**Pattern**: Appear diligent but ignore results

```
Example sequence:
1. "Let me verify this works"   # Stated intent
2. Bash(some-check)             # Check runs
3. [errors returned]            # Problems found
4. "Looks good"                 # False positive claim
```

**Detection**:
- Stated verification intent
- Check returns non-success
- Positive claim despite errors

**Lesson**: "MUST accurately report check results - NEVER claim success when errors exist"

---

### 4. Redundant Tool Chains

**Pattern**: Multiple tools when one suffices

```
Example sequence:
1. Grep("pattern", file)        # Search in file
2. Read(file)                   # Read same file
3. [Same info extracted]        # Redundant
```

**Detection**:
- Sequential tools targeting same resource
- Information from tool N could come from tool N-1
- No new information gained

**Lesson**: "MUST use single appropriate tool - avoid tool chains for single lookups"

---

### 5. Scope Overkill

**Pattern**: Full suite for single file change

```
Example sequence:
1. Edit(single-file.tsx)        # Changed one file
2. Bash(npm test)               # Full test suite
3. [Only cared about 1 test]    # Overkill
```

**Detection**:
- Single file changed
- Full project check run
- Only portion of result relevant

**Lesson**: "MUST scope verification to match change scope"

---

## Dismissive Language Detection

Flag these phrases as responsibility avoidance:

| Phrase | Classification | Action |
|--------|---------------|--------|
| "pre-existing" | Critical | Generate lesson about ownership |
| "not related to my changes" | Critical | Generate lesson about responsibility |
| "already there" | Warning | Flag for review |
| "unrelated issues" | Warning | Flag for review |
| "I only changed X" | Warning | Flag for review |

## Usage

This skill is automatically invoked by:
- `model-evaluator` agent during Phase 1
- `critics-reviewer` agent during Phase 2

Manual invocation:
```
/rules-learning-pipeline:wasteful-pattern-detection <session-file>
```

## Output Format

```markdown
## Wasteful Patterns Detected

| Pattern | Instance | Line | Severity |
|---------|----------|------|----------|
| BDN | "tsc full → pre-existing → tsc file" | 45-52 | Critical |
| CIP | "lint errors → ignored → continued" | 78-85 | Critical |

## Dismissive Language Found

| Phrase | Context | Line |
|--------|---------|------|
| "pre-existing" | After tsc errors | 48 |

## Lessons Required

1. "MUST scope verification to match change scope"
2. "MUST address all errors from checks before proceeding"
```
