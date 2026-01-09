---
name: critics-review
description: Review lessons for accuracy and completeness (Phase 2 only)
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

# Critics Review

Run Phase 2 of the learning pipeline - validate lessons and catch missed opportunities.

## Usage

```
/rules-learning-pipeline:critics-review <lessons-file> [--strict]
```

## What It Does

1. Validate scope classifications using decision matrix
2. Check lesson specificity (score ≥ 2 required)
3. Detect missed wasteful patterns:
   - BDN (Broad-Dismiss-Narrow)
   - CIP (Check-Ignore-Proceed)
   - Verification Theater
   - Redundant Tool Chains
4. Flag unflagged dismissive language
5. Verify cross-project-domain patterns detected
6. Return verdict: APPROVED | NEEDS_REVISION | REJECTED

## Execution

```
Task(
  subagent_type: "critics-reviewer",
  prompt: "Review lessons at {lessons_file}:

    1. AUDIT scope classifications
       - Apply validation matrix
       - Check for cross-project-domain patterns

    2. VALIDATE specificity
       - Score each lesson (file, format, MUST/NEVER, error ref)
       - Reject lessons scoring < 2

    3. DETECT missed wasteful patterns
       - Scan for BDN, CIP, Verification Theater
       - Flag redundant tool chains

    4. AUDIT dismissive language
       - 'pre-existing' → critical issue
       - 'not related to my changes' → critical issue
       - 'already there' → warning

    5. GENERATE verdict
       - APPROVED: 0 critical, ≤2 minor
       - NEEDS_REVISION: 1-3 critical OR >2 minor
       - REJECTED: >3 critical

    Output to:
    - docs/evaluations/{session}-critics.md
    - docs/evaluations/{session}-lessons-validated.md"
)
```

## Verdict Criteria

| Verdict | Criteria |
|---------|----------|
| APPROVED | 0 critical issues, ≤2 minor issues |
| NEEDS_REVISION | 1-3 critical issues OR >2 minor issues |
| REJECTED | >3 critical issues OR fundamental scope errors |

## Critical Issues

- Scope misclassification affecting routing
- Specificity score of 0
- Missed critical pattern (caused visible error)
- Undetected wasteful pattern
- Unflagged dismissive language
