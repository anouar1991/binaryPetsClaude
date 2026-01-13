---
name: user-correction-detection
description: Detect patterns where users repeatedly correct the model or provide explicit information that gets ignored
---

# User Correction Detection Skill

Identifies anti-patterns where models ignore, misuse, or require repeated user corrections for explicit information.

## Patterns Detected

### 1. User Correction Pattern (UCP)

**Pattern**: User provides explicit info → model uses wrong value → user corrects → model may still fail

```
Example sequence:
1. User: "SSH to 172.17.0.4"
2. Model: Bash(ssh 172.17.0.5)       # Wrong IP
3. User: "No, the IP is 172.17.0.4"
4. Model: Bash(ssh 172.17.0.4)       # Finally correct

Detection indicators:
- User message contains explicit value (IP, port, password, path)
- Model action uses different value
- User repeats/corrects with same or emphasized value
```

**Severity**: Critical (1 correction) → Severe (2+ corrections)

**Lesson**: "MUST use exact values provided by user for {category}"

---

### 2. Ignored Explicit Instruction (IEI)

**Pattern**: User gives explicit instruction → model does something different

```
Example sequence:
1. User: "Use port 2525 for the content filter"
2. Model: Edit(main.cf, "content_filter = smtp:127.0.0.1:10025")  # Wrong port!
3. [No immediate user correction - error discovered later]

Detection indicators:
- User message contains imperative + specific value
- Model action doesn't use that value
- Value is extractable (number, IP, path, name)
```

**Severity**: Critical

**Lesson**: "MUST extract and use explicit values from user instructions before acting"

---

### 3. Repeated Instruction Pattern (RIP)

**Pattern**: User repeats the same instruction multiple times

```
Example sequence:
1. User: "Run the tests"
2. Model: [does something else]
3. User: "Please run the tests"
4. Model: [still doesn't run tests]
5. User: "I said run the tests!"

Detection indicators:
- Same semantic instruction appears 2+ times
- Model actions between don't address the instruction
- User may show frustration markers (!, caps, "I said")
```

**Severity**: Warning (2x) → Critical (3x+)

**Lesson**: "MUST address user's explicit request before proceeding with other actions"

---

### 4. Critical Info Amnesia (CIA)

**Pattern**: User provides critical info early → model forgets/ignores it later

```
Example sequence:
1. User: "The database password is 'secret123'"
2. [... 10 turns later ...]
3. Model: Bash(psql -U admin -W)     # Prompts for password instead of using it
4. User: "I already told you the password is secret123"

Detection indicators:
- Critical info provided (credentials, IPs, ports, paths)
- Later action requires that info
- Model doesn't use the provided value
- User reminds model of previously provided info
```

**Severity**: Critical

**Lesson**: "MUST track and reuse critical information (credentials, IPs, ports) provided earlier in session"

---

### 5. Value Substitution Error (VSE)

**Pattern**: Model substitutes user's explicit value with a "better" or default one

```
Example sequence:
1. User: "Connect to Redis on port 6380"
2. Model: Bash(redis-cli -p 6379)    # Used default instead of user's port
3. User: "I said 6380, not 6379"

Detection indicators:
- User provides non-default value
- Model uses common default instead
- Values are similar but different (6379 vs 6380, localhost vs 127.0.0.1)
```

**Severity**: Critical

**Lesson**: "NEVER substitute user-provided values with defaults - user's explicit values override conventions"

---

## Detection Algorithm

```python
FOR each user message in session:

    # Step 1: Extract explicit values
    explicit_values = extract_values(user_message)
    # Values: IPs, ports, passwords, paths, URLs, names, commands

    FOR each value in explicit_values:

        # Step 2: Track in session context
        session_context.add(category=value.type, value=value.text, turn=current_turn)

        # Step 3: Check subsequent model actions
        FOR each model_action in actions_after(current_turn):

            # Check if action should use this value
            IF action_relates_to(model_action, value.type):

                # Check if correct value was used
                IF NOT action_uses_value(model_action, value.text):

                    # Pattern detected!
                    IF similar_value_used(model_action, value):
                        flag(VSE, value, model_action)  # Substitution
                    ELSE:
                        flag(IEI, value, model_action)  # Ignored

        # Step 4: Check for user corrections
        FOR each later_user_message in messages_after(current_turn):
            IF contains_correction(later_user_message, value):
                flag(UCP, value, correction_count)

        # Step 5: Check for reminder patterns
        FOR each later_user_message in messages_after(current_turn + 5):
            IF user_reminds_of(later_user_message, value):
                flag(CIA, value, turns_elapsed)
```

