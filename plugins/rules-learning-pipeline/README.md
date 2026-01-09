# Rules Learning Pipeline

Automated learning pipeline that evaluates model sessions, extracts lessons, detects wasteful patterns, and optimizes CLAUDE.md rules.

## Commands

| Command | Description |
|---------|-------------|
| `/rules-learning-pipeline:learn-from-session` | Full 4-phase pipeline |
| `/rules-learning-pipeline:evaluate-model` | Phase 1: Evaluate session |
| `/rules-learning-pipeline:critics-review` | Phase 2: Validate lessons |
| `/rules-learning-pipeline:optimize-prompts` | Phase 3: Optimize rules |

## Agents

- **model-evaluator** - Parse sessions, calculate metrics, extract lessons
- **critics-reviewer** - Validate scopes, check specificity, catch missed patterns
- **prompt-optimizer** - Route lessons, optimize rules, write files

## Skills

- **wasteful-pattern-detection** - Detect BDN, CIP, Verification Theater
- **scope-classification** - Classify lessons into correct scopes
- **rule-optimization** - Transform lessons into optimized rules

## Wasteful Patterns Detected

| Pattern | Description |
|---------|-------------|
| BDN | Broad check → dismiss → narrow check |
| CIP | Check → ignore errors → proceed |
| Verification Theater | "verify" → errors → "looks good" |
| Redundant Tool Chains | Multiple tools when one suffices |

## License

MIT
