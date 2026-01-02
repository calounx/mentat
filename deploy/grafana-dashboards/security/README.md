# CHOM Security & Compliance Grafana Dashboards

## Overview

This directory contains three specialized Grafana dashboards for comprehensive security monitoring and compliance tracking of the CHOM platform. These dashboards enable proactive security monitoring, real-time threat detection, compliance verification, and security incident response.

## Dashboards

### 1. Security Operations Dashboard
**File:** `1-security-operations.json`
**UID:** `chom-security-operations`
**Focus:** Real-time threat detection and security operations

**Key Metrics:**
- **Threat Monitoring:** Real-time threat level, active threats, security incidents
- **Web Application Firewall (WAF):** Request blocking, attack type analysis, rule effectiveness
- **DDoS Mitigation:** Attack detection, traffic patterns, rate limiting effectiveness
- **Intrusion Detection System (IDS):** Alert severity tracking, signature triggering
- **File Integrity Monitoring:** Unauthorized file modifications, integrity violations
- **Security Patching:** Pending patches, patch compliance, vulnerability tracking

**Use Cases:**
- Monitor active security threats in real-time
- Detect and respond to DDoS attacks
- Track WAF effectiveness and attack patterns
- Identify intrusion attempts and anomalies
- Ensure timely security patch deployment

**Alert Thresholds:**
- Threat Level Critical: Immediate action required
- Active DDoS > 0: P1 incident
- WAF Blocks > 100/5min: P2 investigation
- SQL Injection > 10/hour: P2 incident
- Privilege Escalation > 0: P1 critical

---

### 2. Compliance & Audit Dashboard
**File:** `2-compliance-audit.json`
**UID:** `chom-compliance-audit`
**Focus:** GDPR compliance, data governance, and audit readiness

**Key Metrics:**
- **Compliance Scoring:** Overall compliance score, GDPR compliance, active violations
- **GDPR Compliance:** Data subject requests, consent tracking, violation monitoring
- **Data Retention:** Policy adherence, retention violations, data purging
- **Access Control Audit:** Permission changes, role assignments, sensitive data access
- **Encryption Status:** Data-at-rest coverage, data-in-transit (TLS), key rotation
- **Backup Compliance:** Frequency, retention, encryption status

**Use Cases:**
- Ensure GDPR compliance and avoid penalties
- Track data subject rights requests (access, erasure, portability)
- Monitor data retention policy adherence
- Audit access control changes and privilege modifications
- Verify encryption coverage for sensitive data
- Validate backup compliance and disaster recovery readiness

**Compliance Requirements:**
- Overall Compliance Score: Target ≥95%
- GDPR Compliance: Target ≥95%
- Data-at-Rest Encryption: Target ≥99%
- Data-in-Transit Encryption: Target ≥99.5%
- Backup Success Rate: Target 100%

---

### 3. Access & Authentication Dashboard
**File:** `3-access-authentication.json`
**UID:** `chom-access-authentication`
**Focus:** Authentication security, access patterns, and credential management

**Key Metrics:**
- **Authentication Activity:** Login success/failure rates, active sessions, account lockouts
- **Two-Factor Authentication (2FA):** Adoption rate, enrollment status by role, verification activity
- **Password Security:** Policy compliance, weak passwords, expired passwords, reuse violations
- **Session Management:** Session lifecycle, duration by role, hijacking attempts
- **API Authentication:** Key usage, token rotation, authentication failures
- **Suspicious Login Patterns:** Impossible travel, unusual times, new devices, brute force detection

**Use Cases:**
- Monitor authentication success rates and detect brute force attacks
- Track 2FA adoption and enforce multi-factor authentication
- Ensure password policy compliance across users
- Detect session hijacking and suspicious login patterns
- Monitor API authentication and key rotation
- Identify compromised credentials and unauthorized access

**Security Targets:**
- Login Success Rate: ≥95%
- 2FA Adoption Rate: ≥90% (100% for admins/owners)
- Password Policy Compliance: ≥95%
- Failed Login Threshold: <100/hour (alert on breach)
- Session Hijacking: 0 tolerance (immediate investigation)

