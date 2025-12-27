# Upgrade Mechanism Implementation Guide

## Overview

This guide explains how to install, configure, and use the observability stack upgrade mechanism.

## Installation

### 1. Install Upgrade Scripts

```bash
# Copy scripts to system locations
sudo cp scripts/observability-upgrade.sh /usr/local/bin/observability-upgrade
sudo cp scripts/observability-rollback.sh /usr/local/bin/observability-rollback
sudo chmod +x /usr/local/bin/observability-upgrade
sudo chmod +x /usr/local/bin/observability-rollback

# Install systemd units
sudo cp etc/systemd/observability-upgrade.service /etc/systemd/system/
sudo cp etc/systemd/observability-upgrade.timer /etc/systemd/system/
sudo systemctl daemon-reload

# Create required directories
sudo mkdir -p /var/lib/observability
sudo mkdir -p /var/backups/observability
sudo mkdir -p /etc/observability
sudo mkdir -p /usr/local/lib/observability

# Copy configuration files
sudo cp config/upgrade-policy.yaml /etc/observability/
sudo cp config/compatibility-matrix.yaml /etc/observability/
```

### 2. Install Dependencies

```bash
# Install required tools
sudo apt-get install -y jq curl wget

# For YAML parsing
sudo apt-get install -y python3-yaml

# Or install yq for better YAML support
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

### 3. Initialize Version State

```bash
# Detect currently installed versions
sudo observability-upgrade check

# This creates /var/lib/observability/versions.state
```

## Configuration

### Upgrade Policy (/etc/observability/upgrade-policy.yaml)

Configure automatic upgrade behavior:

```yaml
# Example: Enable automatic patch upgrades only
default_policy:
  auto_upgrade: patch_only
  require_approval: false

# Example: Enable automatic minor upgrades for Prometheus
components:
  prometheus:
    auto_upgrade: minor
    max_age_days: 30
    require_approval: false

# Example: Maintenance windows
maintenance_windows:
  - day: saturday
    start: "02:00"
    end: "06:00"
    timezone: UTC
```

### Compatibility Matrix (/etc/observability/compatibility-matrix.yaml)

Defines version compatibility rules. Generally you don't need to modify this unless:
- Adding custom components
- Overriding compatibility rules
- Blacklisting specific versions

## Usage

### Check for Updates

```bash
# Check what updates are available
sudo observability-upgrade check
```

Output example:
```
Updates Available:
==================
Component         Current    Latest     Type     Release Date
------------------------------------------------------------------------
prometheus        2.48.1     2.49.0     minor    2024-12-15
node_exporter     1.7.0      1.8.0      minor    2024-12-20
loki              2.9.3      2.9.4      patch    2024-12-18
```

### Apply Upgrades (Interactive)

```bash
# Show upgrade plan and prompt for confirmation
sudo observability-upgrade apply
```

This will:
1. Show which components will be upgraded
2. Display estimated duration
3. Show disk space required
4. Prompt for confirmation
5. Execute upgrades with health checks
6. Rollback automatically on failure

### Apply Upgrades (Automated)

```bash
# Auto-approve upgrades (for automation)
sudo observability-upgrade apply --yes

# Upgrade specific component only
sudo observability-upgrade apply --component=prometheus --yes

