# Phase 1 Pre-Flight Checklist

**Date:** ___________________
**Engineer:** ___________________
**Start Time:** ___________________

---

## System Requirements

| Check | Command | Expected Result | Status | Notes |
|-------|---------|-----------------|--------|-------|
| Running as root | `id` | UID 0 | ⬜ |  |
| Disk space available | `df -h /var/lib` | > 1 GB free | ⬜ |  |
| jq installed | `which jq` | /usr/bin/jq | ⬜ |  |
| curl installed | `which curl` | /usr/bin/curl | ⬜ |  |
| python3 installed | `which python3` | /usr/bin/python3 | ⬜ |  |
| Config file exists | `ls config/upgrade.yaml` | File found | ⬜ |  |
| Config file valid | `python3 -c "import yaml; yaml.safe_load(open('config/upgrade.yaml'))"` | No errors | ⬜ |  |

---

## Current State Verification

| Check | Command | Expected | Actual | Status |
|-------|---------|----------|--------|--------|
| Upgrade status | `./scripts/upgrade-orchestrator.sh --status` | "idle" | _______ | ⬜ |
| State file valid | `./scripts/upgrade-orchestrator.sh --verify` | "PASS" | _______ | ⬜ |
| No pending upgrades | `cat /var/lib/observability-upgrades/state.json \| jq '.status'` | "idle" or "completed" | _______ | ⬜ |

---

## Component Status

| Exporter | Service Active | Current Version | Expected Target | Status |
|----------|----------------|-----------------|-----------------|--------|
| node_exporter | `systemctl is-active node_exporter` | _______ | 1.9.1 | ⬜ |
| nginx_exporter | `systemctl is-active nginx_exporter` | _______ | 1.5.1 | ⬜ |
| mysqld_exporter | `systemctl is-active mysqld_exporter` | _______ | 0.18.0 | ⬜ |
| phpfpm_exporter | `systemctl is-active phpfpm_exporter` | _______ | 2.3.0 | ⬜ |
| fail2ban_exporter | `systemctl is-active fail2ban_exporter` | _______ | 0.5.0 | ⬜ |

**Get current versions:**
```bash
for exp in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    echo -n "$exp: "
    /usr/local/bin/$exp --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
done
```

---

## Network Connectivity

| Check | Command | Expected | Status |
|-------|---------|----------|--------|
| GitHub API reachable | `curl -s https://api.github.com/zen` | Quote text | ⬜ |
| GitHub releases accessible | `curl -sI https://github.com/prometheus/node_exporter/releases \| head -1` | HTTP 200 | ⬜ |
| Prometheus accessible | `curl -s http://localhost:9090/-/healthy` | "Prometheus is Healthy" | ⬜ |
| Grafana accessible | `curl -sI http://localhost:3000 \| head -1` | HTTP 200 or 302 | ⬜ |

---

## Backup Verification

| Check | Command | Expected | Status |
|-------|---------|----------|--------|
| Backup directory exists | `ls -ld /var/lib/observability-upgrades/backups` | Directory exists | ⬜ |
| Backup directory writable | `touch /var/lib/observability-upgrades/backups/test && rm /var/lib/observability-upgrades/backups/test` | No errors | ⬜ |
| Sufficient space for backups | `df -h /var/lib/observability-upgrades` | > 500 MB free | ⬜ |

---

## Prometheus Target Health

| Check | Command | Expected | Status |
|-------|---------|----------|--------|
| All exporter targets UP | `curl -s http://localhost:9090/api/v1/targets \| jq '.data.activeTargets[] \| select(.labels.job \| contains("exporter")) \| .health' \| sort \| uniq -c` | All "up" | ⬜ |
| No stale targets | `curl -s http://localhost:9090/api/v1/targets \| jq '.data.activeTargets[] \| select(.labels.job \| contains("exporter") and .health != "up") \| .labels.instance'` | Empty | ⬜ |
| Recent scrape success | `curl -s http://localhost:9090/api/v1/query?query=up{job=~".*exporter"} \| jq '.data.result[] \| {instance: .metric.instance, up: .value[1]}'` | All "1" | ⬜ |

---

## Dry-Run Execution

| Check | Command | Expected | Status |
|-------|---------|----------|--------|
| Dry-run successful | `./scripts/upgrade-orchestrator.sh --phase 1 --dry-run` | No errors, shows 5 components | ⬜ |
| Target versions correct | Review dry-run output | Matches expected versions | ⬜ |
| All components detected | Count components in dry-run | 5 exporters | ⬜ |

**Dry-run output verification:**
- [ ] node_exporter → 1.9.1
- [ ] nginx_exporter → 1.5.1
- [ ] mysqld_exporter → 0.18.0
- [ ] phpfpm_exporter → 2.3.0
- [ ] fail2ban_exporter → 0.5.0

