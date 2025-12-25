# Security Quick Start Guide

This guide provides essential security configuration steps for deploying the observability stack.

## Table of Contents
- [Pre-Deployment Security Checklist](#pre-deployment-security-checklist)
- [Credential Management](#credential-management)
- [Verification Steps](#verification-steps)
- [Security Features](#security-features)

---

## Pre-Deployment Security Checklist

### 1. Review Security Audit Report
```bash
cat SECURITY-AUDIT-REPORT.md
```

### 2. Change All Default Passwords

**MySQL Exporter:**
```bash
# Generate strong password (16+ chars, mixed case, numbers, symbols)
MYSQL_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)A1!
echo "Generated password: $MYSQL_PASS"

# Create MySQL user
mysql -u root -p << EOF
CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY '$MYSQL_PASS';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
FLUSH PRIVILEGES;
EOF

# Update config (edit the CHANGE_ME password)
vim /etc/mysqld_exporter/.my.cnf
```

**Loki Authentication (if using):**
```bash
# Store in file (most secure)
mkdir -p /etc/observability/secrets
chmod 700 /etc/observability/secrets

# Generate and store password
openssl rand -base64 32 > /etc/observability/secrets/loki-password
chmod 600 /etc/observability/secrets/loki-password

# Update host config to use file reference
vim config/hosts/your-host.yaml
# Set: loki_password: file:/etc/observability/secrets/loki-password
```

### 3. Scan for Hardcoded Secrets

```bash
# Run automated scanner
source scripts/lib/secrets.sh
scan_for_hardcoded_secrets config/hosts/your-host.yaml
```

### 4. Verify File Permissions

```bash
# Check credential files
ls -la /etc/mysqld_exporter/.my.cnf
# Should show: -rw------- (600)

ls -la /etc/observability/secrets/
# Should show: -rw------- (600) for all files
```

---

## Credential Management

### Using File-Based Secrets (Recommended)

**Host Configuration:**
```yaml
modules:
  mysqld_exporter:
    enabled: true
    config:
      mysql_user: exporter
      mysql_password: file:/etc/observability/secrets/mysql-exporter-password

  promtail:
    enabled: true
    config:
      loki_url: http://observability:3100/loki/api/v1/push
      loki_user: env:LOKI_USER
      loki_password: file:/etc/observability/secrets/loki-password
```

**Creating Secret Files:**
```bash
# Create secret directory
mkdir -p /etc/observability/secrets
chmod 700 /etc/observability/secrets

# Store secret
echo "MySecureP@ssw0rd123!" > /etc/observability/secrets/mysql-exporter-password
chmod 600 /etc/observability/secrets/mysql-exporter-password
```

### Password Requirements

All passwords MUST meet these criteria:
- ✅ Minimum 16 characters
- ✅ Contains uppercase letters
- ✅ Contains lowercase letters
- ✅ Contains numbers
- ✅ Contains special characters
- ❌ No placeholder patterns (CHANGE_ME, YOUR_, EXAMPLE, etc.)

**Test Password Validation:**
```bash
source scripts/lib/common.sh
validate_credentials "exporter" "YourPassword123!" "test"
```

---

## Verification Steps

### 1. Verify Checksum Downloads

```bash
# Test checksum verification
source scripts/lib/common.sh
cd /tmp
download_and_verify \
  "https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz" \
  "test.tar.gz" \
  "https://github.com/prometheus/node_exporter/releases/download/v1.7.0/sha256sums.txt"

# Should show: "SECURITY: Checksum verified successfully"
```

### 2. Verify Systemd Hardening

```bash
# Check security score (lower is better)
systemd-analyze security node_exporter

# Verify specific protections
systemctl show node_exporter | grep -E "Protect|Restrict|Capability|NoNew"

# Expected outputs:
# ProtectSystem=strict
# ProtectHome=yes
# NoNewPrivileges=yes
# CapabilityBoundingSet=
```

### 3. Check Service Status

```bash
# All services should be active
systemctl status node_exporter
systemctl status nginx_exporter
systemctl status mysqld_exporter
systemctl status phpfpm_exporter
systemctl status fail2ban_exporter

# Check for permission errors in logs
journalctl -u node_exporter -n 50
```

### 4. Verify Metrics Endpoints

```bash
# Test each exporter (should return metrics)
curl -sf http://localhost:9100/metrics | grep node_cpu
curl -sf http://localhost:9113/metrics | grep nginx
curl -sf http://localhost:9104/metrics | grep mysql
curl -sf http://localhost:9253/metrics | grep phpfpm
curl -sf http://localhost:9191/metrics | grep fail2ban
```

---

## Security Features

### What's Protected

#### 1. Command Injection Prevention
- ✅ Whitelist-only command execution in module detection
- ✅ Special character filtering (`;`, `|`, `&`, `$`, `` ` ``)
- ✅ No arbitrary code execution

#### 2. Credential Security
- ✅ Automatic placeholder detection and rejection
- ✅ Password complexity enforcement
- ✅ File-based secrets with mode 600
- ✅ Secure temporary file handling
- ✅ Automatic cleanup on exit

#### 3. Binary Integrity
- ✅ SHA256 checksum verification for downloads
- ✅ Cryptographic validation before installation
- ✅ Automatic failure on mismatch

#### 4. System Hardening
- ✅ Systemd security directives on all services:
  - ProtectSystem=strict (read-only filesystem)
  - NoNewPrivileges=true (prevent privilege escalation)
  - CapabilityBoundingSet= (no capabilities)
  - SystemCallFilter (restricted syscalls)
  - RestrictAddressFamilies (network-only)
  - PrivateTmp, ProtectHome, ProtectKernel*, etc.

#### 5. Input Sanitization
- ✅ sed injection prevention
- ✅ YAML injection protection
- ✅ Safe file operations with validation

---

## Troubleshooting Security Issues

### "Credential validation failed"
```bash
# Check password requirements
source scripts/lib/common.sh
validate_credentials "user" "yourpassword" "test"

# View detailed error messages
# Generate compliant password
openssl rand -base64 24 | sed 's/[^a-zA-Z0-9]//g' | head -c 16; echo "A1!"
```

### "Checksum verification FAILED"
```bash
# Network issue or corrupted download
# Verify URL is correct
wget -O /tmp/test.tar.gz "YOUR_URL"
sha256sum /tmp/test.tar.gz

# Compare with published checksums
curl -s "CHECKSUM_URL"
```

### Service won't start after hardening
```bash
# Check for permission errors
journalctl -u SERVICE_NAME -n 100

# Common issues:
# 1. Service needs write access to directory
#    Solution: Add ReadWritePaths=/path/to/dir in service file

# 2. Service needs additional capabilities
#    Solution: Add specific capability to CapabilityBoundingSet

# 3. Service uses system calls not in @system-service
#    Solution: Use strace to identify, add to SystemCallFilter
```

### "SECURITY: User 'X' does not exist"
```bash
# User wasn't created properly
# Re-run module installation
./scripts/setup-monitored-host.sh YOUR_IP --force
```

---

## Security Maintenance

### Regular Tasks

**Weekly:**
- [ ] Review service logs for security events
- [ ] Check for failed authentication attempts

**Monthly:**
- [ ] Scan for new hardcoded secrets
- [ ] Review systemd security scores
- [ ] Verify credential file permissions

**Quarterly:**
- [ ] Rotate all passwords
- [ ] Update to latest module versions
- [ ] Re-run security audit

### Monitoring Security

```bash
# Watch for permission changes
auditctl -w /etc/mysqld_exporter/.my.cnf -p wa -k credential_access
auditctl -w /etc/observability/secrets -p wa -k secret_access

# Monitor failed auth
journalctl -f | grep -i "authentication failed"

# Check for privilege escalation attempts
journalctl | grep -i "operation not permitted"
```

---

## Advanced Security Features

### Future Vault Integration

The system is ready for HashiCorp Vault:

```yaml
# In host config (when vault is configured)
modules:
  mysqld_exporter:
    config:
      mysql_password: vault:secret/data/mysql/exporter
```

**Setup Steps:**
1. Install vault CLI
2. Configure VAULT_ADDR and VAULT_TOKEN
3. Update secret references in configs
4. Secrets will be automatically resolved

### Audit Logging

Enable detailed security logging:

```bash
# Set environment variable
export DEBUG=true

# Run installation
./scripts/setup-monitored-host.sh YOUR_IP

# View security audit trail
grep "SECURITY:" /var/log/syslog
```

---

## Security Contacts

**Report Security Issues:**
- Review: SECURITY-AUDIT-REPORT.md
- Code: See inline SECURITY comments in source files
- Questions: Check scripts/lib/secrets.sh for credential handling

**Security Functions Available:**
```bash
source scripts/lib/common.sh
source scripts/lib/secrets.sh

# Credential validation
validate_credentials "user" "pass" "description"

# Secret resolution
resolve_secret "file:/path/to/secret"

# Secure download
download_and_verify "url" "output" "checksum_url"

# Safe file operations
safe_chown "user:group" "/path"
safe_chmod "600" "/path" "description"

# Hardcoded secret scanning
scan_for_hardcoded_secrets "config.yaml"
```

---

## Quick Command Reference

```bash
# Generate strong password
openssl rand -base64 32 | tr -d "=+/" | cut -c1-20

# Create secure directory
mkdir -p /path && chmod 700 /path

# Store secret securely
echo "secret" > /path/file && chmod 600 /path/file

# Verify service hardening
systemd-analyze security SERVICE_NAME

# Test credential validation
source scripts/lib/common.sh && validate_credentials "user" "pass" "test"

# Scan for secrets
source scripts/lib/secrets.sh && scan_for_hardcoded_secrets config.yaml

# Check file permissions
ls -la /etc/mysqld_exporter/.my.cnf

# View security logs
grep "SECURITY:" /var/log/syslog
journalctl -u SERVICE_NAME | grep -i security
```

---

**Remember:** Security is a process, not a product. Regularly review and update security configurations.