# Dry-run (simulate without applying)
sudo observability-upgrade apply --dry-run
```

### Rollback

List available backups:
```bash
sudo observability-rollback --list
```

Rollback to specific backup:
```bash
sudo observability-rollback --to=20241227_030000
```

Rollback specific component:
```bash
sudo observability-rollback --to=20241227_030000 --component=prometheus
```

Quick rollback to previous version:
```bash
sudo observability-rollback --previous
```

### Automatic Upgrades

Enable automatic upgrades (will run during maintenance windows):
```bash
sudo observability-upgrade auto-enable
```

Disable automatic upgrades:
```bash
sudo observability-upgrade auto-disable
```

Check auto-upgrade status:
```bash
sudo observability-upgrade auto-status
```

## Safety Features

### 1. Pre-Upgrade Checks

Before any upgrade, the system validates:
- Sufficient disk space
- All services are healthy
- Configuration syntax is valid
- Network connectivity to download sources
- Compatibility between versions
- No concurrent upgrades running

If any check fails, the upgrade is aborted.

### 2. Backup Creation

Before each upgrade, the system creates a backup containing:
- Current binary
- Configuration files
- Systemd units
- Version state

Backups are stored in `/var/backups/observability/{timestamp}/`

### 3. Health Validation

After upgrading each component, the system:
- Verifies service started successfully
- Checks HTTP endpoints are responding
- Validates expected metrics are present
- Scans logs for errors
- Runs component-specific functional tests

### 4. Automatic Rollback

If health validation fails, the system automatically:
- Stops the failed service
- Restores binary from backup
- Restores configuration from backup
- Restarts the service
- Verifies rollback success

### 5. Compatibility Checking

The system prevents incompatible upgrades by:
- Checking compatibility matrix
- Validating version dependencies
- Preventing blacklisted versions
- Enforcing upgrade paths for breaking changes

## Monitoring

### Upgrade Metrics

The upgrade system exposes Prometheus metrics at `http://localhost:9099/metrics`:

```prometheus
# Current component version
observability_component_version{component="prometheus"} 2.48.1

# Last upgrade timestamp
observability_last_upgrade_timestamp{component="prometheus"} 1703674800

# Upgrade status (1=success, 0=failed)
observability_upgrade_status{component="prometheus",status="success"} 1

# Versions behind latest
observability_versions_behind{component="prometheus"} 1
```

### Alerting

Add these rules to Prometheus:

```yaml
groups:
  - name: upgrade_alerts
    interval: 1h
    rules:
      - alert: ComponentVersionOutdated
        expr: observability_versions_behind > 2
        for: 7d
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.component }} is 2+ versions behind"

      - alert: UpgradeFailed
        expr: observability_upgrade_status{status="failed"} == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Upgrade failed for {{ $labels.component }}"
```

### Logs

View upgrade logs:
```bash
# View upgrade service logs
sudo journalctl -u observability-upgrade.service -f

# View recent upgrade activity
sudo journalctl -u observability-upgrade.service --since "1 week ago"

# View rollback logs
sudo grep -r "rollback" /var/log/syslog
```

## Troubleshooting

### Issue: Upgrade Fails with "Insufficient disk space"

**Solution:**
```bash
# Check disk space
df -h /var/lib/observability

# Clean up old backups
sudo observability-backup cleanup --keep=3

# Or manually remove old backups
sudo rm -rf /var/backups/observability/20241201_*
```

### Issue: Health Check Fails After Upgrade

**Solution:**
```bash
# Check service status
sudo systemctl status prometheus

# Check logs
sudo journalctl -u prometheus -n 100

# Manual rollback if needed
sudo observability-rollback --previous
```

### Issue: Download Fails

**Solution:**
```bash
# Check network connectivity
curl -I https://api.github.com

# Check proxy settings in /etc/observability/upgrade-policy.yaml
# Configure proxy if needed:
download:
  proxy: "http://proxy.example.com:8080"

# Retry with verbose logging
sudo observability-upgrade apply --verbose
```

### Issue: Compatibility Check Fails

**Solution:**
```bash
# Review compatibility matrix
cat /etc/observability/compatibility-matrix.yaml

# Override compatibility check (dangerous!)
sudo observability-upgrade apply --skip-compatibility-check

# Or upgrade dependencies first
sudo observability-upgrade apply --component=alertmanager
sudo observability-upgrade apply --component=prometheus
```

### Issue: Automatic Upgrades Not Running

**Solution:**
```bash
# Check timer status
sudo systemctl status observability-upgrade.timer

# Check timer schedule
sudo systemctl list-timers observability-upgrade.timer

# View timer logs
sudo journalctl -u observability-upgrade.timer

# Manually trigger upgrade
sudo systemctl start observability-upgrade.service
```

