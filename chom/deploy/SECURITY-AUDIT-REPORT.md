# CHOM Deployment Infrastructure Security Audit Report

**Date**: 2025-12-31
**Auditor**: Security Audit (Automated)
**Scope**: All deployment scripts in `/chom/deploy/`
**Framework**: OWASP Top 10, CIS Benchmarks, Defense in Depth

---

## Executive Summary

This security audit identified **CRITICAL** and **HIGH** severity vulnerabilities in the CHOM deployment infrastructure. While the scripts demonstrate good practices in some areas (systemd hardening, service isolation), they contain serious security flaws that could lead to credential exposure, privilege escalation, and system compromise.

**Risk Level**: **HIGH**

**Critical Findings**: 5
**High Findings**: 8
**Medium Findings**: 12
**Low Findings**: 6

---

## Critical Vulnerabilities

### CRITICAL-1: Secrets Exposed in Process List (CWE-214)
**Severity**: CRITICAL (CVSS 9.1)
**OWASP**: A02:2021 - Cryptographic Failures

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:543`

```bash
DASHBOARD_PASSWORD_HASH=$(php -r "echo password_hash('${DASHBOARD_PASSWORD}', PASSWORD_BCRYPT);")
```

**Vulnerability**:
- Plaintext password visible in process list (`ps aux`, `/proc/*/cmdline`)
- Any user on the system can read passwords during execution
- Password persists in shell history
- Race condition window of several seconds

**Attack Scenario**:
```bash
# Attacker runs this while setup script executes:
while true; do ps auxww | grep -i password; done

# Output:
root  12345  php -r echo password_hash('xK9mPq2nR5tL8vW3', PASSWORD_BCRYPT);
```

**Impact**:
- Dashboard credentials compromised
- Administrative access to VPS management interface
- Lateral movement to managed WordPress sites

**Remediation**:
```bash
# SECURE: Use environment variable + heredoc
DASHBOARD_PASSWORD_HASH=$(DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD}" php <<'PHP'
<?php
$password = getenv('DASHBOARD_PASSWORD');
if ($password === false) {
    fwrite(STDERR, "Password not provided\n");
    exit(1);
}
echo password_hash($password, PASSWORD_BCRYPT);
PHP
)
unset DASHBOARD_PASSWORD  # Clear from environment immediately
```

**OWASP Reference**: A02:2021 - Ensure sensitive data is not logged or exposed

---

### CRITICAL-2: MySQL Credentials in World-Readable /tmp (CWE-377)
**Severity**: CRITICAL (CVSS 8.8)
**OWASP**: A01:2021 - Broken Access Control

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:383-401`

```bash
MYSQL_CNF_FILE=$(mktemp -t mysql.XXXXXX)
sudo chmod 600 "$MYSQL_CNF_FILE"  # RACE CONDITION!

write_system_file "$MYSQL_CNF_FILE" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
```

**Vulnerability**:
1. **Time-of-check/Time-of-use (TOCTOU) race condition**:
   - File created with default permissions (0644)
   - Brief window before chmod executes
   - Attacker can read password in this window

2. **Predictable filename pattern**: `mysql.XXXXXX` (6 random chars = 36^6 = ~2 billion combinations)
   - Feasible to brute-force in local inotify monitoring

**Attack Scenario**:
```bash
# Attacker sets up monitoring:
inotifywait -m /tmp -e create | while read path event file; do
    if [[ "$file" =~ ^mysql\. ]]; then
        cat "/tmp/$file" 2>/dev/null
    fi
done
```

**Proof of Concept Timeline**:
```
T+0.000s: mktemp creates /tmp/mysql.Ab3X9z (mode 0644)
T+0.001s: ATTACKER reads password
T+0.002s: chmod 600 executes (too late)
```

**Impact**:
- Database root password exposed
- Complete database compromise
- Access to all WordPress site databases
- Credential theft for lateral movement

**Remediation**:
```bash
# SECURE: Set umask BEFORE creating file
(
    umask 077  # Subshell to limit scope
    MYSQL_CNF_FILE=$(mktemp -t mysql.XXXXXX)

    # File is created with 0600 atomically
    write_system_file "$MYSQL_CNF_FILE" << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF

    # Use then immediately destroy
    sudo mysql --defaults-extra-file="$MYSQL_CNF_FILE" << 'SQL'
    -- MySQL commands
SQL

    shred -u "$MYSQL_CNF_FILE" 2>/dev/null || rm -f "$MYSQL_CNF_FILE"
)
```

**OWASP Reference**: A01:2021 - Enforce least privilege, A04:2021 - Insecure Design

---

### CRITICAL-3: SSH Host Key Validation Disabled (CWE-295)
**Severity**: CRITICAL (CVSS 8.1)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/deploy.sh:70`, `/chom/deploy/deploy-enhanced.sh:927`

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$key_path" -p "$port" "${user}@${host}" "$cmd"
```

**Vulnerability**:
- **Disables TOFU (Trust On First Use)** protection
- No host key verification → susceptible to MITM attacks
- Accepts ANY SSH host key without validation
- `/dev/null` for known_hosts prevents key persistence

**Attack Scenario**:
```
[Attacker]        [Deployment Script]        [Real VPS]
    |                     |                       |
    |  <-- ARP Poison --> |                       |
    |                     |                       |
    |     DNS Hijack  --> |                       |
    |                     |                       |
    |  <-- SSH Connect -- |                       |
    | Present fake key    |                       |
    | Script accepts! --> |                       X (never reached)
    |                     |
    | Capture credentials |
    | Deploy backdoor     |
```

**Impact**:
- Man-in-the-middle attacks
- Credential interception
- Backdoor injection during deployment
- Complete infrastructure compromise

**Remediation**:
```bash
# SECURE: Proper host key management

# Option 1: Manual verification (recommended for first run)
ensure_host_key() {
    local host=$1
    local port=$2
    local known_hosts="${KEYS_DIR}/known_hosts"

    if ! grep -q "^${host}" "$known_hosts" 2>/dev/null; then
        log_warn "Host key not verified for $host"
        log_info "Fetching host key..."

        # Show fingerprint for manual verification
        ssh-keyscan -p "$port" "$host" 2>/dev/null | tee -a "$known_hosts"

        log_warn "Verify this fingerprint matches your VPS provider's dashboard:"
        ssh-keygen -lf <(ssh-keyscan -p "$port" "$host" 2>/dev/null)

        read -p "Does the fingerprint match? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_error "Host key verification failed"
            exit 1
        fi
    fi
}

# Use it:
ensure_host_key "$ip" "$port"

# Then connect normally (WITH host key checking):
ssh -o UserKnownHostsFile="${KEYS_DIR}/known_hosts" \
    -i "$key_path" -p "$port" "${user}@${host}" "$cmd"
```

**OWASP Reference**: A07:2021 - Use strong authentication, A05:2021 - Security Misconfiguration

---

### CRITICAL-4: Unrestricted Passwordless Sudo (CWE-250)
**Severity**: CRITICAL (CVSS 8.8)
**OWASP**: A01:2021 - Broken Access Control

**Location**: `/chom/deploy/scripts/create-deploy-user.sh:58`

```bash
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME"
```

**Vulnerability**:
- Grants unrestricted root access without password
- No command whitelisting
- No auditing of privileged operations
- Single compromised SSH key = full root access

**Attack Scenario**:
```bash
# If SSH key is compromised (phishing, laptop theft, GitHub leak):
ssh deploy@target-vps
sudo su -  # No password required
# Attacker now has root access
```

**Impact**:
- Complete system compromise
- Privilege escalation from user to root
- No audit trail for privileged commands
- Persistence mechanisms (rootkits, backdoors)

**Remediation**:
```bash
# SECURE: Restrict to specific commands needed for deployment

cat > /etc/sudoers.d/"$USERNAME" << 'SUDOERS'
# Deployment user - restricted sudo access
Defaults:deploy !requiretty
Defaults:deploy env_reset
Defaults:deploy secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# System package management
deploy ALL=(root) NOPASSWD: /usr/bin/apt-get update
deploy ALL=(root) NOPASSWD: /usr/bin/apt-get upgrade
deploy ALL=(root) NOPASSWD: /usr/bin/apt-get install *

# Service management (specific services only)
deploy ALL=(root) NOPASSWD: /bin/systemctl daemon-reload
deploy ALL=(root) NOPASSWD: /bin/systemctl enable prometheus
deploy ALL=(root) NOPASSWD: /bin/systemctl enable loki
deploy ALL=(root) NOPASSWD: /bin/systemctl enable grafana-server
deploy ALL=(root) NOPASSWD: /bin/systemctl enable alertmanager
deploy ALL=(root) NOPASSWD: /bin/systemctl enable node_exporter
deploy ALL=(root) NOPASSWD: /bin/systemctl enable nginx
deploy ALL=(root) NOPASSWD: /bin/systemctl enable mariadb
deploy ALL=(root) NOPASSWD: /bin/systemctl enable redis-server
deploy ALL=(root) NOPASSWD: /bin/systemctl restart prometheus
deploy ALL=(root) NOPASSWD: /bin/systemctl restart loki
deploy ALL=(root) NOPASSWD: /bin/systemctl restart grafana-server
deploy ALL=(root) NOPASSWD: /bin/systemctl restart alertmanager
deploy ALL=(root) NOPASSWD: /bin/systemctl restart node_exporter
deploy ALL=(root) NOPASSWD: /bin/systemctl restart nginx
deploy ALL=(root) NOPASSWD: /bin/systemctl restart mariadb
deploy ALL=(root) NOPASSWD: /bin/systemctl restart redis-server
deploy ALL=(root) NOPASSWD: /bin/systemctl stop prometheus
deploy ALL=(root) NOPASSWD: /bin/systemctl stop loki
deploy ALL=(root) NOPASSWD: /bin/systemctl stop grafana-server
deploy ALL=(root) NOPASSWD: /bin/systemctl stop alertmanager
deploy ALL=(root) NOPASSWD: /bin/systemctl stop node_exporter
deploy ALL=(root) NOPASSWD: /bin/systemctl stop nginx

# File operations (specific paths only)
deploy ALL=(root) NOPASSWD: /usr/bin/tee /etc/observability/*
deploy ALL=(root) NOPASSWD: /usr/bin/tee /etc/vpsmanager/*
deploy ALL=(root) NOPASSWD: /usr/bin/tee /etc/nginx/sites-available/*
deploy ALL=(root) NOPASSWD: /usr/bin/tee /etc/systemd/system/*.service
deploy ALL=(root) NOPASSWD: /usr/bin/tee /etc/grafana/grafana.ini
deploy ALL=(root) NOPASSWD: /bin/chown -R observability\:observability *
deploy ALL=(root) NOPASSWD: /bin/chmod * /etc/observability/*
deploy ALL=(root) NOPASSWD: /bin/chmod * /etc/vpsmanager/*

# Firewall management
deploy ALL=(root) NOPASSWD: /usr/sbin/ufw *

# User management (limited)
deploy ALL=(root) NOPASSWD: /usr/sbin/useradd --system --no-create-home *
deploy ALL=(root) NOPASSWD: /usr/sbin/usermod *

# Process management (for cleanup)
deploy ALL=(root) NOPASSWD: /usr/bin/kill *
deploy ALL=(root) NOPASSWD: /usr/bin/killall *

# Nginx testing
deploy ALL=(root) NOPASSWD: /usr/sbin/nginx -t

# MySQL (only via defaults-extra-file to hide passwords)
deploy ALL=(root) NOPASSWD: /usr/bin/mysql --defaults-extra-file=*

# NO SHELL ACCESS
# deploy ALL=(root) NOPASSWD: /bin/bash  # FORBIDDEN
# deploy ALL=(root) NOPASSWD: /bin/sh    # FORBIDDEN
# deploy ALL=(root) NOPASSWD: ALL        # FORBIDDEN
SUDOERS

chmod 0440 /etc/sudoers.d/"$USERNAME"
visudo -c  # Validate syntax
```

**Additional Hardening**:
```bash
# Enable sudo logging
cat >> /etc/sudoers.d/logging << 'EOF'
Defaults log_input, log_output
Defaults iolog_dir=/var/log/sudo-io
Defaults!/usr/bin/sudoreplay !log_output
EOF

# Monitor sudo abuse
cat > /etc/rsyslog.d/50-sudo.conf << 'EOF'
# Log all sudo commands to dedicated file
:programname, isequal, "sudo" /var/log/sudo.log
& stop
EOF
systemctl restart rsyslog
```

**OWASP Reference**: A01:2021 - Follow principle of least privilege

---

### CRITICAL-5: Unprotected Credentials Written to /root (CWE-532)
**Severity**: CRITICAL (CVSS 7.5)
**OWASP**: A09:2021 - Security Logging and Monitoring Failures

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:665-668`

```bash
write_system_file /root/.observability-credentials << EOF
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
EOF
sudo chmod 600 /root/.observability-credentials
```

**Vulnerability**:
- Credentials stored in plaintext on filesystem
- No encryption at rest
- Survives system reboot
- Backup systems may copy this file
- No expiration or rotation mechanism

**Attack Scenario**:
```bash
# Attacker gains any local access (LFI, arbitrary file read, backup exposure):
cat /root/.observability-credentials
# GRAFANA_ADMIN_PASSWORD=xK9mPq2nR5tL8vW3

cat /root/.vpsmanager-credentials
# DASHBOARD_PASSWORD=aB7nKp4mR9sT
# MYSQL_ROOT_PASSWORD=wX2vCq8nPr5L
```

**Impact**:
- Long-term credential exposure
- Credentials in backups (off-site storage)
- Log file inclusion attacks
- No forward secrecy

**Remediation**:

**Option 1: Don't store credentials**
```bash
# BEST: Display once, require secure storage elsewhere
log_warn "IMPORTANT: Save these credentials securely!"
log_warn "Grafana Admin Password: ${GRAFANA_ADMIN_PASSWORD}"
log_warn "This password will not be displayed again."

# Force user to acknowledge
read -p "Have you saved the password? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    log_error "Password not saved. Aborting."
    exit 1
fi

# DO NOT write to disk
```

**Option 2: Encrypted storage with systemd credentials**
```bash
# Use systemd credential encryption (Debian 13 supports this)
echo -n "${GRAFANA_ADMIN_PASSWORD}" | \
    systemd-creds encrypt - /etc/credstore/grafana-admin.cred

# Update systemd service to use encrypted credential
cat > /etc/systemd/system/grafana-server.service.d/credentials.conf << 'EOF'
[Service]
LoadCredential=admin-password:/etc/credstore/grafana-admin.cred
EOF

# Grafana can read from: $CREDENTIALS_DIRECTORY/admin-password
```

**Option 3: Secrets management service**
```bash
# Use HashiCorp Vault, AWS Secrets Manager, or similar
vault kv put secret/grafana/admin password="${GRAFANA_ADMIN_PASSWORD}"

# Retrieve in scripts:
GRAFANA_ADMIN_PASSWORD=$(vault kv get -field=password secret/grafana/admin)
```

**OWASP Reference**: A02:2021 - Encrypt sensitive data at rest, A09:2021 - Implement security logging

---

## High Severity Vulnerabilities

### HIGH-1: Insecure Grafana Configuration Allows Auth Bypass
**Severity**: HIGH (CVSS 7.5)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:548-549`

```bash
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
sudo sed -i "s/;admin_password = admin/admin_password = ${GRAFANA_ADMIN_PASSWORD}/" /etc/grafana/grafana.ini
```

**Vulnerability**:
- No enforcement of password change on first login
- Anonymous access not explicitly disabled
- No account lockout policy
- No 2FA/MFA configuration
- Session timeout not configured

**Impact**:
- Brute force attacks feasible
- Session hijacking
- Unauthorized dashboard access

**Remediation**:
```ini
# /etc/grafana/grafana.ini
[security]
admin_password = <generated-password>
disable_initial_admin_creation = false
admin_user = admin

# Force password change
admin_password_change = true

# Disable anonymous access
[auth.anonymous]
enabled = false

# Session security
[session]
cookie_secure = true
cookie_samesite = strict
session_life_time = 86400

# Account lockout
[login]
max_login_attempts = 5
login_attempt_window = 300

# Enable 2FA
[auth]
disable_login_form = false
oauth_auto_login = false

[auth.generic_oauth]
enabled = false
```

**OWASP Reference**: A07:2021 - Implement MFA, enforce password policies

---

### HIGH-2: Loki Authentication Enabled But No Tenant Isolation
**Severity**: HIGH (CVSS 7.3)
**OWASP**: A01:2021 - Broken Access Control

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:395`

```yaml
auth_enabled: true
```

**Vulnerability**:
- Authentication enabled but no tenant configuration
- Single tenant "default" hardcoded in Grafana datasource
- No authentication required for log ingestion
- Port 3100 exposed to network without auth

**Impact**:
- Any host can inject logs without authentication
- Log pollution/DoS
- Sensitive data exfiltration via logs
- Multi-tenant isolation broken

**Remediation**:
```yaml
# /etc/observability/loki/loki.yml
auth_enabled: true

# Configure multi-tenancy
limits_config:
  enforce_metric_name: true
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_strategy: global
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  per_tenant_override_config: /etc/observability/loki/overrides.yml

# Create tenant-specific limits
# /etc/observability/loki/overrides.yml
overrides:
  tenant1:
    ingestion_rate_mb: 20
    ingestion_burst_size_mb: 40
  tenant2:
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20
```

**Nginx reverse proxy with authentication**:
```nginx
# /etc/nginx/sites-available/loki
server {
    listen 127.0.0.1:3100;  # Local only

    location /loki/api/v1/push {
        # Require authentication for log ingestion
        auth_request /auth;

        proxy_pass http://localhost:3100;
        proxy_set_header X-Scope-OrgID $tenant_id;
    }

    location = /auth {
        internal;
        proxy_pass http://localhost:8080/auth;
    }
}
```

**OWASP Reference**: A01:2021 - Enforce access control, A05:2021 - Secure defaults

---

### HIGH-3: Dashboard Rate Limiting Insufficient
**Severity**: HIGH (CVSS 6.8)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:556-575`

```php
$attempts_file = '/tmp/dashboard_login_attempts_' . md5($_SERVER['REMOTE_ADDR']);
$max_attempts = 5;
$lockout_duration = 300; // 5 minutes
```

**Vulnerability**:
- **Client-side rate limiting**: Attacker can use distributed IPs
- **No server-side enforcement**: Nginx not configured for rate limiting
- **Predictable temp files**: `/tmp/dashboard_login_attempts_<md5>`
- **No global limit**: Each IP gets 5 attempts independently
- **Easy bypass**: Attacker rotates IPs via proxy/VPN/Tor

**Attack Scenario**:
```python
# Distributed brute force attack
import requests
from itertools import cycle

proxies = load_proxies()  # 1000 proxies
passwords = load_wordlist()  # Common passwords

for password in passwords:
    for proxy in cycle(proxies):
        # Each proxy gets 5 attempts before lockout
        response = requests.post(
            'http://target:8080/',
            data={'password': password},
            proxies={'http': proxy}
        )
        if 'authenticated' in response.text:
            print(f"Password found: {password}")
            exit(0)
```

**Impact**:
- Brute force attacks feasible
- Credential stuffing attacks
- Account takeover
- Resource exhaustion

**Remediation**:

**Layer 1: Nginx rate limiting**
```nginx
# /etc/nginx/conf.d/rate-limit.conf
limit_req_zone $binary_remote_addr zone=dashboard_login:10m rate=5r/m;
limit_req_status 429;

# /etc/nginx/sites-available/dashboard
server {
    listen 8080;
    server_name _;
    root /var/www/dashboard;

    location / {
        # Global rate limit: 5 requests per minute
        limit_req zone=dashboard_login burst=5 nodelay;
        limit_req_log_level warn;

        try_files $uri $uri/ /index.php?$args;
    }

    # Stricter limit for login endpoint
    location = /index.php {
        limit_req zone=dashboard_login burst=3 nodelay;

        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }
}
```

**Layer 2: Fail2ban integration**
```ini
# /etc/fail2ban/filter.d/dashboard-auth.conf
[Definition]
failregex = ^.*Dashboard: Failed login attempt from <HOST>$
ignoreregex =

# /etc/fail2ban/jail.d/dashboard.conf
[dashboard-auth]
enabled = true
port = 8080
filter = dashboard-auth
logpath = /var/log/nginx/error.log
maxretry = 5
findtime = 600
bantime = 3600
```

**Layer 3: PHP-level CAPTCHA after failed attempts**
```php
// After 3 failed attempts, require CAPTCHA
if (count($recent_attempts) >= 3) {
    if (!isset($_POST['captcha']) || !verify_captcha($_POST['captcha'])) {
        http_response_code(403);
        exit('CAPTCHA required after multiple failed attempts');
    }
}
```

**OWASP Reference**: A07:2021 - Implement account lockout, ASVS V2.2

---

### HIGH-4: Firewall Rules Allow Unnecessary Public Exposure
**Severity**: HIGH (CVSS 6.5)
**OWASP**: A05:2021 - Security Misconfiguration

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:600-601`

```bash
sudo ufw allow 3100/tcp    # Loki (for log ingestion from monitored hosts)
sudo ufw allow 9090/tcp    # Prometheus (for federation if needed)
```

**Vulnerability**:
- Loki port 3100 exposed to internet without authentication
- Prometheus port 9090 exposed to internet
- No IP whitelisting for sensitive services
- Port 9100 (node_exporter) also exposed in vpsmanager script

**Attack Surface**:
```
Internet -> Port 3100 (Loki) -> Direct log injection
Internet -> Port 9090 (Prometheus) -> Metrics scraping/DoS
Internet -> Port 9100 (Node Exporter) -> System metrics exposure
```

**Impact**:
- Information disclosure (system metrics, hostnames, internal IPs)
- Log injection/pollution
- Denial of service
- Reconnaissance for targeted attacks

**Remediation**:

**Option 1: VPN/WireGuard tunnel (BEST)**
```bash
# Install WireGuard on observability server
apt-get install -y wireguard

# Generate keys
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

# Configure WireGuard
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
PrivateKey = <server-private-key>
Address = 10.0.0.1/24
ListenPort = 51820

# Monitored host 1
[Peer]
PublicKey = <host1-public-key>
AllowedIPs = 10.0.0.2/32

# Monitored host 2
[Peer]
PublicKey = <host2-public-key>
AllowedIPs = 10.0.0.3/32
EOF

# Firewall: Only allow WireGuard
sudo ufw allow 51820/udp
sudo ufw deny 3100/tcp
sudo ufw deny 9090/tcp
sudo ufw deny 9100/tcp

# Bind services to WireGuard interface
# Prometheus: --web.listen-address=10.0.0.1:9090
# Loki: server.http_listen_address: 10.0.0.1
```

**Option 2: IP whitelisting**
```bash
# Allow only specific IPs
VPSMANAGER_IP="203.0.113.50"
ADMIN_IP="198.51.100.10"

sudo ufw deny 3100/tcp
sudo ufw deny 9090/tcp
sudo ufw deny 9100/tcp

sudo ufw allow from $VPSMANAGER_IP to any port 3100 proto tcp
sudo ufw allow from $VPSMANAGER_IP to any port 9100 proto tcp
sudo ufw allow from $ADMIN_IP to any port 9090 proto tcp
```

**Option 3: mTLS authentication**
```bash
# Generate CA for internal services
openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
    -keyout /etc/observability/ca-key.pem \
    -out /etc/observability/ca-cert.pem \
    -subj "/CN=CHOM Internal CA"

# Configure Prometheus with TLS
# --web.config.file=/etc/observability/prometheus/web-config.yml

# /etc/observability/prometheus/web-config.yml
tls_server_config:
  cert_file: /etc/observability/prometheus/prometheus.crt
  key_file: /etc/observability/prometheus/prometheus.key
  client_auth_type: RequireAndVerifyClientCert
  client_ca_file: /etc/observability/ca-cert.pem
```

**OWASP Reference**: A05:2021 - Minimize attack surface, disable unnecessary services

---

### HIGH-5: No Input Validation in Dashboard PHP Code
**Severity**: HIGH (CVSS 6.3)
**OWASP**: A03:2021 - Injection

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:669-673`

```php
$www_dir = '/var/www';
foreach (glob("$www_dir/*/public") as $path) {
    $domain = basename(dirname($path));
    if ($domain !== 'dashboard') {
        $sites[] = $domain;
    }
}
```

**Vulnerability**:
- **Path traversal risk**: Unsanitized `glob()` pattern
- **Command injection potential**: `basename()` on untrusted paths
- **XSS in output**: Domain names echoed without proper escaping

**Attack Scenario**:
```bash
# Attacker creates malicious directory:
sudo mkdir -p "/var/www/<script>alert(1)</script>/public"

