# CHOM Security Quick Start Guide

## One-Command Setup

Deploy complete security infrastructure in one command:

```bash
cd /home/calounx/repositories/mentat/deploy/security
sudo ./master-security-setup.sh
```

This will configure:
- SSH key authentication
- Firewall rules
- SSL/TLS certificates
- Secrets encryption
- Database hardening
- Application hardening
- Intrusion prevention
- File integrity monitoring
- Security monitoring
- Access control
- Compliance validation

**Duration:** 20-30 minutes
**Requires:** Root access, internet connection

---

## Individual Components

### 1. SSH Hardening (3 minutes)
```bash
sudo DEPLOY_USER=stilgar SSH_PORT=2222 ./setup-ssh-keys.sh
```
**Result:** SSH key-only authentication, password auth disabled

### 2. Firewall (2 minutes)
```bash
# Landsraad (application server)
sudo SERVER_ROLE=landsraad MENTAT_IP=<ip> ./configure-firewall.sh

# Mentat (observability server)
sudo SERVER_ROLE=mentat LANDSRAAD_IP=<ip> ./configure-firewall.sh
```
**Result:** UFW active with role-based rules

### 3. SSL Certificates (5 minutes)
```bash
sudo DOMAIN=landsraad.arewel.com EMAIL=admin@arewel.com ./setup-ssl.sh
```
**Result:** Let's Encrypt certificate, A+ rating, auto-renewal

### 4. Secrets Management (3 minutes)
```bash
sudo ./manage-secrets.sh generate
```
**Result:** All secrets generated and GPG encrypted

### 5. Database Security (4 minutes)
```bash
sudo ./harden-database.sh
```
**Result:** PostgreSQL with SSL, SCRAM-SHA-256, audit logging

### 6. Application Security (3 minutes)
```bash
sudo APP_ROOT=/var/www/chom ./harden-application.sh
```
**Result:** Laravel production mode, PHP hardened, secure permissions

### 7. Fail2Ban (3 minutes)
```bash
sudo SSH_PORT=2222 ADMIN_EMAIL=admin@arewel.com ./setup-fail2ban.sh
```
**Result:** Intrusion prevention for SSH, Nginx, Laravel

### 8. File Integrity (5 minutes)
```bash
sudo ADMIN_EMAIL=admin@arewel.com ./setup-intrusion-detection.sh
```
**Result:** AIDE monitoring with daily checks

### 9. Security Monitoring (5 minutes)
```bash
sudo LOKI_URL=http://mentat.arewel.com:3100 ./setup-security-monitoring.sh
```
**Result:** Promtail sending logs to Loki/Grafana

### 10. Access Control (3 minutes)
```bash
sudo DEPLOY_USER=stilgar ./configure-access-control.sh
```
**Result:** User access with least privilege, password policy

---

## Daily Commands

### Check Security Status
```bash
# View all banned IPs
chom-fail2ban banned

# Check recent SSH logins
chom-audit-logs ssh

# View suspicious activity
chom-audit-logs suspicious

# Check SSL certificate expiry
chom-ssl expiry landsraad.arewel.com

# View firewall status
chom-firewall status
```

### Quick Security Audit
```bash
sudo /home/calounx/repositories/mentat/deploy/security/security-audit.sh
```
**Duration:** 2-3 minutes
**Output:** Security issues by severity

---

## Emergency Procedures

### Security Incident
```bash
# Interactive incident response
sudo /home/calounx/repositories/mentat/deploy/security/incident-response.sh interactive
```

### Block Attacker IP
```bash
sudo /home/calounx/repositories/mentat/deploy/security/incident-response.sh block 192.168.1.100
```

### Rotate All Credentials
```bash
sudo chom-secrets rotate
```

---

## Weekly Tasks

### Security Audit (2 minutes)
```bash
sudo /home/calounx/repositories/mentat/deploy/security/security-audit.sh
```

### Vulnerability Scan (5 minutes)
```bash
sudo /home/calounx/repositories/mentat/deploy/security/vulnerability-scan.sh
```

### Compliance Check (3 minutes)
```bash
sudo /home/calounx/repositories/mentat/deploy/security/compliance-check.sh
```

### User Audit (1 minute)
```bash
sudo chom-user-audit
```

---

## Management Helpers

All scripts create convenient management commands:

| Command | Purpose |
|---------|---------|
| `chom-secrets` | Secrets management |
| `chom-firewall` | Firewall management |
| `chom-ssl` | SSL certificate management |
| `chom-db` | Database management |
| `chom-fail2ban` | Fail2Ban management |
| `chom-aide` | File integrity monitoring |
| `chom-audit-logs` | Security log analysis |
| `chom-user-audit` | User access audit |
| `chom-backup-encryption` | Backup encryption |

### Examples
```bash
# Secrets
chom-secrets list
chom-secrets show app_key
chom-secrets rotate

# Firewall
chom-firewall status
chom-firewall allow-ip 10.0.0.50
chom-firewall list

# SSL
chom-ssl status
chom-ssl renew
chom-ssl expiry landsraad.arewel.com

# Database
chom-db backup
chom-db restore backup_20260103.sql.gz
chom-db audit

# Fail2Ban
chom-fail2ban status
chom-fail2ban banned
chom-fail2ban unban 192.168.1.100

# AIDE
chom-aide check
chom-aide update
chom-aide status

# Audit Logs
chom-audit-logs ssh
chom-audit-logs fail2ban
chom-audit-logs suspicious

# User Audit
chom-user-audit

# Backup Encryption
chom-backup-encryption list
chom-backup-encryption verify
chom-backup-encryption test
```

