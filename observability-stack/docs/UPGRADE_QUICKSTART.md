# Upgrade System Quick Start

Fast reference for upgrading the observability stack.

## Prerequisites

```bash
# Must be run as root
sudo su

# Verify jq is installed
which jq || apt-get install -y jq
```

## Common Commands

### Check What Would Be Upgraded

```bash
cd /path/to/observability-stack
sudo ./scripts/upgrade-orchestrator.sh --all --dry-run
```

### Show Current Status

```bash
sudo ./scripts/upgrade-orchestrator.sh --status
```

### Upgrade Everything (Safe Mode)

```bash
# Interactive with confirmations
sudo ./scripts/upgrade-orchestrator.sh --all --mode safe
```

### Upgrade Everything (Automated)

```bash
# No confirmations - for CI/CD
sudo ./scripts/upgrade-orchestrator.sh --all --mode standard --yes
```

### Upgrade Specific Phase

```bash
# Phase 1: Low-risk exporters
sudo ./scripts/upgrade-orchestrator.sh --phase 1

# Phase 2: Prometheus (high-risk)
sudo ./scripts/upgrade-orchestrator.sh --phase 2

# Phase 3: Loki/Promtail
sudo ./scripts/upgrade-orchestrator.sh --phase 3
```

### Upgrade Single Component

```bash
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
```

### Resume After Failure

```bash
sudo ./scripts/upgrade-orchestrator.sh --resume
```

### Rollback Last Upgrade

```bash
sudo ./scripts/upgrade-orchestrator.sh --rollback
```

## Upgrade Workflow

### Standard Upgrade Procedure

1. **Dry-run to preview**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --all --dry-run
   ```

2. **Start with low-risk phase**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --phase 1
   ```

3. **Verify exporters working**:
   ```bash
   # Check metrics endpoints
   curl http://localhost:9100/metrics  # node_exporter
   curl http://localhost:9113/metrics  # nginx_exporter
   ```

4. **Upgrade Prometheus (careful!)**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --phase 2 --mode safe
   ```

5. **Upgrade logging stack**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --phase 3
   ```

6. **Verify everything**:
   ```bash
   sudo ./scripts/upgrade-orchestrator.sh --status
   ```

## Component Versions

Current → Target versions configured in system:

- **node_exporter**: 1.7.0 → 1.9.1
- **nginx_exporter**: 1.1.0 → 1.5.1
- **mysqld_exporter**: 0.15.1 → 0.18.0
- **phpfpm_exporter**: 2.2.0 → 2.3.0
- **fail2ban_exporter**: 0.4.1 → 0.5.0
- **prometheus**: 2.48.1 → 2.55.1 → 3.8.1 (two-stage)
- **loki**: 2.9.3 → 3.6.3
- **promtail**: 2.9.3 → 3.6.3

## Troubleshooting Quick Fixes

### Upgrade stuck "in_progress"

```bash
# Check what's running
ps aux | grep upgrade

# If nothing running, check state
sudo ./scripts/upgrade-orchestrator.sh --status

# Resume
sudo ./scripts/upgrade-orchestrator.sh --resume
```

### Remove stuck lock

```bash
sudo rm -rf /var/lib/observability-upgrades/.state.lock
```

### Check service health

```bash
# Check service status
sudo systemctl status node_exporter
sudo systemctl status prometheus
sudo systemctl status loki

# Check logs
sudo journalctl -u node_exporter -n 50
```

### Manual rollback

```bash
# Automatic rollback
sudo ./scripts/upgrade-orchestrator.sh --rollback

# Manual restore from backup
COMPONENT="node_exporter"
BACKUP_DIR="/var/lib/observability-upgrades/backups/$COMPONENT"
LATEST=$(ls -t $BACKUP_DIR | head -1)

sudo cp "$BACKUP_DIR/$LATEST/$COMPONENT" /usr/local/bin/
sudo systemctl restart $COMPONENT
```

## Safety Checklist

Before upgrading:

- [ ] Backups of critical data exist
- [ ] Monitoring is working (to detect issues)
- [ ] Low-traffic time window selected
- [ ] Dry-run completed successfully
- [ ] Team notified of maintenance

