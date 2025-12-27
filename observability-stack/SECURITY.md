# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 3.0.x   | :white_check_mark: |
| 2.x.x   | :x:                |
| < 2.0   | :x:                |

## Reporting a Vulnerability

**PLEASE DO NOT REPORT SECURITY VULNERABILITIES THROUGH PUBLIC GITHUB ISSUES.**

We take security seriously. If you discover a security vulnerability, please follow responsible disclosure practices.

### How to Report

1. **GitHub Security Advisory**
   - Go to: https://github.com/calounx/mentat/security/advisories/new
   - This ensures private disclosure until a fix is ready

2. **Alternative: GitHub Issue (Non-Critical)**
   - For lower-severity issues, open a GitHub issue
   - https://github.com/calounx/mentat/issues

### What to Include

Please include as much information as possible:

```
Subject: SECURITY: [Brief Description]

Vulnerability Details:
- Component/Script affected: [e.g., setup-observability.sh]
- Type of vulnerability: [e.g., command injection, path traversal]
- Attack vector: [How can it be exploited?]
- Impact: [What can an attacker achieve?]
- Affected versions: [Which versions are vulnerable?]

Reproduction Steps:
1. [Step 1]
2. [Step 2]
3. [Step 3]

Proof of Concept:
[Code or commands to demonstrate the vulnerability]

Suggested Fix:
[If you have ideas for fixing it]

Additional Context:
[Any other relevant information]
```

### What to Expect

1. **Acknowledgment**: Within 24-48 hours
2. **Initial Assessment**: Within 3-5 business days
3. **Status Updates**: Weekly until resolved
4. **Resolution**: Depends on severity
   - Critical: 7 days
   - High: 14 days
   - Medium: 30 days
   - Low: 90 days

### Our Commitment

- We will acknowledge your report promptly
- We will investigate and validate the issue
- We will keep you informed of our progress
- We will notify you when the issue is fixed
- We will publicly acknowledge your contribution (if you wish)

---

## Security Considerations

### Secrets Management

**DO NOT commit secrets to the repository:**

- API keys
- Passwords
- Private keys
- Certificates
- Tokens

**Use the built-in secrets management:**

```bash
# Store secrets securely
./scripts/init-secrets.sh

# Secrets location
/opt/observability-stack/secrets/

# Secrets are encrypted using systemd credentials
# Reference in config: ${SECRET:name}
```

### Secure Installation

**Always:**

1. Use strong passwords (16+ characters)
2. Enable SSL/TLS for all external access
3. Use firewall rules to restrict access
4. Keep system and packages updated
5. Use secure SMTP credentials
6. Validate configuration before deployment

**Never:**

1. Use default passwords in production
2. Expose services directly to internet without auth
3. Disable SSL/TLS in production
4. Commit secrets or credentials
5. Run with overly permissive firewall rules

### Configuration Security

**Check your configuration:**

```bash
# Validate configuration
./scripts/validate-config.sh

# Look for placeholders
grep -r "CHANGE_ME\|YOUR_\|EXAMPLE" config/

# Check file permissions
ls -la secrets/
# Should be: -rw------- (600)
```

### Network Security

**Firewall Configuration:**

```yaml
Observability VPS:
  - Port 22 (SSH): Restricted to your IP
  - Port 80 (HTTP): Public (for ACME challenges only)
  - Port 443 (HTTPS): Public (Grafana access)
  - All other ports: Localhost only

Monitored Hosts:
  - Port 22 (SSH): Restricted to your IP
  - Exporter ports (9100-9253): Only from Observability VPS IP
  - All other ports: Default deny
```

### Authentication

**Multiple layers of authentication:**

1. **Grafana**: Username/password (change default!)
2. **Prometheus/Loki**: HTTP Basic Auth via Nginx
3. **SSH**: Key-based authentication recommended
4. **Exporters**: Firewall-restricted (no auth needed)

### SSL/TLS

**Automatic SSL with Let's Encrypt:**

```bash
# Certificates are automatically:
- Obtained during setup
- Renewed before expiry
- Monitored by systemd timer

# Manual renewal:
certbot renew --force-renewal
systemctl reload nginx
```

---

## Security Features

### Implemented Protections

✅ **Input Validation**
- All user inputs validated
- Path traversal prevention
- Command injection prevention
- JQ injection prevention

✅ **Secrets Management**
- Encrypted storage via systemd credentials
- Secure file permissions (600)
- No secrets in git repository
- No secrets in process arguments