---

## Configuration Files

### Environment Variables
Set these before running scripts:

```bash
export DEPLOY_USER="stilgar"
export SSH_PORT="2222"
export DOMAIN="landsraad.arewel.com"
export EMAIL="admin@arewel.com"
export SERVER_ROLE="landsraad"  # or "mentat"
export MENTAT_IP="<mentat-server-ip>"
export LANDSRAAD_IP="<landsraad-server-ip>"
```

### Important Paths

| Path | Purpose |
|------|---------|
| `/etc/chom/secrets/` | Encrypted secrets storage |
| `/var/backups/chom/` | Backup storage |
| `/var/log/chom/` | Security logs and reports |
| `/etc/aide/aide.conf` | File integrity config |
| `/etc/fail2ban/jail.local` | Fail2Ban configuration |
| `/etc/ssh/sshd_config` | SSH configuration |
| `/etc/ufw/` | Firewall rules |
| `/etc/nginx/sites-enabled/` | Nginx SSL config |

---

## Post-Installation Checklist

### Immediate (Day 1)
- [ ] Test SSH key authentication
- [ ] Verify you can still connect
- [ ] Add public key to authorized_keys
- [ ] Test sudo access
- [ ] Verify SSL certificate (https://www.ssllabs.com/ssltest/)
- [ ] Check firewall rules don't block legitimate traffic
- [ ] Test Fail2Ban with failed login attempt
- [ ] Verify monitoring dashboards show data

### Short-term (Week 1)
- [ ] Review security audit results
- [ ] Address any critical/high issues
- [ ] Test backup encryption/decryption
- [ ] Verify AIDE baseline is correct
- [ ] Test incident response procedures
- [ ] Document any custom configurations
- [ ] Train team on security tools

### Ongoing
- [ ] Daily: Review security logs
- [ ] Weekly: Run security audit
- [ ] Monthly: Rotate secrets
- [ ] Quarterly: Full security assessment

---

## Troubleshooting

### Can't SSH after setup
1. Use console access (Proxmox/VPS panel)
2. Check `/etc/ssh/sshd_config`
3. Verify authorized_keys: `/home/stilgar/.ssh/authorized_keys`
4. Check firewall: `ufw status`
5. Check Fail2Ban: `chom-fail2ban status`

### Firewall blocking legitimate traffic
```bash
# Temporarily allow IP
sudo ufw allow from <ip>

# Check rules
sudo ufw status numbered

# Delete rule by number
sudo ufw delete <number>
```

### SSL certificate issues
```bash
# Check certificate status
chom-ssl status

# Test renewal
sudo certbot renew --dry-run

# Check Nginx config
sudo nginx -t

# View Nginx error log
sudo tail -f /var/log/nginx/error.log
```

### Fail2Ban banned legitimate user
```bash
# Check banned IPs
chom-fail2ban banned

# Unban specific IP
sudo chom-fail2ban unban <ip>

# Add to whitelist
sudo chom-fail2ban whitelist <ip>
```

### AIDE false positives
```bash
# Update baseline after authorized changes
sudo chom-aide update

# Check what changed
sudo chom-aide check
```

---

## Support

### Documentation
- **Full README:** `/home/calounx/repositories/mentat/deploy/security/README.md`
- **Implementation Summary:** `/home/calounx/repositories/mentat/deploy/SECURITY_IMPLEMENTATION_SUMMARY.md`
- **This Guide:** `/home/calounx/repositories/mentat/deploy/security/QUICK_START.md`

### Logs
- **Master Setup:** `/var/log/chom/master-security-setup.log`
- **Security Audits:** `/var/log/chom/security-audits/`
- **Vulnerability Scans:** `/var/log/chom/vulnerability-scans/`
- **Incidents:** `/var/log/chom/incidents/`

### Emergency Contact
- **Email:** admin@arewel.com
- **Incident Response:** `sudo ./incident-response.sh interactive`

---

## Quick Reference Card

```
╔══════════════════════════════════════════════════════════════╗
║                  CHOM Security Quick Reference                ║
╠══════════════════════════════════════════════════════════════╣
║ SETUP                                                         ║
║  Full:        sudo ./master-security-setup.sh                ║
║                                                              ║
║ DAILY CHECKS                                                 ║
║  Banned IPs:  chom-fail2ban banned                          ║
║  SSH Logs:    chom-audit-logs ssh                           ║
║  Suspicious:  chom-audit-logs suspicious                    ║
║                                                              ║
║ WEEKLY TASKS                                                 ║
║  Audit:       sudo ./security-audit.sh                      ║
║  Vuln Scan:   sudo ./vulnerability-scan.sh                  ║
║  Compliance:  sudo ./compliance-check.sh                    ║
║                                                              ║
║ EMERGENCY                                                    ║
║  Incident:    sudo ./incident-response.sh interactive       ║
║  Block IP:    sudo ./incident-response.sh block <ip>        ║
║  Rotate:      sudo chom-secrets rotate                      ║
║                                                              ║
║ MANAGEMENT                                                   ║
║  Secrets:     chom-secrets <list|show|rotate>               ║
║  Firewall:    chom-firewall <status|list>                   ║
║  SSL:         chom-ssl <status|renew|expiry>                ║
║  Database:    chom-db <backup|restore|audit>                ║
║  Fail2Ban:    chom-fail2ban <status|banned|unban>           ║
║  AIDE:        chom-aide <check|update|status>               ║
╚══════════════════════════════════════════════════════════════╝
```

---

**Last Updated:** 2026-01-03
**Version:** 1.0
**Status:** Production Ready ✅
