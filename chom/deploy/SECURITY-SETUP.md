# CHOM Security Setup Guide

Comprehensive security hardening for your CHOM deployment.

## Overview

This guide covers essential security configurations to protect your CHOM infrastructure:

1. SSL/TLS certificate setup (Let's Encrypt)
2. Firewall configuration (UFW)
3. Two-Factor Authentication (2FA) for admin accounts
4. Secrets management and rotation
5. Security monitoring and alerting
6. Hardening checklist

**Time required:** 30-60 minutes
**Difficulty:** Intermediate

---

## Table of Contents

1. [SSL/TLS Setup](#ssltls-setup)
2. [Firewall Configuration](#firewall-configuration)
3. [Two-Factor Authentication](#two-factor-authentication)
4. [Secrets Management](#secrets-management)
5. [Security Monitoring](#security-monitoring)
6. [Hardening Checklist](#hardening-checklist)
7. [Security Maintenance](#security-maintenance)

---

## SSL/TLS Setup

### Why SSL/TLS?

- Encrypts traffic between browsers and your servers
- Prevents man-in-the-middle attacks
- Required for 2FA and secure authentication
- Improves SEO ranking
- Free with Let's Encrypt

### Prerequisites

- Domain names pointing to your VPS IPs
- Ports 80 and 443 open in firewall
- Valid email address for Let's Encrypt notifications

### Step 1: Configure DNS

Point your domains to VPS IPs:

```
# Example DNS records (A records)
monitoring.example.com  →  203.0.113.10  (Observability VPS)
manager.example.com     →  203.0.113.20  (VPSManager VPS)
```

**Verify DNS propagation:**
```bash
# From your local machine
dig monitoring.example.com +short
# Should return: 203.0.113.10

dig manager.example.com +short
# Should return: 203.0.113.20

# Or use online tool:
# https://dnschecker.org
```

### Step 2: Install Certbot (Observability VPS)

```bash
# SSH into Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP

# Install Certbot
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx

# Verify installation
certbot --version
```

### Step 3: Obtain SSL Certificate (Observability VPS)

```bash
# Get certificate for Grafana domain
sudo certbot --nginx -d monitoring.example.com

# Follow prompts:
# 1. Enter email address
# 2. Agree to Terms of Service (Y)
# 3. Share email with EFF (optional - Y/N)
# 4. Choose redirect option (2 for HTTPS redirect)
```

**What Certbot does:**
- Verifies domain ownership via HTTP challenge
- Downloads SSL certificate
- Configures Nginx automatically
- Sets up auto-renewal

### Step 4: Verify SSL (Observability VPS)

```bash
# Check certificate
sudo certbot certificates

# Should show:
# Certificate Name: monitoring.example.com
# Expiry Date: [90 days from now]
# Certificate Path: /etc/letsencrypt/live/monitoring.example.com/fullchain.pem
# Private Key Path: /etc/letsencrypt/live/monitoring.example.com/privkey.pem

# Test in browser
https://monitoring.example.com:3000
# Should show green lock icon
```

### Step 5: Install Certbot (VPSManager VPS)

```bash
# SSH into VPSManager VPS
ssh deploy@YOUR_VPSMANAGER_IP

# Install Certbot
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d manager.example.com

# Follow same prompts as Observability VPS
```

### Step 6: Configure Nginx for SSL (Manual Configuration)

If automatic configuration didn't work, edit Nginx manually:

**Observability VPS - Grafana SSL:**
```bash
sudo nano /etc/nginx/sites-available/observability
```

```nginx
server {
    listen 80;
    server_name monitoring.example.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name monitoring.example.com;

    # SSL Certificate
    ssl_certificate /etc/letsencrypt/live/monitoring.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/monitoring.example.com/privkey.pem;

    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

    # HSTS (HTTP Strict Transport Security)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/monitoring.example.com/chain.pem;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Test and reload:**
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Step 7: Configure Auto-Renewal

```bash
# Test auto-renewal (dry-run)
sudo certbot renew --dry-run

# If successful, certbot automatically sets up systemd timer
# Verify timer is active:
sudo systemctl status certbot.timer

# Should show: active (waiting)

# Manual renewal (if needed):
sudo certbot renew
```

### Step 8: Update Grafana Configuration

```bash
# SSH into Observability VPS
sudo nano /etc/grafana/grafana.ini
```

```ini
[server]
protocol = http
http_addr = 127.0.0.1
http_port = 3000
domain = monitoring.example.com
root_url = https://monitoring.example.com
```

```bash
# Restart Grafana
sudo systemctl restart grafana-server
```

### SSL/TLS Verification Checklist

- [ ] Certificates obtained for all domains
- [ ] HTTPS redirects configured
- [ ] Green lock icon appears in browser
- [ ] HSTS enabled (check headers)
- [ ] Auto-renewal working (dry-run successful)
- [ ] Certificate expires in ~90 days

**Test SSL configuration:**
- https://www.ssllabs.com/ssltest/
- Should get A or A+ rating

---

## Firewall Configuration

### Why UFW (Uncomplicated Firewall)?

- Simple to configure
- Built into Debian/Ubuntu
- Stateful packet filtering
- Prevents unauthorized access

### Observability VPS Firewall

```bash
# SSH into Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP

# Check if UFW is installed
sudo ufw status

# Allow SSH from your IP ONLY (prevent lockout)
sudo ufw allow from YOUR_LOCAL_IP to any port 22
# Example: sudo ufw allow from 203.0.113.50 to any port 22

# Allow HTTP/HTTPS for Let's Encrypt and web access
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow Grafana (if not behind reverse proxy)
sudo ufw allow 3000/tcp

# Allow Prometheus (if not behind reverse proxy)
sudo ufw allow 9090/tcp

# Allow Loki from VPSManager IP ONLY
sudo ufw allow from YOUR_VPSMANAGER_IP to any port 3100
# Example: sudo ufw allow from 203.0.113.20 to any port 3100

# Enable firewall
sudo ufw enable
# Answer 'y' to proceed

# Verify rules
sudo ufw status verbose
```

**Expected output:**
```
Status: active

To                         Action      From
--                         ------      ----
22                         ALLOW       203.0.113.50
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
3000/tcp                   ALLOW       Anywhere
9090/tcp                   ALLOW       Anywhere
3100                       ALLOW       203.0.113.20
```

### VPSManager VPS Firewall

```bash
# SSH into VPSManager VPS
ssh deploy@YOUR_VPSMANAGER_IP

# Allow SSH from your IP ONLY
sudo ufw allow from YOUR_LOCAL_IP to any port 22

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow application port (if using custom port)
sudo ufw allow 8080/tcp

# Allow metrics scraping from Observability IP ONLY
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9100  # Node exporter
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9113  # Nginx exporter
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9104  # MySQL exporter
sudo ufw allow from YOUR_OBSERVABILITY_IP to any port 9253  # PHP-FPM exporter

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status verbose
```

### Advanced Firewall Rules

**Rate limiting (prevent brute force):**
```bash
# Limit SSH connections
sudo ufw limit 22/tcp

# Limit HTTP requests (DDoS protection)
sudo ufw limit 80/tcp
sudo ufw limit 443/tcp
```

**Allow specific subnets:**
```bash
# Allow entire office network
sudo ufw allow from 203.0.113.0/24 to any port 22
```

**Block specific IPs:**
```bash
# Block malicious IP
sudo ufw deny from 198.51.100.50
```

**Logging:**
```bash
# Enable logging
sudo ufw logging on

# View logs
sudo tail -f /var/log/ufw.log
```

### Firewall Troubleshooting

**Locked out of SSH?**
- Use VPS provider console/VNC
- Disable UFW: `sudo ufw disable`
- Fix rules, then re-enable

**Service can't connect?**
```bash
# Check if port is blocked
sudo ufw status | grep PORT

# Add rule if needed
sudo ufw allow PORT/tcp
```

---

## Two-Factor Authentication

### Application 2FA (Laravel)

Your CHOM application supports 2FA. See [/docs/security/SECURITY-QUICK-REFERENCE.md](/home/calounx/repositories/mentat/chom/docs/security/SECURITY-QUICK-REFERENCE.md) for:

- Setting up 2FA for admin users
- Configuring 2FA middleware
- Backup codes management
- Recovery procedures

### SSH 2FA (Optional but Recommended)

Add 2FA to SSH login for extra security.

**Step 1: Install Google Authenticator**
```bash
# On each VPS
ssh deploy@YOUR_VPS_IP
sudo apt-get install -y libpam-google-authenticator
```

**Step 2: Configure Authenticator**
```bash
# Run setup (as deploy user)
google-authenticator

# Answer questions:
# - Time-based tokens? y
# - Update .google_authenticator file? y
# - Disallow multiple uses? y
# - Allow time skew? n
# - Enable rate limiting? y

# Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
# Save emergency scratch codes somewhere safe!
```

**Step 3: Configure SSH**
```bash
# Edit PAM config
sudo nano /etc/pam.d/sshd

# Add at the end:
auth required pam_google_authenticator.so
```

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Set these values:
ChallengeResponseAuthentication yes
UsePAM yes

# Optional - require BOTH password and 2FA:
AuthenticationMethods publickey,keyboard-interactive

# Or - require key OR password+2FA:
# AuthenticationMethods publickey keyboard-interactive:pam
```

```bash
# Restart SSH
sudo systemctl restart sshd
```

**Step 4: Test 2FA**
```bash
# Open NEW terminal (don't close current one!)
ssh deploy@YOUR_VPS_IP

# You should be prompted for:
# 1. SSH key passphrase (if key is encrypted)
# 2. Verification code (from authenticator app)
```

> **WARNING:** Test 2FA in a new terminal while keeping current session open. If something breaks, you can fix it from the existing session.

### 2FA Recovery

**If you lose your phone:**
1. Use emergency scratch codes (saved during setup)
2. Or, disable 2FA from VPS console:
   ```bash
   # Comment out in /etc/pam.d/sshd:
   # auth required pam_google_authenticator.so
   sudo systemctl restart sshd
   ```

---

## Secrets Management

### Database Credentials

**Secure storage:**
```bash
# SSH into VPSManager
ssh deploy@YOUR_VPSMANAGER_IP
cd /var/www/vpsmanager

# Ensure .env has restrictive permissions
chmod 600 .env

# Verify owner
ls -la .env
# Should show: -rw------- 1 www-data www-data

# If not:
sudo chown www-data:www-data .env
sudo chmod 600 .env
```

**Rotate database password:**
```bash
# Generate new password
NEW_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')
echo "New password: $NEW_PASSWORD"

# Update database
sudo mysql -u root -p << EOF
ALTER USER 'vpsmanager'@'localhost' IDENTIFIED BY '$NEW_PASSWORD';
FLUSH PRIVILEGES;
EOF

# Update .env
sudo nano /var/www/vpsmanager/.env
# Change DB_PASSWORD=

# Clear cache
php artisan config:cache

# Test connection
php artisan migrate:status
```

### SSH Key Rotation

**Generate new SSH keys (every 90 days):**

```bash
# On your control machine
cd ~/.ssh

# Generate new key pair
ssh-keygen -t ed25519 -f id_chom_$(date +%Y%m) -C "chom-deployment-$(date +%Y%m)"

# Copy to VPS servers
ssh-copy-id -i id_chom_$(date +%Y%m).pub deploy@OBSERVABILITY_IP
ssh-copy-id -i id_chom_$(date +%Y%m).pub deploy@VPSMANAGER_IP

# Test new key
ssh -i id_chom_$(date +%Y%m) deploy@OBSERVABILITY_IP

# Update inventory.yaml to use new key
nano configs/inventory.yaml

# Remove old key from VPS
ssh deploy@OBSERVABILITY_IP
nano ~/.ssh/authorized_keys
# Delete old key line
```

### Secrets Rotation Schedule

| Secret | Rotation Frequency | Automated? |
|--------|-------------------|------------|
| Database passwords | 90 days | Yes (Laravel command) |
| SSH keys | 90 days | Manual |
| API tokens | 180 days | Yes (Laravel command) |
| SSL certificates | Auto (90 days) | Yes (Let's Encrypt) |
| Laravel APP_KEY | Never (breaks sessions) | Manual if compromised |

**Automate rotation:**
```bash
# See docs/security/SECURITY-QUICK-REFERENCE.md for:
php artisan secrets:rotate --all
```

---

## Security Monitoring

### 1. Failed Login Monitoring

**Monitor SSH login attempts:**
```bash
# On each VPS
sudo tail -f /var/log/auth.log | grep "Failed password"

# Count recent failures
sudo grep "Failed password" /var/log/auth.log | wc -l
```

**Set up alert:**
```bash
# Install fail2ban
sudo apt-get install -y fail2ban

# Configure
sudo nano /etc/fail2ban/jail.local
```

```ini
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
```

```bash
# Start fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check banned IPs
sudo fail2ban-client status sshd
```

### 2. File Integrity Monitoring

**Monitor critical files:**
```bash
# Install AIDE (Advanced Intrusion Detection Environment)
sudo apt-get install -y aide

# Initialize database
sudo aideinit

# Move database
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Run check
sudo aide --check

# Automate checks
sudo crontab -e
# Add: 0 2 * * * /usr/bin/aide --check | mail -s "AIDE Report" admin@example.com
```

### 3. Security Scanning

**Install ClamAV (antivirus):**
```bash
sudo apt-get install -y clamav clamav-daemon

# Update virus definitions
sudo freshclam

# Scan directory
sudo clamscan -r /var/www/

# Schedule daily scans
sudo crontab -e
# Add: 0 3 * * * /usr/bin/clamscan -r /var/www/ --quiet
```

**Vulnerability scanning with Lynis:**
```bash
# Install Lynis
sudo apt-get install -y lynis

# Run audit
sudo lynis audit system

# Review recommendations
sudo lynis show suggestions
```

### 4. Prometheus Security Alerts

Configure alerts in `/etc/prometheus/alert_rules.yml`:

```yaml
groups:
  - name: security_alerts
    interval: 60s
    rules:
      # Failed SSH logins
      - alert: HighFailedSSHLogins
        expr: increase(node_systemd_unit_state{name="ssh.service",state="failed"}[5m]) > 5
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High number of failed SSH logins"
          description: "{{ $value }} failed SSH attempts in last 5 minutes"

      # Firewall changes
      - alert: FirewallRulesChanged
        expr: changes(node_ufw_status[5m]) > 0
        labels:
          severity: high
        annotations:
          summary: "Firewall rules modified"
          description: "UFW rules changed on {{ $labels.instance }}"

      # Suspicious process
      - alert: SuspiciousProcessDetected
        expr: node_processes_state{state="running"} > 200
        for: 5m
        labels:
          severity: high
        annotations:
          summary: "Unusual number of processes"
          description: "{{ $value }} processes running on {{ $labels.instance }}"
```

### 5. Log Analysis

**Centralize security logs in Loki:**

Create Grafana dashboard with:
- Failed SSH attempts (grep "Failed password" /var/log/auth.log)
- Sudo usage (grep "COMMAND" /var/log/auth.log)
- Nginx errors (4xx, 5xx from access.log)
- PHP errors (from php-fpm.log)
- Database errors (from mysql/error.log)

**LogQL queries for security:**
```logql
# Failed logins
{job="varlogs", filename="/var/log/auth.log"} |= "Failed password"

# Sudo usage
{job="varlogs", filename="/var/log/auth.log"} |= "sudo" |= "COMMAND"

# 404 attacks (scanning)
{job="varlogs", filename="/var/log/nginx/access.log"} |~ "404" | line_format "{{.ip}}"

# SQL injection attempts
{job="varlogs"} |~ "(?i)(union.*select|select.*from|drop.*table)"

# XSS attempts
{job="varlogs"} |~ "(?i)(<script|javascript:|onerror=)"
```

---

## Hardening Checklist

### System Hardening

- [ ] Disable root SSH login
  ```bash
  sudo nano /etc/ssh/sshd_config
  # Set: PermitRootLogin no
  sudo systemctl restart sshd
  ```

- [ ] Disable password authentication
  ```bash
  # In /etc/ssh/sshd_config:
  PasswordAuthentication no
  ```

- [ ] Enable automatic security updates
  ```bash
  sudo apt-get install -y unattended-upgrades
  sudo dpkg-reconfigure --priority=low unattended-upgrades
  ```

- [ ] Set secure file permissions
  ```bash
  # SSH keys
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys

  # Application files
  sudo chown -R www-data:www-data /var/www/vpsmanager
  sudo chmod -R 755 /var/www/vpsmanager
  sudo chmod -R 775 /var/www/vpsmanager/storage
  sudo chmod 600 /var/www/vpsmanager/.env
  ```

- [ ] Disable unused services
  ```bash
  # List all services
  systemctl list-unit-files --type=service

  # Disable unused ones
  sudo systemctl disable SERVICE_NAME
  ```

- [ ] Remove unnecessary packages
  ```bash
  sudo apt-get autoremove
  sudo apt-get autoclean
  ```

### Network Hardening

- [ ] Configure TCP/IP stack
  ```bash
  sudo nano /etc/sysctl.conf
  ```

  ```ini
  # IP Spoofing protection
  net.ipv4.conf.all.rp_filter = 1
  net.ipv4.conf.default.rp_filter = 1

  # Ignore ICMP ping requests
  net.ipv4.icmp_echo_ignore_all = 1

  # Disable source packet routing
  net.ipv4.conf.all.accept_source_route = 0

  # Ignore send redirects
  net.ipv4.conf.all.send_redirects = 0

  # Block SYN attacks
  net.ipv4.tcp_syncookies = 1
  net.ipv4.tcp_max_syn_backlog = 2048
  net.ipv4.tcp_synack_retries = 2
  net.ipv4.tcp_syn_retries = 5

  # Log Martians
  net.ipv4.conf.all.log_martians = 1
  ```

  ```bash
  sudo sysctl -p
  ```

- [ ] Disable IPv6 (if not used)
  ```bash
  # In /etc/sysctl.conf:
  net.ipv6.conf.all.disable_ipv6 = 1
  net.ipv6.conf.default.disable_ipv6 = 1
  ```

### Application Hardening

- [ ] Configure Laravel security
  ```bash
  # In .env:
  APP_ENV=production
  APP_DEBUG=false
  SESSION_SECURE_COOKIE=true
  SESSION_HTTP_ONLY=true
  SESSION_SAME_SITE=strict
  ```

- [ ] Hide server information
  ```bash
  # Nginx
  sudo nano /etc/nginx/nginx.conf
  # Add to http block:
  server_tokens off;

  # PHP
  sudo nano /etc/php/8.4/fpm/php.ini
  # Set:
  expose_php = Off
  ```

- [ ] Configure security headers (already in SSL config)
  - X-Frame-Options: SAMEORIGIN
  - X-Content-Type-Options: nosniff
  - X-XSS-Protection: 1; mode=block
  - Referrer-Policy: no-referrer-when-downgrade
  - Content-Security-Policy (configure for your app)

### Database Hardening

- [ ] Run mysql_secure_installation
  ```bash
  sudo mysql_secure_installation
  ```

- [ ] Remove test databases
  ```bash
  sudo mysql -u root -p -e "DROP DATABASE IF EXISTS test;"
  ```

- [ ] Create app-specific database user
  ```bash
  # Not root!
  CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'strong_password';
  GRANT SELECT, INSERT, UPDATE, DELETE ON database.* TO 'appuser'@'localhost';
  ```

- [ ] Bind MySQL to localhost only
  ```bash
  # In /etc/mysql/mariadb.conf.d/50-server.cnf:
  bind-address = 127.0.0.1
  ```

### Redis Hardening

- [ ] Set Redis password
  ```bash
  sudo nano /etc/redis/redis.conf
  # Uncomment and set:
  requirepass YOUR_STRONG_PASSWORD

  sudo systemctl restart redis-server

  # Update Laravel .env:
  REDIS_PASSWORD=YOUR_STRONG_PASSWORD
  ```

- [ ] Bind Redis to localhost
  ```bash
  # In /etc/redis/redis.conf:
  bind 127.0.0.1
  ```

- [ ] Disable dangerous commands
  ```bash
  # In /etc/redis/redis.conf:
  rename-command FLUSHDB ""
  rename-command FLUSHALL ""
  rename-command KEYS ""
  rename-command CONFIG ""
  ```

---

## Security Maintenance

### Daily Tasks

- [ ] Review security logs
  ```bash
  # SSH attempts
  sudo grep "Failed password" /var/log/auth.log | tail -20

  # Sudo usage
  sudo grep "COMMAND" /var/log/auth.log | tail -20

  # Nginx errors
  sudo tail -20 /var/log/nginx/error.log
  ```

- [ ] Check for failed services
  ```bash
  systemctl --failed
  ```

- [ ] Monitor disk usage
  ```bash
  df -h
  ```

### Weekly Tasks

- [ ] Apply security updates
  ```bash
  sudo apt-get update
  sudo apt-get upgrade -y
  ```

- [ ] Review Grafana security dashboard
  - Failed login attempts
  - Unusual traffic patterns
  - Resource usage anomalies

- [ ] Check SSL certificate expiry
  ```bash
  sudo certbot certificates
  ```

### Monthly Tasks

- [ ] Review and rotate credentials
  ```bash
  # Use Laravel secrets rotation
  php artisan secrets:rotate --dry-run
  php artisan secrets:rotate --all
  ```

- [ ] Review firewall rules
  ```bash
  sudo ufw status verbose
  ```

- [ ] Review user accounts
  ```bash
  # List users
  cat /etc/passwd | grep -v nologin

  # Remove unused accounts
  sudo deluser USERNAME
  ```

- [ ] Check for rootkits
  ```bash
  sudo apt-get install -y rkhunter
  sudo rkhunter --update
  sudo rkhunter --check
  ```

### Quarterly Tasks

- [ ] Full security audit
  ```bash
  sudo lynis audit system > security-audit-$(date +%Y%m%d).txt
  ```

- [ ] Penetration testing
  - Use tools like OWASP ZAP
  - Or hire professional pentesters

- [ ] Review and update security policies
- [ ] Train team on security best practices

### Annual Tasks

- [ ] Complete infrastructure review
- [ ] Disaster recovery drill
- [ ] Compliance audit (if applicable)
- [ ] Security training certification

---

## Security Incident Response

### If You Detect a Breach

1. **Isolate affected systems**
   ```bash
   # Disable network
   sudo ufw deny out

   # Stop services
   sudo systemctl stop nginx php8.4-fpm
   ```

2. **Preserve evidence**
   ```bash
   # Copy logs
   sudo cp -r /var/log /backup/incident-$(date +%Y%m%d)/

   # Snapshot disk (if possible)
   ```

3. **Investigate**
   - Check /var/log/auth.log for unauthorized access
   - Review application logs for SQL injection, XSS
   - Check running processes: `ps aux`
   - Check network connections: `sudo netstat -tulpn`
   - Check cron jobs: `crontab -l`, `sudo crontab -l`

4. **Contain and remediate**
   - Change all passwords
   - Rotate SSH keys
   - Remove malicious code
   - Patch vulnerabilities

5. **Restore and monitor**
   - Restore from clean backup if needed
   - Monitor closely for 30 days
   - Implement additional controls

6. **Document and report**
   - Document timeline of incident
   - Report to stakeholders
   - File reports as required by regulations

---

## Security Resources

### Tools
- **Lynis** - Security auditing: https://cisofy.com/lynis/
- **AIDE** - File integrity: https://aide.github.io/
- **Fail2ban** - Intrusion prevention: https://www.fail2ban.org/
- **OWASP ZAP** - Web security scanner: https://www.zaproxy.org/

### References
- **CIS Benchmarks**: https://www.cisecurity.org/cis-benchmarks/
- **OWASP Top 10**: https://owasp.org/www-project-top-ten/
- **Let's Encrypt Docs**: https://letsencrypt.org/docs/
- **UFW Guide**: https://help.ubuntu.com/community/UFW

### Training
- **Linux Security** - Linux Foundation
- **Web Security** - OWASP
- **Cloud Security** - Cloud Security Alliance

---

## Quick Security Checklist

### Immediate (Deploy Day)

- [ ] Change default passwords (Grafana admin/admin)
- [ ] Configure firewall (UFW)
- [ ] Install SSL certificates
- [ ] Create deployment users (no root)
- [ ] Copy SSH keys (no password auth)

### First Week

- [ ] Enable 2FA for admin accounts
- [ ] Configure security monitoring alerts
- [ ] Set up fail2ban
- [ ] Run initial security audit (Lynis)
- [ ] Document security policies

### Ongoing

- [ ] Daily: Review security logs
- [ ] Weekly: Apply updates
- [ ] Monthly: Rotate credentials
- [ ] Quarterly: Security audit
- [ ] Annually: Full review

---

## Compliance Notes

### GDPR Considerations

If handling EU citizen data:
- Encrypt data at rest and in transit (SSL/TLS)
- Implement access controls (2FA)
- Log all data access (audit logs)
- Regular security assessments
- Data breach notification procedures

### PCI-DSS Considerations

If handling payment cards:
- Use TLS 1.2+ only
- Regular vulnerability scans
- Restrict access by IP
- Multi-factor authentication
- Log all access to cardholder data

### HIPAA Considerations

If handling health information:
- Encrypt data (AES-256)
- Audit all data access
- Implement access controls
- Regular risk assessments
- Business Associate Agreements

**Consult legal/compliance team for specific requirements.**

---

## Summary

Security is an ongoing process, not a one-time setup:

1. **Deploy with security** - SSL, firewall, strong passwords
2. **Monitor actively** - Logs, alerts, dashboards
3. **Update regularly** - Patches, credentials, certificates
4. **Test frequently** - Audits, scans, penetration tests
5. **Respond quickly** - Incident response plan

**Remember**: The weakest link determines your security posture. Stay vigilant!

---

**Last Updated:** 2025-12-30

**Related Documentation:**
- [QUICK-START.md](./QUICK-START.md) - Deployment guide
- [README.md](./README.md) - Comprehensive documentation
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Problem solving
- [/docs/security/SECURITY-QUICK-REFERENCE.md](/home/calounx/repositories/mentat/chom/docs/security/SECURITY-QUICK-REFERENCE.md) - Application 2FA
