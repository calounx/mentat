# CHOM Security Incident Response Playbook

## Document Control

**Version:** 1.0
**Last Updated:** 2026-01-02
**Owner:** Security Operations Team
**Classification:** CONFIDENTIAL - INTERNAL USE ONLY

---

## Table of Contents

1. [Overview](#overview)
2. [Incident Severity Levels](#incident-severity-levels)
3. [Incident Response Team](#incident-response-team)
4. [Dashboard Alert Mapping](#dashboard-alert-mapping)
5. [Response Procedures by Alert Type](#response-procedures-by-alert-type)
6. [Post-Incident Activities](#post-incident-activities)
7. [Communication Templates](#communication-templates)
8. [Escalation Matrix](#escalation-matrix)

---

## Overview

This playbook provides standardized procedures for responding to security incidents detected through the CHOM Grafana security dashboards. It aligns with NIST SP 800-61r2 (Computer Security Incident Handling Guide) and OWASP incident response best practices.

### Goals

- **Minimize Impact:** Rapidly contain and mitigate security incidents
- **Preserve Evidence:** Maintain forensic integrity for investigation
- **Restore Operations:** Return to normal operations as quickly as possible
- **Prevent Recurrence:** Implement lessons learned to strengthen security posture
- **Maintain Compliance:** Ensure regulatory reporting requirements are met

### Dashboards Reference

- **Dashboard 1:** Security Operations (Threat Detection, WAF, DDoS, IDS)
- **Dashboard 2:** Compliance & Audit (GDPR, Data Governance, Access Control)
- **Dashboard 3:** Access & Authentication (Login Patterns, 2FA, Session Management)

---

## Incident Severity Levels

| Severity | Definition | Response Time | Examples |
|----------|-----------|---------------|----------|
| **P1 - Critical** | Active attack, data breach, or system compromise affecting production | Immediate (5 min) | Active DDoS attack, data exfiltration, ransomware, privilege escalation |
| **P2 - High** | Significant security threat requiring urgent attention | 15 minutes | Multiple failed 2FA attempts, WAF detecting ongoing SQL injection, suspicious admin activity |
| **P3 - Medium** | Security anomaly requiring investigation | 1 hour | Unusual login patterns, elevated failed login rates, compliance violations |
| **P4 - Low** | Security event requiring monitoring | 4 hours | Password policy violations, expired SSL certificates (>30 days), minor rate limit violations |

---

## Incident Response Team

### Roles and Responsibilities

#### Incident Commander (IC)
- **Primary:** Security Team Lead
- **Backup:** DevOps Manager
- **Responsibilities:** Overall incident coordination, decision authority, stakeholder communication

#### Security Analyst
- **Primary:** Security Operations Team
- **Responsibilities:** Alert triage, initial investigation, evidence collection

#### System Administrator
- **Primary:** DevOps Team
- **Responsibilities:** System containment, log collection, access control modifications

#### Communications Lead
- **Primary:** Product Manager
- **Responsibilities:** Internal/external communications, regulatory notifications

#### Legal/Compliance Officer
- **Primary:** Legal Team
- **Responsibilities:** Regulatory compliance, breach notification requirements, evidence preservation

---

## Dashboard Alert Mapping

### Security Operations Dashboard Alerts

| Alert Name | Severity | Dashboard Panel | Threshold |
|------------|----------|-----------------|-----------|
| Threat Level Critical | P1 | Threat Level Gauge | Level = 3 (Critical) |
| Active DDoS Attack | P1 | Active DDoS Attacks | > 0 attacks |
| WAF High Block Rate | P2 | WAF Blocks (5m) | > 100 blocks/5min |
| IDS Critical Alert | P1 | IDS Alerts by Severity | Critical severity spike |
| File Integrity Violation | P2 | File Integrity Violations | > 0 violations |
| Privilege Escalation | P1 | Privilege Escalation (1h) | > 0 attempts |
| SQL Injection Detected | P2 | SQL Injection Blocked | > 10 attempts/hour |
| Security Patches Critical | P3 | Pending Security Patches | > 5 critical patches |

### Compliance & Audit Dashboard Alerts

| Alert Name | Severity | Dashboard Panel | Threshold |
|------------|----------|-----------------|-----------|
| Compliance Score Low | P2 | Overall Compliance Score | < 90% |
| GDPR Violation | P1 | GDPR Violations | > 0 violations |
| Data Breach Risk High | P1 | Data Breach Risk Score | > 70 |
| Retention Exceeded | P2 | Records Exceeding Retention | > 500 records |
| Encryption Coverage Low | P2 | Data-at-Rest Encryption | < 95% |
| Backup Failure | P2 | Backup Compliance Status | Failed backups |
| SSL Certificate Expiring | P3 | SSL Certificate Expiration | < 30 days |

### Access & Authentication Dashboard Alerts

| Alert Name | Severity | Dashboard Panel | Threshold |
|------------|----------|-----------------|-----------|
| Brute Force Attack | P1 | Failed Logins (1h) | > 100 failures/hour |
| Account Lockout Spike | P2 | Account Lockouts (1h) | > 10 lockouts/hour |
| Suspicious Login Pattern | P2 | Suspicious Logins (1h) | > 5 events/hour |
| 2FA Bypass Attempt | P1 | 2FA Verification Activity | Multiple 2FA failures |
| Session Hijacking | P1 | Session Hijacking Attempts | > 0 attempts |
| Weak Password Compliance | P3 | Users with Weak Passwords | > 20 users |
| API Auth Failures | P2 | API Authentication Failures | > 50 failures/5min |
| Impossible Travel | P1 | Suspicious Login Patterns | Impossible travel detected |

---

## Response Procedures by Alert Type

### 1. Active DDoS Attack (P1)

**Alert Source:** Security Operations Dashboard > Active DDoS Attacks

**Immediate Actions (0-5 minutes):**

1. **Verify Alert**
   - Check Dashboard: Confirm `chom_ddos_attacks_active > 0`
   - Validate Metrics: Review "Request Rate & DDoS Mitigation" panel
   - Check Logs: `{job="nginx"} |= "ddos"`

2. **Activate Incident Commander**
   - Page IC via PagerDuty/Slack
   - Declare P1 incident
   - Open incident war room (Slack #incident-response)

3. **Initial Containment**
   ```bash
   # Enable aggressive rate limiting
   kubectl patch configmap nginx-config -p '{"data":{"rate-limit":"10r/s"}}'

   # Block top attacking IPs (top 10)
   curl -X POST http://localhost:9090/api/v1/query \
     -d 'query=topk(10, rate(chom_http_requests_blocked_ddos_total[1m]) by (ip))' \
     | jq -r '.data.result[].metric.ip' \
     | xargs -I {} fail2ban-client set nginx banip {}
   ```

4. **Enable DDoS Mitigation**
   - Activate Cloudflare "I'm Under Attack" mode (if applicable)
   - Enable WAF DDoS rules
   - Implement geographic blocking if pattern detected

**Investigation (5-30 minutes):**

5. **Analyze Attack Pattern**
   - Review "Top Attack Source Countries" panel
   - Identify attack vector (Layer 3/4 vs Layer 7)
   - Check Loki logs for attack signatures:
     ```logql
     {job="nginx"}
     |= "ddos"
     | json
     | line_format "{{.timestamp}} | {{.ip}} | {{.method}} | {{.path}} | {{.user_agent}}"
     ```

6. **Collect Evidence**
   - Export Grafana dashboard snapshot
   - Save Prometheus metrics: `curl http://localhost:9090/api/v1/query_range ...`
   - Capture network traffic: `tcpdump -i eth0 -w ddos-$(date +%Y%m%d-%H%M%S).pcap`

7. **Assess Impact**
   - Check application availability
   - Review error rates and response times
   - Identify affected services

**Mitigation (30-60 minutes):**

8. **Scale Resources**
   ```bash
   # Auto-scale pods
   kubectl autoscale deployment chom-app --min=5 --max=20 --cpu-percent=70

   # Increase rate limits gradually
   kubectl patch configmap nginx-config -p '{"data":{"rate-limit":"50r/s"}}'
   ```

9. **Network-Level Filtering**
   - Configure upstream ISP/CDN to filter malicious traffic
   - Implement SYN cookies for TCP flood protection
   - Enable connection rate limiting at firewall

10. **Monitor Effectiveness**
    - Track "Request Rate & DDoS Mitigation" panel
    - Confirm legitimate traffic is passing through
    - Validate business KPIs are recovering

**Recovery & Post-Incident:**

11. **Gradual Service Restoration**
    - Remove temporary blocks once attack subsides
    - Return rate limits to normal
    - Monitor for attack resumption (common pattern)

12. **Post-Incident Report** (See Section 6)

**Prevention Recommendations:**
- Implement CDN-based DDoS protection (Cloudflare, Akamai)
- Configure automatic rate limiting rules
- Set up geo-blocking for high-risk regions
- Implement CAPTCHA for suspicious traffic

---

### 2. Brute Force Attack (P1)

**Alert Source:** Access & Authentication Dashboard > Failed Logins

**Immediate Actions (0-5 minutes):**

1. **Verify Attack Pattern**
   - Check Dashboard: `chom_auth_failed_total > 100` in 1 hour
   - Review "Top Failed Login IPs" panel
   - Identify targeted accounts

2. **Automatic Account Protection**
   ```bash
   # Lock targeted accounts immediately
   php artisan chom:security:lock-accounts --failed-attempts=5 --duration=1h

   # Force logout all sessions for targeted accounts
   php artisan chom:security:revoke-sessions --user-ids=$(
     curl -s http://localhost:9090/api/v1/query \
       -d 'query=chom_auth_failed_total > 10' \
       | jq -r '.data.result[].metric.user_id'
   )
   ```

3. **Block Attacking IPs**
   ```bash
   # Ban IPs with >10 failed attempts
   curl -X POST http://localhost:9090/api/v1/query \
     -d 'query=topk(20, rate(chom_auth_failed_total[5m]) by (ip))' \
     | jq -r '.data.result[].metric.ip' \
     | xargs -I {} fail2ban-client set chom-auth banip {}
   ```

**Investigation (5-30 minutes):**

4. **Analyze Attack Pattern**
   - Review Loki logs:
     ```logql
     {job="authentication"}
     |= "failed_login"
     | json
     | line_format "{{.timestamp}} | {{.ip}} | {{.username}} | {{.user_agent}}"
     ```
   - Identify if credential stuffing (multiple usernames) or targeted attack
   - Check for distributed attack (multiple IPs)

5. **Assess Compromise**
   - Check for any successful logins from attacking IPs:
     ```promql
     chom_auth_success_total{ip=~"<attacking_ip_pattern>"}
     ```
   - Review "Suspicious Login Patterns" for correlated activity
   - Verify 2FA status for targeted accounts

6. **Evidence Collection**
   - Export failed login attempts to CSV
   - Save IP geolocation data
   - Capture user agent strings for fingerprinting

**Mitigation (30-60 minutes):**

7. **Strengthen Authentication**
   ```bash
   # Enable CAPTCHA for all login attempts temporarily
   php artisan config:set security.captcha_enabled=true

   # Reduce login attempt threshold
   php artisan config:set security.max_login_attempts=3

   # Increase lockout duration
   php artisan config:set security.lockout_duration=3600
   ```

8. **Notify Affected Users**
   - Send security alert emails to targeted accounts
   - Force password reset for compromised accounts
   - Require 2FA enrollment for affected users

9. **Network-Level Protection**
   ```bash
   # Update firewall rules
   iptables -A INPUT -p tcp --dport 443 -m state --state NEW \
     -m recent --set --name BRUTE_FORCE

   iptables -A INPUT -p tcp --dport 443 -m state --state NEW \
     -m recent --update --seconds 60 --hitcount 10 \
     --name BRUTE_FORCE -j DROP
   ```

**Recovery:**

10. **Monitor for Attack Cessation**
    - Track failed login rate returning to baseline
    - Verify no new attacking IPs emerging
    - Confirm legitimate users can authenticate

11. **Gradual Lockdown Removal**
    - Remove CAPTCHA after 24 hours of normal activity
    - Unblock IPs after 7 days (maintain watchlist)
    - Return authentication thresholds to normal

**Prevention Recommendations:**
- Implement risk-based authentication (device fingerprinting)
- Deploy honeypot login forms to detect automated attacks
- Enable Cloudflare Bot Fight Mode
- Require 2FA for all users (not just privileged accounts)
- Implement progressive delays on failed logins

---

### 3. SQL Injection Attack (P2)

**Alert Source:** Security Operations Dashboard > SQL Injection Blocked

**Immediate Actions (0-15 minutes):**

1. **Verify Attack**
   - Check Dashboard: `chom_waf_sql_injection_blocked_total > 10/hour`
   - Review "WAF Blocks by Attack Type" for spike
   - Validate WAF is blocking effectively

2. **Prevent Database Access**
   ```bash
   # If attacks are bypassing WAF, restrict DB access
   # Allow only application server IPs
   mysql -e "UPDATE mysql.user SET Host='10.0.1.100' WHERE User='chom';"
   mysql -e "FLUSH PRIVILEGES;"
   ```

3. **Capture Attack Payloads**
   ```bash
   # Export WAF logs with SQL injection attempts
   curl -G 'http://loki:3100/loki/api/v1/query_range' \
     --data-urlencode 'query={job="waf"} |= "sql_injection"' \
     --data-urlencode 'start='$(date -d '1 hour ago' +%s)000000000 \
     > sqli-attack-$(date +%Y%m%d-%H%M%S).json
   ```

**Investigation (15-45 minutes):**

4. **Analyze Attack Vectors**
   - Review "Top WAF Rules Triggered" panel
   - Identify exploited endpoints:
     ```logql
     {job="waf"}
     |= "sql_injection"
     | json
     | line_format "{{.endpoint}} | {{.payload}} | {{.ip}}"
     ```
   - Determine if attacks target specific vulnerability

5. **Assess Application Vulnerability**
   ```bash
   # Check for parameterized queries
   grep -r "DB::raw\|->whereRaw" app/ --exclude-dir=vendor

   # Review Laravel query builder usage
   grep -r "->where(" app/ | grep -v "->where(\["
   ```

6. **Database Integrity Check**
   ```sql
   -- Check for unauthorized changes
   SELECT * FROM mysql.general_log
   WHERE command_type = 'Query'
   AND argument LIKE '%UNION%' OR argument LIKE '%DROP%'
   ORDER BY event_time DESC LIMIT 100;

   -- Review recent admin actions
   SELECT * FROM audit_log
   WHERE action IN ('INSERT', 'UPDATE', 'DELETE')
   AND created_at > DATE_SUB(NOW(), INTERVAL 2 HOUR)
   ORDER BY created_at DESC;
   ```

**Mitigation (45-60 minutes):**

7. **Harden WAF Rules**
   ```bash
   # Enable stricter ModSecurity rules
   echo "SecRuleEngine On" >> /etc/modsecurity/modsecurity.conf
   echo "SecRule REQUEST_FILENAME|ARGS_NAMES|ARGS \"@detectSQLi\" \\
     \"id:1000001,phase:2,block,log,msg:'SQL Injection Attack'\"" \
     >> /etc/modsecurity/custom_rules.conf

   # Reload WAF
   systemctl reload nginx
   ```

8. **Code Review and Patching**
   - Identify vulnerable code patterns
   - Implement parameterized queries:
     ```php
     // BEFORE (Vulnerable)
     DB::select("SELECT * FROM users WHERE email = '{$email}'");

     // AFTER (Secure)
     DB::select("SELECT * FROM users WHERE email = ?", [$email]);
     ```
   - Deploy emergency patch to production

9. **Input Validation**
   ```php
   // Add strict validation rules
   $request->validate([
       'email' => 'required|email|max:255',
       'search' => 'required|string|max:100|regex:/^[a-zA-Z0-9\s]+$/',
   ]);
   ```

**Recovery:**

10. **Verify Mitigation**
    - Attempt safe SQL injection payloads against test environment
    - Confirm WAF blocks all variants
    - Validate application functions correctly with legitimate input

11. **Database Forensics** (if breach suspected)
    ```sql
    -- Export database state for forensics
    mysqldump --all-databases > backup-forensic-$(date +%Y%m%d).sql

    -- Review user privileges
    SELECT User, Host, Select_priv, Insert_priv, Update_priv, Delete_priv
    FROM mysql.user;
    ```

**Prevention Recommendations:**
- Implement ORM/query builder exclusively (no raw SQL)
- Enable Laravel's mass assignment protection
- Deploy static code analysis (SAST) in CI/CD pipeline
- Conduct regular penetration testing
- Implement Content Security Policy (CSP) headers

---

### 4. GDPR Data Breach (P1)

**Alert Source:** Compliance & Audit Dashboard > GDPR Violations

**Immediate Actions (0-5 minutes):**

1. **Verify Breach**
   - Check Dashboard: `chom_gdpr_violations_total > 0`
   - Review "GDPR Violations Over Time" for breach type
   - Confirm personal data exposure

2. **Activate Legal Team**
   - Immediate notification to Data Protection Officer (DPO)
   - Engage legal counsel
   - Start breach notification timer (72-hour GDPR requirement)

3. **Contain Data Exposure**
   ```bash
   # If data exfiltration detected, block external access
   iptables -A OUTPUT -p tcp --dport 443 -j DROP  # Temporary measure

   # Revoke database access credentials
   mysql -e "REVOKE ALL PRIVILEGES ON *.* FROM 'compromised_user'@'%';"
   mysql -e "FLUSH PRIVILEGES;"
   ```

**Investigation (5-60 minutes):**

4. **Determine Breach Scope**
   ```sql
   -- Identify exposed personal data
   SELECT
     table_name,
     COUNT(*) as record_count,
     'Contains PII' as data_type
   FROM information_schema.columns
   WHERE table_schema = 'chom'
   AND column_name IN ('email', 'name', 'phone', 'address', 'ssn', 'passport')
   GROUP BY table_name;

   -- Check audit log for unauthorized access
   SELECT * FROM audit_log
   WHERE action = 'SELECT'
   AND resource_type = 'User'
   AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
   ORDER BY created_at DESC;
   ```

5. **Identify Affected Data Subjects**
   ```sql
   -- Export list of affected users
   SELECT
     id,
     email,
     name,
     created_at,
     country  -- For determining supervisory authority
   FROM users
   WHERE id IN (
     SELECT DISTINCT user_id FROM audit_log
     WHERE action = 'UNAUTHORIZED_ACCESS'
     AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
   )
   INTO OUTFILE '/tmp/affected-users.csv';
   ```

6. **Evidence Preservation**
   ```bash
   # Freeze database state
   mysqldump --all-databases --single-transaction \
     > gdpr-breach-evidence-$(date +%Y%m%d-%H%M%S).sql

   # Export all relevant logs
   journalctl --since "24 hours ago" > system-logs-$(date +%Y%m%d).log

   # Loki log export
   curl -G 'http://loki:3100/loki/api/v1/query_range' \
     --data-urlencode 'query={job=~".*"}' \
     --data-urlencode 'start='$(date -d '24 hours ago' +%s)000000000 \
     > loki-logs-$(date +%Y%m%d).json
   ```

**Mitigation (1-4 hours):**

7. **Assess Breach Categories (GDPR Article 33)**
   - [ ] **Confidentiality Breach:** Unauthorized access to personal data
   - [ ] **Integrity Breach:** Alteration of personal data
   - [ ] **Availability Breach:** Loss or destruction of personal data

8. **Risk Assessment for Data Subjects**
   - **Low Risk:** No notification required to individuals
   - **High Risk:** Must notify affected individuals "without undue delay"

   Risk factors:
   - Sensitive data exposed (health, biometric, financial)?
   - Data already publicly available?
   - Encryption status of exposed data?
   - Number of affected individuals?

9. **Supervisory Authority Notification (72-hour deadline)**

   Required information per GDPR Article 33(3):
   - Nature of breach (confidentiality/integrity/availability)
   - Categories and approximate number of data subjects affected
   - Categories and approximate number of personal data records
   - Contact details of DPO
   - Likely consequences of breach
   - Measures taken or proposed to address breach

**Recovery:**

10. **Individual Notification** (if high risk)

    Email template to affected users:
    ```
    Subject: Important Security Notice - Data Breach Notification

    Dear [Name],

    We are writing to inform you of a data security incident that may
    have affected your personal information.

    What Happened:
    On [DATE], we discovered that [DESCRIPTION OF BREACH].

    What Information Was Involved:
    The following information may have been accessed: [LIST DATA TYPES]

    What We Are Doing:
    [MITIGATION STEPS TAKEN]

    What You Can Do:
    [RECOMMENDED ACTIONS FOR USERS]

    For More Information:
    Contact our Data Protection Officer at dpo@example.com

    We sincerely apologize for this incident.
    ```

11. **Documentation and Reporting**
    - Complete GDPR breach register entry (Article 33(5))
    - Notify relevant supervisory authorities
    - Document all breach response actions
    - Update incident response procedures based on lessons learned

**Prevention Recommendations:**
- Implement data minimization (GDPR Article 5)
- Enable encryption at rest for all PII
- Deploy Data Loss Prevention (DLP) tools
- Regular GDPR compliance audits
- Staff training on data protection

---

### 5. Privilege Escalation Attempt (P1)

**Alert Source:** Security Operations Dashboard > Privilege Escalation

**Immediate Actions (0-5 minutes):**

1. **Verify Alert**
   - Check Dashboard: `chom_security_privilege_escalation_attempts_total > 0`
   - Identify compromised account
   - Review "Admin Privilege Usage" panel

2. **Revoke Elevated Access**
   ```bash
   # Immediately revoke admin privileges for suspicious account
   php artisan chom:security:revoke-role --user-id=<USER_ID> --role=admin

   # Force logout all sessions
   php artisan chom:security:revoke-sessions --user-id=<USER_ID>

   # Disable account pending investigation
   php artisan chom:users:disable --user-id=<USER_ID> --reason="Security: Privilege escalation attempt"
   ```

3. **Lock Down Admin Functions**
   ```bash
   # Enable additional authentication for admin panel
   php artisan config:set security.admin_require_2fa=true
   php artisan config:set security.admin_require_approval=true
   ```

**Investigation (5-30 minutes):**

4. **Analyze Escalation Method**
   ```logql
   {job="authentication"}
   |= "privilege_escalation"
   | json
   | line_format "{{.timestamp}} | {{.user_id}} | {{.attempted_role}} | {{.method}} | {{.ip}}"
   ```

   Common escalation vectors:
   - **Insecure Direct Object Reference (IDOR):** Manipulating user ID parameters
   - **Mass Assignment:** Adding admin fields to registration/update requests
   - **JWT Token Manipulation:** Modifying role claims in JWT
   - **SQL Injection:** Updating user roles via SQL injection
   - **Authorization Bypass:** Accessing admin endpoints without proper checks

5. **Check for Vulnerability Exploitation**
   ```bash
   # Review recent code changes
   git log --since="7 days ago" --grep="role\|permission\|admin" --oneline

   # Check for authorization middleware
   grep -r "->middleware('admin')" routes/
   grep -r "->can('admin')" app/Http/Controllers/

   # Review role assignment logic
   grep -r "assignRole\|syncRoles\|attachRole" app/
   ```

6. **Identify Affected Resources**
   ```sql
   -- Check what admin actions were performed
   SELECT * FROM audit_log
   WHERE user_id = <SUSPICIOUS_USER_ID>
   AND action IN ('role_assigned', 'permission_granted', 'config_changed')
   AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
   ORDER BY created_at DESC;

   -- Review unauthorized access to sensitive data
   SELECT * FROM audit_log
   WHERE user_id = <SUSPICIOUS_USER_ID>
   AND resource_type IN ('User', 'Settings', 'ApiKey')
   AND created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR);
   ```

**Mitigation (30-60 minutes):**

7. **Patch Vulnerability**

   Example fixes:

   **IDOR Prevention:**
   ```php
   // BEFORE (Vulnerable)
   $user = User::findOrFail($request->input('user_id'));
   $user->role = 'admin';
   $user->save();

   // AFTER (Secure)
   $user = User::findOrFail($request->input('user_id'));
   $this->authorize('update', $user);  // Policy check
   $user->role = $request->input('role');  // Will be validated
   $user->save();
   ```

   **Mass Assignment Protection:**
   ```php
   // Add to User model
   protected $guarded = ['role', 'is_admin', 'permissions'];

   // Or use fillable whitelist
   protected $fillable = ['name', 'email', 'password'];
   ```

   **JWT Role Verification:**
   ```php
   // Verify role claim matches database
   public function handle($request, Closure $next) {
       $token_role = $request->user()->token()->role;
       $db_role = $request->user()->role;

       if ($token_role !== $db_role) {
           abort(403, 'Token role mismatch - potential tampering');
       }

       return $next($request);
   }
   ```

8. **Harden Authorization**
   ```php
   // Implement strict authorization policy
   Gate::define('assign-role', function (User $user, User $target, string $role) {
       // Only owners can assign admin roles
       if ($role === 'admin' && !$user->isOwner()) {
           Log::warning('Privilege escalation attempt', [
               'user_id' => $user->id,
               'target_id' => $target->id,
               'attempted_role' => $role,
           ]);
           return false;
       }

       // Users can't elevate their own privileges
       if ($user->id === $target->id) {
           return false;
       }

       return $user->can('manage-users');
   });
   ```

9. **Audit All Admin Accounts**
   ```sql
   -- Review all admin role assignments
   SELECT
     u.id,
     u.email,
     u.name,
     r.name as role,
     ra.created_at as role_assigned_at
   FROM users u
   JOIN role_user ra ON u.id = ra.user_id
   JOIN roles r ON ra.role_id = r.id
   WHERE r.name IN ('admin', 'owner')
   ORDER BY ra.created_at DESC;
   ```

**Recovery:**

10. **Restore Legitimate Access**
    - Review all admin accounts for legitimacy
    - Reset passwords for all admin accounts
    - Re-enable 2FA for all privileged accounts
    - Document authorized privilege changes

11. **Enhanced Monitoring**
    ```php
    // Add real-time alerting for privilege changes
    Event::listen(RoleAssigned::class, function ($event) {
        if (in_array($event->role, ['admin', 'owner'])) {
            Notification::send(
                User::admins(),
                new PrivilegeEscalationAttempt($event->user, $event->role)
            );
        }
    });
    ```

**Prevention Recommendations:**
- Implement "principle of least privilege" across all roles
- Require multi-party approval for admin role assignments
- Enable detailed audit logging for all privilege changes
- Regular access reviews (quarterly)
- Implement "just-in-time" privileged access (temporary elevation)

---

### 6. Compliance Score Below Threshold (P2)

**Alert Source:** Compliance & Audit Dashboard > Overall Compliance Score

**Immediate Actions (0-15 minutes):**

1. **Identify Compliance Gaps**
   - Check Dashboard: `chom_compliance_score < 0.90`
   - Review "Active Violations" panel
   - Analyze specific compliance failures:
     - GDPR compliance score
     - Data retention adherence
     - Encryption coverage
     - Backup compliance

2. **Prioritize Critical Violations**
   ```sql
   -- Export compliance violations by severity
   SELECT
     violation_type,
     severity,
     COUNT(*) as count,
     MIN(detected_at) as first_detected
   FROM compliance_violations
   WHERE status = 'active'
   GROUP BY violation_type, severity
   ORDER BY
     FIELD(severity, 'critical', 'high', 'medium', 'low'),
     count DESC;
   ```

3. **Notify Compliance Team**
   - Alert Data Protection Officer
   - Schedule emergency compliance review
   - Prepare violation report for management

**Investigation (15-60 minutes):**

4. **Data Retention Violations**
   - Check "Records Exceeding Retention" panel
   - Identify data categories out of compliance:
     ```sql
     -- Find data exceeding retention policy
     SELECT
       table_name,
       COUNT(*) as records_over_retention,
       MAX(DATEDIFF(NOW(), created_at)) as max_age_days
     FROM (
       SELECT 'users' as table_name, created_at
       FROM users WHERE deleted_at IS NULL
       AND created_at < DATE_SUB(NOW(), INTERVAL 5 YEAR)

       UNION ALL

       SELECT 'sessions' as table_name, created_at
       FROM sessions
       AND created_at < DATE_SUB(NOW(), INTERVAL 90 DAY)

       -- Add other tables with retention policies
     ) as retention_check
     GROUP BY table_name;
     ```

5. **Encryption Compliance**
   - Review "Data-at-Rest Encryption Coverage"
   - Identify unencrypted data stores:
     ```bash
     # Check database encryption status
     mysql -e "SHOW VARIABLES LIKE '%encrypt%';"

     # Verify filesystem encryption
     lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,ENCRYPTION

     # Check backup encryption
     ls -lh /backups/ | grep -v ".enc$"  # Unencrypted backups
     ```

6. **Backup Compliance**
   - Verify "Backup Compliance Status" panel
   - Check backup frequency and retention:
     ```bash
     # List recent backups
     ls -lht /backups/ | head -20

     # Verify backup completeness
     find /backups -name "*.sql" -mtime -1 | wc -l  # Should be >= 1
     ```

**Mitigation (1-4 hours):**

7. **Execute Data Purge**
   ```bash
   # Run data retention cleanup job
   php artisan chom:compliance:purge-expired-data --dry-run

   # Review what will be deleted
   cat storage/logs/purge-dry-run.log

   # Execute actual purge
   php artisan chom:compliance:purge-expired-data --force

   # Verify compliance improvement
   php artisan chom:compliance:calculate-score
   ```

8. **Enable Missing Encryption**
   ```bash
   # Enable database encryption
   mysql -e "ALTER TABLE users ENCRYPTION='Y';"
   mysql -e "ALTER TABLE personal_data ENCRYPTION='Y';"

   # Encrypt existing backups
   for backup in /backups/*.sql; do
     gpg --encrypt --recipient security@example.com "$backup"
     rm "$backup"  # Remove unencrypted version
   done

   # Update backup script to encrypt
   echo "gpg --encrypt --recipient security@example.com" \
     >> /scripts/backup.sh
   ```

9. **Fix Backup Compliance**
   ```bash
   # Enable automated backups
   crontab -e
   # Add: 0 2 * * * /scripts/backup.sh  # Daily at 2 AM

   # Configure backup retention
   cat > /etc/backup-policy.conf <<EOF
   RETENTION_DAILY=7
   RETENTION_WEEKLY=4
   RETENTION_MONTHLY=12
   RETENTION_YEARLY=7
   EOF

   # Run backup rotation script
   /scripts/rotate-backups.sh
   ```

**Recovery:**

10. **Verify Compliance Improvement**
    - Monitor "Overall Compliance Score" returning to >90%
    - Confirm "Active Violations" count decreasing
    - Validate metrics:
      ```promql
      # Check compliance score trend
      rate(chom_compliance_score[1h])

      # Verify violation resolution
      chom_compliance_violations_active
      ```

11. **Document Remediation Actions**
    - Log all compliance fixes in audit system
    - Update compliance documentation
    - Schedule follow-up review (1 week)

**Prevention Recommendations:**
- Implement automated compliance checks in CI/CD
- Schedule quarterly compliance audits
- Enable real-time compliance monitoring alerts
- Maintain compliance runbook with remediation procedures
- Regular staff training on compliance requirements

---

## Post-Incident Activities

### 1. Incident Documentation

Complete within 24 hours of incident resolution:

**Incident Report Template:**

```markdown
# Security Incident Report

**Incident ID:** INC-[YYYY-MM-DD]-[###]
**Severity:** [P1/P2/P3/P4]
**Status:** [Resolved/Ongoing]
**Incident Commander:** [Name]

## Executive Summary
[2-3 sentence summary of incident]

## Timeline
- **Detection:** [Date/Time] - [How detected]
- **Response:** [Date/Time] - [Initial actions taken]
- **Containment:** [Date/Time] - [How threat was contained]
- **Eradication:** [Date/Time] - [How threat was removed]
- **Recovery:** [Date/Time] - [How service was restored]
- **Lessons Learned:** [Date/Time] - [Post-incident review completed]

## Impact Assessment
- **Users Affected:** [Number]
- **Data Compromised:** [Yes/No - Description]
- **Downtime:** [Duration]
- **Financial Impact:** [$Amount]
- **Regulatory Impact:** [GDPR breach notification, etc.]

## Root Cause Analysis
[Detailed analysis of how incident occurred]

## Response Actions Taken
1. [Action 1]
2. [Action 2]
...

## Evidence Collected
- [ ] Log files exported
- [ ] Dashboard snapshots saved
- [ ] Network traffic captures
- [ ] Database forensic backups
- [ ] Attacker IP addresses documented

## Remediation Actions
- [ ] Immediate fixes deployed
- [ ] Vulnerability patched
- [ ] Security controls enhanced
- [ ] Monitoring improved

## Lessons Learned
**What Went Well:**
- [Item 1]
- [Item 2]

**What Could Be Improved:**
- [Item 1]
- [Item 2]

**Action Items:**
- [ ] [Action item with owner and due date]
- [ ] [Action item with owner and due date]
```

### 2. Lessons Learned Meeting

Schedule within 3 business days of major incidents (P1/P2):

**Agenda:**
1. Incident timeline review (10 min)
2. What went well (10 min)
3. What could be improved (15 min)
4. Action item identification (15 min)
5. Playbook updates (10 min)

**Attendees:**
- Incident Commander
- All responders
- Management (for P1 incidents)
- Product/Engineering leads

### 3. Compliance Reporting

**GDPR Data Breach (Article 33):**
- **Deadline:** 72 hours from breach awareness
- **Recipient:** Relevant supervisory authority
- **Content:** See "GDPR Data Breach" response procedure

**HIPAA Breach Notification (if applicable):**
- **Deadline:** 60 days
- **Recipients:** Affected individuals, HHS, media (if >500 people affected)

**PCI DSS Incident Reporting (if applicable):**
- **Deadline:** Immediate for suspected compromise
- **Recipients:** Payment brands, acquiring bank

### 4. Security Control Enhancements

Update security posture based on incident:

1. **Firewall Rules**
   ```bash
   # Document new firewall rules
   iptables-save > /etc/iptables/rules.v4.$(date +%Y%m%d)

   # Update firewall documentation
   vim /docs/firewall-rules.md
   ```

2. **WAF Rules**
   ```bash
   # Export updated ModSecurity rules
   cp /etc/modsecurity/custom_rules.conf \
      /etc/modsecurity/custom_rules.conf.$(date +%Y%m%d)
   ```

3. **Monitoring Rules**
   ```yaml
   # Update Prometheus alerting rules
   vim /etc/prometheus/alerts/security.yml

   # Add new alert based on incident pattern
   groups:
     - name: security_incidents
       rules:
         - alert: [NewThreatPattern]
           expr: [Metric expression]
           for: [Duration]
           annotations:
             summary: "New threat detected"
             description: "Learned from incident INC-[ID]"
   ```

4. **Access Control Updates**
   ```bash
   # Review and update RBAC policies
   php artisan chom:security:audit-permissions

   # Document changes in access control policy
   vim /docs/access-control-policy.md
   ```

### 5. Metrics and KPIs

Track incident response effectiveness:

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Mean Time to Detect (MTTD)** | < 5 minutes | Time from incident start to alert |
| **Mean Time to Respond (MTTR)** | < 15 minutes (P1) | Time from alert to response action |
| **Mean Time to Contain (MTTC)** | < 30 minutes (P1) | Time from alert to containment |
| **Mean Time to Recover (MTTR)** | < 2 hours (P1) | Time from alert to full recovery |
| **False Positive Rate** | < 10% | Alerts that were not actual incidents |

---

## Communication Templates

### Internal Alert (Slack/Teams)

```
🚨 SECURITY INCIDENT - P[1/2/3/4]

**Incident:** [Brief description]
**Status:** [ACTIVE/CONTAINED/RESOLVED]
**Severity:** P[1/2/3/4]
**Incident Commander:** @[username]
**War Room:** #incident-[YYYYMMDD-###]

**Impact:**
- Users affected: [Number/None]
- Services impacted: [List/None]
- Data exposure: [Yes/No]

**Actions Required:**
- [ ] [Action item for specific team]
- [ ] [Action item for specific team]

**Next Update:** [Time]
```

### Customer Communication (P1 Incidents)

**Status Page Update:**

```
Investigating: We are currently investigating reports of [issue description].
We will provide updates as more information becomes available.

Posted: [Time] UTC
```

```
Identified: We have identified the issue affecting [service/feature].
Our team is working on a fix.

Posted: [Time] UTC
```

```
Monitoring: A fix has been implemented and we are monitoring the results.

Posted: [Time] UTC
```

```
Resolved: This incident has been resolved. All services are operating normally.
We apologize for any inconvenience.

Posted: [Time] UTC
```

### Executive Summary (P1/P2)

```
Subject: Security Incident Summary - [Date]

Executive Summary:

On [DATE] at [TIME], we detected and responded to a [P1/P2] security
incident involving [BRIEF DESCRIPTION].

Impact:
- Duration: [X hours]
- Users affected: [Number]
- Data exposure: [Yes/No with details]
- Service availability: [Percentage]

Response:
The incident was detected via [DETECTION METHOD] and contained within
[TIME]. We have [REMEDIATION SUMMARY].

Current Status:
[RESOLVED/MONITORING/ONGOING] - [Brief status]

Next Steps:
1. [Action item 1]
2. [Action item 2]

A full incident report will be available within 24 hours.

[Incident Commander Name]
[Contact Information]
```

---

## Escalation Matrix

| Severity | Initial Response | Escalation (15 min) | Escalation (30 min) | Escalation (1 hour) |
|----------|------------------|---------------------|---------------------|---------------------|
| **P1 - Critical** | Security Analyst | Security Team Lead + DevOps Manager | VP Engineering + DPO | CTO + CEO |
| **P2 - High** | Security Analyst | Security Team Lead | VP Engineering | CTO (if ongoing) |
| **P3 - Medium** | Security Analyst | Security Team Lead (if ongoing) | - | - |
| **P4 - Low** | Security Analyst | - | - | - |

### Contact Information

**Security Team:**
- Security Team Lead: [Name] - [Phone] - [Email]
- Security Analyst (On-Call): [PagerDuty Rotation]
- Security Analyst (Backup): [Name] - [Phone]

**Engineering Leadership:**
- VP Engineering: [Name] - [Phone] - [Email]
- DevOps Manager: [Name] - [Phone] - [Email]

**Legal/Compliance:**
- Data Protection Officer: [Name] - [Phone] - [Email]
- Legal Counsel: [Name] - [Phone] - [Email]

**Executive Team:**
- CTO: [Name] - [Phone] - [Email]
- CEO: [Name] - [Phone] - [Email]

**External Contacts:**
- Cyber Insurance: [Company] - [Policy #] - [Phone]
- Legal Counsel (External): [Firm] - [Phone]
- Incident Response Retainer: [Company] - [Phone]

---

## Appendix A: Security Tools Reference

### Dashboard URLs

- **Security Operations:** http://grafana:3000/d/chom-security-operations
- **Compliance & Audit:** http://grafana:3000/d/chom-compliance-audit
- **Access & Authentication:** http://grafana:3000/d/chom-access-authentication

### Log Query Examples

**Prometheus:**
```bash
# Query current threat level
curl 'http://localhost:9090/api/v1/query?query=chom_security_threat_level'

# Query failed logins in last hour
curl 'http://localhost:9090/api/v1/query?query=increase(chom_auth_failed_total[1h])'

# Export time-series data
curl -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(chom_waf_requests_blocked_total[5m])' \
  --data-urlencode 'start=2026-01-02T00:00:00Z' \
  --data-urlencode 'end=2026-01-02T23:59:59Z' \
  --data-urlencode 'step=300s'
```

**Loki:**
```bash
# Query authentication logs
curl -G 'http://loki:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="authentication"} |= "failed_login"' \
  --data-urlencode 'start='$(date -d '1 hour ago' +%s)000000000

# Query WAF logs
curl -G 'http://loki:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="waf"} |= "blocked"' \
  --data-urlencode 'limit=100'
```

### Evidence Collection Script

```bash
#!/bin/bash
# Security Incident Evidence Collection Script
# Usage: ./collect-evidence.sh [incident-id]

INCIDENT_ID=$1
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
EVIDENCE_DIR="/var/security/incidents/${INCIDENT_ID}"

mkdir -p "${EVIDENCE_DIR}"

echo "[*] Collecting evidence for incident ${INCIDENT_ID}"

# Export Grafana dashboards
echo "[*] Exporting Grafana dashboards..."
curl -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  http://localhost:3000/api/dashboards/uid/chom-security-operations \
  > "${EVIDENCE_DIR}/dashboard-security-ops-${TIMESTAMP}.json"

# Export Prometheus metrics
echo "[*] Exporting Prometheus metrics..."
curl -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query={__name__=~"chom_.*"}' \
  --data-urlencode 'start='$(date -d '2 hours ago' +%s) \
  --data-urlencode 'end='$(date +%s) \
  > "${EVIDENCE_DIR}/prometheus-metrics-${TIMESTAMP}.json"

# Export Loki logs
echo "[*] Exporting Loki logs..."
curl -G 'http://loki:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job=~".*"}' \
  --data-urlencode 'start='$(date -d '2 hours ago' +%s)000000000 \
  > "${EVIDENCE_DIR}/loki-logs-${TIMESTAMP}.json"

# Database snapshot
echo "[*] Creating database snapshot..."
mysqldump --all-databases --single-transaction \
  > "${EVIDENCE_DIR}/database-${TIMESTAMP}.sql"

# System logs
echo "[*] Collecting system logs..."
journalctl --since "2 hours ago" > "${EVIDENCE_DIR}/system-logs-${TIMESTAMP}.log"

# Network state
echo "[*] Capturing network state..."
netstat -tulanp > "${EVIDENCE_DIR}/network-state-${TIMESTAMP}.txt"
iptables -L -n -v > "${EVIDENCE_DIR}/firewall-rules-${TIMESTAMP}.txt"

# Create tarball
echo "[*] Creating evidence archive..."
tar -czf "${EVIDENCE_DIR}.tar.gz" -C /var/security/incidents "${INCIDENT_ID}"

echo "[*] Evidence collection complete: ${EVIDENCE_DIR}.tar.gz"
echo "[*] SHA256: $(sha256sum ${EVIDENCE_DIR}.tar.gz | cut -d' ' -f1)"
```

---

## Appendix B: Regulatory Compliance Checklists

### GDPR Breach Notification Checklist

Within 72 hours of becoming aware of a breach:

- [ ] Describe nature of breach (confidentiality/integrity/availability)
- [ ] Provide contact details of Data Protection Officer
- [ ] Describe likely consequences of breach
- [ ] Describe measures taken/proposed to address breach
- [ ] Estimate categories and number of data subjects affected
- [ ] Estimate categories and number of records affected
- [ ] Notify relevant supervisory authority
- [ ] If high risk to individuals, notify affected data subjects
- [ ] Document breach in data breach register

### PCI DSS Incident Response Checklist

- [ ] Contain the incident (isolate affected systems)
- [ ] Preserve evidence (logs, system images, network traffic)
- [ ] Notify payment brands immediately if card data suspected compromised
- [ ] Notify acquiring bank within 24 hours
- [ ] Engage PCI Forensic Investigator (PFI) if compromise confirmed
- [ ] Complete PCI DSS Incident Report
- [ ] Implement remediation actions
- [ ] Revalidate PCI DSS compliance after remediation

### HIPAA Breach Notification Checklist

Within 60 days of breach discovery:

- [ ] Conduct risk assessment (is notification required?)
- [ ] Notify affected individuals by mail (or email if consented)
- [ ] Notify HHS (immediate if >500 individuals, annually if <500)
- [ ] If >500 individuals affected, notify prominent media outlets
- [ ] Provide toll-free number for individuals to call
- [ ] Document breach in breach log
- [ ] Update breach notification procedures if needed

---

## Document Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | Security Team | Initial playbook creation |

---

**END OF PLAYBOOK**

*This playbook should be reviewed and updated quarterly or after any major incident. All team members with incident response responsibilities should be familiar with these procedures.*