# Dashboard now renders:
<a href="https://<script>alert(1)</script>">
    <script>alert(1)</script>
</a>
```

**Impact**:
- Cross-site scripting (XSS)
- Session hijacking
- Malicious redirects
- Admin account takeover

**Remediation**:
```php
// SECURE: Validate and sanitize all inputs
$www_dir = '/var/www';
$sites = [];

// Whitelist allowed characters in domain names
$domain_pattern = '/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/i';

foreach (glob("$www_dir/*/public") as $path) {
    // Validate path is within expected directory
    $real_path = realpath($path);
    if ($real_path === false || strpos($real_path, realpath($www_dir)) !== 0) {
        error_log("Invalid path detected: $path");
        continue;
    }

    $domain = basename(dirname($real_path));

    // Validate domain name format
    if ($domain === 'dashboard' || !preg_match($domain_pattern, $domain)) {
        continue;
    }

    // Sanitize for output
    $sites[] = $domain;
}

// In HTML output:
foreach ($sites as $site):
    // Use htmlspecialchars with ENT_QUOTES for XSS protection
    $safe_site = htmlspecialchars($site, ENT_QUOTES, 'UTF-8');
?>
    <tr>
        <td><a href="https://<?= $safe_site ?>" target="_blank"><?= $safe_site ?></a></td>
        <td><span class="badge badge-green">Active</span></td>
    </tr>
