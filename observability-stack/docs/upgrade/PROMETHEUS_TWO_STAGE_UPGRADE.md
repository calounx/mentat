# Prometheus Two-Stage Upgrade Strategy (Phase 2)
## Critical Upgrade: 2.48.1 → 2.55.1 → 3.8.1

**DANGER: This is the highest risk upgrade in the observability stack.**

This document provides a comprehensive strategy for safely upgrading Prometheus from 2.48.1 to 3.8.1 through a required intermediate version 2.55.1.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Why Two Stages Are Required](#why-two-stages-are-required)
3. [Stage 1: 2.48.1 → 2.55.1](#stage-1-2481--2551)
4. [Stage 2: 2.55.1 → 3.8.1](#stage-2-2551--381)
5. [Risk Assessment](#risk-assessment)
6. [Complete Execution Plan](#complete-execution-plan)
7. [Breaking Changes Reference](#breaking-changes-reference)
8. [Rollback Procedures](#rollback-procedures)
9. [Validation Checklists](#validation-checklists)

---

## Executive Summary

### Critical Facts

- **Current Version**: Prometheus 2.48.1
- **Target Version**: Prometheus 3.8.1
- **Required Intermediate**: Prometheus 2.55.1
- **Cannot Skip**: Direct upgrade to 3.x will fail
- **One-Way Migration**: Cannot rollback after Stage 1 completes
- **Estimated Downtime**:
  - Stage 1: 10-15 minutes
  - Stage 2: 15-20 minutes
  - Total: ~30-35 minutes across both stages
- **Recommended Wait Between Stages**: 1-2 weeks

### Risk Level: HIGH

**Why This Is High Risk:**

1. TSDB format changes prevent direct upgrade
2. Breaking changes in Prometheus 3.x API and configuration
3. Native histograms require configuration updates
4. Alert rules may need syntax updates
5. Grafana dashboards may break
6. Recording rules could fail
7. Remote write endpoints might need reconfiguration

### Success Criteria

- All Prometheus targets remain scraped
- All alert rules continue firing
- Grafana dashboards display data correctly
- No data loss during migration
- Query performance remains stable
- TSDB compaction completes successfully

---

## Why Two Stages Are Required

### TSDB Compatibility Matrix

```
Prometheus Version    TSDB Format    Can Read Previous Format
------------------    -----------    -----------------------
2.48.1                v1            Yes (v1)
2.55.1                v2            Yes (v1, v2)
3.0.0+                v3            No (only v3)
```

### The Migration Problem

**Direct upgrade from 2.48.1 → 3.8.1 will fail because:**

1. Prometheus 2.48.1 uses TSDB format v1
2. Prometheus 3.x uses TSDB format v3
3. Prometheus 3.x **cannot read** TSDB format v1
4. Prometheus 2.55.1 is the bridge version that:
   - Can read TSDB format v1 (your current data)
   - Can write TSDB format v2 (compatible with 3.x)
   - Performs automatic migration on startup

### Data Migration Process

```
Stage 1: TSDB v1 → v2 Migration
--------------------------------
[2.48.1 with TSDB v1] → Stop → [2.55.1 starts] → Automatic conversion → [TSDB v2]
                                                  (10-15 min process)

Waiting Period (1-2 weeks)
--------------------------
Monitor stability, verify data integrity, validate queries

Stage 2: TSDB v2 → v3 Migration + Breaking Changes
---------------------------------------------------
[2.55.1 with TSDB v2] → Stop → Update config → [3.8.1 starts] → Automatic conversion → [TSDB v3]
                                                                  (15-20 min process)
```

### One-Way Migration Warning

**CRITICAL: After Stage 1 completes successfully:**

- You **cannot** downgrade to Prometheus < 2.55.1
- TSDB format v2 is not readable by Prometheus 2.48.1 or earlier
- The only rollback option is to restore from backup (see [Rollback Procedures](#rollback-procedures))

**Implication:** You must ensure Stage 1 is 100% successful before proceeding to Stage 2.

---

## Stage 1: 2.48.1 → 2.55.1

### Overview

**Goal**: Migrate TSDB from v1 to v2 format while maintaining backward compatibility with all existing configurations.

**Duration**: 10-15 minutes downtime + 1-2 weeks stability monitoring

**Risk Level**: Medium-High

### Pre-Stage 1 Requirements

#### 1. Full TSDB Backup

**CRITICAL: This is your only rollback option.**

```bash
# 1. Create backup directory
sudo mkdir -p /var/backups/prometheus-upgrade-stage1
BACKUP_DIR="/var/backups/prometheus-upgrade-stage1/backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

# 2. Create Prometheus TSDB snapshot (preferred method)
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# This creates a snapshot in /var/lib/prometheus/snapshots/
SNAPSHOT_DIR=$(ls -t /var/lib/prometheus/snapshots/ | head -1)
sudo cp -a "/var/lib/prometheus/snapshots/$SNAPSHOT_DIR" "$BACKUP_DIR/tsdb-snapshot"

# 3. Backup configuration files
sudo cp -a /etc/prometheus "$BACKUP_DIR/config"
sudo cp -a /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
sudo cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus-binary-2.48.1"
sudo cp /usr/local/bin/promtool "$BACKUP_DIR/promtool-binary-2.48.1"

# 4. Document current state
echo "2.48.1" > "$BACKUP_DIR/VERSION"
sudo systemctl status prometheus > "$BACKUP_DIR/service-status.txt"
curl http://localhost:9090/api/v1/status/config | jq . > "$BACKUP_DIR/runtime-config.json"
curl http://localhost:9090/api/v1/targets | jq . > "$BACKUP_DIR/targets.json"

# 5. Verify backup integrity
sudo du -sh "$BACKUP_DIR"
echo "Backup created at: $BACKUP_DIR"
echo "SAVE THIS PATH FOR ROLLBACK"
```

**Backup Size Estimation:**
- TSDB snapshot: ~2-10 GB (depends on retention period)
- Config files: ~1-5 MB
- Total: Allow 15 GB free disk space minimum

#### 2. Validation Checklist

```bash
# Check current version
prometheus --version
# Expected: prometheus, version 2.48.1

# Check disk space (need 3x current TSDB size)
df -h /var/lib/prometheus
# Need: Minimum 15 GB free

# Verify config syntax
promtool check config /etc/prometheus/prometheus.yml
# Expected: SUCCESS

# Check all targets are up
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | .labels.instance'
# Expected: Empty output (all targets healthy)

# Verify alert rules
promtool check rules /etc/prometheus/rules/*.yml
# Expected: SUCCESS

# Check TSDB health
curl -s http://localhost:9090/api/v1/status/tsdb | jq .
# Review for any warnings
```

### Stage 1 Execution Steps

#### Step 1: Download Prometheus 2.55.1

```bash
# Set version
PROM_VERSION="2.55.1"
ARCH="linux-amd64"

# Download
cd /tmp
wget "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.${ARCH}.tar.gz"

# Download checksum
wget "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/sha256sums.txt"

# Verify checksum
sha256sum -c sha256sums.txt 2>&1 | grep "prometheus-${PROM_VERSION}.${ARCH}.tar.gz"
# Expected: OK

# Extract
tar -xzf "prometheus-${PROM_VERSION}.${ARCH}.tar.gz"
cd "prometheus-${PROM_VERSION}.${ARCH}"
```

#### Step 2: Pre-Deployment Validation

```bash
# Test new binary with existing config
./prometheus --config.file=/etc/prometheus/prometheus.yml --web.enable-lifecycle --dry-run 2>&1 | grep -i error
# Expected: No errors

# Check version
./prometheus --version
# Expected: prometheus, version 2.55.1
```

#### Step 3: Stop Current Prometheus

```bash
# Stop service
sudo systemctl stop prometheus

# Verify stopped
sudo systemctl status prometheus
# Expected: inactive (dead)

# Verify no Prometheus processes running
ps aux | grep prometheus | grep -v grep
# Expected: Empty

# Record stop time for monitoring
echo "Prometheus stopped at: $(date)" | tee -a /tmp/prometheus-upgrade.log
```

#### Step 4: Install New Binary

```bash
# Backup old binaries (already done, but extra safety)
sudo cp /usr/local/bin/prometheus /usr/local/bin/prometheus-2.48.1.backup
sudo cp /usr/local/bin/promtool /usr/local/bin/promtool-2.48.1.backup

# Install new binaries
sudo cp prometheus /usr/local/bin/
sudo cp promtool /usr/local/bin/
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify installation
prometheus --version
# Expected: prometheus, version 2.55.1
```

#### Step 5: Configuration Updates (Stage 1)

**Good News**: Prometheus 2.55.1 is backward compatible with 2.48.1 configuration.

**No configuration changes required for Stage 1.**

However, verify the configuration:

```bash
# Validate config with new binary
promtool check config /etc/prometheus/prometheus.yml
# Expected: SUCCESS
```

#### Step 6: Start Prometheus 2.55.1

```bash
# Start service
sudo systemctl start prometheus

# Monitor startup logs (this is critical)
sudo journalctl -u prometheus -f
```

**Expected Log Output:**

```
level=info msg="Starting Prometheus" version="(version=2.55.1...)"
level=info msg="TSDB migration started" from_version=1 to_version=2
level=info msg="Replaying WAL" segment=0
level=info msg="WAL replay completed"
level=info msg="TSDB migration: converting blocks" total=X converted=Y
level=info msg="TSDB migration completed successfully" duration=10m32s
level=info msg="TSDB opened" duration=11m15s
level=info msg="Starting web handler"
level=info msg="Server is ready to receive web requests"
```

**CRITICAL: TSDB migration will take 10-15 minutes. Do not interrupt this process.**

#### Step 7: Health Validation

Wait for TSDB migration to complete, then run:

```bash
# Check service status
sudo systemctl status prometheus
# Expected: active (running)

# Check health endpoint
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

# Check readiness
curl -s http://localhost:9090/-/ready
# Expected: Prometheus is Ready.

# Verify targets are being scraped
sleep 60  # Wait for first scrape cycle
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health}'
# Expected: All targets show "health": "up"

# Check for errors in logs
sudo journalctl -u prometheus -n 100 --no-pager | grep -i error
# Expected: No critical errors

# Verify metrics collection
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'
# Expected: All instances show value "1"
```

#### Step 8: Validate TSDB Migration

```bash
# Check TSDB status
curl -s http://localhost:9090/api/v1/status/tsdb | jq .

# Verify data continuity (check for recent data)
curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total&time='$(date +%s) | jq '.data.result | length'
# Expected: Non-zero number of results

# Check oldest and newest data points
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | head -5
# Expected: Metric names returned

# Verify query performance (should be similar to 2.48.1)
time curl -s 'http://localhost:9090/api/v1/query_range?query=rate(node_cpu_seconds_total[5m])&start='$(($(date +%s) - 3600))'&end='$(date +%s)'&step=15s' > /dev/null
# Expected: Response within 2-5 seconds
```

#### Step 9: Alert Rules Validation

```bash
# Check if alert rules are loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'
# Expected: List of all your alert groups

# Verify alert evaluation
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {alert: .labels.alertname, state: .state}'
# Expected: Alerts in normal states (firing/pending/inactive)

# Check for rule evaluation errors
sudo journalctl -u prometheus -n 500 --no-pager | grep -i "rule evaluation"
# Expected: No errors
```

#### Step 10: Grafana Dashboard Validation

```bash
# Test Prometheus datasource from Grafana
# Access Grafana at http://your-domain:3000
# Navigate to: Configuration → Data Sources → Prometheus
# Click "Test" button
# Expected: "Data source is working"

# Verify dashboards load data
# Navigate to each dashboard and verify:
# - Overview dashboard shows all hosts
# - Node Exporter dashboard shows metrics
# - No "No data" panels
# - Queries execute without errors
```

### Stage 1 Validation Criteria (Before Stage 2)

**Do NOT proceed to Stage 2 until ALL criteria are met:**

- [ ] Prometheus 2.55.1 running stable for 1-2 weeks
- [ ] All targets scraped successfully (check daily)
- [ ] No TSDB compaction errors in logs
- [ ] All alert rules evaluating correctly
- [ ] Grafana dashboards displaying data
- [ ] Query performance acceptable
- [ ] No unexpected errors in logs
- [ ] Disk space usage stable
- [ ] No data gaps detected

**Recommended Monitoring Period**: 1-2 weeks

During this period:

1. **Daily Checks**:
   ```bash
   # Quick health check
   curl -s http://localhost:9090/-/healthy && echo "HEALTHY" || echo "UNHEALTHY"

   # Check for errors
   sudo journalctl -u prometheus --since "1 day ago" | grep -i error | wc -l
   # Expected: 0 or minimal errors

   # Verify target health
   curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | .labels.instance'
   # Expected: Empty
   ```

2. **Weekly Validation**:
   - Review Grafana dashboards for data continuity
   - Check alert rule firing history
   - Verify TSDB size and growth rate
   - Review disk usage trends

3. **Specific Tests**:
   ```bash
   # Test complex queries (recording rules)
   curl -s 'http://localhost:9090/api/v1/query?query=instance:node_cpu:ratio' | jq .

   # Verify long-range queries
   curl -s 'http://localhost:9090/api/v1/query_range?query=up&start='$(($(date +%s) - 604800))'&end='$(date +%s)'&step=3600s' | jq '.status'
   # Expected: "success"
   ```

### Stage 1 Success Indicators

Green light to proceed to Stage 2:

1. Zero TSDB corruption errors
2. All targets stable
3. Alert rules functioning
4. Grafana dashboards operational
5. No performance degradation
6. Logs clean of errors
7. Disk space under control

---

## Stage 2: 2.55.1 → 3.8.1

### Overview

**Goal**: Upgrade to Prometheus 3.8.1 with TSDB v3 format and implement breaking changes.

**Duration**: 15-20 minutes downtime

**Risk Level**: High

**Prerequisites**: Stage 1 completed and validated for 1-2 weeks

### Breaking Changes in Prometheus 3.x

Prometheus 3.x introduces several breaking changes that require configuration updates:

#### 1. Native Histograms (Enabled by Default)

**What Changed**: Prometheus 3.x enables native histogram support by default.

**Impact**:
- Existing histogram metrics may be collected differently
- Query syntax for histograms may need updates
- Potential increase in storage usage

**Action Required**: Configure native histograms behavior.

#### 2. Scrape Configuration Changes

**What Changed**: Some scrape configuration flags and behaviors changed.

**Impact**:
- `honor_timestamps` default changed
- `scrape_timeout` validation stricter
- Metric relabeling behavior updated

**Action Required**: Review and update scrape configs.

#### 3. Deprecated Feature Flags Removed

**Removed Flags**:
- `--storage.tsdb.allow-overlapping-blocks` (now always allowed)
- `--storage.tsdb.wal-compression` (now always enabled)
- `--web.enable-admin-api` (replaced with `--web.enable-lifecycle`)

**Action Required**: Remove deprecated flags from systemd service file.

#### 4. PromQL Function Changes

**Changed Functions**:
- `timestamp()` behavior updated
- `histogram_quantile()` supports native histograms
- New functions for native histogram operations

**Action Required**: Review recording rules and complex queries.

#### 5. Remote Write Changes

**What Changed**: Remote write protocol updated to v2.0.

**Impact**: Remote write endpoints must support v2.0 protocol.

**Action Required**: Verify remote write compatibility (if configured).

### Pre-Stage 2 Requirements

#### 1. Full TSDB Backup (Again)

**CRITICAL: Create a new backup before Stage 2.**

```bash
# Create Stage 2 backup directory
BACKUP_DIR="/var/backups/prometheus-upgrade-stage2/backup-$(date +%Y%m%d-%H%M%S)"
sudo mkdir -p "$BACKUP_DIR"

# Create TSDB snapshot
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
SNAPSHOT_DIR=$(ls -t /var/lib/prometheus/snapshots/ | head -1)
sudo cp -a "/var/lib/prometheus/snapshots/$SNAPSHOT_DIR" "$BACKUP_DIR/tsdb-snapshot"

# Backup configurations
sudo cp -a /etc/prometheus "$BACKUP_DIR/config"
sudo cp -a /etc/systemd/system/prometheus.service "$BACKUP_DIR/"
sudo cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus-binary-2.55.1"
sudo cp /usr/local/bin/promtool "$BACKUP_DIR/promtool-binary-2.55.1"

# Document current state
echo "2.55.1" > "$BACKUP_DIR/VERSION"
curl http://localhost:9090/api/v1/status/config | jq . > "$BACKUP_DIR/runtime-config.json"
curl http://localhost:9090/api/v1/targets | jq . > "$BACKUP_DIR/targets.json"
curl http://localhost:9090/api/v1/rules | jq . > "$BACKUP_DIR/rules.json"

echo "Stage 2 backup created at: $BACKUP_DIR"
```

#### 2. Configuration Analysis

```bash
# Analyze current configuration for breaking changes
promtool check config /etc/prometheus/prometheus.yml --new-config-format 2>&1 | tee /tmp/config-check-v3.txt

# Review systemd service file for deprecated flags
grep -E "allow-overlapping-blocks|wal-compression|web.enable-admin-api" /etc/systemd/system/prometheus.service

# Check alert rules for deprecated syntax
promtool check rules /etc/prometheus/rules/*.yml --new-eval-format 2>&1 | tee /tmp/rules-check-v3.txt
```

### Stage 2 Configuration Updates

#### Update 1: Prometheus Configuration File

**File**: `/etc/prometheus/prometheus.yml`

**Changes Required**:

```yaml
# Add native histogram configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'observability-stack'

  # NEW: Native histogram configuration
  scrape_protocols:
    - PrometheusProto    # Default protocol
    - OpenMetricsText1.0.0
    - OpenMetricsText0.0.1
    - PrometheusText0.0.4

# Update scrape configs if needed
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'observability-vps'

    # OPTIONAL: Disable native histograms for specific jobs if needed
    # native_histogram_bucket_limit: 0  # Disable native histograms
    # native_histogram_min_bucket_factor: 1.0
```

**Preparation Script**:

```bash
# Create updated configuration
sudo cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.pre-v3
sudo nano /etc/prometheus/prometheus.yml

# Add the global scrape_protocols section shown above
# Review each scrape_config for compatibility

# Validate new configuration with Prometheus 3.x promtool
# (We'll download the 3.8.1 binary first)
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v3.8.1/prometheus-3.8.1.linux-amd64.tar.gz
tar -xzf prometheus-3.8.1.linux-amd64.tar.gz
cd prometheus-3.8.1.linux-amd64

# Test new config
./promtool check config /etc/prometheus/prometheus.yml
# Expected: SUCCESS
```

#### Update 2: Systemd Service File

**File**: `/etc/systemd/system/prometheus.service`

**Current Service File** (assumed):

```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --storage.tsdb.retention.time=15d \
  --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
```

**Updated Service File for 3.8.1**:

```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --storage.tsdb.retention.time=15d \
  --web.enable-lifecycle \
  --enable-feature=exemplar-storage \
  --enable-feature=native-histograms

# REMOVED deprecated flags:
# --storage.tsdb.allow-overlapping-blocks (always allowed in v3)
# --storage.tsdb.wal-compression (always enabled in v3)

Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**Key Changes**:
- Removed deprecated `--storage.tsdb.allow-overlapping-blocks`
- Removed deprecated `--storage.tsdb.wal-compression`
- Added `--enable-feature=native-histograms` (optional, but recommended)
- Added `--enable-feature=exemplar-storage` (for tracing integration)
- Added `Restart` directives for resilience

**Preparation Script**:

```bash
# Backup current service file
sudo cp /etc/systemd/system/prometheus.service /etc/systemd/system/prometheus.service.pre-v3

# Edit service file
sudo nano /etc/systemd/system/prometheus.service

# Apply changes shown above

# Validate systemd syntax
systemd-analyze verify prometheus.service
# Expected: No errors

# Don't reload yet - will do during upgrade
```

#### Update 3: Alert Rules (PromQL Syntax)

**Most alert rules will work without changes**, but validate:

```bash
# Use Prometheus 3.8.1 promtool to check rules
cd /tmp/prometheus-3.8.1.linux-amd64
./promtool check rules /etc/prometheus/rules/*.yml
# Expected: SUCCESS

# If errors, review and fix:
# - histogram_quantile() may need adjustments
# - timestamp() behavior changed slightly
# - Check for deprecated functions
```

**Common Issues**:

1. **Native Histogram Queries**:
   ```promql
   # Old: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
   # New: Same syntax, but now supports native histograms automatically
   ```

2. **Timestamp Function**:
   ```promql
   # Behavior unchanged for most use cases
   # But now more precise with native histograms
   ```

**No changes expected for standard alert rules**, but test thoroughly.

### Stage 2 Execution Steps

#### Step 1: Download Prometheus 3.8.1

```bash
# Already downloaded for testing, now verify
cd /tmp/prometheus-3.8.1.linux-amd64

# Verify checksum
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v3.8.1/sha256sums.txt
sha256sum -c sha256sums.txt 2>&1 | grep "prometheus-3.8.1.linux-amd64.tar.gz"
# Expected: OK
```

#### Step 2: Final Pre-Upgrade Validation

```bash
# Validate new configuration
cd /tmp/prometheus-3.8.1.linux-amd64
./promtool check config /etc/prometheus/prometheus.yml
# Expected: SUCCESS

# Validate alert rules
./promtool check rules /etc/prometheus/rules/*.yml
# Expected: SUCCESS

# Test startup with dry-run
./prometheus --config.file=/etc/prometheus/prometheus.yml --dry-run 2>&1 | grep -i error
# Expected: No errors
```

#### Step 3: Stop Prometheus 2.55.1

```bash
# Stop service
sudo systemctl stop prometheus

# Verify stopped
sudo systemctl status prometheus
# Expected: inactive (dead)

# Record downtime start
echo "Stage 2 downtime started at: $(date)" | tee -a /tmp/prometheus-upgrade-stage2.log
```

#### Step 4: Install Prometheus 3.8.1

```bash
# Backup 2.55.1 binaries
sudo cp /usr/local/bin/prometheus /usr/local/bin/prometheus-2.55.1.backup
sudo cp /usr/local/bin/promtool /usr/local/bin/promtool-2.55.1.backup

# Install 3.8.1 binaries
cd /tmp/prometheus-3.8.1.linux-amd64
sudo cp prometheus promtool /usr/local/bin/
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify installation
prometheus --version
# Expected: prometheus, version 3.8.1
```

#### Step 5: Update Configuration Files

```bash
# Configuration already updated in Pre-Stage 2 Requirements
# Verify files are in place
sudo promtool check config /etc/prometheus/prometheus.yml
# Expected: SUCCESS
```

#### Step 6: Reload Systemd and Start Prometheus 3.8.1

```bash
# Reload systemd to pick up service file changes
sudo systemctl daemon-reload

# Start Prometheus 3.8.1
sudo systemctl start prometheus

# Monitor startup logs CLOSELY
sudo journalctl -u prometheus -f
```

**Expected Log Output**:

```
level=info msg="Starting Prometheus Server" version="(version=3.8.1...)"
level=info msg="TSDB migration started" from_version=2 to_version=3
level=info msg="Replaying WAL"
level=info msg="WAL replay completed"
level=info msg="TSDB migration: converting blocks to v3 format" total=X converted=Y
level=info msg="Compacting v3 blocks"
level=info msg="TSDB migration completed successfully" duration=15m12s
level=info msg="TSDB opened" duration=16m05s
level=info msg="Loading configuration file" filename=/etc/prometheus/prometheus.yml
level=info msg="Completed loading of configuration file"
level=info msg="Server is ready to receive web requests"
```

**CRITICAL: TSDB v2 → v3 migration will take 15-20 minutes. Do not interrupt.**

#### Step 7: Health Validation

```bash
# Wait for migration to complete
# Monitor logs until you see "Server is ready to receive web requests"

# Check service status
sudo systemctl status prometheus
# Expected: active (running)

# Check health
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

# Check readiness
curl -s http://localhost:9090/-/ready
# Expected: Prometheus is Ready.

# Verify version
curl -s http://localhost:9090/api/v1/status/buildinfo | jq .
# Expected: version "3.8.1"
```

#### Step 8: Validate Scrape Targets

```bash
# Wait for first scrape cycle (15-30 seconds)
sleep 30

# Check all targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {instance: .labels.instance, health: .health, lastScrape: .lastScrape}'

# Count healthy targets
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health == "up")] | length'
# Expected: Total number of your targets

# Check for scrape errors
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | {instance: .labels.instance, error: .lastError}'
# Expected: Empty (no unhealthy targets)
```

#### Step 9: Validate Alert Rules

```bash
# Check rule groups loaded
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].name'
# Expected: All your alert groups listed

# Verify rule evaluation
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type == "alerting") | {alert: .name, state: .state, health: .health}'
# Expected: All rules showing "health": "ok"

# Check for evaluation errors
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.health != "ok")'
# Expected: Empty (no unhealthy rules)

# Review logs for rule errors
sudo journalctl -u prometheus -n 200 --no-pager | grep -i "rule evaluation"
# Expected: No errors
```

#### Step 10: Validate Data Continuity

```bash
# Query recent data
curl -s 'http://localhost:9090/api/v1/query?query=up&time='$(date +%s) | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'
# Expected: All instances with value "1"

# Query historical data (verify old data accessible)
curl -s 'http://localhost:9090/api/v1/query?query=up&time='$(($(date +%s) - 86400)) | jq '.status'
# Expected: "success"

# Test range query across upgrade time
UPGRADE_TIME=$(($(date +%s) - 1800))  # 30 minutes ago
curl -s 'http://localhost:9090/api/v1/query_range?query=up{instance="observability-vps"}&start='$((UPGRADE_TIME - 3600))'&end='$((UPGRADE_TIME + 3600))'&step=60s' | jq '.status'
# Expected: "success"

# Check for data gaps
curl -s 'http://localhost:9090/api/v1/query_range?query=up&start='$(($(date +%s) - 3600))'&end='$(date +%s)'&step=15s' | jq '.data.result[0].values | length'
# Expected: ~240 data points (3600 / 15)
```

#### Step 11: Test Native Histograms

```bash
# Check if native histograms are enabled
curl -s http://localhost:9090/api/v1/status/flags | jq '.data | ."enable-feature"'
# Expected: Should include "native-histograms"

# Query for native histogram metrics (if any exporters provide them)
curl -s 'http://localhost:9090/api/v1/query?query={__name__=~".*_bucket"}' | jq '.data.result | length'
# Expected: Count of histogram metrics

# Native histograms may not be used yet (requires exporter support)
# This is OK - the feature is enabled and ready
```

#### Step 12: Grafana Dashboard Validation

```bash
# Access Grafana at http://your-domain:3000
# Test Prometheus datasource:
# 1. Configuration → Data Sources → Prometheus
# 2. Click "Test" button
# Expected: "Data source is working"

# Verify each dashboard:
# 1. Overview Dashboard
#    - All hosts visible
#    - Metrics loading
#    - No errors
# 2. Node Exporter Dashboard
#    - CPU, memory, disk panels populated
#    - No "No data" errors
# 3. Service Dashboards (Nginx, MySQL, etc.)
#    - Metrics visible
#    - Queries executing
# 4. Logs Explorer
#    - Loki still working (unchanged)
```

**Dashboard Compatibility Notes**:

- Most dashboards should work without changes
- If a panel shows errors, check query syntax
- Native histogram queries may need dashboard updates
- Recording rules should continue working

#### Step 13: Performance Validation

```bash
# Test query performance
time curl -s 'http://localhost:9090/api/v1/query_range?query=rate(node_cpu_seconds_total[5m])&start='$(($(date +%s) - 3600))'&end='$(date +%s)'&step=15s' > /dev/null
# Expected: Similar or better than 2.55.1 performance

# Check TSDB size
sudo du -sh /var/lib/prometheus
# Expected: May be slightly larger due to native histogram support

# Monitor memory usage
free -h
ps aux | grep prometheus | grep -v grep
# Expected: Prometheus using reasonable memory (~2-4 GB for typical setup)
```

#### Step 14: Final Validation

```bash
# Check for errors in logs
sudo journalctl -u prometheus -n 500 --no-pager | grep -i error
# Expected: No critical errors

# Verify TSDB status
curl -s http://localhost:9090/api/v1/status/tsdb | jq .
# Review: No warnings

# Check runtime info
curl -s http://localhost:9090/api/v1/status/runtimeinfo | jq .
# Verify: Correct version, reasonable uptime

# Final health check
curl -s http://localhost:9090/-/healthy && echo "UPGRADE SUCCESSFUL" || echo "UPGRADE FAILED"
```

### Stage 2 Post-Upgrade Monitoring

**Monitor for 24-48 hours after Stage 2:**

1. **Immediate (0-2 hours)**:
   ```bash
   # Every 15 minutes
   curl -s http://localhost:9090/-/healthy
   sudo journalctl -u prometheus --since "15 minutes ago" | grep -i error
   ```

2. **Short-term (2-24 hours)**:
   ```bash
   # Every 2 hours
   curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | select(.health != "up")] | length'
   # Expected: 0

   sudo du -sh /var/lib/prometheus
   # Monitor disk usage growth
   ```

3. **Medium-term (24-48 hours)**:
   - Review Grafana dashboards daily
   - Check alert rule firing patterns
   - Verify TSDB compaction succeeds
   - Monitor query performance

---

## Risk Assessment

### Risk Matrix

| Risk Category | Likelihood | Impact | Mitigation |
|---------------|-----------|---------|------------|
| TSDB corruption during Stage 1 migration | Low | Critical | Full backup before Stage 1, TSDB snapshot |
| Configuration incompatibility in Stage 2 | Medium | High | Pre-validation with 3.x promtool, dry-run testing |
| Data loss during upgrade | Very Low | Critical | Snapshot-based backup, WAL replay |
| Alert rule failures | Low | Medium | Pre-validation, syntax checking |
| Grafana dashboard breakage | Low | Low | Dashboard export before upgrade |
| Query performance degradation | Low | Medium | Performance testing, monitoring |
| Cannot rollback after Stage 1 | Medium | High | Extended validation period between stages |

### Risk Mitigation Strategies

#### 1. Backup Strategy

**Multi-layer backup approach:**

- **TSDB Snapshot**: Official Prometheus snapshot API (preferred)
- **File-level backup**: Copy entire `/var/lib/prometheus`
- **Configuration backup**: All config files, service definitions
- **Binary backup**: Keep old Prometheus binaries

**Backup verification:**

```bash
# Verify snapshot integrity
ls -lh /var/lib/prometheus/snapshots/
# Should contain recent snapshot

# Verify configuration backup
ls -lh /var/backups/prometheus-upgrade-*/config/
# Should contain prometheus.yml, rules/*.yml

# Test restore procedure (before upgrade)
# See [Rollback Procedures](#rollback-procedures)
```

#### 2. Validation Testing

**Pre-upgrade validation:**

- Use Prometheus 3.x promtool to check config before Stage 2
- Test queries against 2.55.1 that will be used in 3.x
- Export Grafana dashboards for backup
- Document all alert rules and their current state

**Post-upgrade validation:**

- Comprehensive health checks after each stage
- Data continuity verification
- Performance benchmarking
- Alert rule validation

#### 3. Staged Rollout

**Mandatory waiting period between stages:**

- Minimum 1 week (recommended: 2 weeks)
- Daily health checks during waiting period
- Weekly validation of metrics and alerts
- Monitor for any TSDB issues

#### 4. Monitoring During Upgrade

**Active monitoring:**

```bash
# Real-time log monitoring
sudo journalctl -u prometheus -f

# Separate terminal for health checks
watch -n 5 'curl -s http://localhost:9090/-/healthy'

# Monitor disk I/O during migration
iostat -x 5
```

#### 5. Communication Plan

**Before upgrade:**

- Notify team of planned downtime
- Schedule upgrade during low-traffic period
- Prepare rollback plan
- Document current state

**During upgrade:**

- Keep team informed of progress
- Report any unexpected issues immediately
- Document all steps taken

**After upgrade:**

- Confirm successful completion
- Monitor for 24-48 hours
- Report any anomalies

---

## Complete Execution Plan

### Timeline Overview

```
Week 0: Preparation Phase
├─ Day 1-2: Review documentation, plan execution
├─ Day 3-4: Create backups, validate prerequisites
├─ Day 5: Stage 1 execution
└─ Day 6-7: Initial validation

Week 1-2: Stability Monitoring (Stage 1)
├─ Daily: Health checks, target validation
├─ Weekly: Dashboard review, alert validation
└─ End of Week 2: Stage 1 validation complete

Week 3: Stage 2 Preparation
├─ Day 1-2: Review breaking changes, update configs
├─ Day 3-4: Create Stage 2 backups, pre-validation
├─ Day 5: Stage 2 execution
└─ Day 6-7: Intensive monitoring

Week 4+: Ongoing Monitoring
└─ Continue monitoring for regressions
```

### Pre-Execution Checklist

**One week before Stage 1:**

- [ ] Read complete upgrade documentation
- [ ] Review Prometheus changelog for 2.55.1
- [ ] Identify backup storage location (15+ GB free)
- [ ] Schedule downtime window (off-peak hours)
- [ ] Notify team of upgrade plan
- [ ] Verify disk space: `df -h /var/lib/prometheus`
- [ ] Document current configuration state
- [ ] Export Grafana dashboards as backup

**One day before Stage 1:**

- [ ] Verify all prerequisites met
- [ ] Confirm backup storage available
- [ ] Test backup procedure
- [ ] Review rollback plan
- [ ] Ensure on-call engineer available
- [ ] Prepare monitoring terminals

**One hour before Stage 1:**

- [ ] Final health check: All targets up
- [ ] Create TSDB snapshot
- [ ] Backup configuration files
- [ ] Download Prometheus 2.55.1 binary
- [ ] Verify checksum
- [ ] Open log monitoring terminal

### Stage 1 Execution Checklist

- [ ] Stop Prometheus 2.48.1
- [ ] Verify stopped: `systemctl status prometheus`
- [ ] Install Prometheus 2.55.1 binary
- [ ] Verify version: `prometheus --version`
- [ ] Start Prometheus 2.55.1
- [ ] Monitor TSDB migration in logs (10-15 min)
- [ ] Wait for "Server is ready" message
- [ ] Verify health: `curl http://localhost:9090/-/healthy`
- [ ] Verify targets: All showing "up"
- [ ] Verify alerts: Rules loaded and evaluating
- [ ] Test Grafana dashboards
- [ ] Check for errors in logs
- [ ] Document completion time
- [ ] Begin 1-2 week monitoring period

### Between-Stage Monitoring Checklist

**Daily (for 1-2 weeks):**

- [ ] Quick health check: `curl http://localhost:9090/-/healthy`
- [ ] Check targets: All up
- [ ] Review logs for errors
- [ ] Verify TSDB compaction success
- [ ] Monitor disk usage

**Weekly:**

- [ ] Review all Grafana dashboards
- [ ] Validate alert rule history
- [ ] Test complex queries
- [ ] Check TSDB size growth
- [ ] Verify no data gaps

**Stage 1 Sign-off** (after 1-2 weeks):

- [ ] All daily checks passed
- [ ] No TSDB errors
- [ ] All targets stable
- [ ] Grafana dashboards working
- [ ] No performance issues
- [ ] Team sign-off obtained
- [ ] Ready for Stage 2

### Pre-Stage 2 Checklist

**One week before Stage 2:**

- [ ] Review Prometheus 3.x changelog
- [ ] Identify breaking changes
- [ ] Update configuration files (prometheus.yml, service file)
- [ ] Validate new config with 3.x promtool
- [ ] Test alert rules with 3.x promtool
- [ ] Schedule Stage 2 downtime
- [ ] Notify team

**One day before Stage 2:**

- [ ] Create Stage 2 backup
- [ ] Download Prometheus 3.8.1 binary
- [ ] Verify checksum
- [ ] Pre-validate configuration
- [ ] Review rollback plan
- [ ] Prepare updated service file

**One hour before Stage 2:**

- [ ] Final health check
- [ ] Create TSDB snapshot
- [ ] Verify backup integrity
- [ ] Open monitoring terminals
- [ ] Final team notification

### Stage 2 Execution Checklist

- [ ] Stop Prometheus 2.55.1
- [ ] Verify stopped: `systemctl status prometheus`
- [ ] Install Prometheus 3.8.1 binary
- [ ] Verify version: `prometheus --version`
- [ ] Update service file: `systemctl daemon-reload`
- [ ] Start Prometheus 3.8.1
- [ ] Monitor TSDB v2 → v3 migration (15-20 min)
- [ ] Wait for "Server is ready" message
- [ ] Verify health: `curl http://localhost:9090/-/healthy`
- [ ] Verify version: Check build info API
- [ ] Verify targets: All showing "up"
- [ ] Verify alerts: Rules loaded and evaluating
- [ ] Test native histogram features
- [ ] Test Grafana dashboards (all dashboards)
- [ ] Validate data continuity (before/after upgrade)
- [ ] Check query performance
- [ ] Review logs for errors
- [ ] Document completion
- [ ] Begin 24-48 hour intensive monitoring

### Post-Stage 2 Monitoring Checklist

**0-2 hours (every 15 minutes):**

- [ ] Health check
- [ ] Target health
- [ ] Log review
- [ ] Disk usage

**2-24 hours (every 2 hours):**

- [ ] Full health check
- [ ] Target validation
- [ ] Alert rule status
- [ ] Grafana dashboard spot-check
- [ ] TSDB compaction status

**24-48 hours (twice daily):**

- [ ] Comprehensive dashboard review
- [ ] Query performance validation
- [ ] Alert firing patterns
- [ ] Disk usage trends
- [ ] Error log review

**Sign-off** (after 48 hours):

- [ ] All monitoring checks passed
- [ ] No regressions detected
- [ ] Team sign-off obtained
- [ ] Upgrade complete

---

## Breaking Changes Reference

### Comprehensive Breaking Changes List

#### 1. Native Histograms

**Change**: Native histogram support enabled by default in Prometheus 3.x.

**Impact**:
- Histogram metrics can be collected in native format
- More efficient storage for high-resolution histograms
- Query behavior may change for histogram_quantile()

**Configuration**:

```yaml
# Global configuration to control native histograms
global:
  # Optional: Limit native histogram buckets
  native_histogram_bucket_limit: 160  # Default

  # Optional: Minimum bucket width factor
  native_histogram_min_bucket_factor: 1.0  # Default

# Per-job configuration
scrape_configs:
  - job_name: 'my-service'
    # Disable native histograms for this job
    native_histogram_bucket_limit: 0
```

**Migration Path**:
- Existing histogram metrics continue to work
- New exporters may provide native histograms
- Update queries only if using native histogram features

#### 2. Scrape Configuration Changes

**Change**: Scrape behavior and defaults updated.

**Impact**:

| Parameter | Prometheus 2.x | Prometheus 3.x | Action Required |
|-----------|---------------|---------------|-----------------|
| `honor_timestamps` | `false` | `true` | Review if overriding timestamps |
| `scrape_timeout` | Lax validation | Strict validation | Ensure timeout < interval |
| `scrape_protocols` | Implicit | Explicit | Configure protocols if needed |

**Configuration**:

```yaml
scrape_configs:
  - job_name: 'example'
    scrape_interval: 15s
    scrape_timeout: 10s  # Must be < scrape_interval

    # NEW: Explicit protocol configuration
    scrape_protocols:
      - PrometheusProto
      - OpenMetricsText1.0.0
      - OpenMetricsText0.0.1
      - PrometheusText0.0.4

    # honor_timestamps now defaults to true
    honor_timestamps: true
```

**Validation**:

```bash
# Check for scrape_timeout >= scrape_interval
promtool check config /etc/prometheus/prometheus.yml
```

#### 3. Removed Feature Flags

**Removed Flags**:

| Flag | Prometheus 2.x | Prometheus 3.x | Action |
|------|---------------|---------------|---------|
| `--storage.tsdb.allow-overlapping-blocks` | Optional | Always allowed | Remove from service file |
| `--storage.tsdb.wal-compression` | Optional | Always enabled | Remove from service file |
| `--web.enable-admin-api` | Enables admin API | Deprecated | Use `--web.enable-lifecycle` |

**Service File Update**:

```ini
# BEFORE (Prometheus 2.x)
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.allow-overlapping-blocks \
  --storage.tsdb.wal-compression \
  --web.enable-admin-api

# AFTER (Prometheus 3.x)
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.enable-lifecycle
```

#### 4. PromQL Function Changes

**Updated Functions**:

| Function | Change | Impact |
|----------|--------|--------|
| `histogram_quantile()` | Native histogram support | Improved accuracy for native histograms |
| `histogram_sum()` | New function | Sum of native histogram |
| `histogram_count()` | New function | Count of native histogram observations |
| `histogram_fraction()` | New function | Fraction of observations in range |
| `timestamp()` | Behavior refined | More precise with native histograms |

**Example Queries**:

```promql
# Traditional histogram quantile (still works)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Native histogram quantile (automatic if metric is native)
histogram_quantile(0.95, rate(http_request_duration_seconds[5m]))

# New native histogram functions
histogram_sum(rate(http_request_duration_seconds[5m]))
histogram_count(rate(http_request_duration_seconds[5m]))
histogram_fraction(0.0, 1.0, rate(http_request_duration_seconds[5m]))
```

**Migration**:
- Existing queries continue to work
- No changes required unless using new native histogram features
- Test complex recording rules after upgrade

#### 5. Remote Write Protocol

**Change**: Remote write protocol upgraded to v2.0.

**Impact**:
- Remote write endpoints must support protocol v2.0
- New metadata handling
- Improved performance and compression

**Configuration**:

```yaml
remote_write:
  - url: "https://remote-storage.example.com/api/v1/push"
    # NEW: Protocol version (auto-negotiated)
    protocol_version: 2  # Default for Prometheus 3.x

    # Backward compatibility (if remote endpoint doesn't support v2)
    protocol_version: 1
```

**Validation**:

If using remote write:

1. Verify remote endpoint supports protocol v2.0
2. Check remote write logs after upgrade
3. Monitor remote write lag metrics

**For this observability stack**: No remote write configured, no action needed.

#### 6. API Changes

**Updated Endpoints**:

| Endpoint | Change | Impact |
|----------|--------|--------|
| `/api/v1/status/buildinfo` | New fields | Additional version info |
| `/api/v1/metadata` | Updated response | More detailed metadata |
| `/api/v1/targets/metadata` | New endpoint | Per-target metadata |

**Compatibility**: Grafana and Alertmanager compatible with new API.

#### 7. TSDB Changes

**Storage Improvements**:

- **TSDB format v3**: More efficient block structure
- **Improved compression**: Better disk usage
- **Faster compaction**: Reduced I/O during compaction

**Monitoring**:

```bash
# Check TSDB status
curl -s http://localhost:9090/api/v1/status/tsdb | jq .

# Monitor compaction
sudo journalctl -u prometheus | grep compaction
```

---

## Rollback Procedures

### Critical Warning

**After Stage 1 completes (2.55.1 running with TSDB v2):**
- **Cannot downgrade** to Prometheus 2.48.1 or earlier
- TSDB v2 format is **not readable** by Prometheus < 2.55.1
- Only rollback option: **Restore from backup**

**After Stage 2 completes (3.8.1 running with TSDB v3):**
- Can rollback to Prometheus 2.55.1 if needed
- Cannot rollback to Prometheus < 2.55.1

### Rollback Decision Tree

```
Problem Detected After Upgrade
├─ Is Prometheus completely down?
│  ├─ Yes → Immediate rollback required
│  └─ No → Continue to next check
│
├─ Are critical targets not being scraped?
│  ├─ Yes → Investigate, consider rollback if unfixable
│  └─ No → Continue to next check
│
├─ Are alert rules failing to evaluate?
│  ├─ Yes → Check if fixable, consider rollback
│  └─ No → Continue to next check
│
├─ Is there data loss or corruption?
│  ├─ Yes → Immediate rollback required
│  └─ No → Monitor and fix issues
│
└─ Minor issues (dashboards, performance)?
   └─ Fix forward, no rollback needed
```

### Rollback Procedure: Stage 1 (2.55.1 → 2.48.1)

**CRITICAL**: This rollback is **destructive** and results in data loss.

**When to use**: Only if Stage 1 completely fails (Prometheus won't start, critical corruption).

**Steps**:

```bash
# 1. Stop failed Prometheus 2.55.1
sudo systemctl stop prometheus

# 2. Identify backup directory
BACKUP_DIR="/var/backups/prometheus-upgrade-stage1/backup-YYYYMMDD-HHMMSS"
ls -lt /var/backups/prometheus-upgrade-stage1/
# Use the most recent backup

# 3. Restore Prometheus 2.48.1 binary
sudo cp "$BACKUP_DIR/prometheus-binary-2.48.1" /usr/local/bin/prometheus
sudo cp "$BACKUP_DIR/promtool-binary-2.48.1" /usr/local/bin/promtool
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify version
prometheus --version
# Expected: prometheus, version 2.48.1

# 4. Restore TSDB from snapshot
sudo systemctl stop prometheus  # Ensure stopped
sudo rm -rf /var/lib/prometheus/*
sudo cp -a "$BACKUP_DIR/tsdb-snapshot/"* /var/lib/prometheus/
sudo chown -R prometheus:prometheus /var/lib/prometheus

# 5. Restore configuration
sudo cp -a "$BACKUP_DIR/config/"* /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus

# 6. Restore service file
sudo cp "$BACKUP_DIR/prometheus.service" /etc/systemd/system/
sudo systemctl daemon-reload

# 7. Start Prometheus 2.48.1
sudo systemctl start prometheus

# 8. Monitor startup
sudo journalctl -u prometheus -f

# 9. Validate
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

**Data Loss**:
- All data collected between backup and rollback is **lost**
- Queries for that time period will return no data

### Rollback Procedure: Stage 2 (3.8.1 → 2.55.1)

**When to use**: If Stage 2 fails or critical issues detected with Prometheus 3.x.

**Advantage**: Can rollback to 2.55.1 which can read TSDB v2 format.

**Steps**:

```bash
# 1. Stop Prometheus 3.8.1
sudo systemctl stop prometheus

# 2. Identify Stage 2 backup
BACKUP_DIR="/var/backups/prometheus-upgrade-stage2/backup-YYYYMMDD-HHMMSS"
ls -lt /var/backups/prometheus-upgrade-stage2/

# 3. Restore Prometheus 2.55.1 binary
sudo cp "$BACKUP_DIR/prometheus-binary-2.55.1" /usr/local/bin/prometheus
sudo cp "$BACKUP_DIR/promtool-binary-2.55.1" /usr/local/bin/promtool
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify version
prometheus --version
# Expected: prometheus, version 2.55.1

# 4. Restore configuration (revert v3 changes)
sudo cp -a "$BACKUP_DIR/config/"* /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus

# 5. Restore service file (remove v3 flags)
sudo cp "$BACKUP_DIR/prometheus.service" /etc/systemd/system/
sudo systemctl daemon-reload

# 6. Restore TSDB if needed (only if corruption occurred)
# Note: If TSDB v3 migration completed, 2.55.1 may not read it
# In that case, restore from snapshot
if [ -d "$BACKUP_DIR/tsdb-snapshot" ]; then
    sudo systemctl stop prometheus
    sudo rm -rf /var/lib/prometheus/*
    sudo cp -a "$BACKUP_DIR/tsdb-snapshot/"* /var/lib/prometheus/
    sudo chown -R prometheus:prometheus /var/lib/prometheus
fi

# 7. Start Prometheus 2.55.1
sudo systemctl start prometheus

# 8. Monitor startup
sudo journalctl -u prometheus -f

# 9. Validate
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq .status
```

**Data Loss**:
- If restoring from TSDB snapshot: Data between Stage 2 start and rollback is **lost**
- If TSDB intact: No data loss, but TSDB v3 may not be readable by 2.55.1

### Partial Rollback: Configuration Only

**When to use**: Prometheus 3.8.1 runs but configuration issues detected.

**Advantage**: No downtime, no data loss.

**Steps**:

```bash
# 1. Identify problematic configuration
sudo promtool check config /etc/prometheus/prometheus.yml

# 2. Restore previous configuration
BACKUP_DIR="/var/backups/prometheus-upgrade-stage2/backup-YYYYMMDD-HHMMSS"
sudo cp "$BACKUP_DIR/config/prometheus.yml" /etc/prometheus/prometheus.yml

# 3. Reload configuration (no restart needed)
curl -X POST http://localhost:9090/-/reload

# 4. Verify
sudo journalctl -u prometheus -n 50 --no-pager | grep -i "reload"
curl -s http://localhost:9090/api/v1/status/config | jq .
```

### Emergency Rollback: Complete Stack Failure

**When to use**: Prometheus completely unrecoverable, need immediate restore.

**Steps**:

```bash
# 1. Stop all services
sudo systemctl stop prometheus alertmanager grafana-server

# 2. Restore from most recent working backup
# Use Stage 1 backup if Stage 2 failed
# Use Stage 2 backup if only config issue
BACKUP_DIR="/var/backups/prometheus-upgrade-stageN/backup-YYYYMMDD-HHMMSS"

# 3. Full restore
sudo rm -rf /var/lib/prometheus/*
sudo rm -rf /etc/prometheus/*
sudo cp -a "$BACKUP_DIR/tsdb-snapshot/"* /var/lib/prometheus/
sudo cp -a "$BACKUP_DIR/config/"* /etc/prometheus/
sudo cp "$BACKUP_DIR/prometheus-binary-"* /usr/local/bin/prometheus
sudo cp "$BACKUP_DIR/promtool-binary-"* /usr/local/bin/promtool
sudo cp "$BACKUP_DIR/prometheus.service" /etc/systemd/system/

# 4. Fix permissions
sudo chown -R prometheus:prometheus /var/lib/prometheus /etc/prometheus
sudo chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
sudo chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# 5. Restart
sudo systemctl daemon-reload
sudo systemctl start prometheus alertmanager grafana-server

# 6. Validate
curl -s http://localhost:9090/-/healthy
```

---

## Validation Checklists

### Stage 1 Validation Checklist

**Immediate Post-Upgrade (0-2 hours):**

- [ ] Prometheus service running: `systemctl status prometheus`
- [ ] Version verified: `prometheus --version` shows 2.55.1
- [ ] Health endpoint: `curl http://localhost:9090/-/healthy` returns "Healthy"
- [ ] Readiness endpoint: `curl http://localhost:9090/-/ready` returns "Ready"
- [ ] TSDB migration completed: Check logs for "TSDB migration completed successfully"
- [ ] No errors in logs: `journalctl -u prometheus -n 200 | grep -i error`
- [ ] All targets scraped: `curl http://localhost:9090/api/v1/targets` shows all "up"
- [ ] Alert rules loaded: `curl http://localhost:9090/api/v1/rules` returns rules
- [ ] Grafana datasource working: Test connection in Grafana UI
- [ ] Dashboards displaying data: Spot-check main dashboards

**Daily (for 1-2 weeks):**

- [ ] Health check: `curl http://localhost:9090/-/healthy`
- [ ] Targets healthy: No down targets in `/api/v1/targets`
- [ ] No critical errors: `journalctl -u prometheus --since "1 day ago" | grep -Ei "error|fatal"`
- [ ] TSDB compaction successful: Check logs for compaction
- [ ] Disk usage stable: `df -h /var/lib/prometheus`
- [ ] Memory usage normal: `ps aux | grep prometheus`
- [ ] Query performance acceptable: Test sample queries

**Weekly:**

- [ ] All Grafana dashboards reviewed: No data gaps
- [ ] Alert rules firing correctly: Review Alertmanager
- [ ] Recording rules evaluated: Check for evaluation errors
- [ ] Long-range queries working: Test queries over retention period
- [ ] TSDB size growth normal: Compare to pre-upgrade growth rate
- [ ] No data corruption: Spot-check historical data

**Sign-off Criteria (before Stage 2):**

- [ ] All daily checks passed for 7-14 consecutive days
- [ ] All weekly checks passed
- [ ] No TSDB-related errors in logs
- [ ] All stakeholders approve proceeding to Stage 2
- [ ] Stage 2 preparation completed

### Stage 2 Validation Checklist

**Immediate Post-Upgrade (0-2 hours):**

- [ ] Prometheus service running: `systemctl status prometheus`
- [ ] Version verified: `prometheus --version` shows 3.8.1
- [ ] Build info API: `curl http://localhost:9090/api/v1/status/buildinfo | jq .data.version`
- [ ] Health endpoint: `curl http://localhost:9090/-/healthy` returns "Healthy"
- [ ] Readiness endpoint: `curl http://localhost:9090/-/ready` returns "Ready"
- [ ] TSDB v2→v3 migration completed: Check logs
- [ ] Configuration loaded: Check logs for "Completed loading of configuration file"
- [ ] No critical errors: `journalctl -u prometheus -n 200 | grep -Ei "error|fatal"`
- [ ] All targets scraped: All targets showing "up"
- [ ] Alert rules loaded and evaluating: No health errors
- [ ] Native histograms feature enabled: Check `/api/v1/status/flags`
- [ ] Grafana datasource working: Test connection
- [ ] All dashboards displaying data: Comprehensive review

**First 24 Hours (every 2 hours):**

- [ ] Health check: `curl http://localhost:9090/-/healthy`
- [ ] Targets healthy: Check `/api/v1/targets`
- [ ] Alert rules status: Check `/api/v1/rules`
- [ ] No critical errors in logs
- [ ] TSDB compaction successful
- [ ] Disk usage monitoring
- [ ] Memory usage normal
- [ ] Query performance acceptable
- [ ] Grafana dashboards working

**24-48 Hours (twice daily):**

- [ ] Comprehensive health validation
- [ ] All dashboards reviewed
- [ ] Alert firing patterns normal
- [ ] Recording rules evaluated correctly
- [ ] Query performance benchmarked
- [ ] TSDB size growth monitored
- [ ] Long-range queries tested
- [ ] Data continuity verified (pre/post upgrade)

**Sign-off Criteria (after 48 hours):**

- [ ] All validation checks passed
- [ ] No regressions detected
- [ ] Performance within acceptable range
- [ ] All features working as expected
- [ ] Stakeholder sign-off obtained
- [ ] Upgrade documentation completed

### Grafana Dashboard Validation

**Dashboard-by-Dashboard Checklist:**

1. **Overview Dashboard**:
   - [ ] All hosts visible
   - [ ] Up/down status accurate
   - [ ] Active alerts displayed
   - [ ] Recent changes panel working

2. **Node Exporter Dashboard**:
   - [ ] CPU usage panels populated
   - [ ] Memory usage showing data
   - [ ] Disk usage metrics visible
   - [ ] Network traffic graphed
   - [ ] Load average displayed
   - [ ] Filesystem metrics working

3. **Nginx Exporter Dashboard** (if enabled):
   - [ ] Active connections shown
   - [ ] Requests per second graphed
   - [ ] Error rates visible
   - [ ] Upstream metrics working

4. **MySQL Exporter Dashboard** (if enabled):
   - [ ] Connection metrics shown
   - [ ] Query performance graphed
   - [ ] InnoDB metrics visible
   - [ ] Replication status (if applicable)

5. **PHP-FPM Exporter Dashboard** (if enabled):
   - [ ] Active processes shown
   - [ ] Queue length graphed
   - [ ] Slow requests visible
   - [ ] Pool statistics working

6. **Logs Explorer** (Loki):
   - [ ] Log streaming working (Loki unchanged)
   - [ ] Filters functional
   - [ ] Log levels visible

### Alert Rule Validation

**Alert-by-Alert Checklist:**

```bash
# Get all alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type == "alerting") | {name: .name, health: .health, state: .state}'

# Check for any unhealthy rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.health != "ok")'
# Expected: Empty
```

**Key Alert Rules to Verify:**

- [ ] InstanceDown: Fires when targets down
- [ ] HighCpuLoad: Fires at 80% CPU
- [ ] CriticalCpuLoad: Fires at 95% CPU
- [ ] HighMemoryUsage: Fires at 80% memory
- [ ] CriticalMemoryUsage: Fires at 95% memory
- [ ] DiskSpaceLow: Fires at 80% disk
- [ ] DiskSpaceCritical: Fires at 90% disk
- [ ] (All other custom alert rules)

**Test Alert Delivery:**

```bash
# Send test alert to Alertmanager
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlertPostUpgrade",
      "severity": "warning",
      "instance": "test"
    },
    "annotations": {
      "summary": "Test alert after Prometheus upgrade to 3.8.1"
    }
  }]'

# Check if received in Alertmanager
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | select(.labels.alertname == "TestAlertPostUpgrade")'

# Verify email delivery (check inbox or logs)
sudo journalctl -u alertmanager -n 50 | grep -i "test"
```

### Performance Validation

**Query Performance Benchmarks:**

```bash
# Simple instant query
time curl -s 'http://localhost:9090/api/v1/query?query=up' > /dev/null
# Expected: <1 second

# Range query (1 hour)
time curl -s 'http://localhost:9090/api/v1/query_range?query=rate(node_cpu_seconds_total[5m])&start='$(($(date +%s) - 3600))'&end='$(date +%s)'&step=15s' > /dev/null
# Expected: 2-5 seconds

# Complex query with aggregation
time curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(node_network_receive_bytes_total[5m])) by (instance)' > /dev/null
# Expected: <2 seconds

# Long-range query (1 week)
time curl -s 'http://localhost:9090/api/v1/query_range?query=up&start='$(($(date +%s) - 604800))'&end='$(date +%s)'&step=3600s' > /dev/null
# Expected: 5-10 seconds
```

**Compare to Pre-Upgrade Baselines:**

- Document query times before Stage 1
- Compare after Stage 1
- Compare after Stage 2
- Acceptable variance: ±20%

### Data Continuity Validation

**Check for Data Gaps:**

```bash
# Query across upgrade time
UPGRADE_TIME=<timestamp-when-upgrade-occurred>

# Before upgrade
curl -s 'http://localhost:9090/api/v1/query?query=up{instance="observability-vps"}&time='$((UPGRADE_TIME - 300)) | jq '.data.result[0].value[1]'
# Expected: "1"

# During upgrade (expect gap)
curl -s 'http://localhost:9090/api/v1/query?query=up{instance="observability-vps"}&time='$UPGRADE_TIME | jq '.data.result'
# May be empty or "0" (expected during downtime)

# After upgrade
curl -s 'http://localhost:9090/api/v1/query?query=up{instance="observability-vps"}&time='$((UPGRADE_TIME + 300)) | jq '.data.result[0].value[1]'
# Expected: "1"

# Range query across upgrade
curl -s 'http://localhost:9090/api/v1/query_range?query=up{instance="observability-vps"}&start='$((UPGRADE_TIME - 1800))'&end='$((UPGRADE_TIME + 1800))'&step=60s' | jq '.data.result[0].values | length'
# Expected: ~60 data points (some may be missing during downtime)
```

**Verify Historical Data:**

```bash
# Oldest data point
curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total&time='$(($(date +%s) - 1296000)) | jq '.status'
# Expected: "success" (if data exists from 15 days ago)

# Newest data point
curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' | jq '.data.result | length'
# Expected: Non-zero
```

---

## Summary and Final Recommendations

### Key Takeaways

1. **Two stages are mandatory**: Direct upgrade from 2.48.1 to 3.8.1 will fail
2. **TSDB migration is automatic**: Happens on first startup of each new version
3. **One-way migration**: Cannot rollback after Stage 1 without data loss
4. **Wait between stages**: 1-2 weeks recommended for stability validation
5. **Backup is critical**: Only rollback option if upgrade fails
6. **Breaking changes in Stage 2**: Configuration updates required
7. **Comprehensive validation**: Test every component after each stage

### Risk Mitigation Summary

- **Backup**: Multi-layer backup strategy before each stage
- **Validation**: Pre-validate configurations with new promtool
- **Monitoring**: Intensive monitoring during and after upgrade
- **Staged approach**: Mandatory waiting period between stages
- **Rollback plan**: Documented and tested procedures
- **Communication**: Keep team informed throughout process

### Success Criteria Summary

**Stage 1 Success**:
- Prometheus 2.55.1 running stable for 1-2 weeks
- All targets scraped successfully
- No TSDB errors
- Grafana dashboards working

**Stage 2 Success**:
- Prometheus 3.8.1 running stable for 48 hours
- All breaking changes implemented
- Native histograms enabled
- No regressions detected

### Final Recommendations

1. **Schedule wisely**: Perform upgrades during low-traffic periods
2. **Backup thoroughly**: Create comprehensive backups before each stage
3. **Validate extensively**: Test configurations before and after upgrade
4. **Monitor actively**: Watch logs and metrics during migration
5. **Wait patiently**: Don't rush between stages
6. **Document everything**: Keep detailed notes of upgrade process
7. **Test rollback**: Understand rollback procedures before upgrade
8. **Communicate clearly**: Keep team informed of status

### Next Steps

1. Review this document thoroughly
2. Schedule Stage 1 upgrade window
3. Create comprehensive backups
4. Execute Stage 1 following checklist
5. Monitor for 1-2 weeks
6. Prepare Stage 2 configuration updates
7. Schedule Stage 2 upgrade window
8. Execute Stage 2 following checklist
9. Monitor for 48 hours
10. Sign-off and document completion

---

## Appendix: Useful Commands

### Health Check Commands

```bash
# Quick health check
curl -s http://localhost:9090/-/healthy && echo "OK" || echo "FAIL"

# Detailed status
curl -s http://localhost:9090/api/v1/status/runtimeinfo | jq .

# TSDB status
curl -s http://localhost:9090/api/v1/status/tsdb | jq .

# Build info (version)
curl -s http://localhost:9090/api/v1/status/buildinfo | jq .

# Configuration status
curl -s http://localhost:9090/api/v1/status/config | jq .

# Feature flags
curl -s http://localhost:9090/api/v1/status/flags | jq .
```

### Monitoring Commands

```bash
# Watch service status
watch -n 5 'systemctl status prometheus | head -20'

# Follow logs
sudo journalctl -u prometheus -f

# Check for errors in last hour
sudo journalctl -u prometheus --since "1 hour ago" | grep -Ei "error|fatal|panic"

# Monitor targets
watch -n 10 'curl -s http://localhost:9090/api/v1/targets | jq ".data.activeTargets[] | {instance: .labels.instance, health: .health}"'

# Monitor disk usage
watch -n 30 'df -h /var/lib/prometheus'
```

### Backup Commands

```bash
# Create TSDB snapshot
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

# List snapshots
ls -lht /var/lib/prometheus/snapshots/

# Backup configuration
sudo tar -czf prometheus-config-backup-$(date +%Y%m%d-%H%M%S).tar.gz /etc/prometheus/

# Backup binaries
sudo cp /usr/local/bin/prometheus /backup/prometheus-$(prometheus --version | awk '{print $3}')
```

### Validation Commands

```bash
# Validate config
promtool check config /etc/prometheus/prometheus.yml

# Validate rules
promtool check rules /etc/prometheus/rules/*.yml

# Test query
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq .

# Count targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# List all metrics
curl -s http://localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | head -20
```

---

**Document Version**: 1.0
**Last Updated**: 2024-12-27
**Prometheus Upgrade Path**: 2.48.1 → 2.55.1 → 3.8.1
**Author**: Observability Stack Team

**CRITICAL**: This is a high-risk upgrade. Read this document completely before starting. Follow all steps carefully. Do not skip validation steps.
