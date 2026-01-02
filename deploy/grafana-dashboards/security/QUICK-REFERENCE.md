# CHOM Security Dashboards - Quick Reference Guide

## Emergency Response Numbers

**CRITICAL INCIDENT (P1):** Call Security Team Lead immediately

- **Security Team Lead:** [PHONE NUMBER]
- **Security On-Call:** [PAGERDUTY]
- **DevOps Manager:** [PHONE NUMBER]
- **DPO (Data Protection Officer):** [PHONE NUMBER]

---

## Dashboard URLs

- **Security Operations:** http://grafana:3000/d/chom-security-operations
- **Compliance & Audit:** http://grafana:3000/d/chom-compliance-audit
- **Access & Authentication:** http://grafana:3000/d/chom-access-authentication

---

## Alert Severity Quick Reference

| Alert Level | Response Time | Action Required |
|-------------|---------------|-----------------|
| **P1 - CRITICAL** | 5 minutes | Call on-call, open incident war room |
| **P2 - HIGH** | 15 minutes | Investigate immediately, notify team lead |
| **P3 - MEDIUM** | 1 hour | Investigate, document findings |
| **P4 - LOW** | 4 hours | Review during business hours |

---

## Common P1 Incidents - First 5 Minutes

### Active DDoS Attack
```bash
# 1. Verify attack
curl 'http://localhost:9090/api/v1/query?query=chom_ddos_attacks_active'

# 2. Enable aggressive rate limiting
kubectl patch configmap nginx-config -p '{"data":{"rate-limit":"10r/s"}}'

# 3. Block top attacking IPs
curl 'http://localhost:9090/api/v1/query?query=topk(10,rate(chom_http_requests_blocked_ddos_total[1m])by(ip))' \
  | jq -r '.data.result[].metric.ip' \
  | xargs -I {} fail2ban-client set nginx banip {}

# 4. Open incident channel: #incident-YYYYMMDD-###
```

### Brute Force Attack
```bash
# 1. Verify attack pattern
curl 'http://localhost:9090/api/v1/query?query=increase(chom_auth_failed_total[1h])'

# 2. Lock targeted accounts
php artisan chom:security:lock-accounts --failed-attempts=5 --duration=1h

# 3. Block attacking IPs
curl 'http://localhost:9090/api/v1/query?query=topk(20,rate(chom_auth_failed_total[5m])by(ip))' \
  | jq -r '.data.result[].metric.ip' \
  | xargs -I {} fail2ban-client set chom-auth banip {}

# 4. Enable CAPTCHA temporarily
php artisan config:set security.captcha_enabled=true
```

### SQL Injection Attack
```bash
# 1. Verify WAF is blocking
curl 'http://localhost:9090/api/v1/query?query=increase(chom_waf_sql_injection_blocked_total[1h])'

# 2. Restrict database access (if bypassing WAF)
mysql -e "UPDATE mysql.user SET Host='10.0.1.100' WHERE User='chom'; FLUSH PRIVILEGES;"

# 3. Export attack logs
curl -G 'http://loki:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="waf"} |= "sql_injection"' \
  --data-urlencode 'start='$(date -d '1 hour ago' +%s)000000000 \
  > sqli-attack-$(date +%Y%m%d-%H%M%S).json
```

### GDPR Data Breach
```bash
# 1. Verify breach
curl 'http://localhost:9090/api/v1/query?query=increase(chom_gdpr_violations_total[1h])'

# 2. Notify DPO IMMEDIATELY (72-hour clock starts)
# Call: [DPO PHONE NUMBER]

# 3. Contain exposure
iptables -A OUTPUT -p tcp --dport 443 -j DROP  # Temporary

# 4. Identify affected users
mysql -e "SELECT id,email,name FROM users WHERE id IN (
  SELECT DISTINCT user_id FROM audit_log
  WHERE action='UNAUTHORIZED_ACCESS'
  AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
) INTO OUTFILE '/tmp/affected-users.csv';"
```

### Privilege Escalation
```bash
# 1. Verify escalation attempt
curl 'http://localhost:9090/api/v1/query?query=increase(chom_security_privilege_escalation_attempts_total[1h])'

# 2. Revoke admin access for suspicious user
php artisan chom:security:revoke-role --user-id=<USER_ID> --role=admin

# 3. Force logout all sessions
php artisan chom:security:revoke-sessions --user-id=<USER_ID>

# 4. Disable account
php artisan chom:users:disable --user-id=<USER_ID> --reason="Security: Privilege escalation"
```