During upgrade:

- [ ] Watch dashboards for anomalies
- [ ] Check logs for errors
- [ ] Verify each phase before continuing

After upgrade:

- [ ] All services running: `systemctl status <service>`
- [ ] Metrics endpoints responding
- [ ] Grafana dashboards showing data
- [ ] Alerts firing correctly
- [ ] No error logs: `journalctl -p err -since "1 hour ago"`

## Emergency Procedures

### Stop Upgrade in Progress

```bash
# Find upgrade process
ps aux | grep upgrade-orchestrator

# Kill it
sudo kill <PID>

# State is preserved, you can resume later
```

### Complete Rollback

```bash
# Rollback all upgraded components
sudo ./scripts/upgrade-orchestrator.sh --rollback

# Verify
sudo ./scripts/upgrade-orchestrator.sh --status

# Check services
sudo systemctl status node_exporter nginx_exporter mysqld_exporter
```

### Reset Everything

```bash
# WARNING: This loses upgrade history and resume capability
sudo rm -rf /var/lib/observability-upgrades/
sudo ./scripts/upgrade-orchestrator.sh --all --dry-run
```

## Integration Examples

### Cron Job (Monthly)

```bash
# Edit crontab
sudo crontab -e

# Add monthly upgrade on 1st at 2 AM
0 2 1 * * /opt/observability-stack/scripts/upgrade-orchestrator.sh --all --mode standard --yes >> /var/log/observability-upgrade.log 2>&1
```

### Pre-Upgrade Notification

```bash
#!/bin/bash
# Send notification before upgrade
curl -X POST https://hooks.slack.com/... \
  -d '{"text": "Starting observability stack upgrade"}'

# Run upgrade
./scripts/upgrade-orchestrator.sh --all --yes

# Send completion
curl -X POST https://hooks.slack.com/... \
  -d '{"text": "Observability stack upgrade completed"}'
```

### Health Check Script

```bash
#!/bin/bash
# health-check.sh

COMPONENTS="node_exporter nginx_exporter mysqld_exporter prometheus loki promtail"

for component in $COMPONENTS; do
  if systemctl is-active --quiet $component; then
    echo "✓ $component is running"
  else
    echo "✗ $component is NOT running"
    exit 1
  fi
done

echo "All components healthy"
```

## Advanced Options

### Custom Target Versions

```bash
# Override version from environment
export VERSION_OVERRIDE_NODE_EXPORTER=1.10.0
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
```

### Skip Backups (Faster, Riskier)

```bash
sudo ./scripts/upgrade-orchestrator.sh --all --skip-backup --yes
```

### Force Re-Upgrade

```bash
# Force upgrade even if at target version
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --force
```

### Debug Mode

```bash
export DEBUG=true
sudo -E ./scripts/upgrade-orchestrator.sh --component node_exporter
```

## Getting Help

```bash
# Show help
./scripts/upgrade-orchestrator.sh --help

# Run tests
sudo ./tests/test-upgrade-idempotency.sh

# Check documentation
cat docs/UPGRADE_ORCHESTRATION.md
```

## File Locations

```
Config:       config/upgrade.yaml
State:        /var/lib/observability-upgrades/state.json
Backups:      /var/lib/observability-upgrades/backups/
History:      /var/lib/observability-upgrades/history/
Logs:         /var/log/observability-setup.log
```

## Exit Codes

- `0` = Success
- `1` = Failure
- `2` = Validation failed
- `3` = User canceled

## Quick Reference

| Task | Command |
|------|---------|
| Preview upgrades | `--all --dry-run` |
| Check status | `--status` |
| Upgrade all | `--all` |
| Upgrade phase 1 | `--phase 1` |
| Upgrade one component | `--component <name>` |
| Resume | `--resume` |
| Rollback | `--rollback` |
| Safe mode | `--mode safe` |
| Fast mode | `--mode fast` |
| Auto-confirm | `--yes` |
| Force upgrade | `--force` |
| Verify state | `--verify` |