---

## Installation

### Prerequisites

- Grafana 10.0.0 or higher
- Prometheus datasource configured (UID: `prometheus`)
- Loki datasource configured (UID: `loki`) - optional but recommended
- CHOM application metrics exposed at `/metrics` endpoint

### Import Dashboards

#### Method 1: Grafana UI

1. Open Grafana web interface
2. Navigate to **Dashboards** → **Import**
3. Upload JSON file or paste JSON content
4. Select Prometheus datasource
5. Click **Import**

#### Method 2: Grafana API

```bash
# Set your Grafana API key
export GRAFANA_API_KEY="your-api-key"
export GRAFANA_URL="http://localhost:3000"

# Import Security Operations Dashboard
curl -X POST "${GRAFANA_URL}/api/dashboards/db" \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @1-security-operations.json

# Import Compliance & Audit Dashboard
curl -X POST "${GRAFANA_URL}/api/dashboards/db" \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @2-compliance-audit.json

# Import Access & Authentication Dashboard
curl -X POST "${GRAFANA_URL}/api/dashboards/db" \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @3-access-authentication.json
```

#### Method 3: Provisioning (Recommended for Production)

Create `/etc/grafana/provisioning/dashboards/security-dashboards.yml`:

```yaml
apiVersion: 1

providers:
  - name: 'CHOM Security Dashboards'
    orgId: 1
    folder: 'Security'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards/security
```

Copy dashboard files:

```bash
sudo mkdir -p /var/lib/grafana/dashboards/security
sudo cp *.json /var/lib/grafana/dashboards/security/
sudo chown -R grafana:grafana /var/lib/grafana/dashboards/security
sudo systemctl restart grafana-server
```

---

## Required Metrics

The dashboards expect the following Prometheus metrics to be exposed by the CHOM application:

### Security Operations Metrics

```promql
# Threat Detection
chom_security_threat_level                        # 0=Low, 1=Elevated, 2=High, 3=Critical
chom_security_active_threats                      # Current active threats
chom_security_threat_detected_total               # Counter

# WAF (Web Application Firewall)
chom_waf_requests_blocked_total{attack_type}      # Counter by attack type
chom_waf_sql_injection_blocked_total              # Counter
chom_waf_xss_blocked_total                        # Counter
chom_waf_path_traversal_blocked_total             # Counter
chom_waf_command_injection_blocked_total          # Counter
chom_waf_file_upload_blocked_total                # Counter
chom_waf_rule_triggered_total{rule_id,rule_name} # Counter

# DDoS Protection
chom_ddos_attacks_active                          # Gauge
chom_ddos_attack_mitigated_total                  # Counter
chom_http_requests_total                          # Counter
chom_http_requests_blocked_ddos_total             # Counter

# Intrusion Detection
chom_ids_alerts_total{severity}                   # Counter by severity
chom_ids_signature_triggered_total{signature_id,signature_name,severity} # Counter

# File Integrity
chom_file_integrity_violations                    # Gauge
chom_security_privilege_escalation_attempts_total # Counter

# Security Patching
chom_security_patch_pending{severity}             # Gauge
chom_security_patches_applied{severity}           # Counter
chom_security_patch_time_to_apply_days            # Gauge
chom_security_vulnerable_packages                 # Gauge
```

### Compliance & Audit Metrics

