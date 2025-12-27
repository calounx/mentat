# Phase 3: Loki and Promtail Upgrade Plan

**Component Versions:**
- Loki: 2.9.3 to 3.6.3 (Major version upgrade)
- Promtail: 2.9.3 to 3.6.3 (Deprecated, EOL March 2, 2026)

**Risk Level:** MEDIUM
**Estimated Downtime:** 5-10 minutes
**Rollback Complexity:** Medium (data restoration required)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Breaking Changes Analysis](#breaking-changes-analysis)
3. [Upgrade Sequence Strategy](#upgrade-sequence-strategy)
4. [Promtail Deprecation Planning](#promtail-deprecation-planning)
5. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
6. [Execution Plan](#execution-plan)
7. [Rollback Procedure](#rollback-procedure)
8. [Data Integrity Validation](#data-integrity-validation)
9. [Grafana Integration](#grafana-integration)
10. [Troubleshooting](#troubleshooting)

---

## Executive Summary

This document outlines the upgrade strategy for the Loki logging stack from version 2.9.3 to 3.6.3. This is a **major version upgrade** with significant breaking changes requiring configuration migration.

**Critical Decisions:**
- Upgrade Loki FIRST, then Promtail (backward compatibility maintained)
- Use schema v13 with TSDB indexing (already configured)
- Install Loki Operational UI Grafana plugin for UI access
- Plan Promtail to Grafana Alloy migration for Q3-Q4 2025
- Upgrade Promtail to 3.6.3 despite deprecation (security fixes until EOL)

**Coordination Requirements:**
- Multiple monitored hosts running Promtail must be upgraded sequentially
- Brief log ingestion interruption expected (5-10 minutes)
- Grafana data source remains functional during upgrade

---

## Breaking Changes Analysis

### Loki 3.x Breaking Changes

#### 1. Loki Operational UI Removed (v3.6)

**Change:** Loki's built-in web UI has been moved to a Grafana plugin.

**Impact:**
- Direct access to `http://localhost:3100` no longer provides UI
- All UI functionality now accessed via Grafana plugin
- APIs remain unchanged (backward compatible)

**Migration Required:**
- Install `grafana-lokioperational-app` plugin in Grafana
- No configuration changes needed for headless operation

**Reference:** [Loki v3.6 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-6/)

#### 2. Schema Configuration (v3.0)

**Change:** Loki 3.0 defaults to schema v13 with TSDB indexing.

**Current Configuration Analysis:**
```yaml
# /home/calounx/repositories/mentat/observability-stack/loki/loki-config.yaml
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb          # ✓ Already using TSDB
      object_store: filesystem
      schema: v13          # ✓ Already using v13
      index:
        prefix: index_
        period: 24h
```

**Status:** NO MIGRATION REQUIRED - Already using recommended schema v13 with TSDB.

**Reference:** [Loki Storage Schema](https://grafana.com/docs/loki/latest/operations/storage/schema/)

#### 3. Structured Metadata (v3.0)

**Change:** Structured Metadata enabled by default (requires TSDB + v13 schema).

**Impact:**
- Supports OTLP native endpoint
- Allows key-value pairs attached to log lines
- Increases index size if heavily used

**Current Status:** Automatically enabled (schema v13 + TSDB already configured).

**No Action Required** unless you want to disable it:
```yaml
limits_config:
  allow_structured_metadata: false  # Optional: Disable if not needed
```

#### 4. Storage Client Changes (v3.4)

**Change:** New object storage clients based on Thanos (opt-in in 3.4, default in future).

**Current Configuration:** Using `filesystem` storage (not affected).

**Action:** Monitor for future releases if migrating to S3/GCS.

**Reference:** [Loki v3.5 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-5/)

#### 5. Label Limit Enforcement (v3.4+)

**Change:** Max label limit reduced from 30 to 15 labels per series.

**Impact:** Reduces index bloat and improves performance.

**Action Required:**
- Audit current label usage in Promtail scrape configs
- Ensure log streams don't exceed 15 labels
- Use structured metadata for additional key-value pairs

**Validation Command:**
```bash
# Query Loki for label cardinality
curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data[]' | wc -l
```

#### 6. Duplicate Label Handling (v3.3)

**Change:** When duplicate labels exist, only FIRST value is kept (was LAST).

**Impact:** Minor - only affects misconfigured Promtail pipelines.

**Action:** Review Promtail relabeling configs for duplicates.

#### 7. Bloom Filter Format Change (v3.3)

**Change:** Bloom block format incompatible with previous versions.

**Impact:** Requires deletion of existing bloom blocks before upgrade.

**Action Required:**
```bash
# If using bloom filters, delete before upgrade
rm -rf /var/lib/loki/bloomblocks/*
```

**Current Status:** Bloom filters not explicitly configured - likely not in use.

#### 8. Deprecated Configuration Removed

**Removed:**
- `shared_store` and `shared_store_key_prefix` from shipper config
- BoltDB store (deprecated in favor of TSDB)
- `table_manager` (deprecated - use `compactor` instead)

**Current Configuration Analysis:**
```yaml
# DEPRECATED - Should be removed
table_manager:
  retention_deletes_enabled: true
  retention_period: 360h
```

**Migration Required:** Remove `table_manager` section, rely on `compactor`:
```yaml
compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 10m
  retention_enabled: true           # ✓ Already configured
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
  delete_request_store: filesystem
```

**Reference:** [Loki Upgrade Guide](https://grafana.com/docs/loki/latest/setup/upgrade/)

---

### Promtail 3.x Changes

#### 1. Promtail Deprecation Announcement (v3.0)

**Change:** Promtail code merged into Grafana Alloy. No new features.

**EOL Timeline:**
- **LTS Support Until:** February 28, 2026
- **End-of-Life:** March 2, 2026
- **Security Fixes:** Available until EOL

**Migration Path:** Grafana Alloy (OpenTelemetry-based collector)

**Reference:** [Promtail EOL Announcement](https://community.grafana.com/t/promtail-end-of-life-eol-march-2026-how-to-migrate-to-grafana-alloy-for-existing-loki-server-deployments/159636)

#### 2. Configuration Compatibility

**Change:** Promtail 3.x configuration format backward compatible.

**Impact:** Existing Promtail configs work without modification.

**Status:** NO BREAKING CHANGES to configuration syntax.

#### 3. Version Matching Requirement

**Critical:** Promtail and Loki versions MUST match (major.minor).

**Version Matrix:**
- Loki 2.9.3 + Promtail 2.9.x = Compatible
- Loki 3.6.3 + Promtail 3.6.x = Compatible
- Loki 3.6.3 + Promtail 2.9.x = **NOT RECOMMENDED** (may work but unsupported)

**Upgrade Order:** Loki first, then Promtail (backward compatibility window).

---

## Upgrade Sequence Strategy

### Why Upgrade Loki First?

**Backward Compatibility:** Loki 3.x can ingest logs from Promtail 2.9.x for a limited transition period.

**Risk Mitigation:**
- Upgrade Loki on observability server (single node)
- Validate Loki health before touching monitored hosts
- Minimizes coordination complexity across multiple hosts

**Forward Incompatibility:** Promtail 3.x cannot send to Loki 2.x reliably.

### Upgrade Sequence

```
Phase 3.1: Loki Upgrade (Observability Server)
├─ Stop Loki service
├─ Backup configuration and data
├─ Update binary to 3.6.3
├─ Migrate configuration (remove deprecated fields)
├─ Start Loki service
├─ Validate health and ingestion
└─ Install Grafana Loki Operational UI plugin

Phase 3.2: Promtail Upgrade (Coordinated Across Hosts)
├─ Stop Promtail on Host 1
├─ Update binary to 3.6.3
├─ Start Promtail service
├─ Validate log shipping
├─ Wait 5 minutes
├─ Repeat for Host 2, 3, ... N
└─ Validate all hosts shipping logs
```

### Multi-Host Promtail Coordination

**Rolling Upgrade Strategy:**
- Upgrade one host at a time
- Wait 5 minutes between hosts for validation
- Monitor Loki ingestion rate during upgrades

**Expected Behavior:**
- Brief log gaps during Promtail restarts (30-60 seconds per host)
- Promtail will replay missed logs from disk buffer (if configured)
- No permanent log loss expected

**Monitoring During Upgrade:**
```bash
# Check Loki ingestion rate
curl -s http://localhost:3100/metrics | grep loki_ingester_chunks_created_total

# Check active Promtail connections
curl -s http://localhost:3100/metrics | grep loki_distributor_ingester_clients
```

### Version Compatibility Window

During the transition period, this configuration is supported:

| Component | Version | Status |
|-----------|---------|--------|
| Loki | 3.6.3 | Upgraded |
| Promtail (Host 1-5) | 2.9.3 | Old (being upgraded) |
| Promtail (Host 6-10) | 3.6.3 | New (upgraded) |

**Maximum Transition Time:** Recommended to complete within 24 hours.

---

## Promtail Deprecation Planning

### Official EOL Timeline

**Announcement:** Promtail deprecated in favor of Grafana Alloy (Loki 3.0 release)

**Support Windows:**
- **Active Development:** Ended (merged into Alloy)
- **Bug Fixes:** Until February 28, 2026
- **Security Patches:** Until March 2, 2026
- **End-of-Life:** March 2, 2026

**Why Upgrade to 3.6.3 Despite Deprecation?**
1. Security fixes (13 months of support remaining)
2. Compatibility with Loki 3.6.3
3. Synchronized upgrade with Loki (version matching)
4. Maintains observability during Alloy migration planning

**Reference:** [Migrate to Alloy Guide](https://grafana.com/docs/loki/latest/setup/migrate/migrate-to-alloy/)

### Grafana Alloy Migration Plan

**Timeline:**
- **Q1 2025:** Upgrade Loki/Promtail to 3.6.3 (this phase)
- **Q2 2025:** Plan and test Alloy migration in staging
- **Q3 2025:** Execute Alloy rollout (before EOL)
- **Q4 2025:** Complete migration and decommission Promtail

**Migration Strategy:**

#### Stage 1: Research and Testing (Q2 2025)
- Install Grafana Alloy in test environment
- Convert Promtail configs using `alloy convert` tool
- Validate log ingestion, relabeling, and performance
- Test OTLP endpoints (future-proofing)

#### Stage 2: Parallel Deployment (Q3 2025)
- Deploy Alloy alongside Promtail on 1-2 test hosts
- Run both collectors simultaneously (duplicate logs acceptable)
- Validate Alloy metrics, logs, and traces collection
- Benchmark resource usage (CPU, memory)

#### Stage 3: Gradual Rollout (Q3-Q4 2025)
- Migrate 10% of hosts to Alloy
- Monitor for 1 week
- Migrate remaining hosts in batches
- Decommission Promtail before March 2026 EOL

**Alloy Configuration Conversion:**

Grafana provides an automated conversion tool:

```bash
# Install Grafana Alloy
wget https://github.com/grafana/alloy/releases/latest/download/alloy-linux-amd64

# Convert Promtail config to Alloy
./alloy convert \
  --source-format=promtail \
  --output=/etc/alloy/config.alloy \
  /etc/promtail/promtail.yaml
```

**Alloy Benefits Over Promtail:**
- Unified agent for logs, metrics, and traces (reduces agent sprawl)
- Native OTLP support (OpenTelemetry compatibility)
- Continued feature development and support
- Better performance and resource efficiency
- Active community and ecosystem

**Reference:** [Migrate from Promtail to Alloy](https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/)

### Deprecation Notice Template

Add this to your runbook and share with stakeholders:

```
DEPRECATION NOTICE: Promtail

Promtail will reach End-of-Life on March 2, 2026.

Current Status:
- Version: 3.6.3 (upgraded January 2025)
- Supported Until: February 28, 2026
- Migration Target: Grafana Alloy
- Migration Deadline: Q4 2025

Action Required:
1. Continue using Promtail 3.6.3 for production logging
2. Plan Grafana Alloy migration for Q2-Q3 2025
3. Complete migration before March 2026 EOL

Resources:
- Migration Guide: https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/
- Alloy Documentation: https://grafana.com/docs/alloy/latest/
- Conversion Tool: alloy convert --source-format=promtail
```

---

## Pre-Upgrade Checklist

### Loki Pre-Upgrade Validation

```bash
# 1. Check current Loki version
/usr/local/bin/loki --version
# Expected: loki, version 2.9.3

# 2. Verify Loki is running and healthy
systemctl status loki
curl -s http://localhost:3100/ready | jq
# Expected: {"status":"ready"}

# 3. Check disk space (need 2x data size for backup)
df -h /var/lib/loki
# Required: At least 10GB free

# 4. Validate current configuration
# Check for deprecated fields
grep -E "(table_manager|shared_store)" /etc/loki/loki-config.yaml

# 5. Test query functionality
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'limit=10' | jq -r '.data.result[0]'
# Expected: Log entries returned

# 6. Check label cardinality (should be < 15 per stream)
curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data[]'

# 7. Verify retention working
ls -lah /var/lib/loki/chunks/
# Should only contain last 15 days (360h)

# 8. Check Grafana datasource connectivity
curl -s http://localhost:3000/api/health | jq
```

### Promtail Pre-Upgrade Validation (Per Host)

```bash
# 1. Check current Promtail version
/usr/local/bin/promtail --version
# Expected: promtail, version 2.9.3

# 2. Verify Promtail is running
systemctl status promtail
curl -s http://localhost:9080/ready | jq

# 3. Check Promtail metrics
curl -s http://localhost:9080/metrics | grep promtail_sent_entries_total

# 4. Verify log positions file
ls -lah /var/lib/promtail/positions.yaml
# Should exist and be recent

# 5. Test log ingestion
tail -f /var/log/syslog &
# Verify new log lines appear in Loki within 30 seconds

# 6. Check for configuration errors
journalctl -u promtail -n 50 --no-pager | grep -i error
```

### Backup Validation

```bash
# Verify backup script exists and is executable
ls -l /home/calounx/repositories/mentat/observability-stack/scripts/backup.sh
chmod +x /home/calounx/repositories/mentat/observability-stack/scripts/backup.sh

# Test backup directory writable
mkdir -p /var/lib/observability-upgrades/backups/phase3-loki
touch /var/lib/observability-upgrades/backups/phase3-loki/test
rm /var/lib/observability-upgrades/backups/phase3-loki/test
```

---

## Execution Plan

### Phase 3.1: Loki Upgrade (Observability Server)

**Estimated Time:** 15-20 minutes
**Downtime:** 5-10 minutes

#### Step 1: Create Backup (Pre-Upgrade)

```bash
# Set variables
BACKUP_DIR="/var/lib/observability-upgrades/backups/phase3-loki"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Stop Loki service
sudo systemctl stop loki

# Backup binary
sudo cp /usr/local/bin/loki "$BACKUP_DIR/$TIMESTAMP/loki-2.9.3"

# Backup configuration
sudo cp -r /etc/loki "$BACKUP_DIR/$TIMESTAMP/config"

# Backup data (WARNING: This can be large, use snapshot API in production)
# For test environments:
sudo tar -czf "$BACKUP_DIR/$TIMESTAMP/loki-data.tar.gz" /var/lib/loki

# For production (use Loki snapshot API):
# curl -XPOST http://localhost:3100/loki/api/v1/admin/tsdb/snapshot
# Then backup the snapshot directory

# Record current version
/usr/local/bin/loki --version > "$BACKUP_DIR/$TIMESTAMP/version.txt"

# Set permissions
sudo chown -R $USER:$USER "$BACKUP_DIR/$TIMESTAMP"

echo "Backup completed: $BACKUP_DIR/$TIMESTAMP"
```

#### Step 2: Update Loki Binary

```bash
# Download Loki 3.6.3
cd /tmp
wget https://github.com/grafana/loki/releases/download/v3.6.3/loki-linux-amd64.zip

# Verify checksum (optional but recommended)
wget https://github.com/grafana/loki/releases/download/v3.6.3/SHA256SUMS
sha256sum -c SHA256SUMS 2>&1 | grep loki-linux-amd64.zip

# Extract binary
unzip loki-linux-amd64.zip

# Verify binary
chmod +x loki-linux-amd64
./loki-linux-amd64 --version
# Expected: loki, version 3.6.3

# Install binary
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chown root:root /usr/local/bin/loki
sudo chmod 755 /usr/local/bin/loki

# Verify installation
/usr/local/bin/loki --version
```

#### Step 3: Migrate Configuration

```bash
# Edit Loki configuration
sudo nano /etc/loki/loki-config.yaml

# REMOVE deprecated table_manager section:
# DELETE THESE LINES:
# table_manager:
#   retention_deletes_enabled: true
#   retention_period: 360h

# KEEP compactor section (already configured):
# compactor:
#   working_directory: /var/lib/loki/compactor
#   compaction_interval: 10m
#   retention_enabled: true
#   retention_delete_delay: 2h
#   retention_delete_worker_count: 150
#   delete_request_store: filesystem

# OPTIONAL: Add label limit enforcement (recommended):
# limits_config:
#   max_label_names_per_series: 15  # Add this line

# Save and exit (Ctrl+O, Ctrl+X)
```

**Configuration Diff:**

```diff
--- loki-config.yaml (2.9.3)
+++ loki-config.yaml (3.6.3)
@@ -70,9 +70,7 @@
 limits_config:
   retention_period: 360h  # 15 days
+  max_label_names_per_series: 15  # Enforce label limit
   ingestion_rate_mb: 10
   ingestion_burst_size_mb: 20
   max_streams_per_user: 10000
   max_line_size: 256kb
   reject_old_samples: true
   reject_old_samples_max_age: 168h  # 7 days

-table_manager:
-  retention_deletes_enabled: true
-  retention_period: 360h  # 15 days
-
 analytics:
   reporting_enabled: false
```

#### Step 4: Validate Configuration

```bash
# Loki 3.x doesn't have a config validation command
# Manual validation required

# Check YAML syntax
python3 -c "import yaml; yaml.safe_load(open('/etc/loki/loki-config.yaml'))"
# Expected: No output (success)

# Verify required fields present
grep -q "schema: v13" /etc/loki/loki-config.yaml && echo "Schema v13: OK"
grep -q "store: tsdb" /etc/loki/loki-config.yaml && echo "TSDB: OK"
grep -q "retention_enabled: true" /etc/loki/loki-config.yaml && echo "Retention: OK"

# Ensure deprecated fields removed
! grep -q "table_manager" /etc/loki/loki-config.yaml && echo "table_manager removed: OK"
! grep -q "shared_store" /etc/loki/loki-config.yaml && echo "shared_store removed: OK"
```

#### Step 5: Start Loki and Validate

```bash
# Start Loki service
sudo systemctl start loki

# Wait for startup (30 seconds)
sleep 30

# Check service status
sudo systemctl status loki

# Check logs for errors
sudo journalctl -u loki -n 50 --no-pager

# Verify health endpoint
curl -s http://localhost:3100/ready | jq
# Expected: {"status":"ready"}

# Test query functionality
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'limit=1' | jq -r '.status'
# Expected: "success"

# Check version
curl -s http://localhost:3100/metrics | grep "loki_build_info"
# Expected: version="3.6.3"

# Monitor ingestion (wait 2 minutes for data)
sleep 120
curl -s http://localhost:3100/metrics | grep loki_ingester_chunks_created_total
```

#### Step 6: Validate Grafana Data Source

```bash
# Test Loki data source from Grafana
curl -s -H "Content-Type: application/json" \
  http://localhost:3000/api/datasources/uid/loki/health | jq
# Expected: "status": "OK"

# Query recent logs via Grafana API (requires API key)
# Manual validation: Open Grafana > Explore > Loki > Query logs
```

### Phase 3.2: Promtail Upgrade (Multi-Host Rollout)

**Estimated Time:** 5 minutes per host
**Total Time:** 5 minutes × N hosts

#### Upgrade Script Template (Per Host)

Create `/tmp/upgrade-promtail.sh`:

```bash
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/var/lib/observability-upgrades/backups/phase3-promtail"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)

echo "=== Promtail Upgrade: $HOSTNAME ==="

# Step 1: Backup
echo "[1/6] Creating backup..."
mkdir -p "$BACKUP_DIR/$HOSTNAME/$TIMESTAMP"
sudo systemctl stop promtail
sudo cp /usr/local/bin/promtail "$BACKUP_DIR/$HOSTNAME/$TIMESTAMP/promtail-2.9.3"
sudo cp -r /etc/promtail "$BACKUP_DIR/$HOSTNAME/$TIMESTAMP/config"
sudo cp /var/lib/promtail/positions.yaml "$BACKUP_DIR/$HOSTNAME/$TIMESTAMP/positions.yaml"
/usr/local/bin/promtail --version > "$BACKUP_DIR/$HOSTNAME/$TIMESTAMP/version.txt"

# Step 2: Download Promtail 3.6.3
echo "[2/6] Downloading Promtail 3.6.3..."
cd /tmp
wget -q https://github.com/grafana/loki/releases/download/v3.6.3/promtail-linux-amd64.zip
unzip -q promtail-linux-amd64.zip
chmod +x promtail-linux-amd64

# Step 3: Verify binary
echo "[3/6] Verifying binary..."
./promtail-linux-amd64 --version | grep "3.6.3" || { echo "Version mismatch!"; exit 1; }

# Step 4: Install binary
echo "[4/6] Installing binary..."
sudo mv promtail-linux-amd64 /usr/local/bin/promtail
sudo chown root:root /usr/local/bin/promtail
sudo chmod 755 /usr/local/bin/promtail

# Step 5: Start Promtail
echo "[5/6] Starting Promtail..."
sudo systemctl start promtail
sleep 10

# Step 6: Validate
echo "[6/6] Validating..."
sudo systemctl status promtail --no-pager
curl -s http://localhost:9080/ready | jq || { echo "Health check failed!"; exit 1; }

# Check for errors in logs
ERROR_COUNT=$(sudo journalctl -u promtail -n 20 --no-pager | grep -i error | wc -l)
if [ "$ERROR_COUNT" -gt 0 ]; then
  echo "WARNING: $ERROR_COUNT errors found in logs"
  sudo journalctl -u promtail -n 20 --no-pager | grep -i error
fi

# Check version
VERSION=$(/usr/local/bin/promtail --version | grep -oP 'version \K[0-9.]+')
echo "Promtail version: $VERSION"

# Check log shipping
METRICS=$(curl -s http://localhost:9080/metrics | grep promtail_sent_entries_total)
echo "Log shipping metrics: $METRICS"

echo "=== Upgrade completed successfully: $HOSTNAME ==="
echo "Backup location: $BACKUP_DIR/$HOSTNAME/$TIMESTAMP"
```

#### Rollout Sequence

```bash
# Make script executable
chmod +x /tmp/upgrade-promtail.sh

# Execute on Host 1
ssh host1.example.com 'bash -s' < /tmp/upgrade-promtail.sh

# Wait 5 minutes and validate
sleep 300
curl -s http://loki-server:3100/metrics | grep loki_distributor_bytes_received_total

# Repeat for Host 2, 3, ... N
for HOST in host2 host3 host4 host5; do
  echo "=== Upgrading $HOST ==="
  ssh $HOST.example.com 'bash -s' < /tmp/upgrade-promtail.sh

  echo "Waiting 5 minutes before next host..."
  sleep 300

  echo "Validating Loki ingestion..."
  curl -s http://localhost:3100/metrics | grep loki_distributor_bytes_received_total
done
```

---

## Rollback Procedure

### Loki Rollback

**When to Rollback:**
- Loki service fails to start after 3 restart attempts
- Health check endpoint returns errors for > 5 minutes
- Log ingestion drops to zero for > 10 minutes
- Critical configuration errors detected

**Rollback Steps:**

```bash
# Set backup directory
BACKUP_DIR="/var/lib/observability-upgrades/backups/phase3-loki"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -1)

echo "Rolling back to: $LATEST_BACKUP"

# Step 1: Stop Loki 3.6.3
sudo systemctl stop loki

# Step 2: Restore binary
sudo cp "$BACKUP_DIR/$LATEST_BACKUP/loki-2.9.3" /usr/local/bin/loki
sudo chown root:root /usr/local/bin/loki
sudo chmod 755 /usr/local/bin/loki

# Step 3: Restore configuration
sudo rm -rf /etc/loki
sudo cp -r "$BACKUP_DIR/$LATEST_BACKUP/config" /etc/loki
sudo chown -R loki:loki /etc/loki

# Step 4: Restore data (if corrupted)
# WARNING: This will lose logs ingested after backup
# sudo systemctl stop loki
# sudo rm -rf /var/lib/loki
# sudo tar -xzf "$BACKUP_DIR/$LATEST_BACKUP/loki-data.tar.gz" -C /
# sudo chown -R loki:loki /var/lib/loki

# Step 5: Start Loki 2.9.3
sudo systemctl start loki

# Step 6: Validate rollback
sleep 30
curl -s http://localhost:3100/ready | jq
curl -s http://localhost:3100/metrics | grep "loki_build_info"

# Expected version: 2.9.3
/usr/local/bin/loki --version
```

**Post-Rollback Actions:**
- Document rollback reason and failure symptoms
- Review logs for root cause: `journalctl -u loki -n 200`
- Test upgrade in staging environment
- Report issues to Grafana Loki GitHub

### Promtail Rollback (Per Host)

```bash
# Set variables
BACKUP_DIR="/var/lib/observability-upgrades/backups/phase3-promtail"
HOSTNAME=$(hostname)
LATEST_BACKUP=$(ls -t "$BACKUP_DIR/$HOSTNAME" | head -1)

echo "Rolling back Promtail on $HOSTNAME to: $LATEST_BACKUP"

# Step 1: Stop Promtail 3.6.3
sudo systemctl stop promtail

# Step 2: Restore binary
sudo cp "$BACKUP_DIR/$HOSTNAME/$LATEST_BACKUP/promtail-2.9.3" /usr/local/bin/promtail
sudo chown root:root /usr/local/bin/promtail
sudo chmod 755 /usr/local/bin/promtail

# Step 3: Restore configuration
sudo rm -rf /etc/promtail
sudo cp -r "$BACKUP_DIR/$HOSTNAME/$LATEST_BACKUP/config" /etc/promtail
sudo chown -R promtail:promtail /etc/promtail

# Step 4: Restore positions file
sudo cp "$BACKUP_DIR/$HOSTNAME/$LATEST_BACKUP/positions.yaml" /var/lib/promtail/positions.yaml
sudo chown promtail:promtail /var/lib/promtail/positions.yaml

# Step 5: Start Promtail 2.9.3
sudo systemctl start promtail

# Step 6: Validate rollback
sleep 10
curl -s http://localhost:9080/ready | jq
/usr/local/bin/promtail --version
```

### Rollback Decision Matrix

| Symptom | Severity | Rollback? | Alternative |
|---------|----------|-----------|-------------|
| Loki won't start | Critical | YES | Check config syntax |
| Loki starts but /ready fails | High | YES after 5min | Check logs for errors |
| Ingestion rate drops 50% | Medium | NO | Investigate Promtail connectivity |
| Ingestion rate drops 100% | High | YES after 10min | Check Loki logs |
| Query performance degraded | Low | NO | Monitor for 1 hour |
| High memory usage | Medium | NO | Check compactor, retention |
| Grafana datasource error | Medium | NO | Restart Grafana, check datasource config |

---

## Data Integrity Validation

### Log Retention Verification

```bash
# Test 1: Verify retention period enforced (15 days = 360h)
RETENTION_DAYS=15
CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%s)

# Query oldest logs
OLDEST_LOG=$(curl -s -G "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job=~".+"}' \
  --data-urlencode "start=$((CUTOFF_DATE - 86400))" \
  --data-urlencode "end=$CUTOFF_DATE" \
  --data-urlencode 'limit=1' | jq -r '.data.result[0].values[0][0]')

if [ -n "$OLDEST_LOG" ]; then
  OLDEST_TIMESTAMP=$((OLDEST_LOG / 1000000000))
  AGE_DAYS=$(( ($(date +%s) - OLDEST_TIMESTAMP) / 86400 ))

  if [ $AGE_DAYS -le $RETENTION_DAYS ]; then
    echo "✓ Retention working: Oldest log is $AGE_DAYS days old (limit: $RETENTION_DAYS)"
  else
    echo "✗ Retention issue: Oldest log is $AGE_DAYS days old (limit: $RETENTION_DAYS)"
  fi
else
  echo "⚠ No logs found older than $RETENTION_DAYS days (expected if new deployment)"
fi
```

### Log Loss Detection

```bash
# Test 2: Verify no log gaps during upgrade

# Query log counts 1 hour before upgrade
UPGRADE_TIME="2025-01-15T10:00:00Z"  # Replace with actual upgrade time
PRE_UPGRADE=$(date -d "$UPGRADE_TIME - 1 hour" --rfc-3339=seconds | sed 's/ /T/')
UPGRADE_START=$(date -d "$UPGRADE_TIME" --rfc-3339=seconds | sed 's/ /T/')
POST_UPGRADE=$(date -d "$UPGRADE_TIME + 1 hour" --rfc-3339=seconds | sed 's/ /T/')

# Count logs before upgrade
LOGS_BEFORE=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query=count_over_time({job=~".+"}[1h])' \
  --data-urlencode "start=$PRE_UPGRADE" \
  --data-urlencode "end=$UPGRADE_START" | jq -r '.data.result[0].values[-1][1]')

# Count logs after upgrade
LOGS_AFTER=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query=count_over_time({job=~".+"}[1h])' \
  --data-urlencode "start=$UPGRADE_START" \
  --data-urlencode "end=$POST_UPGRADE" | jq -r '.data.result[0].values[-1][1]')

echo "Logs before upgrade: $LOGS_BEFORE"
echo "Logs after upgrade: $LOGS_AFTER"

# Expected: Minor drop during upgrade (5-10 minutes), then resume
DIFF=$(( (LOGS_BEFORE - LOGS_AFTER) * 100 / LOGS_BEFORE ))
if [ $DIFF -lt 20 ]; then
  echo "✓ Log ingestion normal (variance: ${DIFF}%)"
else
  echo "⚠ Significant log drop detected (variance: ${DIFF}%)"
fi
```

### Query Performance Validation

```bash
# Test 3: Benchmark query performance (should be similar to pre-upgrade)

# Simple query benchmark
time curl -s -G "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'limit=100' > /dev/null
# Expected: < 2 seconds

# Range query benchmark
time curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'start=2025-01-15T00:00:00Z' \
  --data-urlencode 'end=2025-01-15T23:59:59Z' \
  --data-urlencode 'limit=1000' > /dev/null
# Expected: < 5 seconds for 24h range
```

### Index Health Check

```bash
# Test 4: Verify TSDB index health

# Check index files
ls -lh /var/lib/loki/tsdb-index/
# Should contain recent index files

# Check for index errors in logs
sudo journalctl -u loki -n 500 --no-pager | grep -i "index" | grep -i "error"
# Expected: No critical errors

# Verify compaction running
curl -s http://localhost:3100/metrics | grep loki_compactor_compaction_duration_seconds_count
# Expected: Non-zero (compaction has run)
```

### Stream Validation

```bash
# Test 5: Verify label cardinality within limits

# List all labels
LABEL_COUNT=$(curl -s "http://localhost:3100/loki/api/v1/labels" | jq -r '.data | length')
echo "Total unique labels: $LABEL_COUNT"

# Check stream count
STREAM_COUNT=$(curl -s "http://localhost:3100/loki/api/v1/series" \
  --data-urlencode 'match={job=~".+"}' | jq -r '.data | length')
echo "Total streams: $STREAM_COUNT"

# Expected: < 10000 (matches max_streams_per_user config)
if [ $STREAM_COUNT -lt 10000 ]; then
  echo "✓ Stream count within limits"
else
  echo "⚠ Stream count high: $STREAM_COUNT (limit: 10000)"
fi
```

### Promtail Connection Validation

```bash
# Test 6: Verify all Promtail instances connected

# List expected hosts
EXPECTED_HOSTS=("host1" "host2" "host3" "host4" "host5")

# Query labels for hostname
for HOST in "${EXPECTED_HOSTS[@]}"; do
  RESULT=$(curl -s -G "http://localhost:3100/loki/api/v1/query" \
    --data-urlencode "query={hostname=\"$HOST\"}" \
    --data-urlencode 'limit=1' | jq -r '.data.result | length')

  if [ "$RESULT" -gt 0 ]; then
    echo "✓ $HOST: Connected and shipping logs"
  else
    echo "✗ $HOST: No recent logs found"
  fi
done
```

---

## Grafana Integration

### Install Loki Operational UI Plugin

The Loki built-in UI has been removed in v3.6 and moved to a Grafana plugin.

**Reference:** [Loki Operational UI Plugin](https://grafana.com/grafana/plugins/grafana-lokioperational-app/)

#### Installation Steps

```bash
# Option 1: Install via Grafana CLI
sudo grafana-cli plugins install grafana-lokioperational-app

# Option 2: Install via Docker (if using containerized Grafana)
# Add to docker-compose.yml:
# environment:
#   - GF_INSTALL_PLUGINS=grafana-lokioperational-app

# Restart Grafana
sudo systemctl restart grafana-server

# Wait for startup
sleep 10

# Verify plugin installed
curl -s http://localhost:3000/api/plugins/grafana-lokioperational-app | jq -r '.name'
# Expected: "Loki Operational UI"
```

#### Enable Plugin in Grafana

1. Open Grafana: http://localhost:3000
2. Navigate to: **Configuration > Plugins**
3. Search for: "Loki Operational"
4. Click: **Enable**
5. Configure data source: Select your Loki datasource (uid: loki)

#### Access Loki Operational UI

- URL: `http://localhost:3000/a/grafana-lokioperational-app`
- Features:
  - Ring status
  - Ingester metrics
  - Compactor status
  - Query performance
  - Retention policies

### Update Loki Data Source

The existing Loki datasource should continue working without changes.

**Verify Configuration:**

```bash
# Check datasource configuration
curl -s http://localhost:3000/api/datasources/uid/loki | jq

# Expected output:
{
  "name": "Loki",
  "type": "loki",
  "url": "http://localhost:3100",
  "access": "proxy",
  "jsonData": {
    "maxLines": 1000
  }
}
```

**Optional: Add v3-specific features:**

```yaml
# grafana/provisioning/datasources/datasources.yaml

datasources:
  - name: Loki
    type: loki
    uid: loki
    access: proxy
    url: http://localhost:3100
    editable: false
    jsonData:
      maxLines: 1000
      timeout: 60
      # New in Loki 3.x: Structured metadata support
      derivedFields:
        - name: TraceID
          matcherRegex: "traceID=(\\w+)"
          url: "http://localhost:3000/explore?left={\"datasource\":\"tempo\",\"queries\":[{\"query\":\"$${__value.raw}\"}]}"
```

### Dashboard Compatibility

Existing Grafana dashboards using Loki datasource should work without modification.

**Validation Steps:**

1. Open Grafana: http://localhost:3000
2. Navigate to: **Explore**
3. Select datasource: **Loki**
4. Test query: `{job="varlogs"}`
5. Verify log lines displayed
6. Test LogQL aggregations: `count_over_time({job="varlogs"}[5m])`

**Common Issues:**

| Issue | Cause | Solution |
|-------|-------|----------|
| "Bad Gateway" error | Loki not running | Check `systemctl status loki` |
| "No data" in Explore | No recent logs | Check Promtail status on hosts |
| Slow queries | High cardinality | Reduce label count, add indexes |
| "Too many streams" | Label explosion | Review Promtail relabel configs |

### Alert Rule Migration

**LogQL Compatibility:** Loki 3.x maintains backward compatibility with LogQL queries.

**Validation:**

```bash
# List current Loki alert rules (if configured)
curl -s http://localhost:3100/loki/api/v1/rules | jq

# Test alert rule query
curl -s -G "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query=rate({job="varlogs"} |= "error" [5m]) > 0' | jq -r '.status'
# Expected: "success"
```

**No migration required** unless using deprecated query syntax.

---

## Troubleshooting

### Loki Issues

#### Issue: Loki service fails to start

**Symptoms:**
```bash
systemctl status loki
# Output: Failed to start Loki.
```

**Diagnosis:**
```bash
# Check logs for specific error
sudo journalctl -u loki -n 50 --no-pager

# Common errors:
# - "invalid configuration": Config syntax error
# - "permission denied": File permissions issue
# - "address already in use": Port conflict
```

**Solutions:**

1. **Configuration Error:**
```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('/etc/loki/loki-config.yaml'))"

# Check for deprecated fields
grep -E "(table_manager|shared_store)" /etc/loki/loki-config.yaml
```

2. **Permission Error:**
```bash
sudo chown -R loki:loki /var/lib/loki
sudo chown -R loki:loki /etc/loki
sudo chmod 755 /var/lib/loki
```

3. **Port Conflict:**
```bash
# Check if port 3100 in use
sudo netstat -tlnp | grep 3100

# Kill conflicting process or change Loki port in config
```

#### Issue: High memory usage

**Symptoms:**
```bash
# Loki consuming > 2GB RAM
ps aux | grep loki
```

**Diagnosis:**
```bash
# Check ingestion rate
curl -s http://localhost:3100/metrics | grep loki_distributor_bytes_received_total

# Check number of streams
curl -s "http://localhost:3100/loki/api/v1/series" \
  --data-urlencode 'match={job=~".+"}' | jq -r '.data | length'
```

**Solutions:**

1. **Reduce stream cardinality:**
```yaml
# /etc/loki/loki-config.yaml
limits_config:
  max_label_names_per_series: 10  # Reduce from 15
  max_streams_per_user: 5000      # Reduce from 10000
```

2. **Tune cache settings:**
```yaml
chunk_store_config:
  chunk_cache_config:
    embedded_cache:
      max_size_mb: 256  # Reduce from 500
```

3. **Enable compaction more frequently:**
```yaml
compactor:
  compaction_interval: 5m  # Reduce from 10m
```

#### Issue: Logs older than retention period not deleted

**Diagnosis:**
```bash
# Check compactor status
curl -s http://localhost:3100/metrics | grep loki_compactor_compaction_duration_seconds_count

# Check retention config
grep -A 5 "limits_config" /etc/loki/loki-config.yaml
```

**Solution:**
```bash
# Ensure retention enabled in compactor
grep -A 10 "compactor:" /etc/loki/loki-config.yaml | grep "retention_enabled: true"

# Manually trigger compaction (if needed)
# Note: Loki 3.x doesn't have a manual trigger API
# Restart Loki to force compaction run
sudo systemctl restart loki
```

### Promtail Issues

#### Issue: Promtail not shipping logs

**Symptoms:**
```bash
curl -s http://localhost:9080/metrics | grep promtail_sent_entries_total
# Output: 0 or no increase over time
```

**Diagnosis:**
```bash
# Check Promtail logs
sudo journalctl -u promtail -n 50 --no-pager

# Common errors:
# - "connection refused": Loki unreachable
# - "permission denied": Cannot read log files
# - "context deadline exceeded": Timeout connecting to Loki
```

**Solutions:**

1. **Loki Connectivity:**
```bash
# Test Loki reachable from Promtail host
curl -s http://loki-server:3100/ready | jq

# Check Promtail config for correct Loki URL
grep "url:" /etc/promtail/promtail.yaml
```

2. **File Permission:**
```bash
# Ensure promtail user in adm group
sudo usermod -a -G adm promtail

# Check log file permissions
ls -l /var/log/syslog
# Should be readable by adm group

# Restart Promtail
sudo systemctl restart promtail
```

3. **Authentication:**
```bash
# Verify Loki credentials (if using HTTP auth)
grep -A 5 "client:" /etc/promtail/promtail.yaml

# Test authentication
curl -u username:password http://loki-server:3100/ready
```

#### Issue: Duplicate log entries

**Symptoms:**
- Same log line appears multiple times in Loki

**Cause:**
- Multiple Promtail instances reading same log file
- Promtail positions file corrupted

**Solution:**
```bash
# Check positions file
cat /var/lib/promtail/positions.yaml

# If corrupted, reset positions (will re-ingest logs)
sudo systemctl stop promtail
sudo mv /var/lib/promtail/positions.yaml /var/lib/promtail/positions.yaml.bak
sudo systemctl start promtail
```

#### Issue: Version mismatch warning

**Symptoms:**
```bash
sudo journalctl -u promtail -n 50 | grep "version mismatch"
```

**Solution:**
```bash
# Verify versions match
/usr/local/bin/promtail --version
curl -s http://loki-server:3100/metrics | grep loki_build_info

# Upgrade Promtail to match Loki version
# Follow Phase 3.2 upgrade procedure
```

### Grafana Integration Issues

#### Issue: Loki datasource returns "Bad Gateway"

**Diagnosis:**
```bash
# Check Loki status
systemctl status loki

# Test Loki from Grafana server
curl -s http://localhost:3100/ready | jq
```

**Solution:**
```bash
# Restart Loki
sudo systemctl restart loki

# Verify datasource URL in Grafana
curl -s http://localhost:3000/api/datasources/uid/loki | jq -r '.url'
```

#### Issue: Loki Operational UI plugin not visible

**Diagnosis:**
```bash
# Check plugin installed
grafana-cli plugins ls | grep lokioperational

# Check Grafana logs
sudo journalctl -u grafana-server -n 50 | grep plugin
```

**Solution:**
```bash
# Reinstall plugin
sudo grafana-cli plugins install grafana-lokioperational-app

# Restart Grafana
sudo systemctl restart grafana-server

# Check plugin permissions
ls -l /var/lib/grafana/plugins/grafana-lokioperational-app
```

---

## Summary Checklist

### Pre-Upgrade Validation
- [ ] Loki 2.9.3 running and healthy
- [ ] Promtail 2.9.3 running on all hosts
- [ ] Disk space available (10GB+ free)
- [ ] Backup strategy tested
- [ ] Configuration audited for deprecated fields
- [ ] Label cardinality checked (< 15 per stream)
- [ ] Downtime window scheduled

### Loki Upgrade
- [ ] Loki service stopped
- [ ] Binary backed up
- [ ] Configuration backed up
- [ ] Data backed up
- [ ] Loki 3.6.3 binary downloaded and verified
- [ ] Configuration migrated (table_manager removed)
- [ ] Loki 3.6.3 started successfully
- [ ] Health check passing
- [ ] Query functionality validated
- [ ] Grafana datasource working

### Promtail Upgrade
- [ ] Loki upgrade completed and validated
- [ ] Promtail upgrade script prepared
- [ ] Host 1 upgraded and validated
- [ ] 5-minute soak period completed
- [ ] Remaining hosts upgraded sequentially
- [ ] All hosts shipping logs to Loki
- [ ] No log loss detected

### Grafana Integration
- [ ] Loki Operational UI plugin installed
- [ ] Plugin enabled and configured
- [ ] Loki datasource tested in Explore
- [ ] Existing dashboards functional
- [ ] Alert rules validated

### Post-Upgrade Validation
- [ ] Log retention enforced (15 days)
- [ ] No log gaps detected during upgrade
- [ ] Query performance acceptable
- [ ] Index health verified
- [ ] Stream count within limits
- [ ] All Promtail hosts connected
- [ ] Compaction running
- [ ] No critical errors in logs

### Documentation
- [ ] Backup locations documented
- [ ] Upgrade timestamp recorded
- [ ] Issues encountered documented
- [ ] Promtail deprecation notice communicated
- [ ] Alloy migration plan created (Q2-Q4 2025)

---

## Reference Links

### Official Documentation
- [Loki v3.0 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-0/)
- [Loki v3.6 Release Notes](https://grafana.com/docs/loki/latest/release-notes/v3-6/)
- [Loki Upgrade Guide](https://grafana.com/docs/loki/latest/setup/upgrade/)
- [Loki Storage Schema](https://grafana.com/docs/loki/latest/operations/storage/schema/)
- [Promtail Documentation](https://grafana.com/docs/loki/latest/send-data/promtail/)

### Migration Guides
- [Upgrade from 2.x to 3.0](https://grafana.com/docs/loki/latest/setup/upgrade/upgrade-from-2x/)
- [Migrate to Grafana Alloy](https://grafana.com/docs/loki/latest/setup/migrate/migrate-to-alloy/)
- [Alloy Migration from Promtail](https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/)

### Deprecation Notices
- [Promtail EOL Announcement](https://community.grafana.com/t/promtail-end-of-life-eol-march-2026-how-to-migrate-to-grafana-alloy-for-existing-loki-server-deployments/159636)
- [Grafana Alloy Overview](https://grafana.com/docs/alloy/latest/)

### GitHub Issues
- [Loki 3.0 Breaking Changes](https://github.com/grafana/loki/issues/7076)
- [Loki UI moved to Grafana Plugin](https://github.com/grafana/loki/pull/19390)

### Plugins
- [Loki Operational UI Plugin](https://grafana.com/grafana/plugins/grafana-lokioperational-app/)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-15
**Prepared By:** Observability Team
**Review Date:** Q2 2025 (before Alloy migration)
