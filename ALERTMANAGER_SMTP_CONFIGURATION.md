# Alertmanager SMTP Configuration Guide

**Date**: 2026-01-09
**Status**: Ready for deployment
**Target**: mentat.arewel.com (observability server)

---

## Executive Summary

This document provides complete SMTP configuration for Alertmanager to enable email alerts for critical incidents in production. The configuration is based on the existing codebase analysis and production deployment architecture.

---

## Current Architecture

### Deployment Type
- **Method**: Native systemd services (NO Docker)
- **Server**: mentat.arewel.com
- **Service User**: observability
- **Config Location**: `/etc/observability/alertmanager/alertmanager.yml`
- **Binary Location**: `/opt/observability/bin/alertmanager`

### Existing Integration
The system already has:
1. ✅ API endpoint to fetch SMTP config: `/api/v1/system/smtp-config`
2. ✅ Deployment script that auto-configures SMTP from database
3. ✅ Artisan command to sync config: `php artisan alertmanager:sync`
4. ✅ Email template for HTML notifications

---

## Configuration Files

### Location of Alertmanager Configuration

**Primary Config File**:
```
/etc/observability/alertmanager/alertmanager.yml
```

**Template Config File** (in repository):
```
/home/calounx/repositories/mentat/deploy/config/mentat/alertmanager.yml
```

**Email Templates**:
```
/etc/alertmanager/templates/email.tmpl
```

---

## SMTP Configuration Block

### Complete Alertmanager YAML Configuration

The configuration uses placeholder values that are populated from the CHOM database via the deployment script or sync command.

**File**: `/etc/observability/alertmanager/alertmanager.yml`

```yaml
# AlertManager configuration for CHOM
# SMTP settings will be injected by deployment script from database
global:
  resolve_timeout: 5m
  # SMTP configuration - populated from system_settings table
  smtp_from: '__SMTP_FROM__'
  smtp_smarthost: '__SMTP_SMARTHOST__'
  smtp_auth_username: '__SMTP_USERNAME__'
  smtp_auth_password: '__SMTP_PASSWORD__'
  smtp_require_tls: __SMTP_REQUIRE_TLS__

# Route configuration
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'

  routes:
    # Critical alerts
    - match:
        severity: critical
      receiver: 'critical-alerts'
      continue: true
      repeat_interval: 4h

    # Warning alerts
    - match:
        severity: warning
      receiver: 'warning-alerts'
      repeat_interval: 12h

# Inhibit rules
inhibit_rules:
  # Inhibit warning if critical is firing
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']

  # Inhibit any alert if instance is down
  - source_match:
      alertname: 'InstanceDown'
    target_match_re:
      severity: '.*'
    equal: ['instance']

# Receivers
receivers:
  # Default receiver - logs to stdout (visible in journalctl)
  - name: 'default'

  # Critical alerts receiver - sends email notifications
  - name: 'critical-alerts'
    email_configs:
      - to: '__ALERT_EMAIL__'
        headers:
          Subject: '[CRITICAL] {{ .GroupLabels.alertname }} on {{ .GroupLabels.instance }}'
        html: |
          <h2 style="color: #dc2626;">🚨 Critical Alert</h2>
          <p><strong>Alert:</strong> {{ .GroupLabels.alertname }}</p>
          <p><strong>Instance:</strong> {{ .GroupLabels.instance }}</p>
          <p><strong>Severity:</strong> {{ .GroupLabels.severity }}</p>
          {{ range .Alerts }}
          <hr>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Summary:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Started:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05" }}</p>
          {{ end }}
        send_resolved: true

  # Warning alerts receiver - sends email notifications
  - name: 'warning-alerts'
    email_configs:
      - to: '__ALERT_EMAIL__'
        headers:
          Subject: '[WARNING] {{ .GroupLabels.alertname }} on {{ .GroupLabels.instance }}'
        html: |
          <h2 style="color: #f59e0b;">⚠️ Warning Alert</h2>
          <p><strong>Alert:</strong> {{ .GroupLabels.alertname }}</p>
          <p><strong>Instance:</strong> {{ .GroupLabels.instance }}</p>
          <p><strong>Severity:</strong> {{ .GroupLabels.severity }}</p>
          {{ range .Alerts }}
          <hr>
          <p><strong>Description:</strong> {{ .Annotations.description }}</p>
          <p><strong>Summary:</strong> {{ .Annotations.summary }}</p>
          <p><strong>Started:</strong> {{ .StartsAt.Format "2006-01-02 15:04:05" }}</p>
          {{ end }}
        send_resolved: true
```