<?php endforeach; ?>
```

**OWASP Reference**: A03:2021 - Use parameterization and input validation

---

### HIGH-6: Redis Running Without Authentication
**Severity**: HIGH (CVSS 6.5)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:427-428`

```bash
sed -i 's/^# maxmemory .*/maxmemory 128mb/' /etc/redis/redis.conf
sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
```

**Vulnerability**:
- No `requirepass` directive configured
- Redis accessible without authentication
- Bound to 0.0.0.0 by default
- Protected mode may not be enabled

**Attack Scenario**:
```bash
# Attacker scans for open Redis instances
nmap -p 6379 target-vps

# Connect without authentication
redis-cli -h target-vps
> CONFIG SET dir /var/www/html/
> CONFIG SET dbfilename shell.php
> SET payload "<?php system($_GET['cmd']); ?>"
> SAVE
# Now access: http://target-vps/shell.php?cmd=whoami
```

**Impact**:
- Unauthorized data access
- Data manipulation/deletion
- Remote code execution via module loading
- Session hijacking (if sessions stored in Redis)

**Remediation**:
```bash
# /etc/redis/redis.conf

# Bind to localhost only
bind 127.0.0.1 ::1

# Enable protected mode
protected-mode yes

# Require authentication
requirepass $(openssl rand -base64 32)

# Disable dangerous commands
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG ""
rename-command SHUTDOWN ""
rename-command SAVE ""
rename-command BGSAVE ""
rename-command DEBUG ""
rename-command MODULE ""

# Enable ACLs (Redis 6+)
aclfile /etc/redis/users.acl

# /etc/redis/users.acl
user default on nopass ~* &* +@all
user app on ><strong-password> ~app:* +@read +@write +@hash +@string -@dangerous
```

