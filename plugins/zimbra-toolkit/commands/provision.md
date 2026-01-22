---
description: Guide through user or domain provisioning
allowed-tools: Bash, AskUserQuestion
argument-hint: [user|domain] [name]
---

Guide the user through Zimbra account or domain provisioning.

## Determine Provisioning Type

If $1 is "user" or "domain", use that type.
Otherwise, ask:

What would you like to provision?
- User account (mailbox)
- Domain

## User Provisioning

If provisioning a user:

### 1. Gather Information

Ask for the following (use AskUserQuestion for choices):

**Required:**
- Email address (user@domain.com format)
- Initial password (or generate one)

**Optional:**
- Display name
- First name (givenName)
- Last name (sn)
- Class of Service (COS)
- Quota (in GB)

### 2. Validate Domain

Before creating user, verify domain exists:
```bash
zmprov gd <domain>
```

If domain doesn't exist, offer to create it first.

### 3. List Available COS

Show available COS options:
```bash
zmprov gac
```

### 4. Create Account

Build and execute zmprov command:

```bash
zmprov ca user@domain.com 'password' \
  displayName 'Display Name' \
  givenName 'First' \
  sn 'Last' \
  zimbraCOSid <cos-id> \
  zimbraMailQuota <bytes>
```

### 5. Verify Creation

Confirm account was created:
```bash
zmprov ga user@domain.com | head -20
```

### 6. Provide Login Details

Show user:
- Email address
- Temporary password
- Webmail URL: https://<hostname>/
- Recommendation to change password on first login

## Domain Provisioning

If provisioning a domain:

### 1. Gather Information

**Required:**
- Domain name

**Optional:**
- Public service hostname
- Default COS for new accounts
- Domain quota (total storage)

### 2. Check Domain Doesn't Exist

```bash
zmprov gd <domain>
```

If exists, inform user and ask what to do.

### 3. Create Domain

```bash
zmprov cd domain.com \
  zimbraPublicServiceHostname mail.domain.com \
  zimbraPublicServiceProtocol https \
  zimbraPublicServicePort 443
```

### 4. Configure DNS (Guidance)

Provide DNS records needed:

```
MX record: domain.com -> mail.domain.com (priority 10)
A record: mail.domain.com -> <server-ip>
SPF: v=spf1 mx -all
```

### 5. Set Default COS (Optional)

If user wants default COS:
```bash
zmprov md domain.com zimbraDomainDefaultCOSId <cos-id>
```

### 6. Verify Creation

```bash
zmprov gd domain.com
```

## Output

After successful provisioning, provide summary:

```
=== Provisioning Complete ===

Type: [User/Domain]
Name: [email/domain]
Created: [timestamp]

Details:
  [Key details about what was created]

Next Steps:
  1. [What user should do next]
  2. [Any configuration needed]
```