---

## SMTP Configuration Requirements

### Prerequisites

Before configuring Alertmanager SMTP, ensure you have:

1. **SMTP Server Details**:
   - SMTP host (e.g., smtp.gmail.com, smtp.sendgrid.net, mail.arewel.com)
   - SMTP port (typically 587 for TLS, 465 for SSL, 25 for plain)
   - Authentication username (if required)
   - Authentication password (if required)
   - Encryption method (tls, ssl, or null)

2. **Email Addresses**:
   - From address (sender): e.g., `alertmanager@arewel.com`
   - To address (recipients): e.g., `ops@arewel.com` or `admin@arewel.com`

3. **Access Requirements**:
   - SSH access to mentat.arewel.com as `stilgar` user
   - Sudo privileges to manage alertmanager service
   - Access to CHOM admin UI to configure SMTP in database

### Common SMTP Providers

**Gmail** (for testing/development):
```
Host: smtp.gmail.com
Port: 587
Encryption: tls
Username: your-email@gmail.com
Password: app-specific password (not your regular password)
```

**SendGrid**:
```
Host: smtp.sendgrid.net
Port: 587
Encryption: tls
Username: apikey
Password: <your-sendgrid-api-key>
```

**AWS SES**:
```
Host: email-smtp.<region>.amazonaws.com
Port: 587
Encryption: tls
Username: <your-smtp-username>
Password: <your-smtp-password>
```

**Mailgun**:
```
Host: smtp.mailgun.org
Port: 587
Encryption: tls
Username: postmaster@<your-domain>
Password: <your-mailgun-password>
```

---

## Configuration Methods

There are **THREE methods** to configure Alertmanager SMTP:

### Method 1: Via CHOM Admin UI (RECOMMENDED)

This is the recommended approach as it uses the existing infrastructure.

**Steps**:

1. **Configure SMTP in CHOM Database**:
   - Log into CHOM admin panel at https://landsraad.arewel.com
   - Navigate to System Settings > Email Configuration
   - Enter SMTP details:
     - Host
     - Port
     - Username
     - Password
     - Encryption (tls/ssl/null)
     - From Address
     - From Name
   - Save settings

2. **Sync to Alertmanager**:

   SSH to landsraad.arewel.com and run:
   ```bash
   ssh stilgar@landsraad.arewel.com
   cd /var/www/chom/current
   php artisan alertmanager:sync --host=mentat.arewel.com
   ```

3. **Verify Configuration**:
   ```bash
   ssh stilgar@mentat.arewel.com
   sudo cat /etc/observability/alertmanager/alertmanager.yml | grep smtp
   sudo systemctl status alertmanager
   ```

**Advantages**:
- Uses existing database-driven configuration
- Centralized management
- Automatic sync capability
- Built-in validation

---

### Method 2: Manual Configuration on mentat

If Method 1 fails or you don't have access to CHOM admin UI:

**Steps**:

1. **SSH to mentat**:
   ```bash
   ssh stilgar@mentat.arewel.com
   ```

2. **Backup Current Configuration**:
   ```bash
   sudo cp /etc/observability/alertmanager/alertmanager.yml \
           /etc/observability/alertmanager/alertmanager.yml.backup
   ```

3. **Edit Configuration File**:
   ```bash
   sudo nano /etc/observability/alertmanager/alertmanager.yml
   ```

4. **Update SMTP Settings** (replace placeholders):
   ```yaml
   global:
     resolve_timeout: 5m
     smtp_from: 'alertmanager@arewel.com'
     smtp_smarthost: 'smtp.example.com:587'
     smtp_auth_username: 'your-username'
     smtp_auth_password: 'your-password'
     smtp_require_tls: true
   ```

