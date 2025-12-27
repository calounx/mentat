# Upgrade Mechanism Quick Reference

## Quick Start

```bash
# 1. Check for updates
observability-upgrade check

# 2. Apply upgrades (interactive)
observability-upgrade apply

# 3. Rollback if needed
observability-rollback --previous
```

## Common Commands

### Check and Plan
```bash
observability-upgrade check                 # What's available?
observability-upgrade plan                  # Detailed plan
```

### Apply Upgrades
```bash
observability-upgrade apply                 # Interactive
observability-upgrade apply --yes           # Auto-approve
observability-upgrade apply --component=prometheus --yes
observability-upgrade apply --dry-run       # Simulate
```

### Rollback
```bash
observability-rollback --list               # List backups
observability-rollback --to=20241227_030000 # Specific backup
observability-rollback --previous           # Last backup
observability-rollback --previous --component=prometheus
```

### Auto-Upgrade
```bash
observability-upgrade auto-enable           # Enable
observability-upgrade auto-disable          # Disable
observability-upgrade auto-status           # Status
```

## Safety Checklist

Before upgrading:
- [ ] All services healthy: `systemctl status prometheus loki grafana`
- [ ] Sufficient disk space: `df -h /var/lib/observability`
- [ ] Recent backup exists: `observability-rollback --list`
- [ ] Reviewed changelog for breaking changes
- [ ] Maintenance window (if production)

## Upgrade Process Flow

```
1. Pre-Flight Checks
   ├─ Disk space
   ├─ Service health
   ├─ Compatibility
   └─ Network access
         ↓
2. Create Backup
   ├─ Binaries → /var/backups/observability/{timestamp}/bin/
   ├─ Configs → /var/backups/observability/{timestamp}/config/
   └─ State → /var/backups/observability/{timestamp}/state/
         ↓
3. Download & Verify
   ├─ Download new binary
   ├─ Verify checksum
   └─ Test execution
         ↓
4. Apply Upgrade
   ├─ Stop service
   ├─ Replace binary
   └─ Start service
         ↓
5. Health Validation
   ├─ Service running?
   ├─ Endpoint responding?
   └─ Metrics present?
         ↓
6. Success? ─┬─ YES → Update version state → DONE
             │
             └─ NO → AUTOMATIC ROLLBACK → ALERT
```

## Troubleshooting

| Issue | Quick Fix |
|-------|-----------|
| Upgrade fails | `observability-rollback --previous` |
| Service won't start | `journalctl -u <service> -n 100` |
| Health check fails | `curl http://localhost:<port>/metrics` |
| Out of disk space | `observability-backup cleanup` |
| Download fails | Check network, retry |
| Timer not running | `systemctl start observability-upgrade.timer` |

## File Locations

```
Config:        /etc/observability/upgrade-policy.yaml
Compatibility: /etc/observability/compatibility-matrix.yaml
Version State: /var/lib/observability/versions.state
Backups:       /var/backups/observability/
Logs:          journalctl -u observability-upgrade.service
```

## Version Comparison

```bash
# Current versions
jq '.components | to_entries[] | "\(.key): \(.value.current_version)"' \
  /var/lib/observability/versions.state

# Upgrade history
sqlite3 /var/lib/observability/upgrade-history.db \
  "SELECT timestamp, component, old_version, new_version, status
   FROM upgrades ORDER BY timestamp DESC LIMIT 10"
```

## Emergency Rollback

If system is broken after upgrade:

```bash
# 1. Stop all services
systemctl stop prometheus loki grafana alertmanager promtail

# 2. Quick rollback
observability-rollback --previous --force

# 3. Verify services
systemctl status prometheus loki grafana

# 4. Check health
curl http://localhost:9090/-/healthy
curl http://localhost:3100/ready
curl http://localhost:3000/api/health
```

## Upgrade Policies

| Policy | What It Does |
|--------|--------------|
| `none` | Never auto-upgrade |
| `patch_only` | Only x.y.Z updates |
| `minor` | Only x.Y.z updates |
| `any` | All updates (including major) |

Set in `/etc/observability/upgrade-policy.yaml`:

```yaml
components:
  prometheus:
    auto_upgrade: minor      # Allow 2.48.x → 2.49.x
  grafana:
    auto_upgrade: none       # Never auto-upgrade
  node_exporter:
    auto_upgrade: any        # Allow any version
```

## Monitoring Upgrades

### Metrics
```prometheus
# Check if components are outdated
observability_versions_behind{component="prometheus"} > 0

# Last upgrade time
time() - observability_last_upgrade_timestamp{component="prometheus"} > 86400
```

### Alerts
```yaml
- alert: ComponentOutdated
  expr: observability_versions_behind > 2
  for: 7d

- alert: UpgradeFailed
  expr: observability_upgrade_status{status="failed"} == 1
```

## Maintenance Windows

Configure in `/etc/observability/upgrade-policy.yaml`:

```yaml
maintenance_windows:
  - day: saturday      # Day of week
    start: "02:00"     # Start time (UTC)
    end: "06:00"       # End time (UTC)
    timezone: UTC
```

Auto-upgrades only run during these windows.

## Component Dependencies

```
Prometheus ←──── Exporters (node, nginx, etc.)
    ↓
Alertmanager
    ↓
Grafana

Loki ←──── Promtail
 ↓
Grafana
```

Upgrade order (to maintain compatibility):
1. Exporters first
2. Prometheus/Loki
3. Alertmanager
4. Promtail
5. Grafana last

## Backup Retention

Default: Keep last 5 backups + 30 days minimum

Cleanup old backups:
```bash
# Manual cleanup (keeps last 3)
find /var/backups/observability -maxdepth 1 -type d -name "20*" | \
  sort -r | tail -n +4 | xargs rm -rf

# Automated cleanup via policy
# Edit /etc/observability/upgrade-policy.yaml:
backup_retention:
  keep_count: 5
  keep_days: 30
```

## Testing Upgrades

### Dry Run
```bash
# Simulate without applying
observability-upgrade apply --dry-run
```

### Staging First
```bash
# Test in staging
ssh staging "observability-upgrade apply --yes"

# Wait 24-48 hours

# Apply to production
ssh production "observability-upgrade apply --yes"
```

### Component-by-Component
```bash
# Upgrade one component at a time
observability-upgrade apply --component=prometheus --yes
# Wait and verify
observability-upgrade apply --component=loki --yes
# Continue...
```

## Getting Help

```bash
observability-upgrade --help
observability-rollback --help
```

View detailed design:
```bash
cat /home/calounx/repositories/mentat/observability-stack/docs/upgrade-mechanism-design.md
```

Implementation guide:
```bash
cat /home/calounx/repositories/mentat/observability-stack/docs/upgrade-implementation-guide.md
```

## Critical Notes

1. **Always test in staging first**
2. **Schedule upgrades during maintenance windows**
3. **Keep at least 2 backups before cleanup**
4. **Monitor services for 24h after upgrade**
5. **Have rollback plan ready**
6. **Document any manual config changes**
7. **Check compatibility matrix for major upgrades**
