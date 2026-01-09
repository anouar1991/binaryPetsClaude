---
name: evaluate-model
description: Evaluate a model session and extract lessons (Phase 1 only)
allowed-tools: Read, Write, Edit, Grep, Glob, Task
---

# Evaluate Model

Run Phase 1 of the learning pipeline - evaluate session and extract lessons.

## Usage

```
/rules-learning-pipeline:evaluate-model <session-file> [--verbose]
```

## What It Does

1. Parse action sequences (gold vs predicted)
2. Calculate metrics: Success Match, F1, Precision, Recall
3. Identify error types:
   - Standard: Skipped Step, Wrong Order, Wrong Target, Hallucinated Action
   - Wasteful: BDN, CIP, Verification Theater, Redundant Tool Chains
4. Detect dismissive language patterns
5. Extract lessons with:
   - Specificity score validation (≥ 2)
   - Scope classification
   - Domain keywords

## Execution

```
Task(
  subagent_type: "model-evaluator",
  prompt: "Evaluate session at {input_file}:

    1. PARSE action sequences
    2. CALCULATE metrics (F1, Precision, Recall)
    3. IDENTIFY error types including:
       - Wasteful Verification (broad → dismiss → narrow)
       - Dismissive Reasoning (pre-existing, not related)
       - Redundant Tool Calls
       - Scope Mismatch
    4. EXTRACT lessons with specificity validation
    5. CLASSIFY scope for each lesson

    Output to:
    - docs/evaluations/{session}-evaluation.md
    - docs/evaluations/{session}-lessons-raw.md"
)
```

## Output

- `docs/evaluations/{session}-evaluation.md` - Full metrics and error analysis
- `docs/evaluations/{session}-lessons-raw.md` - Extracted lessons with scopes