5. **Update Email Recipients** (find and replace `__ALERT_EMAIL__`):
   ```yaml
   receivers:
     - name: 'critical-alerts'
       email_configs:
         - to: 'ops@arewel.com'
   ```

6. **Validate Configuration**:
   ```bash
   sudo /opt/observability/bin/amtool check-config \
        /etc/observability/alertmanager/alertmanager.yml
   ```

7. **Reload Alertmanager**:
   ```bash
   sudo systemctl reload alertmanager
   # OR restart if reload doesn't work
   sudo systemctl restart alertmanager
   ```

8. **Verify Service is Running**:
   ```bash
   sudo systemctl status alertmanager
   sudo journalctl -u alertmanager -n 20
   ```

---

### Method 3: Via Deployment Script

If you're doing a fresh deployment or re-deployment:

**Steps**:

1. **Ensure SMTP Config in Database** (see Method 1, step 1)

2. **Run Deployment Script**:
   ```bash
   ssh stilgar@mentat.arewel.com
   cd /home/calounx/repositories/mentat
   sudo ./deploy/scripts/deploy-observability.sh
   ```

   The script will:
   - Fetch SMTP config from CHOM API
   - Inject values into alertmanager.yml
   - Deploy configuration
   - Restart services

**Note**: This re-deploys the entire observability stack.

---

## Testing Email Alerts

After configuration, test that email alerts are working.

### Test 1: Send Manual Test Alert

**On mentat.arewel.com**:

```bash
# Send a test critical alert
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestCriticalAlert",
      "severity": "critical",
      "instance": "test-instance"
    },
    "annotations": {
      "summary": "This is a test critical alert",
      "description": "Testing Alertmanager SMTP email delivery for critical alerts"
    }
  }]'
```

**Expected Result**:
- Email received at configured address within 1-2 minutes
- Subject: `[CRITICAL] TestCriticalAlert on test-instance`
- HTML formatted email with red header

### Test 2: Send Warning Alert

```bash
# Send a test warning alert
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestWarningAlert",
      "severity": "warning",
      "instance": "test-instance"
    },
    "annotations": {
      "summary": "This is a test warning alert",
      "description": "Testing Alertmanager SMTP email delivery for warning alerts"
    }
  }]'
```

**Expected Result**:
- Email received at configured address
- Subject: `[WARNING] TestWarningAlert on test-instance`
- HTML formatted email with orange header

### Test 3: Verify in Alertmanager UI

1. **Open Alertmanager UI**:
   - URL: https://mentat.arewel.com/alertmanager
   - Should show test alerts in "Alerts" tab

2. **Check Alert Status**:
   - Alerts should be visible
   - Should show as "active"

3. **Silence Test Alerts**:
   ```bash
   # Get alert fingerprint
   curl http://localhost:9093/api/v2/alerts | jq '.[].fingerprint'

   # Or silence all test alerts via UI
   ```

### Test 4: Check Alertmanager Logs

```bash
# View recent logs
sudo journalctl -u alertmanager -n 50

# Follow logs in real-time
sudo journalctl -u alertmanager -f

# Look for SMTP-related messages
sudo journalctl -u alertmanager | grep -i smtp
sudo journalctl -u alertmanager | grep -i email
```

**Look for**:
- `level=info msg="Notify successful"` - Email sent successfully
- `level=error msg="Notify failed"` - Email failed (check SMTP config)

---

## Troubleshooting

### Issue 1: Emails Not Received

**Symptoms**: Test alert sent but no email received

**Diagnosis**:
```bash
# Check Alertmanager logs for errors
sudo journalctl -u alertmanager -n 100 | grep -i error

# Verify SMTP config is populated (not placeholders)
sudo cat /etc/observability/alertmanager/alertmanager.yml | grep smtp

# Check if placeholders still exist
sudo grep -E '__SMTP_|__ALERT_EMAIL__' /etc/observability/alertmanager/alertmanager.yml
```

**Solutions**:
- If placeholders exist: Run `php artisan alertmanager:sync` or manually configure
- Check SMTP credentials are correct
- Verify SMTP host is reachable: `telnet smtp.example.com 587`
- Check spam folder for test emails
- Verify from/to email addresses are valid

