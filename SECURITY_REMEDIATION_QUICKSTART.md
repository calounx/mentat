# Security Remediation Quick Start Guide

**Date:** 2026-01-02
**Priority:** CRITICAL - Implement immediately
**Estimated Time:** 16-24 hours for critical issues

---

## IMMEDIATE ACTIONS (Next 24 Hours)

### 1. Remove Hardcoded Email Addresses (VULN-001)
**Impact:** Critical information disclosure
**Time:** 30 minutes

```bash
# Files to update:
# - chom/deploy/scripts/setup-observability-vps.sh:62
# - chom/deploy/scripts/setup-vpsmanager-vps.sh:56

# Replace lines with:
if [[ -z "${SSL_EMAIL:-}" ]]; then
    log_error "SSL_EMAIL environment variable is required"
    log_error "Usage: export SSL_EMAIL=admin@example.com"
    exit 1
fi

# Validate format
if [[ ! "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_error "Invalid email format: ${SSL_EMAIL}"
    exit 1
fi
```

### 2. Fix MySQL Credentials in Process List (VULN-002)
**Impact:** Database compromise
**Time:** 1 hour

```bash
# File: chom/scripts/deploy-production.sh:116

# Replace:
mysqldump -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" > "$BACKUP_FILE"

# With:
MYSQL_CNF=$(mktemp)
chmod 600 "$MYSQL_CNF"
cat > "$MYSQL_CNF" << EOF
[client]
host=${DB_HOST}
user=${DB_USERNAME}
password=${DB_PASSWORD}
EOF

mysqldump --defaults-extra-file="$MYSQL_CNF" "$DB_DATABASE" > "$BACKUP_FILE"
shred -u "$MYSQL_CNF" 2>/dev/null || rm -f "$MYSQL_CNF"
```

### 3. Implement Backup Encryption (VULN-003)
**Impact:** GDPR/PCI-DSS violation
**Time:** 2 hours

```bash
# Install GPG if needed
sudo apt-get install -y gnupg

# Generate backup encryption key
gpg --full-generate-key
# Choose: RSA 4096, no expiration
# Email: backup@your-domain.com

# Update backup script to encrypt
mysqldump --defaults-extra-file="$MYSQL_CNF" "$DB_DATABASE" | \
    gpg --encrypt --recipient backup@your-domain.com \
    --output "$BACKUP_FILE.gpg"

# Never store plaintext backup
```

### 4. Remove .env from Git History (VULN-007)
**Impact:** Credential exposure
**Time:** 1 hour

```bash
# Check if .env in history
git log --all --full-history -- "*/.env"

# If found, remove (WARNING: rewrites history)
cd /home/calounx/repositories/mentat

# Install git-filter-repo
pip3 install git-filter-repo

# Remove .env files
git filter-repo --path chom/.env --invert-paths
git filter-repo --path docker/.env --invert-paths

# Force push (coordinate with team)
git push origin --force --all

# Rotate exposed credentials immediately
```

### 5. Fix Command Injection in SSL Setup (VULN-005)
**Impact:** Remote code execution
**Time:** 1.5 hours

```bash
# File: chom/deploy/scripts/setup-ssl.sh

# Add validation before line 57
validate_domain() {
    [[ -z "$1" ]] && return 1
    [[ ! "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]] && return 1
    [[ ${#1} -gt 253 ]] && return 1
    [[ "$1" =~ [;\|\&\$\(\)\{\}] ]] && return 1
    return 0
}

validate_email() {
    [[ -z "$1" ]] && return 1
    [[ ! "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && return 1
    [[ "$1" =~ [;\|\&\$\(\)\{\}`] ]] && return 1
    return 0
}

# Use before certbot
read -p "Enter domain: " GRAFANA_DOMAIN
validate_domain "$GRAFANA_DOMAIN" || { log_error "Invalid domain"; exit 1; }

read -p "Enter email: " EMAIL
validate_email "$EMAIL" || { log_error "Invalid email"; exit 1; }
```

---

## CREDENTIAL ROTATION (Next 4 Hours)

All exposed credentials MUST be rotated immediately:

### Step 1: Generate New Credentials
```bash
# Generate secure passwords
openssl rand -base64 32 > /tmp/new-redis-password
openssl rand -base64 32 > /tmp/new-mysql-password
openssl rand -base64 32 > /tmp/new-grafana-password
chmod 600 /tmp/new-*
```

### Step 2: Update Production Systems
```bash
# Redis
redis-cli CONFIG SET requirepass "$(cat /tmp/new-redis-password)"

# MySQL
mysql -u root -p << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$(cat /tmp/new-mysql-password)';
FLUSH PRIVILEGES;
EOF

# Grafana
grafana-cli admin reset-admin-password "$(cat /tmp/new-grafana-password)"
```

### Step 3: Update Configuration Files
```bash
# Update .env (NEVER commit)
sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$(cat /tmp/new-redis-password)/" /var/www/chom/.env
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$(cat /tmp/new-mysql-password)/" /var/www/chom/.env

# Update credentials files
echo "GRAFANA_ADMIN_PASSWORD=$(cat /tmp/new-grafana-password)" > /root/.observability-credentials
chmod 600 /root/.observability-credentials
```

### Step 4: Secure Cleanup
```bash
shred -u /tmp/new-* 2>/dev/null
```

---

## SECURITY HEADERS (Next 2 Hours)

### Update All Nginx Configurations

```nginx
# Add to ALL server blocks
server {
    # ... existing config ...

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self';" always;

    # HSTS (HTTPS only)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Hide version
    server_tokens off;
}
```

### Test Configuration
```bash
# Test config
nginx -t