```promql
# Compliance Scoring
chom_compliance_score                             # Gauge (0-1)
chom_gdpr_compliance_score                        # Gauge (0-1)
chom_data_breach_risk_score                       # Gauge (0-100)
chom_compliance_violations_active                 # Gauge
chom_compliance_audits_total                      # Counter

# GDPR
chom_gdpr_requests_total{type}                    # Counter (access, rectification, erasure, portability)
chom_gdpr_request_age_days{status}                # Gauge
chom_user_consents_active                         # Gauge
chom_user_consents_expired                        # Gauge
chom_user_consents_withdrawn                      # Gauge
chom_gdpr_data_processing_activities{purpose}     # Gauge
chom_gdpr_violations_total{type}                  # Counter

# Data Retention
chom_data_retention_compliant                     # Gauge
chom_data_retention_total                         # Gauge
chom_data_retention_exceeded                      # Gauge
chom_data_purges_total                            # Counter
chom_audit_storage_bytes                          # Gauge
chom_data_lifecycle_bytes{stage}                  # Gauge (active, archived, pending_deletion)

# Access Control Audit
chom_audit_access_control_events_total{event}     # Counter
chom_audit_sensitive_data_access_total{role}      # Counter
chom_audit_admin_actions_total{action}            # Counter

# Encryption
chom_data_encrypted_bytes                         # Gauge
chom_data_total_bytes                             # Gauge
chom_encryption_key_rotation_timestamp            # Timestamp

# Backups
chom_backups_completed_total                      # Counter
chom_backups_failed_total                         # Counter
chom_backups_encrypted_total                      # Counter
chom_ssl_cert_expiry_timestamp{domain}            # Timestamp
```

### Access & Authentication Metrics

```promql
# Authentication
chom_auth_success_total{role}                     # Counter
chom_auth_failed_total{ip}                        # Counter
chom_sessions_active                              # Gauge
chom_account_lockout_total                        # Counter
chom_suspicious_login_total{pattern}              # Counter (impossible_travel, unusual_time, new_device, multiple_ips, tor_vpn)
chom_password_reset_requests_total                # Counter

# Two-Factor Authentication
chom_users_2fa_enabled{role}                      # Gauge
chom_users_total{role}                            # Gauge
chom_auth_2fa_success_total                       # Counter
chom_auth_2fa_failed_total                        # Counter

# Password Security
chom_password_policy_compliance_score             # Gauge (0-1)
chom_users_weak_password                          # Gauge
chom_users_password_expired                       # Gauge
chom_password_reuse_violations_total              # Counter

# Session Management
chom_sessions_created_total                       # Counter
chom_sessions_expired_total                       # Counter
chom_sessions_invalidated_total                   # Counter
chom_session_duration_seconds{role}               # Histogram
chom_security_session_hijacking_attempts_total    # Counter

# OAuth/SSO
chom_oauth_authentications_total{provider}        # Counter

# API Authentication
chom_api_requests_total{auth_type,endpoint}       # Counter
chom_api_auth_failed_total{reason}                # Counter (invalid_key, expired_token, missing_credentials, insufficient_permissions)
chom_api_key_created_timestamp{api_key_id,owner,scope} # Timestamp
chom_sanctum_token_rotations_total                # Counter
chom_sanctum_token_created_total                  # Counter
chom_sanctum_token_revoked_total                  # Counter
```

---

## Alerting Configuration

### Prometheus Alert Rules

Create `/etc/prometheus/rules/chom-security-alerts.yml`:

