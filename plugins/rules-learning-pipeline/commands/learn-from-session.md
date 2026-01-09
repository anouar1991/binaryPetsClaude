---
name: learn-from-session
description: Full learning pipeline - evaluate session, extract lessons, optimize rules
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

# Learn From Session

Orchestrates the complete learning pipeline to extract lessons from model sessions and optimize CLAUDE.md rules.

## Usage

```
/rules-learning-pipeline:learn-from-session <session-file> [--dry-run] [--verbose]
```

## Pipeline Phases

1. **Phase 1: Evaluate** (model-evaluator)
   - Parse action sequences
   - Calculate metrics (F1, Precision, Recall)
   - Detect wasteful patterns (BDN, CIP, Verification Theater)
   - Extract lessons with scope classification

2. **Phase 2: Review** (critics-reviewer)
   - Validate scope classifications
   - Check lesson specificity (score ≥ 2)
   - Flag missed opportunities
   - Return verdict: APPROVED | NEEDS_REVISION | REJECTED

3. **Phase 3: Optimize** (prompt-optimizer)
   - Route lessons by scope
   - Apply peripheral bias
   - Create domain files if threshold met
   - Write optimized rules

4. **Phase 4: Report**
   - Generate summary report
   - Update changelog

## Execution

When invoked, perform these steps:

### Step 1: Validate Input
```
1. Verify input file exists
2. Check file has content
3. Detect input type (session_log | trajectory | failure)
4. Create checkpoint directory
```

### Step 2: Run Phase 1
```
Task(
  subagent_type: "model-evaluator",
  prompt: "Evaluate session at {input_file}:
    1. Parse gold vs predicted actions
    2. Calculate metrics
    3. Identify error types including wasteful patterns
    4. Extract lessons with specificity validation
    5. Detect dismissive language patterns
    Output to: docs/evaluations/{session}-evaluation.md"
)
```

### Step 3: Run Phase 2
```
Task(
  subagent_type: "critics-reviewer",
  prompt: "Review lessons at {lessons-raw.md}:
    1. Validate scope classifications
    2. Check lesson specificity
    3. Detect missed wasteful patterns
    4. Flag dismissive language not caught
    Output to: docs/evaluations/{session}-critics.md"
)

IF verdict == "REJECTED" AND retry_count < 2:
  Re-run Phase 1 with feedback
```

### Step 4: Run Phase 3
```
Task(
  subagent_type: "prompt-optimizer",
  prompt: "Optimize lessons at {lessons-validated.md}:
    1. Route by scope (user-general, project, domain)
    2. Apply peripheral bias
    3. Enforce line limits
    Output to: docs/evaluations/{session}-optimized.md"
)
```

### Step 5: Generate Report
```
1. Write updated rule files (unless --dry-run)
2. Update router index
3. Add changelog entries
4. Generate summary report
```

## Output Files

| Phase | Output | Consumed By |
|-------|--------|-------------|
| 1 | `{session}-evaluation.md` | Phase 2 |
| 1 | `{session}-lessons-raw.md` | Phase 2 |
| 2 | `{session}-critics.md` | Phase 3 |
| 2 | `{session}-lessons-validated.md` | Phase 3 |
| 3 | `{session}-optimized.md` | Phase 4 |
| 4 | `{session}-summary.md` | User |

## Wasteful Patterns Detected

- **BDN** (Broad-Dismiss-Narrow): Full check → dismiss → narrow check
- **CIP** (Check-Ignore-Proceed): Errors found → no action → next task
- **Verification Theater**: "let me verify" → errors → "looks good"
- **Redundant Tool Chains**: Multiple tools when one suffices
