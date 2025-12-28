# Security Policy

This document defines the unified security policy for the Mentat project, covering both the Observability Stack and CHOM (Cloud Hosting Operations Manager).

## Supported Versions

We release patches for security vulnerabilities in the following versions:

### Observability Stack

| Version | Supported          |
| ------- | ------------------ |
| 4.x.x   | :white_check_mark: |
| 3.x.x   | :x:                |
| 2.x.x   | :x:                |
| < 2.0   | :x:                |

### CHOM

| Version | Supported          |
| ------- | ------------------ |
| 1.1.x   | :white_check_mark: |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**PLEASE DO NOT REPORT SECURITY VULNERABILITIES THROUGH PUBLIC GITHUB ISSUES.**

We take security seriously. If you discover a security vulnerability, please follow responsible disclosure practices.

### How to Report

1. **GitHub Security Advisory (Recommended)**
   - Go to: https://github.com/calounx/mentat/security/advisories/new
   - This ensures private disclosure until a fix is ready

2. **Alternative: GitHub Issue (Non-Critical)**
   - For lower-severity issues, open a GitHub issue
   - https://github.com/calounx/mentat/issues

### What to Include

Please include as much information as possible:

```
Subject: SECURITY: [Brief Description]

Project: [Observability Stack / CHOM / Both]

Vulnerability Details:
- Component affected: [e.g., setup-observability.sh, SiteController.php]
- Type of vulnerability: [e.g., command injection, SQL injection, XSS]
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

## Component-Specific Security Documentation

For detailed security information specific to each component:

- **Observability Stack**: See [observability-stack/SECURITY.md](observability-stack/SECURITY.md)
  - Secrets management and encryption
  - Network security and firewall configuration
  - SSL/TLS setup
  - Security testing procedures
  - Security audit history

- **CHOM**: See [chom/docs/security/application-security.md](chom/docs/security/application-security.md)
  - Environment variable security
  - API authentication and authorization
  - Tenant isolation
  - SSH key management
  - Laravel-specific security practices

---

## General Security Best Practices

### Secrets Management

**NEVER commit secrets to the repository:**

- API keys and tokens
- Passwords and credentials
- Private keys and certificates
- Domain names (in config files)
- Email addresses (in config files)
- `.env` files with real data

**Protection mechanisms:**

- All sensitive files are in `.gitignore`
- Use environment variables or secure storage
- Rotate credentials periodically
- Use strong, unique passwords (16+ characters)

### Network Security

**Essential configurations:**

- Enable SSL/TLS for all external endpoints
- Configure firewall rules (allow only necessary ports)
- Use SSH key-based authentication (disable password auth)
- Implement IP-based restrictions where possible
- Never expose services directly to internet without authentication

**Recommended firewall rules:**

```yaml
Default Policy: Deny all incoming, allow outgoing

Allow:
  - Port 22 (SSH): Restricted to your IP only
  - Port 80 (HTTP): Public (for ACME challenges only)
  - Port 443 (HTTPS): Public (authenticated services)
  - Application-specific ports: Localhost or VPN only
```

### Access Control

**Principle of least privilege:**

- Use service-specific user accounts
- Limit root access (use sudo for specific commands)
- Implement role-based access control (RBAC)
- Review and revoke unused permissions regularly
- Use strong authentication for all services

### Dependency Management

**Keep dependencies updated:**

```bash
# System packages
apt update && apt upgrade

# Observability stack
cd observability-stack && ./scripts/upgrade-orchestrator.sh

# CHOM
cd chom && composer update && npm update
```

**Monitor for vulnerabilities:**

```bash
# PHP dependencies
cd chom && composer audit

# JavaScript dependencies
cd chom && npm audit