```yaml
groups:
  - name: chom_security_critical
    interval: 30s
    rules:
      # P1 Critical Alerts
      - alert: ThreatLevelCritical
        expr: chom_security_threat_level == 3
        for: 1m
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "Critical threat level detected"
          description: "Security threat level is CRITICAL. Immediate investigation required."
          dashboard: "http://grafana:3000/d/chom-security-operations"

      - alert: ActiveDDoSAttack
        expr: chom_ddos_attacks_active > 0
        for: 1m
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "Active DDoS attack detected"
          description: "{{ $value }} active DDoS attacks in progress"

      - alert: PrivilegeEscalationAttempt
        expr: increase(chom_security_privilege_escalation_attempts_total[5m]) > 0
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "Privilege escalation attempt detected"
          description: "{{ $value }} privilege escalation attempts in last 5 minutes"

      - alert: BruteForceAttack
        expr: increase(chom_auth_failed_total[1h]) > 100
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "Potential brute force attack"
          description: "{{ $value }} failed login attempts in last hour"

      - alert: GDPRViolation
        expr: increase(chom_gdpr_violations_total[1h]) > 0
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "GDPR violation detected"
          description: "{{ $value }} GDPR violations detected"

      - alert: DataBreachRiskHigh
        expr: chom_data_breach_risk_score > 70
        for: 5m
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "High data breach risk detected"
          description: "Data breach risk score is {{ $value }}/100"

      - alert: SessionHijackingAttempt
        expr: increase(chom_security_session_hijacking_attempts_total[5m]) > 0
        labels:
          severity: critical
          priority: P1
        annotations:
          summary: "Session hijacking attempt detected"
          description: "{{ $value }} session hijacking attempts detected"

  - name: chom_security_high
    interval: 1m
    rules:
      # P2 High Priority Alerts
      - alert: WAFHighBlockRate
        expr: increase(chom_waf_requests_blocked_total[5m]) > 100
        for: 2m
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "High WAF block rate detected"
          description: "{{ $value }} requests blocked in last 5 minutes"

      - alert: SQLInjectionDetected
        expr: increase(chom_waf_sql_injection_blocked_total[1h]) > 10
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "SQL injection attacks detected"
          description: "{{ $value }} SQL injection attempts in last hour"

      - alert: FileIntegrityViolation
        expr: chom_file_integrity_violations > 0
        for: 1m
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "File integrity violation detected"
          description: "{{ $value }} unauthorized file modifications detected"

      - alert: AccountLockoutSpike
        expr: increase(chom_account_lockout_total[1h]) > 10
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "Account lockout spike detected"
          description: "{{ $value }} account lockouts in last hour"

      - alert: SuspiciousLoginPattern
        expr: increase(chom_suspicious_login_total[1h]) > 5
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "Suspicious login patterns detected"
          description: "{{ $value }} suspicious logins in last hour"

      - alert: ComplianceScoreLow
        expr: chom_compliance_score < 0.90
        for: 5m
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "Compliance score below threshold"
          description: "Compliance score is {{ $value | humanizePercentage }}"

      - alert: EncryptionCoverageLow
        expr: (chom_data_encrypted_bytes / chom_data_total_bytes) < 0.95
        for: 5m
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "Encryption coverage below target"
          description: "Only {{ $value | humanizePercentage }} of data is encrypted"

      - alert: APIAuthenticationFailures
        expr: increase(chom_api_auth_failed_total[5m]) > 50
        labels:
          severity: high
          priority: P2
        annotations:
          summary: "High API authentication failure rate"
          description: "{{ $value }} API authentication failures in last 5 minutes"

  - name: chom_security_medium
    interval: 5m
    rules:
      # P3 Medium Priority Alerts
      - alert: CriticalSecurityPatches
        expr: chom_security_patch_pending{severity="critical"} > 5
        for: 1h
        labels:
          severity: medium
          priority: P3
        annotations:
          summary: "Critical security patches pending"
          description: "{{ $value }} critical security patches awaiting installation"

      - alert: SSLCertificateExpiring
        expr: (chom_ssl_cert_expiry_timestamp - time()) / 86400 < 30
        for: 1h
        labels:
          severity: medium
          priority: P3
        annotations:
          summary: "SSL certificate expiring soon"
          description: "SSL certificate expires in {{ $value }} days"

      - alert: DataRetentionViolations
        expr: chom_data_retention_exceeded > 500
        for: 1h
        labels:
          severity: medium
          priority: P3
        annotations:
          summary: "Data retention violations detected"
          description: "{{ $value }} records exceeding retention policy"

      - alert: WeakPasswordCompliance
        expr: chom_users_weak_password > 20
        for: 1h
        labels:
          severity: medium
          priority: P3
        annotations:
          summary: "Users with weak passwords"
          description: "{{ $value }} users have weak passwords"

      - alert: TwoFactorAdoptionLow
        expr: (chom_users_2fa_enabled / chom_users_total) < 0.75
        for: 1h
        labels:
          severity: medium
          priority: P3
        annotations:
          summary: "2FA adoption rate below target"
          description: "Only {{ $value | humanizePercentage }} of users have 2FA enabled"
```

### Alert Manager Configuration

Configure AlertManager to route alerts to appropriate channels:

