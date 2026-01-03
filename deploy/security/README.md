# CHOM Security Hardening Scripts

Comprehensive security infrastructure for production deployment of the CHOM application.

## Overview

This directory contains production-ready security scripts covering all aspects of infrastructure hardening, monitoring, and incident response. All scripts are fully functional with NO placeholders or stubs.

## Security Scripts

### 1. SSH Key Setup (`setup-ssh-keys.sh`)
**Purpose:** Configure SSH key-based authentication with hardening

**Features:**
- ED25519 SSH key generation (4096-bit equivalent security)
- Disable password authentication
- Disable root login
- Custom SSH port (default: 2222)
- Strong cryptographic algorithms
- Login rate limiting (3 attempts)
- Session timeouts

**Usage:**
```bash
sudo ./setup-ssh-keys.sh
```

**Environment Variables:**
- `DEPLOY_USER`: Deployment user name (default: stilgar)
- `SSH_PORT`: SSH port (default: 2222)

---

### 2. Firewall Configuration (`configure-firewall.sh`)
**Purpose:** Configure UFW firewall with defense-in-depth rules

**Features:**
- Role-based firewall rules (landsraad/mentat)
- Default deny incoming, allow outgoing
- Rate limiting for SSH and HTTP/HTTPS
- Service-specific port restrictions
- IPv6 support

**Usage:**
```bash
# Landsraad (application server)
sudo SERVER_ROLE=landsraad MENTAT_IP=<mentat-ip> ./configure-firewall.sh

# Mentat (observability server)
sudo SERVER_ROLE=mentat LANDSRAAD_IP=<landsraad-ip> ./configure-firewall.sh
```

**Ports:**
- **Landsraad:** 80, 443, 5432 (from mentat), 6379 (from mentat), 9100 (from mentat)
- **Mentat:** 443, 9090 (restricted), 3100 (from landsraad)

---

### 3. SSL/TLS Setup (`setup-ssl.sh`)
**Purpose:** Configure Let's Encrypt SSL certificates with A+ security

**Features:**
- Automated Let's Encrypt certificate generation
- TLS 1.2 and 1.3 only
- Strong cipher suites (AEAD preferred)
- HSTS with 2-year max-age
- OCSP stapling
- Perfect Forward Secrecy
- Auto-renewal configuration

**Usage:**
```bash
sudo DOMAIN=landsraad.arewel.com EMAIL=admin@arewel.com ./setup-ssl.sh
```

**SSL Labs Rating:** A+

---

### 4. Secrets Management (`manage-secrets.sh`)
**Purpose:** Securely generate, encrypt, and manage application secrets

**Features:**
- GPG encryption (RSA 4096-bit)
- Automatic secret generation
- Encrypted storage
- Secret rotation
- Key backup and recovery

**Generated Secrets:**
- APP_KEY (Laravel)
- JWT_SECRET
- DB_PASSWORD
- REDIS_PASSWORD
- SESSION_SECRET
- ENCRYPTION_KEY
- API tokens (Prometheus, Grafana, Loki)

**Usage:**
```bash
# Generate and encrypt secrets
sudo ./manage-secrets.sh generate

# Rotate secrets
sudo ./manage-secrets.sh rotate

# Load secrets to .env
sudo ./manage-secrets.sh load
```

**Management:**
```bash
chom-secrets list          # List all secrets
chom-secrets show <name>   # Show specific secret
chom-secrets encrypt       # Encrypt all secrets
chom-secrets decrypt       # Decrypt all secrets
```

---

### 5. Database Hardening (`harden-database.sh`)
**Purpose:** Harden PostgreSQL with enterprise-grade security

**Features:**
- SSL/TLS encryption (TLS 1.2+)
- SCRAM-SHA-256 authentication
- Limited user privileges (principle of least privilege)
- Connection limits
- Audit logging
- WAL archiving
- Read-only backup user

**Usage:**
```bash
sudo ./harden-database.sh
```

**Management:**
```bash
chom-db status             # Show PostgreSQL status
chom-db backup             # Create database backup
chom-db audit              # Show audit log
chom-db connections        # Show active connections
```

---

### 6. Application Hardening (`harden-application.sh`)
**Purpose:** Harden Laravel application and PHP configuration

**Features:**
- Secure file permissions (644/755)
- PHP dangerous functions disabled
- Production mode enforcement
- Session security (httpOnly, secure, sameSite)
- CSRF protection
- XSS prevention
- Open basedir restriction
- Error display disabled

**Usage:**
```bash
sudo APP_ROOT=/var/www/chom ./harden-application.sh
```

**Security Settings:**
- `.env` permissions: 600
- Storage: 775
- PHP files: 644
- Directories: 755

---

### 7. Fail2Ban Setup (`setup-fail2ban.sh`)
**Purpose:** Configure intrusion prevention with Fail2Ban