**Update PHP configuration**:
```bash
# Save Redis password securely
REDIS_PASSWORD=$(openssl rand -base64 32)
echo "requirepass $REDIS_PASSWORD" >> /etc/redis/redis.conf
systemctl restart redis-server

# Update VPSManager config
cat >> /etc/vpsmanager/config.yaml << EOF
redis:
  host: 127.0.0.1
  port: 6379
  password: "${REDIS_PASSWORD}"
  database: 0
EOF

chmod 600 /etc/vpsmanager/config.yaml
```

**OWASP Reference**: A07:2021 - Enforce authentication, A05:2021 - Secure defaults

---

### HIGH-7: MariaDB Listening on All Interfaces
**Severity**: HIGH (CVSS 6.3)
**OWASP**: A05:2021 - Security Misconfiguration

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:404-414`

**Vulnerability**:
- No `bind-address` configuration
- MariaDB listens on 0.0.0.0:3306 by default
- Firewall blocks it, but defense in depth violated

**Attack Scenario**:
```bash
# If firewall is misconfigured or disabled:
nmap -p 3306 target-vps

# Brute force attack:
hydra -l root -P passwords.txt mysql://target-vps
```

**Impact**:
- Database exposed to network
- Brute force attacks
- Exploitation of unpatched vulnerabilities

**Remediation**:
```bash
# /etc/mysql/mariadb.conf.d/50-server.cnf
[mysqld]
bind-address = 127.0.0.1
skip-name-resolve
local-infile = 0

# Disable remote root login (already done, but verify)
# DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

# Additional security
[mysqld]
# Disable LOAD DATA LOCAL INFILE
local_infile = 0

# Enable strict SQL mode
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

# Limit packet size to prevent DoS
max_allowed_packet = 16M

# Connection limits
max_connections = 200
max_connect_errors = 10