```yaml
# /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'priority']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        priority: P1
      receiver: 'critical-pager'
      continue: true

    - match:
        priority: P2
      receiver: 'high-slack'
      continue: true

    - match:
        priority: P3
      receiver: 'medium-email'

receivers:
  - name: 'default'
    email_configs:
      - to: 'security-team@example.com'

  - name: 'critical-pager'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'
        description: '{{ .CommonAnnotations.summary }}'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK'
        channel: '#incident-response'
        title: '🚨 P1 CRITICAL: {{ .CommonAnnotations.summary }}'

  - name: 'high-slack'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK'
        channel: '#security-alerts'
        title: '⚠️ P2 HIGH: {{ .CommonAnnotations.summary }}'

  - name: 'medium-email'
    email_configs:
      - to: 'security-team@example.com'
        headers:
          Subject: 'P3 Security Alert: {{ .CommonAnnotations.summary }}'
```

---

## Security Incident Response Playbook

**File:** `SECURITY-INCIDENT-RESPONSE-PLAYBOOK.md`

Comprehensive playbook covering:

1. **Incident Severity Levels** - P1 through P4 classification
2. **Incident Response Team** - Roles and responsibilities
3. **Dashboard Alert Mapping** - Alert to incident type mapping
4. **Response Procedures** - Step-by-step procedures for:
   - Active DDoS Attack
   - Brute Force Attack
   - SQL Injection Attack
   - GDPR Data Breach
   - Privilege Escalation Attempt
   - Compliance Score Below Threshold
5. **Post-Incident Activities** - Documentation, lessons learned, compliance reporting
6. **Communication Templates** - Internal alerts, customer communications, executive summaries
7. **Escalation Matrix** - Contact information and escalation paths

**Usage:**
Refer to the playbook when any dashboard alert is triggered. Each alert type has a detailed response procedure with specific commands and actions.

---

## Dashboard Features

### Common Features Across All Dashboards

1. **Auto-Refresh:** Dashboards refresh every 30 seconds to 1 minute
2. **Time Range Selector:** Adjustable time windows (5m, 15m, 1h, 6h, 24h, 7d, 30d)
3. **Alert Annotations:** Visual indicators when alerts are triggered
4. **Template Variables:** Filter by specific criteria (user role, attack type, etc.)
5. **Drill-Down:** Click metrics to view detailed logs in Loki
6. **Export:** Export to PDF or snapshot for incident documentation

### Dashboard-Specific Features

**Security Operations:**
- Real-time threat level indicator
- Geographic attack source visualization
- WAF rule effectiveness tracking
- Attack type distribution analysis

**Compliance & Audit:**
- Compliance score trend analysis
- GDPR request processing time tracking
- Audit trail log viewer
- Encryption coverage visualization

**Access & Authentication:**
- Login pattern anomaly detection
- 2FA enrollment tracking by role
- Session lifecycle visualization
- Suspicious login event log

---

## Best Practices

### Dashboard Usage

1. **Daily Monitoring**
   - Start each day by reviewing all three dashboards
   - Check for any overnight security incidents
   - Verify compliance scores are within targets
   - Review authentication success rates

2. **Alert Triage**
   - Respond to P1 alerts within 5 minutes
   - Investigate P2 alerts within 15 minutes
   - Review P3 alerts within 1 hour
   - Follow incident response playbook for each alert type

3. **Trend Analysis**
   - Weekly review of security trends
   - Monthly compliance reporting
   - Quarterly security posture assessment

4. **Evidence Collection**
   - Export dashboard snapshots for all incidents
   - Save Prometheus metrics for forensic analysis
   - Capture Loki logs for detailed investigation

### Metrics Collection

1. **Instrumentation**
   - Instrument all security-relevant events in application code
   - Use consistent metric naming conventions
   - Include relevant labels for filtering (role, ip, attack_type, etc.)
   - Expose metrics via `/metrics` endpoint

2. **Performance**
   - Use counters for events (increment only)
   - Use gauges for current state (can increase/decrease)
   - Use histograms for durations and sizes
   - Keep label cardinality low (avoid high-cardinality labels like user_id in metric names)

