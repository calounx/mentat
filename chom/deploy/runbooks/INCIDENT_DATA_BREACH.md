# Incident Runbook: Data Breach / Security Incident

**Severity:** SEV1 (Critical)
**Impact:** Data confidentiality, integrity, availability compromised
**Expected Resolution Time:** 1-4 hours (initial response)

⚠️  **CRITICAL: This is a security incident. Follow procedures exactly.**

## Detection
- Alert: `UnauthorizedAccess`
- Alert: `SuspiciousActivity`
- IDS/IPS triggers
- Unusual authentication patterns
- Unexpected file modifications
- User reports of compromised accounts

## IMMEDIATE ACTIONS (First 5 Minutes)

### 1. Activate Incident Response Team
```bash
# Send alert to security channel
# Contact: Security Lead, CTO, Legal
# Do NOT communicate details publicly
```

### 2. Preserve Evidence
```bash
# DO NOT RESTART OR SHUTDOWN SYSTEMS YET
# Capture current state first

ssh deploy@landsraad.arewel.com << 'EOF'
INCIDENT_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p /forensics/${INCIDENT_ID}

# Capture running processes
ps auxf > /forensics/${INCIDENT_ID}/processes.txt

# Capture network connections
ss -tunap > /forensics/${INCIDENT_ID}/network.txt
netstat -tulpn > /forensics/${INCIDENT_ID}/netstat.txt

# Capture Docker state
docker ps -a > /forensics/${INCIDENT_ID}/docker-ps.txt
docker logs chom-app > /forensics/${INCIDENT_ID}/app-logs.txt
docker logs chom-nginx > /forensics/${INCIDENT_ID}/nginx-logs.txt

# Capture authentication logs
cp /var/log/auth.log /forensics/${INCIDENT_ID}/
cp -r /opt/chom/storage/logs /forensics/${INCIDENT_ID}/

# Database snapshot
docker exec chom-mysql mysqldump --all-databases | gzip > /forensics/${INCIDENT_ID}/db-snapshot.sql.gz

# File integrity snapshot
find /opt/chom -type f -ls > /forensics/${INCIDENT_ID}/file-listing.txt

# Create archive
tar czf /forensics/incident-${INCIDENT_ID}.tar.gz /forensics/${INCIDENT_ID}/
EOF

# Copy evidence off-server immediately
scp deploy@landsraad.arewel.com:/forensics/incident-*.tar.gz /secure/forensics/
```

### 3. Assess Breach Scope
```bash
# Check for unauthorized users
ssh deploy@landsraad.arewel.com "cat /etc/passwd | grep -E 'bash|sh$'"
ssh deploy@landsraad.arewel.com "cat /home/*/.ssh/authorized_keys"

# Check for unauthorized processes
ssh deploy@landsraad.arewel.com "ps aux | grep -vE 'php|nginx|mysql|redis|docker'"

# Check for outbound connections
ssh deploy@landsraad.arewel.com "lsof -i | grep ESTABLISHED"

# Check recent file modifications
ssh deploy@landsraad.arewel.com "find /opt/chom -type f -mtime -1 -ls"

# Check database for unauthorized access
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  SELECT user, host, last_login
  FROM mysql.user;
"
EOF
```

## CONTAINMENT (Next 15 Minutes)

### 4. Isolate Affected Systems
```bash
# If breach confirmed, ISOLATE immediately
ssh deploy@landsraad.arewel.com << 'EOF'
# Block all incoming traffic except your IP
ufw default deny incoming
ufw allow from YOUR_IP_ADDRESS to any port 22

# Or complete isolation if severe
# ufw deny in from any
EOF

# Enable maintenance mode
ssh deploy@landsraad.arewel.com "docker exec chom-app php artisan down --secret=incident-response-token"

# Access application via secret token for investigation:
# https://landsraad.arewel.com/incident-response-token
```

### 5. Stop Data Exfiltration
```bash
# Monitor outbound traffic
ssh deploy@landsraad.arewel.com << 'EOF'
# Block all outbound except essential
ufw default deny outgoing
ufw allow out to any port 53  # DNS
ufw allow out to any port 80  # HTTP
ufw allow out to any port 443 # HTTPS
ufw allow out to 51.254.139.78  # Monitoring server
ufw reload
EOF
```

## INVESTIGATION (Next 30-60 Minutes)

### 6. Identify Attack Vector
```bash
# Check for web shells
ssh deploy@landsraad.arewel.com << 'EOF'
find /opt/chom -name "*.php" -type f -exec grep -l "eval\|base64_decode\|system\|exec\|shell_exec" {} \;
EOF

# Check for SQL injection in logs
ssh deploy@landsraad.arewel.com << 'EOF'
grep -E "UNION.*SELECT|' OR '1'='1|;DROP|;DELETE|;UPDATE" /opt/chom/storage/logs/laravel.log
EOF

# Check for unauthorized code changes
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
git status
git diff HEAD
EOF

# Check for malicious cron jobs
ssh deploy@landsraad.arewel.com "crontab -l"

# Check for rootkits
ssh deploy@landsraad.arewel.com "rkhunter --check"
```

### 7. Determine Data Exposure
```bash
# Check database access logs
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  SELECT * FROM information_schema.processlist;
  SHOW BINARY LOGS;
"
EOF

# Check for data dumps
ssh deploy@landsraad.arewel.com "find / -name '*.sql' -mtime -7 -ls"

# Identify which tables/data may be compromised
# Priority: users, passwords, payment info, PII
```

## ERADICATION (Next 1-2 Hours)