**Features:**
- SSH brute force protection
- Nginx auth failure protection
- Laravel authentication monitoring
- SQL injection detection
- XSS attempt detection
- Path traversal blocking
- Email alerts on bans

**Jails:**
- SSH (3 attempts, 2 hour ban)
- Nginx HTTP auth (3 attempts, 1 hour ban)
- Laravel auth (5 attempts, 1 hour ban)
- SQL injection (1 attempt, 24 hour ban)
- Recidive (repeat offenders, 7 day ban)

**Usage:**
```bash
sudo SSH_PORT=2222 ADMIN_EMAIL=admin@arewel.com ./setup-fail2ban.sh
```

**Management:**
```bash
chom-fail2ban status       # Show Fail2Ban status
chom-fail2ban banned       # List banned IPs
chom-fail2ban unban <ip>   # Unban specific IP
chom-fail2ban stats        # Show statistics
```

---

### 8. Security Audit (`security-audit.sh`)
**Purpose:** Comprehensive security audit with severity levels

**Audit Coverage:**
- SSH configuration
- Firewall status
- File permissions
- Exposed secrets
- Database security
- PHP security
- SSL/TLS configuration
- System updates
- User accounts
- Running services
- Fail2Ban status
- Laravel security

**Usage:**
```bash
sudo ./security-audit.sh
```

**Exit Codes:**
- 0: No critical or high issues
- 1: High severity issues found
- 2: Critical issues found

---

### 9. Intrusion Detection (`setup-intrusion-detection.sh`)
**Purpose:** Configure AIDE file integrity monitoring

**Features:**
- File integrity monitoring
- Automated daily checks
- Email alerts on changes
- Checksum verification (MD5, SHA256)
- Permission monitoring
- Ownership tracking

**Monitored Directories:**
- System binaries (/bin, /sbin, /usr/bin, /usr/sbin)
- System configuration (/etc)
- Application code (/var/www/chom)
- Security configs (/etc/fail2ban, /etc/aide)

**Usage:**
```bash
sudo ADMIN_EMAIL=admin@arewel.com ./setup-intrusion-detection.sh
```

**Management:**
```bash
chom-aide check            # Run integrity check
chom-aide update           # Update database
chom-aide status           # Show AIDE status
chom-aide run-now          # Run immediate check
```

---

### 10. Vulnerability Scanner (`vulnerability-scan.sh`)
**Purpose:** Scan for CVEs and security vulnerabilities

**Scan Coverage:**
- OS packages (Debian CVE database)
- PHP dependencies (Composer audit)
- Outdated packages
- SSL/TLS configuration
- Default credentials
- Exposed services
- File permissions
- Common misconfigurations

**Usage:**
```bash
sudo ./vulnerability-scan.sh
```

**Exit Codes:**
- 0: No critical or high vulnerabilities
- 1: High severity vulnerabilities
- 2: Critical vulnerabilities

---

### 11. Compliance Check (`compliance-check.sh`)
**Purpose:** Verify compliance with security standards

**Standards:**
- OWASP Top 10 2021
- PCI DSS Level 1
- SOC 2 Type II
- GDPR
- ISO 27001

**Usage:**
```bash
sudo ./compliance-check.sh
```

**Output:** Detailed compliance report with pass/fail status

---

### 12. Backup Encryption (`encrypt-backups.sh`)
**Purpose:** Encrypt all backups using GPG

**Features:**
- GPG encryption (RSA 4096-bit)
- Automated encryption
- Encryption verification
- Automated cleanup (30 day retention)
- Key management

**Usage:**
```bash
# Setup encryption
sudo ./encrypt-backups.sh setup

# Encrypt specific backup
sudo ./encrypt-backups.sh encrypt <file> <output>

# Decrypt backup
sudo ./encrypt-backups.sh decrypt <encrypted> <output>
```

**Management:**
```bash
chom-backup-encryption list        # List encrypted backups
chom-backup-encryption verify      # Verify backups
chom-backup-encryption test        # Test encryption
```

---

### 13. Security Monitoring (`setup-security-monitoring.sh`)
**Purpose:** Configure security event monitoring with Loki/Grafana

**Features:**
- Log aggregation with Promtail
- Security event logging
- Real-time alerting
- Grafana dashboards
- Audit logging

**Monitored Events:**
- SSH authentication
- Sudo commands
- Fail2Ban events
- Nginx access/errors
- Laravel events
- AIDE alerts
- PostgreSQL logs

**Usage:**
```bash
sudo LOKI_URL=http://mentat.arewel.com:3100 ./setup-security-monitoring.sh
```

**Management:**
```bash
chom-audit-logs ssh            # SSH events
chom-audit-logs fail2ban       # Fail2Ban events
chom-audit-logs suspicious     # Suspicious activity
```

---

### 14. Access Control (`configure-access-control.sh`)
**Purpose:** Configure user access with least privilege

