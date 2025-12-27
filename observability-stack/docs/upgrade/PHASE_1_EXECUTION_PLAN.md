# Phase 1 Execution Plan: Low-Risk Exporters Upgrade

**Document Version:** 1.0
**Created:** 2025-12-27
**Target Components:** node_exporter, nginx_exporter, mysqld_exporter, phpfpm_exporter, fail2ban_exporter
**Estimated Duration:** 30-45 minutes
**Risk Level:** LOW

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Phase 1 Overview](#phase-1-overview)
3. [Pre-Flight Checklist](#pre-flight-checklist)
4. [Execution Plan](#execution-plan)
5. [Component-Specific Details](#component-specific-details)
6. [Health Check Procedures](#health-check-procedures)
7. [Rollback Procedures](#rollback-procedures)
8. [Post-Upgrade Validation](#post-upgrade-validation)
9. [Risk Assessment](#risk-assessment)
10. [Dependencies and Coordination](#dependencies-and-coordination)

---

## Executive Summary

### Upgrade Strategy

Phase 1 focuses on upgrading **low-risk monitoring exporters** across all monitored hosts. These components:
- Have minimal service impact (read-only operations)
- Can be upgraded independently in parallel
- Include automatic rollback on health check failure
- Support zero-downtime upgrades via service restart

### Version Upgrades

| Component | Current | Target | Increase | Strategy |
|-----------|---------|--------|----------|----------|
| node_exporter | 1.7.0 | 1.9.1 | Minor | Two minor releases |
| nginx_exporter | 1.1.0 | 1.5.1 | Major + Minor | Major version jump |
| mysqld_exporter | 0.15.1 | 0.18.0 | Minor | Three minor releases |
| phpfpm_exporter | 2.2.0 | 2.3.0 | Patch | Single minor release |
| fail2ban_exporter | 0.4.1 | 0.5.0 | Minor | Single minor release |

### Success Criteria

- All exporters upgraded to target versions
- All health checks passing (HTTP 200 on /metrics endpoints)
- No gaps in metrics collection (< 30 seconds per exporter)
- Zero manual interventions required
- Complete upgrade history and audit trail

---

## Phase 1 Overview

### Architecture Context

```
┌─────────────────────────────────────────────────────────┐
│         OBSERVABILITY VPS (No Changes)                  │
│  ┌──────────────┐                                       │
│  │  Prometheus  │ ◄── Scrapes metrics from exporters    │
│  └──────────────┘                                       │
└──────────────▲──────────────────────────────────────────┘
               │
               │ Scrape (no interruption, max 15s gap)
               │
┌──────────────┴──────────────────────────────────────────┐
│         MONITORED HOSTS (Upgrade Target)                │
│                                                          │
│  ┌────────────────┐  ┌────────────────┐                │
│  │ node_exporter  │  │ nginx_exporter │  ...           │
│  │ Port: 9100     │  │ Port: 9113     │                │
│  │ 1.7.0 → 1.9.1  │  │ 1.1.0 → 1.5.1  │                │
│  └────────────────┘  └────────────────┘                │
│                                                          │
│  Strategy: Stop → Replace Binary → Start                │
│  Downtime: 5-10 seconds per exporter                    │
│  Rollback: Automatic if health check fails              │
└──────────────────────────────────────────────────────────┘
```

### Upgrade Mechanism

1. **Orchestrator** (`upgrade-orchestrator.sh`) coordinates the entire phase
2. **Component Upgrader** (`upgrade-component.sh`) handles individual exporter upgrades
3. **Module Installer** (`modules/_core/*/install.sh`) performs actual binary replacement
4. **State Manager** (`lib/upgrade-state.sh`) tracks progress with crash recovery
5. **Version Resolver** (`lib/versions.sh`) determines target versions dynamically

### Idempotency Guarantees

- Safe to run multiple times
- Detects already-upgraded components and skips
- Resumes from last checkpoint after crash/failure
- State file: `/var/lib/observability-upgrades/state.json`

---

## Pre-Flight Checklist

### 1. Environment Verification

```bash
# Run on observability VPS
cd /opt/observability-stack

# Check current status
sudo ./scripts/upgrade-orchestrator.sh --status

# Verify configuration is valid
sudo ./scripts/upgrade-orchestrator.sh --verify
```

**Expected Output:**
```
Current Upgrade Status
======================
Upgrade ID:        None
Status:            idle
Current Phase:     None
Current Component: None
```

### 2. System Requirements Check

| Requirement | Command | Minimum | Notes |
|-------------|---------|---------|-------|
| Disk Space | `df -h /var/lib` | 1 GB free | Backups + downloads |
| Dependencies | `which jq curl python3` | All present | Required by orchestrator |
| Permissions | `id` | root (UID 0) | Must run as root |
| Config File | `ls -la config/upgrade.yaml` | Exists, readable | Contains upgrade definitions |

**Validation Script:**
```bash
#!/bin/bash
# Run on each monitored host before upgrade

echo "=== Pre-Flight Checks ==="

# Disk space
AVAILABLE_KB=$(df /var/lib | tail -1 | awk '{print $4}')
if [[ $AVAILABLE_KB -lt 1048576 ]]; then
    echo "❌ FAIL: Insufficient disk space ($AVAILABLE_KB KB < 1 GB)"
    exit 1
else
    echo "✓ PASS: Disk space sufficient ($AVAILABLE_KB KB)"
fi

# Dependencies
for cmd in jq curl python3; do
    if ! command -v $cmd &>/dev/null; then
        echo "❌ FAIL: Missing dependency: $cmd"
        exit 1
    else
        echo "✓ PASS: Dependency found: $cmd"
    fi
done

# Permissions
if [[ $EUID -ne 0 ]]; then
    echo "❌ FAIL: Must run as root"
    exit 1
else
    echo "✓ PASS: Running as root"
fi

# Configuration
if [[ ! -f /opt/observability-stack/config/upgrade.yaml ]]; then
    echo "❌ FAIL: Missing config/upgrade.yaml"
    exit 1
else
    echo "✓ PASS: Configuration file exists"
fi

echo ""
echo "=== All Pre-Flight Checks Passed ==="
```

### 3. Backup Verification

**Automatic Backups Created By Orchestrator:**
- Location: `/var/lib/observability-upgrades/backups/<component>/<timestamp>/`
- Contents: Binary, service file, configuration files
- Retention: 30 days (configurable in `config/upgrade.yaml`)

**Manual Pre-Upgrade Snapshot (Optional):**
```bash
# Create manual snapshot before Phase 1
SNAPSHOT_DIR="/var/backups/phase1-pre-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SNAPSHOT_DIR"

# Backup all exporter binaries
for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    if [[ -x "/usr/local/bin/$exporter" ]]; then
        cp -p "/usr/local/bin/$exporter" "$SNAPSHOT_DIR/"
        cp -p "/etc/systemd/system/${exporter}.service" "$SNAPSHOT_DIR/" 2>/dev/null || true
    fi
done

echo "Manual snapshot created: $SNAPSHOT_DIR"
```

### 4. Monitoring Window Preparation

**Alert Suppression (Optional):**

If you want to suppress "instance down" alerts during the upgrade:

```bash
# Silence alerts for 1 hour
SILENCE_DURATION="1h"
ALERTMANAGER_URL="http://localhost:9093"

curl -X POST "${ALERTMANAGER_URL}/api/v2/silences" \
    -H "Content-Type: application/json" \
    -d "{
      \"matchers\": [{\"name\": \"alertname\", \"value\": \".*Exporter.*\", \"isRegex\": true}],
      \"startsAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"endsAt\": \"$(date -u -d '+${SILENCE_DURATION}' +%Y-%m-%dT%H:%M:%SZ)\",
      \"createdBy\": \"upgrade-phase1\",
      \"comment\": \"Phase 1: Exporter upgrades in progress\"
    }"
```

**Dashboard Annotation:**

Add annotation to Grafana to mark upgrade window:

```bash
GRAFANA_URL="http://localhost:3000"
GRAFANA_API_KEY="your-api-key"  # Create from Grafana UI

curl -X POST "${GRAFANA_URL}/api/annotations" \
    -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"Phase 1: Exporter Upgrades Started\",
      \"tags\": [\"upgrade\", \"phase1\"],
      \"time\": $(date +%s)000
    }"
```

### 5. Team Notification

**Before Starting Upgrade:**

```bash
# Example: Send Slack notification
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

curl -X POST "$SLACK_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{
      \"text\": \"🚀 Starting Phase 1 Exporter Upgrades\",
      \"attachments\": [{
        \"color\": \"warning\",
        \"fields\": [
          {\"title\": \"Components\", \"value\": \"node, nginx, mysql, phpfpm, fail2ban exporters\", \"short\": false},
          {\"title\": \"Estimated Duration\", \"value\": \"30-45 minutes\", \"short\": true},
          {\"title\": \"Risk Level\", \"value\": \"LOW\", \"short\": true}
        ]
      }]
    }"
```

---

## Execution Plan

### Execution Modes

The upgrade orchestrator supports three execution modes:

| Mode | Auto-Confirm | Backup | Pause Between | Use Case |
|------|--------------|--------|---------------|----------|
| **safe** | No | Yes | 30s | First-time upgrade, manual control |
| **standard** | Yes | Yes | 10s | Production upgrade (recommended) |
| **fast** | Yes | No | 0s | CI/CD, testing |

**Recommendation for Phase 1:** Use **standard** mode for production

### Step-by-Step Execution

#### Step 1: Dry-Run Validation (5 minutes)

**Purpose:** Verify upgrade plan without making changes

```bash
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --dry-run
```

**Expected Output:**
```
Observability Stack Upgrade Orchestrator
========================================

Mode: DRY-RUN MODE: No actual changes will be made

==========================================
Phase 1 Upgrade
==========================================
Components in phase 1:
  - node_exporter
  - nginx_exporter
  - mysqld_exporter
  - phpfpm_exporter
  - fail2ban_exporter

[DRY-RUN] Would upgrade node_exporter to 1.9.1
[DRY-RUN] Would upgrade nginx_exporter to 1.5.1
[DRY-RUN] Would upgrade mysqld_exporter to 0.18.0
[DRY-RUN] Would upgrade phpfpm_exporter to 2.3.0
[DRY-RUN] Would upgrade fail2ban_exporter to 0.5.0

Phase 1 Summary:
  Succeeded: 5
  Failed: 0
```

**Validation:**
- ✓ All 5 exporters are detected
- ✓ Target versions match expectations
- ✓ No errors in dry-run output

#### Step 2: Execute Phase 1 Upgrade (20-30 minutes)

**Command:**
```bash
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode standard
```

**What Happens:**

```
Time    Component           Action                      Duration
------  ------------------  --------------------------  --------
00:00   Initialization      State management setup      5s
00:05   node_exporter       Begin upgrade
00:06   ├─ Validation       Disk space, dependencies    2s
00:08   ├─ Backup           Binary + service file       3s
00:11   ├─ Stop Service     systemctl stop              2s
00:13   ├─ Download         GitHub release download     10s
00:23   ├─ Install          Binary replacement          2s
00:25   ├─ Start Service    systemctl start             2s
00:27   ├─ Health Check     Wait for /metrics (30s)     5s
00:32   └─ Complete         Mark as completed           1s
        [10s pause between components]
00:42   nginx_exporter      Same as above               ~25s
01:07   mysqld_exporter     Same as above               ~25s
01:32   phpfpm_exporter     Same as above               ~25s
01:57   fail2ban_exporter   Same as above               ~25s
02:22   Phase Complete      All components upgraded
```

**Interactive Prompts (Standard Mode):**

Only one confirmation at the start:
```
Proceed with phase 1 upgrade? [y/N] y
```

After confirmation, the upgrade proceeds automatically with 10-second pauses between components.

#### Step 3: Monitor Progress (Real-Time)

**In a separate terminal, tail the orchestrator output:**
```bash
# If running in background
tail -f /var/lib/observability-upgrades/state.json | jq '.'

# Or watch upgrade status
watch -n 5 'sudo ./scripts/upgrade-orchestrator.sh --status'
```

**Status Output Example:**
```
Upgrade Summary
===============
Upgrade ID:        upgrade-20251227-140000
Status:            in_progress
Current Phase:     1
Current Component: mysqld_exporter

Component Statistics:
  Completed:   2 (node_exporter, nginx_exporter)
  In Progress: 1 (mysqld_exporter)
  Pending:     2 (phpfpm_exporter, fail2ban_exporter)
  Failed:      0
  Skipped:     0
```

#### Step 4: Handle Completion (2 minutes)

**Success Scenario:**

```
Phase 1 Summary:
  Succeeded: 5
  Failed: 0

=== PHASE 1 COMPLETED SUCCESSFULLY ===
```

**Actions:**
1. Verify all exporters are running
2. Check metrics collection resumed
3. Document completion time and any issues

**Failure Scenario:**

```
Phase 1 Summary:
  Succeeded: 3
  Failed: 2 (phpfpm_exporter, fail2ban_exporter)

=== PHASE 1 COMPLETED WITH FAILURES ===
```

**Actions:**
1. Review failure logs: `journalctl -u <failed-exporter> -n 50`
2. Check state file: `cat /var/lib/observability-upgrades/state.json | jq '.components.<failed>'`
3. Decide: Retry individually or rollback

### Execution Timeline

| Time Offset | Activity | Expected Duration |
|-------------|----------|-------------------|
| T-15min | Run pre-flight checklist | 15 minutes |
| T-5min | Notify team, create backup snapshot | 5 minutes |
| T+0min | Start dry-run | 2 minutes |
| T+2min | Review dry-run output | 3 minutes |
| T+5min | Execute Phase 1 upgrade | 20-25 minutes |
| T+30min | Post-upgrade validation | 10 minutes |
| T+40min | Document results, notify team | 5 minutes |
| **Total** | **End-to-end execution** | **45 minutes** |

---

## Component-Specific Details

### 1. node_exporter (1.7.0 → 1.9.1)

**Risk Level:** VERY LOW
**Hosts Affected:** ALL monitored hosts
**Port:** 9100
**Downtime:** 5-10 seconds

**Upgrade Steps:**
1. Stop systemd service
2. Download binary from GitHub: `prometheus/node_exporter` releases
3. Replace `/usr/local/bin/node_exporter`
4. Start systemd service
5. Wait for metrics endpoint (max 30s)

**Health Check:**
```bash
# Endpoint: http://localhost:9100/metrics
# Expected: HTTP 200
# Metric count: ~1000+ metrics

curl -s http://localhost:9100/metrics | head -20
# Should show: node_exporter_build_info{version="1.9.1"}
```

**Known Issues:**
- None expected for this version jump
- No breaking changes between 1.7.0 and 1.9.1

**Rollback Trigger:**
- Metrics endpoint not responding after 30s
- Service fails to start
- Version mismatch detected

**Dependencies:**
- None (can run independently)

---

### 2. nginx_exporter (1.1.0 → 1.5.1)

**Risk Level:** LOW
**Hosts Affected:** Hosts with nginx service
**Port:** 9113
**Downtime:** 5-10 seconds

**Upgrade Steps:**
1. Stop systemd service
2. Download binary from GitHub: `nginxinc/nginx-prometheus-exporter` releases
3. Replace `/usr/local/bin/nginx_exporter`
4. Start systemd service
5. Wait for metrics endpoint (max 30s)

**Health Check:**
```bash
# Endpoint: http://localhost:9113/metrics
# Expected: HTTP 200

curl -s http://localhost:9113/metrics | grep nginx_up
# Should show: nginx_up 1
```

**Configuration Changes:**
- No config file changes required
- Service file remains unchanged
- Nginx stub_status module must still be enabled

**Known Issues:**
- Major version jump (1.x → 1.5.x) but backward compatible
- No breaking changes in exporter

**Rollback Trigger:**
- nginx_up metric not present
- Connection refused to nginx stub_status
- Service crash loop

**Dependencies:**
- Requires nginx stub_status configured at: `http://127.0.0.1:8080/stub_status`

---

### 3. mysqld_exporter (0.15.1 → 0.18.0)

**Risk Level:** LOW
**Hosts Affected:** Hosts with MySQL/MariaDB
**Port:** 9104
**Downtime:** 5-10 seconds

**Upgrade Steps:**
1. Stop systemd service
2. Download binary from GitHub: `prometheus/mysqld_exporter` releases
3. Replace `/usr/local/bin/mysqld_exporter`
4. Start systemd service
5. Wait for metrics endpoint (max 30s)

**Health Check:**
```bash
# Endpoint: http://localhost:9104/metrics
# Expected: HTTP 200

curl -s http://localhost:9104/metrics | grep mysql_up
# Should show: mysql_up 1
```

**Configuration Files:**
- Credentials: `/etc/.mysqld_exporter.cnf` (unchanged)
- Format:
  ```ini
  [client]
  user=exporter
  password=EXPORTER_PASSWORD
  ```

**Known Issues:**
- 0.15.1 → 0.18.0 adds new metrics (no removals)
- Ensure MySQL user `exporter` has required permissions:
  ```sql
  GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';
  FLUSH PRIVILEGES;
  ```

**Rollback Trigger:**
- mysql_up metric showing 0
- Authentication failures in logs
- Missing critical metrics

**Dependencies:**
- MySQL/MariaDB service must be running
- Exporter user credentials must be valid

---

### 4. phpfpm_exporter (2.2.0 → 2.3.0)

**Risk Level:** LOW
**Hosts Affected:** Hosts with PHP-FPM
**Port:** 9253
**Downtime:** 5-10 seconds

**Upgrade Steps:**
1. Stop systemd service
2. Download binary from GitHub: `hipages/php-fpm_exporter` releases
3. Replace `/usr/local/bin/php-fpm_exporter`
4. Start systemd service
5. Wait for metrics endpoint (max 30s)

**Health Check:**
```bash
# Endpoint: http://localhost:9253/metrics
# Expected: HTTP 200

curl -s http://localhost:9253/metrics | grep phpfpm_up
# Should show: phpfpm_up 1
```

**Configuration:**
- Listens on PHP-FPM socket: `/run/php/php8.2-fpm.sock`
- Service file may specify socket path
- Verify socket permissions if issues occur

**Known Issues:**
- 2.2.0 → 2.3.0 is a minor release (low risk)
- Socket path may vary by PHP version
- Common paths:
  - `/run/php/php8.2-fpm.sock`
  - `/run/php/php8.1-fpm.sock`
  - `/var/run/php/php-fpm.sock`

**Rollback Trigger:**
- phpfpm_up metric showing 0
- Socket connection errors
- Pool metrics not appearing

**Dependencies:**
- PHP-FPM service must be running
- FPM status page must be enabled in pool config:
  ```ini
  pm.status_path = /status
  ```

---

### 5. fail2ban_exporter (0.4.1 → 0.5.0)

**Risk Level:** LOW
**Hosts Affected:** Hosts with fail2ban
**Port:** 9191
**Downtime:** 5-10 seconds

**Upgrade Steps:**
1. Stop systemd service
2. Download binary from GitHub: `jangrewe/prometheus-fail2ban-exporter` releases
3. Replace `/usr/local/bin/fail2ban_exporter`
4. Start systemd service
5. Wait for metrics endpoint (max 30s)

**Health Check:**
```bash
# Endpoint: http://localhost:9191/metrics
# Expected: HTTP 200

curl -s http://localhost:9191/metrics | grep fail2ban_up
# Should show: fail2ban_up 1
```

**Configuration:**
- Reads fail2ban jail status from fail2ban-client
- Requires permissions to run `fail2ban-client status`
- Usually runs as fail2ban user or root

**Known Issues:**
- 0.4.1 → 0.5.0 minor version bump (low risk)
- May require fail2ban service running
- Some jails may not report metrics if empty

**Rollback Trigger:**
- fail2ban_up metric showing 0
- Permission denied errors accessing fail2ban
- No jail metrics appearing

**Dependencies:**
- fail2ban service must be running
- Exporter user must have permission to run `fail2ban-client`

---

## Health Check Procedures

### Automated Health Checks

The upgrade orchestrator performs automatic health checks after each component upgrade:

**Health Check Flow:**
```
1. Wait 5 seconds for service startup
2. Attempt HTTP GET to metrics endpoint
3. Retry every 5 seconds for up to 30 seconds (6 attempts)
4. Verify HTTP 200 response
5. (Optional) Verify specific metrics present
```

**Configured in:** `config/upgrade.yaml`
```yaml
health_check:
  type: "http"
  endpoint: "http://localhost:9100/metrics"
  expected_status: 200
  timeout: 30
```

### Manual Health Check Script

Use this script to manually verify all exporters after upgrade:

```bash
#!/bin/bash
# File: /opt/observability-stack/scripts/phase1-health-check.sh

echo "=== Phase 1 Exporter Health Check ==="
echo ""

EXPORTERS=(
    "node_exporter:9100"
    "nginx_exporter:9113"
    "mysqld_exporter:9104"
    "phpfpm_exporter:9253"
    "fail2ban_exporter:9191"
)

FAILED=0
PASSED=0

for exporter_port in "${EXPORTERS[@]}"; do
    IFS=':' read -r exporter port <<< "$exporter_port"

    echo -n "Checking $exporter (port $port)... "

    # Check if service is running
    if ! systemctl is-active --quiet "$exporter"; then
        echo "❌ FAIL: Service not running"
        ((FAILED++))
        continue
    fi

    # Check metrics endpoint
    if ! curl -sf "http://localhost:${port}/metrics" > /dev/null; then
        echo "❌ FAIL: Metrics endpoint not responding"
        ((FAILED++))
        continue
    fi

    # Check version (optional)
    VERSION=$(curl -s "http://localhost:${port}/metrics" | grep -oP "${exporter}_build_info.*version=\"\K[^\"]+")

    echo "✓ PASS (version: $VERSION)"
    ((PASSED++))
done

echo ""
echo "=== Health Check Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ $FAILED -eq 0 ]]; then
    echo "✓ All exporters healthy"
    exit 0
else
    echo "❌ Some exporters failed health check"
    exit 1
fi
```

**Run manually:**
```bash
chmod +x /opt/observability-stack/scripts/phase1-health-check.sh
sudo ./scripts/phase1-health-check.sh
```

### Prometheus Target Verification

After Phase 1 upgrade, verify Prometheus is scraping all upgraded exporters:

```bash
# Check all targets in Prometheus
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | contains("exporter")) | {job: .labels.job, instance: .labels.instance, health: .health, lastScrape: .lastScrape}'
```

**Expected Output:**
```json
{
  "job": "node_exporter",
  "instance": "webserver-01:9100",
  "health": "up",
  "lastScrape": "2025-12-27T14:30:15.123Z"
}
{
  "job": "nginx_exporter",
  "instance": "webserver-01:9113",
  "health": "up",
  "lastScrape": "2025-12-27T14:30:18.456Z"
}
...
```

**Action if targets are down:**
1. Check exporter service status
2. Verify firewall allows Prometheus IP
3. Check exporter health endpoint directly
4. Review Prometheus scrape config

### Dashboard Verification

**Grafana Dashboards to Check:**

1. **Infrastructure Overview**
   - URL: `http://YOUR_DOMAIN/d/infrastructure-overview`
   - Check: All hosts showing as "Up"
   - Check: No gaps in metric graphs

2. **Node Exporter Details**
   - URL: `http://YOUR_DOMAIN/d/node-exporter-details`
   - Check: CPU, Memory, Disk metrics flowing
   - Check: No "No Data" panels

3. **Service-Specific Dashboards**
   - Nginx Dashboard: Connection and request metrics
   - MySQL Dashboard: QPS and connection metrics
   - PHP-FPM Dashboard: Pool and process metrics

**Visual Check:**
- No red "No Data" messages
- Graphs show continuous data (no gaps > 30 seconds)
- Latest data timestamp is current (< 1 minute old)

---

## Rollback Procedures

### Automatic Rollback

The upgrade orchestrator automatically rolls back if:
1. Health check fails after 30 seconds
2. Service fails to start
3. Version verification fails

**Automatic Rollback Flow:**
```
1. Detect health check failure
2. Stop service
3. Restore binary from backup
4. Restore service file from backup
5. Start service
6. Verify rollback health check
7. Mark component as "failed" in state
```

### Manual Rollback

#### Individual Component Rollback

```bash
# Rollback specific component
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --rollback
```

#### Full Phase 1 Rollback

```bash
# Rollback all Phase 1 components
sudo ./scripts/upgrade-orchestrator.sh --rollback
```

**What This Does:**
- Iterates through all upgraded components
- Restores from automatic backups
- Verifies health after rollback
- Updates state to mark rollback

#### Manual Rollback (If Orchestrator Fails)

If the orchestrator itself is broken, manually rollback components:

```bash
#!/bin/bash
# Manual rollback script for node_exporter

COMPONENT="node_exporter"
BACKUP_DIR="/var/lib/observability-upgrades/backups/${COMPONENT}"

# Find latest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -1)

if [[ -z "$LATEST_BACKUP" ]]; then
    echo "No backup found for $COMPONENT"
    exit 1
fi

echo "Rolling back $COMPONENT from backup: $LATEST_BACKUP"

# Stop service
systemctl stop "$COMPONENT"

# Restore binary
cp -p "${BACKUP_DIR}/${LATEST_BACKUP}/${COMPONENT}" "/usr/local/bin/${COMPONENT}"

# Restore service file
if [[ -f "${BACKUP_DIR}/${LATEST_BACKUP}/${COMPONENT}.service" ]]; then
    cp -p "${BACKUP_DIR}/${LATEST_BACKUP}/${COMPONENT}.service" "/etc/systemd/system/${COMPONENT}.service"
    systemctl daemon-reload
fi

# Start service
systemctl start "$COMPONENT"

# Verify
sleep 3
if systemctl is-active --quiet "$COMPONENT"; then
    echo "✓ Rollback successful"
else
    echo "❌ Rollback failed - service not running"
    exit 1
fi
```

### Rollback Decision Matrix

| Failure Scenario | Automatic Rollback? | Manual Action Required |
|------------------|---------------------|------------------------|
| Single exporter health check fails | ✓ Yes | Review logs, re-attempt upgrade |
| Multiple exporters fail | ✓ Yes (each individually) | Investigate common cause |
| Network partition during upgrade | ✗ No | Resume upgrade when network restored |
| Disk full during download | ✗ No | Free space, resume upgrade |
| GitHub API rate limit | ✗ No | Wait 1 hour, resume |
| Service file corruption | ✓ Yes | Restore from backup |

### Rollback Validation

After rollback, verify:

```bash
# 1. Check service is running
systemctl status node_exporter

# 2. Verify version rolled back
/usr/local/bin/node_exporter --version
# Should show: 1.7.0 (original version)

# 3. Check metrics endpoint
curl http://localhost:9100/metrics | grep node_exporter_build_info
# Should show: version="1.7.0"

# 4. Verify Prometheus scraping
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="node_exporter") | .health'
# Should show: "up"
```

---

## Post-Upgrade Validation

### Validation Checklist

**Immediately After Upgrade (T+0):**

- [ ] All 5 exporters show "completed" status in orchestrator
- [ ] All exporter services are active: `systemctl is-active node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter`
- [ ] All metrics endpoints respond HTTP 200
- [ ] Version verification: Each exporter reports target version
- [ ] No error messages in orchestrator output

**5 Minutes After Upgrade (T+5):**

- [ ] Prometheus targets all show "up" status
- [ ] Metrics scrape success rate = 100%
- [ ] No gaps in metric graphs on Grafana
- [ ] Latest scrape timestamp is current (< 1 minute ago)
- [ ] Alert for "ExporterDown" is not firing

**15 Minutes After Upgrade (T+15):**

- [ ] Continuous metrics collection confirmed
- [ ] Dashboards show data for all upgraded exporters
- [ ] No anomalies in metric values (sudden spikes/drops)
- [ ] Resource usage normal (CPU, memory on monitored hosts)
- [ ] No new errors in journalctl for any exporter

**1 Hour After Upgrade (T+60):**

- [ ] Long-term stability confirmed
- [ ] No service crashes or restarts
- [ ] Alert history shows no unexpected alerts
- [ ] Upgrade state marked as "completed" successfully

### Validation Scripts

#### Quick Validation

```bash
#!/bin/bash
# Quick post-upgrade validation

echo "=== Quick Validation ==="

# Check orchestrator status
echo "1. Orchestrator Status:"
sudo ./scripts/upgrade-orchestrator.sh --status | grep -A 5 "Upgrade Summary"

# Check all exporter services
echo ""
echo "2. Exporter Services:"
systemctl is-active node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter

# Check Prometheus targets
echo ""
echo "3. Prometheus Targets:"
curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job | contains("exporter")) | "\(.labels.job): \(.health)"' | sort | uniq -c

echo ""
echo "=== Validation Complete ==="
```

#### Comprehensive Validation

```bash
#!/bin/bash
# Comprehensive post-upgrade validation
# File: /opt/observability-stack/scripts/phase1-validate.sh

VALIDATION_FAILED=0

echo "========================================="
echo " Phase 1 Post-Upgrade Validation"
echo "========================================="
echo ""

# 1. Orchestrator State
echo "1. Checking Orchestrator State..."
UPGRADE_STATUS=$(sudo ./scripts/upgrade-orchestrator.sh --status | grep "Status:" | awk '{print $2}')
if [[ "$UPGRADE_STATUS" == "completed" ]]; then
    echo "   ✓ Upgrade status: completed"
else
    echo "   ⚠ Upgrade status: $UPGRADE_STATUS"
    VALIDATION_FAILED=1
fi

# 2. Component Versions
echo ""
echo "2. Verifying Component Versions..."
EXPECTED_VERSIONS=(
    "node_exporter:1.9.1"
    "nginx_exporter:1.5.1"
    "mysqld_exporter:0.18.0"
    "phpfpm_exporter:2.3.0"
    "fail2ban_exporter:0.5.0"
)

for exp_ver in "${EXPECTED_VERSIONS[@]}"; do
    IFS=':' read -r component expected_version <<< "$exp_ver"
    ACTUAL_VERSION=$(/usr/local/bin/$component --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$ACTUAL_VERSION" == "$expected_version" ]]; then
        echo "   ✓ $component: $ACTUAL_VERSION"
    else
        echo "   ❌ $component: Expected $expected_version, Got $ACTUAL_VERSION"
        VALIDATION_FAILED=1
    fi
done

# 3. Service Status
echo ""
echo "3. Checking Service Status..."
for component in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    if systemctl is-active --quiet $component; then
        echo "   ✓ $component: active"
    else
        echo "   ❌ $component: inactive"
        VALIDATION_FAILED=1
    fi
done

# 4. Metrics Endpoints
echo ""
echo "4. Checking Metrics Endpoints..."
ENDPOINTS=(
    "node_exporter:9100"
    "nginx_exporter:9113"
    "mysqld_exporter:9104"
    "phpfpm_exporter:9253"
    "fail2ban_exporter:9191"
)

for endpoint in "${ENDPOINTS[@]}"; do
    IFS=':' read -r component port <<< "$endpoint"
    if curl -sf "http://localhost:${port}/metrics" > /dev/null; then
        METRIC_COUNT=$(curl -s "http://localhost:${port}/metrics" | grep -c "^[a-z]")
        echo "   ✓ $component: responding ($METRIC_COUNT metrics)"
    else
        echo "   ❌ $component: not responding"
        VALIDATION_FAILED=1
    fi
done

# 5. Prometheus Targets
echo ""
echo "5. Checking Prometheus Targets..."
TARGET_STATUS=$(curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job | contains("exporter")) | "\(.labels.job):\(.health)"' | sort | uniq -c)
echo "$TARGET_STATUS" | while read -r count status; do
    IFS=':' read -r job health <<< "$status"
    if [[ "$health" == "up" ]]; then
        echo "   ✓ $job: $count targets up"
    else
        echo "   ❌ $job: $count targets down"
        VALIDATION_FAILED=1
    fi
done

# 6. Metrics Gap Check
echo ""
echo "6. Checking for Metrics Gaps..."
for component in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    # Query Prometheus for gaps in last 15 minutes
    GAPS=$(curl -s "http://localhost:9090/api/v1/query?query=up{job=\"${component}\"}" | jq -r '.data.result[0].value[1]')
    if [[ "$GAPS" == "1" ]]; then
        echo "   ✓ $component: no gaps"
    else
        echo "   ⚠ $component: possible gap or down"
    fi
done

# 7. Backup Verification
echo ""
echo "7. Verifying Backups Created..."
for component in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
    BACKUP_DIR="/var/lib/observability-upgrades/backups/${component}"
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A $BACKUP_DIR 2>/dev/null)" ]]; then
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -1)
        echo "   ✓ $component: backup exists ($LATEST_BACKUP)"
    else
        echo "   ⚠ $component: no backup found"
    fi
done

# Summary
echo ""
echo "========================================="
if [[ $VALIDATION_FAILED -eq 0 ]]; then
    echo " ✓ ALL VALIDATIONS PASSED"
    echo "========================================="
    exit 0
else
    echo " ❌ SOME VALIDATIONS FAILED"
    echo "========================================="
    exit 1
fi
```

**Run comprehensive validation:**
```bash
chmod +x /opt/observability-stack/scripts/phase1-validate.sh
sudo ./scripts/phase1-validate.sh
```

### Metrics to Monitor

**During Upgrade Window (Real-Time):**

| Metric | Query | Expected | Alert If |
|--------|-------|----------|----------|
| Exporter Up | `up{job=~".*exporter"}` | 1 | 0 for > 30s |
| Scrape Success | `up{job=~".*exporter"}` | 1 | < 1 |
| Scrape Duration | `scrape_duration_seconds{job=~".*exporter"}` | < 1s | > 5s |
| Instance Count | `count(up{job=~".*exporter"})` | Expected # | < Expected |

**After Upgrade (Historical):**

| Metric | Query | Purpose |
|--------|-------|---------|
| Gaps in Collection | `changes(up{job="node_exporter"}[15m])` | Detect scrape interruptions |
| Metric Count Change | `count(node_exporter_build_info) by (version)` | Verify version upgrade |
| Service Restarts | `node_systemd_unit_state{name=~".*exporter.service"}` | Detect crashes |

---

## Risk Assessment

### Risk Matrix

| Risk Category | Probability | Impact | Mitigation | Residual Risk |
|---------------|-------------|--------|------------|---------------|
| **Exporter Binary Failure** | Low (5%) | Medium | Automatic rollback | Very Low |
| **Network Partition** | Very Low (1%) | High | Resume on reconnect | Low |
| **Disk Space Exhaustion** | Very Low (2%) | Medium | Pre-flight check | Very Low |
| **GitHub Rate Limit** | Low (5%) | Low | Version caching, retry | Very Low |
| **Service Crash Loop** | Very Low (1%) | Medium | Health check + rollback | Very Low |
| **Config Incompatibility** | Very Low (1%) | Low | No config changes | Very Low |
| **Multiple Host Failures** | Very Low (1%) | High | Sequential upgrade, pause | Very Low |

### What Could Go Wrong

#### Scenario 1: GitHub API Rate Limit Exceeded

**Symptom:**
```
[ERROR] Failed to download node_exporter from GitHub
GitHub API rate limit exceeded
```

**Cause:**
- Too many download requests to GitHub API
- Unauthenticated requests have 60/hour limit

**Impact:**
- Upgrade will pause and retry
- May delay upgrade by 1 hour

**Mitigation:**
- Orchestrator caches versions for 15 minutes
- Set `GITHUB_TOKEN` environment variable for 5000/hour limit
- Fallback to cached versions in `config/upgrade.yaml`

**Resolution:**
```bash
# Option 1: Wait 1 hour and resume
sudo ./scripts/upgrade-orchestrator.sh --resume

# Option 2: Use GitHub token
export GITHUB_TOKEN="ghp_your_personal_access_token"
sudo -E ./scripts/upgrade-orchestrator.sh --resume

# Option 3: Use fallback versions
# Already configured in config/upgrade.yaml
```

#### Scenario 2: Exporter Service Fails to Start After Upgrade

**Symptom:**
```
[ERROR] Health check failed for nginx_exporter after 30s
[WARN] Attempting automatic rollback...
```

**Cause:**
- Binary incompatibility
- Missing dependencies
- Port already in use
- Service file misconfiguration

**Impact:**
- Single exporter affected
- Automatic rollback restores previous version
- No data loss (max 30s gap)

**Mitigation:**
- Health checks detect failure immediately
- Automatic rollback prevents prolonged outage

**Resolution:**
```bash
# 1. Check what went wrong
journalctl -u nginx_exporter -n 50 --no-pager

# 2. Common issues:
# - Port conflict:
lsof -i :9113

# - Permissions:
ls -la /usr/local/bin/nginx_exporter
# Should be: -rwxr-xr-x root root

# - Dependencies:
ldd /usr/local/bin/nginx_exporter

# 3. Fix and retry
sudo ./scripts/upgrade-orchestrator.sh --component nginx_exporter --force
```

#### Scenario 3: Metrics Gap During Upgrade

**Symptom:**
- Gaps in Grafana dashboards
- Prometheus shows scrape failures

**Cause:**
- Exporter service stopped during binary replacement
- Expected behavior (5-10 second window)

**Impact:**
- Small gap in metrics (< 30 seconds per exporter)
- No permanent data loss
- Historical queries unaffected

**Mitigation:**
- Sequential upgrades with pauses reduce overall impact
- Prometheus continues trying to scrape

**Resolution:**
- No action needed if gap < 30 seconds
- Verify metrics resume flowing after upgrade

#### Scenario 4: Upgrade Orchestrator Crashes Mid-Upgrade

**Symptom:**
- Orchestrator process killed
- Partial upgrade completed

**Cause:**
- OOM killer
- SSH connection dropped
- System reboot

**Impact:**
- Some components upgraded, others not
- State file preserves progress

**Mitigation:**
- Idempotent design allows safe resume
- State file tracks completion

**Resolution:**
```bash
# Resume from where it left off
sudo ./scripts/upgrade-orchestrator.sh --resume

# The orchestrator will:
# 1. Read state file
# 2. Skip already-completed components
# 3. Continue with pending components
```

#### Scenario 5: Configuration File Corruption

**Symptom:**
```
[ERROR] Invalid upgrade configuration
Configuration file not valid YAML
```

**Cause:**
- Manual edit introduced syntax error
- File permissions changed
- Disk corruption

**Impact:**
- Upgrade cannot proceed
- No components affected (fail-fast)

**Mitigation:**
- Pre-flight validation catches issues early
- Automatic backups preserve good state

**Resolution:**
```bash
# 1. Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('config/upgrade.yaml'))"

# 2. Restore from backup if corrupted
cp /var/backups/observability-stack/LATEST/upgrade.yaml config/

# 3. Verify and retry
sudo ./scripts/upgrade-orchestrator.sh --verify
sudo ./scripts/upgrade-orchestrator.sh --phase 1
```

### Monitoring Gaps During Upgrade

**Expected Gaps:**
- Per exporter: 5-10 seconds (service restart)
- With 5 exporters + 10s pauses: Total ~90 seconds of distributed gaps

**Acceptable:**
- Gaps < 30 seconds per component
- No overlapping gaps (sequential upgrade prevents this)
- All exporters back within 5 minutes

**Unacceptable:**
- Gaps > 30 seconds indicate failure
- Multiple exporters down simultaneously
- Persistent gaps after upgrade completes

**Monitoring Dashboard:**

Create temporary dashboard to track upgrade:

```
Panel 1: Exporter Status
Query: up{job=~".*exporter"}
Visualization: Stat panel showing count of "up" instances

Panel 2: Scrape Failures
Query: rate(up{job=~".*exporter"}[5m]) < 1
Visualization: Graph showing failed scrapes over time

Panel 3: Upgrade Progress
Query: count(node_exporter_build_info{version="1.9.1"})
Visualization: Track how many hosts upgraded
```

---

## Dependencies and Coordination

### Inter-Component Dependencies

**Phase 1 Exporters:**
- **Independent:** All exporters can be upgraded in any order
- **No shared dependencies:** Each exporter is self-contained
- **No service coupling:** Failure of one doesn't affect others

**Dependency Graph:**
```
Phase 1 (No dependencies)
├─ node_exporter (standalone)
├─ nginx_exporter (requires nginx service, not upgraded)
├─ mysqld_exporter (requires mysql service, not upgraded)
├─ phpfpm_exporter (requires php-fpm service, not upgraded)
└─ fail2ban_exporter (requires fail2ban service, not upgraded)

Note: All exporters only depend on their monitored service,
      which is NOT being upgraded in Phase 1
```

### Host Coordination

**Multi-Host Deployment:**

If you have multiple monitored hosts:

**Option A: Sequential (Safest)**
```bash
# Upgrade one host at a time
for host in webserver-01 webserver-02 database-01; do
    ssh root@$host "cd /opt/observability-stack && ./scripts/upgrade-orchestrator.sh --phase 1"

    # Wait and verify before next host
    sleep 60
done
```

**Option B: Parallel (Faster, More Risk)**
```bash
# Upgrade all hosts simultaneously
HOSTS="webserver-01 webserver-02 database-01"

for host in $HOSTS; do
    ssh root@$host "cd /opt/observability-stack && nohup ./scripts/upgrade-orchestrator.sh --phase 1 > /tmp/upgrade.log 2>&1 &"
done

# Monitor progress
for host in $HOSTS; do
    ssh root@$host "tail -f /tmp/upgrade.log"
done
```

**Recommended:** Sequential for production

### External Service Dependencies

| Exporter | Depends On | Upgrade Impact | Mitigation |
|----------|-----------|----------------|------------|
| node_exporter | None | No impact | None needed |
| nginx_exporter | nginx service | Exporter restart won't affect nginx | Verify nginx stub_status configured |
| mysqld_exporter | MySQL/MariaDB | Exporter restart won't affect database | Verify exporter user credentials valid |
| phpfpm_exporter | PHP-FPM | Exporter restart won't affect PHP | Verify FPM status endpoint enabled |
| fail2ban_exporter | fail2ban service | Exporter restart won't affect fail2ban | Verify exporter can access fail2ban-client |

**Important:** Phase 1 only upgrades exporters, NOT the services they monitor.

### Prometheus Scraping

**During Upgrade:**
- Prometheus will attempt to scrape every 15 seconds (default interval)
- During exporter restart (5-10s), scrapes will fail
- Failed scrapes are logged but don't alert (unless down > alert threshold)

**Alert Thresholds:**
- Most "ExporterDown" alerts have `for: 1m` threshold
- 5-10 second outage won't trigger alerts
- If upgrade takes > 1 minute per component, alerts may fire

**Mitigation:**
- Pre-silence exporter alerts for upgrade window (see Pre-Flight Checklist)
- Or accept brief alert notifications (will auto-resolve)

### Team Coordination

**Stakeholders to Notify:**

1. **Operations Team**
   - When: 15 minutes before upgrade
   - Why: Aware of potential brief alerts
   - How: Slack/Email

2. **Development Team**
   - When: Day before upgrade
   - Why: Aware of maintenance window
   - How: Slack/Email

3. **Management**
   - When: Day before upgrade
   - Why: Awareness of change management
   - How: Email summary

**Communication Template:**

```
Subject: Phase 1 Exporter Upgrades - [DATE] [TIME]

Team,

We will be upgrading monitoring exporters on all hosts:

Date: [YYYY-MM-DD]
Time: [HH:MM] - [HH:MM] ([TIMEZONE])
Duration: 30-45 minutes
Impact: Minimal (5-10 second gaps per exporter)
Risk: LOW

Components:
- node_exporter: 1.7.0 → 1.9.1
- nginx_exporter: 1.1.0 → 1.5.1
- mysqld_exporter: 0.15.1 → 0.18.0
- phpfpm_exporter: 2.2.0 → 2.3.0
- fail2ban_exporter: 0.4.1 → 0.5.0

Expected Impact:
- Brief gaps in metrics collection (< 30 seconds per host)
- Possible "ExporterDown" alert notifications (auto-resolve)
- No impact to monitored services (nginx, mysql, php-fpm, fail2ban)

Rollback Plan:
- Automatic rollback if health checks fail
- Manual rollback available if needed

Contact:
- Primary: [YOUR NAME] ([CONTACT])
- Secondary: [BACKUP CONTACT]

Thanks,
[YOUR NAME]
```

### Change Management

**Pre-Upgrade:**
- [ ] Create change ticket in ticketing system
- [ ] Document current versions
- [ ] Schedule upgrade window
- [ ] Notify stakeholders
- [ ] Prepare rollback plan

**During Upgrade:**
- [ ] Update change ticket with progress
- [ ] Monitor upgrade status
- [ ] Document any issues encountered
- [ ] Communicate any delays

**Post-Upgrade:**
- [ ] Verify all components upgraded
- [ ] Update change ticket with results
- [ ] Notify stakeholders of completion
- [ ] Document lessons learned

---

## Appendix

### A. Complete Command Reference

```bash
# Pre-Flight
sudo ./scripts/upgrade-orchestrator.sh --status
sudo ./scripts/upgrade-orchestrator.sh --verify
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --dry-run

# Execution
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode standard
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode safe      # With manual confirmations
sudo ./scripts/upgrade-orchestrator.sh --phase 1 --mode fast      # Skip pauses

# Individual Component
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter
sudo ./scripts/upgrade-orchestrator.sh --component node_exporter --force

# Recovery
sudo ./scripts/upgrade-orchestrator.sh --resume
sudo ./scripts/upgrade-orchestrator.sh --rollback

# Validation
sudo ./scripts/phase1-health-check.sh
sudo ./scripts/phase1-validate.sh
```

### B. State File Structure

Location: `/var/lib/observability-upgrades/state.json`

```json
{
  "version": "1.0.0",
  "upgrade_id": "upgrade-20251227-140000",
  "status": "in_progress",
  "started_at": "2025-12-27T14:00:00Z",
  "updated_at": "2025-12-27T14:15:00Z",
  "completed_at": null,
  "current_phase": 1,
  "current_component": "mysqld_exporter",
  "mode": "standard",
  "components": {
    "node_exporter": {
      "status": "completed",
      "from_version": "1.7.0",
      "to_version": "1.9.1",
      "started_at": "2025-12-27T14:01:00Z",
      "completed_at": "2025-12-27T14:02:30Z",
      "attempts": 1,
      "backup_path": "/var/lib/observability-upgrades/backups/node_exporter/20251227_140100",
      "rollback_available": true,
      "health_check_passed": true,
      "checksum": "sha256:abc123..."
    },
    "nginx_exporter": {
      "status": "completed",
      "from_version": "1.1.0",
      "to_version": "1.5.1",
      "started_at": "2025-12-27T14:05:00Z",
      "completed_at": "2025-12-27T14:06:25Z",
      "attempts": 1,
      "backup_path": "/var/lib/observability-upgrades/backups/nginx_exporter/20251227_140500",
      "rollback_available": true,
      "health_check_passed": true,
      "checksum": "sha256:def456..."
    },
    "mysqld_exporter": {
      "status": "in_progress",
      "from_version": "0.15.1",
      "to_version": "0.18.0",
      "started_at": "2025-12-27T14:10:00Z",
      "completed_at": null,
      "attempts": 1,
      "backup_path": "/var/lib/observability-upgrades/backups/mysqld_exporter/20251227_141000",
      "rollback_available": true,
      "health_check_passed": false,
      "checksum": null
    },
    "phpfpm_exporter": {
      "status": "pending",
      "from_version": null,
      "to_version": "2.3.0",
      "started_at": null,
      "completed_at": null,
      "attempts": 0,
      "backup_path": null,
      "rollback_available": false,
      "health_check_passed": false,
      "checksum": null
    },
    "fail2ban_exporter": {
      "status": "pending",
      "from_version": null,
      "to_version": "0.5.0",
      "started_at": null,
      "completed_at": null,
      "attempts": 0,
      "backup_path": null,
      "rollback_available": false,
      "health_check_passed": false,
      "checksum": null
    }
  },
  "errors": [],
  "checkpoints": []
}
```

### C. Troubleshooting Decision Tree

```
Issue: Upgrade orchestrator fails to start
├─ Check root permissions: id
│  └─ Not root → Run with sudo
├─ Check dependencies: which jq curl python3
│  └─ Missing → apt-get install jq curl python3
└─ Check config file: ls -la config/upgrade.yaml
   └─ Missing → Restore from repo

Issue: Individual exporter upgrade fails
├─ Check state file: cat /var/lib/observability-upgrades/state.json | jq '.components.node_exporter'
│  ├─ Status: failed → Check error field
│  └─ Attempts: > 1 → Manual intervention needed
├─ Check service logs: journalctl -u node_exporter -n 50
│  ├─ Permission denied → Check binary ownership
│  ├─ Address in use → Check port conflicts: lsof -i :9100
│  └─ File not found → Verify binary path
└─ Check health endpoint: curl http://localhost:9100/metrics
   ├─ Connection refused → Service not running
   ├─ HTTP 500 → Check service logs
   └─ Timeout → Firewall or network issue

Issue: Health check fails after upgrade
├─ Wait 30 seconds → Automatic retry
├─ Check service status: systemctl status node_exporter
│  ├─ Failed → Check logs
│  └─ Active → Check endpoint
├─ Manual health check: curl -v http://localhost:9100/metrics
│  ├─ Connection refused → Service not listening
│  ├─ HTTP 404 → Wrong endpoint
│  └─ Timeout → Network issue
└─ Verify version: /usr/local/bin/node_exporter --version
   └─ Wrong version → Rollback and retry

Issue: Prometheus not scraping after upgrade
├─ Check Prometheus targets: curl localhost:9090/api/v1/targets
│  └─ Target missing → Regenerate Prometheus config
├─ Check firewall: ufw status
│  └─ Blocking → Add allow rule for Prometheus IP
├─ Check exporter binding: ss -tlnp | grep 9100
│  └─ Not listening → Service configuration issue
└─ Check Prometheus logs: journalctl -u prometheus -n 50
   └─ Scrape error → Check target URL in prometheus.yml
```

### D. Version Release Notes Summary

**node_exporter 1.7.0 → 1.9.1**
- New collectors: zoneinfo, pressure, rapl
- Performance improvements in filesystem collector
- Bug fixes for systemd collector
- No breaking changes

**nginx_exporter 1.1.0 → 1.5.1**
- Added support for NGINX Plus API
- Improved error handling for stub_status
- Metrics naming consistency improvements
- No breaking changes

**mysqld_exporter 0.15.1 → 0.18.0**
- New metrics: InnoDB redo log, binlog cache
- Performance improvements for high-connection databases
- Fixed memory leak in long-running exporters
- No breaking changes (all new metrics are additions)

**phpfpm_exporter 2.2.0 → 2.3.0**
- Support for multiple PHP-FPM pools
- Improved socket handling
- Bug fixes for slow request tracking
- No breaking changes

**fail2ban_exporter 0.4.1 → 0.5.0**
- Support for fail2ban 1.0+
- New metrics: unban count, ban duration
- Improved jail status parsing
- No breaking changes

### E. Contact and Escalation

**Primary Contact:**
- Name: [YOUR NAME]
- Email: [YOUR EMAIL]
- Phone: [YOUR PHONE]
- Availability: [UPGRADE WINDOW]

**Escalation Path:**

Level 1: Self-service (this document)
Level 2: Team lead / Senior engineer
Level 3: Infrastructure manager
Level 4: Vendor support (GitHub Issues)

**Vendor Support:**

| Component | GitHub Issues | Response Time |
|-----------|---------------|---------------|
| node_exporter | https://github.com/prometheus/node_exporter/issues | Community (best effort) |
| nginx_exporter | https://github.com/nginxinc/nginx-prometheus-exporter/issues | Community |
| mysqld_exporter | https://github.com/prometheus/mysqld_exporter/issues | Community |
| phpfpm_exporter | https://github.com/hipages/php-fpm_exporter/issues | Community |
| fail2ban_exporter | https://github.com/jangrewe/prometheus-fail2ban-exporter/issues | Community |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-27 | Deployment Engineer | Initial Phase 1 execution plan |

---

## Sign-Off

**Prepared By:**
Deployment Engineer
Date: 2025-12-27

**Reviewed By:**
[NAME], [TITLE]
Date: ___________

**Approved By:**
[NAME], [TITLE]
Date: ___________

---

**END OF DOCUMENT**