---

## Evidence Collection Script

```bash
#!/bin/bash
# Quick evidence collection for incidents
# Usage: ./collect-evidence.sh [incident-id]

INCIDENT_ID=$1
DIR="/var/security/incidents/${INCIDENT_ID}"
mkdir -p "${DIR}"

# Grafana dashboards
curl -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  http://localhost:3000/api/dashboards/uid/chom-security-operations \
  > "${DIR}/dashboard-$(date +%Y%m%d-%H%M%S).json"

# Prometheus metrics (last 2 hours)
curl -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query={__name__=~"chom_.*"}' \
  --data-urlencode 'start='$(date -d '2 hours ago' +%s) \
  > "${DIR}/metrics-$(date +%Y%m%d-%H%M%S).json"

# Loki logs
curl -G 'http://loki:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job=~".*"}' \
  --data-urlencode 'start='$(date -d '2 hours ago' +%s)000000000 \
  > "${DIR}/logs-$(date +%Y%m%d-%H%M%S).json"

# Database snapshot
mysqldump --all-databases > "${DIR}/db-$(date +%Y%m%d-%H%M%S).sql"

# System state
netstat -tulanp > "${DIR}/netstat-$(date +%Y%m%d-%H%M%S).txt"
iptables -L -n -v > "${DIR}/iptables-$(date +%Y%m%d-%H%M%S).txt"

echo "Evidence collected in ${DIR}"
```

---

## Key Metric Queries

### Security Operations

```promql
# Current threat level (0=Low, 3=Critical)
chom_security_threat_level

# Active threats
chom_security_active_threats

# WAF blocks in last 5 minutes
increase(chom_waf_requests_blocked_total[5m])

# DDoS attacks active
chom_ddos_attacks_active

# Failed logins in last hour
increase(chom_auth_failed_total[1h])

# Privilege escalation attempts
increase(chom_security_privilege_escalation_attempts_total[1h])
```

### Compliance

```promql
# Overall compliance score (target: ≥0.95)
chom_compliance_score

# GDPR compliance score (target: ≥0.95)
chom_gdpr_compliance_score

# Data breach risk (lower is better, alert: >70)
chom_data_breach_risk_score

# Encryption coverage percentage
(chom_data_encrypted_bytes / chom_data_total_bytes) * 100

# Records exceeding retention
chom_data_retention_exceeded
```

### Authentication

```promql
# Login success rate (target: ≥95%)
(sum(increase(chom_auth_success_total[1h])) /
 (sum(increase(chom_auth_success_total[1h])) +
  sum(increase(chom_auth_failed_total[1h])))) * 100

# 2FA adoption rate (target: ≥90%)
(chom_users_2fa_enabled / chom_users_total) * 100

# Suspicious logins in last hour
increase(chom_suspicious_login_total[1h])

# Account lockouts
increase(chom_account_lockout_total[1h])

# Session hijacking attempts
increase(chom_security_session_hijacking_attempts_total[5m])
```

---

## Log Queries (Loki)

### Authentication Logs

```logql
# Failed logins in last hour
{job="authentication"} |= "failed_login" | json

# Suspicious login patterns
{job="authentication"} |= "suspicious_login" | json

# Account lockouts
{job="authentication"} |= "account_locked" | json
```

### WAF Logs

```logql
# All blocked requests
{job="waf"} |= "blocked" | json

# SQL injection attempts
{job="waf"} |= "sql_injection" | json

# XSS attempts
{job="waf"} |= "xss" | json
```

### Audit Logs

```logql
# Access control changes
{job="audit-log"} |= "access_control" | json

# Admin actions
{job="audit-log"} |= "admin_action" | json

# Privilege escalations
{job="audit-log"} |= "privilege_escalation" | json
```

---

## Common Remediation Commands

### Block IP Address

```bash
# Temporary block (fail2ban)
fail2ban-client set nginx banip <IP_ADDRESS>

# Permanent block (iptables)
iptables -A INPUT -s <IP_ADDRESS> -j DROP
iptables-save > /etc/iptables/rules.v4

# Verify block
iptables -L INPUT -n | grep <IP_ADDRESS>
```

