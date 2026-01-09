# Alertmanager SMTP Quick Start Guide

**Target**: mentat.arewel.com
**Time Required**: 10-15 minutes
**Status**: Ready to deploy

---

## Option 1: Automated Configuration (RECOMMENDED)

### Step 1: Configure SMTP in CHOM Admin

1. Login to CHOM admin:
   ```
   URL: https://landsraad.arewel.com/admin/settings
   ```

2. Navigate to Email/SMTP Settings section

3. Enter your SMTP details:
   - **Host**: e.g., `smtp.sendgrid.net` or `smtp.gmail.com`
   - **Port**: `587` (TLS) or `465` (SSL)
   - **Username**: Your SMTP username
   - **Password**: Your SMTP password
   - **Encryption**: `tls` or `ssl`
   - **From Address**: e.g., `alerts@arewel.com`
   - **Alert Email**: e.g., `ops@arewel.com`

4. Click Save

### Step 2: Sync to Alertmanager

SSH to landsraad and run:

```bash
ssh stilgar@landsraad.arewel.com
cd /var/www/chom/current
php artisan alertmanager:sync --host=mentat.arewel.com
```

### Step 3: Test Email Alerts

SSH to mentat and send test alert:

```bash
ssh stilgar@mentat.arewel.com

# Send test critical alert
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestCriticalAlert",
      "severity": "critical",
      "instance": "test"
    },
    "annotations": {
      "summary": "Test alert",
      "description": "Testing SMTP email delivery"
    }
  }]'
```

### Step 4: Verify

- Check your email inbox (should receive within 1-2 minutes)
- Subject should be: `[CRITICAL] TestCriticalAlert on test`
- Email should be HTML formatted with red header

**Done!** Email alerts are now configured.

---

## Option 2: Manual Configuration

If Option 1 doesn't work, configure manually:

### Step 1: Edit Config

```bash
ssh stilgar@mentat.arewel.com

# Backup current config
sudo cp /etc/observability/alertmanager/alertmanager.yml \
        /etc/observability/alertmanager/alertmanager.yml.backup

# Edit config
sudo nano /etc/observability/alertmanager/alertmanager.yml
```

### Step 2: Update SMTP Section

Replace the `global:` section with your SMTP settings:

```yaml
global:
  resolve_timeout: 5m
  smtp_from: 'alerts@arewel.com'              # Your from address
  smtp_smarthost: 'smtp.sendgrid.net:587'     # Your SMTP server:port
  smtp_auth_username: 'apikey'                # Your SMTP username
  smtp_auth_password: 'your-password-here'    # Your SMTP password
  smtp_require_tls: true                      # true for TLS/SSL, false for plain
```

Find all instances of `__ALERT_EMAIL__` and replace with your recipient email:

```yaml
receivers:
  - name: 'critical-alerts'
    email_configs:
      - to: 'ops@arewel.com'  # Replace __ALERT_EMAIL__ with this
```

Save and exit (Ctrl+X, Y, Enter)

### Step 3: Validate and Reload

```bash
# Validate config
sudo /opt/observability/bin/amtool check-config \
     /etc/observability/alertmanager/alertmanager.yml

# If validation passes, reload
sudo systemctl reload alertmanager

# Verify service is running
sudo systemctl status alertmanager
```

### Step 4: Test (same as Option 1 Step 3)

---

## Common SMTP Providers

### Gmail (Testing Only)
```yaml
smtp_from: 'your-email@gmail.com'
smtp_smarthost: 'smtp.gmail.com:587'
smtp_auth_username: 'your-email@gmail.com'
smtp_auth_password: 'your-app-specific-password'  # NOT your regular password!
smtp_require_tls: true
```

**Note**: Must enable "App Passwords" in Google Account settings.

### SendGrid
```yaml
smtp_from: 'alerts@yourdomain.com'
smtp_smarthost: 'smtp.sendgrid.net:587'
smtp_auth_username: 'apikey'
smtp_auth_password: 'SG.your-api-key-here'
smtp_require_tls: true
```

### AWS SES
```yaml
smtp_from: 'alerts@yourdomain.com'
smtp_smarthost: 'email-smtp.us-east-1.amazonaws.com:587'
smtp_auth_username: 'your-smtp-username'
smtp_auth_password: 'your-smtp-password'
smtp_require_tls: true
```

### Mailgun
```yaml
smtp_from: 'alerts@yourdomain.com'
smtp_smarthost: 'smtp.mailgun.org:587'
smtp_auth_username: 'postmaster@yourdomain.com'
smtp_auth_password: 'your-mailgun-password'
smtp_require_tls: true
```

---

## Troubleshooting

### No email received?

```bash
# Check logs for errors
sudo journalctl -u alertmanager -n 50 | grep -i error

# Verify SMTP config populated (no placeholders)
sudo grep smtp /etc/observability/alertmanager/alertmanager.yml

# Check for placeholders that need replacing
sudo grep -E '__SMTP_|__ALERT_EMAIL__' /etc/observability/alertmanager/alertmanager.yml
```

### Authentication failed?

- Verify username/password are correct
- For Gmail: Use app-specific password
- Check SMTP provider allows your server IP

### Service won't start?

```bash
# Check for config errors
sudo /opt/observability/bin/amtool check-config \
     /etc/observability/alertmanager/alertmanager.yml

# View error logs
sudo journalctl -u alertmanager -n 100 --no-pager
```

---

## Verification Commands

```bash
# Check Alertmanager is running
sudo systemctl status alertmanager

# View recent logs
sudo journalctl -u alertmanager -n 20

# List active alerts
curl http://localhost:9093/api/v2/alerts | jq

# View SMTP configuration
sudo grep smtp /etc/observability/alertmanager/alertmanager.yml
```

---

## Success Criteria

✅ Alertmanager service running: `systemctl is-active alertmanager` returns "active"
✅ Config validated: `amtool check-config` exits without errors
✅ No placeholders: `grep __SMTP_ config.yml` returns nothing
✅ Test email received within 1-2 minutes
✅ Email is HTML formatted with proper subject
✅ No errors in logs: `journalctl -u alertmanager | grep error` shows nothing recent

---

## Need Help?

**Full Documentation**: `/home/calounx/repositories/mentat/ALERTMANAGER_SMTP_CONFIGURATION.md`

**Key Commands Reference**:
```bash
# Sync from database
php artisan alertmanager:sync

# Validate config
amtool check-config /etc/observability/alertmanager/alertmanager.yml

# Reload service
sudo systemctl reload alertmanager

# View logs
sudo journalctl -u alertmanager -f
```

**URLs**:
- Alertmanager UI: https://mentat.arewel.com/alertmanager
- CHOM Admin: https://landsraad.arewel.com/admin/settings
- SMTP API: https://landsraad.arewel.com/api/v1/system/smtp-config

---

**Estimated Time**: 10-15 minutes
**Difficulty**: Easy
**Risk**: Low (auto-backup on changes)