## Best Practices

### 1. Regular Update Checks

Run weekly checks to stay informed:
```bash
# Add to crontab
0 9 * * 1 /usr/local/bin/observability-upgrade check | mail -s "Observability Updates Available" ops@example.com
```

### 2. Test Upgrades in Staging

Before applying to production:
```bash
# In staging environment
sudo observability-upgrade apply --yes

# Wait 24-48 hours, monitor for issues

# Then apply to production
```

### 3. Backup Retention

Keep backups for at least 30 days:
```yaml
# In /etc/observability/upgrade-policy.yaml
backup_retention:
  keep_count: 10
  keep_days: 30
```

### 4. Maintenance Windows

Schedule upgrades during low-traffic periods:
```yaml
maintenance_windows:
  - day: sunday
    start: "02:00"
    end: "06:00"
    timezone: UTC
```

### 5. Monitor After Upgrades

Watch metrics for 24 hours after upgrade:
- CPU/Memory usage
- Query latency
- Error rates
- Scrape failures

### 6. Document Custom Changes

If you modify configuration after upgrade:
```bash
# Document in upgrade notes
echo "Modified prometheus.yml to add new scrape target" >> /var/lib/observability/upgrade-notes.txt
```

## Advanced Usage

### Custom Upgrade Hooks

Create pre/post upgrade scripts:

```bash
# /etc/observability/hooks/pre-upgrade-prometheus.sh
#!/bin/bash
echo "Pre-upgrade hook for Prometheus"
# Send notification
# Drain traffic
# etc.

# /etc/observability/hooks/post-upgrade-prometheus.sh
#!/bin/bash
echo "Post-upgrade hook for Prometheus"
# Verify queries work
# Send success notification
# etc.
```

Make them executable:
```bash
sudo chmod +x /etc/observability/hooks/*.sh
```

### Zero-Downtime Upgrades (HA Setup)

For HA deployments with multiple instances:

```bash
# Upgrade one instance at a time
for instance in prom-1 prom-2 prom-3; do
  ssh $instance "observability-upgrade apply --yes"
  sleep 300  # Wait 5 minutes between instances
done
```

### Integration with CI/CD

```yaml
# .gitlab-ci.yml example
upgrade-observability:
  stage: deploy
  script:
    - ssh observability-server "observability-upgrade apply --yes"
  only:
    - schedules
  when: manual
```

## Files and Directories

```
/usr/local/bin/
├── observability-upgrade          # Main upgrade command
└── observability-rollback          # Rollback command

/etc/observability/
├── upgrade-policy.yaml             # Upgrade configuration
├── compatibility-matrix.yaml       # Version compatibility rules
├── notifications.yaml              # Notification settings (optional)
└── hooks/                          # Custom upgrade hooks
    ├── pre-upgrade-*.sh
    └── post-upgrade-*.sh

/var/lib/observability/
├── versions.state                  # Current version tracking (JSON)
└── upgrade-history.db              # Upgrade history database (SQLite)

/var/backups/observability/
├── 20241227_030000/               # Backup directories (timestamp)
│   ├── bin/                       # Binary backups
│   ├── config/                    # Config backups
│   ├── systemd/                   # Systemd unit backups
│   └── upgrade-plan.json          # What was upgraded
└── ...

/etc/systemd/system/
├── observability-upgrade.service   # Upgrade service unit
└── observability-upgrade.timer     # Upgrade timer unit
```

## Security Considerations

1. **Root Access Required**: Upgrade scripts need root to modify system binaries and services
2. **Secrets in Config**: Ensure upgrade-policy.yaml has restrictive permissions if containing secrets
3. **Download Verification**: Always verify checksums and GPG signatures when available
4. **Audit Logging**: All upgrades are logged to syslog and upgrade-history.db
5. **Network Access**: Upgrade scripts need internet access to download binaries

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/your-org/observability-stack/issues
- Documentation: https://github.com/your-org/observability-stack/docs
- Slack: #observability-support