## Value Extraction Patterns

| Category | Regex Pattern | Examples |
|----------|---------------|----------|
| IP Address | `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b` | 172.17.0.4, 192.168.1.1 |
| Port | `port\s*:?\s*(\d{2,5})\b` or `:\d{2,5}\b` | port 2525, :8080 |
| Path | `[/~][\w./-]+` or `\b\w+/\w+[/\w.]*` | /etc/postfix, src/components |
| Password/Secret | `password\s*(is\|:)?\s*['"]?(\S+)` | password is 'secret123' |
| URL | `https?://\S+` | https://api.example.com |
| Command | `run\s+['"\`]?(\S+)` or backtick commands | run `npm test` |
| Filename | `\b[\w-]+\.(py\|js\|ts\|md\|json\|yaml)\b` | config.json, app.py |

## Frustration Markers

Detect user frustration to escalate severity:

| Marker | Pattern | Severity Multiplier |
|--------|---------|---------------------|
| Exclamation | `!` at end of sentence | 1.5x |
| Caps emphasis | `[A-Z]{3,}` words | 1.5x |
| "I said/told you" | `I (said\|told you\|already)` | 2x |
| Repetition with "again" | `again` in correction | 2x |
| Exasperation | `please just`, `simply` | 1.5x |

## Output Format

```markdown
## User Correction Patterns Detected

### Pattern Summary

| Pattern | Count | Severity | Turns |
|---------|-------|----------|-------|
| UCP (User Correction) | 3 | Critical | 5,12,18 |
| IEI (Ignored Instruction) | 1 | Critical | 8 |
| CIA (Info Amnesia) | 1 | Critical | 22 |

---

### Instance #1: User Correction Pattern (UCP)

**Turn 5-7:**
```
User: "SSH to 172.17.0.4"
Model: Bash(ssh 172.17.0.5)
User: "No, it's 172.17.0.4"
```

**Category**: IP Address
**User Value**: 172.17.0.4
**Model Used**: 172.17.0.5
**Corrections Required**: 1
**Frustration Markers**: None

**Lesson Generated**:
```
MUST use exact IP addresses provided by user - never substitute or mistype
```

---

### Instance #2: Ignored Explicit Instruction (IEI)

**Turn 8:**
```
User: "Use port 2525 for the filter"
Model: Edit(main.cf, "content_filter = smtp:127.0.0.1:10025")
```

**Category**: Port
**User Value**: 2525
**Model Used**: 10025
**Pattern**: Value Substitution (used different port entirely)

**Lesson Generated**:
```
MUST extract port numbers from user instructions and use exactly as specified
```

---

## Lessons Required

| # | Lesson | Scope | Source Pattern |
|---|--------|-------|----------------|
| 1 | "MUST use exact IP addresses provided by user" | user-general | UCP |
| 2 | "MUST extract and use port numbers from user instructions" | user-general | IEI |
| 3 | "MUST track credentials provided earlier in session" | user-general | CIA |
```

## Severity Classification

| Pattern | 1st Occurrence | 2nd Occurrence | 3rd+ Occurrence |
|---------|----------------|----------------|-----------------|
| UCP | Warning | Critical | Severe |
| IEI | Critical | Severe | Severe |
| RIP | Warning | Critical | Severe |
| CIA | Critical | Severe | Severe |
| VSE | Critical | Severe | Severe |

## Integration

This skill is automatically invoked by:
- `model-evaluator` agent during Phase 1 (detection)
- `critics-reviewer` agent during Phase 2 (validation)

Manual invocation:
```
/rules-learning-pipeline:user-correction-detection <session-file>
```

## Lesson Templates

### UCP Lesson Template
```
MUST use exact {category} values provided by user - never substitute, mistype, or use defaults
Source: User had to correct {category} {correction_count} time(s) in session
```

### IEI Lesson Template
```
MUST extract {category} from user instructions BEFORE taking action
Source: User explicitly provided {value} but model used {wrong_value}
```

### RIP Lesson Template
```
MUST address user's explicit request immediately - do not proceed with unrelated actions
Source: User repeated instruction {count} times before model complied
```

### CIA Lesson Template
```
MUST maintain session memory for critical info ({category}) - reference earlier turns when needed
Source: User provided {category} in turn {turn}, model forgot by turn {later_turn}
```

### VSE Lesson Template
```
NEVER override user-specified {category} with defaults - explicit values take precedence
Source: User specified {user_value}, model substituted {default_value}
```