# Run security test suite
make test-security
```

### Incident Response

**If a security incident occurs:**

1. Document the incident immediately
2. Isolate affected systems if necessary
3. Identify and contain the threat
4. Notify affected users within 24 hours
5. Apply fixes and verify resolution
6. Update security procedures
7. Publish security advisory (if applicable)
8. Conduct post-incident review

---

## Security Checklist

### Before Deployment

**Universal:**
- [ ] All secrets are in environment variables or secure storage
- [ ] No sensitive data committed to git repository
- [ ] SSL/TLS configured for all external endpoints
- [ ] Firewall rules configured appropriately
- [ ] Strong, unique passwords for all services (16+ characters)
- [ ] SSH key-based authentication enabled
- [ ] Database credentials are strong and unique
- [ ] Configuration validated and tested

**Observability Stack:**
- [ ] Grafana admin password changed from default
- [ ] Prometheus/Loki behind HTTP Basic Auth
- [ ] Secrets initialized using `./scripts/init-secrets.sh`
- [ ] Preflight checks passed: `./observability preflight`

**CHOM:**
- [ ] `APP_DEBUG=false` in production
- [ ] `APP_ENV=production` set correctly
- [ ] Rate limiting configured
- [ ] CORS configured properly
- [ ] Stripe webhook signature validation enabled
- [ ] SSH keys stored with correct permissions (600)

### During Operation

**Regular monitoring:**
- [ ] Review security logs weekly
- [ ] Monitor for failed authentication attempts
- [ ] Check SSL certificate expiry dates
- [ ] Review firewall logs for suspicious activity
- [ ] Verify backup integrity monthly

**Maintenance:**
- [ ] Apply security patches within 7 days (critical) or 30 days (non-critical)
- [ ] Rotate credentials every 90 days
- [ ] Update dependencies monthly
- [ ] Run security test suite before updates
- [ ] Test disaster recovery procedures quarterly

### After Security Incident

1. [ ] Document incident details immediately
2. [ ] Identify and verify root cause
3. [ ] Develop and test fix
4. [ ] Apply fixes to all affected systems
5. [ ] Notify affected users within 24 hours
6. [ ] Update security procedures
7. [ ] Publish security advisory (if applicable)
8. [ ] Conduct post-incident review
9. [ ] Implement preventive measures

---

## Security Resources

### Internal Documentation

- **Observability Stack:**
  - [observability-stack/SECURITY.md](observability-stack/SECURITY.md)
  - [Security Audit Report](observability-stack/docs/security/SECURITY-AUDIT-REPORT.md)
  - [Security Implementation Summary](observability-stack/docs/security/SECURITY-IMPLEMENTATION-SUMMARY.md)
  - [Security Test Guide](observability-stack/tests/SECURITY_TEST_GUIDE.md)

- **CHOM:**
  - [chom/docs/security/application-security.md](chom/docs/security/application-security.md)

### External Resources

- [OWASP Security Guidelines](https://owasp.org/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [Debian Security](https://www.debian.org/security/)
- [Laravel Security](https://laravel.com/docs/security)
- [Prometheus Security](https://prometheus.io/docs/operating/security/)

---

## Contact

### Security Issues

**For security vulnerabilities:**
- GitHub Security Advisory: https://github.com/calounx/mentat/security/advisories/new
- Response time: 24-48 hours (acknowledgment)
- Resolution time: 7-90 days (based on severity)

**PLEASE DO NOT:**
- Report security issues through public GitHub issues
- Post vulnerability details in public forums
- Exploit vulnerabilities beyond proof-of-concept

### General Support

**For non-security issues:**
- GitHub Issues: https://github.com/calounx/mentat/issues
- Documentation: README.md (component-specific)

---

## Acknowledgments

We appreciate the security research community's efforts in keeping our projects secure. Security researchers who responsibly disclose vulnerabilities will be acknowledged in our release notes and security advisories (with their permission).

### Hall of Thanks

- *Your name could be here!* - We welcome responsible disclosure of security vulnerabilities

---

**Last Updated:** 2025-12-28
**Policy Version:** 2.0
**Next Review:** 2026-03-28 (quarterly reviews)