✅ **Network Security**
- Automated firewall configuration
- SSL/TLS by default
- Basic auth for APIs
- IP-based restrictions

✅ **Access Control**
- Root-only installation
- Service-specific users
- Principle of least privilege
- File permission enforcement

### Security Testing

**Automated security tests:**

```bash
# Run security test suite
make test-security

# Specific security tests
bats tests/security/test-jq-injection.bats
bats tests/security/test-path-traversal.bats
bats tests/security/test-lock-race-condition.bats

# ShellCheck for common issues
make test-shellcheck
```

### Security Audit History

| Date | Version | Auditor | Findings | Status |
|------|---------|---------|----------|--------|
| 2025-12-27 | v3.0.0 | Claude Sonnet 4.5 | 4 issues found | ✅ All fixed |
| | | | H-1: JQ injection | ✅ Fixed |
| | | | H-2: Lock race | ✅ Fixed |
| | | | M-2: Version validation | ✅ Fixed |
| | | | M-3: Path traversal | ✅ Fixed |

---

## Known Security Issues

### Currently None

All known security issues in version 3.0.0 have been addressed.

### Previously Addressed

See [Security Audit Report](docs/security/SECURITY-AUDIT-REPORT.md) for details on previously identified and fixed issues.

---

## Security Best Practices

### For Users

**When Deploying:**

1. Run preflight checks: `./observability preflight --observability-vps`
2. Validate configuration: `./scripts/validate-config.sh`
3. Change all default passwords
4. Use strong passwords (16+ chars, mixed case, numbers, symbols)
5. Enable firewall: `ufw enable`
6. Keep system updated: `apt update && apt upgrade`
7. Use SSH keys instead of passwords
8. Restrict SSH access by IP if possible

**Regular Maintenance:**

1. Monitor for security alerts
2. Update regularly: `./scripts/upgrade-orchestrator.sh --all`
3. Review firewall rules: `ufw status`
4. Check for failed login attempts: `journalctl -u sshd | grep Failed`
5. Verify SSL certificate expiry: `certbot certificates`
6. Review Grafana access logs
7. Rotate secrets periodically

### For Developers

**When Contributing:**

1. Never commit secrets or credentials
2. Use ShellCheck on all scripts
3. Run security tests before submitting PR
4. Follow secure coding guidelines
5. Document security implications of changes
6. Use proper input validation
7. Avoid shell injection vulnerabilities
8. Handle errors securely

**Code Review Checklist:**

- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] No command injection vulnerabilities
- [ ] Proper error handling
- [ ] File permissions set correctly
- [ ] Network exposure minimized
- [ ] Authentication required where needed
- [ ] Secure defaults used

---

## Vulnerability Disclosure Timeline

### Our Process

1. **Day 0**: Vulnerability reported
2. **Day 1-2**: Acknowledgment sent to reporter
3. **Day 3-5**: Initial assessment and validation
4. **Day 7-30**: Fix developed (depending on severity)
5. **Day 30-45**: Fix tested and released
6. **Day 45-60**: Public disclosure with credit

### Public Disclosure

After a fix is released:

1. Security advisory published on GitHub
2. CHANGELOG.md updated with security notes
3. All users notified of security update
4. Reporter credited (if desired)

---

## Security Resources

### Internal Documentation

- [Security Audit Report](docs/security/SECURITY-AUDIT-REPORT.md)
- [Security Implementation Summary](docs/security/SECURITY-IMPLEMENTATION-SUMMARY.md)
- [Security Quick Reference](SECURITY_QUICK_REFERENCE.md)
- [Secrets Management Guide](docs/SECRETS.md)

### External Resources

- [OWASP Bash Security](https://owasp.org/www-community/vulnerabilities/Command_Injection)
- [ShellCheck](https://www.shellcheck.net/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [Debian Security](https://www.debian.org/security/)

---

## Security Contact

**For security issues:**
- GitHub Security Advisory: https://github.com/calounx/mentat/security/advisories/new
- Response time: 24-48 hours

**For general issues:**
- GitHub Issues: https://github.com/calounx/mentat/issues
- Documentation: README.md

---

## Acknowledgments

We would like to thank the following security researchers for responsibly disclosing vulnerabilities:

- [Name] - [Brief description] - [Date]
- (Future acknowledgments will be added here)

---

**Last Updated:** 2025-12-27

**Security Policy Version:** 1.0

**Next Review:** 2026-01-27 (quarterly reviews)
