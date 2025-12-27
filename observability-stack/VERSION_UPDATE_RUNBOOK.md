# Version Update Runbook

**Purpose:** Step-by-step procedures for safely updating observability stack components
**Last Updated:** 2025-12-27
**Target Audience:** System Administrators, DevOps Engineers

---

## Table of Contents

1. [Pre-Update Checklist](#pre-update-checklist)
2. [Exporter Updates (Low Risk)](#exporter-updates-low-risk)
3. [Prometheus Update (High Risk)](#prometheus-update-high-risk)
4. [Loki + Promtail Update (Medium Risk)](#loki--promtail-update-medium-risk)
5. [Validation Procedures](#validation-procedures)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)

---

## Pre-Update Checklist

### Required Before ANY Update

- [ ] Read [VERSION_UPDATE_SAFETY_REPORT.md](./VERSION_UPDATE_SAFETY_REPORT.md)
- [ ] Review component-specific breaking changes
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Create backups (see below)
- [ ] Verify rollback procedures
- [ ] Prepare monitoring dashboards
- [ ] Document baseline metrics

### Backup Procedures

#### 1. Backup Prometheus Data

```bash
# Create backup directory
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/prometheus-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# Stop Prometheus
systemctl stop prometheus

# Backup TSDB data
cp -r /var/lib/prometheus "$BACKUP_DIR/data"

# Backup configuration
cp /etc/prometheus/prometheus.yml "$BACKUP_DIR/prometheus.yml"
cp -r /etc/prometheus/rules "$BACKUP_DIR/rules"

# Backup binary
cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus.bin"

# Document version
/usr/local/bin/prometheus --version > "$BACKUP_DIR/VERSION.txt"

# Restart Prometheus
systemctl start prometheus

echo "Backup completed: $BACKUP_DIR"
```

#### 2. Backup Loki Data

```bash
# Create backup directory
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/loki-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# Stop Loki
systemctl stop loki

# Backup data (if using local storage)
cp -r /var/lib/loki "$BACKUP_DIR/data"

# Backup configuration
cp /etc/loki/loki-config.yaml "$BACKUP_DIR/loki-config.yaml"

# Backup binary
cp /usr/local/bin/loki "$BACKUP_DIR/loki.bin"

# Document version
/usr/local/bin/loki --version > "$BACKUP_DIR/VERSION.txt"

# Restart Loki
systemctl start loki

echo "Backup completed: $BACKUP_DIR"
```

#### 3. Backup Grafana Dashboards

```bash
# Create backup directory
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/grafana-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# Backup Grafana database and dashboards
systemctl stop grafana-server
cp -r /var/lib/grafana "$BACKUP_DIR/lib"
cp -r /etc/grafana "$BACKUP_DIR/etc"
systemctl start grafana-server

echo "Backup completed: $BACKUP_DIR"
```

#### 4. Backup Exporter Configurations

```bash
# Create backup directory
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/exporters-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# Backup all exporter binaries and configs
for exporter in node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter promtail; do
    if [[ -f "/usr/local/bin/$exporter" ]] || [[ -f "/usr/local/bin/${exporter/-/_}" ]]; then
        mkdir -p "$BACKUP_DIR/$exporter"

        # Backup binary
        cp /usr/local/bin/${exporter}* "$BACKUP_DIR/$exporter/" 2>/dev/null || true

        # Backup systemd service
        cp /etc/systemd/system/${exporter}.service "$BACKUP_DIR/$exporter/" 2>/dev/null || true

        # Backup configs
        if [[ -d "/etc/$exporter" ]]; then
            cp -r "/etc/$exporter" "$BACKUP_DIR/$exporter/config"
        fi

        # Document version
        if [[ -x "/usr/local/bin/$exporter" ]]; then
            /usr/local/bin/$exporter --version > "$BACKUP_DIR/$exporter/VERSION.txt" 2>&1 || true
        fi
    fi
done

echo "Backup completed: $BACKUP_DIR"
```

### Verification Checklist

Before proceeding with updates:

- [ ] All backups completed successfully
- [ ] Backup integrity verified (test restore on non-production)
- [ ] Baseline metrics captured
- [ ] Service status documented
- [ ] Current versions documented
- [ ] Rollback procedures tested in non-production

---

## Exporter Updates (Low Risk)

### Timeline: 1-2 hours per exporter across all hosts
### Risk Level: LOW
### Rollback: Easy (binary replacement)

### Components

- Node Exporter (1.7.0 → 1.9.1)
- Nginx Exporter (1.1.0 → 1.5.1)
- MySQL Exporter (0.15.1 → 0.18.0)

### Strategy: Rolling Updates

Update one host at a time, verify, then proceed to next host.

---

### Update Node Exporter (1.7.0 → 1.9.1)

#### 1. Pre-Update Validation

```bash
# Check current version
/usr/local/bin/node_exporter --version

# Verify service is running
systemctl status node_exporter

# Test metrics endpoint
curl -s http://localhost:9100/metrics | head -20

# Capture baseline metrics
curl -s http://localhost:9100/metrics > /tmp/node_exporter_baseline.txt
```

#### 2. Download and Verify New Version

```bash
# Set version
VERSION="1.9.1"
cd /tmp

# Download binary
wget https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.linux-amd64.tar.gz

# Download checksum
wget https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/sha256sums.txt

# Verify checksum
sha256sum -c sha256sums.txt --ignore-missing

# Expected output: node_exporter-${VERSION}.linux-amd64.tar.gz: OK
```

#### 3. Install New Version

```bash
# Extract
tar xzf node_exporter-${VERSION}.linux-amd64.tar.gz

# Stop service
systemctl stop node_exporter

# Backup current binary
cp /usr/local/bin/node_exporter /usr/local/bin/node_exporter.backup

# Install new binary
cp node_exporter-${VERSION}.linux-amd64/node_exporter /usr/local/bin/node_exporter
chown node_exporter:node_exporter /usr/local/bin/node_exporter
chmod 755 /usr/local/bin/node_exporter

# Verify new version
/usr/local/bin/node_exporter --version

# Start service
systemctl start node_exporter
```

#### 4. Post-Update Validation

```bash
# Wait for startup
sleep 3

# Check service status
systemctl status node_exporter

# Verify metrics endpoint
curl -s http://localhost:9100/metrics | head -20

# Compare with baseline (should have same metrics)
curl -s http://localhost:9100/metrics > /tmp/node_exporter_new.txt

# Check for key metrics
curl -s http://localhost:9100/metrics | grep -E "node_cpu_seconds_total|node_memory_MemTotal_bytes|node_filesystem_avail_bytes" | head -10

# Verify from Prometheus (on observability VPS)
# curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="node_exporter") | select(.labels.instance=="<HOST_IP>:9100") | {health: .health, lastError: .lastError}'
```

#### 5. Rollback (If Needed)

```bash
# Stop service
systemctl stop node_exporter

# Restore old binary
cp /usr/local/bin/node_exporter.backup /usr/local/bin/node_exporter

# Start service
systemctl start node_exporter

# Verify
systemctl status node_exporter
```

#### 6. Cleanup (If Successful)

```bash
# Remove backup binary
rm /usr/local/bin/node_exporter.backup

# Remove download files
rm -rf /tmp/node_exporter-* /tmp/sha256sums.txt

echo "Node Exporter update completed successfully"
```

---

### Update Nginx Exporter (1.1.0 → 1.5.1)

#### 1. Pre-Update Validation

```bash
# Check current version
/usr/local/bin/nginx-prometheus-exporter --version

# Verify service
systemctl status nginx_exporter

# Test metrics
curl -s http://localhost:9113/metrics | head -20
```

#### 2. Download and Install

```bash
# Set version
VERSION="1.5.1"
cd /tmp

# Download (adjust architecture if needed)
wget https://github.com/nginx/nginx-prometheus-exporter/releases/download/v${VERSION}/nginx-prometheus-exporter_${VERSION}_linux_amd64.tar.gz

# Extract
tar xzf nginx-prometheus-exporter_${VERSION}_linux_amd64.tar.gz

# Stop service
systemctl stop nginx_exporter

# Backup and install
cp /usr/local/bin/nginx-prometheus-exporter /usr/local/bin/nginx-prometheus-exporter.backup
cp nginx-prometheus-exporter /usr/local/bin/nginx-prometheus-exporter
chown nginx_exporter:nginx_exporter /usr/local/bin/nginx-prometheus-exporter
chmod 755 /usr/local/bin/nginx-prometheus-exporter

# Start service
systemctl start nginx_exporter
```

#### 3. Post-Update Validation

```bash
# Verify
systemctl status nginx_exporter
curl -s http://localhost:9113/metrics | grep -E "nginx_up|nginxexporter_build_info"

# Check from Prometheus
# curl -s http://localhost:9090/api/v1/query?query=nginx_up | jq '.data.result[] | select(.metric.instance=="<HOST_IP>:9113")'
```

#### 4. Cleanup

```bash
rm /usr/local/bin/nginx-prometheus-exporter.backup
rm -rf /tmp/nginx-prometheus-exporter*
echo "Nginx Exporter update completed"
```

---

### Update MySQL Exporter (0.15.1 → 0.18.0)

**Note:** Already using .my.cnf configuration, so no config migration needed.

#### 1. Pre-Update Validation

```bash
# Check current version
/usr/local/bin/mysqld_exporter --version

# Verify service
systemctl status mysqld_exporter

# Test metrics
curl -s http://localhost:9104/metrics | grep mysql_up

# Verify database connectivity
mysql -u exporter -p < /dev/null  # Test using exporter credentials
```

#### 2. Download and Verify

```bash
# Set version
VERSION="0.18.0"
cd /tmp

# Download
wget https://github.com/prometheus/mysqld_exporter/releases/download/v${VERSION}/mysqld_exporter-${VERSION}.linux-amd64.tar.gz

# Download checksum
wget https://github.com/prometheus/mysqld_exporter/releases/download/v${VERSION}/sha256sums.txt

# Verify
sha256sum -c sha256sums.txt --ignore-missing
```

#### 3. Install

```bash
# Extract
tar xzf mysqld_exporter-${VERSION}.linux-amd64.tar.gz

# Stop service
systemctl stop mysqld_exporter

# Backup and install
cp /usr/local/bin/mysqld_exporter /usr/local/bin/mysqld_exporter.backup
cp mysqld_exporter-${VERSION}.linux-amd64/mysqld_exporter /usr/local/bin/mysqld_exporter
chown mysqld_exporter:mysqld_exporter /usr/local/bin/mysqld_exporter
chmod 755 /usr/local/bin/mysqld_exporter

# Verify configuration file still exists
cat /etc/mysqld_exporter/.my.cnf

# Start service
systemctl start mysqld_exporter
```

#### 4. Post-Update Validation

```bash
# Verify service
systemctl status mysqld_exporter

# Check metrics
curl -s http://localhost:9104/metrics | grep -E "mysql_up|mysql_global_status_queries"

# Verify new features (RocksDB metrics if applicable)
curl -s http://localhost:9104/metrics | grep rocksdb || echo "RocksDB not enabled (expected if not using RocksDB)"

# Check logs for errors
journalctl -u mysqld_exporter -n 50 --no-pager
```

#### 5. Cleanup

```bash
rm /usr/local/bin/mysqld_exporter.backup
rm -rf /tmp/mysqld_exporter-*
echo "MySQL Exporter update completed"
```

---

### Batch Update Script for All Exporters

For updating all exporters on a single host:

```bash
#!/bin/bash
# update-exporters.sh - Update all exporters on current host

set -euo pipefail

BACKUP_DIR="/var/backups/exporters-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "=== Updating Exporters ==="
echo "Backup directory: $BACKUP_DIR"

# Function to update exporter
update_exporter() {
    local exporter_name=$1
    local version=$2
    local download_url=$3
    local binary_path=$4

    echo ""
    echo "=== Updating $exporter_name to v$version ==="

    # Backup
    if [[ -f "$binary_path" ]]; then
        cp "$binary_path" "$BACKUP_DIR/$(basename $binary_path).backup"
        echo "Backed up to $BACKUP_DIR"
    fi

    # Download, install, restart
    # (Implementation would go here)

    echo "$exporter_name update completed"
}

# Update each exporter
update_exporter "node_exporter" "1.9.1" "https://github.com/..." "/usr/local/bin/node_exporter"
update_exporter "nginx_exporter" "1.5.1" "https://github.com/..." "/usr/local/bin/nginx-prometheus-exporter"
update_exporter "mysqld_exporter" "0.18.0" "https://github.com/..." "/usr/local/bin/mysqld_exporter"

echo ""
echo "=== All exporters updated successfully ==="
echo "Backups available at: $BACKUP_DIR"
```

---

## Prometheus Update (High Risk)

### Timeline: 4-6 hours (includes both upgrade stages)
### Risk Level: HIGH
### Rollback: Limited (only to v2.55.1)

### Two-Stage Upgrade Path

```
v2.48.1 → v2.55.1 (Stage 1) → v3.8.1 (Stage 2)
```

**CRITICAL:** Must upgrade through v2.55.1 as intermediate step due to TSDB format changes.

---

### Stage 1: Prometheus 2.48.1 → 2.55.1

#### 1. Pre-Update Validation

```bash
# Check current version
/usr/local/bin/prometheus --version

# Verify service
systemctl status prometheus

# Check TSDB status
promtool tsdb analyze /var/lib/prometheus

# Capture current targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
curl -s http://localhost:9090/api/v1/targets > /tmp/prometheus_targets_before.json

# Test sample queries
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'

# Document current resource usage
free -h > /tmp/prometheus_resources_before.txt
df -h /var/lib/prometheus >> /tmp/prometheus_resources_before.txt
```

#### 2. Create Comprehensive Backup

```bash
# Stop Prometheus
systemctl stop prometheus

# Create backup
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/prometheus-pre-2.55-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

# Backup everything
cp -r /var/lib/prometheus "$BACKUP_DIR/data"
cp /etc/prometheus/prometheus.yml "$BACKUP_DIR/prometheus.yml"
cp -r /etc/prometheus/rules "$BACKUP_DIR/rules"
cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus.bin"
/usr/local/bin/prometheus --version > "$BACKUP_DIR/VERSION.txt"

# Create restore script
cat > "$BACKUP_DIR/restore.sh" << 'EOF'
#!/bin/bash
echo "Restoring Prometheus 2.48.1..."
systemctl stop prometheus
cp -r data/* /var/lib/prometheus/
cp prometheus.yml /etc/prometheus/
cp -r rules/* /etc/prometheus/rules/
cp prometheus.bin /usr/local/bin/prometheus
chown -R prometheus:prometheus /var/lib/prometheus
systemctl start prometheus
echo "Restore completed"
EOF
chmod +x "$BACKUP_DIR/restore.sh"

echo "Backup completed: $BACKUP_DIR"

# Restart Prometheus before upgrade
systemctl start prometheus
sleep 5
```

#### 3. Download Prometheus 2.55.1

```bash
VERSION="2.55.1"
cd /tmp

# Download
wget https://github.com/prometheus/prometheus/releases/download/v${VERSION}/prometheus-${VERSION}.linux-amd64.tar.gz

# Download checksum
wget https://github.com/prometheus/prometheus/releases/download/v${VERSION}/sha256sums.txt

# Verify
sha256sum -c sha256sums.txt --ignore-missing
```

#### 4. Validate Configuration

```bash
# Extract to temp location
tar xzf prometheus-${VERSION}.linux-amd64.tar.gz

# Validate config with new version
./prometheus-${VERSION}.linux-amd64/promtool check config /etc/prometheus/prometheus.yml

# Validate rules
./prometheus-${VERSION}.linux-amd64/promtool check rules /etc/prometheus/rules/*.yml
```

#### 5. Install Prometheus 2.55.1

```bash
# Stop Prometheus
systemctl stop prometheus

# Wait for clean shutdown
sleep 5

# Install new binary
cp prometheus-${VERSION}.linux-amd64/prometheus /usr/local/bin/prometheus
cp prometheus-${VERSION}.linux-amd64/promtool /usr/local/bin/promtool

# Set permissions
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify version
/usr/local/bin/prometheus --version
```

#### 6. Start and Validate

```bash
# Start Prometheus
systemctl start prometheus

# Monitor startup
journalctl -u prometheus -f
# Press Ctrl+C after seeing "Server is ready to receive web requests"

# Wait for full startup
sleep 10

# Check status
systemctl status prometheus

# Verify targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'

# Test query
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[0]'

# Check TSDB
promtool tsdb analyze /var/lib/prometheus
```

#### 7. Validation Period

**IMPORTANT:** Run Prometheus 2.55.1 for at least 24-48 hours before upgrading to 3.8.1.

```bash
# Monitor for issues
# - Check logs: journalctl -u prometheus -f
# - Check targets: curl http://localhost:9090/api/v1/targets
# - Check rules: curl http://localhost:9090/api/v1/rules
# - Monitor resource usage: top, free -h, df -h
# - Test dashboards in Grafana
# - Verify alerts are firing correctly
```

#### 8. Validation Checklist

- [ ] Prometheus 2.55.1 running successfully for 24-48 hours
- [ ] All targets showing as UP
- [ ] All alert rules evaluating correctly
- [ ] Dashboards displaying data correctly
- [ ] No errors in logs
- [ ] Resource usage within normal limits
- [ ] TSDB healthy (promtool tsdb analyze shows no issues)
- [ ] Queries returning expected results

**Only proceed to Stage 2 after all checks pass.**

---

### Stage 2: Prometheus 2.55.1 → 3.8.1

**CRITICAL:** This is a one-way upgrade. After this, you can only rollback to v2.55.1, not to v2.48.1.

#### 1. Pre-Update Validation

```bash
# Verify current version is 2.55.1
/usr/local/bin/prometheus --version | grep "2.55.1"

# Verify TSDB health
promtool tsdb analyze /var/lib/prometheus

# Create pre-3.x backup
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/prometheus-pre-3.x-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

systemctl stop prometheus
cp -r /var/lib/prometheus "$BACKUP_DIR/data"
cp /etc/prometheus/prometheus.yml "$BACKUP_DIR/prometheus.yml"
cp -r /etc/prometheus/rules "$BACKUP_DIR/rules"
cp /usr/local/bin/prometheus "$BACKUP_DIR/prometheus.bin"
/usr/local/bin/prometheus --version > "$BACKUP_DIR/VERSION.txt"
systemctl start prometheus
sleep 5

echo "Backup completed: $BACKUP_DIR"
```

#### 2. Download Prometheus 3.8.1

```bash
VERSION="3.8.1"
cd /tmp

# Download
wget https://github.com/prometheus/prometheus/releases/download/v${VERSION}/prometheus-${VERSION}.linux-amd64.tar.gz

# Download checksum
wget https://github.com/prometheus/prometheus/releases/download/v${VERSION}/sha256sums.txt

# Verify
sha256sum -c sha256sums.txt --ignore-missing
```

#### 3. Review Migration Guide

```bash
# Download and review migration guide
curl -s https://prometheus.io/docs/prometheus/latest/migration/ | less

# Key things to check:
# - Feature flag changes
# - Configuration format changes
# - PromQL changes
# - API changes
```

#### 4. Validate Configuration for v3

```bash
# Extract
tar xzf prometheus-${VERSION}.linux-amd64.tar.gz

# Validate config
./prometheus-${VERSION}.linux-amd64/promtool check config /etc/prometheus/prometheus.yml

# If validation fails, update configuration before proceeding
# Common issues:
# - Deprecated feature flags
# - Configuration syntax changes
```

#### 5. Update Configuration (If Needed)

Example configuration updates:

```bash
# Backup original config
cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.backup

# Edit configuration to remove deprecated options
nano /etc/prometheus/prometheus.yml

# Re-validate
./prometheus-${VERSION}.linux-amd64/promtool check config /etc/prometheus/prometheus.yml
```

#### 6. Install Prometheus 3.8.1

```bash
# Stop Prometheus
systemctl stop prometheus

# Wait for clean shutdown
sleep 10

# Install new binaries
cp prometheus-${VERSION}.linux-amd64/prometheus /usr/local/bin/prometheus
cp prometheus-${VERSION}.linux-amd64/promtool /usr/local/bin/promtool

# Set permissions
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify version
/usr/local/bin/prometheus --version
```

#### 7. Start and Monitor

```bash
# Start Prometheus
systemctl start prometheus

# Monitor startup closely
journalctl -u prometheus -f

# Watch for:
# - TSDB migration messages
# - Configuration loading
# - "Server is ready to receive web requests"
# - Any ERROR or WARN messages
```

#### 8. Comprehensive Validation

```bash
# Wait for full startup (may take longer due to TSDB migration)
sleep 30

# Check status
systemctl status prometheus

# Verify web UI is accessible
curl -s http://localhost:9090/-/healthy

# Check targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Test queries
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq .

# Check rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | {name: .name, state: .state}'

# Verify TSDB
promtool tsdb analyze /var/lib/prometheus

# Check for errors in logs
journalctl -u prometheus -n 100 --no-pager | grep -i error
```

#### 9. Extended Validation (24 hours)

```bash
# Monitor continuously for 24 hours:

# 1. Resource usage
watch -n 60 'free -h; df -h /var/lib/prometheus'

# 2. Target health
watch -n 300 'curl -s http://localhost:9090/api/v1/targets | jq ".data.activeTargets | map(select(.health != \"up\")) | length"'

# 3. Query performance
# Run test queries and compare latency with v2.55.1 baseline

# 4. Check logs
journalctl -u prometheus -f
```

#### 10. Post-Update Checklist

- [ ] Prometheus 3.8.1 running for 24+ hours without issues
- [ ] All targets UP and scraping successfully
- [ ] All alert rules evaluating correctly
- [ ] All dashboards displaying correctly
- [ ] Query performance acceptable (within 10-15% of baseline)
- [ ] No errors in logs
- [ ] TSDB healthy
- [ ] Resource usage within expected limits
- [ ] Backups verified and tested

#### 11. Rollback to 2.55.1 (If Needed)

**Only possible to rollback to v2.55.1, not earlier versions.**

```bash
# Stop Prometheus
systemctl stop prometheus

# Find latest v2.55.1 backup
BACKUP_DIR="/var/backups/observability-stack/prometheus-pre-3.x-<TIMESTAMP>"

# Restore binary
cp "$BACKUP_DIR/prometheus.bin" /usr/local/bin/prometheus

# TSDB data is compatible, no need to restore
# Configuration rollback if changed
cp "$BACKUP_DIR/prometheus.yml" /etc/prometheus/prometheus.yml

# Start Prometheus
systemctl start prometheus

# Verify
/usr/local/bin/prometheus --version
systemctl status prometheus
```

#### 12. Cleanup (If Successful)

```bash
# Remove download files
rm -rf /tmp/prometheus-* /tmp/sha256sums.txt

# Keep backups for 30 days
echo "Prometheus 3.8.1 upgrade completed successfully"
echo "Backups retained at: /var/backups/observability-stack/"
```

---

## Loki + Promtail Update (Medium Risk)

### Timeline: 2-3 hours
### Risk Level: MEDIUM
### Rollback: Full rollback possible

### Strategy: Update Loki first, then Promtail on all hosts

---

### Part 1: Update Loki (2.9.3 → 3.6.3)

#### 1. Pre-Update Validation

```bash
# Check current version
/usr/local/bin/loki --version

# Verify service
systemctl status loki

# Test API
curl -s http://localhost:3100/ready

# Test log query
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={job="varlogs"}&limit=10' | jq .

# Capture current ingestion rate
curl -s http://localhost:3100/metrics | grep loki_distributor_bytes_received_total
```

#### 2. Create Backup

```bash
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/var/backups/observability-stack/loki-${BACKUP_DATE}"
mkdir -p "$BACKUP_DIR"

systemctl stop loki

# Backup data
cp -r /var/lib/loki "$BACKUP_DIR/data"

# Backup config
cp /etc/loki/loki-config.yaml "$BACKUP_DIR/loki-config.yaml"

# Backup binary
cp /usr/local/bin/loki "$BACKUP_DIR/loki.bin"
/usr/local/bin/loki --version > "$BACKUP_DIR/VERSION.txt"

systemctl start loki
sleep 5

echo "Backup completed: $BACKUP_DIR"
```

#### 3. Download Loki 3.6.3

```bash
VERSION="3.6.3"
cd /tmp

# Download
wget https://github.com/grafana/loki/releases/download/v${VERSION}/loki-linux-amd64.zip

# Extract
unzip loki-linux-amd64.zip
```

#### 4. Validate Configuration

```bash
# Check if config is compatible with v3
./loki-linux-amd64 -config.file=/etc/loki/loki-config.yaml -verify-config

# If validation passes, proceed
```

#### 5. Install Loki 3.6.3

```bash
# Stop Loki
systemctl stop loki

# Install new binary
cp loki-linux-amd64 /usr/local/bin/loki
chown loki:loki /usr/local/bin/loki
chmod 755 /usr/local/bin/loki

# Verify version
/usr/local/bin/loki --version
```

#### 6. Start and Validate

```bash
# Start Loki
systemctl start loki

# Monitor startup
journalctl -u loki -f
# Press Ctrl+C after "Loki started"

# Check status
systemctl status loki

# Verify ready
curl -s http://localhost:3100/ready

# Test query
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={job="varlogs"}&limit=10' | jq .

# Check metrics
curl -s http://localhost:3100/metrics | grep loki_distributor
```

#### 7. Post-Update Validation

- [ ] Loki service running
- [ ] API responding to queries
- [ ] Historical logs still accessible
- [ ] New logs being ingested (check from Promtail)
- [ ] Grafana can query Loki
- [ ] No errors in logs

#### 8. Rollback (If Needed)

```bash
systemctl stop loki
BACKUP_DIR="/var/backups/observability-stack/loki-<TIMESTAMP>"
cp "$BACKUP_DIR/loki.bin" /usr/local/bin/loki
systemctl start loki
```

---

### Part 2: Update Promtail (2.9.3 → 3.6.3)

**Run on each monitored host.**

#### 1. Pre-Update Validation

```bash
# Check current version
/usr/local/bin/promtail --version

# Verify service
systemctl status promtail

# Check if logs are being sent
journalctl -u promtail -n 50 --no-pager | grep -i "sent"

# Verify from Loki (on observability VPS)
# curl 'http://localhost:3100/loki/api/v1/query?query={instance="<HOST_IP>"}' | jq .
```

#### 2. Create Backup

```bash
BACKUP_DIR="/var/backups/promtail-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

systemctl stop promtail

cp /usr/local/bin/promtail-linux-amd64 "$BACKUP_DIR/" 2>/dev/null || cp /usr/local/bin/promtail "$BACKUP_DIR/"
cp /etc/promtail/promtail.yaml "$BACKUP_DIR/"
cp /etc/systemd/system/promtail.service "$BACKUP_DIR/"

systemctl start promtail

echo "Backup: $BACKUP_DIR"
```

#### 3. Download Promtail 3.6.3

```bash
VERSION="3.6.3"
cd /tmp

# Download
wget https://github.com/grafana/loki/releases/download/v${VERSION}/promtail-linux-amd64.zip

# Extract
unzip promtail-linux-amd64.zip
```

#### 4. Install Promtail 3.6.3

```bash
# Stop Promtail
systemctl stop promtail

# Install
cp promtail-linux-amd64 /usr/local/bin/promtail
chown promtail:promtail /usr/local/bin/promtail
chmod 755 /usr/local/bin/promtail

# Verify
/usr/local/bin/promtail --version
```

#### 5. Start and Validate

```bash
# Start
systemctl start promtail

# Check status
systemctl status promtail

# Verify logs are being sent
journalctl -u promtail -f
# Look for "POST /loki/api/v1/push" messages

# Verify from Loki (on observability VPS)
# curl 'http://localhost:3100/loki/api/v1/query?query={instance="<HOST_IP>"}' | jq .
```

#### 6. Repeat for All Hosts

Update Promtail on all monitored hosts using the same procedure.

---

## Validation Procedures

### Comprehensive System Validation

After all updates are complete, run comprehensive validation:

#### 1. Prometheus Validation

```bash
# Targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}' | grep -v '"health": "up"'
# Should return empty (all targets UP)

# Rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.state != "inactive") | {name: .name, state: .state}'

# Query performance test
time curl -s 'http://localhost:9090/api/v1/query?query=up'

# TSDB stats
promtool tsdb analyze /var/lib/prometheus
```

#### 2. Loki Validation

```bash
# Health
curl -s http://localhost:3100/ready

# Query test
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq .

# Ingestion rate
curl -s http://localhost:3100/metrics | grep loki_distributor_bytes_received_total | tail -5

# Query from Grafana Explore
# Navigate to Grafana → Explore → Select Loki → Run query: {job="varlogs"}
```

#### 3. Grafana Validation

```bash
# Service status
systemctl status grafana-server

# Test datasources
curl -s -u admin:PASSWORD http://localhost:3000/api/datasources | jq '.[] | {name: .name, type: .type}'

# Test dashboards load
curl -s -u admin:PASSWORD http://localhost:3000/api/dashboards/home | jq .
```

#### 4. Exporter Validation

For each host, run:

```bash
# Node Exporter
curl -s http://<HOST_IP>:9100/metrics | grep node_exporter_build_info

# Nginx Exporter
curl -s http://<HOST_IP>:9113/metrics | grep nginx_up

# MySQL Exporter
curl -s http://<HOST_IP>:9104/metrics | grep mysql_up

# PHP-FPM Exporter
curl -s http://<HOST_IP>:9253/metrics | grep phpfpm_up

# Fail2ban Exporter
curl -s http://<HOST_IP>:9191/metrics | grep fail2ban_up
```

#### 5. End-to-End Validation

```bash
# 1. Generate test metrics
# On a monitored host, create CPU load
stress --cpu 2 --timeout 60s

# 2. Verify metrics appear in Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=node_load1{instance="<HOST_IP>:9100"}' | jq .

# 3. Verify alert fires (if configured)
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="HighCPU")'

# 4. Verify dashboard updates
# Check Grafana dashboard for the host

# 5. Generate test logs
logger -t test "Test log entry after update"

# 6. Verify logs in Loki
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={syslog_identifier="test"}&limit=5' | jq .
```

---

## Rollback Procedures

### Rollback Decision Matrix

| Situation | Rollback to | Data Loss? | Procedure |
|-----------|-------------|------------|-----------|
| Prometheus 3.8.1 has issues | 2.55.1 | No | Binary rollback |
| Prometheus 2.55.1 has issues | 2.48.1 | Yes (metrics since upgrade) | Full restore |
| Loki 3.6.3 has issues | 2.9.3 | No | Binary + config rollback |
| Promtail 3.6.3 has issues | 2.9.3 | No | Binary rollback |
| Exporter has issues | Previous version | No | Binary rollback |

### Emergency Rollback: Prometheus 3.x → 2.55.1

```bash
#!/bin/bash
# emergency-rollback-prometheus.sh

set -euo pipefail

echo "=== EMERGENCY ROLLBACK: Prometheus 3.x → 2.55.1 ==="

# Stop Prometheus
systemctl stop prometheus

# Find latest pre-3.x backup
BACKUP_DIR=$(ls -td /var/backups/observability-stack/prometheus-pre-3.x-* | head -1)
echo "Using backup: $BACKUP_DIR"

# Restore binary
cp "$BACKUP_DIR/prometheus.bin" /usr/local/bin/prometheus

# Restore configuration if changed
cp "$BACKUP_DIR/prometheus.yml" /etc/prometheus/prometheus.yml

# Start Prometheus
systemctl start prometheus

# Verify
sleep 10
systemctl status prometheus

echo "=== Rollback completed ==="
echo "Version: $(/usr/local/bin/prometheus --version)"
```

### Emergency Rollback: Full Stack

```bash
#!/bin/bash
# emergency-rollback-full.sh

set -euo pipefail

echo "=== EMERGENCY FULL STACK ROLLBACK ==="

# Find latest backups
PROM_BACKUP=$(ls -td /var/backups/observability-stack/prometheus-pre-* | head -1)
LOKI_BACKUP=$(ls -td /var/backups/observability-stack/loki-* | head -1)

echo "Prometheus backup: $PROM_BACKUP"
echo "Loki backup: $LOKI_BACKUP"

# Stop all services
systemctl stop prometheus loki grafana-server alertmanager

# Rollback Prometheus
cp "$PROM_BACKUP/prometheus.bin" /usr/local/bin/prometheus
cp "$PROM_BACKUP/prometheus.yml" /etc/prometheus/prometheus.yml
cp -r "$PROM_BACKUP/rules/"* /etc/prometheus/rules/

# Rollback Loki
cp "$LOKI_BACKUP/loki.bin" /usr/local/bin/loki
cp "$LOKI_BACKUP/loki-config.yaml" /etc/loki/loki-config.yaml

# Start services
systemctl start prometheus loki grafana-server alertmanager

# Verify
sleep 15
systemctl status prometheus loki grafana-server alertmanager

echo "=== Full rollback completed ==="
```

---

## Troubleshooting

### Prometheus Issues

#### Issue: Prometheus won't start after upgrade

```bash
# Check logs
journalctl -u prometheus -n 100 --no-pager

# Common causes:
# 1. Configuration error
promtool check config /etc/prometheus/prometheus.yml

# 2. TSDB corruption
promtool tsdb analyze /var/lib/prometheus

# 3. Permission issues
ls -la /var/lib/prometheus
chown -R prometheus:prometheus /var/lib/prometheus

# 4. Port already in use
lsof -i :9090
```

#### Issue: High memory usage after upgrade

```bash
# Check TSDB stats
promtool tsdb analyze /var/lib/prometheus

# Verify retention settings
grep retention /etc/prometheus/prometheus.yml

# Check for metric explosion
curl -s 'http://localhost:9090/api/v1/query?query=count({__name__=~".+"})' | jq .

# If needed, reduce retention temporarily
# Edit /etc/prometheus/prometheus.yml
# --storage.tsdb.retention.time=15d → 7d
systemctl restart prometheus
```

#### Issue: Queries are slow

```bash
# Check query performance
time curl -s 'http://localhost:9090/api/v1/query?query=up'

# Check TSDB compaction
ls -lh /var/lib/prometheus/01*

# Force compaction
promtool tsdb create-blocks-from rules \
    --output-dir=/tmp/compacted \
    /var/lib/prometheus

# Check for high cardinality
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | jq -r '.data[]' | wc -l
```

### Loki Issues

#### Issue: Loki won't start

```bash
# Check logs
journalctl -u loki -n 100 --no-pager

# Validate config
/usr/local/bin/loki -config.file=/etc/loki/loki-config.yaml -verify-config

# Check permissions
ls -la /var/lib/loki
chown -R loki:loki /var/lib/loki

# Check port
lsof -i :3100
```

#### Issue: Logs not appearing

```bash
# Check Promtail is sending logs
# On monitored host:
journalctl -u promtail -f | grep "POST /loki/api/v1/push"

# Check Loki ingestion
curl -s http://localhost:3100/metrics | grep loki_distributor_bytes_received_total

# Query recent logs
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={job="varlogs"}&limit=10' | jq .

# Check for errors
journalctl -u loki | grep -i error
```

### Exporter Issues

#### Issue: Exporter metrics not scraped

```bash
# Check if exporter is running
systemctl status <exporter>

# Test metrics endpoint locally
curl http://localhost:<PORT>/metrics

# Check from Prometheus server
curl http://<HOST_IP>:<PORT>/metrics

# Check firewall
ufw status | grep <PORT>

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.instance=="<HOST_IP>:<PORT>")'
```

#### Issue: mysql_up shows 0

```bash
# Check credentials
cat /etc/mysqld_exporter/.my.cnf

# Test MySQL connection
mysql -u exporter -p < /dev/null

# Check exporter logs
journalctl -u mysqld_exporter -n 50

# Verify grants
mysql -e "SHOW GRANTS FOR 'exporter'@'localhost';"
```

---

## Post-Update Tasks

### 1. Update Documentation

```bash
# Update version numbers in documentation
sed -i 's/Prometheus: 2.48.1/Prometheus: 3.8.1/g' README.md
sed -i 's/Loki: 2.9.3/Loki: 3.6.3/g' README.md
# ... etc for all components
```

### 2. Update Module Manifests

```bash
# Update version in each module.yaml
vim modules/_core/node_exporter/module.yaml
# Change: version: "1.7.0" → version: "1.9.1"

# Repeat for all modules
```

### 3. Create Change Log Entry

```bash
cat >> CHANGELOG.md << EOF

## [3.1.0] - $(date +%Y-%m-%d)

### Updated
- Prometheus: 2.48.1 → 3.8.1
- Loki: 2.9.3 → 3.6.3
- Promtail: 2.9.3 → 3.6.3
- Node Exporter: 1.7.0 → 1.9.1
- Nginx Exporter: 1.1.0 → 1.5.1
- MySQL Exporter: 0.15.1 → 0.18.0

### Notes
- Prometheus upgrade completed via 2.55.1 intermediate version
- TSDB format upgraded to v3 (rollback limited to v2.55.1)
- All exporters updated to latest stable versions
- No breaking changes to dashboards or alert rules

EOF
```

### 4. Notify Stakeholders

```bash
# Send notification email
cat > /tmp/update-notification.txt << EOF
Subject: Observability Stack Updated - All Components

The observability stack has been successfully updated to the latest versions:

Core Components:
- Prometheus: 3.8.1 (major upgrade)
- Loki: 3.6.3
- Promtail: 3.6.3

Exporters:
- Node Exporter: 1.9.1
- Nginx Exporter: 1.5.1
- MySQL Exporter: 0.18.0

All services are running normally. Dashboards and alerts are functioning as expected.

Downtime: ~15 minutes total
Issues: None reported

Backups available at: /var/backups/observability-stack/

For questions, contact DevOps team.
EOF

# Send email (configure mail command first)
# mail -s "Observability Stack Update Complete" team@example.com < /tmp/update-notification.txt
```

### 5. Clean Up Old Backups

```bash
# Keep backups for 30 days, then remove
find /var/backups/observability-stack -type d -mtime +30 -exec rm -rf {} \;

# Or archive to S3/backup storage
# aws s3 sync /var/backups/observability-stack s3://backups/observability-stack/
```

---

## Summary Checklist

### Pre-Update
- [ ] Read VERSION_UPDATE_SAFETY_REPORT.md
- [ ] Schedule maintenance window
- [ ] Notify stakeholders
- [ ] Create all backups
- [ ] Test rollback procedures
- [ ] Capture baseline metrics

### During Update
- [ ] Update exporters (low risk)
- [ ] Update Prometheus (2-stage: 2.48→2.55→3.8)
- [ ] Update Loki
- [ ] Update Promtail on all hosts
- [ ] Validate each component after update

### Post-Update
- [ ] Run comprehensive validation
- [ ] Monitor for 24-48 hours
- [ ] Update documentation
- [ ] Notify stakeholders of completion
- [ ] Archive backups
- [ ] Update module manifests
- [ ] Create changelog entry

---

**Document Version:** 1.0
**Last Updated:** 2025-12-27
**Next Review:** After all updates completed