# Reload
systemctl reload nginx

# Verify headers
curl -I https://your-domain.com
```

---

## SSH HOST KEY VERIFICATION (Next 1 Hour)

### Enable Strict Checking

```bash
# File: chom/deploy/deploy.sh

# Remove -o StrictHostKeyChecking=no
# Remove -o UserKnownHostsFile=/dev/null

# Add host key verification
SSH_KNOWN_HOSTS="$HOME/.ssh/known_hosts"

# Before first connection
ssh-keyscan -H 10.10.100.20 >> "$SSH_KNOWN_HOSTS"

# Use strict checking
ssh -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
    -i "$key_path" "$DEPLOY_USER@$target_ip"
```

---

## INPUT VALIDATION (Next 3 Hours)

### Add Domain Validation Everywhere

```bash
# Add to deploy-common.sh
validate_domain() {
    local domain="$1"
    [[ -z "$domain" ]] && return 1
    [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]] && return 1
    [[ ${#domain} -gt 253 ]] && return 1
    [[ "$domain" =~ [;\|\&\$\(\)\{\}] ]] && return 1

    # Prevent SSRF
    [[ "$domain" =~ ^(localhost|127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]] && return 1

    return 0
}

# Use before DOMAIN is used
DOMAIN="${DOMAIN:-}"
validate_domain "$DOMAIN" || { log_error "Invalid domain: $DOMAIN"; exit 1; }
```

---

## LOGGING IMPROVEMENTS (Next 2 Hours)

### Secure Log Directory
```bash
# Create secure log directory
DEPLOYMENT_LOG_DIR="/var/log/chom-deploy"
sudo mkdir -p "$DEPLOYMENT_LOG_DIR"
sudo chmod 750 "$DEPLOYMENT_LOG_DIR"
sudo chown root:adm "$DEPLOYMENT_LOG_DIR"

# Update log file creation
DEPLOYMENT_LOG_FILE="$DEPLOYMENT_LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
(umask 077 && sudo touch "$DEPLOYMENT_LOG_FILE")
```

### Add Log Rotation
```bash
# Create logrotate config
sudo cat > /etc/logrotate.d/chom-deploy << 'EOF'
/var/log/chom-deploy/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0600 root root
    sharedscripts
    postrotate
        find /var/log/chom-deploy -name "*.log.*.gz" -mtime +90 -exec shred -u {} \;
    endscript
}
EOF
```

### Sanitize Sensitive Data
```bash
# Add to log_to_file() function
sanitize_log_message() {
    echo "$1" | sed -E '
        s/(password|passwd|pwd)[=:][^ ]*/\1=***REDACTED***/gi;
        s/(secret|api_key|token)[=:][^ ]*/\1=***REDACTED***/gi;
    '
}
```

---

## TESTING CHECKLIST

After implementing fixes, verify:

### Security Tests
- [ ] No hardcoded credentials in codebase
- [ ] .env files not in Git history
- [ ] Database backups are encrypted
- [ ] Credentials not visible in `ps aux`
- [ ] Input validation blocks injection attempts
- [ ] SSH host keys are verified
- [ ] Security headers present in HTTP responses
- [ ] Logs don't contain sensitive data

### Functional Tests
- [ ] Deployment scripts run successfully
- [ ] SSL certificates obtained correctly
- [ ] Database backups can be restored
- [ ] Services start properly
- [ ] Monitoring/observability works

### Verification Commands
```bash
# Check for secrets in code
grep -r "password\|secret\|key" chom/deploy/ --exclude="*.md"

# Check Git history
git log --all --full-history -p | grep -i "redis_password"

# Test backup encryption
gpg --list-keys backup@your-domain.com

# Verify log permissions
ls -la /var/log/chom-deploy/

# Check SSH config
grep StrictHostKeyChecking chom/deploy/*.sh

# Test security headers
curl -I https://your-domain.com | grep -i "x-frame-options\|x-content-type"
```

---

## EMERGENCY CONTACTS

If you discover active exploitation:

1. **Immediate Actions:**
   - Rotate ALL credentials
   - Review access logs
   - Check for unauthorized changes
   - Disconnect compromised systems

2. **Incident Response:**
   - Document timeline
   - Preserve evidence
   - Contact security team
   - Notify affected users (if required)

3. **Recovery:**
   - Restore from known-good backups
   - Verify system integrity
   - Implement additional monitoring
   - Update incident playbooks

---

## COMPLETION CHECKLIST

### Critical (Complete within 24 hours)
- [ ] VULN-001: Remove hardcoded emails
- [ ] VULN-002: Fix MySQL credential exposure
- [ ] VULN-003: Encrypt backups
- [ ] VULN-005: Fix command injection
- [ ] VULN-007: Remove .env from Git
- [ ] Rotate all exposed credentials

### High Priority (Complete within 7 days)
- [ ] VULN-008: Improve password generation
- [ ] VULN-009: Add domain validation
- [ ] VULN-010: Enable SSH host key verification
- [ ] Add security headers to Nginx
- [ ] Implement secure logging
- [ ] Set up log rotation

### Medium Priority (Complete within 30 days)
- [ ] Implement binary checksum verification
- [ ] Set up centralized secrets management
- [ ] Add comprehensive monitoring
- [ ] Implement backup integrity checks
- [ ] Security training for team

---

**Next Steps:**
1. Review this guide with your team
2. Schedule remediation work
3. Test changes in staging environment
4. Deploy to production
5. Verify all tests pass
6. Document changes

**Questions?** See full audit report: `DEPLOYMENT_SECURITY_AUDIT.md`

