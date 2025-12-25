# Secrets Management Guide

Comprehensive guide for managing secrets in the observability stack.

## Table of Contents

1. [Overview](#overview)
2. [Security Architecture](#security-architecture)
3. [Quick Start](#quick-start)
4. [Secret Storage Options](#secret-storage-options)
5. [Migration from Plaintext](#migration-from-plaintext)
6. [Secret Rotation](#secret-rotation)
7. [Backup and Recovery](#backup-and-recovery)
8. [Troubleshooting](#troubleshooting)
9. [Security Best Practices](#security-best-practices)

## Overview

The observability stack implements defense-in-depth secrets management with multiple security layers:

- **File System Isolation**: Secrets stored in gitignored directory with strict permissions (600)
- **Optional Encryption**: Age/GPG encryption at rest for additional security
- **systemd Integration**: Native systemd credentials support for Debian 13+
- **Environment Override**: CI/CD-friendly environment variable support
- **Secure Transmission**: Secrets never passed as command-line arguments
- **Input Validation**: Automatic detection of placeholder and weak passwords

### Threat Model

This system protects against:

1. **Source Code Exposure**: Secrets never committed to git
2. **Process Inspection**: Passwords not visible in process arguments
3. **Unauthorized File Access**: 600 permissions limit access to root only
4. **Backup Leakage**: Encrypted backups prevent credential exposure
5. **Weak Credentials**: Automatic validation prevents default passwords

## Security Architecture

### Defense Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Git Exclusion (.gitignore)                         │
│          Prevents accidental commits                         │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: File Permissions (600, root:root)                  │
│          Restricts OS-level access                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: Optional Encryption (age/gpg)                      │
│          Protects secrets at rest                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 4: systemd Credentials (Debian 13+)                   │
│          Service-isolated encrypted credentials              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 5: Secure Transmission                                │
│          stdin-only password passing to commands             │
└─────────────────────────────────────────────────────────────┘
```

### Secret Resolution Order

When a script needs a secret, it tries these sources in order:

1. **Environment Variable**: `OBSERVABILITY_SECRET_<NAME>`
   - Highest priority
   - Useful for CI/CD pipelines
   - Example: `OBSERVABILITY_SECRET_SMTP_PASSWORD`

2. **Plaintext File**: `secrets/<name>`
   - Standard storage location
   - Must have 600 permissions
   - Validated before use

3. **Encrypted File (age)**: `secrets/<name>.age`
   - Requires age private key
   - Default key location: `~/.config/age/key.txt`

4. **Encrypted File (gpg)**: `secrets/<name>.gpg`
   - Requires GPG private key
   - Uses system GPG keyring

## Quick Start

### 1. Generate Secrets

```bash
cd /home/calounx/repositories/mentat/observability-stack

# Generate all required secrets
sudo ./scripts/init-secrets.sh

# Or with encryption
sudo ./scripts/init-secrets.sh --encrypt-age --age-recipient ~/.config/age/pubkey.txt
```

This creates:
- `secrets/smtp_password` (32 chars, random)
- `secrets/grafana_admin_password` (32 chars, random)
- `secrets/prometheus_basic_auth_password` (32 chars, random)
- `secrets/loki_basic_auth_password` (32 chars, random)

All files are created with 600 permissions, owned by root.

### 2. Configure global.yaml

Use the template with secret references:

```bash
# Copy template
cp config/global.yaml.template config/global.yaml

# Edit non-sensitive values
vim config/global.yaml
```

Secret references are automatically resolved:

```yaml
smtp:
  password: ${SECRET:smtp_password}  # Automatically resolved at runtime

grafana:
  admin_password: ${SECRET:grafana_admin_password}
```

### 3. Run Setup

The setup scripts automatically resolve secrets:

```bash
sudo ./scripts/setup-observability.sh
```

## Secret Storage Options

### Option 1: Plaintext Files (Default)

**Use Case**: Single administrator, encrypted disk

```bash
sudo ./scripts/init-secrets.sh
```

**Pros**:
- Simple, no additional tools needed
- Fast resolution
- Works everywhere

**Cons**:
- Secrets visible to root
- Relies on OS permissions only

**Security Requirements**:
- Full disk encryption (LUKS recommended)
- Strict access controls
- Regular permission audits

### Option 2: age Encryption

**Use Case**: Multiple administrators, shared systems, backup encryption

```bash
# Generate age key (once)
age-keygen -o ~/.config/age/key.txt
age-keygen -y ~/.config/age/key.txt > ~/.config/age/pubkey.txt

# Generate and encrypt secrets
sudo ./scripts/init-secrets.sh --encrypt-age --age-recipient ~/.config/age/pubkey.txt
```

**Pros**:
- Modern encryption (ChaCha20-Poly1305)
- Simple key management
- Fast encryption/decryption

**Cons**:
- Requires age installation
- Key must be available for decryption

**Key Management**:
```bash
# Backup keys securely
gpg --encrypt --recipient admin@example.com ~/.config/age/key.txt

# Distribute public key to team
cat ~/.config/age/pubkey.txt
```

### Option 3: GPG Encryption

**Use Case**: Existing GPG infrastructure, multiple recipients

```bash
# Generate secrets with GPG
sudo ./scripts/init-secrets.sh --encrypt-gpg --gpg-recipient admin@example.com
```

**Pros**:
- Uses existing GPG keys
- Support for multiple recipients
- Web of trust model

**Cons**:
- More complex key management
- Slower than age
- GPG agent required

### Option 4: systemd Credentials (Debian 13+)

**Use Case**: Production systems, TPM2 hardware encryption

```bash
# Check support
sudo ./scripts/systemd-credentials.sh check

# Encrypt all secrets
sudo ./scripts/systemd-credentials.sh encrypt-all

# List encrypted credentials
sudo ./scripts/systemd-credentials.sh list
```

**Pros**:
- Native systemd integration
- TPM2 hardware encryption
- Service-isolated credentials
- Credentials in tmpfs only (never on disk after encryption)

**Cons**:
- Requires systemd 255+ (Debian 13+)
- Requires service file modifications

**Service Integration**:
```ini
[Service]
LoadCredential=smtp-password:/etc/credstore.encrypted/smtp_password.cred
ExecStart=/usr/bin/alertmanager --smtp-password-file=${CREDENTIALS_DIRECTORY}/smtp-password
```

## Migration from Plaintext

### Step 1: Audit Current Credentials

```bash
# Find all plaintext passwords in configs
cd /home/calounx/repositories/mentat/observability-stack
grep -r "password.*=" config/ --include="*.yaml" | grep -v SECRET:
```

### Step 2: Extract to Secrets

Create a migration helper:

```bash
# Create migration script
cat > migrate-secrets.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Extract SMTP password from global.yaml
smtp_pass=$(grep -A5 "smtp:" config/global.yaml | grep "password:" | awk '{print $2}' | tr -d '"')
echo -n "$smtp_pass" > secrets/smtp_password
chmod 600 secrets/smtp_password

# Extract Grafana password
grafana_pass=$(grep -A5 "grafana:" config/global.yaml | grep "admin_password:" | awk '{print $2}' | tr -d '"')
echo -n "$grafana_pass" > secrets/grafana_admin_password
chmod 600 secrets/grafana_admin_password

# Extract Prometheus password
prom_pass=$(grep -A5 "security:" config/global.yaml | grep "prometheus_basic_auth_password:" | awk '{print $2}' | tr -d '"')
echo -n "$prom_pass" > secrets/prometheus_basic_auth_password
chmod 600 secrets/prometheus_basic_auth_password

# Extract Loki password
loki_pass=$(grep -A5 "security:" config/global.yaml | grep "loki_basic_auth_password:" | awk '{print $2}' | tr -d '"')
echo -n "$loki_pass" > secrets/loki_basic_auth_password
chmod 600 secrets/loki_basic_auth_password

echo "Secrets extracted successfully"
EOF

chmod +x migrate-secrets.sh
sudo ./migrate-secrets.sh
```

### Step 3: Update global.yaml

```bash
# Backup current config
cp config/global.yaml config/global.yaml.backup

# Update to use secret references
sed -i 's/password: "[^"]*"$/password: ${SECRET:smtp_password}/' config/global.yaml
sed -i 's/admin_password: "[^"]*"$/admin_password: ${SECRET:grafana_admin_password}/' config/global.yaml
sed -i 's/prometheus_basic_auth_password: "[^"]*"$/prometheus_basic_auth_password: ${SECRET:prometheus_basic_auth_password}/' config/global.yaml
sed -i 's/loki_basic_auth_password: "[^"]*"$/loki_basic_auth_password: ${SECRET:loki_basic_auth_password}/' config/global.yaml
```

### Step 4: Verify

```bash
# Test secret resolution
source scripts/lib/common.sh

# Verify each secret
for secret in smtp_password grafana_admin_password prometheus_basic_auth_password loki_basic_auth_password; do
    echo -n "Testing $secret: "
    if resolve_secret "$secret" true > /dev/null; then
        echo "OK"
    else
        echo "FAILED"
    fi
done
```

### Step 5: Deploy

```bash
# Run setup with new secrets
sudo ./scripts/setup-observability.sh
```

## Secret Rotation

### Why Rotate Secrets?

- **Security Policy**: Many policies require 90-day rotation
- **Suspected Compromise**: Rotate immediately if breach suspected
- **Personnel Changes**: Rotate when administrators leave
- **Compliance**: Meet regulatory requirements

### Rotation Procedure

#### 1. Grafana Admin Password

```bash
# Generate new password
new_pass=$(openssl rand -base64 32 | tr -d '/+=')

# Update secret
echo -n "$new_pass" | sudo tee secrets/grafana_admin_password > /dev/null
sudo chmod 600 secrets/grafana_admin_password

# Update Grafana
sudo grafana-cli admin reset-admin-password "$new_pass"

# Verify login
curl -u "admin:$new_pass" http://localhost:3000/api/health
```

#### 2. SMTP Password

```bash
# Update in Brevo dashboard first, then:
new_smtp_key="your-new-brevo-key"

# Update secret
echo -n "$new_smtp_key" | sudo tee secrets/smtp_password > /dev/null
sudo chmod 600 secrets/smtp_password

# Restart Alertmanager
sudo systemctl restart alertmanager
```

#### 3. HTTP Basic Auth (Prometheus/Loki)

```bash
# Generate new password
new_pass=$(openssl rand -base64 32 | tr -d '/+=')

# Update secret
echo -n "$new_pass" | sudo tee secrets/prometheus_basic_auth_password > /dev/null
sudo chmod 600 secrets/prometheus_basic_auth_password

# Regenerate htpasswd
source scripts/lib/common.sh
create_htpasswd_secure "prometheus" "$new_pass" "/etc/nginx/.htpasswd_prometheus"

# Reload nginx
sudo systemctl reload nginx

# Update monitored hosts (update their Promtail configs)
# ... (see monitored hosts section)
```

### Automated Rotation

Create a rotation reminder:

```bash
# Add to cron for monthly reminder
cat > /etc/cron.monthly/secret-rotation-reminder << 'EOF'
#!/bin/bash
echo "REMINDER: Rotate observability secrets"
echo "Last rotation: $(stat -c %y /home/calounx/repositories/mentat/observability-stack/secrets/smtp_password)"
echo "Run: cd /home/calounx/repositories/mentat/observability-stack && ./scripts/rotate-secrets.sh"
EOF

chmod +x /etc/cron.monthly/secret-rotation-reminder
```

## Backup and Recovery

### Critical Warning

Secrets are **NOT** backed up automatically. You must implement your own backup strategy.

### Backup Strategies

#### Strategy 1: Encrypted Tarball (Recommended)

```bash
# Create encrypted backup
cd /home/calounx/repositories/mentat/observability-stack
tar -czf - secrets/ | \
    gpg --encrypt --recipient admin@example.com \
    -o "observability-secrets-$(date +%Y%m%d).tar.gz.gpg"

# Or with age
tar -czf - secrets/ | \
    age -r $(cat ~/.config/age/pubkey.txt) \
    -o "observability-secrets-$(date +%Y%m%d).tar.gz.age"

# Store in secure location
mv observability-secrets-*.tar.gz.* /secure/backup/location/
```

#### Strategy 2: Password Manager

Use a password manager with team sharing:

1. **1Password**: Create vault "Observability Secrets"
2. **Bitwarden**: Create organization collection
3. **KeePassXC**: Create database with attachments

Store each secret as a separate entry with metadata:
- Secret name
- Purpose
- Last rotation date
- Rotation policy

#### Strategy 3: Hardware Security Module (Enterprise)

For enterprise deployments:

```bash
# Export to HSM (example with YubiKey)
ykman oath accounts add smtp_password "$(cat secrets/smtp_password)"
```

### Recovery Procedure

#### From Encrypted Tarball

```bash
# Decrypt and extract
cd /home/calounx/repositories/mentat/observability-stack

# GPG
gpg --decrypt observability-secrets-20250101.tar.gz.gpg | tar -xzf -

# Age
age -d -i ~/.config/age/key.txt observability-secrets-20250101.tar.gz.age | tar -xzf -

# Fix permissions
sudo chown -R root:root secrets/
sudo chmod 700 secrets/
sudo chmod 600 secrets/*

# Verify
./scripts/init-secrets.sh  # Will skip existing secrets
```

#### From Password Manager

```bash
# Manually recreate each secret
echo -n "your-smtp-password" | sudo tee secrets/smtp_password > /dev/null
echo -n "your-grafana-password" | sudo tee secrets/grafana_admin_password > /dev/null
# ... etc

# Fix permissions
sudo chmod 600 secrets/*
sudo chown root:root secrets/*
```

## Troubleshooting

### Secret not found error

```
[ERROR] Secret not found: smtp_password
```

**Solution**:
```bash
# Check if secret file exists
ls -la secrets/smtp_password

# If missing, create it
echo "your-password" | sudo tee secrets/smtp_password > /dev/null
sudo chmod 600 secrets/smtp_password

# Or regenerate all
sudo ./scripts/init-secrets.sh
```

### Permission denied error

```
[ERROR] Cannot read secret file: Permission denied
```

**Solution**:
```bash
# Fix permissions
sudo chmod 600 secrets/*
sudo chown root:root secrets/*

# Verify
ls -la secrets/
```

### Secret contains placeholder

```
[ERROR] Secret 'smtp_password' contains placeholder value
```

**Solution**:
```bash
# The secret still has CHANGE_ME or similar
cat secrets/smtp_password

# Replace with actual secret
echo "actual-password" | sudo tee secrets/smtp_password > /dev/null
sudo chmod 600 secrets/smtp_password
```

### htpasswd creation fails

```
[ERROR] Failed to create htpasswd entry
```

**Solution**:
```bash
# Install apache2-utils
sudo apt-get install apache2-utils

# Test manually
echo "test-password" | htpasswd -ci /tmp/test.htpasswd testuser

# If still failing, check htpasswd version
htpasswd -v
```

### systemd credentials not supported

```
[ERROR] systemd version 252 is too old
```

**Solution**:
```bash
# This feature requires Debian 13+
cat /etc/debian_version

# If on older Debian, use file-based secrets instead
# systemd credentials are optional
```

## Security Best Practices

### 1. Principle of Least Privilege

- **File Permissions**: Always 600 for secrets, 700 for secrets directory
- **Ownership**: Only root should own secrets
- **Service Users**: Create dedicated users for each service
- **Network Access**: Restrict access with firewall rules

### 2. Defense in Depth

Never rely on a single security layer:

- ✅ File permissions (600)
- ✅ Disk encryption (LUKS)
- ✅ Optional secret encryption (age/gpg)
- ✅ systemd credentials (Debian 13+)
- ✅ Network segmentation
- ✅ Audit logging

### 3. Secret Strength Requirements

All passwords must meet:

- **Minimum Length**: 32 characters
- **Character Variety**: Uppercase, lowercase, numbers, symbols
- **Randomness**: Generated with cryptographic RNG
- **No Patterns**: Avoid dictionary words, keyboard patterns

### 4. Access Auditing

Monitor secret access:

```bash
# Enable audit logging for secrets directory
sudo auditctl -w /home/calounx/repositories/mentat/observability-stack/secrets -p r -k secret_access

# Review access
sudo ausearch -k secret_access
```

### 5. Regular Security Reviews

Monthly checklist:

- [ ] Review secret file permissions
- [ ] Check for placeholder values
- [ ] Verify encryption status
- [ ] Audit access logs
- [ ] Test backup restore
- [ ] Review rotation dates
- [ ] Update documentation

### 6. Incident Response

If secrets are compromised:

1. **Immediate**: Rotate all secrets
2. **Investigate**: Check access logs
3. **Notify**: Inform affected parties
4. **Document**: Record incident details
5. **Improve**: Update security procedures

### 7. Development vs Production

**Never** use production secrets in development:

```bash
# Development: Use separate secret files
export OBSERVABILITY_SECRET_SMTP_PASSWORD="dev-password"

# Production: Use encrypted secrets
sudo ./scripts/systemd-credentials.sh encrypt-all
```

### 8. Secure Communication Channels

When sharing secrets:

- ❌ **Never**: Email, Slack, SMS
- ❌ **Never**: Commit to git
- ❌ **Never**: Include in logs
- ✅ **Use**: Password managers
- ✅ **Use**: Encrypted files
- ✅ **Use**: Secure in-person transfer

### 9. Password Complexity

Use the generator for all secrets:

```bash
# Generate strong password
openssl rand -base64 32 | tr -d '/+='

# Or use the built-in function
source scripts/lib/common.sh
generate_secret 32
```

### 10. Documentation Security

This documentation:

- ✅ Contains no actual secrets
- ✅ Uses placeholders only
- ✅ Teaches secure practices
- ✅ Safe to commit to git

## References

- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [systemd Credentials](https://systemd.io/CREDENTIALS/)
- [age Encryption](https://age-encryption.org/)
- [CIS Benchmark for Secret Management](https://www.cisecurity.org/)
