---
description: Export current Zimbra configuration
allowed-tools: Bash, Write
argument-hint: [output-dir]
---

Export Zimbra server configuration for backup or migration purposes.

## Output Location

If $ARGUMENTS is provided, use it as output directory.
Otherwise, use current directory with timestamp: `./zimbra-config-backup-YYYYMMDD-HHMMSS/`

Create the output directory if it doesn't exist.

## Configuration Export

### 1. Server Information

Export server details:
```bash
zmcontrol -v > output/zimbra-version.txt
hostname > output/hostname.txt
```

### 2. Global Configuration

Export global Zimbra settings:
```bash
zmprov gacf > output/global-config.txt
```

### 3. Server Configuration

Export server-specific settings:
```bash
zmprov gs $(hostname) > output/server-config.txt
```

### 4. All Domains

Export all domains and their settings:
```bash
zmprov gad > output/domains-list.txt

# For each domain, export settings
for domain in $(zmprov gad); do
    zmprov gd $domain > output/domain-$domain.txt
done
```

### 5. All COS (Class of Service)

Export COS definitions:
```bash
zmprov gac > output/cos-list.txt

# For each COS, export settings
for cos in $(zmprov gac); do
    zmprov gc "$cos" > output/cos-$cos.txt
done
```

### 6. All Accounts

Export account list with key attributes:
```bash
zmprov -l gaa > output/accounts-list.txt

# Export account details (careful with large deployments)
for account in $(zmprov -l gaa); do
    zmprov ga $account > output/accounts/$account.txt
done 2>/dev/null
```

Note: For large deployments, this may take significant time. Ask user if they want full account export or just the list.

### 7. Distribution Lists

Export distribution lists:
```bash
zmprov gadl > output/dl-list.txt

for dl in $(zmprov gadl); do
    echo "=== $dl ===" >> output/distribution-lists.txt
    zmprov gdl $dl >> output/distribution-lists.txt
    zmprov gdlm $dl >> output/distribution-lists.txt
    echo "" >> output/distribution-lists.txt
done
```

### 8. Postfix Configuration

Export mail transport settings:
```bash
postconf -n > output/postfix-main.txt
postconf -M > output/postfix-master.txt
```

### 9. Local Configuration

Export local server config:
```bash
zmlocalconfig > output/local-config.txt
zmlocalconfig -s > output/local-config-secrets.txt  # Contains passwords
```

**Security Note**: local-config-secrets.txt contains sensitive data. Warn user to secure this file.

### 10. Zimlet Configuration

Export installed zimlets:
```bash
zmzimletctl listZimlets > output/zimlets-list.txt
```

### 11. Certificate Information

Export certificate details (not the private keys):
```bash
zmcertmgr viewdeployedcrt > output/certificates.txt 2>/dev/null || echo "Certificate info not available" > output/certificates.txt
```

## Create Summary File

Write `output/README.md`:

```markdown
# Zimbra Configuration Backup

**Date**: [timestamp]
**Server**: [hostname]
**Version**: [zimbra-version]

## Contents

- `zimbra-version.txt` - Zimbra version
- `global-config.txt` - Global configuration
- `server-config.txt` - Server-specific settings
- `domains-list.txt` - List of domains
- `domain-*.txt` - Individual domain configs
- `cos-list.txt` - List of COS
- `cos-*.txt` - Individual COS configs
- `accounts-list.txt` - List of all accounts
- `accounts/` - Individual account configs
- `distribution-lists.txt` - All DLs with members
- `postfix-*.txt` - Postfix configuration
- `local-config.txt` - Local configuration
- `local-config-secrets.txt` - **SENSITIVE** Passwords
- `zimlets-list.txt` - Installed zimlets
- `certificates.txt` - Certificate information

## Security Warning

`local-config-secrets.txt` contains sensitive passwords.
Store this backup securely and restrict access.

## Restore Notes

To restore configuration, use appropriate zmprov commands:
- Domains: `zmprov cd domain.com [attrs...]`
- COS: `zmprov cc "COS Name" [attrs...]`
- Accounts: `zmprov ca user@domain.com password [attrs...]`
- DLs: `zmprov cdl dl@domain.com` then `zmprov adlm dl@domain.com member@domain.com`
```

## Output

After backup completes:

```
=== Zimbra Configuration Backup Complete ===

Location: [output-directory]
Server: [hostname]
Version: [version]

Exported:
  ✓ Global configuration
  ✓ Server configuration
  ✓ [N] domains
  ✓ [N] COS definitions
  ✓ [N] accounts
  ✓ [N] distribution lists
  ✓ Postfix configuration
  ✓ Local configuration
  ✓ Zimlet list
  ✓ Certificates

Total size: [size]

⚠️  Security Note: local-config-secrets.txt contains passwords.
    Store this backup securely.

Files created:
  [list key files]
```