3. **Retention**
   - Configure Prometheus retention based on compliance requirements
   - Consider long-term storage with Thanos or Cortex
   - Archive critical security metrics for forensic purposes

### Security Hardening

1. **Dashboard Access**
   - Restrict dashboard viewing to security team
   - Enable authentication for Grafana
   - Use role-based access control (RBAC)
   - Audit dashboard access and modifications

2. **Metrics Endpoint Security**
   - Secure `/metrics` endpoint with authentication
   - Use network policies to restrict Prometheus scraping
   - Monitor for unauthorized metric access

3. **Alert Routing**
   - Test alert delivery regularly
   - Maintain updated on-call rotation
   - Validate escalation paths quarterly
   - Document all alert routing changes

---

## Troubleshooting

### Common Issues

**Dashboard shows "No Data"**
```bash
# Check if Prometheus is scraping CHOM metrics
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="chom")'

# Verify metrics are being exposed
curl http://chom-app:8000/metrics | grep chom_

# Check Prometheus datasource in Grafana
curl -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  http://localhost:3000/api/datasources/uid/prometheus
```

**Metrics showing unexpected values**
```bash
# Query raw metric to verify value
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=chom_security_threat_level'

# Check metric help text for expected range
curl http://chom-app:8000/metrics | grep -A2 chom_security_threat_level
```

**Alerts not triggering**
```bash
# Verify alert rule is loaded
curl http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="chom_security_critical")'

# Check if alert is firing
curl http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="ThreatLevelCritical")'

# Verify AlertManager is receiving alerts
curl http://localhost:9093/api/v2/alerts
```

**Loki logs not showing**
```bash
# Verify Loki datasource
curl -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  http://localhost:3000/api/datasources/uid/loki

# Test Loki query
curl -G 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query={job="authentication"}' \
  --data-urlencode 'limit=10'
```

---

## Support and Maintenance

### Regular Maintenance Tasks

**Weekly:**
- Review dashboard effectiveness and accuracy
- Verify all alerts are functioning correctly
- Update metric thresholds based on baseline changes

**Monthly:**
- Update dashboard panels based on new security requirements
- Review and tune alert rules to reduce false positives
- Audit dashboard access logs

**Quarterly:**
- Comprehensive security posture review
- Update incident response playbook
- Review and update compliance thresholds
- Conduct tabletop exercises using dashboards

### Dashboard Version Control

All dashboard JSON files are version-controlled in Git:

```bash
# Track dashboard changes
git log --follow 1-security-operations.json

# Compare dashboard versions
git diff HEAD~1 1-security-operations.json

# Restore previous version if needed
git checkout HEAD~1 1-security-operations.json
```

---

## References

### Security Standards

- **OWASP Top 10 2021:** https://owasp.org/Top10/
- **NIST Cybersecurity Framework:** https://www.nist.gov/cyberframework
- **CIS Controls:** https://www.cisecurity.org/controls
- **SANS Critical Security Controls:** https://www.sans.org/cloud-security/

### Compliance Frameworks

- **GDPR:** https://gdpr.eu/
- **PCI DSS:** https://www.pcisecuritystandards.org/
- **HIPAA:** https://www.hhs.gov/hipaa/
- **SOC 2:** https://www.aicpa.org/soc

### Monitoring Best Practices

- **Prometheus Best Practices:** https://prometheus.io/docs/practices/
- **Grafana Dashboarding Best Practices:** https://grafana.com/docs/grafana/latest/best-practices/
- **Incident Response Guide (NIST SP 800-61r2):** https://csrc.nist.gov/publications/detail/sp/800-61/rev-2/final

---

## License

These dashboards are part of the CHOM platform and are subject to the same license terms.

---

## Contact

For questions or issues regarding these security dashboards:

- **Security Team:** security@example.com
- **DevOps Team:** devops@example.com
- **Documentation:** https://docs.chom.example.com/security-dashboards

---

**Last Updated:** 2026-01-02
**Dashboard Version:** 1.0
**Compatibility:** Grafana 10.0.0+, Prometheus 2.45.0+, Loki 2.9.0+