### Issue 2: SMTP Authentication Failed

**Symptoms**: Logs show "authentication failed" or "535 error"

**Solutions**:
- Verify username/password are correct
- For Gmail: Use app-specific password, not account password
- Check if 2FA is enabled (may require app password)
- Verify SMTP provider allows connections from mentat server IP

### Issue 3: TLS/SSL Errors

**Symptoms**: "tls: first record does not look like a TLS handshake"

**Solutions**:
- Verify correct port (587 for TLS, 465 for SSL)
- Set `smtp_require_tls: false` if SMTP server doesn't support TLS
- Check if SMTP server certificate is valid

### Issue 4: Configuration Not Applied

**Symptoms**: Changes to config file not taking effect

**Solutions**:
```bash
# Validate config syntax
sudo /opt/observability/bin/amtool check-config \
     /etc/observability/alertmanager/alertmanager.yml

# Reload doesn't always work, try restart
sudo systemctl restart alertmanager

# Verify service restarted
sudo systemctl status alertmanager
```

### Issue 5: Alertmanager Service Won't Start

**Symptoms**: `systemctl status alertmanager` shows failed state

**Diagnosis**:
```bash
# Check service status
sudo systemctl status alertmanager -l

# View full logs
sudo journalctl -u alertmanager -n 100 --no-pager

# Check for config errors
sudo /opt/observability/bin/amtool check-config \
     /etc/observability/alertmanager/alertmanager.yml
```

**Solutions**:
- Fix YAML syntax errors (indentation, quotes)
- Ensure file permissions are correct: `sudo chown observability:observability /etc/observability/alertmanager/alertmanager.yml`
- Check for typos in placeholders

---

## Validation Checklist

After configuration, verify:

- [ ] SMTP settings populated (no `__PLACEHOLDER__` values)
- [ ] Alertmanager service running: `sudo systemctl is-active alertmanager`
- [ ] Configuration validated: `amtool check-config` passes
- [ ] Test critical alert email received
- [ ] Test warning alert email received
- [ ] Emails formatted correctly (HTML, proper subject)
- [ ] Resolution emails sent when alerts resolve
- [ ] Logs show successful notifications
- [ ] No errors in journalctl logs

---

## Production Recommendations

### SMTP Provider Selection

For production use, consider:

1. **Dedicated Email Service** (SendGrid, Mailgun, AWS SES):
   - High deliverability
   - Better monitoring
   - Dedicated IPs
   - Professional support

2. **Self-Hosted SMTP**:
   - Full control
   - No external dependencies
   - Requires SPF/DKIM/DMARC setup
   - More maintenance

3. **Do NOT use Gmail for production**:
   - Daily sending limits
   - Not designed for automated alerts
   - May flag as spam
   - Account lockout risk

### Email Configuration Best Practices

1. **Use Dedicated Alert Email**:
   ```
   From: alerts@arewel.com
   To: ops@arewel.com
   ```

2. **Set Up SPF/DKIM Records**:
   - Prevents emails being marked as spam
   - Improves deliverability

3. **Configure Multiple Recipients**:
   ```yaml
   - to: 'ops@arewel.com,admin@arewel.com,oncall@arewel.com'
   ```

4. **Use Distribution Lists**:
   - Create ops@arewel.com distribution list
   - Easier to manage team changes

5. **Set Up Email Filtering**:
   - Create folders for CRITICAL vs WARNING
   - Use email rules based on subject prefix

### Alert Routing Strategy

Consider setting up multiple receivers:

```yaml
receivers:
  # Critical alerts - page on-call
  - name: 'critical-alerts'
    email_configs:
      - to: 'oncall@arewel.com'
        send_resolved: true
    # Could also add PagerDuty, Slack here

  # Warning alerts - ops team
  - name: 'warning-alerts'
    email_configs:
      - to: 'ops@arewel.com'
        send_resolved: true

  # Infrastructure alerts - infra team
  - name: 'infrastructure-alerts'
    email_configs:
      - to: 'infra@arewel.com'
        send_resolved: true
```

