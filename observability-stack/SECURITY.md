# Observability Stack - Security Guide

> For general security policy, vulnerability reporting, and best practices, see the [main Security Policy](../SECURITY.md).

This document covers security considerations specific to the Observability Stack deployment and operations.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 4.0.x   | :white_check_mark: |
| 3.0.x   | :white_check_mark: |
| < 3.0   | :x:                |

## Reporting Vulnerabilities

**Please use the unified reporting procedure outlined in [../SECURITY.md](../SECURITY.md#reporting-a-vulnerability).**

For Observability Stack-specific vulnerabilities, include:
- Component/script affected (e.g., `setup-observability.sh`)
- Steps to reproduce
- Impact assessment

---

## Secrets Management

### Built-in Encryption System

The Observability Stack uses systemd credentials for secure secrets storage:

```bash
# Initialize secrets securely
./scripts/init-secrets.sh

# Secrets are stored encrypted at:
/opt/observability-stack/secrets/

# Reference secrets in config files:
${SECRET:grafana_admin_password}
${SECRET:smtp_password}
```

### What Should Be Secret

**NEVER commit to repository:**
- API keys and tokens
- Passwords (Grafana, SMTP, HTTP Basic Auth)
- Private keys and certificates
- Domain names (use placeholders in examples)
- Email addresses (use examples in templates)
- `config/global.yaml` with real values

**Secure file permissions:**
```bash
# Secrets directory permissions
chmod 700 /opt/observability-stack/secrets/
chmod 600 /opt/observability-stack/secrets/*

# Config file permissions (if contains sensitive data)
chmod 600 config/global.yaml
```

### Secrets Rotation

To rotate secrets:

```bash
# 1. Update the secret file
sudo nano /opt/observability-stack/secrets/grafana_admin_password

# 2. Reload the affected service
sudo systemctl reload grafana-server

# 3. Update Grafana UI password
# Log into Grafana and update in Settings > Profile
```

### Configuration Validation

**Check your configuration before deployment:**

```bash
# Validate configuration
./scripts/validate-config.sh

# Look for placeholders
grep -r "CHANGE_ME\|YOUR_\|EXAMPLE" config/

# Check file permissions
ls -la /opt/observability-stack/secrets/
# Should show: drwx------ and -rw-------
```

---

## Network Security

### Firewall Configuration

**Recommended UFW rules:**

```bash
# Observability VPS
ufw default deny incoming
ufw default allow outgoing
ufw allow from YOUR_IP to any port 22  # SSH (restricted)
ufw allow 80/tcp                        # HTTP (ACME challenges)
ufw allow 443/tcp                       # HTTPS (Grafana)
ufw enable

# Monitored hosts
ufw default deny incoming
ufw default allow outgoing
ufw allow from YOUR_IP to any port 22              # SSH (restricted)
ufw allow from OBSERVABILITY_VPS_IP to any port 9100  # Node Exporter
ufw allow from OBSERVABILITY_VPS_IP to any port 9253  # phpfpm Exporter
ufw enable
```

### Service Exposure

**Port mapping:**

| Service    | Port | Exposure | Authentication |
|------------|------|----------|----------------|
| Grafana    | 3000 | Nginx → 443 | Username/Password |
| Prometheus | 9090 | Nginx → 443/prometheus | HTTP Basic Auth |
| Loki       | 3100 | Nginx → 443/loki | HTTP Basic Auth |
| Alertmanager | 9093 | Localhost only | None needed |
| Node Exporter | 9100 | Firewall restricted | None needed |

**Key principle:** Only Grafana is publicly accessible (via HTTPS with authentication). All other services are either localhost-only or firewall-restricted.

### SSL/TLS Configuration

**Automated with Let's Encrypt:**

```bash
# Certificates obtained automatically during setup
# Auto-renewal via systemd timer: certbot-renewal.timer

# Manual renewal if needed
sudo certbot renew --force-renewal
sudo systemctl reload nginx

# Check certificate expiry
sudo certbot certificates
```

**Strong TLS configuration (Nginx):**
- TLS 1.2 and 1.3 only
- Strong cipher suites
- HSTS enabled
- OCSP stapling

---

## Authentication & Authorization

### Grafana Authentication

**Initial setup:**
```bash
# Default credentials (CHANGE IMMEDIATELY):
Username: admin
Password: <from config/global.yaml or secrets>

# Change on first login via Grafana UI:
# Settings > Profile > Change Password
```

**Security hardening:**
- Enable multi-factor authentication (optional)
- Use strong passwords (16+ characters)
- Configure session timeout
- Enable audit logging
- Limit organization access

### Prometheus/Loki Authentication

**HTTP Basic Auth via Nginx:**

```bash
# Create htpasswd file
sudo htpasswd -c /etc/nginx/.htpasswd prometheus_user

# Nginx automatically enforces authentication
# Configure clients with credentials:
curl -u prometheus_user:password https://domain.com/prometheus/api/v1/query
```

### SSH Authentication

**Best practices:**

```bash
# Use SSH keys, not passwords
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add public key to server
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server

# Disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart sshd

# Restrict SSH to specific IPs (optional)
ufw delete allow 22
ufw allow from YOUR_IP to any port 22
```

---

## Security Features

### Input Validation

All scripts implement comprehensive input validation:

```bash
✓ Path traversal prevention (../ sequences blocked)
✓ Command injection prevention (sanitized user inputs)
✓ JQ injection prevention (safe JSON processing)
✓ Domain/email validation (regex patterns)
✓ Version string validation (semantic versioning)
```

### File Permissions

Enforced automatically by installation scripts:

```bash
# Service files
-rw-r--r-- /etc/systemd/system/*.service

# Secrets
drwx------ /opt/observability-stack/secrets/
-rw------- /opt/observability-stack/secrets/*

# Scripts
-rwxr-xr-x /opt/observability-stack/scripts/*.sh

# Config files
-rw-r--r-- /opt/observability-stack/config/*.yaml
```

### Lock Files

Prevent concurrent script execution:

```bash
# Atomic lock creation
mkdir /var/lock/observability-stack-setup.lock 2>/dev/null || exit 1

# Automatic cleanup on script exit
trap 'rmdir /var/lock/observability-stack-setup.lock 2>/dev/null' EXIT
```

---

## Security Testing

### Automated Test Suite

**Run all security tests:**

```bash
cd observability-stack
make test-security
```

**Individual test categories:**

```bash
# JQ injection vulnerability tests
bats tests/security/test-jq-injection.bats

# Path traversal vulnerability tests
bats tests/security/test-path-traversal.bats

# Lock file race condition tests
bats tests/security/test-lock-race-condition.bats

# Version validation tests
bats tests/security/test-version-validation.bats
```

**Static analysis:**

```bash
# ShellCheck for shell script issues
make test-shellcheck

# Dependency vulnerability scanning
# (manually check for component updates)
```

### Manual Security Audits

**Pre-deployment checklist:**

```bash
# 1. Validate configuration
./scripts/validate-config.sh

# 2. Run preflight checks
./observability preflight --observability-vps

# 3. Review secrets
sudo ls -la /opt/observability-stack/secrets/
# Should show: drwx------ and -rw-------

# 4. Test authentication
curl -k https://your-domain.com/grafana/api/health
# Should require authentication

# 5. Verify firewall
sudo ufw status verbose
# Should show only necessary ports open
```

---

## Security Audit History

| Date | Version | Auditor | Findings | Status |
|------|---------|---------|----------|--------|
| 2025-12-27 | v4.0.0 | Claude Sonnet 4.5 | 4 issues found | All fixed |
| | | | H-1: JQ injection in config parsing | Fixed in v4.0.0 |
| | | | H-2: Lock file race condition | Fixed in v4.0.0 |
| | | | M-2: Inadequate version validation | Fixed in v4.0.0 |
| | | | M-3: Path traversal in host scripts | Fixed in v4.0.0 |
| 2025-12-27 | v3.0.0 | Claude Sonnet 4.5 | Initial security review | All addressed |

**Detailed audit reports:**
- [Security Audit Report v4.0.0](docs/security/SECURITY-AUDIT-REPORT.md)
- [Security Implementation Summary](docs/security/SECURITY-IMPLEMENTATION-SUMMARY.md)

---

## Known Security Considerations

### Installation Scripts

**Privilege requirements:**
- Scripts require root access for system-level changes
- Always review scripts before running: `less setup-observability.sh`
- Download from trusted sources only
- Verify checksums if available

**What scripts do:**
- Install system packages (apt)
- Create system users and groups
- Modify systemd services
- Configure firewall rules
- Set file permissions

### Configuration Files

**Sensitive data locations:**

```bash
# Contains secrets - DO NOT COMMIT
config/global.yaml

# Safe to commit (examples only)
config/global.yaml.example

# Auto-generated - verify before committing
config/generated/*.yaml
```

### Exporter Security

**Node Exporter (port 9100):**
- Exposes system metrics
- No built-in authentication
- MUST be firewall-restricted to Prometheus server IP only
- Consider using TLS (optional, adds complexity)

**phpfpm Exporter (port 9253):**
- Exposes PHP-FPM metrics
- No built-in authentication
- Firewall-restricted to Prometheus server IP only

**MySQL Exporter (optional):**
- Requires MySQL credentials
- Store credentials securely
- Use read-only MySQL user with limited privileges

---

## Incident Response

### Security Event Detection

**Monitor these logs:**

```bash
# Authentication failures
journalctl -u sshd | grep Failed
journalctl -u grafana-server | grep authentication

# Nginx access logs (unusual activity)
tail -f /var/log/nginx/access.log

# Firewall blocks
journalctl -k | grep UFW

# Systemd service failures
systemctl --failed
```

### Breach Response Procedure

**If you suspect a security breach:**

1. **Immediate actions:**
   ```bash
   # Isolate the server
   sudo ufw default deny incoming

   # Stop affected services
   sudo systemctl stop grafana-server prometheus loki

   # Create forensic snapshot
   sudo journalctl > /tmp/incident-$(date +%Y%m%d-%H%M%S).log
   ```

2. **Investigation:**
   - Review authentication logs
   - Check for unauthorized users: `cat /etc/passwd`
   - Review recent file modifications: `find / -mtime -1 -type f`
   - Check for suspicious processes: `ps aux | less`
   - Review Grafana access logs

3. **Remediation:**
   - Rotate all credentials immediately
   - Review and update firewall rules
   - Apply security patches
   - Restore from known-good backup if needed

4. **Recovery:**
   - Re-enable services only after verifying security
   - Monitor closely for 72 hours
   - Document incident and lessons learned

5. **Reporting:**
   - Report to main repository: [Security Advisory](https://github.com/calounx/mentat/security/advisories/new)
   - Update security documentation based on findings

---

## Best Practices Summary

### Deployment

1. Run preflight checks before installation
2. Use strong, unique passwords (16+ characters)
3. Change all default credentials immediately
4. Enable and configure firewall
5. Use SSH keys instead of passwords
6. Validate configuration before going live
7. Enable SSL/TLS (automatic with Let's Encrypt)

### Operations

1. Monitor logs weekly for suspicious activity
2. Review Grafana dashboards for anomalies
3. Keep system packages updated: `apt update && apt upgrade`
4. Rotate secrets every 90 days
5. Test backup restoration quarterly
6. Review user access quarterly
7. Check SSL certificate expiry monthly

### Updates

1. Read changelog before updating
2. Backup configuration files
3. Test updates in staging environment (if available)
4. Run security tests after updates: `make test-security`
5. Verify all services after updates: `systemctl status grafana-server prometheus loki`

---

## Additional Resources

### Internal Documentation

- [Main Security Policy](../SECURITY.md) - Unified security policy and reporting
- [Security Test Guide](tests/SECURITY_TEST_GUIDE.md) - How to run security tests
- [Secrets Management Guide](docs/SECRETS.md) - Detailed secrets documentation
- [Security Quick Reference](SECURITY_QUICK_REFERENCE.md) - One-page security checklist

### External Resources

- [Grafana Security](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/)
- [Prometheus Security](https://prometheus.io/docs/operating/security/)
- [Loki Security](https://grafana.com/docs/loki/latest/operations/authentication/)
- [OWASP Bash Security](https://owasp.org/www-community/vulnerabilities/Command_Injection)
- [CIS Debian Benchmarks](https://www.cisecurity.org/benchmark/debian_linux)

---

## Contact

**For security vulnerabilities:**
- Report via: [GitHub Security Advisory](https://github.com/calounx/mentat/security/advisories/new)
- See reporting procedures in [main Security Policy](../SECURITY.md)

**For general issues:**
- GitHub Issues: https://github.com/calounx/mentat/issues
- Documentation: [README.md](README.md)

---

**Last Updated:** 2025-12-28
**Document Version:** 2.0 (consolidated)
**Applies to:** Observability Stack v4.0.x and v3.0.x