### Revoke User Access

```bash
# Disable user account
php artisan chom:users:disable --user-id=<USER_ID>

# Revoke admin role
php artisan chom:security:revoke-role --user-id=<USER_ID> --role=admin

# Force logout all sessions
php artisan chom:security:revoke-sessions --user-id=<USER_ID>

# Revoke API tokens
php artisan chom:api:revoke-tokens --user-id=<USER_ID>
```

### Enable Enhanced Security

```bash
# Enable CAPTCHA globally
php artisan config:set security.captcha_enabled=true

# Increase rate limiting
kubectl patch configmap nginx-config -p '{"data":{"rate-limit":"10r/s"}}'

# Require 2FA for all users
php artisan config:set security.2fa_required_all=true

# Reduce login attempt threshold
php artisan config:set security.max_login_attempts=3
```

### Database Emergency Actions

```bash
# Restrict database access to app server only
mysql -e "UPDATE mysql.user SET Host='10.0.1.100' WHERE User='chom';"
mysql -e "FLUSH PRIVILEGES;"

# Create forensic backup
mysqldump --all-databases > forensic-backup-$(date +%Y%m%d-%H%M%S).sql

# Check for unauthorized changes
mysql -e "SELECT * FROM mysql.general_log WHERE
  command_type='Query' AND
  (argument LIKE '%UNION%' OR argument LIKE '%DROP%')
  ORDER BY event_time DESC LIMIT 100;"
```

---

## Escalation Contacts

### P1 - Critical (Immediate)
1. Security Team Lead: [PHONE]
2. DevOps Manager: [PHONE]
3. VP Engineering: [PHONE]

### P2 - High (15 min)
1. Security Team Lead: [PHONE]
2. VP Engineering: [EMAIL]

### Compliance/Legal
- Data Protection Officer: [PHONE/EMAIL]
- Legal Counsel: [PHONE/EMAIL]