---

## Quick Reference

### Key Commands

```bash
# Sync SMTP config from CHOM database
php artisan alertmanager:sync --host=mentat.arewel.com

# Export SMTP config from database
php artisan smtp:export --format=yaml

# Validate Alertmanager config
sudo /opt/observability/bin/amtool check-config /etc/observability/alertmanager/alertmanager.yml

# Reload Alertmanager
sudo systemctl reload alertmanager

# Restart Alertmanager
sudo systemctl restart alertmanager

# Check service status
sudo systemctl status alertmanager

# View logs
sudo journalctl -u alertmanager -f

# Send test alert
curl -X POST http://localhost:9093/api/v2/alerts -H "Content-Type: application/json" -d '[{"labels":{"alertname":"Test","severity":"critical"},"annotations":{"summary":"Test"}}]'

# List active alerts
curl http://localhost:9093/api/v2/alerts | jq

# Check SMTP routes
sudo /opt/observability/bin/amtool config routes --config.file=/etc/observability/alertmanager/alertmanager.yml
```

### Key Files

```
Config:     /etc/observability/alertmanager/alertmanager.yml
Templates:  /etc/alertmanager/templates/email.tmpl
Binary:     /opt/observability/bin/alertmanager
Service:    /etc/systemd/system/alertmanager.service
Data:       /var/lib/observability/alertmanager
```

### Key URLs

```
Alertmanager UI:  https://mentat.arewel.com/alertmanager
SMTP API:         https://landsraad.arewel.com/api/v1/system/smtp-config
Admin UI:         https://landsraad.arewel.com/admin/settings
Prometheus:       https://mentat.arewel.com/prometheus
Grafana:          https://mentat.arewel.com:3000
```

---

## Next Steps

After configuring SMTP:

1. **Monitor Email Delivery**:
   - Check alert emails over next 24-48 hours
   - Verify no delivery failures
   - Check spam folders

2. **Tune Alert Rules**:
   - Review firing alerts
   - Adjust thresholds if too noisy
   - See: `/etc/observability/prometheus/prometheus-alerts/`

3. **Set Up Additional Channels**:
   - Consider adding Slack integration
   - Set up PagerDuty for critical alerts
   - Add webhook receivers for custom integrations

4. **Document Runbooks**:
   - Create response procedures for each alert
   - See: `/home/calounx/repositories/mentat/chom/ALERTING.md`

5. **Test Incident Response**:
   - Simulate real alerts
   - Verify team receives and responds
   - Update on-call procedures

---

## Support & References

**Documentation**:
- Alertmanager Guide: `/home/calounx/repositories/mentat/chom/ALERTING.md`
- Observability Guide: `/home/calounx/repositories/mentat/chom/OBSERVABILITY.md`
- Deployment Guide: `/home/calounx/repositories/mentat/chom/deploy/observability-native/DEPLOYMENT-GUIDE.md`

**Official Docs**:
- Alertmanager: https://prometheus.io/docs/alerting/latest/alertmanager/
- Email Configuration: https://prometheus.io/docs/alerting/latest/configuration/#email_config

**Code References**:
- SyncAlertmanagerConfig: `/home/calounx/repositories/mentat/app/Console/Commands/SyncAlertmanagerConfig.php`
- SystemConfigController: `/home/calounx/repositories/mentat/app/Http/Controllers/Api/SystemConfigController.php`
- Deploy Script: `/home/calounx/repositories/mentat/deploy/scripts/deploy-observability.sh`

---

## Status: Ready for Deployment

This configuration is **ready to be applied** to production. The recommended approach is:

1. Configure SMTP in CHOM admin UI
2. Run `php artisan alertmanager:sync --host=mentat.arewel.com`
3. Send test alerts
4. Verify email delivery
5. Monitor for 24 hours

**Estimated Time**: 15-30 minutes
**Risk Level**: Low (existing config backed up automatically)
**Rollback**: Restore from `.backup` file if needed

---

**Document Version**: 1.0
**Last Updated**: 2026-01-09
**Author**: Agent 2 (Alertmanager SMTP Configuration)