# Enable query logging for audit
general_log = 1
general_log_file = /var/log/mysql/query.log
```

**OWASP Reference**: A05:2021 - Minimize attack surface

---

### HIGH-8: No TLS/SSL for Internal Service Communication
**Severity**: HIGH (CVSS 6.1)
**OWASP**: A02:2021 - Cryptographic Failures

**Location**: Multiple locations in setup scripts

**Vulnerability**:
- Grafana → Prometheus: HTTP (no encryption)
- Grafana → Loki: HTTP (no encryption)
- VPSManager → Observability: HTTP (no encryption)
- All internal API calls in cleartext

**Attack Scenario**:
```bash
# Attacker with network access (compromised container, VLAN access):
tcpdump -i any -A 'tcp port 9090 or tcp port 3100'

# Captures:
# - Prometheus queries (may contain sensitive metric labels)
# - Loki log queries (may contain secrets in logs)
# - Authentication tokens
```

**Impact**:
- Credential interception
- Session hijacking
- Data exfiltration
- MITM attacks

**Remediation**:

**Generate internal CA**:
```bash
#!/bin/bash
# Create internal certificate authority

mkdir -p /etc/observability/tls
cd /etc/observability/tls

# Generate CA
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
    -subj "/CN=CHOM Internal CA/O=CHOM/C=US"

# Generate service certificates
for service in prometheus loki grafana alertmanager; do
    # Generate key
    openssl genrsa -out ${service}-key.pem 2048

    # Generate CSR
    openssl req -new -key ${service}-key.pem -out ${service}.csr \
        -subj "/CN=${service}.internal.chom/O=CHOM/C=US"

    # Sign with CA
    openssl x509 -req -in ${service}.csr -CA ca-cert.pem -CAkey ca-key.pem \
        -CAcreateserial -out ${service}-cert.pem -days 730 \
        -extensions v3_req -extfile <(cat << EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${service}
DNS.2 = ${service}.internal.chom
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF
)

    rm ${service}.csr
done