### 8. Remove Malicious Code/Access
```bash
# Remove unauthorized users
ssh deploy@landsraad.arewel.com << 'EOF'
# Review and remove suspicious users
userdel -r SUSPICIOUS_USER
EOF

# Remove unauthorized SSH keys
ssh deploy@landsraad.arewel.com << 'EOF'
# Review all authorized_keys files
find /home -name authorized_keys -exec cat {} \;
# Remove unauthorized entries
EOF

# Remove web shells
ssh deploy@landsraad.arewel.com << 'EOF'
# Delete identified malicious files
rm /path/to/webshell.php
EOF

# Clean database
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  -- Remove unauthorized admin users if found
  DELETE FROM users WHERE email = 'malicious@attacker.com';
"
EOF
```

### 9. Patch Vulnerabilities
```bash
# Update all software
ssh deploy@landsraad.arewel.com << 'EOF'
apt-get update && apt-get upgrade -y
docker compose -f /opt/chom/docker-compose.production.yml pull
docker compose -f /opt/chom/docker-compose.production.yml up -d
EOF

# Apply security patches
# Fix identified vulnerability (SQL injection, XSS, etc.)
# Deploy patched code
```

### 10. Rotate ALL Credentials
```bash
# Database passwords
ssh deploy@landsraad.arewel.com << 'EOF'
NEW_DB_PASS=$(openssl rand -base64 32)
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  ALTER USER 'chom'@'%' IDENTIFIED BY '${NEW_DB_PASS}';
  FLUSH PRIVILEGES;
"
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${NEW_DB_PASS}/" /opt/chom/.env
EOF

# Application keys
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/chom
docker exec chom-app php artisan key:generate --force
EOF

# SSH keys
ssh-keygen -t ed25519 -f ~/.ssh/chom_deploy_new -N ""
ssh-copy-id -i ~/.ssh/chom_deploy_new deploy@landsraad.arewel.com
# Remove old keys after verifying new one works

# API tokens - REVOKE ALL
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
  TRUNCATE TABLE personal_access_tokens;
"
EOF

# Force all users to reset passwords
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-app php artisan tinker --execute="
  \App\Models\User::query()->update(['password' => null, 'must_reset_password' => true]);
"
EOF
```

## RECOVERY (Next 1-2 Hours)

### 11. Restore from Clean Backup
```bash
# Restore from last known clean backup (before breach)
ssh deploy@landsraad.arewel.com << 'EOF'
cd /opt/backups/chom
./restore-chom.sh --timestamp 2026-01-01-120000 --verify
EOF

# Apply only verified changes since backup
# Do NOT restore any files/data from breached period
```

### 12. Strengthen Security
```bash
# Enhanced firewall rules
ssh deploy@landsraad.arewel.com << 'EOF'
ufw reset
ufw default deny incoming
ufw default deny outgoing
ufw allow out 53/udp  # DNS
ufw allow out 80/tcp  # HTTP
ufw allow out 443/tcp # HTTPS
ufw allow from TRUSTED_IP to any port 22
ufw enable
EOF

# Enhanced fail2ban
ssh deploy@landsraad.arewel.com << 'EOF'
cat > /etc/fail2ban/jail.d/hardened.conf << 'F2B'
[DEFAULT]
bantime = 86400
maxretry = 3
findtime = 600

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-noscript]
enabled = true

[nginx-badbots]
enabled = true
F2B

systemctl restart fail2ban
EOF

# Enable audit logging
ssh deploy@landsraad.arewel.com << 'EOF'
apt-get install -y auditd
auditctl -w /opt/chom -p wa -k chom_changes
auditctl -w /etc/passwd -p wa -k passwd_changes
systemctl enable auditd
EOF
```

### 13. Resume Service
```bash
# Verify system clean
./deploy/disaster-recovery/scripts/health-check.sh --mode security

# Disable maintenance mode
ssh deploy@landsraad.arewel.com "docker exec chom-app php artisan up"

# Monitor closely for 24 hours
watch -n 300 './deploy/disaster-recovery/scripts/health-check.sh --mode full'
```

## NOTIFICATION & COMPLIANCE

### 14. Notify Stakeholders
```bash
# Internal notification (immediate)
# - CTO, CEO
# - Legal team
# - All engineering staff
# - Customer support team

# External notification (if PII exposed)
# - Affected customers (within 72 hours per GDPR)
# - Data protection authority
# - Law enforcement (if criminal)

# Template communication:
# "On [DATE], we discovered unauthorized access to our systems.
#  We have contained the incident and taken steps to prevent recurrence.
#  [Specific impact to users if any]
#  We are working with security experts and will provide updates."
```

## POST-INCIDENT

### 15. Forensic Analysis
- Hire external security firm if breach is severe
- Conduct full post-mortem
- Document attack timeline
- Identify all vulnerabilities exploited

### 16. Regulatory Compliance
- GDPR: Report within 72 hours if EU data affected
- Document all actions taken
- Preserve evidence for investigation
- Consult legal team

### 17. Long-term Improvements
- Penetration testing
- Security audit
- Code review
- Security training for team
- Implement WAF
- Enhanced monitoring
- Incident response drills

---

## Legal & Compliance Contacts

**Legal Team:** legal@company.com
**Data Protection Officer:** dpo@company.com
**Cyber Insurance:** policy-number-here
**Security Firm:** [Retained firm contact]

---

**Version:** 1.0 | **Updated:** 2026-01-02
**Classification:** CONFIDENTIAL - Incident Response Team Only
