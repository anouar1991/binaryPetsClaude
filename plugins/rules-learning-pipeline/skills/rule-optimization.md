---
name: rule-optimization
description: Optimize rules following Anthropic best practices for CLAUDE.md
---

# Rule Optimization Skill

Transforms lessons into optimized rules following Anthropic's official best practices.

## Anthropic Best Practices

### 1. Length Constraints

| Limit | Value | Severity |
|-------|-------|----------|
| Ideal | < 60 lines | Target |
| Maximum | < 300 lines | ERROR if exceeded |

**Rationale**: Instruction-following quality decreases uniformly as instruction count increases.

### 2. Peripheral Bias

LLMs bias towards instructions at the START and END of prompts.

```
CLAUDE.md Structure:
┌──────────────────────────────┐
│  CRITICAL rules (start)      │  ← Highest attention
├──────────────────────────────┤
│  Standard rules (middle)     │  ← Lower attention
├──────────────────────────────┤
│  CRITICAL rules (end)        │  ← High attention
└──────────────────────────────┘
```

### 3. Emphasis Keywords

| Keyword | Usage | Example |
|---------|-------|---------|
| MUST | Required action | "MUST trace URL routing first" |
| NEVER | Prohibited action | "NEVER assume view from name" |
| CRITICAL | Highest priority | "CRITICAL: Verify before modify" |
| IMPORTANT | High priority | "IMPORTANT: Test after changes" |
| ALWAYS | Consistent requirement | "ALWAYS read before editing" |

### 4. Specificity Requirements

| BAD | GOOD |
|-----|------|
| "Be careful with code" | "MUST trace URL routing before modifying any view class" |
| "Test things" | "MUST verify /health returns 200 before testing API" |
| "Update config" | "MUST copy .env.example to .env and set API_KEY" |

### 5. Prohibited Content

- NO code style rules (defer to linters)
- NO vague language ("try to", "consider", "be careful")
- NO duplicate rules
- NO project-specific rules in user-general scope

## Rule Transformation Patterns

| Lesson Type | Rule Pattern |
|-------------|--------------|
| Wrong assumption | `NEVER assume X without verifying Y` |
| Missing step | `MUST do X before Y` |
| Inconsistency | `Use consistent X across Y` |
| Duplication | `Single source of truth for X` |
| Untested code | `Test X immediately after Y` |
| Wasteful pattern | `MUST scope X to match Y` |

## Specificity Scoring

Each rule MUST score ≥ 2:

| Criterion | +1 Point | Example |
|-----------|----------|---------|
| Specific file/path | ✓ | "proxy-server/.env.example" |
| Specific format/syntax | ✓ | `{"messages": [{role, content}]}` |
| Uses MUST/NEVER/ALWAYS | ✓ | "MUST wait for server" |
| References detectable error | ✓ | "400 error", "timeout" |

## Route Expansion Thresholds

| Condition | Threshold | Action |
|-----------|-----------|--------|
| Critical pattern | ≥ 1 rule | CREATE immediately |
| Standard pattern | ≥ 3 rules | CREATE domain file |
| Below threshold | < 3 rules | Add to pending section |

**Critical patterns**:
- Caused visible error
- API format/protocol
- Security-related
- Data loss prevention

## File Template

```markdown
# {Domain} Rules

## CRITICAL

### 1. {Most important rule}
- {Specific instruction}

## Standards

### 2. {Standard rule}
- {Details}

## Quick Reference

| Mistake | Prevention |
|---------|------------|
| {mistake} | {prevention} |

## REMEMBER

{Critical reminder - peripheral bias}

---
## Changelog
- **{date}**: {changes}
```

## Usage

This skill is automatically invoked by:
- `prompt-optimizer` agent during Phase 3

Manual invocation:
```
/rules-learning-pipeline:rule-optimization <rule-text>
```

## Output Format

```markdown
## Rule Optimization

### Input
"Installation includes config copy"

### Analysis
- Specificity score: 1 (FAIL)
- Missing: specific file, actionable verb
- Has: general concept reference

### Optimized Rule
"MUST copy proxy-server/.env.example to .env and set CLAUDE_API_KEY before running"

### Scoring
- Specific file: +1 (proxy-server/.env.example)
- Uses MUST: +1
- Clear action: +1
- **Total: 3** ✓

### Placement
- Position: START (critical pattern)
- Emphasis: MUST
- Domain: infrastructure
```