### External
- Cyber Insurance: [POLICY#] - [PHONE]
- Incident Response Retainer: [COMPANY] - [PHONE]

---

## Dashboard Panel Quick Reference

### Security Operations Dashboard

**Row 1: Overview**
- Threat Level (0-3 gauge)
- Active Threats (counter)
- WAF Blocks 5m (counter)
- Active DDoS (counter)
- IDS Alerts 1h (counter)
- Pending Patches (counter)

**Row 2: WAF Analytics**
- WAF Blocks by Attack Type (time series)
- Attack Type Distribution (pie chart)
- Top Attack Countries (bar chart)
- Top WAF Rules Triggered (table)

**Row 3: DDoS & Rate Limiting**
- Request Rate & DDoS Mitigation (time series)
- Rate Limited Endpoints (time series)
- Top Rate Limited IPs (bar chart)
- Network Traffic Anomaly (time series)

**Row 4: IDS & File Integrity**
- IDS Alerts by Severity (time series)
- Alert Severity Distribution (pie chart)
- File Integrity Violations (table)
- Top IDS Signatures (table)

**Row 5: Patch Management**
- Patch Compliance Rate (gauge)
- Critical Patches Pending (stat)
- Avg Patch Application Time (stat)
- Vulnerable Packages (stat)
- Patch Application History (time series)

### Compliance & Audit Dashboard

**Row 1: Overview**
- Overall Compliance Score (gauge)
- GDPR Compliance Score (gauge)
- Data Breach Risk Score (gauge)
- Active Violations (stat)
- Audits This Month (stat)

**Row 2: GDPR**
- GDPR Data Subject Requests (time series)
- GDPR Request Processing Time (table)
- User Consent Status (pie chart)
- Data Processing by Purpose (bar chart)
- GDPR Violations Over Time (time series)

**Row 3: Data Retention**
- Retention Policy Compliance (gauge)
- Records Exceeding Retention (stat)
- Data Purges 30d (stat)
- Audit Storage Usage (stat)
- Data Lifecycle Distribution (time series)

**Row 4: Access Control Audit**
- Access Control Audit Events (time series)
- Audit Log Events (table)
- Sensitive Data Access by Role (bar chart)
- Admin Privilege Usage (time series)

**Row 5: Encryption**
- Data-at-Rest Encryption (gauge)
- Data-in-Transit Encryption (gauge)
- Unencrypted Data Volume (stat)
- Days Since Key Rotation (stat)
- Backup Compliance Status (time series)
- SSL Certificate Expiration (table)

### Access & Authentication Dashboard

**Row 1: Overview**
- Login Success Rate (gauge)
- Successful Logins 1h (stat)
- Failed Logins 1h (stat)
- Active Sessions (stat)
- Account Lockouts 1h (stat)
- Suspicious Logins 1h (stat)
- Password Resets 1h (stat)
- Authentication Activity Over Time (time series)

**Row 2: 2FA**
- 2FA Adoption Rate (gauge)
- 2FA Enrollment Status (pie chart)
- 2FA Adoption by Role (bar chart)
- 2FA Verification Activity (time series)

**Row 3: Password Security**
- Password Policy Compliance (gauge)
- Users with Weak Passwords (stat)
- Expired Passwords (stat)
- Password Reuse Violations (stat)

**Row 4: Session Management**
- Session Lifecycle Activity (time series)
- Avg Session Duration by Role (bar chart)
- Session Hijacking Attempts (time series)
- OAuth/SSO Activity by Provider (time series)

**Row 5: API Authentication**
- API Key Usage by Endpoint (time series)
- API Authentication Failures (time series)
- API Key Rotation Status (table)
- Token Rotation Activity (time series)

**Row 6: Suspicious Patterns**
- Suspicious Login Patterns (time series)
- Suspicious Pattern Distribution (pie chart)
- Suspicious Login Event Log (table)
- Login Geographic Distribution (bar chart)
- Top Failed Login IPs (bar chart)

---

## Metric Threshold Reference

| Metric | Normal | Warning | Critical | Action |
|--------|--------|---------|----------|--------|
| Threat Level | 0-1 | 2 | 3 | Investigate/Escalate |
| Login Success Rate | >95% | 90-95% | <90% | Check auth system |
| 2FA Adoption | >90% | 75-90% | <75% | Enforce policy |
| Compliance Score | >95% | 90-95% | <90% | Remediate violations |
| WAF Blocks/5min | <10 | 10-100 | >100 | Investigate attack |
| Failed Logins/hour | <20 | 20-100 | >100 | Brute force alert |
| Encryption Coverage | >99% | 95-99% | <95% | Enable encryption |
| Data Breach Risk | <30 | 30-70 | >70 | Immediate action |

---

## Quick Tips

### Performance Optimization
- Use `rate()` for counters, not `increase()` when possible
- Limit time ranges to reduce query load
- Use recording rules for expensive queries
- Cache dashboard queries when appropriate

### Troubleshooting
- Check Prometheus targets: http://localhost:9090/targets
- Verify Loki logs: http://localhost:3100/ready
- Test metrics endpoint: curl http://chom-app:8000/metrics
- Validate alert rules: promtool check rules /etc/prometheus/rules/

### Best Practices
- Review dashboards daily at shift start
- Respond to all P1 alerts within 5 minutes
- Document all incidents in incident register
- Update playbook after each major incident
- Conduct monthly tabletop exercises

---

## Emergency Procedures Checklist

### P1 Incident Response
- [ ] Verify alert in dashboard
- [ ] Call Incident Commander
- [ ] Open war room (#incident-YYYYMMDD-###)
- [ ] Execute immediate containment actions
- [ ] Collect evidence (logs, metrics, snapshots)
- [ ] Document timeline and actions
- [ ] Notify stakeholders per escalation matrix
- [ ] Follow playbook procedures for incident type

### GDPR Data Breach (72-hour deadline)
- [ ] Notify DPO immediately
- [ ] Contain data exposure
- [ ] Identify affected data subjects
- [ ] Assess breach severity (high/low risk)
- [ ] Preserve evidence
- [ ] Prepare breach notification for supervisory authority
- [ ] If high risk: Prepare individual notifications
- [ ] Document in breach register

### Post-Incident
- [ ] Complete incident report within 24 hours
- [ ] Schedule lessons learned meeting (3 business days)
- [ ] Update playbook with findings
- [ ] Implement preventive measures
- [ ] Close incident ticket

---

**Last Updated:** 2026-01-02
**Version:** 1.0
**Keep this guide accessible at all times for rapid incident response**

---

**Print this page and keep it at your workstation for quick reference during incidents.**