chown -R observability:observability /etc/observability/tls
chmod 600 /etc/observability/tls/*-key.pem
chmod 644 /etc/observability/tls/*-cert.pem /etc/observability/tls/ca-cert.pem
```

**Configure Prometheus with TLS**:
```yaml
# /etc/observability/prometheus/web-config.yml
tls_server_config:
  cert_file: /etc/observability/tls/prometheus-cert.pem
  key_file: /etc/observability/tls/prometheus-key.pem
  client_auth_type: RequireAndVerifyClientCert
  client_ca_file: /etc/observability/tls/ca-cert.pem

# Update prometheus.service
ExecStart=/opt/observability/bin/prometheus \
    --config.file=/etc/observability/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/observability/prometheus \
    --web.listen-address=:9090 \
    --web.config.file=/etc/observability/prometheus/web-config.yml
```

**Configure Grafana to use HTTPS datasources**:
```yaml
# /etc/grafana/provisioning/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: https://localhost:9090
    jsonData:
      tlsAuth: true
      tlsAuthWithCACert: true
      tlsSkipVerify: false
    secureJsonData:
      tlsCACert: |
        -----BEGIN CERTIFICATE-----
        <content of /etc/observability/tls/ca-cert.pem>
        -----END CERTIFICATE-----
      tlsClientCert: |
        -----BEGIN CERTIFICATE-----
        <content of /etc/observability/tls/grafana-cert.pem>
        -----END CERTIFICATE-----
      tlsClientKey: |
        -----BEGIN PRIVATE KEY-----
        <content of /etc/observability/tls/grafana-key.pem>
        -----END PRIVATE KEY-----
```

**OWASP Reference**: A02:2021 - Encrypt data in transit

---

## Medium Severity Vulnerabilities

### MEDIUM-1: Weak Grafana Password Generation
**Severity**: MEDIUM (CVSS 5.9)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:548`

```bash
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
```

**Vulnerability**:
- Only alphanumeric characters (reduced entropy)
- No special characters
- Entropy: ~142 bits (good) but could be better
- Password not validated against complexity requirements

**Impact**:
- Slightly weaker against brute force
- Does not meet some compliance requirements (PCI-DSS, NIST)

**Remediation**:
```bash
# Generate strong password with special characters
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32 | head -c 32)

# Or use all printable ASCII except quotes to avoid escaping issues:
GRAFANA_ADMIN_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+=-{}[]|:<>?,./' < /dev/urandom | head -c 32)

# Validate password strength
if ! echo "$GRAFANA_ADMIN_PASSWORD" | grep -q '[A-Z]' ||
   ! echo "$GRAFANA_ADMIN_PASSWORD" | grep -q '[a-z]' ||
   ! echo "$GRAFANA_ADMIN_PASSWORD" | grep -q '[0-9]' ||
   ! echo "$GRAFANA_ADMIN_PASSWORD" | grep -q '[^A-Za-z0-9]'; then
    log_error "Generated password does not meet complexity requirements"
    exit 1
fi
```

**OWASP Reference**: A07:2021 - Use strong password policies

---

### MEDIUM-2: Nginx Server Tokens Disabled But Version Leakage Possible
**Severity**: MEDIUM (CVSS 5.3)
**OWASP**: A05:2021 - Security Misconfiguration

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:297`

```nginx
server_tokens off;
```

**Vulnerability**:
- `server_tokens off` only hides version in headers
- Nginx version still detectable via error pages, timing attacks
- Module fingerprinting possible

**Impact**:
- Information disclosure
- Targeted exploitation of known vulnerabilities

**Remediation**:
```nginx
# Fully hide Nginx version
http {
    server_tokens off;
    more_set_headers 'Server: WebServer';  # Requires nginx-extras or headers-more module
}

# Custom error pages with no version info
error_page 404 /404.html;
error_page 500 502 503 504 /50x.html;
```

**OWASP Reference**: A05:2021 - Remove unnecessary information disclosure

---

### MEDIUM-3: Prometheus Retention Too Short for Security Analysis
**Severity**: MEDIUM (CVSS 5.0)
**OWASP**: A09:2021 - Security Logging and Monitoring Failures

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:330`

```bash
--storage.tsdb.retention.time=15d \
```

**Vulnerability**:
- 15 days retention insufficient for security investigation
- Compliance requirements often mandate 90+ days
- Attack patterns may be missed in short timeframe

**Impact**:
- Incomplete incident response
- Loss of forensic evidence
- Compliance violations (GDPR, PCI-DSS, SOC 2)

**Remediation**:
```bash
# Increase retention to 90 days (adjust based on disk space)
--storage.tsdb.retention.time=90d \
--storage.tsdb.retention.size=50GB \  # Also set size limit

# For longer retention, use remote storage
# /etc/observability/prometheus/prometheus.yml
remote_write:
  - url: https://long-term-storage.internal/api/v1/write
    basic_auth:
      username: prometheus
      password_file: /etc/observability/prometheus/remote-write-password
```

**OWASP Reference**: A09:2021 - Retain security logs for investigation

---

### MEDIUM-4: No Audit Logging for Privileged Operations
**Severity**: MEDIUM (CVSS 5.5)
**OWASP**: A09:2021 - Security Logging and Monitoring Failures

**Location**: All setup scripts

**Vulnerability**:
- No logging of deployment script execution
- No audit trail for sudo commands
- Cannot determine who ran what when

**Impact**:
- Cannot attribute actions to users
- Incomplete incident investigation
- Compliance violations

**Remediation**:
```bash
# Enable audit logging at start of all scripts
exec > >(tee -a "/var/log/chom-deployment-$(date +%Y%m%d-%H%M%S).log")
exec 2>&1

log_info "Deployment started by: $(whoami) from: ${SSH_CLIENT:-local}"
log_info "Script: $0"
log_info "Arguments: $*"

# Enable sudo logging (add to all scripts)
cat > /etc/sudoers.d/logging << 'EOF'
Defaults log_input, log_output
Defaults iolog_dir=/var/log/sudo-io/%{user}/%{seq}
Defaults iolog_file=%{user}-%{seq}
Defaults log_year, log_host, logfile=/var/log/sudo.log
EOF

# Enable auditd for critical file changes
auditctl -w /etc/sudoers.d -p wa -k sudoers_changes
auditctl -w /etc/grafana/grafana.ini -p wa -k grafana_config
auditctl -w /root/.observability-credentials -p r -k credential_access
```

**OWASP Reference**: A09:2021 - Implement comprehensive logging

---

### MEDIUM-5: Composer Installer Downloaded Over HTTP
**Severity**: MEDIUM (CVSS 5.3)
**OWASP**: A08:2021 - Software and Data Integrity Failures

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:438`

```bash
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
```

**Vulnerability**:
- No signature verification
- Trust on first use (TOFU)
- Potential MITM attack during download

**Impact**:
- Supply chain attack
- Malicious code execution
- Compromised dependencies

**Remediation**:
```bash
# Download with signature verification
EXPECTED_SIGNATURE="$(curl -sS https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
    log_error "Composer installer signature mismatch"
    log_error "Expected: $EXPECTED_SIGNATURE"
    log_error "Got: $ACTUAL_SIGNATURE"
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# Or use distribution package (more secure)
apt-get install -y composer
```

**OWASP Reference**: A08:2021 - Verify integrity of downloaded components

---

### MEDIUM-6: No File Integrity Monitoring
**Severity**: MEDIUM (CVSS 5.0)
**OWASP**: A08:2021 - Software and Data Integrity Failures

**Location**: N/A (missing security control)

**Vulnerability**:
- No detection of unauthorized file modifications
- Backdoors could be installed undetected
- Configuration tampering unnoticed

**Impact**:
- Delayed breach detection
- Persistence mechanisms undetected
- Compliance violations

**Remediation**:
```bash
# Install AIDE (Advanced Intrusion Detection Environment)
apt-get install -y aide

# Initialize database
aideinit

# Configure what to monitor
cat >> /etc/aide/aide.conf << 'EOF'
# Critical system binaries
/bin p+i+u+g+sha256
/sbin p+i+u+g+sha256
/usr/bin p+i+u+g+sha256
/usr/sbin p+i+u+g+sha256

# Observability stack
/opt/observability p+i+u+g+sha256
/etc/observability p+i+u+g+sha256
/etc/grafana p+i+u+g+sha256
/etc/nginx p+i+u+g+sha256

# Systemd units
/etc/systemd/system p+i+u+g+sha256

# Sudo configuration
/etc/sudoers p+i+u+g+sha256
/etc/sudoers.d p+i+u+g+sha256
EOF

# Run daily checks
cat > /etc/cron.daily/aide-check << 'EOF'
#!/bin/bash
aide --check | mail -s "AIDE Report for $(hostname)" security@example.com
EOF
chmod +x /etc/cron.daily/aide-check
```

**OWASP Reference**: A08:2021 - Implement integrity verification

---

### MEDIUM-7: Grafana Admin User Not Renamed
**Severity**: MEDIUM (CVSS 4.8)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:549`

**Vulnerability**:
- Default username "admin" is publicly known
- Brute force attacks target this username
- Reduces security to single factor (password)

**Impact**:
- Easier brute force attacks
- Credential stuffing attacks

**Remediation**:
```ini
# /etc/grafana/grafana.ini
[security]
admin_user = chom_admin_$(openssl rand -hex 4)
admin_password = <generated-password>

# Or create custom admin and disable default
[security]
disable_initial_admin_creation = true

# Then create via Grafana API after first start:
ADMIN_USER="chom_admin_$(openssl rand -hex 4)"
ADMIN_PASSWORD=$(openssl rand -base64 32)

grafana-cli admin reset-admin-password "$ADMIN_PASSWORD"

# Create new admin user
curl -X POST http://localhost:3000/api/admin/users \
    -H "Authorization: Bearer $ADMIN_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$ADMIN_USER\",\"login\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\",\"role\":\"Admin\"}"

# Delete default admin
curl -X DELETE http://localhost:3000/api/admin/users/1 \
    -H "Authorization: Bearer $ADMIN_API_TOKEN"
```

**OWASP Reference**: A07:2021 - Change default credentials

---

### MEDIUM-8: Download Binary Artifacts Without Checksum Verification
**Severity**: MEDIUM (CVSS 5.5)
**OWASP**: A08:2021 - Software and Data Integrity Failures

**Location**: Multiple locations (Prometheus, Loki, Node Exporter downloads)

```bash
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
```

**Vulnerability**:
- No SHA256 checksum verification
- No GPG signature verification
- Vulnerable to MITM attacks
- Compromised GitHub releases undetected

**Impact**:
- Supply chain attack
- Malicious binaries installed
- Complete system compromise

**Remediation**:
```bash
# Download with checksum verification
download_and_verify() {
    local url=$1
    local checksum_url=$2
    local filename=$(basename "$url")

    log_info "Downloading $filename..."
    wget -q "$url" -O "$filename"

    log_info "Downloading checksum..."
    wget -q "$checksum_url" -O "${filename}.sha256"

    log_info "Verifying checksum..."
    if ! sha256sum -c "${filename}.sha256" 2>&1 | grep -q "OK"; then
        log_error "Checksum verification failed for $filename"
        rm -f "$filename" "${filename}.sha256"
        exit 1
    fi

    log_success "Checksum verified for $filename"
}

# Use it:
PROM_VERSION="2.54.1"
download_and_verify \
    "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz" \
    "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/sha256sums.txt"
```

**OWASP Reference**: A08:2021 - Verify digital signatures and checksums

---

### MEDIUM-9: Dashboard Login Uses POST But No CSRF Protection
**Severity**: MEDIUM (CVSS 5.4)
**OWASP**: A01:2021 - Broken Access Control

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:606`

```php
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['password'])) {
```

**Vulnerability**:
- No CSRF token validation
- Cross-site request forgery possible
- Session fixation not prevented

**Attack Scenario**:
```html
<!-- Attacker's malicious page -->
<form action="http://target-vps:8080/" method="POST" id="csrf">
    <input type="hidden" name="password" value="attacker-guess">
</form>
<script>
    // Auto-submit when victim visits page
    document.getElementById('csrf').submit();
</script>
```

**Impact**:
- Unauthorized login attempts via victim's browser
- Session hijacking
- Click-jacking attacks

**Remediation**:
```php
// Generate CSRF token
session_start();
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// Validate CSRF token on POST
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!isset($_POST['csrf_token']) ||
        !hash_equals($_SESSION['csrf_token'], $_POST['csrf_token'])) {
        http_response_code(403);
        error_log("Dashboard: CSRF token mismatch from {$_SERVER['REMOTE_ADDR']}");
        exit('Invalid request');
    }

    // Regenerate token after use
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// Include in form:
?>
<form method="post">
    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['csrf_token'], ENT_QUOTES) ?>">
    <input type="password" name="password" required>
    <button type="submit">Login</button>
</form>
```

**OWASP Reference**: A01:2021 - Implement CSRF protection

---

### MEDIUM-10: Loki Compactor Configuration May Cause Data Loss
**Severity**: MEDIUM (CVSS 4.5)
**OWASP**: A04:2021 - Insecure Design

**Location**: `/chom/deploy/scripts/setup-observability-vps.sh:432`

```yaml
compactor:
  working_directory: ${DATA_DIR}/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
```

**Vulnerability**:
- Very aggressive retention deletion (2 hours)
- No backup before compaction
- Single node setup means no redundancy

**Impact**:
- Accidental data loss
- Cannot recover from configuration errors
- Security logs may be deleted prematurely

**Remediation**:
```yaml
compactor:
  working_directory: ${DATA_DIR}/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 24h  # Safer: 24 hours
  retention_delete_worker_count: 50
  delete_request_cancel_period: 24h

limits_config:
  retention_period: 720h  # 30 days

  # Per-stream retention override for security logs
  per_tenant_override_config: /etc/observability/loki/overrides.yml

# /etc/observability/loki/overrides.yml
overrides:
  security:
    retention_period: 2160h  # 90 days for security logs
```

**Also implement backups**:
```bash
# Daily backup of Loki data
cat > /etc/cron.daily/backup-loki << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/loki"
DATE=$(date +%Y%m%d)

mkdir -p "$BACKUP_DIR"

# Stop compactor temporarily
systemctl stop loki

# Create backup
tar czf "$BACKUP_DIR/loki-data-$DATE.tar.gz" /var/lib/observability/loki/

# Restart compactor
systemctl start loki

# Keep only last 7 days
find "$BACKUP_DIR" -name "loki-data-*.tar.gz" -mtime +7 -delete
EOF
chmod +x /etc/cron.daily/backup-loki
```

**OWASP Reference**: A04:2021 - Design for resilience and data protection

---

### MEDIUM-11: No Network Segmentation Between Services
**Severity**: MEDIUM (CVSS 4.8)
**OWASP**: A04:2021 - Insecure Design

**Location**: Overall architecture

**Vulnerability**:
- All services on same network namespace
- No isolation between Grafana, Prometheus, Loki
- Lateral movement easy if one service compromised

**Impact**:
- Privilege escalation
- Lateral movement
- Complete stack compromise from single service

**Remediation**:

**Option 1: Network namespaces**
```bash
# Create isolated network namespace for each service
ip netns add prometheus-ns
ip netns add loki-ns
ip netns add grafana-ns

# Create veth pairs for communication
ip link add veth-prom type veth peer name veth-prom-br
ip link add veth-loki type veth peer name veth-loki-br
ip link add veth-grafana type veth peer name veth-grafana-br

# Create bridge for inter-service communication
ip link add name obs-bridge type bridge
ip link set veth-prom-br master obs-bridge
ip link set veth-loki-br master obs-bridge
ip link set veth-grafana-br master obs-bridge

# Assign to namespaces
ip link set veth-prom netns prometheus-ns
ip link set veth-loki netns loki-ns
ip link set veth-grafana netns grafana-ns

# Configure IPs
ip netns exec prometheus-ns ip addr add 10.0.1.1/24 dev veth-prom
ip netns exec loki-ns ip addr add 10.0.1.2/24 dev veth-loki
ip netns exec grafana-ns ip addr add 10.0.1.3/24 dev veth-grafana

# Update systemd services to use network namespace
[Service]
NetworkNamespacePath=/var/run/netns/prometheus-ns
```

**Option 2: Firewall rules for service isolation**
```bash
# Create iptables chains for service isolation
iptables -N OBSERVABILITY_RULES

# Prometheus: Allow only from Grafana
iptables -A OBSERVABILITY_RULES -p tcp --dport 9090 -s 127.0.0.1 -j ACCEPT
iptables -A OBSERVABILITY_RULES -p tcp --dport 9090 -j DROP

# Loki: Allow only from Grafana and remote hosts
iptables -A OBSERVABILITY_RULES -p tcp --dport 3100 -s 127.0.0.1 -j ACCEPT
iptables -A OBSERVABILITY_RULES -p tcp --dport 3100 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A OBSERVABILITY_RULES -p tcp --dport 3100 -j DROP
```

**OWASP Reference**: A04:2021 - Implement defense in depth

---

### MEDIUM-12: Predictable Session Cookie Configuration
**Severity**: MEDIUM (CVSS 4.3)
**OWASP**: A07:2021 - Identification and Authentication Failures

**Location**: `/chom/deploy/scripts/setup-vpsmanager-vps.sh:548`

```php
session_start();
```

**Vulnerability**:
- Default PHP session configuration
- No custom session name
- No HTTP-only flag enforcement
- No SameSite attribute

**Impact**:
- Session hijacking
- XSS-based session theft
- CSRF attacks

**Remediation**:
```php
// Secure session configuration
ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_secure', 1);  // Only over HTTPS
ini_set('session.cookie_samesite', 'Strict');
ini_set('session.use_strict_mode', 1);
ini_set('session.use_only_cookies', 1);
ini_set('session.sid_length', 48);
ini_set('session.sid_bits_per_character', 6);

// Custom session name (not PHPSESSID)
session_name('DASHBOARD_SESSION_' . bin2hex(random_bytes(8)));

// Regenerate session ID on privilege change
session_start();

// After successful login:
session_regenerate_id(true);

// Set additional security headers
header('X-Frame-Options: DENY');
header('X-Content-Type-Options: nosniff');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');
header("Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';");
```

**OWASP Reference**: A07:2021 - Implement secure session management

---

## Low Severity Issues

### LOW-1: Missing Security Headers in Nginx
**Severity**: LOW (CVSS 3.1)

**Location**: `/chom/deploy/scripts/setup-ssl.sh:150-153`

**Vulnerability**:
- Only basic security headers configured
- Missing Permissions-Policy
- Missing Content-Security-Policy
- Missing Referrer-Policy

**Remediation**:
```nginx
# Complete security headers
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self';" always;
```

**OWASP Reference**: A05:2021 - Security headers

---

### LOW-2: Verbose Error Pages Enabled
**Severity**: LOW (CVSS 2.7)

**Location**: PHP configuration

**Vulnerability**:
- PHP display_errors may be enabled
- Nginx error pages expose server info

**Remediation**:
```php
# /etc/php/8.2/fpm/php.ini
display_errors = Off
display_startup_errors = Off
error_reporting = E_ALL
log_errors = On
error_log = /var/log/php-fpm/error.log
```

```nginx
# Custom error pages
error_page 404 /404.html;
error_page 500 502 503 504 /50x.html;

location = /404.html {
    internal;
    root /usr/share/nginx/html;
}
```

---

### LOW-3: systemd Service Hardening Not Applied
**Severity**: LOW (CVSS 3.3)

**Location**: All systemd service files

**Vulnerability**:
- No sandboxing directives
- Services run with full capabilities
- No filesystem restrictions

**Remediation**:
```ini
[Service]
# Hardening options
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/observability/prometheus /var/log/observability
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true
PrivateMounts=true
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
```

---

### LOW-4: No Automatic Security Updates
**Severity**: LOW (CVSS 3.5)

**Location**: N/A (missing)

**Remediation**:
```bash
# Enable unattended-upgrades
apt-get install -y unattended-upgrades

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Mail "security@example.com";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
```

---

### LOW-5: SSH Hardening Not Applied
**Severity**: LOW (CVSS 3.9)

**Location**: N/A (missing)

**Remediation**:
```bash
# /etc/ssh/sshd_config
Protocol 2
Port 2222  # Non-standard port
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
AllowUsers deploy
MaxAuthTries 3
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
Subsystem sftp /usr/lib/openssh/sftp-server

# Strong key exchange algorithms
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

---

### LOW-6: No Intrusion Detection System (IDS)
**Severity**: LOW (CVSS 3.3)

**Location**: N/A (missing)

**Remediation**:
```bash
# Install OSSEC or Wazuh
apt-get install -y ossec-hids-server

# Or use fail2ban with aggressive rules
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh,2222
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[grafana-auth]
enabled = true
port = 3000
logpath = /var/log/grafana/grafana.log
maxretry = 3
findtime = 600
bantime = 7200
EOF
```

---

## Summary and Prioritized Remediation Plan

### Immediate Actions (Critical - Fix within 24 hours):

1. **CRITICAL-1**: Fix password exposure in process list
   - Impact: Credential theft
   - Effort: 1 hour
   - File: `setup-vpsmanager-vps.sh:543`

2. **CRITICAL-2**: Fix MySQL credentials race condition
   - Impact: Database compromise
   - Effort: 1 hour
   - File: `setup-vpsmanager-vps.sh:383-401`

3. **CRITICAL-3**: Enable SSH host key verification
   - Impact: MITM attacks
   - Effort: 2 hours
   - Files: `deploy.sh:70`, `deploy-enhanced.sh:927`

4. **CRITICAL-4**: Restrict passwordless sudo
   - Impact: Privilege escalation
   - Effort: 3 hours
   - File: `create-deploy-user.sh:58`

5. **CRITICAL-5**: Remove plaintext credential storage
   - Impact: Long-term credential exposure
   - Effort: 2 hours
   - Files: `setup-observability-vps.sh:665`, `setup-vpsmanager-vps.sh:881`

### Short-term (High - Fix within 1 week):

6. **HIGH-1**: Harden Grafana authentication
7. **HIGH-2**: Configure Loki multi-tenancy and auth
8. **HIGH-3**: Implement proper rate limiting
9. **HIGH-4**: Restrict firewall rules with IP whitelisting
10. **HIGH-5**: Add input validation to dashboard
11. **HIGH-6**: Enable Redis authentication
12. **HIGH-7**: Bind MariaDB to localhost only
13. **HIGH-8**: Implement TLS for internal communication

### Medium-term (Medium - Fix within 1 month):

14-25. All MEDIUM findings

### Long-term (Low - Fix within 3 months):

26-31. All LOW findings

---

## Security Hardening Checklist

### Pre-Deployment:
- [ ] Generate unique SSH keys per environment
- [ ] Configure proper known_hosts management
- [ ] Set up secrets management system (Vault/AWS Secrets Manager)
- [ ] Create network segmentation plan
- [ ] Document incident response procedures

### During Deployment:
- [ ] Use restricted sudo commands (not NOPASSWD:ALL)
- [ ] Enable SSH host key verification
- [ ] Implement TLS for all service communication
- [ ] Configure proper file permissions (umask 077 for secrets)
- [ ] Enable comprehensive audit logging

### Post-Deployment:
- [ ] Change all default passwords immediately
- [ ] Enable 2FA/MFA on all admin interfaces
- [ ] Configure alerting for security events
- [ ] Set up log forwarding to SIEM
- [ ] Schedule regular security scans
- [ ] Implement automated backups
- [ ] Enable automatic security updates
- [ ] Configure AIDE file integrity monitoring
- [ ] Set up VPN/WireGuard for internal services
- [ ] Review and harden firewall rules

### Ongoing Maintenance:
- [ ] Rotate credentials every 90 days
- [ ] Review audit logs weekly
- [ ] Apply security patches within 48 hours
- [ ] Conduct penetration testing quarterly
- [ ] Review access control lists monthly
- [ ] Update SSL certificates before expiration
- [ ] Monitor for unauthorized changes (AIDE)
- [ ] Review Fail2ban logs for attack patterns

---

## OWASP Top 10 Coverage Matrix

| OWASP 2021 Category | Findings | Status |
|---------------------|----------|--------|
| A01: Broken Access Control | CRITICAL-4, HIGH-4, MEDIUM-9, MEDIUM-11 | CRITICAL |
| A02: Cryptographic Failures | CRITICAL-1, CRITICAL-2, CRITICAL-5, HIGH-8 | CRITICAL |
| A03: Injection | HIGH-5 | HIGH |
| A04: Insecure Design | MEDIUM-10, MEDIUM-11 | MEDIUM |
| A05: Security Misconfiguration | CRITICAL-3, HIGH-1, HIGH-4, MEDIUM-2, LOW-1 | CRITICAL |
| A07: Identification and Authentication Failures | HIGH-1, HIGH-3, HIGH-6, MEDIUM-7, MEDIUM-12 | HIGH |
| A08: Software and Data Integrity Failures | MEDIUM-5, MEDIUM-6, MEDIUM-8 | MEDIUM |
| A09: Security Logging and Monitoring Failures | CRITICAL-5, MEDIUM-3, MEDIUM-4 | CRITICAL |
| A10: Server-Side Request Forgery | Not applicable | N/A |
| A06: Vulnerable Components | Not assessed (requires version scanning) | TODO |

---

## Compliance Implications

### GDPR:
- **Article 32 (Security of Processing)**: CRITICAL-1, CRITICAL-2, CRITICAL-5 violate encryption at rest/transit requirements
- **Article 25 (Data Protection by Design)**: CRITICAL-4, HIGH-4 violate principle of least privilege

### PCI-DSS (if processing payments):
- **Req 2.2.4**: CRITICAL-4 (unrestricted sudo)
- **Req 4.1**: HIGH-8 (unencrypted internal traffic)
- **Req 8.2.3**: MEDIUM-1 (weak password requirements)
- **Req 10.2**: MEDIUM-4 (insufficient audit logging)

### SOC 2:
- **CC6.1**: CRITICAL-3 (inadequate access controls)
- **CC6.6**: HIGH-8 (unencrypted transmission)
- **CC7.2**: MEDIUM-4 (insufficient monitoring)

---

## Tools and Testing Recommendations

### Vulnerability Scanning:
```bash
# Network scanning
nmap -sV -sC -p- target-vps

# Web vulnerability scanning
nikto -h http://target-vps:8080

# SSL/TLS testing
testssl.sh target-vps:443

# Dependency scanning
npm audit  # for Node.js deps
composer audit  # for PHP deps
```

### Penetration Testing:
```bash
# Brute force testing
hydra -l deploy -P passwords.txt ssh://target-vps

# Web fuzzing
ffuf -w wordlist.txt -u http://target-vps:8080/FUZZ

# SQL injection testing
sqlmap -u "http://target-vps/endpoint" --batch
```

### Security Monitoring:
```bash
# Real-time monitoring
watch -n 1 'netstat -tulpn | grep LISTEN'
watch -n 5 'tail -20 /var/log/auth.log'

# Process monitoring for secrets
watch -n 1 'ps auxww | grep -i password'
```

---

## Conclusion

The CHOM deployment infrastructure requires **immediate remediation** of critical vulnerabilities before production use. The five CRITICAL findings pose serious risks of:

1. Credential theft (CRITICAL-1, CRITICAL-2, CRITICAL-5)
2. Man-in-the-middle attacks (CRITICAL-3)
3. Privilege escalation (CRITICAL-4)

**Recommendation**: Do not deploy to production until at minimum all CRITICAL and HIGH severity findings are remediated. Implement defense-in-depth with multiple security layers, follow the principle of least privilege, and establish continuous security monitoring.

**Estimated Remediation Time**:
- Critical fixes: 8-10 hours
- High severity fixes: 20-25 hours
- Medium severity fixes: 30-40 hours
- Low severity fixes: 10-15 hours

**Total**: ~70-90 hours of security hardening work required.

---

**Report End**

For questions or clarification on any finding, please reference the specific CWE number and OWASP category listed with each vulnerability.
