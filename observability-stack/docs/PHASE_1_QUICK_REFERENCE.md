# Phase 1 Quick Reference Card

**Print this page and keep it handy during the upgrade**

---

## Quick Stats

| Metric | Value |
|--------|-------|
| Components | 5 exporters |
| Risk Level | LOW |
| Estimated Duration | 30-45 minutes |
| Downtime per Exporter | 5-10 seconds |
| Rollback Available | Yes (automatic) |

---

## One-Line Commands

```bash
# Pre-flight check
sudo ./scripts/upgrade-orchestrator.sh --status && sudo ./scripts/upgrade-orchestrator.sh --verify

# Dry-run
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --dry-run

# Execute upgrade (STANDARD MODE - recommended)
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode standard

# Execute upgrade (SAFE MODE - with confirmations)
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode safe

# Check status during upgrade
watch -n 5 'sudo ./scripts/upgrade-orchestrator.sh --status'

# Resume after failure
sudo ./scripts/upgrade-orchestrator.sh --resume

# Rollback everything
sudo ./scripts/upgrade-orchestrator.sh --rollback

# Rollback single component
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --rollback
```

---

## Expected Versions

| Component | From | To | Risk |
|-----------|------|-----|------|
| node_exporter | 1.7.0 | 1.9.1 | VERY LOW |
| nginx_exporter | 1.1.0 | 1.5.1 | LOW |
| mysqld_exporter | 0.15.1 | 0.18.0 | LOW |
| phpfpm_exporter | 2.2.0 | 2.3.0 | LOW |
| fail2ban_exporter | 0.4.1 | 0.5.0 | LOW |

---

## Health Check One-Liners

```bash
# Check all exporters are running
systemctl is-active node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter

# Check all metrics endpoints
for port in 9100 9113 9104 9253 9191; do curl -s http://localhost:$port/metrics | head -1; done

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("exporter")) | {job: .labels.job, health: .health}'

# Verify versions
for exp in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do echo -n "$exp: "; /usr/local/bin/$exp --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1; done
```

---

## Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| Primary | [YOUR NAME] | [PHONE/EMAIL] |
| Backup | [BACKUP NAME] | [PHONE/EMAIL] |
| Escalation | [MANAGER NAME] | [PHONE/EMAIL] |

---

## Critical Files

| File | Purpose |
|------|---------|
| `/var/lib/observability-upgrades/state.json` | Upgrade state tracking |
| `/var/lib/observability-upgrades/backups/` | Automatic backups |
| `/opt/observability-stack/config/upgrade.yaml` | Upgrade configuration |
| `/tmp/upgrade-orchestrator.log` | Execution log (if redirected) |

---

## Rollback Decision Matrix

| Scenario | Automatic Rollback? | Action |
|----------|---------------------|--------|
| Health check fails (< 30s) | YES | Wait and monitor |
| Service won't start | YES | Review logs, retry |
| Wrong version installed | NO | Manual rollback |
| Multiple failures | YES (per component) | Investigate root cause |
| Network partition | NO | Resume when restored |

---

## Success Criteria Checklist

After upgrade, verify:

- [ ] Orchestrator status shows "completed"
- [ ] All 5 services are "active": `systemctl is-active ...`
- [ ] All 5 metrics endpoints respond HTTP 200
- [ ] Prometheus targets all show "up"
- [ ] No gaps > 30 seconds in Grafana dashboards
- [ ] Versions match expected: `/usr/local/bin/<exporter> --version`
- [ ] No errors in: `journalctl -u <exporter> -n 50`

---

## Troubleshooting Fast Track

**Exporter service won't start:**
```bash
journalctl -u node_exporter -n 50 --no-pager
systemctl status node_exporter
lsof -i :9100  # Check port conflicts
```

**Metrics endpoint not responding:**
```bash
curl -v http://localhost:9100/metrics
ss -tlnp | grep 9100  # Check if listening
```

**Health check timeout:**
```bash
# Manual check
curl --max-time 5 http://localhost:9100/metrics

# If fails, rollback
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --rollback
```

**Prometheus not scraping:**
```bash
# Check firewall
ufw status | grep 9100

# Check target in Prometheus
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.instance | contains("9100"))'
```

**Version mismatch:**
```bash
# Verify installed version
/usr/local/bin/node_exporter --version

# If wrong, force reinstall
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --force
```

---

## Timeline Template

| Time | Checkpoint | Status | Notes |
|------|------------|--------|-------|
| T-15m | Pre-flight check | ⬜ |  |
| T-5m | Team notification | ⬜ |  |
| T+0m | Start dry-run | ⬜ |  |
| T+5m | Execute Phase 1 | ⬜ |  |
| T+30m | Validate completion | ⬜ |  |
| T+45m | Final sign-off | ⬜ |  |

---

## Port Reference

| Exporter | Port | Endpoint |
|----------|------|----------|
| node_exporter | 9100 | /metrics |
| nginx_exporter | 9113 | /metrics |
| mysqld_exporter | 9104 | /metrics |
| phpfpm_exporter | 9253 | /metrics |
| fail2ban_exporter | 9191 | /metrics |

---

## State File Quick Parse

```bash
# Current status
jq '.status' /var/lib/observability-upgrades/state.json

# Component statuses
jq '.components | to_entries[] | {name: .key, status: .value.status}' /var/lib/observability-upgrades/state.json

# Failed components
jq '.components | to_entries[] | select(.value.status == "failed") | .key' /var/lib/observability-upgrades/state.json

# Completed count
jq '.components | to_entries[] | select(.value.status == "completed") | .key' /var/lib/observability-upgrades/state.json | wc -l
```

---

## Quick Notifications

**Start upgrade:**
```bash
echo "Phase 1 upgrade started at $(date)" | mail -s "Upgrade Alert" team@example.com
```

**Completion:**
```bash
echo "Phase 1 upgrade completed at $(date). All exporters upgraded successfully." | mail -s "Upgrade Complete" team@example.com
```

**Failure:**
```bash
echo "Phase 1 upgrade encountered failures at $(date). Reviewing logs." | mail -s "Upgrade Alert - Action Required" team@example.com
```

---

## Manual Backup (Before Upgrade)

```bash
BACKUP="/tmp/phase1-manual-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for exp in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    [[ -x "/usr/local/bin/$exp" ]] && cp -p "/usr/local/bin/$exp" "$BACKUP/"
done
echo "Backup saved to: $BACKUP"
```

---

## Post-Upgrade Smoke Test

```bash
#!/bin/bash
# Quick smoke test after Phase 1

PASS=0
FAIL=0

echo "=== Phase 1 Smoke Test ==="

# 1. Services
for svc in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    if systemctl is-active --quiet $svc; then
        echo "✓ $svc"
        ((PASS++))
    else
        echo "✗ $svc"
        ((FAIL++))
    fi
done

# 2. Endpoints
for port in 9100 9113 9104 9253 9191; do
    if curl -sf http://localhost:$port/metrics > /dev/null; then
        echo "✓ Port $port"
        ((PASS++))
    else
        echo "✗ Port $port"
        ((FAIL++))
    fi
done

echo ""
echo "Passed: $PASS | Failed: $FAIL"
[[ $FAIL -eq 0 ]] && echo "✓ SMOKE TEST PASSED" || echo "✗ SMOKE TEST FAILED"
```

---

**END OF QUICK REFERENCE**