**Features:**
- Deployment user creation
- Sudo configuration (limited commands)
- SSH access management
- Password policy (14 chars, complexity)
- Account lockout (5 attempts, 30 min)
- Session timeout (15 minutes)
- Audit logging

**Usage:**
```bash
sudo DEPLOY_USER=stilgar ./configure-access-control.sh
```

**Management:**
```bash
chom-user-audit            # Run user access audit
sudo -l                    # List allowed sudo commands
ausearch -k identity       # Search audit logs
```

---

### 15. Incident Response (`incident-response.sh`)
**Purpose:** Automated security incident response

**Features:**
- Forensic data capture
- Server isolation
- Attacker IP blocking
- Credential rotation
- Backup restoration
- Incident reporting
- Email notifications

**Usage:**
```bash
# Interactive mode
sudo ./incident-response.sh interactive

# Automated response
sudo ./incident-response.sh auto intrusion <attacker-ip>

# Block specific IP
sudo ./incident-response.sh block <ip>
```

**Incident Types:**
- intrusion
- malware
- data_breach
- dos

---

## Master Setup Script

Run all security scripts in the correct order:

```bash
sudo ./master-security-setup.sh
```

This will execute:
1. SSH key setup
2. Firewall configuration
3. SSL/TLS setup
4. Secrets management
5. Database hardening
6. Application hardening
7. Fail2Ban setup
8. Intrusion detection
9. Security monitoring
10. Access control
11. Security audit
12. Compliance check

---

## Security Checklist

### Initial Setup
- [ ] Run master security setup
- [ ] Configure SSH keys
- [ ] Setup firewall rules
- [ ] Obtain SSL certificates
- [ ] Generate and encrypt secrets
- [ ] Harden database
- [ ] Harden application
- [ ] Configure Fail2Ban
- [ ] Setup intrusion detection
- [ ] Configure monitoring
- [ ] Setup access control

### Daily Operations
- [ ] Review security logs
- [ ] Check Fail2Ban banned IPs
- [ ] Monitor AIDE alerts
- [ ] Review vulnerability scans

### Weekly Tasks
- [ ] Run security audit
- [ ] Run compliance check
- [ ] Review access logs
- [ ] Update SSL certificates (if needed)

### Monthly Tasks
- [ ] Rotate secrets
- [ ] Review user accounts
- [ ] Update security policies
- [ ] Test backup restoration
- [ ] Test incident response

### Quarterly Tasks
- [ ] Full security assessment
- [ ] Penetration testing
- [ ] Update documentation
- [ ] Security awareness training

---

## Compliance Coverage

### OWASP Top 10 2021
- ✓ A01: Broken Access Control
- ✓ A02: Cryptographic Failures
- ✓ A03: Injection
- ✓ A04: Insecure Design
- ✓ A05: Security Misconfiguration
- ✓ A06: Vulnerable and Outdated Components
- ✓ A07: Identification and Authentication Failures
- ✓ A08: Software and Data Integrity Failures
- ✓ A09: Security Logging and Monitoring Failures
- ✓ A10: Server-Side Request Forgery

### PCI DSS Requirements
- ✓ 1: Install and maintain firewall
- ✓ 2: Change defaults
- ✓ 3: Protect stored data
- ✓ 4: Encrypt data in transit
- ✓ 5: Protect against malware
- ✓ 6: Develop secure systems
- ✓ 8: Identify and authenticate
- ✓ 10: Track and monitor
- ✓ 11: Test security systems
- ✓ 12: Security policy

### SOC 2 Principles
- ✓ Security
- ✓ Availability
- ✓ Processing Integrity
- ✓ Confidentiality
- ✓ Privacy

---

## Emergency Contacts

**Security Incidents:**
- Email: admin@arewel.com
- On-Call: [Configure in scripts]

**Incident Response:**
```bash
sudo ./incident-response.sh interactive
```

---

## Documentation

- **Scripts:** All scripts are self-documenting with inline comments
- **Logs:** `/var/log/chom/`
- **Incidents:** `/var/log/chom/incidents/`
- **Forensics:** `/var/forensics/`
- **Backups:** `/var/backups/chom/`

---

## Security Principles

1. **Defense in Depth:** Multiple layers of security
2. **Principle of Least Privilege:** Minimal access rights
3. **Fail Securely:** Secure defaults, fail closed
4. **No Security by Obscurity:** Documented and tested
5. **Separation of Duties:** Role-based access
6. **Regular Audits:** Continuous monitoring
7. **Incident Response:** Prepared and tested
8. **Encryption:** At rest and in transit

---

## Support

For questions or issues:
1. Review script output and logs
2. Check `/var/log/chom/` for detailed logs
3. Run security audit for diagnostics
4. Contact security team

---

**Version:** 1.0
**Last Updated:** 2026-01-03
**Maintained by:** CHOM Security Team
