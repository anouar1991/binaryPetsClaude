---
description: Diagnose Zimbra services, ports, and common issues
allowed-tools: Bash, Read, Grep
argument-hint: [service|all]
---

Diagnose Zimbra services and identify common issues.

## Target

Service to diagnose: $ARGUMENTS (default: all)

## Diagnostic Steps

### 1. Check Zimbra Version and Status

Run: `zmcontrol -v` to get version
Run: `zmcontrol status` to check all services

### 2. Check Critical Ports

Verify these ports are listening:
- 25 (SMTP)
- 80/443 (HTTP/HTTPS)
- 7071 (Admin)
- 389/636 (LDAP)
- 143/993 (IMAP)
- 110/995 (POP)

Use: `netstat -tlnp | grep -E "(25|80|443|7071|389|636|143|993|110|995)"`

### 3. Check Disk Space

Run: `df -h /opt/zimbra`

Critical if:
- /opt/zimbra > 90% used
- Any partition at 100%

### 4. Check Recent Errors

Scan logs for errors:
- `/opt/zimbra/log/mailbox.log` - Mailbox issues
- `/opt/zimbra/log/zimbra.log` - General issues
- `/var/log/zimbra.log` - System-level issues

Use: `tail -100 /opt/zimbra/log/mailbox.log | grep -i error`

### 5. Check Mail Queue

Run: `mailq | tail -5` to check queue status

Warning if:
- More than 1000 messages queued
- Messages stuck for > 1 hour

### 6. Check LDAP

Run: `ldapsearch -x -H ldap://localhost:389 -b "" -s base` to verify LDAP responds

### 7. Service-Specific Checks

If $ARGUMENTS is specific service:
- **mta**: Check postfix status, content_filter setting
- **mailbox**: Check Java heap, connection pool
- **proxy**: Check nginx config, upstream servers
- **ldap**: Check replication status

## Output Format

Present findings as:

```
=== Zimbra Diagnostic Report ===

Version: [version]
Overall Status: [HEALTHY/WARNING/CRITICAL]

Services:
  ✓ service-name (running)
  ✗ service-name (stopped) - ACTION NEEDED

Ports:
  ✓ 25 (SMTP)
  ✓ 443 (HTTPS)
  ...

Disk:
  /opt/zimbra: XX% used (YY GB free)

Queue:
  Messages: NNN

Issues Found:
  1. [Issue description] - [Suggested fix]
  2. ...

Recommendations:
  1. [Action to take]
  2. ...
```

If critical issues found, prioritize them and provide specific remediation steps.