---

## Change Management

| Task | Status | Notes |
|------|--------|-------|
| Change ticket created | ⬜ | Ticket #: _______ |
| Stakeholders notified | ⬜ | Date: _______ |
| Maintenance window scheduled | ⬜ | Window: _______ |
| Rollback plan reviewed | ⬜ |  |
| Team on standby | ⬜ | Contact: _______ |

---

## Communication

| Task | Status | Date/Time | Notes |
|------|--------|-----------|-------|
| Ops team notified (15m before) | ⬜ | _______ |  |
| Dev team notified (day before) | ⬜ | _______ |  |
| Management notified (day before) | ⬜ | _______ |  |
| Grafana annotation created | ⬜ | _______ |  |
| Alert silence created (optional) | ⬜ | _______ | Duration: _____ |

---

## Manual Backup (Optional)

| Task | Status | Location | Notes |
|------|--------|----------|-------|
| Manual snapshot created | ⬜ | _________________ | Command: `BACKUP="/tmp/phase1-manual-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BACKUP"; for exp in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do [[ -x "/usr/local/bin/$exp" ]] && cp -p "/usr/local/bin/$exp" "$BACKUP/"; done` |
| Snapshot verified | ⬜ | _________________ | Command: `ls -la $BACKUP` |

---

## Environment Variables (Optional)

| Variable | Set? | Value | Purpose |
|----------|------|-------|---------|
| GITHUB_TOKEN | ⬜ | ghp_______... | Increase GitHub API rate limit |
| DRY_RUN | ⬜ | true/false | Testing only |

---

## Final Checks

| Check | Status | Notes |
|-------|--------|-------|
| All pre-flight checks passed | ⬜ |  |
| Dry-run completed successfully | ⬜ |  |
| Team ready and available | ⬜ |  |
| Rollback plan understood | ⬜ |  |
| Monitoring dashboard open | ⬜ |  |
| Documentation accessible | ⬜ |  |
| Emergency contacts confirmed | ⬜ |  |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation | Accepted? |
|------|------------|--------|------------|-----------|
| Exporter service failure | Low | Medium | Automatic rollback | ⬜ |
| Network partition | Very Low | High | Resume on recovery | ⬜ |
| Disk space exhaustion | Very Low | Medium | Pre-flight check | ⬜ |
| Multiple host failures | Very Low | High | Sequential upgrade | ⬜ |
| GitHub API rate limit | Low | Low | Version caching | ⬜ |

---

## Go/No-Go Decision

**All checks passed?** ⬜ YES ⬜ NO

**If NO, list blocking issues:**
1. _____________________________________
2. _____________________________________
3. _____________________________________

**Decision:**

- [ ] ✅ **GO** - Proceed with Phase 1 upgrade
- [ ] ⛔ **NO-GO** - Defer upgrade, resolve issues
- [ ] ⏸️ **HOLD** - Need more information/testing

**Approved by:** _____________________
**Signature:** _____________________
**Date/Time:** _____________________

---

## Execution Notes

**Start Time:** _____________________

**Actual Command Executed:**
```
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode _______
```

**Observations during execution:**
_____________________________________
_____________________________________
_____________________________________

**Completion Time:** _____________________

**Total Duration:** _____________________

**Outcome:**
- [ ] ✅ Success - all components upgraded
- [ ] ⚠️ Partial success - some components failed
- [ ] ❌ Failed - rolled back

**Components upgraded:**
- [ ] node_exporter
- [ ] nginx_exporter
- [ ] mysqld_exporter
- [ ] phpfpm_exporter
- [ ] fail2ban_exporter

**Issues encountered:**
_____________________________________
_____________________________________
_____________________________________

**Resolution actions taken:**
_____________________________________
_____________________________________
_____________________________________

---

## Post-Upgrade Validation

| Check | Status | Notes |
|-------|--------|-------|
| All services active | ⬜ |  |
| All metrics endpoints responding | ⬜ |  |
| Prometheus targets UP | ⬜ |  |
| No gaps in Grafana dashboards | ⬜ |  |
| Versions verified | ⬜ |  |
| No errors in logs | ⬜ |  |
| Smoke test passed | ⬜ |  |

---

## Sign-Off

**Upgrade completed successfully:** ⬜ YES ⬜ NO

**Engineer:** _____________________
**Signature:** _____________________
**Date/Time:** _____________________

**Reviewed by:** _____________________
**Signature:** _____________________
**Date/Time:** _____________________

---

## Lessons Learned

**What went well:**
_____________________________________
_____________________________________

**What could be improved:**
_____________________________________
_____________________________________

**Action items for next phase:**
_____________________________________
_____________________________________

---

**END OF CHECKLIST**
